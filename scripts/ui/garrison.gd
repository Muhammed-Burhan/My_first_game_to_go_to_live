class_name Garrison
extends Control
## The progression screen: who you are taking into the siege, what today is
## asking of you, and what is still locked. Opened from the title strip.
##
## Three tabs rather than one long scroll, because on a phone a scroll hides
## exactly the thing this screen exists to show: that there is more.

signal closed

const W := 1080.0

var _tab := 0
var _tabs: Array[TabButton] = []
var _body: Body
var _close: Button
var _header: Header


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.03, 0.07, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_header = Header.new()
	_header.position = Vector2(50, 60)
	_header.size = Vector2(980, 240)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)

	var labels := ["COMMANDERS", "CONTRACTS", "UNLOCKS"]
	for i in range(labels.size()):
		var t := TabButton.new()
		t.label = labels[i]
		t.index = i
		t.position = Vector2(50 + i * 328, 322)
		t.size = Vector2(312, 92)
		t.chosen.connect(_select_tab)
		add_child(t)
		_tabs.append(t)

	_body = Body.new()
	_body.position = Vector2(50, 442)
	_body.size = Vector2(980, 1290)
	_body.changed.connect(refresh)
	add_child(_body)

	_close = Button.new()
	_close.text = "BACK"
	_close.position = Vector2(340, 1764)
	_close.size = Vector2(400, 110)
	_close.pressed.connect(func():
		Sfx.play("back")
		close())
	add_child(_close)
	UiTheme.add_press_feel(_close)


func open(tab: int = 0) -> void:
	visible = true
	_select_tab(tab)
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.18)


func close() -> void:
	visible = false
	closed.emit()


func _select_tab(i: int) -> void:
	_tab = i
	for t in _tabs:
		t.active = t.index == i
		t.queue_redraw()
	refresh()


func refresh() -> void:
	_body.tab = _tab
	_body.rebuild()
	_header.queue_redraw()


# ------------------------------------------------------------------ header

## Level, renown bar and the next thing worth playing for.
class Header extends Control:
	func _draw() -> void:
		Gfx.draw_text(self, Vector2(0, 74), "THE GARRISON", 62, Config.C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Fonts.display(6))
		RenownBar.draw_into(self, Rect2(40, 116, size.x - 80, 96), true)


# ------------------------------------------------------------------ tabs

class TabButton extends Control:
	signal chosen(index: int)
	var label := ""
	var index := 0
	var active := false
	var _box_on: StyleBoxTexture
	var _box_off: StyleBoxTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_box_on = Gfx.gradient_box(Color("3d3112"), Color("1a1408"), Config.C_ROCK, 3.0, 18.0)
		_box_off = Gfx.gradient_box(Color("141c30"), Color("0a1020"), Color(Config.C_UI_LINE, 0.28), 2.0, 18.0)

	func _draw() -> void:
		draw_style_box(_box_on if active else _box_off, Rect2(Vector2.ZERO, size))
		Gfx.draw_text(self, Vector2(0, size.y * 0.5 + 12), label, 30,
			Config.C_ROCK if active else Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 6,
			Fonts.ui(Fonts.W_BLACK, 2))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			Sfx.play("click")
			chosen.emit(index)


# ------------------------------------------------------------------ body

## Holds whichever tab's rows are current. Rows are built as child controls so
## each one can take its own taps.
class Body extends Control:
	signal changed
	var tab := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func rebuild() -> void:
		for c in get_children():
			c.queue_free()
		match tab:
			0:
				_build_commanders()
			1:
				_build_contracts()
			_:
				_build_unlocks()
		queue_redraw()

	func _build_commanders() -> void:
		var y := 0.0
		for c in Meta.COMMANDERS:
			var row := CommanderRow.new()
			row.data = c
			row.position = Vector2(0, y)
			row.size = Vector2(size.x, 196)
			row.picked.connect(func():
				changed.emit())
			add_child(row)
			y += 210.0

	func _build_contracts() -> void:
		var y := 0.0
		for c in Meta.contracts():
			var row := ContractRow.new()
			row.data = c
			row.position = Vector2(0, y)
			row.size = Vector2(size.x, 168)
			add_child(row)
			y += 184.0
		var note := Note.new()
		note.position = Vector2(0, y + 24)
		note.size = Vector2(size.x, 200)
		add_child(note)

	func _build_unlocks() -> void:
		var y := 0.0
		for lv in range(2, Meta.LEVEL_CAP + 1):
			var items := Meta.unlocks_at(lv)
			if items.is_empty():
				continue
			for item in items:
				var row := UnlockRow.new()
				row.item = item
				row.level = lv
				row.position = Vector2(0, y)
				row.size = Vector2(size.x, 100)
				add_child(row)
				y += 108.0


