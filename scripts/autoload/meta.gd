extends Node
## Everything that survives a run.
##
## The old build had nothing here: you played, you got a number, and the game
## was exactly the same the next time you opened it. Nothing had changed, so
## there was no reason for a second run. This file is that reason.
##
## Three layers, in the order the player feels them:
##
##   Contracts  Three objectives a day. Minutes to finish, and they pay renown,
##              so every run is pushing something visible.
##   Renown     Earned every run, win or lose. Feeds levels.
##   Unlocks    Levels hand over commanders, modes and new boons. This is the
##              drawer that fills up, and the reason a week-two player has a
##              different game in front of them than a day-one player.
##
## Booth mode opts out and unlocks everything: a stranger at a fair gets ninety
## seconds, and gating content behind a grind they will never do is just a
## worse demo.

signal renown_changed(total: int)
signal levelled_up(level: int, unlocks: Array)
signal contract_advanced(contract: Dictionary)
signal contract_completed(contract: Dictionary)

# ---------------------------------------------------------------- levels

## Front-loaded on purpose: the first two levels land inside a run or two, so
## the system announces itself before anyone decides the game has nothing more
## to show them. After that it stretches out.
const LEVEL_CAP := 12


static func renown_for_level(level_value: int) -> int:
	if level_value <= 1:
		return 0
	var n := level_value - 1
	# Linear + quadratic. The linear term keeps the first level about one run
	# away; the quadratic one stops the whole track falling out in a single
	# sitting. At 55 the cap is roughly twenty-odd good runs, which is a few
	# days of casual play rather than an afternoon.
	return 140 * n + 55 * (n * (n - 1)) / 2


static func level_for_renown(total: int) -> int:
	var lv := 1
	while lv < LEVEL_CAP and total >= renown_for_level(lv + 1):
		lv += 1
	return lv


# ---------------------------------------------------------------- commanders

## Picked before a run. Each is a different opening problem, not a straight
## power bump: every one of them gives something up. `mods` folds into the
## Boons table at run start, so commanders and boons share one system.
const COMMANDERS := [
	{
		# Deliberately empty. The Warden is the tuned baseline the balance sim
		# measures against, and the only commander with nothing to give up —
		# which is its own kind of pick once the others start costing lives.
		"id": "warden", "name": "Warden", "title": "Warden of the Gate", "level": 1,
		"blurb": "The siege as it was meant to be fought.",
		"cost": "No edge. No cost. Nothing to work around.",
		"art": "gate", "color": Color("c9a063"), "lives": 0, "rock": 0, "mods": {},
	},
	{
		"id": "quartermaster", "name": "Quartermaster", "title": "Quartermaster", "level": 2,
		"blurb": "Open the siege with 110 extra rock.",
		"cost": "Every kill pays 14% less.",
		"art": "coin", "color": Color("f2c14e"), "lives": 0, "rock": 110,
		"mods": {"rock_kill": -0.14},
	},
	{
		"id": "mason", "name": "Mason", "title": "Master Mason", "level": 4,
		"blurb": "Emplacements take 45% less damage, and repairs are free.",
		"cost": "Everything you build costs 12% more.",
		"art": "shield", "color": Color("7fb069"), "lives": 0, "rock": 0,
		"mods": {"tower_taken": -0.45, "repair_cost": -0.9, "build_cost": 0.12},
	},
	{
		"id": "zealot", "name": "Zealot", "title": "Zealot of the Wall", "level": 6,
		"blurb": "Your own repeater: +65% damage, +25% fire rate.",
		"cost": "The gate holds one breach fewer.",
		"art": "crit", "color": Color("d63a2f"), "lives": -1, "rock": 0,
		"mods": {"cmd_dmg": 0.65, "cmd_rate": 0.25},
	},
	{
		"id": "marshal", "name": "Marshal", "title": "Marshal of the Column", "level": 8,
		"blurb": "Guard posts field two more spearmen. Everything hits 15% harder.",
		"cost": "You open with 70 rock less.",
		"art": "spear", "color": Color("57a9e0"), "lives": 0, "rock": -70,
		"mods": {"garrison_extra": 2, "dmg_all": 0.15},
	},
	{
		"id": "naftgir", "name": "Naftgir", "title": "Keeper of the Naphtha", "level": 10,
		"blurb": "Every shot you own sets its target alight.",
		"cost": "The column climbs 12% faster.",
		"art": "fire", "color": Color("ff9a2e"), "lives": 0, "rock": 0,
		"mods": {"burn_all": 11.0, "burn_all_time": 2.5, "enemy_speed": 0.12},
	},
]

