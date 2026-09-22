class_name ShotRunner
extends Node
## Scripted screenshot tour for visual checks without a device:
##   godot --path . --resolution 720x1280 -- --shot=C:/tmp/shots
## Saves loading, title, mid-battle, menus, pause, score and QR frames, then quits.

var main: Node
var dir: String = "user://shots"
## The tour plays a run to completion, which pays renown and can complete
## contracts. That would quietly rewrite the developer's own profile, so the
## progression fields are snapshotted here and put back before it quits.
var _profile_backup: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			dir = a.substr(7)
	DirAccess.make_dir_recursive_absolute(dir)
	_backup_profile()
	_run()


func _backup_profile() -> void:
	for k in ["renown", "commander", "contracts", "commander_auto"]:
		_profile_backup[k] = Save.data[k].duplicate(true) if Save.data[k] is Dictionary else Save.data[k]
	# Show the garrison mid-progression rather than empty: locked and unlocked
	# rows side by side is the thing worth looking at. Pass --fresh to shoot the
	# tour as a first-time player instead, which is the state that decides
	# whether anyone gets as far as a second run.
	if "--fresh" in OS.get_cmdline_user_args():
		Save.data["renown"] = 0
		Meta.commander = "warden"
		Save.data["commander"] = "warden"
		Save.data["contracts"] = {"day": -1, "list": [], "day_stats": {}}
		return
	Save.data["renown"] = Meta.renown_for_level(6) + 60
	Meta.set_commander("mason")


func _restore_profile() -> void:
	for k in _profile_backup.keys():
		Save.data[k] = _profile_backup[k]
	Meta.commander = str(Save.data.get("commander", "warden"))
	Save.save_profile()


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


