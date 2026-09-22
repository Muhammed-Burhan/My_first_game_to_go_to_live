class_name ShareCard
extends Control
## The end-of-run card, built to be screenshotted. Portrait, high contrast, and
## everything that makes a run arguable is on it: which Daily, how deep, the
## build you ran as icons, and your rank.
##
## It fills the screen, so "save the image" is just a grab of the frame — no
## SubViewport, and what the player sees is exactly what gets written out.

signal closed

const W := 1080.0
const H := 1920.0
const SHARE_DIR := "user://share"

var result: Dictionary = {}
var last_path: String = ""
var _art: CardArt
var _copy_btn: Button
var _save_btn: Button
var _close_btn: Button
var _toast: Label
var _toast_time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_art = CardArt.new()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)

	_copy_btn = _button("COPY TEXT", Vector2(60, 1706), Vector2(440, 104))
	_copy_btn.pressed.connect(_on_copy)
	_save_btn = _button("SAVE IMAGE", Vector2(580, 1706), Vector2(440, 104))
	UiTheme.make_primary(_save_btn)
	_save_btn.pressed.connect(_on_save)
	_close_btn = _button("BACK", Vector2(390, 1828), Vector2(300, 74))
	_close_btn.add_theme_font_size_override("font_size", 30)
	_close_btn.pressed.connect(func():
		Sfx.play("back")
		close())

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 32)
	_toast.add_theme_color_override("font_color", Config.C_GOOD)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.position = Vector2(40, 1650)
	_toast.size = Vector2(1000, 48)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)


func _button(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.add_theme_font_size_override("font_size", 36)
	add_child(b)
	UiTheme.add_press_feel(b)
	return b


func show_card(r: Dictionary) -> void:
	result = r
	_art.result = r
	_art.queue_redraw()
	visible = true
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.25)


func close() -> void:
	visible = false
	closed.emit()


## The line people paste into a chat or a Story. Deliberately short.
func summary_text() -> String:
	var mode_id := str(result.get("mode_id", "campaign"))
	var head := "Citadel Defense"
	if mode_id == "daily":
		head = "Citadel Daily #%d" % int(result.get("daily", 0))
	elif mode_id == "free":
		head = "Citadel Free Siege"
	else:
		head = "Citadel Campaign"
	var emoji := str(result.get("emoji", ""))
	var depth := int(result.get("waves", 0))
	var line := "%s — Wave %d" % [head, depth]
	if emoji != "":
		line += "  " + emoji
	line += "  ·  %d pts" % int(result.get("score", 0))
	if mode_id == "free":
		line += "  ·  seed %d" % int(result.get("seed", 0))
	return line


func _on_copy() -> void:
	DisplayServer.clipboard_set(summary_text())
	Sfx.play("pick", -6.0)
	_flash_toast("Copied. Paste it anywhere.")


func _on_save() -> void:
	Sfx.play("click")
	var path := await save_png()
	if path == "":
		_flash_toast("Could not save the image.")
		return
	_flash_toast("Saved to %s" % path.get_file())


## Grabs the current frame — which is this card — and writes it out.
func save_png() -> String:
	DirAccess.make_dir_recursive_absolute(SHARE_DIR)
	# Hide the chrome so the saved card is just the card.
	for b in [_copy_btn, _save_btn, _close_btn, _toast]:
		b.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	for b in [_copy_btn, _save_btn, _close_btn]:
		b.visible = true
	_toast.visible = true
	var mode_id := str(result.get("mode_id", "run"))
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	var path := "%s/citadel_%s_%s.png" % [SHARE_DIR, mode_id, stamp]
	if img.save_png(path) != OK:
		return ""
	last_path = path
	if OS.has_feature("web"):
		_web_download(path)
	return ProjectSettings.globalize_path(path)