## Boons held back from the starting pool and handed over as the player levels.
## A day-one draft and a week-two draft should not look the same.
const BOON_UNLOCKS := {
	3: ["greek_fire", "barrage", "kings_purse"],
	5: ["marksmen", "salvage", "bulwark"],
	7: ["zagros_wind", "veterans", "hand_cannon"],
	9: ["blood_price", "scorched_earth", "greed", "thin_walls", "no_quarter"],
}

## Modes behind a level. Campaign is always open: it is the tutorial.
const MODE_UNLOCKS := {"daily": 2, "free": 4}


# ---------------------------------------------------------------- contracts

## `scope` is "run" for something that has to happen inside a single run, "day"
## for a counter that accumulates until midnight.
const CONTRACTS := [
	{"id": "hold8", "text": "Hold 8 waves in a single run", "stat": "waves", "scope": "run", "target": 8, "renown": 70},
	{"id": "hold14", "text": "Hold 14 waves in a single run", "stat": "waves", "scope": "run", "target": 14, "renown": 120},
	{"id": "kills200", "text": "Break 200 attackers today", "stat": "kills", "scope": "day", "target": 200, "renown": 60},
	{"id": "kills500", "text": "Break 500 attackers today", "stat": "kills", "scope": "day", "target": 500, "renown": 110},
	{"id": "burn60", "text": "Burn 60 attackers alive", "stat": "kills_fire", "scope": "day", "target": 60, "renown": 80},
	{"id": "streak15", "text": "Reach a x15 kill streak", "stat": "streak", "scope": "run", "target": 15, "renown": 70},
	{"id": "streak25", "text": "Reach a x25 kill streak", "stat": "streak", "scope": "run", "target": 25, "renown": 110},
	{"id": "build8", "text": "Raise 8 emplacements in one run", "stat": "builds", "scope": "run", "target": 8, "renown": 50},
	{"id": "siege6", "text": "Wreck 6 siege engines today", "stat": "kills_heavy", "scope": "day", "target": 6, "renown": 80},
	{"id": "flawless", "text": "Hold 5 waves without losing a life", "stat": "flawless_waves", "scope": "run", "target": 5, "renown": 90},
	{"id": "daily", "text": "Play today's Daily Siege", "stat": "daily_runs", "scope": "day", "target": 1, "renown": 50},
	{"id": "campaign_win", "text": "Break all ten campaign waves", "stat": "campaign_wins", "scope": "day", "target": 1, "renown": 100},
	{"id": "mangonel", "text": "Raise 3 mangonels in one run", "stat": "builds_mangonel", "scope": "run", "target": 3, "renown": 60},
	{"id": "quiet", "text": "Hold 6 waves without firing the repeater", "stat": "quiet_waves", "scope": "run", "target": 6, "renown": 80},
]

const CONTRACT_COUNT := 3

## Counters for the run in progress. Reset by `begin_run`.
var run_stats: Dictionary = {}
## The commander selected for the next run.
var commander: String = "warden"


func _ready() -> void:
	_ensure_profile()
	commander = str(Save.data.get("commander", "warden"))
	if not is_unlocked_commander(commander):
		commander = "warden"
	_roll_contracts_if_new_day()


# ---------------------------------------------------------------- profile

## The profile predates this file, so every key it needs is added on load
## rather than assumed. An old profile.json still opens.
func _ensure_profile() -> void:
	var d: Dictionary = Save.data
	if not d.has("renown"):
		d["renown"] = 0
	if not d.has("commander"):
		d["commander"] = "warden"
	if not d.has("contracts"):
		d["contracts"] = {"day": -1, "list": [], "day_stats": {}}


func renown() -> int:
	return int(Save.data.get("renown", 0))


func level() -> int:
	# The booth gets everything: a stranger at a fair has ninety seconds, and
	# gating content behind a grind they will never do is just a worse demo.
	# The balance sim gets everything too, so a run measured today and a run
	# measured next month are measuring the same game.
	if Game.booth_mode or Game.sim_mode:
		return LEVEL_CAP
	return level_for_renown(renown())


## Where the bar sits inside the current level.
func level_progress() -> Dictionary:
	var lv := level()
	if lv >= LEVEL_CAP:
		return {"level": lv, "have": 0, "need": 0, "frac": 1.0, "capped": true}
	var from := renown_for_level(lv)
	var to := renown_for_level(lv + 1)
	var have := renown() - from
	return {
		"level": lv, "have": have, "need": to - from,
		"frac": clampf(float(have) / maxf(float(to - from), 1.0), 0.0, 1.0), "capped": false,
	}


# ---------------------------------------------------------------- unlocks

func is_unlocked_commander(id: String) -> bool:
	for c in COMMANDERS:
		if c["id"] == id:
			return level() >= int(c["level"])
	return false


func commander_data(id: String = "") -> Dictionary:
	var want := id if id != "" else commander
	for c in COMMANDERS:
		if c["id"] == want:
			return c
	return COMMANDERS[0]


