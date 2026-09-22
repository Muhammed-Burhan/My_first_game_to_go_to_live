class_name Background
extends Node2D
## The backdrop, and the lights that sit in it.
##
## Everything static — sky, ridgelines, moon, plain, camp, terraces, the
## citadel wall — lives in BackgroundPaint and is rendered exactly once into a
## texture at load. Godot replays a Node2D’s draw commands every frame, and
## that paint issues about 3,400 of them; measured with --hide=bg it was 56% of
## the game’s entire draw call count, more than five times everything moving on
## screen. It is one textured quad now.
##
## What stays live is only what actually changes: twinkling stars, breathing
## windows, and the torches and campfires, which are real 2D lights so the
## scene sits in a warm pool at the top and a cold one at the bottom.

const W := BackgroundPaint.W
const H := BackgroundPaint.H
const MOON_POS := BackgroundPaint.MOON_POS

var _baked: Texture2D = null


func _ready() -> void:
	# One night grade for the whole battlefield canvas; the UI layer is separate.
	var tint := CanvasModulate.new()
	tint.color = Config.NIGHT_TINT
	add_child(tint)

	var stars := Stars.new()
	stars.z_index = -1
	add_child(stars)

	for x in BackgroundPaint.WALL_TORCHES:
		var flame := Flicker.new()
		flame.position = Vector2(x, 318.0)
		flame.radius = 200.0
		flame.core = 7.0
		add_child(flame)
	for f in BackgroundPaint.CAMP_FIRES:
		var fire := Flicker.new()
		fire.position = f
		fire.radius = 260.0
		fire.core = 11.0
		fire.rate = 8.0
		add_child(fire)
	_build()


## Render the static paint once into a texture and keep the quad. Falls back to
## drawing it live when there is no real renderer to bake with — headless runs
## (the sim, the progression test) never show a frame anyway.
func _build() -> void:
	if DisplayServer.get_name() == "headless" or Game.sim_mode:
		var live := BackgroundPaint.new()
		live.z_index = -2
		add_child(live)
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(int(W), int(H))
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var paint := BackgroundPaint.new()
	vp.add_child(paint)
	# Two frames: one for _draw to run, one for the render target to resolve.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	var windows: Array[Vector2] = paint.lit_windows.duplicate()
	vp.queue_free()
	if img == null or img.is_empty():
		# Something went wrong with the render target; draw it live rather
		# than shipping a blank sky.
		var live2 := BackgroundPaint.new()
		live2.z_index = -2
		add_child(live2)
		return
	_baked = ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = _baked
	sprite.centered = false
	sprite.z_index = -2
	add_child(sprite)
	# The windows breathe, so they were never part of the static paint.
	for p in windows:
		var w := LitWindow.new()
		w.position = p
		add_child(w)


class Stars extends Node2D:
	var _stars: Array = []
	var _t := 0.0
	var _shoot := -1.0
	var _shoot_from := Vector2.ZERO
	var _shoot_dir := Vector2(1, 0.35)
	var _next_shoot := 6.0
	var _redraw_in := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 314
		for i in range(130):
			_stars.append([
				Vector2(rng.randf_range(6, 1074), rng.randf_range(6, 540)),
				rng.randf_range(1.0, 3.2),
				rng.randf() * TAU,
				rng.randf(),
			])

	func _process(delta: float) -> void:
		_t += delta
		# A twinkle is not worth 130 redrawn points at 60Hz. At 15 it looks
		# identical and costs a quarter as much.
		_redraw_in -= delta
		if _shoot >= 0.0:
			_shoot += delta
			if _shoot > 1.1:
				_shoot = -1.0
		else:
			_next_shoot -= delta
			if _next_shoot <= 0.0:
				_next_shoot = randf_range(9.0, 22.0)
				_shoot = 0.0
				_shoot_from = Vector2(randf_range(100, 900), randf_range(40, 260))
				_shoot_dir = Vector2(randf_range(0.6, 1.0), randf_range(0.2, 0.5)).normalized()
		# A shooting star needs every frame; the idle twinkle does not.
		if _shoot >= 0.0 or _redraw_in <= 0.0:
			_redraw_in = 1.0 / 15.0
			queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var a: float = 0.5 + 0.5 * sin(_t * (1.2 + float(s[3]) * 1.8) + float(s[2]))
			var col: Color = Config.C_STAR if float(s[3]) < 0.8 else Color("bcd2ff")
			if float(s[1]) > 2.6:
				draw_circle(s[0], float(s[1]) * 2.6, Color(col, 0.10 * a))
			draw_circle(s[0], float(s[1]), Color(col, 0.35 + 0.65 * a))
		if _shoot >= 0.0:
			var u := _shoot / 1.1
			var head: Vector2 = _shoot_from + _shoot_dir * 620.0 * u
			var tail: Vector2 = head - _shoot_dir * 150.0
			var a := sin(u * PI)
			draw_line(tail, head, Color(Config.C_STAR, 0.0), 1.0)
			for i in range(6):
				var k := float(i) / 6.0
				draw_line(tail.lerp(head, k), tail.lerp(head, k + 0.17), Color(Config.C_STAR, a * k * 0.8), 1.0 + k * 2.0)
			draw_circle(head, 3.0, Color(Config.C_STAR, a))


## A flame plus its point light: torches on the wall and the camp fires.
class Flicker extends Node2D:
	var radius := 180.0
	var core := 7.0
	var rate := 11.0
	var _light: PointLight2D
	var _t := 0.0

	func _ready() -> void:
		_t = randf() * 10.0
		_light = Gfx.make_light(Config.C_TORCH, 1.0, radius)
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		var f := 0.78 + 0.22 * sin(_t * rate) + 0.08 * sin(_t * rate * 2.7 + 1.3)
		_light.energy = 0.75 * f
		_light.texture_scale = (radius / 128.0) * (0.94 + 0.06 * f)
		queue_redraw()

	func _draw() -> void:
		var f := 1.0 + 0.18 * sin(_t * rate) + 0.08 * sin(_t * rate * 2.3)
		draw_circle(Vector2(0, -core * 0.4), core * 2.4 * f, Color(Config.C_FIRE, 0.16))
		draw_circle(Vector2.ZERO, core * f, Config.C_FIRE)
		draw_circle(Vector2(0, -core * 0.5), core * 0.62 * f, Config.C_FIRE_HOT)


## A window whose lamp breathes, so the citadel looks inhabited.
class LitWindow extends Node2D:
	var _t := 0.0
	var _rate := 1.0

	func _ready() -> void:
		_t = randf() * 6.0
		_rate = randf_range(0.7, 2.2)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var a := 0.42 + 0.16 * sin(_t * _rate) + 0.06 * sin(_t * _rate * 3.1)
		draw_circle(Vector2(6, 8), 18, Color(Config.C_FIRE, 0.07 * a))
		draw_rect(Rect2(0, 0, 12, 15), Color(Config.C_FIRE_HOT, a))
		draw_rect(Rect2(0, 0, 12, 5), Color(Config.C_FIRE_HOT, a * 0.6))