## On web there is no gallery, so hand the browser a download instead.
func _web_download(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var bytes := f.get_buffer(f.get_length())
	JavaScriptBridge.download_buffer(bytes, path.get_file(), "image/png")


func _flash_toast(msg: String) -> void:
	_toast.text = msg
	_toast_time = 2.4
	_toast.modulate.a = 1.0


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time < 0.6:
			_toast.modulate.a = _toast_time / 0.6


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()


## Everything above the buttons: this is what ends up in the screenshot.
class CardArt extends Control:
	var result: Dictionary = {}

	func _draw() -> void:
		if result.is_empty():
			return
		var mode_id := str(result.get("mode_id", "campaign"))
		var endless := mode_id != "campaign"
		# Ground
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, 900), Vector2(0, 900)]),
			PackedColorArray([Config.C_SKY_TOP, Config.C_SKY_TOP, Config.C_SKY_MID, Config.C_SKY_MID]))
		draw_polygon(
			PackedVector2Array([Vector2(0, 900), Vector2(W, 900), Vector2(W, H), Vector2(0, H)]),
			PackedColorArray([Config.C_SKY_MID, Config.C_SKY_MID, Color("070c18"), Color("070c18")]))
		_draw_skyline()
		# Gold rule frame
		draw_rect(Rect2(36, 36, W - 72, H - 72), Color(0, 0, 0, 0.0))
		for r in [Rect2(36, 36, W - 72, 5), Rect2(36, H - 41, W - 72, 5),
				Rect2(36, 36, 5, H - 72), Rect2(W - 41, 36, 5, H - 72)]:
			draw_rect(r, Color(Config.C_ROCK, 0.65))

		# Masthead
		Gfx.draw_text(self, Vector2(0, 150), "CITADEL DEFENSE", 62, Config.C_SAND_LIGHT,
			HORIZONTAL_ALIGNMENT_CENTER, W, 12)
		var head := "CAMPAIGN"
		if mode_id == "daily":
			head = "DAILY SIEGE  #%d" % int(result.get("daily", 0))
		elif mode_id == "free":
			head = "FREE SIEGE  ·  SEED %d" % int(result.get("seed", 0))
		Gfx.draw_text(self, Vector2(0, 206), head, 36, Config.C_ROCK, HORIZONTAL_ALIGNMENT_CENTER, W, 8)

		# The number people compare
		var depth := int(result.get("waves", 0))
		Gfx.draw_text(self, Vector2(0, 330), "REACHED", 34, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, W, 6)
		Gfx.draw_glow(self, Vector2(W * 0.5, 430), 300.0, Config.C_ROCK, 0.3, 5)
		Gfx.draw_text(self, Vector2(0, 470), "WAVE %d" % depth, 150, Config.C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, W, 18)
		if endless:
			Gfx.draw_text(self, Vector2(0, 528), Config.endless_tier(maxi(depth, 1)) + " TIER", 38,
				Config.C_ROCK, HORIZONTAL_ALIGNMENT_CENTER, W, 8)
		else:
			var won := bool(result.get("won", false))
			Gfx.draw_text(self, Vector2(0, 528), "THE GATE HELD" if won else "THE GATE FELL", 38,
				Config.C_GOOD if won else Config.C_THREAT, HORIZONTAL_ALIGNMENT_CENTER, W, 8)

		# Score slab
		var slab := Rect2(120, 580, W - 240, 150)
		Gfx.draw_panel(self, slab, Color(0.03, 0.05, 0.1, 0.85), Color(Config.C_ROCK, 0.6), 24.0, 3.0)
		Gfx.draw_text(self, Vector2(0, 640), "SCORE", 28, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, W, 5)
		Gfx.draw_text(self, Vector2(0, 706), str(int(result.get("score", 0))), 64, Config.C_ROCK,
			HORIZONTAL_ALIGNMENT_CENTER, W, 10)

		_draw_build(780)
		_draw_stats(1200)

		# Call to action
		Gfx.draw_text(self, Vector2(0, 1470), "Beat this on today's siege", 38, Config.C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, W, 8)
		Gfx.draw_text(self, Vector2(0, 1520), "HITEX  ·  Erbil International Fair", 28, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, W, 5)
		# The emoji line, printed so it survives a screenshot
		var emoji := str(result.get("emoji", ""))
		if emoji != "":
			Gfx.draw_text(self, Vector2(0, 1596), emoji, 46, Config.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, W, 8)

	func _draw_skyline() -> void:
		var y := 980.0
		var rng := RandomNumberGenerator.new()
		rng.seed = 1258
		var x := 40.0
		while x < W - 40.0:
			var w := rng.randf_range(60, 140)
			var h := rng.randf_range(40, 120)
			draw_rect(Rect2(x, y - h, w, h), Color(0.04, 0.06, 0.12, 0.9))
			var cx := x
			while cx < x + w - 14:
				draw_rect(Rect2(cx, y - h - 16, 18, 16), Color(0.04, 0.06, 0.12, 0.9))
				cx += 30.0
			x += w + rng.randf_range(4, 18)

	## The build you ran, as the icons from the draft.
	func _draw_build(y: float) -> void:
		var boons: Array = result.get("boons", [])
		Gfx.draw_text(self, Vector2(0, y), "THE BUILD", 30, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, W, 6)
		if boons.is_empty():
			Gfx.draw_text(self, Vector2(0, y + 70), "No boons taken", 30, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, W, 5)
			return
		var per_row := 6
		var rows := int(ceil(float(boons.size()) / float(per_row)))
		rows = mini(rows, 3)
		var shown := mini(boons.size(), per_row * 3)
		for i in range(shown):
			var b := Boons.by_id(str(boons[i]))
			if b.is_empty():
				continue
			var row := i / per_row
			var col := i % per_row
			var in_row := mini(shown - row * per_row, per_row)
			var step := 150.0
			var start := (W - step * (in_row - 1)) * 0.5
			var c := Vector2(start + col * step, y + 100 + row * 140)
			var rim: Color = Boons.RARITY_COLOR[int(b["rarity"])]
			draw_circle(c + Vector2(0, 4), 54, Color(0, 0, 0, 0.45))
			draw_circle(c, 50, Color(0.04, 0.06, 0.12, 0.95))
			draw_arc(c, 48, 0, TAU, 32, rim, 4.0)
			DraftScreen.draw_boon_art(self, c, str(b.get("art", "star")), 0.62, 0.0)
		if boons.size() > shown:
			Gfx.draw_text(self, Vector2(0, y + 100 + rows * 140 - 40), "+%d more" % (boons.size() - shown),
				26, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, W, 5)

	func _draw_stats(y: float) -> void:
		var dur := float(result.get("duration", 0.0))
		var cells := [
			["KILLS", str(int(result.get("kills", 0)))],
			["STREAK", "x%d" % int(result.get("best_combo", 0))],
			["TIME", "%d:%02d" % [int(dur) / 60, int(dur) % 60]],
			["LIVES", str(int(result.get("lives", 0)))],
		]
		var cw := (W - 240.0) / 4.0
		for i in range(cells.size()):
			var cx := 120.0 + i * cw
			draw_line(Vector2(cx, y - 10), Vector2(cx, y + 96), Color(Config.C_ROCK, 0.25 if i > 0 else 0.0), 2.0)
			Gfx.draw_text(self, Vector2(cx, y + 34), str(cells[i][0]), 26, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_CENTER, cw, 5)
			Gfx.draw_text(self, Vector2(cx, y + 88), str(cells[i][1]), 46, Config.C_TEXT,
				HORIZONTAL_ALIGNMENT_CENTER, cw, 8)
