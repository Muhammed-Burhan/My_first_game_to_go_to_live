class_name PauseMenu
extends Control
## Pause overlay. Runs with process_mode ALWAYS so it still animates and accepts
## taps while the rest of the tree is frozen.

signal resumed
signal quit_to_title

var _panel: Panel
var _stats: Label
var _mute_btn: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = Panel.new()
	_panel.position = Vector2(130, 560)
	_panel.size = Vector2(820, 800)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 86)
	title.add_theme_color_override("font_color", Config.C_ROCK)
	title.add_theme_constant_override("outline_size", 14)
	title.position = Vector2(130, 620)
	title.size = Vector2(820, 110)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	_stats = Label.new()
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.add_theme_font_size_override("font_size", 36)
	_stats.add_theme_color_override("font_color", Config.C_TEXT_DIM)
	_stats.position = Vector2(150, 750)
	_stats.size = Vector2(780, 160)
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stats)

	var resume := _button("RESUME", Vector2(220, 940), Vector2(640, 120))
	UiTheme.make_primary(resume)
	resume.pressed.connect(func():
		Sfx.play("click")
		resumed.emit())

	_mute_btn = _button("SOUND: ON", Vector2(220, 1080), Vector2(640, 100))
	_mute_btn.pressed.connect(_on_mute)

	var quit := _button("QUIT TO TITLE", Vector2(220, 1200), Vector2(640, 100))
	UiTheme.make_danger(quit)
	quit.pressed.connect(func():
		Sfx.play("back")
		quit_to_title.emit())


func _button(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	add_child(b)
	UiTheme.add_press_feel(b)
	return b


func open() -> void:
	visible = true
	_refresh()
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.9, 0.9)
	modulate.a = 0.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(self, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	visible = false


func _refresh() -> void:
	_mute_btn.text = "SOUND: OFF" if Sfx.muted else "SOUND: ON"
	var mode_name: String = str(Config.MODES[Game.mode]["name"])
	_stats.text = "%s   ·   %s\nRock earned %d   ·   Kills %d" % [
		mode_name, Game.wave_label(), Game.rock_earned, Game.kills]


func _on_mute() -> void:
	Sfx.set_muted(not Sfx.muted)
	_refresh()
	if not Sfx.muted:
		Sfx.play("click")


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
