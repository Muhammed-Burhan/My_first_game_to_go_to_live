class_name Hud
extends Control
## In-game overlay: rock, lives, wave, speed, pause, the next-wave preview and
## the Start button, plus the wave-announce banner and the kill-streak meter.
## Reads Game signals and the level's phase every frame.

var level: Level
var _bar: TopBar
var _rock_label: Label
var _wave_label: Label
var _tier_label: Label
var _lives: LivesIcons
var _auto_btn: Button
var _speed_btn: Button
var _pause_btn: Button
var _start_btn: Button
var _repair_btn: Button
var _preview: WavePreview
var _progress: WaveProgress
var _combo: ComboMeter
var _heat: HeatMeter
var _banner: WaveBanner
var _hint: Label
var _hint_time: float = 0.0
var _rock_pop: float = 0.0
var _shown_rock: float = 0.0
var _last_countdown: int = -1

signal pause_requested


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bar = TopBar.new()
	_bar.position = Vector2(20, 20)
	_bar.size = Vector2(1040, 152)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	var rock_icon := RockIcon.new()
	rock_icon.position = Vector2(78, 68)
	add_child(rock_icon)
	_rock_label = _label("150", 50, Vector2(114, 40), Config.C_ROCK)
	_rock_label.size = Vector2(160, 56)
	add_child(_rock_label)

	_wave_label = _label("WAVE 1/10", 40, Vector2(396, 30), Config.C_TEXT)
	_wave_label.size = Vector2(288, 46)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_wave_label)

	_tier_label = _label("", 22, Vector2(396, 76), Config.C_ROCK)
	_tier_label.size = Vector2(288, 30)
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tier_label)

	# AUTO hands the gatehouse repeater to the game while both hands are busy
	# building. It is the weaker option on purpose (see commander.gd), so it
	# sits beside the speed toggle as a convenience, not above it.
	_auto_btn = Button.new()
	_auto_btn.text = "AUTO"
	_auto_btn.position = Vector2(788, 24)
	_auto_btn.size = Vector2(84, 84)
	_auto_btn.add_theme_font_size_override("font_size", 24)
	_auto_btn.pressed.connect(_on_auto)
	add_child(_auto_btn)
	UiTheme.add_press_feel(_auto_btn)
	UiTheme.make_compact(_auto_btn)

	_speed_btn = Button.new()
	_speed_btn.text = "1x"
	_speed_btn.position = Vector2(880, 24)
	_speed_btn.size = Vector2(84, 84)
	_speed_btn.add_theme_font_size_override("font_size", 36)
	_speed_btn.pressed.connect(_on_speed)
	add_child(_speed_btn)
	UiTheme.add_press_feel(_speed_btn)
	UiTheme.make_compact(_speed_btn)

	_pause_btn = Button.new()
	_pause_btn.text = "❚❚"
	_pause_btn.position = Vector2(972, 24)
	_pause_btn.size = Vector2(84, 84)
	_pause_btn.add_theme_font_size_override("font_size", 30)
	_pause_btn.pressed.connect(func():
		Sfx.play("click")
		pause_requested.emit())
	add_child(_pause_btn)
	UiTheme.add_press_feel(_pause_btn)
	UiTheme.make_compact(_pause_btn)

	# Second row: lives on the left, the wave's progress taking the rest. Both
	# used to be crammed into the same band as the counters.
	_lives = LivesIcons.new()
	_lives.position = Vector2(24, 118)
	_lives.size = Vector2(230, 46)
	add_child(_lives)

	_progress = WaveProgress.new()
	_progress.position = Vector2(268, 130)
	_progress.size = Vector2(788, 22)
	_progress.visible = false
	add_child(_progress)

	_preview = WavePreview.new()
	_preview.position = Vector2(40, 200)
	_preview.size = Vector2(620, 90)
	add_child(_preview)

	_start_btn = Button.new()
	_start_btn.text = "START"
	_start_btn.position = Vector2(700, 196)
	_start_btn.size = Vector2(350, 100)
	_start_btn.pressed.connect(_on_start)
	add_child(_start_btn)
	UiTheme.make_primary(_start_btn)
	UiTheme.add_press_feel(_start_btn)

	_repair_btn = Button.new()
	_repair_btn.position = Vector2(40, 310)
	_repair_btn.size = Vector2(420, 92)
	_repair_btn.add_theme_font_size_override("font_size", 32)
	_repair_btn.visible = false
	_repair_btn.pressed.connect(_on_repair)
	add_child(_repair_btn)
	UiTheme.add_press_feel(_repair_btn)

	_heat = HeatMeter.new()
	_heat.position = Vector2(210, 1780)
	_heat.size = Vector2(660, 74)
	_heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heat)

	_combo = ComboMeter.new()
	_combo.position = Vector2(660, 1660)
	_combo.size = Vector2(380, 120)
	add_child(_combo)

	_banner = WaveBanner.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)

	_hint = _label("Tap a stone plinth to build a tower", 38, Vector2(40, 1800), Config.C_TEXT)
	_hint.size = Vector2(1000, 60)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)

	Game.rock_changed.connect(_on_rock)
	Game.lives_changed.connect(_on_lives)
	Game.wave_changed.connect(_on_wave)
	Game.speed_changed.connect(_on_speed_changed)
	Game.combo_changed.connect(func(c): _combo.set_combo(c))


