class_name PostFx
extends Node2D
## Full-screen grade drawn over the battlefield and under the UI: vignette,
## impact flashes, and a red edge pulse when the gate is one hit from falling.

const W := 1080.0
const H := 1920.0

var _flash_color: Color = Color.WHITE
var _flash: float = 0.0
var _danger: float = 0.0
var _t: float = 0.0
var _vignette: Texture2D
var _grain: Texture2D


func _ready() -> void:
	_vignette = Gfx.vignette_texture()
	_grain = _make_grain()
	z_index = 60
	z_as_relative = false
	set_process(true)


## One 60px tile carrying both the static and the scanlines, pre-multiplied to
## the strength we want. 60 is divisible by the 5px line pitch, so it tiles
## without seams down the screen.
func _make_grain() -> ImageTexture:
	var img := Image.create(60, 60, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	for y in range(60):
		var scan := (y % 5) < 2
		for x in range(60):
			var v := rng.randf()
			# Grain rides as a faint light speck; the scanline as a faint dark band.
			var a := 0.030 * v
			var col := Color(1, 1, 1, a)
			if scan:
				col = Color(0, 0, 0, 0.05 + a * 0.3)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func flash(color: Color, strength: float = 0.5) -> void:
	if Game.sim_mode:
		return
	_flash_color = color
	_flash = maxf(_flash, strength)
	queue_redraw()


## 0 = calm, 1 = last life.
func set_danger(level: float) -> void:
	_danger = clampf(level, 0.0, 1.0)


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.6)
		queue_redraw()
	elif _danger > 0.0:
		queue_redraw()


## A whisper of CRT: scanlines and static, baked into one tile so the whole
## grade costs a single draw call instead of a few hundred.
func _draw_scanlines() -> void:
	if _grain == null:
		return
	draw_texture_rect(_grain, Rect2(0, 0, W, H), true, Color(1, 1, 1, 1))


func _draw() -> void:
	var rect := Rect2(-40, -40, W + 80, H + 80)
	draw_texture_rect(_vignette, rect, false, Color(0.015, 0.025, 0.06, 0.72))
	_draw_scanlines()
	if _danger > 0.0:
		var pulse := 0.35 + 0.35 * sin(_t * 3.4)
		draw_texture_rect(_vignette, rect, false, Color(Config.C_THREAT, 0.42 * _danger * pulse))
	if _flash > 0.0:
		var a := _flash * _flash
		draw_rect(Rect2(0, 0, W, H), Color(_flash_color, 0.5 * a))
