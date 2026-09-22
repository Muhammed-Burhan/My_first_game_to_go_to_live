extends Node
## Run state: mode, rock, lives, wave, speed, timing, kill streak.
## Emits signals the HUD listens to. Pure state + rules. No nodes, no drawing.

signal rock_changed(value: int)
signal lives_changed(value: int, delta: int)
signal wave_changed(value: int)
signal speed_changed(value: float)
signal combo_changed(count: int)
signal paused_changed(value: bool)
signal run_started
signal run_ended(result: Dictionary)

var mode: int = Config.Mode.CAMPAIGN
var rock: int = 0
var lives: int = 0
var max_lives: int = 3
var wave: int = 0            # 0 = before first wave; 1..N during play
var waves_cleared: int = 0
var rock_earned: int = 0
var kills: int = 0
var speed: float = 1.0
var run_time: float = 0.0    # game seconds at 1x (not scaled by the speed toggle)
var running: bool = false
var paused: bool = false
var won: bool = false
var booth_mode: bool = false
var sim_mode: bool = false
var last_result: Dictionary = {}
var run_seed: int = 0        # 0 = the authored campaign map
## Fixed draft seed for --sim runs. Override with --boonseed=N to sweep.
var sim_boon_seed: int = 1258
var daily_index: int = 0

var combo: int = 0
var best_combo: int = 0
## Whether the player pulled the repeater's trigger during the current wave.
var _fired_this_wave: bool = false
var repairs: int = 0
var _combo_timer: float = 0.0


func _ready() -> void:
	_read_launch_flags()


func _read_launch_flags() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--booth":
			booth_mode = true
		if a == "--sim":
			sim_mode = true
		if a == "--endless":
			mode = Config.Mode.FREE
		if a == "--daily":
			mode = Config.Mode.DAILY
		if a.begins_with("--boonseed="):
			sim_boon_seed = int(a.substr(11))
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("window.location.search", true)
		if q is String and (q as String).contains("mode=booth"):
			booth_mode = true
		if q is String and (q as String).contains("game=daily"):
			mode = Config.Mode.DAILY
		if q is String and (q as String).contains("game=free"):
			mode = Config.Mode.FREE


func mode_id() -> String:
	return str(Config.MODES[mode]["id"])


func is_endless() -> bool:
	return bool(Config.MODES[mode]["endless"])


func is_seeded() -> bool:
	return bool(Config.MODES[mode]["seeded"])


## Total waves in this mode, or -1 when there is no end.
func wave_total() -> int:
	return -1 if is_endless() else Config.WAVE_COUNT


func wave_label() -> String:
	if is_endless():
		return "WAVE %d" % maxi(wave, 1)
	return "WAVE %d/%d" % [maxi(wave, 1), Config.WAVE_COUNT]


func new_run(new_mode: int = -1) -> void:
	if new_mode >= 0:
		mode = new_mode
	daily_index = Config.daily_index()
	match mode:
		Config.Mode.DAILY:
			run_seed = Config.daily_seed()
		Config.Mode.FREE:
			run_seed = randi_range(100000, 9999999)
		_:
			run_seed = 0
	# The campaign has no map seed, so the boon draft would normally roll fresh
	# every run. That makes the balance bot non-reproducible: the same strategy
	# can clear wave 5 or wave 10 depending on what it was offered. Under --sim
	# the draft is pinned, so a number in the README is a number you can check.
	var boon_seed := run_seed
	if boon_seed == 0:
		boon_seed = sim_boon_seed if sim_mode else randi()
	Boons.reset(boon_seed)
	Meta.begin_run()
	var m: Dictionary = Config.MODES[mode]
	rock = int(m["rock"])
	lives = int(m["lives"])
	# The commander is chosen before the run and sits underneath every boon
	# drafted later, so it is folded in here, before the first wave.
	var cmd := Meta.apply_commander()
	rock = maxi(0, rock + int(cmd.get("rock", 0)))
	lives = maxi(1, lives + int(cmd.get("lives", 0)))
	max_lives = lives
	if mode == Config.Mode.DAILY:
		Meta.track("daily_runs")
	wave = 0
	waves_cleared = 0
	rock_earned = 0
	kills = 0
	combo = 0
	_fired_this_wave = false
	best_combo = 0
	repairs = 0
	_combo_timer = 0.0
	run_time = 0.0
	running = true
	paused = false
	won = false
	last_result = {}
	rock_changed.emit(rock)
	lives_changed.emit(lives, 0)
	wave_changed.emit(wave)
	speed_changed.emit(speed)
	combo_changed.emit(0)
	run_started.emit()