func set_commander(id: String) -> bool:
	if not is_unlocked_commander(id):
		return false
	commander = id
	Save.data["commander"] = id
	Save.save_profile()
	return true


func is_unlocked_mode(mode_id: String) -> bool:
	if not MODE_UNLOCKS.has(mode_id):
		return true
	return level() >= int(MODE_UNLOCKS[mode_id])


func mode_unlock_level(mode_id: String) -> int:
	return int(MODE_UNLOCKS.get(mode_id, 1))


## Boon ids the player has NOT earned yet, as a set the draft can skip.
func locked_boon_ids() -> Dictionary:
	var locked := {}
	var lv := level()
	for key in BOON_UNLOCKS.keys():
		if lv < int(key):
			for id in BOON_UNLOCKS[key]:
				locked[id] = true
	return locked


## Everything a given level hands over, for the reveal on the score screen.
func unlocks_at(lv: int) -> Array:
	var out: Array = []
	for c in COMMANDERS:
		if int(c["level"]) == lv:
			out.append({"kind": "COMMANDER", "name": str(c["title"]),
				"desc": str(c["blurb"]), "color": c["color"], "art": str(c["art"])})
	for mode_id in MODE_UNLOCKS.keys():
		if int(MODE_UNLOCKS[mode_id]) == lv:
			for m in Config.MODES.values():
				if str(m["id"]) == mode_id:
					out.append({"kind": "MODE", "name": str(m["name"]),
						"desc": str(m["tagline"]), "color": Config.C_ROCK, "art": "gate"})
	if BOON_UNLOCKS.has(lv):
		var ids: Array = BOON_UNLOCKS[lv]
		# Name them. "3 new boons" is a number; "Greek Fire, Barrage, King's
		# Purse" is a reason to play another run.
		var names: Array = []
		for id in ids:
			var b := Boons.by_id(str(id))
			if not b.is_empty():
				names.append(str(b["name"]))
		out.append({"kind": "DRAFT", "name": "%d NEW BOONS" % ids.size(),
			"desc": ", ".join(names), "color": Color("c07ae8"), "art": "star"})
	return out


## The next thing worth playing for. This is the line that does the work on the
## score screen: it is the answer to "why press play again".
func next_unlock() -> Dictionary:
	var lv := level()
	for want in range(lv + 1, LEVEL_CAP + 1):
		var items := unlocks_at(want)
		if not items.is_empty():
			return {
				"level": want, "at": renown_for_level(want),
				"remaining": maxi(renown_for_level(want) - renown(), 0), "items": items,
			}
	return {}


# ---------------------------------------------------------------- contracts

func _today() -> int:
	return Config.days_since_epoch()


func _roll_contracts_if_new_day() -> void:
	var c: Dictionary = Save.data["contracts"]
	if int(c.get("day", -1)) == _today():
		return
	# Seeded on the date, so everyone gets the same three today. That is worth
	# something socially even before the leaderboard is involved.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + _today() * 31337
	var pool: Array = CONTRACTS.duplicate()
	var list: Array = []
	for i in range(CONTRACT_COUNT):
		if pool.is_empty():
			break
		var pick: Dictionary = pool[rng.randi() % pool.size()]
		pool.erase(pick)
		list.append({"id": str(pick["id"]), "progress": 0, "done": false})
	c["day"] = _today()
	c["list"] = list
	c["day_stats"] = {}
	Save.save_profile()


func contract_def(id: String) -> Dictionary:
	for c in CONTRACTS:
		if c["id"] == id:
			return c
	return {}


## [{id, text, progress, target, renown, done}] for the UI.
func contracts() -> Array:
	_roll_contracts_if_new_day()
	var out: Array = []
	for entry in Save.data["contracts"]["list"]:
		var d := contract_def(str(entry["id"]))
		if d.is_empty():
			continue
		out.append({
			"id": str(entry["id"]), "text": str(d["text"]),
			"progress": mini(int(entry["progress"]), int(d["target"])),
			"target": int(d["target"]), "renown": int(d["renown"]), "done": bool(entry["done"]),
		})
	return out


func contracts_done() -> int:
	var n := 0
	for c in contracts():
		if bool(c["done"]):
			n += 1
	return n


# ---------------------------------------------------------------- run hooks

func begin_run() -> void:
	run_stats = {
		"waves": 0, "kills": 0, "kills_fire": 0, "kills_heavy": 0,
		"builds": 0, "builds_mangonel": 0, "streak": 0,
		"flawless_waves": 0, "quiet_waves": 0,
		"daily_runs": 0, "campaign_wins": 0,
	}
	_roll_contracts_if_new_day()


