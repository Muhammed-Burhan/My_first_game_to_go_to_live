extends Node
## Root: owns the level and the UI layers, and runs the screen state machine
## Loading -> Title -> Playing -> Score -> (Title | Playing). Also hosts the
## headless sim and the screenshot runner.

signal loading_finished

var level: Level
var ui: CanvasLayer
var boot: CanvasLayer
var hud: Hud
var menu: BuildMenu
var title: TitleScreen
var score: ScoreScreen
var pause_menu: PauseMenu
var draft: DraftScreen
var share: ShareCard
var garrison: Garrison
var loading: LoadingScreen
var loaded: bool = false


func _ready() -> void:
	# A --sim run pins every random source it can so two balance runs differ as
	# little as possible. It still will not match to the wave: the game steps
	# on _process(delta) and a headless frame is not a fixed length, so a run
	# is a sample, not a fingerprint. Take the sim as a distribution.
	if Game.sim_mode:
		seed(Game.sim_boon_seed)
	else:
		randomize()
	var theme := UiTheme.make()
	get_tree().root.theme = theme

	level = Level.new()
	add_child(level)

	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	# Theme does not propagate through a CanvasLayer, so each root control gets it.
	hud = Hud.new()
	hud.theme = theme
	hud.visible = false
	ui.add_child(hud)
	hud.bind(level)

	menu = BuildMenu.new()
	menu.theme = theme
	ui.add_child(menu)

	title = TitleScreen.new()
	title.theme = theme
	title.visible = false
	ui.add_child(title)

	score = ScoreScreen.new()
	score.theme = theme
	ui.add_child(score)

	pause_menu = PauseMenu.new()
	pause_menu.theme = theme
	ui.add_child(pause_menu)

	draft = DraftScreen.new()
	draft.theme = theme
	ui.add_child(draft)

	share = ShareCard.new()
	share.theme = theme
	ui.add_child(share)

	garrison = Garrison.new()
	garrison.theme = theme
	ui.add_child(garrison)

	level.slot_tapped.connect(_on_slot_tapped)
	level.tower_tapped.connect(_on_tower_tapped)
	level.empty_tapped.connect(func(): menu.close())
	menu.build_chosen.connect(func(slot, type): level.place_tower(slot, type))
	menu.upgrade_chosen.connect(func(t): level.upgrade_tower(t))
	menu.sell_chosen.connect(func(t): level.sell_tower(t))
	menu.repair_chosen.connect(func(t): level.repair_tower(t))
	title.start_requested.connect(_start_game)
	title.garrison_requested.connect(func(tab: int):
		title.visible = false
		garrison.open(tab))
	garrison.closed.connect(func(): title.show_title())
	score.play_again.connect(func(): _start_game(Game.mode))
	score.back_to_title.connect(_show_title)
	score.share_requested.connect(func(): share.show_card(Game.last_result))
	hud.pause_requested.connect(_open_pause)
	pause_menu.resumed.connect(_close_pause)
	pause_menu.quit_to_title.connect(_quit_to_title)
	level.draft_requested.connect(_on_draft_requested)
	draft.chosen.connect(_on_draft_chosen)
	Game.run_ended.connect(_on_run_ended)

	if Game.sim_mode:
		# The sim has no screens: build the (silent) audio bank and play at once.
		var sim := SimPlayer.new()
		sim.level = level
		add_child(sim)
		loaded = true
		_start_game(Game.mode)
		return

	# Progression self-test: needs the real autoloads, so it runs inside the
	# game the way --sim and --shot do rather than as a detached -s script.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--units="):
			# Sits in the same canvas as the battlefield (a CanvasLayer does not
			# share the stretch transform, which left the mound showing at the
			# edges), with the level hidden underneath it.
			level.visible = false
			ui.visible = false
			var sheet := UnitSheet.new()
			add_child(sheet)
			return
		if a == "--metatest":
			var mt := MetaTest.new()
			add_child(mt)
			return

	_start_loading()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var shots := ShotRunner.new()
			shots.main = self
			add_child(shots)


func _start_loading() -> void:
	boot = CanvasLayer.new()
	boot.layer = 50
	add_child(boot)
	loading = LoadingScreen.new()
	loading.theme = get_tree().root.theme
	boot.add_child(loading)
	loading.finished.connect(func():
		loaded = true
		loading.queue_free()
		boot.queue_free()
		_show_title()
		loading_finished.emit())


func _show_title() -> void:
	_close_pause()
	garrison.visible = false
	share.close()
	menu.close()
	hud.visible = false
	score.visible = false
	title.show_title()
	Sfx.music("menu")


func _start_game(mode: int = Config.Mode.CAMPAIGN) -> void:
	# A launch flag or a shared ?game=daily link can name a mode this profile
	# has not opened yet. Fall back rather than dropping them into something
	# the menu says is locked.
	if not Meta.is_unlocked_mode(str(Config.MODES[mode]["id"])):
		mode = Config.Mode.CAMPAIGN
	_close_pause()
	share.close()
	menu.close()
	title.visible = false
	score.visible = false
	hud.visible = true
	level.start_run(mode)
	hud.reset()


func _on_run_ended(result: Dictionary) -> void:
	menu.close()
	_close_pause()
	if Game.sim_mode:
		return
	await get_tree().create_timer(1.7).timeout
	hud.visible = false
	score.show_result(result)


func _on_slot_tapped(slot: Slot) -> void:
	if level.phase == "done":
		return
	menu.open_slot(slot)


func _on_tower_tapped(t: Tower) -> void:
	if level.phase == "done":
		return
	menu.open_tower(t)


# ------------------------------------------------------------------ draft

func _on_draft_requested(wave: int) -> void:
	if not Game.running:
		return
	var offers := Boons.offer(3)
	if offers.is_empty():
		return
	# The balance bot drafts too, or the sim would measure a game nobody plays.
	if Game.sim_mode:
		Boons.take(offers[randi() % offers.size()])
		return
	menu.close()
	get_tree().paused = true
	draft.open(wave, offers)


func _on_draft_chosen(boon: Dictionary) -> void:
	if not boon.is_empty():
		Boons.take(boon)
	get_tree().paused = false


# ------------------------------------------------------------------ pause

func _can_pause() -> bool:
	return loaded and hud.visible and Game.running and not Game.sim_mode and not draft.visible


func _open_pause() -> void:
	if not _can_pause() or pause_menu.visible:
		return
	menu.close()
	Game.set_paused(true)
	get_tree().paused = true
	pause_menu.open()


func _close_pause() -> void:
	if draft.visible:
		return
	if not pause_menu.visible:
		get_tree().paused = false
		return
	pause_menu.close()
	Game.set_paused(false)
	get_tree().paused = false


func _quit_to_title() -> void:
	_close_pause()
	Game.running = false
	level.abandon()
	_show_title()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_SPACE and level.phase == "prep":
		level.skip_prep()
	if key == KEY_F and hud.visible:
		Game.toggle_speed()
	if key == KEY_ESCAPE:
		if pause_menu.visible:
			_close_pause()
		elif _can_pause():
			_open_pause()
		elif not Game.booth_mode and title.visible and OS.has_feature("pc"):
			get_tree().quit()