func tick(delta: float) -> void:
	if not running:
		return
	run_time += delta
	if combo > 0:
		_combo_timer -= delta
		if _combo_timer <= 0.0:
			combo = 0
			combo_changed.emit(0)


## The commander pulled the trigger this wave; the "quiet" contract is off.
func note_commander_fired() -> void:
	_fired_this_wave = true


func register_kill() -> int:
	kills += 1
	combo += 1
	best_combo = maxi(best_combo, combo)
	_combo_timer = Config.COMBO_WINDOW
	combo_changed.emit(combo)
	Meta.track("kills")
	Meta.track("streak", combo, "max")
	return combo


func can_afford(cost: int) -> bool:
	return rock >= cost


func spend(cost: int) -> bool:
	if rock < cost:
		return false
	rock -= cost
	rock_changed.emit(rock)
	return true


func add_rock(amount: int, counts_as_earned: bool = true) -> void:
	rock += amount
	if counts_as_earned:
		rock_earned += amount
	rock_changed.emit(rock)


func lose_lives(n: int) -> void:
	if not running:
		return
	var before := lives
	lives = max(0, lives - n)
	lives_changed.emit(lives, lives - before)
	combo = 0
	combo_changed.emit(0)
	if lives <= 0:
		end_run(false)


func set_wave(w: int) -> void:
	wave = w
	wave_changed.emit(wave)


func wave_cleared() -> void:
	waves_cleared = wave
	Meta.track("waves")
	# "Flawless" and "quiet" are streaks, not totals: a wave that costs a life
	# or that the player shot their way through resets the count to zero.
	if lives >= max_lives:
		Meta.track("flawless_waves")
	else:
		Meta.run_stats["flawless_waves"] = 0
	if not _fired_this_wave:
		Meta.track("quiet_waves")
	else:
		Meta.run_stats["quiet_waves"] = 0
	_fired_this_wave = false
	add_rock(Boons.wave_bonus(Config.wave_clear_bonus(wave)))
	if not is_endless() and wave >= Config.WAVE_COUNT:
		end_run(true)


## Endless lets you buy a life back between waves, so a late run has something
## to spend a surplus on. Price climbs with the wave and with each repair bought.
func repair_cost() -> int:
	return int(150 + wave * 30 + repairs * 220)


func can_repair() -> bool:
	return is_endless() and running and lives < max_lives and can_afford(repair_cost())


func repair_gate() -> bool:
	if not can_repair():
		return false
	if not spend(repair_cost()):
		return false
	repairs += 1
	lives += 1
	lives_changed.emit(lives, 1)
	return true


## A boon handing the gate another breach to absorb, or taking one away.
func grant_lives(n: int) -> void:
	if n > 0:
		max_lives += n
		lives += n
	else:
		max_lives = maxi(1, max_lives + n)
		lives = maxi(1, lives + n)
	lives_changed.emit(lives, n)


func set_paused(p: bool) -> void:
	if paused == p:
		return
	paused = p
	paused_changed.emit(p)


func toggle_speed() -> void:
	speed = 2.0 if speed < 1.5 else 1.0
	speed_changed.emit(speed)


func end_run(did_win: bool) -> void:
	if not running:
		return
	running = false
	paused = false
	won = did_win
	var breakdown := Config.compute_score(rock_earned, lives, waves_cleared, run_time, won, mode, kills)
	last_result = {
		"won": won, "score": breakdown["total"], "breakdown": breakdown,
		"waves": waves_cleared, "lives": lives, "rock": rock_earned,
		"kills": kills, "duration": run_time, "best_combo": best_combo,
		"mode": mode, "mode_id": mode_id(), "seed": run_seed, "daily": daily_index,
		"boons": Boons.taken.duplicate(), "emoji": Boons.emoji_line(),
		"commander": Meta.commander,
	}
	if not sim_mode:
		last_result["new_best"] = Save.record_run(last_result)
		# Renown is paid after the profile records the run, so a new personal
		# best is already known and can be worth something.
		last_result["meta"] = Meta.end_run(last_result)
	run_ended.emit(last_result)
