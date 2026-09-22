class_name SimPlayer
extends Node
## Headless balance bot. Run with:
##   godot --headless --path . -- --sim --strategy=mixed --seed=1
## Plays the level with a simple strategy at high time scale, logs each wave,
## prints a SIM_RESULT json line and quits. Used to tune Config numbers.

var level: Level
var strategy: String = "mixed"
var _log: Array = []
var _lives_lost_this_wave := 0
var _wave_start_rock := 0
var _timeout := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--strategy="):
			strategy = a.substr(11)
		if a.begins_with("--seed="):
			seed(int(a.substr(7)))
	Engine.time_scale = 12.0
	Engine.max_fps = 0
	level.wave_started.connect(_on_wave_started)
	level.wave_cleared.connect(_on_wave_cleared)
	Game.lives_changed.connect(func(_v, d): if d < 0: _lives_lost_this_wave -= d)
	Game.run_ended.connect(_on_run_ended)
	Game.speed = 2.0


func _process(delta: float) -> void:
	_timeout += delta
	if _timeout > 600.0:
		print("SIM_RESULT " + JSON.stringify({"error": "timeout", "strategy": strategy, "log": _log}))
		get_tree().quit(2)
		return
	if not Game.running:
		return
	_act()
	if level.phase == "prep" and level.prep_left > 0.6:
		level.skip_prep()


## Rank empty slots by how much path they cover; prefer slots later on the path
## (closer to the gate) as a mild tie-break, since leaks happen at the top.
func _best_slot(range_px: float) -> Slot:
	var best: Slot = null
	var best_score := -1.0
	for s in level.slots:
		if s.tower != null:
			continue
		var cover := 0.0
		for p in level._path_points_cache:
			if p.distance_to(s.position) <= range_px:
				cover += 1.0
		var sc := cover + (1.0 - s.position.y / 1920.0) * 20.0
		sc -= level.dist_to_path(s.position) * 0.05
		if sc > best_score:
			best_score = sc
			best = s
	return best


func _act() -> void:
	var wave := level.next_wave if level.phase == "prep" else Game.wave
	var wanted := _wanted_type(wave)
	if wanted >= 0:
		var cost := Config.tower_cost(wanted, 1)
		if Game.can_afford(cost):
			var slot := _best_slot(Config.TOWERS[wanted]["range"])
			if slot != null:
				level.place_tower(slot, wanted)
				return
	# No slot or nothing wanted: upgrade. Informed play upgrades ballistas first
	# from wave 6 (armour is coming); otherwise the lowest-tier tower.
	var best: Tower = null
	var best_key := 999
	for s in level.slots:
		if s.tower == null or s.tower.tier >= Config.MAX_TIER:
			continue
		var key := s.tower.tier * 10
		if strategy == "mixed" and wave >= 6:
			var ttype: int = s.tower.type
			var heavy: bool = ttype == Config.TowerType.BALLISTA or ttype == Config.TowerType.MANGONEL or ttype == Config.TowerType.NAPHTHA
			key += 0 if heavy else 5
		if key < best_key:
			best_key = key
			best = s.tower
	if best != null and Game.can_afford(Config.tower_cost(best.type, best.tier + 1)):
		if _all_slots_full() or Game.rock > 200 or (strategy == "mixed" and wave >= 6):
			level.upgrade_tower(best)
			return
	# Everything affordable is already maxed: spend the surplus on empty slots.
	# Endless runs long enough that a hoarding bot is not a useful model.
	if not _all_slots_full() and Game.rock > 300:
		var fill := Config.TowerType.BALLISTA
		if _count(Config.TowerType.MANGONEL) < 2 and Game.rock > 600:
			fill = Config.TowerType.MANGONEL
		elif _count(Config.TowerType.NAPHTHA) < _count(Config.TowerType.BALLISTA):
			fill = Config.TowerType.NAPHTHA
		var slot2 := _best_slot(Config.TOWERS[fill]["range"])
		if slot2 != null:
			level.place_tower(slot2, fill)


func _all_slots_full() -> bool:
	for s in level.slots:
		if s.tower == null:
			return false
	return true


func _count(type: int) -> int:
	var n := 0
	for s in level.slots:
		if s.tower != null and s.tower.type == type:
			n += 1
	return n


## Which tower to buy next (-1 = save). Strategies model different players.
func _wanted_type(wave: int) -> int:
	var a := _count(Config.TowerType.ARCHER)
	var g := _count(Config.TowerType.GUARD)
	var o := _count(Config.TowerType.OIL)
	var nf := _count(Config.TowerType.NAPHTHA)
	var b := _count(Config.TowerType.BALLISTA)
	var mg := _count(Config.TowerType.MANGONEL)
	match strategy:
		"archers":
			return Config.TowerType.ARCHER
		"greedy":
			# Buys the most expensive thing affordable, in rotation.
			if Game.can_afford(210) and mg <= b:
				return Config.TowerType.MANGONEL
			if Game.can_afford(130) and b <= a:
				return Config.TowerType.BALLISTA
			if Game.can_afford(115) and nf < 2:
				return Config.TowerType.NAPHTHA
			if Game.can_afford(75) and o < a:
				return Config.TowerType.OIL
			return Config.TowerType.ARCHER
		"naive":
			# First-timer: archers, one guard post, a late ballista, no upkeep.
			if wave >= 3 and g < 1:
				return Config.TowerType.GUARD
			if wave >= 7 and b < 1:
				return Config.TowerType.BALLISTA
			return Config.TowerType.ARCHER
		_:
			# "mixed": a rounded line that uses the whole kit in roughly the order
			# the campaign teaches it.
			if a < 3:
				return Config.TowerType.ARCHER
			if g < 1:
				return Config.TowerType.GUARD
			if wave >= 3 and b < 1:
				return Config.TowerType.BALLISTA
			if wave >= 4 and o < 1:
				return Config.TowerType.OIL
			if wave >= 5 and nf < 1:
				return Config.TowerType.NAPHTHA
			if wave >= 5 and b < 2:
				return Config.TowerType.BALLISTA
			if wave >= 6 and g < 2:
				return Config.TowerType.GUARD
			if wave >= 7 and mg < 1:
				return Config.TowerType.MANGONEL
			if wave >= 8 and nf < 2:
				return Config.TowerType.NAPHTHA
			if wave >= 9 and b < 3:
				return Config.TowerType.BALLISTA
			if wave >= 10:
				return -1  # save for upgrades from here on
			if a < 5:
				return Config.TowerType.ARCHER
			if o < 2:
				return Config.TowerType.OIL
			return -1


func _on_wave_started(w: int) -> void:
	_lives_lost_this_wave = 0
	_wave_start_rock = Game.rock


func _on_wave_cleared(w: int) -> void:
	var towers := {}
	for s in level.slots:
		if s.tower != null:
			var key := "%s%d" % [Config.TOWERS[s.tower.type]["id"], s.tower.tier]
			towers[key] = towers.get(key, 0) + 1
	_log.append({"wave": w, "lives_lost": _lives_lost_this_wave, "rock_start": _wave_start_rock,
		"rock_end": Game.rock, "t": snappedf(Game.run_time, 0.1), "towers": towers})


func _on_run_ended(result: Dictionary) -> void:
	var out := result.duplicate()
	out["strategy"] = strategy
	out["slots"] = level.slots.size()
	out["log"] = _log
	out["lives_lost_final_wave"] = _lives_lost_this_wave
	print("SIM_RESULT " + JSON.stringify(out))
	await get_tree().process_frame
	get_tree().quit(0)
