class_name DraftScreen
extends Control
## Between waves: three boons, take one. This is the roguelite beat — the thing
## that makes two runs of the same seed diverge, and the thing a player actually
## recounts afterwards. Runs with the tree paused, like the pause menu.

signal chosen(boon: Dictionary)

const CARD_W := 330.0
const CARD_H := 760.0
const CARD_Y := 560.0

var _cards: Array[BoonCard] = []
var _title: Label
var _sub: Label
var _taken_strip: TakenStrip


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_title = _label("CHOOSE A BOON", 78, 300, Config.C_ROCK)
	_sub = _label("", 34, 400, Config.C_TEXT_DIM)

	_taken_strip = TakenStrip.new()
	_taken_strip.position = Vector2(60, 1400)
	_taken_strip.size = Vector2(960, 160)
	_taken_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_taken_strip)


func _label(text: String, size: int, y: float, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 12)
	l.position = Vector2(40, y)
	l.size = Vector2(1000, size + 30)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func open(wave: int, offers: Array) -> void:
	for c in _cards:
		c.queue_free()
	_cards.clear()
	if offers.is_empty():
		chosen.emit({})
		return
	_sub.text = "Wave %d held  ·  the spoils are yours" % wave
	visible = true
	modulate.a = 0.0
	var start_x := (1080.0 - (offers.size() * CARD_W + (offers.size() - 1) * 30.0)) * 0.5
	for i in range(offers.size()):
		var card := BoonCard.new()
		card.boon = offers[i]
		card.position = Vector2(start_x + i * (CARD_W + 30.0), CARD_Y)
		card.size = Vector2(CARD_W, CARD_H)
		card.picked.connect(_on_pick)
		add_child(card)
		_cards.append(card)
		# Deal them in one at a time, like cards off a deck.
		card.pivot_offset = card.size / 2.0
		card.scale = Vector2(0.6, 0.6)
		card.rotation = randf_range(-0.14, 0.14)
		card.modulate.a = 0.0
		var t := card.create_tween()
		t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		t.tween_interval(0.09 * i)
		t.tween_property(card, "modulate:a", 1.0, 0.16)
		t.parallel().tween_property(card, "scale", Vector2.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(card, "rotation", 0.0, 0.34)
	_taken_strip.refresh()
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.2)
	Sfx.play("draft", -4.0)


func _on_pick(boon: Dictionary) -> void:
	if not visible:
		return
	Sfx.play("curse" if int(boon["rarity"]) == Boons.Rarity.CURSED else "pick", -2.0)
	for c in _cards:
		if c.boon != boon:
			var t := c.create_tween()
			t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			t.tween_property(c, "modulate:a", 0.0, 0.18)
			t.parallel().tween_property(c, "scale", Vector2(0.85, 0.85), 0.18)
		else:
			c.pivot_offset = c.size / 2.0
			var t2 := c.create_tween()
			t2.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
			t2.tween_property(c, "scale", Vector2(1.12, 1.12), 0.14).set_trans(Tween.TRANS_BACK)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.34)
	tw.tween_property(self, "modulate:a", 0.0, 0.22)
	tw.tween_callback(func():
		visible = false
		chosen.emit(boon))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()


# ------------------------------------------------------------------ widgets