## The line under the contract list: what this is and when it turns over.
class Note extends Control:
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if _t > 0.5:
			_t = 0.0
			queue_redraw()

	func _draw() -> void:
		var now := Time.get_datetime_dict_from_system(true)
		var left := 86400 - (int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"]))
		Gfx.draw_text(self, Vector2(0, 40), "THREE NEW CONTRACTS IN  %02d:%02d:%02d" % [
			left / 3600, (left % 3600) / 60, left % 60], 28, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 6, Fonts.ui(Fonts.W_BOLD, 3))
		Gfx.draw_text(self, Vector2(0, 92), "Everyone playing today gets the same three.",
			26, Color(Config.C_TEXT_DIM, 0.7), HORIZONTAL_ALIGNMENT_CENTER, size.x, 5,
			Fonts.ui(Fonts.W_MED))


# ------------------------------------------------------------------ rows

class CommanderRow extends Control:
	signal picked
	var data: Dictionary = {}
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		set_process(true)

	func _process(delta: float) -> void:
		_t += delta
		if selected():
			queue_redraw()

	func unlocked() -> bool:
		return Meta.level() >= int(data["level"])

	func selected() -> bool:
		return Meta.commander == str(data["id"])

	func _draw() -> void:
		var open := unlocked()
		var on := selected()
		var col: Color = data["color"]
		var rect := Rect2(Vector2.ZERO, size)
		var rim: Color = col if on else (Color(Config.C_UI_LINE, 0.3) if open else Color(0.3, 0.32, 0.38, 0.35))
		if on:
			Gfx.draw_glow(self, size / 2.0, size.x * 0.4, col, 0.20 + 0.08 * sin(_t * 2.2), 4)
		Gfx.draw_panel(self, rect, Color(0.055, 0.08, 0.15, 0.95) if open else Color(0.03, 0.035, 0.055, 0.9),
			rim, 22.0, 4.0 if on else 2.0)
		# Portrait medallion
		var c := Vector2(104, size.y * 0.5)
		draw_circle(c, 62, Color(col, 0.13 if open else 0.05))
		draw_arc(c, 62, 0, TAU, 40, Color(col, 0.55 if open else 0.2), 3.0)
		if open:
			DraftScreen.draw_boon_art(self, c, str(data["art"]), 0.44, _t)
		else:
			_draw_padlock(c)
		var tint: Color = Config.C_TEXT if open else Color(Config.C_TEXT_DIM, 0.55)
		Gfx.draw_text(self, Vector2(196, 62), str(data["title"]), 40, tint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
		if open:
			Gfx.draw_text(self, Vector2(198, 104), str(data["blurb"]), 26, Color(col, 0.95),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_MED))
			Gfx.draw_text(self, Vector2(198, 142), str(data["cost"]), 25, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_MED))
		else:
			Gfx.draw_text(self, Vector2(198, 108), "Unlocks at level %d" % int(data["level"]),
				28, Config.C_ROCK, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_BOLD))
			Gfx.draw_text(self, Vector2(198, 148), "%d more renown" % maxi(
				Meta.renown_for_level(int(data["level"])) - Meta.renown(), 0),
				24, Color(Config.C_TEXT_DIM, 0.75), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_MED))
		if on:
			var tag := Rect2(size.x - 196, 22, 168, 48)
			Gfx.draw_panel(self, tag, Color(col, 0.22), Color(col, 0.8), 14.0, 2.0)
			Gfx.draw_text(self, Vector2(tag.position.x, 56), "LEADING", 26, col,
				HORIZONTAL_ALIGNMENT_CENTER, tag.size.x, 5, Fonts.ui(Fonts.W_BLACK, 2))

	func _draw_padlock(c: Vector2) -> void:
		var col := Color(0.55, 0.58, 0.66, 0.7)
		draw_arc(c + Vector2(0, -12), 15, PI, TAU, 18, col, 6.0)
		draw_rect(Rect2(c.x - 22, c.y - 6, 44, 34), col)
		draw_circle(c + Vector2(0, 8), 5, Color(0.1, 0.11, 0.15, 0.9))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			accept_event()
			if not unlocked():
				Sfx.play("deny")
				return
			if Meta.set_commander(str(data["id"])):
				Sfx.play("upgrade")
				picked.emit()


