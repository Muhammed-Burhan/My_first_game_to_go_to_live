class_name UiTheme
extends RefCounted
## Builds the UI Theme in code: system font with Arabic/Kurdish fallback,
## moulded sandstone-on-night panels with a gold rim, big touch-friendly buttons.
## Every surface is a baked rounded-rect gradient (see Gfx.gradient_box), so the
## UI reads as pressed metal rather than as flat rectangles.

const GOLD_TOP := Color("e8bd6a")
const GOLD_BOT := Color("a9762f")


static func make() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Roboto", "Noto Sans", "Noto Sans Arabic", "Arial", "sans-serif"])
	font.font_weight = 700
	font.allow_system_fallback = true
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	theme.default_font = font
	theme.default_font_size = 40

	# Buttons: night-blue body, gold rim, lighter top edge.
	var normal := Gfx.gradient_box(Color("1b2c4e"), Color("0c1528"), Config.C_UI_LINE, 3.0, 24.0)
	var hover := Gfx.gradient_box(Color("27406e"), Color("142238"), Config.C_SAND_LIGHT, 3.0, 24.0)
	var pressed := Gfx.gradient_box(Color("0c1528"), Color("1b2c4e"), Config.C_SAND_LIGHT, 3.0, 24.0)
	var disabled := Gfx.gradient_box(Color(0.09, 0.11, 0.16, 0.6), Color(0.05, 0.06, 0.1, 0.6), Color(Config.C_UI_LINE, 0.3), 2.0, 24.0)
	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", Config.C_TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Config.C_ROCK)
	theme.set_color("font_disabled_color", "Button", Config.C_TEXT_DIM)
	theme.set_color("font_outline_color", "Button", Color(0, 0, 0, 0.8))
	theme.set_constant("outline_size", "Button", 6)
	theme.set_font_size("font_size", "Button", 40)

	# Labels
	theme.set_color("font_color", "Label", Config.C_TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.75))

	# Panels
	var panel := Gfx.gradient_box(Color(0.075, 0.105, 0.19, 0.96), Color(0.025, 0.04, 0.085, 0.97),
		Config.C_UI_LINE, 3.0, 30.0, Vector4(26, 22, 26, 22))
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	# LineEdit
	var le := Gfx.gradient_box(Color(0.02, 0.035, 0.075, 0.95), Color(0.04, 0.06, 0.11, 0.95), Config.C_UI_LINE, 3.0, 18.0)
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", Gfx.gradient_box(Color(0.02, 0.035, 0.075, 0.95), Color(0.05, 0.075, 0.13, 0.95), Config.C_ROCK, 4.0, 18.0))
	theme.set_color("font_color", "LineEdit", Config.C_TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Config.C_TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", Config.C_ROCK)
	theme.set_font_size("font_size", "LineEdit", 48)
	return theme


## Gold "call to action" look for the one button that matters on a screen.
static func make_primary(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", Gfx.gradient_box(GOLD_TOP, GOLD_BOT, Color("fff0c0"), 3.0, 24.0))
	btn.add_theme_stylebox_override("hover", Gfx.gradient_box(GOLD_TOP.lightened(0.12), GOLD_BOT.lightened(0.1), Color.WHITE, 3.0, 24.0))
	btn.add_theme_stylebox_override("pressed", Gfx.gradient_box(GOLD_BOT, GOLD_TOP, Color("fff0c0"), 3.0, 24.0))
	btn.add_theme_stylebox_override("disabled", Gfx.gradient_box(Color("6b5730"), Color("3e3220"), Color("8d7a52"), 2.0, 24.0))
	btn.add_theme_color_override("font_color", Color("2a1d10"))
	btn.add_theme_color_override("font_hover_color", Color("2a1d10"))
	btn.add_theme_color_override("font_pressed_color", Color("2a1d10"))
	btn.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.35))
	btn.add_theme_constant_override("outline_size", 4)


## Red variant, for destructive or "quit" actions.
static func make_danger(btn: Button) -> void:
	btn.add_theme_stylebox_override("normal", Gfx.gradient_box(Color("a8352b"), Color("5e1a14"), Color("e8776c"), 3.0, 24.0))
	btn.add_theme_stylebox_override("hover", Gfx.gradient_box(Color("c04136"), Color("74211a"), Color("ffb0a6"), 3.0, 24.0))
	btn.add_theme_stylebox_override("pressed", Gfx.gradient_box(Color("5e1a14"), Color("a8352b"), Color("e8776c"), 3.0, 24.0))
	btn.add_theme_color_override("font_color", Config.C_TEXT)


## Adds a press-scale feel to any Button so taps read on a phone.
static func add_press_feel(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	btn.button_down.connect(func():
		btn.pivot_offset = btn.size / 2.0
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.06))
	btn.button_up.connect(func():
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
