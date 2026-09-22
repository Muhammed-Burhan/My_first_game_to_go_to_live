class_name LoadingScreen
extends Control
## Boot screen. The bar is not a fake: it drives the actual work — synthesizing
## the whole sound bank, baking the UI textures, warming the shaders — one step
## per frame, and reports what it is doing. Shows the crest, a shimmer on the
## wordmark, marching silhouettes and a rotating tip while it works.

signal finished

const W := 1080.0
const H := 1920.0
const MIN_TIME := 2.0     # never blink past; the booth wants to be looked at

var _steps: Array = []
var _step_i: int = 0
var _label := ""
var _progress := 0.0      # smoothed, what the bar shows
var _target := 0.0        # actual completion
var _t := 0.0
var _tip_i := 0
var _tip_t := 0.0
var _tip_fade := 1.0
var _done := false
var _art: Art
var _bar: Bar
var _status: Label
var _tip: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = Config.C_SKY_TOP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_art = Art.new()
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_art)

	_bar = Bar.new()
	_bar.position = Vector2(130, 1420)
	_bar.size = Vector2(820, 56)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	_status = _make_label(34, Config.C_TEXT_DIM, 1490)
	_tip = _make_label(32, Config.C_TEXT, 1700)
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.size = Vector2(880, 120)
	_tip.position.x = 100

	var tip_head := _make_label(26, Config.C_ROCK, 1650)
	tip_head.text = "TIP"

	_tip_i = randi() % Config.TIPS.size()
	_tip.text = Config.TIPS[_tip_i]

	_steps = _build_steps()
	set_process(true)


