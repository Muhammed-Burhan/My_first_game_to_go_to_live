class_name Atmosphere
extends Node2D
## Moving air: clouds crossing the moon, mist lying in the terrace hollows,
## embers off the camp fires and dust drifting up the mound. Purely decorative,
## drawn above the backdrop and below the units.

const W := 1080.0
const H := 1920.0


func _ready() -> void:
	var clouds := Clouds.new()
	clouds.z_index = -16
	add_child(clouds)

	var fog := Fog.new()
	fog.z_index = -6
	add_child(fog)

	add_child(_embers())
	add_child(_dust())


## Sparks lifting off the Mongol camp at the bottom of the mound.
func _embers() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(W * 0.5, H - 60.0)
	p.amount = 26
	p.lifetime = 5.5
	p.preprocess = 4.0
	p.lifetime_randomness = 0.5
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(W * 0.5, 70.0)
	p.direction = Vector2(0, -1)
	p.spread = 22.0
	p.gravity = Vector2(14, -26)
	p.initial_velocity_min = 26.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 1.6
	p.scale_amount_max = 4.0
	p.damping_min = 2.0
	p.damping_max = 6.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(Config.C_FIRE_HOT, 0.0), Color(Config.C_FIRE, 0.85), Color(Config.C_THREAT, 0.0)])
	p.color_ramp = g
	p.z_index = 12
	p.emitting = true
	return p


## Fine pale dust hanging over the whole mound.
func _dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(W * 0.5, H * 0.62)
	p.amount = 34
	p.lifetime = 9.0
	p.preprocess = 6.0
	p.lifetime_randomness = 0.6
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(W * 0.52, H * 0.34)
	p.direction = Vector2(-1, -0.35)
	p.spread = 40.0
	p.gravity = Vector2(-6, -4)
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 20.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 3.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(Config.C_SAND_LIGHT, 0.0), Color(Config.C_SAND_LIGHT, 0.22), Color(Config.C_SAND_LIGHT, 0.0)])
	p.color_ramp = g
	p.z_index = 11
	p.emitting = true
	return p


## Slow cloud bank drifting across the night sky, dimming the moon as it passes.
class Clouds extends Node2D:
	var _clouds: Array = []
	var _t := 0.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 771
		for i in range(6):
			var puffs: Array = []
			var n := rng.randi_range(5, 9)
			var w := rng.randf_range(160.0, 340.0)
			for j in range(n):
				var u := float(j) / float(n - 1)
				puffs.append([
					Vector2(lerpf(-w, w, u) + rng.randf_range(-20, 20), rng.randf_range(-14, 14)),
					rng.randf_range(34.0, 74.0) * (1.0 - absf(u - 0.5) * 0.5),
				])
			_clouds.append({
				"puffs": puffs,
				"y": rng.randf_range(60.0, 430.0),
				"x": rng.randf_range(-300.0, 1400.0),
				"speed": rng.randf_range(5.0, 13.0),
				"alpha": rng.randf_range(0.07, 0.17),
				"w": w,
			})

	func _process(delta: float) -> void:
		_t += delta
		for c in _clouds:
			c["x"] += c["speed"] * delta
			if c["x"] - c["w"] > 1400.0:
				c["x"] = -400.0 - c["w"]
		queue_redraw()

	func _draw() -> void:
		for c in _clouds:
			var base := Vector2(c["x"], c["y"])
			var tint: Color = Config.C_SKY_HAZE.lerp(Config.C_MOON, 0.25)
			for p in c["puffs"]:
				draw_circle(base + p[0] + Vector2(0, 6), p[1], Color(Config.C_SKY_TOP, c["alpha"] * 0.7))
				draw_circle(base + p[0], p[1], Color(tint, c["alpha"]))


## Mist pooling in the terrace hollows. Two counter-drifting sheets so the
## overlap reads as depth rather than as one moving stripe.
class Fog extends Node2D:
	const BANDS := [
		{"y": 700.0, "h": 54.0, "a": 0.055, "speed": 11.0},
		{"y": 905.0, "h": 62.0, "a": 0.065, "speed": -8.0},
		{"y": 1180.0, "h": 70.0, "a": 0.07, "speed": 13.0},
		{"y": 1470.0, "h": 78.0, "a": 0.075, "speed": -10.0},
		{"y": 1720.0, "h": 86.0, "a": 0.08, "speed": 7.0},
	]
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for i in range(BANDS.size()):
			var b: Dictionary = BANDS[i]
			var off: float = fmod(_t * float(b["speed"]), 400.0)
			var pts := PackedVector2Array()
			var steps := 24
			var y: float = b["y"]
			var h: float = b["h"]
			for s in range(steps + 1):
				var u := float(s) / steps
				var x := -80.0 + u * 1240.0
				var wave := sin((x + off) * 0.006 + i) * 10.0 + sin((x - off) * 0.013 + i * 2.0) * 6.0
				pts.append(Vector2(x, y + wave - h * 0.5))
			for s in range(steps, -1, -1):
				var u := float(s) / steps
				var x := -80.0 + u * 1240.0
				var wave := sin((x - off * 0.7) * 0.009 + i * 1.3) * 9.0
				pts.append(Vector2(x, y + wave + h * 0.5))
			draw_colored_polygon(pts, Color(Config.C_SKY_HAZE, float(b["a"])))