func bind(lvl: Level) -> void:
	level = lvl
	# Carry the preference across runs: someone who plays on AUTO wants it on
	# next time, not to rediscover the button every launch.
	if lvl.commander != null:
		lvl.commander.auto = bool(Save.data.get("commander_auto", false))
	_refresh_auto()
	level.phase_changed.connect(_on_phase)
	level.wave_started.connect(_on_wave_started)
	level.milestone.connect(_on_milestone)


func _label(text: String, size: int, pos: Vector2, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _process(delta: float) -> void:
	if level == null:
		return
	# The rock counter rolls toward its value instead of snapping.
	if absf(_shown_rock - Game.rock) > 0.5:
		_shown_rock = lerpf(_shown_rock, float(Game.rock), minf(1.0, delta * 9.0))
		_rock_label.text = str(int(round(_shown_rock)))
	if _rock_pop > 0.0:
		_rock_pop = maxf(0.0, _rock_pop - delta * 4.0)
		_rock_label.scale = Vector2.ONE * (1.0 + 0.18 * _rock_pop)
	match level.phase:
		"prep":
			_heat.visible = false
			var secs := int(ceil(level.prep_left))
			_start_btn.text = "START  %d" % secs
			_start_btn.visible = true
			_preview.visible = true
			_progress.visible = false
			_preview.wave = level.next_wave
			_preview.queue_redraw()
			if secs != _last_countdown and secs <= 3 and secs > 0:
				_last_countdown = secs
				Sfx.play("countdown", -14.0)
			_update_repair()
			_update_hint(delta)
		"wave":
			_heat.visible = true
			if level.commander != null:
				_heat.heat = level.commander.heat
				_heat.locked = level.commander.locked > 0.0
				_heat.auto = level.commander.auto
				_heat.queue_redraw()
			_last_countdown = -1
			_start_btn.visible = false
			_preview.visible = false
			_repair_btn.visible = false
			_hint.visible = false
			_progress.visible = true
			_progress.value = level.wave_progress()
			_progress.queue_redraw()
		_:
			_heat.visible = false
			_start_btn.visible = false
			_preview.visible = false
			_repair_btn.visible = false
			_hint.visible = false
			_progress.visible = false


## Endless only: once everything is maxed, rock buys the gate back.
func _update_repair() -> void:
	var want := Game.is_endless() and Game.running and Game.lives < Game.max_lives
	_repair_btn.visible = want
	if not want:
		return
	var cost := Game.repair_cost()
	_repair_btn.text = "REPAIR GATE   %d" % cost
	_repair_btn.disabled = not Game.can_afford(cost)


func _update_hint(delta: float) -> void:
	if level.next_wave != 1:
		_hint.visible = false
		return
	_hint_time += delta
	_hint.visible = true
	_hint.modulate.a = 0.6 + 0.4 * sin(_hint_time * 3.0)
	var has_tower := false
	for s in level.slots:
		if s.tower != null:
			has_tower = true
	_hint.text = "Tap a stone plinth to build" if not has_tower else "Hold anywhere in battle to fire  ·  START when ready"


func _on_rock(v: int) -> void:
	_rock_pop = 1.0
	_rock_label.pivot_offset = Vector2(0, 40)
	if absf(_shown_rock - v) > 400.0:
		_shown_rock = v
		_rock_label.text = str(v)


func _on_lives(v: int, delta: int) -> void:
	_lives.lives = v
	_lives.total = Game.max_lives
	if delta < 0:
		_lives.flash = 1.0
	elif delta > 0:
		_lives.gain = 1.0
	_lives.queue_redraw()


func _on_wave(w: int) -> void:
	_wave_label.text = Game.wave_label()
	if Game.is_endless():
		_tier_label.text = Config.endless_tier(maxi(w, 1))
		_wave_label.add_theme_color_override("font_color", Config.C_TEXT)
	else:
		_tier_label.text = ""
		if w == Config.WAVE_COUNT:
			_wave_label.add_theme_color_override("font_color", Config.C_THREAT)
			_wave_label.text = "FINAL WAVE"
		else:
			_wave_label.add_theme_color_override("font_color", Config.C_TEXT)


func _on_wave_started(w: int) -> void:
	_hint_time = 0.0
	var groups := Config.wave_preview(w, Game.mode)
	var boss := false
	for g in groups:
		if g[0] == Config.EnemyType.BOSS:
			boss = true
	var title := "WAVE %d" % w
	var sub := "INCOMING"
	if boss:
		title = "SIEGE TOWER"
		sub = "WAVE %d" % w
	elif Game.is_endless():
		sub = Config.endless_tier(w)
	elif w == Config.WAVE_COUNT:
		sub = "THE LAST PUSH"
	_banner.show_banner(title, sub, Config.C_THREAT if boss else Config.C_ROCK)


func _on_milestone(_w: int, text: String) -> void:
	_banner.show_banner(text, "", Config.C_GOOD)


func _on_speed_changed(s: float) -> void:
	_speed_btn.text = "%dx" % int(s)


func _on_auto() -> void:
	if level == null or level.commander == null:
		return
	Sfx.play("click")
	level.commander.set_auto(not level.commander.auto)
	_refresh_auto()


## Gold when the gunner has the trigger, plain when the player does.
func _refresh_auto() -> void:
	var on := level != null and level.commander != null and level.commander.auto
	UiTheme.make_compact(_auto_btn, on)


func _on_speed() -> void:
	Sfx.play("click")
	Game.toggle_speed()


func _on_repair() -> void:
	if Game.repair_gate():
		Sfx.play("upgrade")
		if level != null:
			level.gate.damage = maxi(0, level.gate.damage - 1)
			level.gate.queue_redraw()
			Fx.float_text(level.fx_layer, Level.GATE_POS + Vector2(0, 110), "GATE REPAIRED", Config.C_GOOD, 48, "crit")
	else:
		Sfx.play("deny")
	_update_repair()


func _on_start() -> void:
	Sfx.play("click")
	level.skip_prep()


func _on_phase(_p: String) -> void:
	pass


func reset() -> void:
	_shown_rock = float(Game.rock)
	_rock_label.text = str(Game.rock)
	_lives.total = Game.max_lives
	_lives.lives = Game.lives
	_combo.set_combo(0)
	_last_countdown = -1


# ------------------------------------------------------------------ widgets

## The stone-and-gold bar behind the readouts.
## Two chips, not a plate. A full-width slab is the heaviest possible way to
## show two numbers, and it was taking 150px off the top of the mound to do it
## — on a portrait phone that is the part of the board you most want to see.
class TopBar extends Control:
	var _rock_box: StyleBoxTexture
	var _wave_box: StyleBoxTexture
	var _lives_box: StyleBoxTexture

	func _ready() -> void:
		_rock_box = Gfx.gradient_box(Color(0.11, 0.15, 0.26, 0.9), Color(0.03, 0.05, 0.11, 0.94),
			Config.C_ROCK, 3.0, 26.0)
		_wave_box = Gfx.gradient_box(Color(0.08, 0.11, 0.21, 0.84), Color(0.025, 0.04, 0.09, 0.9),
			Color(Config.C_UI_LINE, 0.6), 2.5, 22.0)
		_lives_box = Gfx.gradient_box(Color(0.07, 0.09, 0.17, 0.78), Color(0.02, 0.03, 0.07, 0.86),
			Color(Config.C_THREAT, 0.45), 2.0, 18.0)

	func _draw() -> void:
		draw_style_box(_rock_box, Rect2(4, 4, 250, 88))
		draw_style_box(_wave_box, Rect2(376, 4, 288, 88))
		# The lives row gets its own pill, or the shields read as loose
		# stickers dropped on the mound.
		draw_style_box(_lives_box, Rect2(4, 98, 230, 46))


class RockIcon extends Node2D:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var s := 1.0 + 0.03 * sin(_t * 2.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
		draw_circle(Vector2(0, 3), 24, Color(0, 0, 0, 0.4))
		draw_circle(Vector2.ZERO, 22, Config.C_ROCK.darkened(0.35))
		draw_colored_polygon(PackedVector2Array([
			Vector2(-18, 6), Vector2(-10, -14), Vector2(6, -18), Vector2(18, -4), Vector2(12, 14), Vector2(-6, 16),
		]), Config.C_ROCK)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-10, -12), Vector2(4, -15), Vector2(8, -4), Vector2(-6, 0),
		]), Config.C_FIRE_HOT)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class LivesIcons extends Control:
	var lives := 3
	var total := 3
	var flash := 0.0
	var gain := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if flash > 0.0:
			flash = maxf(0.0, flash - delta * 2.0)
			queue_redraw()
		if gain > 0.0:
			gain = maxf(0.0, gain - delta * 1.6)
			queue_redraw()

	func _draw() -> void:
		var step: float = 48.0 if total <= 3 else 38.0
		for i in range(total):
			var c := Vector2(24 + i * step, size.y * 0.5)
			var on := i < lives
			var col := Config.C_THREAT if on else Color(0.16, 0.16, 0.2, 0.85)
			if not on and flash > 0.0 and i == lives:
				col = Config.C_THREAT.lerp(Color(0.16, 0.16, 0.2), 1.0 - flash)
			var sc: float = 0.66 if total <= 3 else 0.52
			if gain > 0.0 and i == lives - 1:
				sc *= 1.0 + 0.3 * gain
			draw_set_transform(c, 0.0, Vector2(sc, sc))
			var pts := PackedVector2Array([
				Vector2(-24, -26), Vector2(24, -26), Vector2(24, 4), Vector2(0, 30), Vector2(-24, 4),
			])
			draw_colored_polygon(pts, col.darkened(0.4))
			var inner := PackedVector2Array([
				Vector2(-17, -20), Vector2(17, -20), Vector2(17, 2), Vector2(0, 21), Vector2(-17, 2),
			])
			draw_colored_polygon(inner, col)
			if on:
				draw_colored_polygon(PackedVector2Array([
					Vector2(-14, -17), Vector2(0, -17), Vector2(0, 14), Vector2(-14, 0),
				]), Color(1, 1, 1, 0.16))
				draw_circle(Vector2(0, -4), 6, Config.C_ROCK)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## How much of the current wave is dealt with, shown under the top bar.