## Average frame rate over a window. Engine.get_frames_per_second() is a
## single-frame sample and swings by fifteen frames between runs, which is
## enough noise to hide or invent a real regression.
func _fps_over(seconds: float) -> float:
	# Wall clock, not get_process_delta_time(): this node does not run
	# _process, so its delta is zero and the average came out as zero too.
	var frames := 0
	var t0 := Time.get_ticks_msec()
	var want := int(seconds * 1000.0)
	while Time.get_ticks_msec() - t0 < want:
		await get_tree().process_frame
		frames += 1
	var secs := float(Time.get_ticks_msec() - t0) / 1000.0
	# Draw calls alongside the rate: it is the difference between "the art is
	# too heavy" and "something else is eating the frame", and guessing wrong
	# costs a day.
	print("  draw_calls %d  items %d  lights?%d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	return float(frames) / maxf(secs, 0.001)


## --hide=bg,atmos,post,units,towers,road strips layers out before the frame
## rate is measured. Guessing which layer costs the frame is how you spend a
## day optimising the wrong thing.
func _apply_hide(level: Node) -> void:
	var want := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hide="):
			want = a.substr(7)
	if want == "":
		return
	var parts := want.split(",")
	for name in parts:
		match name:
			"bg":
				level.background.visible = false
			"post":
				level.post.visible = false
			"atmos":
				for c in level.get_children():
					if c is Atmosphere:
						c.visible = false
			"road":
				for c in level.get_children():
					if c is Line2D or c.get_class() == "Node2D":
						if not (c is Atmosphere) and c != level.fx_layer:
							c.visible = false
			"stones":
				for c in level.get_children():
					if c.get_script() != null and str(c.get_script().resource_path).ends_with("level.gd"):
						pass
				for c in level.get_children():
					if c.get_class() == "Node2D" and c.get_script() == null:
						c.visible = false
			"units":
				for e in level.enemies.get_children():
					e.visible = false
			"towers":
				for t in level.towers():
					t.visible = false
			"slots":
				for sl in level.slots:
					sl.visible = false
			"lights":
				_kill_lights(level)
	print("HIDDEN %s" % want)


## Every PointLight2D in the tree. Canvas lights re-render whatever they touch,
## so they cost far more than their draw-call count suggests.
func _kill_lights(n: Node) -> void:
	if n is PointLight2D:
		n.visible = false
	for c in n.get_children():
		_kill_lights(c)


func _snap(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join(shot_name)
	var err := img.save_png(path)
	print("SHOT %s %s" % [path, "ok" if err == OK else "ERR %d" % err])


func _run() -> void:
	await get_tree().create_timer(1.0).timeout
	await _snap("00_loading.png")
	if not main.loaded:
		await main.loading_finished
	await get_tree().create_timer(0.6).timeout
	await _snap("01_title.png")

	# Real input path: a synthetic tap on the campaign card must start the game.
	print("TITLE_SIZE %s" % str(main.title.size))
	_click(Vector2(292, 1230))
	await get_tree().create_timer(0.5).timeout
	print("TAP_START %s" % ("ok" if main.hud.visible and not main.title.visible else "FAIL"))
	var level: Level = main.level
	# And a tap on a plinth must open the build menu.
	_click(level.slots[0].position)
	await get_tree().create_timer(0.3).timeout
	print("TAP_SLOT %s" % ("ok" if main.menu.is_open() else "FAIL"))
	main.menu.close()
	await get_tree().create_timer(0.1).timeout
	Game.add_rock(2000, false)
	var by_y := level.slots.duplicate()
	by_y.sort_custom(func(a, b): return a.position.y > b.position.y)
	level.place_tower(by_y[0], Config.TowerType.ARCHER)
	level.place_tower(by_y[1], Config.TowerType.OIL)
	level.place_tower(by_y[2], Config.TowerType.BALLISTA)
	level.place_tower(by_y[3], Config.TowerType.ARCHER)
	level.place_tower(by_y[5], Config.TowerType.BALLISTA)
	level.place_tower(by_y[7], Config.TowerType.OIL)
	level.upgrade_tower(by_y[0].tower)
	level.upgrade_tower(by_y[0].tower)
	level.upgrade_tower(by_y[1].tower)
	level.upgrade_tower(by_y[2].tower)
	level.upgrade_tower(by_y[2].tower)
	level.upgrade_tower(by_y[5].tower)
	Game.set_wave(7)
	level.next_wave = 7
	level.skip_prep()
	await get_tree().create_timer(0.15).timeout
	await _snap("02_wave_banner.png")
	level._spawn_list = Config.wave_spawn_list(7)
	level.wave_size = level._spawn_list.size()
	var length := level.curve.get_baked_length()
	level.spawn_enemy(Config.EnemyType.RAIDER, length * 0.12)
	level.spawn_enemy(Config.EnemyType.RAIDER, length * 0.15)
	level.spawn_enemy(Config.EnemyType.RUNNER, length * 0.30)
	level.spawn_enemy(Config.EnemyType.SHIELDMAN, length * 0.42)
	level.spawn_enemy(Config.EnemyType.CART, length * 0.55)
	level.spawn_enemy(Config.EnemyType.RAIDER, length * 0.62)
	level.spawn_enemy(Config.EnemyType.BOSS, length * 0.08)
	await get_tree().create_timer(2.2).timeout
	_apply_hide(level)
	await _snap("03_battle.png")
	print("FPS_BATTLE %.1f" % await _fps_over(1.5))
	await get_tree().create_timer(0.8).timeout
	await _snap("04_battle_b.png")

	# AUTO has to pull the trigger with no finger on the screen, and the crews
	# have to be facing what they are shooting at. Both are easy to break and
	# invisible in a still, so they are checked rather than eyeballed.
	var aimed := 0
	for s2 in level.slots:
		if s2.tower != null and s2.tower._target != null:
			aimed += 1
	print("CREW_AIMED %d towers have a target" % aimed)
	level.commander.set_auto(true)
	var heat0: float = level.commander.heat
	await get_tree().create_timer(1.4).timeout
	print("AUTO_FIRE %s" % ("ok" if level.commander.heat > heat0 else "FAIL"))
	await _snap("19_auto_fire.png")
	# And it must stop short of the lockout rather than riding into it.
	await get_tree().create_timer(4.0).timeout
	print("AUTO_NO_LOCKOUT %s (heat %.2f)" % [
		"ok" if level.commander.locked <= 0.0 else "FAIL", level.commander.heat])
	level.commander.set_auto(false)
	await get_tree().create_timer(0.3).timeout

	main.menu.open_tower(by_y[2].tower)
	await get_tree().create_timer(0.35).timeout
	await _snap("05_tower_menu.png")
	main.menu.close()
	for s in level.slots:
		if s.tower == null:
			main.menu.open_slot(s)
			break
	await get_tree().create_timer(0.35).timeout
	await _snap("06_build_menu.png")
	main.menu.close()

	# The roguelite draft, forced open so it lands in the tour.
	main._on_draft_requested(7)
	await get_tree().create_timer(0.9).timeout
	await _snap("07_draft.png")
	main.draft._on_pick(main.draft._cards[1].boon)
	await get_tree().create_timer(0.9).timeout

	main._open_pause()
	await get_tree().create_timer(0.4).timeout
	await _snap("08_pause.png")
	main._close_pause()
	await get_tree().create_timer(0.2).timeout

	# Gate damage then defeat
	level.gate.hit()
	await get_tree().create_timer(0.3).timeout
	level.gate.hit()
	await _snap("09_gate_damaged.png")
	Game.waves_cleared = 6
	Game.rock_earned = 640
	Game.lives = 1
	Game.lose_lives(1)
	# Long enough for the renown bar to finish counting and the unlock banner
	# to land: that frame is the whole argument for a second run, so the tour
	# has to actually show it.
	await get_tree().create_timer(4.6).timeout
	await _snap("10_score.png")
	main.score._name_edit.text = "Hawre"
	main.score._on_submit()
	await get_tree().create_timer(0.5).timeout
	await _snap("11_qr.png")

	# The share card: the thing a player screenshots.
	main.share.show_card(Game.last_result)
	await get_tree().create_timer(0.7).timeout
	await _snap("12_share_card.png")
	main.share.close()

	# Free Siege: a seeded mound, deep wave, tier and elites showing.
	main._show_title()
	await get_tree().create_timer(0.5).timeout
	await _snap("13_title_modes.png")

	# The progression screens.
	main.garrison.open(0)
	await get_tree().create_timer(0.45).timeout
	await _snap("14_garrison_commanders.png")
	main.garrison.open(1)
	await get_tree().create_timer(0.35).timeout
	await _snap("15_garrison_contracts.png")
	main.garrison.open(2)
	await get_tree().create_timer(0.35).timeout
	await _snap("16_garrison_unlocks.png")
	main.garrison.close()
	await get_tree().create_timer(0.35).timeout
	main._start_game(Config.Mode.FREE)
	Game.add_rock(4000, false)
	for i in range(6):
		level.place_tower(by_y[i], [Config.TowerType.ARCHER, Config.TowerType.OIL, Config.TowerType.BALLISTA][i % 3])
	Game.set_wave(18)
	level.next_wave = 18
	level.skip_prep()
	await get_tree().create_timer(0.2).timeout
	level._wave_scale = Config.endless_scale(18)
	level._spawn_list = Config.wave_spawn_list(18, Config.Mode.FREE)
	level.wave_size = level._spawn_list.size()
	for i in range(7):
		level.spawn_enemy(Config.EnemyType.RAIDER, length * (0.1 + i * 0.09))
	level.spawn_enemy(Config.EnemyType.SHIELDMAN, length * 0.5)
	level.spawn_enemy(Config.EnemyType.CART, length * 0.34)
	await get_tree().create_timer(1.6).timeout
	await _snap("17_endless.png")
	print("FPS_ENDLESS %.1f" % await _fps_over(1.5))
	_restore_profile()
	get_tree().quit()