func _make_label(size: int, col: Color, y: float) -> Label:
	var l := Label.new()
	l.position = Vector2(90, y)
	l.size = Vector2(900, size + 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Every step is [label, work]. They run one per frame so the bar can breathe.
func _build_steps() -> Array:
	var out: Array = []
	out.append(["Waking the watch", func(): pass])
	for i in range(Sfx.step_count()):
		var idx := i
		out.append(["", func(): _label = Sfx.build_step(idx)])
	out.append(["Cutting the stonework", func():
		Gfx.light_texture()
		Gfx.soft_light_texture()
		Gfx.vignette_texture()])
	out.append(["Lighting the torches", func(): Gfx.flash_material()])
	out.append(["Reading the ledger", func():
		Save.load_profile()
		Leaderboard.refresh_remote()])
	out.append(["Opening the gate", func(): pass])
	return out


func _process(delta: float) -> void:
	_t += delta
	_tip_t += delta
	if _tip_t > 4.0:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % Config.TIPS.size()
		_tip_fade = 0.0
		_tip.text = Config.TIPS[_tip_i]
	_tip_fade = minf(1.0, _tip_fade + delta * 3.0)
	_tip.modulate.a = _tip_fade

	# One unit of real work per frame.
	if _step_i < _steps.size():
		var step: Array = _steps[_step_i]
		var declared := str(step[0])
		if declared != "":
			_label = declared
		var work: Callable = step[1]
		work.call()
		_step_i += 1
		_target = float(_step_i) / float(_steps.size())

	_progress = lerpf(_progress, _target, minf(1.0, delta * 6.0))
	_bar.value = _progress
	_bar.queue_redraw()
	_status.text = "%s  ·  %d%%" % [_label, int(round(_progress * 100.0))]

	if not _done and _step_i >= _steps.size() and _progress > 0.995 and _t >= MIN_TIME:
		_done = true
		_finish()


func _finish() -> void:
	_status.text = "READY"
	Sfx.play("star", -4.0)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(self, "modulate:a", 0.0, 0.45)
	tw.tween_callback(func():
		visible = false
		finished.emit())


# ------------------------------------------------------------------ widgets

## The crest, the wordmark with a shimmer, and a marching column of silhouettes.
class Art extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		_draw_sky()
		_draw_skyline()
		_draw_crest(Vector2(540, 560))
		_draw_wordmark()
		_draw_marchers()

	func _draw_sky() -> void:
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(1080, 0), Vector2(1080, 1200), Vector2(0, 1200)]),
			PackedColorArray([Config.C_SKY_TOP, Config.C_SKY_TOP, Config.C_SKY_MID, Config.C_SKY_MID]))
		draw_polygon(
			PackedVector2Array([Vector2(0, 1200), Vector2(1080, 1200), Vector2(1080, 1920), Vector2(0, 1920)]),
			PackedColorArray([Config.C_SKY_MID, Config.C_SKY_MID, Color("0b1020"), Color("0b1020")]))
		# Slow radial god-rays behind the crest
		for i in range(10):
			var a := _t * 0.08 + float(i) / 10.0 * TAU
			var p0 := Vector2(540, 560)
			var p1 := p0 + Vector2(cos(a), sin(a)) * 900.0
			var p2 := p0 + Vector2(cos(a + 0.12), sin(a + 0.12)) * 900.0
			draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(Config.C_ROCK, 0.018))
		for i in range(70):
			var x := fmod(sin(float(i) * 91.7) * 43758.5 , 1.0)
			var y := fmod(sin(float(i) * 13.3) * 24634.1, 1.0)
			var p := Vector2(absf(x) * 1080.0, absf(y) * 1100.0)
			var tw := 0.4 + 0.6 * sin(_t * 1.6 + float(i))
			draw_circle(p, 1.6, Color(Config.C_STAR, 0.35 * tw))

	func _draw_skyline() -> void:
		# A low citadel silhouette sitting on the horizon under the wordmark.
		var y := 1230.0
		draw_rect(Rect2(0, y, 1080, 1920 - y), Color("070c18"))
		var rng := RandomNumberGenerator.new()
		rng.seed = 1258
		var x := 40.0
		while x < 1040.0:
			var w := rng.randf_range(48, 120)
			var h := rng.randf_range(30, 90)
			draw_rect(Rect2(x, y - h, w, h), Color("070c18"))
			var cx := x
			while cx < x + w - 10:
				draw_rect(Rect2(cx, y - h - 12, 14, 12), Color("070c18"))
				cx += 24.0
			# A few lit windows
			if rng.randf() < 0.55:
				var wy := y - h + rng.randf_range(10, maxf(h - 24, 12))
				draw_rect(Rect2(x + w * 0.4, wy, 10, 13), Color(Config.C_FIRE, 0.35 + 0.2 * sin(_t * 2.0 + x)))
			x += w + rng.randf_range(2, 14)

	## Shield crest with the gate arch and crossed weapons.
	func _draw_crest(c: Vector2) -> void:
		var s := 1.0 + 0.02 * sin(_t * 1.6)
		draw_set_transform(c, 0.0, Vector2(s, s))
		Gfx.draw_glow(self, Vector2.ZERO, 230.0, Config.C_ROCK, 0.55, 5)
		# Weapons first: the shield is painted over their lower halves.
		draw_set_transform(c, -0.62, Vector2(s, s))
		_draw_sword()
		draw_set_transform(c, 0.62, Vector2(s, s))
		_draw_spear()
		draw_set_transform(c, 0.0, Vector2(s, s))
		var shield := PackedVector2Array([
			Vector2(-130, -150), Vector2(130, -150), Vector2(130, 10),
			Vector2(0, 165), Vector2(-130, 10),
		])
		draw_colored_polygon(shield, Config.C_SAND_DEEP)
		var inner := PackedVector2Array([
			Vector2(-112, -132), Vector2(112, -132), Vector2(112, 4),
			Vector2(0, 142), Vector2(-112, 4),
		])
		draw_colored_polygon(inner, Config.C_WALL)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-112, -132), Vector2(0, -132), Vector2(0, 142), Vector2(-112, 4),
		]), Color(Config.C_SAND_LIGHT, 0.18))
		# Gate arch
		draw_rect(Rect2(-42, -60, 84, 120), Config.C_WINDOW)
		draw_circle(Vector2(0, -60), 42, Config.C_WINDOW)
		draw_rect(Rect2(-30, -56, 60, 112), Config.C_WOOD_DARK)
		for i in range(3):
			draw_rect(Rect2(-28 + i * 20, -56, 4, 112), Color(Config.C_WOOD, 0.5))
		# Crenellations across the top of the shield
		var cx := -112.0
		while cx < 100.0:
			draw_rect(Rect2(cx, -156, 22, 24), Config.C_SAND_DEEP)
			cx += 38.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Both weapons are long enough that a good span clears the shield rim once
	# they are rotated out to the sides.
	func _draw_sword() -> void:
		draw_rect(Rect2(-10, -308, 20, 226), Config.C_IRON)
		draw_rect(Rect2(-10, -308, 7, 226), Config.C_IRON.lightened(0.45))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-10, -308), Vector2(10, -308), Vector2(0, -340),
		]), Config.C_IRON.lightened(0.3))
		draw_rect(Rect2(-38, -88, 76, 15), Config.C_ROCK)          # crossguard
		draw_rect(Rect2(-7, -73, 14, 42), Config.C_WOOD_DARK)      # grip
		draw_circle(Vector2(0, -28), 10, Config.C_ROCK)            # pommel

	func _draw_spear() -> void:
		draw_rect(Rect2(-7, -300, 14, 278), Config.C_WOOD_DARK)
		draw_rect(Rect2(-7, -300, 4, 278), Color(Config.C_WOOD, 0.8))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-17, -300), Vector2(17, -300), Vector2(0, -348),
		]), Config.C_IRON)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-17, -300), Vector2(0, -300), Vector2(0, -348),
		]), Config.C_IRON.lightened(0.4))
		draw_rect(Rect2(-12, -298, 24, 11), Config.C_ROCK)

	func _draw_wordmark() -> void:
		var font := ThemeDB.fallback_font
		var y := 880.0
		for line in [["CITADEL", 128, y], ["DEFENSE", 128, y + 118]]:
			var text: String = line[0]
			var fs: int = line[1]
			var ly: float = line[2]
			draw_string_outline(font, Vector2(0, ly + 6), text, HORIZONTAL_ALIGNMENT_CENTER, 1080, fs, 22, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(0, ly), text, HORIZONTAL_ALIGNMENT_CENTER, 1080, fs, Config.C_SAND_LIGHT)
		# Shimmer: a bright band sweeping left to right across the wordmark.
		var sweep := fmod(_t * 0.45, 2.2) / 2.2
		var sx := lerpf(-220.0, 1300.0, sweep)
		for i in range(7):
			var k := float(i) / 6.0
			var w := 26.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx + k * 120 - w, y - 100), Vector2(sx + k * 120 + w, y - 100),
				Vector2(sx + k * 120 + w - 70, y + 150), Vector2(sx + k * 120 - w - 70, y + 150),
			]), Color(1, 1, 1, 0.05 * (1.0 - absf(k - 0.5) * 2.0)))
		var sub := "ERBIL  ·  1258  ·  HOLD THE GATE"
		draw_string_outline(font, Vector2(0, y + 190), sub, HORIZONTAL_ALIGNMENT_CENTER, 1080, 38, 8, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(0, y + 190), sub, HORIZONTAL_ALIGNMENT_CENTER, 1080, 38, Config.C_ROCK)

	## A column of tiny attackers crossing the bottom of the screen.
	func _draw_marchers() -> void:
		var y := 1268.0
		for i in range(16):
			var speed := 34.0 + float(i % 3) * 7.0
			var x := fmod(_t * speed + float(i) * 95.0, 1260.0) - 90.0
			var bob := sin(_t * 7.0 + float(i)) * 2.0
			var col := Color("05070f")
			draw_circle(Vector2(x, y - 14 + bob), 7, col)
			draw_circle(Vector2(x, y - 26 + bob), 5, col)
			var s := sin(_t * 7.0 + float(i)) * 4.0
			draw_line(Vector2(x - 2, y - 8 + bob), Vector2(x - 2 + s, y), col, 3.0)
			draw_line(Vector2(x + 2, y - 8 + bob), Vector2(x + 2 - s, y), col, 3.0)
			if i % 3 == 0:
				draw_line(Vector2(x + 6, y - 30 + bob), Vector2(x + 10, y - 2 + bob), col, 2.5)


