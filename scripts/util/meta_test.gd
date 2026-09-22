class_name MetaTest
extends Node
## Self-test for the progression layer:
##   godot --headless --path . -- --metatest
##
## It checks the things that are easy to get quietly wrong and impossible to
## see in a screenshot: that renown survives a save/load round trip, that
## levels gate the right content, that contracts count and pay exactly once,
## and that a commander's modifiers actually reach the tables the game reads.
##
## Runs against a scratch profile and puts the real one back before quitting.
## Exit code is non-zero on failure, so CI can gate on it.

var _failures := 0
var _backup: Dictionary = {}


func _ready() -> void:
	_backup = Save.data.duplicate(true)
	_levels()
	_gating()
	_round_trip()
	_contracts()
	_day_scope()
	_commanders()
	_awards()
	Save.data = _backup
	Save.save_profile()
	print("META_CHECK %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _ok(label: String, cond: bool, detail: String = "") -> void:
	if cond:
		print("  ok    %s" % label)
	else:
		_failures += 1
		print("  FAIL  %s   %s" % [label, detail])


func _levels() -> void:
	print("-- levels")
	_ok("level 1 at zero renown", Meta.level_for_renown(0) == 1)
	_ok("level 2 is one or two runs away", Meta.renown_for_level(2) == 140,
		"got %d" % Meta.renown_for_level(2))
	var rising := true
	for lv in range(2, Meta.LEVEL_CAP + 1):
		if Meta.renown_for_level(lv) <= Meta.renown_for_level(lv - 1):
			rising = false
	_ok("thresholds strictly increase", rising)
	_ok("the cap holds", Meta.level_for_renown(99999999) == Meta.LEVEL_CAP)


func _gating() -> void:
	print("-- gating")
	Save.data["renown"] = 0
	_ok("campaign is never locked", Meta.is_unlocked_mode("campaign"))
	_ok("the daily starts locked", not Meta.is_unlocked_mode("daily"))
	_ok("only the warden at level 1",
		Meta.is_unlocked_commander("warden") and not Meta.is_unlocked_commander("zealot"))
	_ok("the epic boons start out of the draft", Meta.locked_boon_ids().has("greek_fire"))
	_ok("a locked boon is never offered", not _offers_locked())
	Save.data["renown"] = Meta.renown_for_level(6)
	_ok("the daily is open by level 6", Meta.is_unlocked_mode("daily"))
	_ok("the zealot opens at level 6", Meta.is_unlocked_commander("zealot"))
	_ok("the naftgir is still locked at 6", not Meta.is_unlocked_commander("naftgir"))
	Save.data["renown"] = Meta.renown_for_level(12)
	_ok("nothing is locked at the cap", Meta.locked_boon_ids().is_empty())


## Draft a hundred times at level 1 and make sure nothing held back slips out.
func _offers_locked() -> bool:
	var locked := Meta.locked_boon_ids()
	for i in range(100):
		Boons.reset(i + 1)
		for b in Boons.offer(3):
			if locked.has(str(b["id"])):
				return true
	return false


func _round_trip() -> void:
	print("-- renown survives a save and load")
	Save.data["renown"] = 0
	Meta.add_renown(275)
	Save.save_profile()
	Save.load_profile()
	_ok("renown reloads", Meta.renown() == 275, "got %d" % Meta.renown())
	_ok("as an int, not a JSON float", typeof(Save.data.get("renown")) == TYPE_INT)
	_ok("the commander reloads", str(Save.data.get("commander", "")) != "")


func _contracts() -> void:
	print("-- contracts")
	# Force a known contract in so this does not depend on today's roll.
	Save.data["contracts"] = {"day": Meta._today(), "day_stats": {},
		"list": [{"id": "build8", "progress": 0, "done": false}]}
	var before := Meta.renown()
	Meta.begin_run()
	for i in range(7):
		Meta.track("builds")
	var entry: Dictionary = Save.data["contracts"]["list"][0]
	_ok("progress accrues", int(entry["progress"]) == 7, "got %s" % str(entry["progress"]))
	_ok("nothing is paid early", Meta.renown() == before, "got %d" % Meta.renown())
	Meta.track("builds")
	_ok("completing pays", Meta.renown() == before + 50,
		"got %d, wanted %d" % [Meta.renown(), before + 50])
	Meta.track("builds")
	Meta.track("builds")
	_ok("and pays only once", Meta.renown() == before + 50, "got %d" % Meta.renown())


func _day_scope() -> void:
	print("-- a day-scoped contract spans runs")
	Save.data["contracts"] = {"day": Meta._today(), "day_stats": {},
		"list": [{"id": "kills200", "progress": 0, "done": false}]}
	Meta.begin_run()
	for i in range(120):
		Meta.track("kills")
	var entry: Dictionary = Save.data["contracts"]["list"][0]
	_ok("one run is not enough", not bool(entry["done"]))
	Meta._commit_day_stats()
	Meta.begin_run()
	for i in range(85):
		Meta.track("kills")
	_ok("the second run finishes it", bool(entry["done"]),
		"progress %s" % str(entry["progress"]))
	print("-- a run-scoped contract does not")
	Save.data["contracts"] = {"day": Meta._today(), "day_stats": {},
		"list": [{"id": "build8", "progress": 0, "done": false}]}
	Meta.begin_run()
	for i in range(5):
		Meta.track("builds")
	Meta._commit_day_stats()
	Meta.begin_run()
	for i in range(5):
		Meta.track("builds")
	_ok("five plus five is not eight in one run",
		not bool(Save.data["contracts"]["list"][0]["done"]),
		"progress %s" % str(Save.data["contracts"]["list"][0]["progress"]))


func _commanders() -> void:
	print("-- commanders reach the tables the game reads")
	Save.data["renown"] = Meta.renown_for_level(12)
	var base := Config.tower_cost(Config.TowerType.ARCHER, 1)
	Boons.reset(1)
	Meta.set_commander("mason")
	Meta.apply_commander()
	_ok("the mason soaks damage", Boons.tower_damage_taken(100.0) < 60.0,
		"took %.1f of 100" % Boons.tower_damage_taken(100.0))
	_ok("and pays a surcharge to build", Boons.tower_cost(Config.TowerType.ARCHER, 1) > base,
		"%d vs %d" % [Boons.tower_cost(Config.TowerType.ARCHER, 1), base])
	Boons.reset(1)
	Meta.set_commander("zealot")
	Meta.apply_commander()
	_ok("the zealot sharpens the repeater", Boons.m("cmd_dmg") > 1.5,
		"cmd_dmg %.2f" % Boons.m("cmd_dmg"))
	_ok("and costs a life", int(Meta.commander_data("zealot")["lives"]) == -1)
	Boons.reset(1)
	Meta.set_commander("warden")
	Meta.apply_commander()
	_ok("the warden changes nothing at all",
		Boons.tower_cost(Config.TowerType.ARCHER, 1) == base
		and is_equal_approx(Boons.m("dmg_all"), 1.0)
		and is_equal_approx(Boons.m("rock_kill"), 1.0)
		and is_equal_approx(Boons.m("build_cost"), 1.0))


func _awards() -> void:
	print("-- a run is worth something")
	var loss: Dictionary = Meta.renown_for_run(
		{"waves": 7, "kills": 96, "won": false, "mode_id": "campaign"})
	var win: Dictionary = Meta.renown_for_run(
		{"waves": 10, "kills": 200, "won": true, "mode_id": "campaign"})
	var nothing: Dictionary = Meta.renown_for_run(
		{"waves": 0, "kills": 0, "won": false, "mode_id": "campaign"})
	_ok("a losing run still pays", int(loss["total"]) > 0, "got %d" % int(loss["total"]))
	_ok("a wipe on wave 1 still pays something", int(nothing["total"]) > 0)
	_ok("a win pays more than a loss", int(win["total"]) > int(loss["total"]),
		"%d vs %d" % [int(win["total"]), int(loss["total"])])
	_ok("two good runs reach level 2", int(win["total"]) * 2 >= Meta.renown_for_level(2),
		"a win pays %d, level 2 needs %d" % [int(win["total"]), Meta.renown_for_level(2)])
	# Shape of the curve, stated as what it should feel like rather than as
	# the formula, so a future tuning pass has something to check against.
	_ok("the first unlock is about one run away",
		Meta.renown_for_level(2) <= int(win["total"]),
		"level 2 is %d, a win pays %d" % [Meta.renown_for_level(2), int(win["total"])])
	_ok("the mid track is several sessions, not one",
		Meta.renown_for_level(6) >= int(win["total"]) * 4,
		"level 6 is %d, a win pays %d" % [Meta.renown_for_level(6), int(win["total"])])
	_ok("the cap is not reachable in an afternoon",
		Meta.renown_for_level(Meta.LEVEL_CAP) >= int(win["total"]) * 15,
		"the cap is %d, a win pays %d" % [Meta.renown_for_level(Meta.LEVEL_CAP), int(win["total"])])
