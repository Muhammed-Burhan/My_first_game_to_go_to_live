class_name ShotRunner
extends Node
## Scripted screenshot tour for visual checks without a device:
##   godot --path . --resolution 720x1280 -- --shot=C:/tmp/shots
## Saves loading, title, mid-battle, menus, pause, score and QR frames, then quits.

var main: Node
var dir: String = "user://shots"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			dir = a.substr(7)
	DirAccess.make_dir_recursive_absolute(dir)
	_run()


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		get_viewport().push_input(ev, true)


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
	await _snap("03_battle.png")
	print("FPS_BATTLE %d" % int(Engine.get_frames_per_second()))
	await get_tree().create_timer(0.8).timeout
	await _snap("04_battle_b.png")

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
	await get_tree().create_timer(3.0).timeout
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
	await _snap("14_endless.png")
	print("FPS_ENDLESS %d" % int(Engine.get_frames_per_second()))
	get_tree().quit()