class ContractRow extends Control:
	var data: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var done: bool = bool(data["done"])
		var accent: Color = Config.C_GOOD if done else Config.C_ROCK
		Gfx.draw_panel(self, Rect2(Vector2.ZERO, size), Color(0.055, 0.08, 0.15, 0.95),
			Color(accent, 0.5 if done else 0.3), 22.0, 2.0)
		Gfx.draw_text(self, Vector2(36, 58), str(data["text"]), 32,
			Config.C_TEXT_DIM if done else Config.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		var bar := Rect2(36, 82, size.x - 250, 26)
		var frac := float(data["progress"]) / maxf(float(data["target"]), 1.0)
		Gfx.draw_bar(self, bar, frac, Color(0, 0, 0, 0.5), accent)
		Gfx.draw_text(self, Vector2(36, 142), "%d / %d" % [int(data["progress"]), int(data["target"])],
			26, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_BOLD))
		# Reward, or a tick once it is paid.
		var rx := size.x - 170.0
		if done:
			draw_circle(Vector2(rx + 60, 84), 38, Color(Config.C_GOOD, 0.18))
			var p := Vector2(rx + 60, 84)
			draw_line(p + Vector2(-18, 0), p + Vector2(-5, 14), Config.C_GOOD, 7.0)
			draw_line(p + Vector2(-5, 14), p + Vector2(19, -14), Config.C_GOOD, 7.0)
			Gfx.draw_text(self, Vector2(rx, 142), "CLAIMED", 24, Config.C_GOOD,
				HORIZONTAL_ALIGNMENT_CENTER, 120, 5, Fonts.ui(Fonts.W_BLACK, 2))
		else:
			Gfx.draw_text(self, Vector2(rx, 84), "+%d" % int(data["renown"]), 46, Config.C_ROCK,
				HORIZONTAL_ALIGNMENT_CENTER, 120, 7)
			Gfx.draw_text(self, Vector2(rx, 122), "RENOWN", 22, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, 120, 5, Fonts.ui(Fonts.W_BLACK, 2))


class UnlockRow extends Control:
	var item: Dictionary = {}
	var level := 2

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var have := Meta.level() >= level
		var col: Color = item["color"]
		Gfx.draw_panel(self, Rect2(Vector2.ZERO, size),
			Color(0.055, 0.08, 0.15, 0.9) if have else Color(0.03, 0.035, 0.055, 0.85),
			Color(col, 0.55 if have else 0.18), 20.0, 2.0)
		# Level chip
		var chip := Rect2(20, 20, 100, 60)
		Gfx.draw_panel(self, chip, Color(col, 0.2 if have else 0.07), Color(col, 0.6 if have else 0.2), 14.0, 2.0)
		Gfx.draw_text(self, Vector2(chip.position.x, 62), "LV %d" % level, 30,
			col if have else Color(col, 0.45), HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 6)
		var tint: Color = Config.C_TEXT if have else Color(Config.C_TEXT_DIM, 0.5)
		var text_w := size.x - 380.0
		var body_font := Fonts.ui(Fonts.W_MED)
		Gfx.draw_text(self, Vector2(144, 46), Gfx.fit_text(str(item["name"]), 30, text_w), 30, tint,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 6)
		Gfx.draw_text(self, Vector2(146, 80), Gfx.fit_text(str(item["desc"]), 23, text_w, body_font), 23,
			Color(Config.C_TEXT_DIM, 1.0 if have else 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, 5, body_font)
		Gfx.draw_text(self, Vector2(size.x - 244, 56), str(item["kind"]), 21,
			Color(col, 0.9 if have else 0.35), HORIZONTAL_ALIGNMENT_RIGHT, 224, 5,
			Fonts.ui(Fonts.W_BLACK, 2))