## Record progress on a tracked statistic. "max" is for best-of-run values like
## a kill streak; "add" is for counters.
func track(stat: String, value: int = 1, mode: String = "add") -> void:
	if Game.sim_mode or Game.booth_mode:
		return
	if not run_stats.has(stat):
		run_stats[stat] = 0
	if mode == "max":
		run_stats[stat] = maxi(int(run_stats[stat]), value)
	else:
		run_stats[stat] = int(run_stats[stat]) + value
	_refresh_contracts()


func _day_stats() -> Dictionary:
	var c: Dictionary = Save.data["contracts"]
	if not c.has("day_stats"):
		c["day_stats"] = {}
	return c["day_stats"]


func _stat_value(def: Dictionary) -> int:
	var stat := str(def["stat"])
	if str(def["scope"]) == "run":
		return int(run_stats.get(stat, 0))
	return int(_day_stats().get(stat, 0)) + int(run_stats.get(stat, 0))


## Recompute every open contract against the current counters. Completing one
## pays immediately: the reward should land while the player is still in the
## run that earned it, not two menus later.
func _refresh_contracts() -> void:
	var dirty := false
	for entry in Save.data["contracts"]["list"]:
		if bool(entry["done"]):
			continue
		var def := contract_def(str(entry["id"]))
		if def.is_empty():
			continue
		var value := _stat_value(def)
		if value == int(entry["progress"]):
			continue
		entry["progress"] = value
		dirty = true
		var payload := {
			"id": str(entry["id"]), "text": str(def["text"]), "progress": value,
			"target": int(def["target"]), "renown": int(def["renown"]),
		}
		if value >= int(def["target"]):
			entry["done"] = true
			add_renown(int(def["renown"]))
			contract_completed.emit(payload)
		else:
			contract_advanced.emit(payload)
	if dirty:
		Save.save_profile()


## Fold the run's counters into the day totals. Once, at run end.
func _commit_day_stats() -> void:
	var day := _day_stats()
	for k in run_stats.keys():
		if k == "streak":
			continue  # a best-of-run value does not accumulate across the day
		day[k] = int(day.get(k, 0)) + int(run_stats[k])


# ---------------------------------------------------------------- renown

func add_renown(amount: int) -> Dictionary:
	if amount <= 0 or Game.sim_mode or Game.booth_mode:
		return {"gained": 0, "levels": []}
	var before := level()
	Save.data["renown"] = renown() + amount
	Save.save_profile()
	renown_changed.emit(renown())
	var after := level()
	var gained: Array = []
	if after > before:
		for lv in range(before + 1, after + 1):
			gained.append(lv)
		levelled_up.emit(after, gained)
	return {"gained": amount, "levels": gained}


## What a finished run is worth. Depth dominates: the thing to have people
## chasing is one more wave, not one more minute of farming a cleared one.
func renown_for_run(result: Dictionary) -> Dictionary:
	var waves := int(result.get("waves", 0))
	var kills := int(result.get("kills", 0))
	var lines: Array = []
	var depth := waves * 14
	if depth > 0:
		lines.append(["Waves held", depth])
	var fight := int(kills / 4)
	if fight > 0:
		lines.append(["Attackers broken", fight])
	var bonus := 0
	if bool(result.get("won", false)):
		bonus += 60
		lines.append(["The gate held", 60])
	if bool(result.get("new_best", false)):
		bonus += 40
		lines.append(["New personal best", 40])
	if str(result.get("mode_id", "")) == "daily":
		bonus += 25
		lines.append(["Daily siege", 25])
	return {"total": maxi(depth + fight + bonus, 10), "lines": lines}


## Close out a run: commit the day counters, pay the renown, and report what
## changed so the score screen can animate it.
func end_run(result: Dictionary) -> Dictionary:
	if Game.sim_mode or Game.booth_mode:
		return {}
	if bool(result.get("won", false)) and str(result.get("mode_id", "")) == "campaign":
		track("campaign_wins")
	var award := renown_for_run(result)
	var before_renown := renown()
	var before_level := level()
	_commit_day_stats()
	var res := add_renown(int(award["total"]))
	Save.save_profile()
	return {
		"lines": award["lines"], "gained": int(award["total"]),
		"before": before_renown, "after": renown(),
		"before_level": before_level, "after_level": level(),
		"levels": res.get("levels", []),
		"next": next_unlock(),
	}


# ---------------------------------------------------------------- run setup

## Fold the chosen commander into the run. Called after Boons.reset and before
## the first wave, so its mods sit underneath everything drafted later.
func apply_commander() -> Dictionary:
	# The sim always fights as the Warden, or every balance number would drift
	# with whatever the last human player happened to have selected.
	var c := commander_data("warden") if Game.sim_mode else commander_data()
	var m: Dictionary = c.get("mods", {})
	for k in m.keys():
		if Boons.mods.has(k):
			Boons.mods[k] = Boons.mods[k] + m[k]
	Boons.mods_changed.emit()
	return c
