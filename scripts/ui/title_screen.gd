class_name TitleScreen
extends Control
## Title over the live backdrop: wordmark, the Daily Siege as the hero card,
## Campaign and Free Siege beneath it, then the board.
## In booth mode it doubles as the attract loop, alternating daily / all-time.

signal start_requested(mode: int)
signal garrison_requested(tab: int)

var _board: LeaderboardPanel
var _strip: TopStrip
var _garrison_row: GarrisonRow
var _cards: Array[Control] = []
var _banner: Banner
var _daily: DailyCard
var _mute_btn: Button
var _t := 0.0
var _attract_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.66)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_banner = Banner.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	# Level and renown ride at the very top. It is the first thing on the
	# screen because it is the thing that is different from last time.
	_strip = TopStrip.new()
	_strip.position = Vector2(55, 40)
	_strip.size = Vector2(880, 104)
	_strip.tapped.connect(func(): garrison_requested.emit(2))
	add_child(_strip)

	# The Daily is the hero: it is the one that is the same for everyone today.
	_daily = DailyCard.new()
	_daily.position = Vector2(55, 630)
	_daily.size = Vector2(970, 300)
	_daily.chosen.connect(_on_card)
	add_child(_daily)
	_cards.append(_daily)

	var side := [Config.Mode.CAMPAIGN, Config.Mode.FREE]
	for i in range(side.size()):
		var card := ModeCard.new()
		card.mode = side[i]
		card.position = Vector2(55 + i * 495, 960)
		card.size = Vector2(475, 300)
		card.chosen.connect(_on_card)
		add_child(card)
		_cards.append(card)

	# Who you are taking in, and what today is asking for.
	_garrison_row = GarrisonRow.new()
	_garrison_row.position = Vector2(55, 1288)
	_garrison_row.size = Vector2(970, 146)
	_garrison_row.tapped.connect(func(tab: int): garrison_requested.emit(tab))
	add_child(_garrison_row)

	_board = LeaderboardPanel.new()
	_board.position = Vector2(55, 1462)
	_board.size = Vector2(970, 350)
	add_child(_board)

	_mute_btn = Button.new()
	_mute_btn.position = Vector2(948, 168)
	_mute_btn.size = Vector2(92, 92)
	_mute_btn.add_theme_font_size_override("font_size", 44)
	_mute_btn.pressed.connect(_on_mute)
	add_child(_mute_btn)
	_refresh_mute()

	var foot := Label.new()
	foot.text = "HITEX  ·  Erbil International Fair"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 26)
	foot.add_theme_color_override("font_color", Config.C_TEXT_DIM)
	foot.position = Vector2(0, 1846)
	foot.size = Vector2(1080, 40)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(foot)


func show_title() -> void:
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.35)
	_board.highlight_id = ""
	_board.refresh()
	_strip.queue_redraw()
	_garrison_row.queue_redraw()
	Leaderboard.refresh_remote()
	for i in range(_cards.size()):
		var c := _cards[i]
		c.call("refresh")
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2(0.88, 0.88)
		var t := c.create_tween()
		t.tween_interval(0.07 * i)
		t.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	if Game.booth_mode:
		_attract_timer += delta
		if _attract_timer > 7.0:
			_attract_timer = 0.0
			_board.toggle_board()


func _on_card(mode: int) -> void:
	var mode_id := str(Config.MODES[mode]["id"])
	if not Meta.is_unlocked_mode(mode_id):
		# Show them what it is and what it costs rather than just buzzing.
		Sfx.play("deny")
		garrison_requested.emit(2)
		return
	Sfx.play("click")
	start_requested.emit(mode)


func _on_mute() -> void:
	Sfx.set_muted(not Sfx.muted)
	_refresh_mute()
	if not Sfx.muted:
		Sfx.play("click")


func _refresh_mute() -> void:
	_mute_btn.text = "♪" if not Sfx.muted else "✕"


## The wordmark and its sweeping shine, drawn behind the cards.
class Banner extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		Wordmark.draw(self, 372.0, 1080.0, 1.0, _t)