## Segmented gold progress bar with a moving sheen.
class Bar extends Control:
	var value := 0.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta

	func _draw() -> void:
		var r := size.y * 0.5
		# Track
		Gfx.draw_bar(self, Rect2(Vector2.ZERO, size), 0.0, Color(0.02, 0.03, 0.07, 0.9), Config.C_ROCK, false)
		draw_arc(Vector2(r, r), r, PI * 0.5, PI * 1.5, 20, Color(Config.C_UI_LINE, 0.7), 3.0)
		draw_arc(Vector2(size.x - r, r), r, -PI * 0.5, PI * 0.5, 20, Color(Config.C_UI_LINE, 0.7), 3.0)
		draw_line(Vector2(r, 1.5), Vector2(size.x - r, 1.5), Color(Config.C_UI_LINE, 0.7), 3.0)
		draw_line(Vector2(r, size.y - 1.5), Vector2(size.x - r, size.y - 1.5), Color(Config.C_UI_LINE, 0.7), 3.0)
		# Fill
		if value > 0.002:
			var inner := Rect2(Vector2(4, 4), Vector2(maxf((size.x - 8) * value, size.y - 8), size.y - 8))
			Gfx.draw_bar(self, inner, 1.0, Color(0, 0, 0, 0), Config.C_ROCK)
			# Sheen travelling along the filled part
			var sx := fmod(_t * 320.0, maxf(inner.size.x, 1.0))
			draw_rect(Rect2(inner.position.x + sx - 14, inner.position.y, 28, inner.size.y), Color(1, 1, 1, 0.16))
		# Tick marks every 10%
		for i in range(1, 10):
			var x := size.x * float(i) / 10.0
			draw_line(Vector2(x, 8), Vector2(x, size.y - 8), Color(0, 0, 0, 0.28), 2.0)