class WaveProgress extends Control:
	var value := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		# No caption. A percentage printed inside a 22px bar is unreadable at
		# arm’s length, and the bar is already saying the same thing.
		Gfx.draw_bar(self, Rect2(Vector2.ZERO, size), value, Color(0, 0, 0, 0.6), Config.C_GOOD)
		for i in range(1, 8):
			var x := size.x * float(i) / 8.0
			draw_line(Vector2(x, 3), Vector2(x, size.y - 3), Color(0, 0, 0, 0.3), 2.0)


## The commander's barrel temperature. Red means locked out.
class HeatMeter extends Control:
	var heat := 0.0
	var locked := false
	var auto := false
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func _process(delta: float) -> void:
		_t += delta
		if locked:
			queue_redraw()

	func _draw() -> void:
		# A plate behind it: this is the one control the player holds, and its
		# caption was previously printed straight over the attackers.
		Gfx.draw_panel(self, Rect2(-18, 6, size.x + 36, size.y - 4),
			Color(0.02, 0.03, 0.07, 0.62), Color(Config.C_UI_LINE, 0.28), 26.0, 2.0)
		var bar := Rect2(0, 30, size.x, 24)
		var fg: Color = Config.C_GOOD.lerp(Config.C_FIRE, clampf(heat * 1.25, 0.0, 1.0))
		if locked:
			fg = Config.C_THREAT.lerp(Config.C_FIRE_HOT, 0.5 + 0.5 * sin(_t * 12.0))
		Gfx.draw_bar(self, bar, 1.0, Color(0, 0, 0, 0), Color(0.02, 0.03, 0.07, 0.8), false)
		# A marked red zone, so the lockout can be seen coming instead of being
		# discovered when the gun stops.
		draw_rect(Rect2(bar.position.x + bar.size.x * 0.78, bar.position.y,
			bar.size.x * 0.22, bar.size.y), Color(Config.C_THREAT, 0.28))
		Gfx.draw_bar(self, bar, heat, Color(0, 0, 0, 0), fg)
		for i in range(1, 5):
			var x := bar.size.x * float(i) / 5.0
			draw_line(Vector2(x, bar.position.y + 4), Vector2(x, bar.end.y - 4), Color(0, 0, 0, 0.35), 2.0)
		var label := "OVERHEATED" if locked else ("AUTO FIRE · HOLD TO TAKE OVER" if auto else "HOLD ANYWHERE TO FIRE")
		Gfx.draw_text(self, Vector2(0, 22), label, 24,
			Config.C_THREAT if locked else Color(Config.C_TEXT, 0.72),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 6, Fonts.ui(Fonts.W_BLACK, 3))