## Shared press behaviour for every card on this screen.
class CardBase extends Control:
	signal chosen(mode: int)
	var mode := Config.Mode.CAMPAIGN
	var _down := false
	var _t := 0.0
	var _home_y := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_t = randf() * 4.0
		_home_y = position.y
		pivot_offset = size / 2.0
		build()
		refresh()

	func build() -> void:
		pass

	func refresh() -> void:
		queue_redraw()

	## Shared with the garrison rows: same lock, same meaning, everywhere.
	static func draw_padlock(ci: CanvasItem, c: Vector2, s: float = 1.0) -> void:
		var col := Color(0.62, 0.66, 0.74, 0.85)
		ci.draw_arc(c + Vector2(0, -16 * s), 17 * s, PI, TAU, 20, col, 7.0 * s)
		ci.draw_rect(Rect2(c.x - 25 * s, c.y - 8 * s, 50 * s, 38 * s), col)
		ci.draw_circle(c + Vector2(0, 8 * s), 6 * s, Color(0.1, 0.11, 0.15, 0.95))

	func _process(delta: float) -> void:
		_t += delta
		if not _down:
			# A slow bob and a hair of tilt: enough to read as alive, little
			# enough that six of them on screen do not swim.
			position.y = _home_y + sin(_t * 1.4) * 4.0
			rotation = sin(_t * 0.9) * 0.006
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pivot_offset = size / 2.0
			if event.pressed:
				_down = true
				var t := create_tween()
				t.tween_property(self, "scale", Vector2(0.96, 0.96), 0.07)
			elif _down:
				_down = false
				var t := create_tween()
				t.tween_property(self, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				chosen.emit(mode)


## The Daily: one seed a day, the same mound for everyone, a countdown to the next.
class DailyCard extends CardBase:
	var _best := 0
	var _best_wave := 0
	var _box: StyleBoxTexture
	var _pill: StyleBoxTexture

	func build() -> void:
		mode = Config.Mode.DAILY
		_box = Gfx.gradient_box(Color("3d3112"), Color("15100a"), Config.C_ROCK, 4.0, 30.0)
		_pill = Gfx.gradient_box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0.3), Color(Config.C_ROCK, 0.5), 2.0, 16.0)

	func refresh() -> void:
		_best = Save.best("daily")
		_best_wave = Save.best_wave("daily")
		queue_redraw()

	## Time left until the seed rolls over at midnight UTC.
	func _countdown() -> String:
		var now := Time.get_datetime_dict_from_system(true)
		var left := 86400 - (int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"]))
		return "%02d:%02d:%02d" % [left / 3600, (left % 3600) / 60, left % 60]

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(_t * 1.9)
		var open := Meta.is_unlocked_mode("daily")
		if open:
			Gfx.draw_glow(self, size / 2.0, size.x * 0.45, Config.C_ROCK, 0.24 + 0.12 * pulse, 5)
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		if not open:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.7))
			CardBase.draw_padlock(self, Vector2(140, size.y * 0.5), 1.4)
			Gfx.draw_text(self, Vector2(250, 118), "DAILY SIEGE", 60, Color(Config.C_TEXT_DIM, 0.75),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
			Gfx.draw_text(self, Vector2(252, 168), "Opens at level %d  ·  %d renown away" % [
				Meta.mode_unlock_level("daily"),
				maxi(Meta.renown_for_level(Meta.mode_unlock_level("daily")) - Meta.renown(), 0)],
				30, Config.C_ROCK, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
			Gfx.draw_text(self, Vector2(252, 216), "One seed a day. The same siege for everyone.",
				26, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_MED))
			return
		# Sun-and-mound emblem on the left
		var c := Vector2(140, size.y * 0.5)
		draw_circle(c, 78, Color(Config.C_ROCK, 0.12))
		for i in range(12):
			var a := _t * 0.25 + float(i) / 12.0 * TAU
			draw_line(c + Vector2(cos(a), sin(a)) * 62.0, c + Vector2(cos(a), sin(a)) * 80.0,
				Color(Config.C_ROCK, 0.45), 4.0)
		draw_circle(c, 54, Config.C_ROCK.darkened(0.15))
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(-52, 30), c + Vector2(-26, -18), c + Vector2(4, -34),
			c + Vector2(30, -10), c + Vector2(52, 30),
		]), Color("2a1d10"))
		draw_rect(Rect2(c.x - 16, c.y - 6, 32, 36), Config.C_ROCK)
		# Headline
		Gfx.draw_text(self, Vector2(250, 92), "DAILY SIEGE", 60, Config.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		Gfx.draw_text(self, Vector2(252, 136), "#%d  ·  same mound for everyone today" % Config.daily_index(),
			28, Config.C_ROCK, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		# Best + countdown pills
		var pill_a := Rect2(250, 164, 320, 60)
		draw_style_box(_pill, pill_a)
		var best_text := "BEST  WAVE %d" % _best_wave if _best_wave > 0 else "NOT PLAYED YET"
		Gfx.draw_text(self, Vector2(250, 204), best_text, 28,
			Config.C_ROCK if _best_wave > 0 else Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 320, 5)
		var pill_b := Rect2(588, 164, 320, 60)
		draw_style_box(_pill, pill_b)
		Gfx.draw_text(self, Vector2(588, 204), "NEW IN  " + _countdown(), 28, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, 320, 5)
		Gfx.draw_text(self, Vector2(250, 276), "TAP TO PLAY TODAY'S SIEGE", 32,
			Color(Config.C_ROCK, 0.65 + 0.35 * pulse), HORIZONTAL_ALIGNMENT_LEFT, -1, 6)


## Campaign and Free Siege: the smaller pair under the Daily.
class ModeCard extends CardBase:
	var _best := 0
	var _box: StyleBoxTexture
	var _art_box: StyleBoxTexture

	func build() -> void:
		var free := mode == Config.Mode.FREE
		var rim: Color = Config.C_ELITE if free else Config.C_UI_LINE
		_box = Gfx.gradient_box(
			Color("3a2450") if free else Color("24365c"),
			Color("1a0f2a") if free else Color("0d1830"), rim, 4.0, 28.0)
		_art_box = Gfx.gradient_box(Color(0.03, 0.05, 0.1, 0.85), Color(0.05, 0.08, 0.15, 0.85),
			Color(rim, 0.4), 2.0, 18.0)

	func refresh() -> void:
		_best = Save.best(str(Config.MODES[mode]["id"]))
		queue_redraw()

	func _draw() -> void:
		var m: Dictionary = Config.MODES[mode]
		var free := mode == Config.Mode.FREE
		var rim: Color = Config.C_ELITE if free else Config.C_UI_LINE
		var open := Meta.is_unlocked_mode(str(m["id"]))
		var pulse := 0.5 + 0.5 * sin(_t * 2.0 + (1.6 if free else 0.0))
		if open:
			Gfx.draw_glow(self, size / 2.0, size.x * 0.6, rim, 0.22 + 0.10 * pulse, 4)
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		var art := Rect2(22, 20, size.x - 44, 130)
		draw_style_box(_art_box, art)
		var c := art.position + art.size / 2.0
		if free:
			_draw_dice(c)
		else:
			_draw_gate(c)
		if not open:
			# Dim the whole card and say plainly what opens it. A locked thing
			# the player can see is a goal; a hidden one is nothing at all.
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06, 0.72))
			CardBase.draw_padlock(self, Vector2(size.x * 0.5, 82), 1.15)
			Gfx.draw_text(self, Vector2(0, 194), str(m["name"]), 40, Color(Config.C_TEXT_DIM, 0.7),
				HORIZONTAL_ALIGNMENT_CENTER, size.x)
			Gfx.draw_text(self, Vector2(0, 236), "LEVEL %d" % Meta.mode_unlock_level(str(m["id"])),
				32, Config.C_ROCK, HORIZONTAL_ALIGNMENT_CENTER, size.x, 6)
			Gfx.draw_text(self, Vector2(0, 274), "%d renown away" % maxi(
				Meta.renown_for_level(Meta.mode_unlock_level(str(m["id"]))) - Meta.renown(), 0),
				24, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5, Fonts.ui(Fonts.W_MED))
			return
		Gfx.draw_text(self, Vector2(0, 194), str(m["name"]), 40, Config.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		Gfx.draw_text(self, Vector2(0, 230), str(m["sub"]), 26, rim, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		var best_text := "BEST  %d" % _best if _best > 0 else "NO RUN YET"
		Gfx.draw_text(self, Vector2(0, 272), best_text, 26,
			Config.C_ROCK if _best > 0 else Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)

	func _draw_gate(c: Vector2) -> void:
		draw_rect(Rect2(c.x - 34, c.y - 20, 68, 56), Config.C_WALL)
		draw_circle(Vector2(c.x, c.y - 20), 34, Config.C_WALL)
		draw_rect(Rect2(c.x - 21, c.y - 16, 42, 52), Config.C_WOOD_DARK)
		var cx := c.x - 42.0
		while cx < c.x + 30.0:
			draw_rect(Rect2(cx, c.y - 60, 16, 17), Config.C_WALL)
			cx += 26.0
		for i in range(8):
			draw_circle(Vector2(c.x - 84 + i * 24, c.y + 46), 5, Config.C_THREAT if i < 7 else Config.C_ROCK)

	func _draw_dice(c: Vector2) -> void:
		# A tumbling die: this one is a different mound every time.
		var a := sin(_t * 0.9) * 0.22
		draw_set_transform(c, a, Vector2.ONE)
		draw_rect(Rect2(-40, -40, 80, 80), Config.C_ELITE.darkened(0.35))
		draw_rect(Rect2(-34, -34, 68, 68), Config.C_ELITE)
		draw_rect(Rect2(-34, -34, 68, 20), Color(1, 1, 1, 0.12))
		for p in [Vector2(-17, -17), Vector2(17, -17), Vector2(0, 0), Vector2(-17, 17), Vector2(17, 17)]:
			draw_circle(p, 7, Color("1a0f2a"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Level and renown, across the top of the title. Tapping it opens the garrison
## on the unlock track, because "what is this bar for" is the question it asks.
class TopStrip extends Control:
	signal tapped

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		Meta.renown_changed.connect(func(_t): queue_redraw())

	func _draw() -> void:
		RenownBar.draw_into(self, Rect2(0, 0, size.x, 96))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			Sfx.play("click")
			tapped.emit()


## Two chips: the commander leading the next run, and how today's contracts are
## going. Both open the garrison, on the tab they are about.
class GarrisonRow extends Control:
	signal tapped(tab: int)
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _cmd_rect() -> Rect2:
		return Rect2(0, 0, size.x * 0.58 - 12.0, size.y)

	func _con_rect() -> Rect2:
		return Rect2(size.x * 0.58 + 12.0, 0, size.x * 0.42 - 12.0, size.y)

	func _draw() -> void:
		var cmd := Meta.commander_data()
		var col: Color = cmd["color"]
		var r := _cmd_rect()
		Gfx.draw_panel(self, r, Color(0.055, 0.08, 0.15, 0.94), Color(col, 0.55), 22.0, 2.0)
		var c := r.position + Vector2(74, r.size.y * 0.5)
		draw_circle(c, 46, Color(col, 0.14))
		draw_arc(c, 46, 0, TAU, 32, Color(col, 0.5), 2.5)
		DraftScreen.draw_boon_art(self, c, str(cmd["art"]), 0.33, _t)
		Gfx.draw_text(self, Vector2(r.position.x + 136, r.position.y + 58), "COMMANDER", 22,
			Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_BLACK, 4))
		Gfx.draw_text(self, Vector2(r.position.x + 136, r.position.y + 100), str(cmd["title"]), 34,
			Config.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)

		# Contracts: the count is the hook, so it is the big number.
		var done := Meta.contracts_done()
		var total: int = Meta.contracts().size()
		var all_done := total > 0 and done >= total
		var accent: Color = Config.C_GOOD if all_done else Config.C_ROCK
		var r2 := _con_rect()
		Gfx.draw_panel(self, r2, Color(0.055, 0.08, 0.15, 0.94), Color(accent, 0.55), 22.0, 2.0)
		Gfx.draw_text(self, Vector2(r2.position.x, r2.position.y + 50), "CONTRACTS", 22,
			Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x, 5, Fonts.ui(Fonts.W_BLACK, 4))
		Gfx.draw_text(self, Vector2(r2.position.x, r2.position.y + 104), "%d / %d" % [done, total], 44,
			accent, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x, 7)
		if not all_done:
			# A soft pulse on the card's own rim while there is still something
			# to claim. Anything radial here spills outside the chip.
			var a := 0.30 + 0.22 * sin(_t * 2.4)
			Gfx.draw_panel(self, r2.grow(-3.0), Color(0, 0, 0, 0), Color(accent, a), 20.0, 3.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			Sfx.play("click")
			tapped.emit(1 if _con_rect().has_point(event.position) else 0)