## One draftable boon, drawn entirely in code so rarity reads at a glance.
class BoonCard extends Control:
	signal picked(boon: Dictionary)

	var boon: Dictionary = {}
	var _t := 0.0
	var _down := false
	var _box: StyleBoxTexture
	var _art_box: StyleBoxTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_t = randf() * 3.0
		var rim: Color = Boons.RARITY_COLOR[int(boon["rarity"])]
		var cursed := int(boon["rarity"]) == Boons.Rarity.CURSED
		_box = Gfx.gradient_box(
			Color("2a1620") if cursed else Color("1c2b4a"),
			Color("140a10") if cursed else Color("0a1022"), rim, 4.0, 28.0)
		_art_box = Gfx.gradient_box(Color(0.02, 0.03, 0.07, 0.9), Color(0.05, 0.07, 0.13, 0.9),
			Color(rim, 0.45), 2.0, 20.0)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if event.pressed:
				_down = true
			elif _down:
				_down = false
				picked.emit(boon)

	func _draw() -> void:
		var rarity := int(boon["rarity"])
		var rim: Color = Boons.RARITY_COLOR[rarity]
		var pulse := 0.5 + 0.5 * sin(_t * 2.0)
		# Rarer cards glow harder. Cursed ones throb.
		var glow := 0.22 + 0.10 * float(rarity) + (0.18 * pulse if rarity >= Boons.Rarity.EPIC else 0.05 * pulse)
		Gfx.draw_glow(self, size / 2.0, size.x * 0.85, rim, glow, 4)
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		# Rarity ribbon
		var ribbon := Rect2(0, 22, size.x, 46)
		draw_rect(ribbon, Color(rim, 0.22))
		draw_line(Vector2(0, 22), Vector2(size.x, 22), Color(rim, 0.8), 3.0)
		draw_line(Vector2(0, 68), Vector2(size.x, 68), Color(rim, 0.8), 3.0)
		Gfx.draw_text(self, Vector2(0, 56), str(Boons.RARITY_NAME[rarity]), 28, rim,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 6)
		# Art well
		var art := Rect2(30, 96, size.x - 60, 250)
		draw_style_box(_art_box, art)
		DraftScreen.draw_boon_art(self, art.position + art.size / 2.0, str(boon.get("art", "star")), 1.0, _t)
		# Name
		Gfx.draw_text(self, Vector2(0, 408), str(boon["name"]), 42, Config.C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 8)
		# Body text, wrapped by hand so it sits where we want it
		var font := ThemeDB.fallback_font
		var words := str(boon["text"]).split(" ")
		var line := ""
		var y := 470.0
		for w in words:
			var probe := line + (" " if line != "" else "") + w
			if font.get_string_size(probe, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x > size.x - 56:
				Gfx.draw_text(self, Vector2(0, y), line, 28, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
				y += 36.0
				line = w
			else:
				line = probe
		if line != "":
			Gfx.draw_text(self, Vector2(0, y), line, 28, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		# Stack counter, so repeat picks read as stacking
		var have := Boons.count_taken(str(boon["id"]))
		if have > 0:
			Gfx.draw_text(self, Vector2(0, size.y - 96), "ALREADY x%d" % have, 24, Color(rim, 0.9),
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		var cta := "TAKE THE RISK" if rarity == Boons.Rarity.CURSED else "TAKE"
		var cta_col: Color = Config.C_THREAT if rarity == Boons.Rarity.CURSED else Config.C_ROCK
		Gfx.draw_text(self, Vector2(0, size.y - 40), cta, 32, Color(cta_col, 0.65 + 0.35 * pulse),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 6)


## The boons already drafted this run, as a row of small badges.
class TakenStrip extends Control:
	func refresh() -> void:
		queue_redraw()

	func _draw() -> void:
		if Boons.taken.is_empty():
			Gfx.draw_text(self, Vector2(0, 60), "No boons yet.", 26, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
			return
		Gfx.draw_text(self, Vector2(0, 34), "THIS RUN", 24, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		var n := Boons.taken.size()
		var step: float = minf(84.0, (size.x - 40.0) / maxf(float(n), 1.0))
		var start := (size.x - step * (n - 1)) * 0.5
		for i in range(n):
			var b := Boons.by_id(Boons.taken[i])
			if b.is_empty():
				continue
			var c := Vector2(start + i * step, 100)
			var rim: Color = Boons.RARITY_COLOR[int(b["rarity"])]
			draw_circle(c + Vector2(0, 3), 30, Color(0, 0, 0, 0.45))
			draw_circle(c, 28, Color(0.05, 0.07, 0.13, 0.95))
			draw_arc(c, 27, 0, TAU, 28, rim, 3.0)
			DraftScreen.draw_boon_art(self, c, str(b.get("art", "star")), 0.36, 0.0)


## Shared icon set, used by the cards, the strip and the share card.
static func draw_boon_art(ci: CanvasItem, c: Vector2, art: String, s: float = 1.0, t: float = 0.0) -> void:
	ci.draw_set_transform(c, 0.0, Vector2(s, s))
	match art:
		"arrow":
			ci.draw_line(Vector2(-70, 40), Vector2(50, -40), Config.C_WOOD, 9.0)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(50, -40), Vector2(78, -58), Vector2(62, -22)]), Config.C_IRON)
			ci.draw_line(Vector2(-70, 40), Vector2(-44, 44), Config.C_SAND_LIGHT, 7.0)
			ci.draw_line(Vector2(-70, 40), Vector2(-66, 66), Config.C_SAND_LIGHT, 7.0)
		"range":
			for i in range(3):
				ci.draw_arc(Vector2.ZERO, 30.0 + i * 24.0, 0, TAU, 40, Color(Config.C_ROCK, 0.85 - i * 0.22), 6.0)
			ci.draw_circle(Vector2.ZERO, 14, Config.C_ROCK)
		"rate":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(14, -76), Vector2(-34, 8), Vector2(-2, 8),
				Vector2(-14, 76), Vector2(36, -12), Vector2(4, -12)]), Config.C_FIRE_HOT)
		"splash":
			ci.draw_circle(Vector2.ZERO, 54, Color(Config.C_FIRE, 0.3))
			ci.draw_colored_polygon(Gfx.star_points(Vector2.ZERO, 66, 26, 8, t * 0.4), Config.C_FIRE)
			ci.draw_circle(Vector2.ZERO, 22, Config.C_FIRE_HOT)
		"coin":
			for i in range(3):
				var o := Vector2(-22 + i * 22, 24 - i * 22)
				ci.draw_circle(o + Vector2(0, 4), 30, Color(0, 0, 0, 0.35))
				ci.draw_circle(o, 28, Config.C_ROCK.darkened(0.3))
				ci.draw_circle(o, 22, Config.C_ROCK)
				ci.draw_circle(o + Vector2(-6, -6), 8, Config.C_FIRE_HOT)
		"pierce":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-10, 64), Vector2(10, 64), Vector2(10, -30), Vector2(0, -70), Vector2(-10, -30)]),
				Config.C_IRON)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-10, -30), Vector2(0, -70), Vector2(0, 64), Vector2(-10, 64)]),
				Config.C_IRON.lightened(0.4))
			ci.draw_rect(Rect2(-34, 30, 68, 12), Config.C_ROCK)
		"spear":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-46, -54), Vector2(46, -54), Vector2(46, 10), Vector2(0, 66), Vector2(-46, 10)]),
				Config.C_GOOD.darkened(0.25))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-34, -42), Vector2(34, -42), Vector2(34, 6), Vector2(0, 50), Vector2(-34, 6)]),
				Config.C_GOOD)
			ci.draw_line(Vector2(0, -70), Vector2(0, 40), Config.C_WOOD, 7.0)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-12, -60), Vector2(12, -60), Vector2(0, -88)]), Config.C_IRON)
		"fire":
			for i in range(3):
				var k := float(i) / 3.0
				var w := 56.0 * (1.0 - k * 0.45)
				var h := 84.0 * (1.0 - k * 0.4)
				var col: Color = [Config.C_THREAT, Config.C_FIRE, Config.C_FIRE_HOT][i]
				ci.draw_colored_polygon(PackedVector2Array([
					Vector2(-w * 0.5, 56 - k * 14), Vector2(0, 56 - h - k * 10),
					Vector2(w * 0.5, 56 - k * 14), Vector2(0, 70 - k * 20)]), col)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-56, -58), Vector2(56, -58), Vector2(56, 8), Vector2(0, 74), Vector2(-56, 8)]),
				Config.C_IRON_DARK)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-42, -44), Vector2(42, -44), Vector2(42, 2), Vector2(0, 56), Vector2(-42, 2)]),
				Config.C_IRON)
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-42, -44), Vector2(0, -44), Vector2(0, 56), Vector2(-42, 2)]),
				Color(1, 1, 1, 0.16))
		"stone":
			ci.draw_circle(Vector2(4, 10), 56, Color(0, 0, 0, 0.3))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-58, 20), Vector2(-36, -46), Vector2(24, -60),
				Vector2(60, -14), Vector2(44, 48), Vector2(-20, 58)]), Color("8a8580"))
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(-36, -46), Vector2(24, -60), Vector2(32, -8), Vector2(-24, 0)]), Color("aaa49d"))
		"drum":
			ci.draw_circle(Vector2(0, 6), 58, Config.C_WOOD_DARK)
			ci.draw_circle(Vector2.ZERO, 54, Color("c8ab84"))
			ci.draw_arc(Vector2.ZERO, 54, 0, TAU, 36, Config.C_WOOD_DARK, 5.0)
			ci.draw_line(Vector2(-70, -46), Vector2(-16, -8), Config.C_WOOD, 7.0)
			ci.draw_line(Vector2(72, -40), Vector2(20, -6), Config.C_WOOD, 7.0)
		"crit":
			ci.draw_line(Vector2(-52, 54), Vector2(46, -50), Config.C_IRON, 12.0)
			ci.draw_line(Vector2(52, 54), Vector2(-46, -50), Config.C_IRON, 12.0)
			ci.draw_line(Vector2(-52, 54), Vector2(-30, 34), Config.C_ROCK, 14.0)
			ci.draw_line(Vector2(52, 54), Vector2(30, 34), Config.C_ROCK, 14.0)
			ci.draw_colored_polygon(Gfx.star_points(Vector2(0, -6), 30, 12, 4, 0.0), Config.C_FIRE_HOT)
		"gate":
			ci.draw_rect(Rect2(-56, -40, 112, 100), Config.C_WALL)
			ci.draw_circle(Vector2(0, -40), 56, Config.C_WALL)
			ci.draw_rect(Rect2(-34, -34, 68, 94), Config.C_WOOD_DARK)
			ci.draw_circle(Vector2(0, -34), 34, Config.C_WOOD_DARK)
			for i in range(3):
				ci.draw_rect(Rect2(-30 + i * 22, -34, 5, 94), Color(Config.C_WOOD, 0.6))
			ci.draw_rect(Rect2(-34, -6, 68, 9), Config.C_IRON)
		_:
			ci.draw_colored_polygon(Gfx.star_points(Vector2.ZERO, 66, 28, 5, 0.0), Config.C_ROCK)
			ci.draw_colored_polygon(Gfx.star_points(Vector2(0, -8), 32, 14, 5, 0.0), Config.C_FIRE_HOT)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