## Kill streak: a number that grows and a ring that drains.
class ComboMeter extends Control:
	var combo := 0
	var _pop := 0.0
	var _left := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func set_combo(c: int) -> void:
		if c > combo:
			_pop = 1.0
		combo = c
		_left = Config.COMBO_WINDOW if c > 0 else 0.0
		visible = c >= 3
		queue_redraw()

	func _process(delta: float) -> void:
		if not visible:
			return
		_left = maxf(0.0, _left - delta * Game.speed)
		if _pop > 0.0:
			_pop = maxf(0.0, _pop - delta * 3.5)
		if _left <= 0.0:
			visible = false
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x - 70, 60)
		var s := 1.0 + 0.22 * _pop
		draw_circle(c, 56 * s, Color(0.02, 0.03, 0.07, 0.75))
		draw_arc(c, 56 * s, -PI * 0.5, -PI * 0.5 + TAU * (_left / Config.COMBO_WINDOW), 40, Config.C_FIRE, 6.0)
		Gfx.draw_text(self, Vector2(c.x - 100, c.y + 16), "x%d" % combo, int(46 * s), Config.C_FIRE_HOT,
			HORIZONTAL_ALIGNMENT_CENTER, 200)
		Gfx.draw_text(self, Vector2(c.x - 120, c.y + 84), "STREAK", 22, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, 240)


## Slides a wave announcement across the screen, then clears itself.
class WaveBanner extends Control:
	var _title := ""
	var _sub := ""
	var _col := Config.C_ROCK
	var _t := 0.0
	var _dur := 2.1
	var _active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		visible = false

	func show_banner(title: String, sub: String, col: Color) -> void:
		_title = title
		_sub = sub
		_col = col
		_t = 0.0
		_active = true
		visible = true
		Sfx.play("whoosh", -10.0)

	func _process(delta: float) -> void:
		if not _active:
			return
		_t += delta
		if _t >= _dur:
			_active = false
			visible = false
		queue_redraw()

	func _draw() -> void:
		var u := _t / _dur
		# Slide in, hold, slide out.
		var x := 0.0
		var a := 1.0
		if u < 0.18:
			var k := u / 0.18
			x = lerpf(-1080.0, 0.0, 1.0 - pow(1.0 - k, 3.0))
		elif u > 0.78:
			var k := (u - 0.78) / 0.22
			x = lerpf(0.0, 1080.0, k * k)
			a = 1.0 - k
		var y := 720.0
		var h := 190.0
		draw_set_transform(Vector2(x, 0), 0.0, Vector2.ONE)
		# Ribbon
		draw_colored_polygon(PackedVector2Array([
			Vector2(-40, y), Vector2(1120, y), Vector2(1120, y + h), Vector2(-40, y + h),
		]), Color(0.02, 0.03, 0.07, 0.82 * a))
		draw_line(Vector2(-40, y + 3), Vector2(1120, y + 3), Color(_col, 0.9 * a), 5.0)
		draw_line(Vector2(-40, y + h - 3), Vector2(1120, y + h - 3), Color(_col, 0.9 * a), 5.0)
		# Diagonal hazard stripes at the edges
		for i in range(8):
			var sx := -40.0 + i * 26.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(sx, y + 6), Vector2(sx + 14, y + 6), Vector2(sx - 12, y + h - 6), Vector2(sx - 26, y + h - 6),
			]), Color(_col, 0.14 * a))
			var ex := 1120.0 - i * 26.0
			draw_colored_polygon(PackedVector2Array([
				Vector2(ex, y + 6), Vector2(ex - 14, y + 6), Vector2(ex + 12, y + h - 6), Vector2(ex + 26, y + h - 6),
			]), Color(_col, 0.14 * a))
		Gfx.draw_text(self, Vector2(0, y + 96), _title, 92, Color(Config.C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, 1080, 12)
		if _sub != "":
			Gfx.draw_text(self, Vector2(0, y + 152), _sub, 38, Color(_col, a), HORIZONTAL_ALIGNMENT_CENTER, 1080, 8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Next-wave enemy preview: silhouettes with counts.
class WavePreview extends Control:
	var wave := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var font := Fonts.ui(Fonts.W_BLACK)
		draw_string_outline(font, Vector2(0, 34), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(0, 34), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Config.C_TEXT_DIM)
		var groups := Config.wave_preview(wave, Game.mode)
		# Endless waves can be long; show the four heaviest groups and a "+n".
		var shown := groups.slice(0, 4)
		var x := 108.0
		for g in shown:
			var t: int = g[0]
			var n: int = g[1]
			var c := Vector2(x, 26)
			match t:
				Config.EnemyType.RAIDER:
					draw_circle(c, 14, Color("4a3222"))
					draw_circle(c + Vector2(0, -12), 8, Color("2b1f14"))
				Config.EnemyType.RUNNER:
					draw_circle(c, 11, Color("c9a63a"))
					draw_line(c + Vector2(-8, -8), c + Vector2(-24, -14), Config.C_THREAT, 4.0)
				Config.EnemyType.SHIELDMAN:
					draw_circle(c, 17, Config.C_IRON_DARK)
					draw_circle(c, 13, Config.C_IRON)
					draw_circle(c, 5, Config.C_THREAT)
				Config.EnemyType.CART:
					draw_rect(Rect2(c.x - 20, c.y - 12, 40, 22), Config.C_WOOD)
					draw_circle(c + Vector2(-12, 12), 7, Config.C_WOOD_DARK)
					draw_circle(c + Vector2(12, 12), 7, Config.C_WOOD_DARK)
				Config.EnemyType.BOSS:
					draw_rect(Rect2(c.x - 16, c.y - 26, 32, 48), Config.C_WOOD)
					draw_rect(Rect2(c.x - 20, c.y - 30, 40, 8), Config.C_WOOD_DARK)
					draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -30), c + Vector2(4, -40), c + Vector2(-14, -46)]), Config.C_THREAT)
			var label := "x%d" % n if t != Config.EnemyType.BOSS else ("BOSS" if n == 1 else "BOSS x%d" % n)
			var col: Color = Config.C_TEXT if t != Config.EnemyType.BOSS else Config.C_THREAT
			draw_string_outline(font, Vector2(x + 26, 38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 6, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(x + 26, 38), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
			x += 128.0
		if groups.size() > shown.size():
			draw_string(font, Vector2(x, 38), "+%d" % (groups.size() - shown.size()),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Config.C_TEXT_DIM)
