class_name Fx
extends RefCounted
## Visual effects: floating text, particle bursts, sparks, shockwaves, scorch
## marks, flying coins and the hit-stop. All fire-and-forget nodes added to the
## level's fx layer, so nothing here needs cleanup by the caller.

const HUD_ROCK_POS := Vector2(96, 96)


static func float_text(layer: Node2D, pos: Vector2, text: String, color: Color, size: int = 32,
		style: String = "plain") -> void:
	if Game.sim_mode:
		return
	var n := FloatText.new()
	n.position = pos
	n.text = text
	n.color = color
	n.font_size = size
	n.style = style
	layer.add_child(n)


static func burst(layer: Node2D, pos: Vector2, color: Color, amount: int, speed: float,
		gravity: float = 500.0, lifetime: float = 0.55) -> void:
	if Game.sim_mode:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, gravity)
	p.initial_velocity_min = speed * 0.35
	p.initial_velocity_max = speed
	p.scale_amount_min = 2.5
	p.scale_amount_max = 6.5
	p.damping_min = 40.0
	p.damping_max = 120.0
	p.color = color
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([color.lightened(0.4), color, Color(color, 0.0)])
	p.color_ramp = g
	p.emitting = true
	layer.add_child(p)
	_reap(layer, p, lifetime + 0.2)


## Directional sparks: an impact throwing debris back along the hit normal.
static func sparks(layer: Node2D, pos: Vector2, dir: Vector2, color: Color, amount: int = 8,
		speed: float = 320.0) -> void:
	if Game.sim_mode:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 0.32
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = dir.normalized() if dir.length_squared() > 0.001 else Vector2.UP
	p.spread = 38.0
	p.gravity = Vector2(0, 760)
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.6
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), color, Color(color, 0.0)])
	p.color_ramp = g
	p.emitting = true
	layer.add_child(p)
	_reap(layer, p, 0.55)


## Slow drifting smoke, for wrecked carts and burning oil.
static func smoke(layer: Node2D, pos: Vector2, amount: int = 12, scale: float = 1.0) -> void:
	if Game.sim_mode:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 1.6
	p.one_shot = true
	p.explosiveness = 0.7
	p.direction = Vector2(0, -1)
	p.spread = 26.0
	p.gravity = Vector2(10, -70)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 90.0
	p.scale_amount_min = 6.0 * scale
	p.scale_amount_max = 16.0 * scale
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(0.35, 0.33, 0.34, 0.0), Color(0.3, 0.29, 0.3, 0.5), Color(0.18, 0.18, 0.2, 0.0)])
	p.color_ramp = g
	p.emitting = true
	layer.add_child(p)
	_reap(layer, p, 2.0)


static func ring(layer: Node2D, pos: Vector2, radius: float, color: Color) -> void:
	if Game.sim_mode:
		return
	var r := Ring.new()
	r.position = pos
	r.radius = radius
	r.color = color
	layer.add_child(r)


## A fast expanding pressure ring: boss deaths, big impacts.
static func shockwave(layer: Node2D, pos: Vector2, radius: float, color: Color, duration: float = 0.5) -> void:
	if Game.sim_mode:
		return
	var s := Shockwave.new()
	s.position = pos
	s.radius = radius
	s.color = color
	s.dur = duration
	layer.add_child(s)


static func scorch(layer: Node2D, pos: Vector2, radius: float) -> void:
	if Game.sim_mode:
		return
	var s := Scorch.new()
	s.position = pos
	s.radius = radius
	s.z_index = -5
	layer.add_child(s)


## A coin that arcs from a kill up to the rock counter in the HUD.
static func coin(layer: Node2D, pos: Vector2, amount: int = 1) -> void:
	if Game.sim_mode:
		return
	for i in range(mini(amount, 5)):
		var c := Coin.new()
		c.position = pos
		c.delay = i * 0.06
		c.spread = Vector2(randf_range(-70, 70), randf_range(-90, -30))
		layer.add_child(c)


## The big one. A Contra-style detonation: white core, expanding fireball rings,
## a ragged debris spray, a smoke column and a scorch. `power` 0.5 is a grenade,
## 1.0 a wrecked siege engine, 1.6 the siege tower going up.
static func explosion(layer: Node2D, pos: Vector2, power: float = 1.0, tint: Color = Config.C_FIRE) -> void:
	if Game.sim_mode:
		return
	var r := 90.0 * power
	var boom := Fireball.new()
	boom.position = pos
	boom.radius = r
	boom.tint = tint
	boom.z_index = 4
	layer.add_child(boom)
	shockwave(layer, pos, r * 2.4, tint, 0.42 + 0.12 * power)
	burst(layer, pos, Config.C_FIRE_HOT, int(14 * power) + 8, 320.0 * power, 420.0, 0.45)
	burst(layer, pos, tint, int(20 * power) + 10, 250.0 * power, 620.0, 0.7)
	debris(layer, pos, int(9 * power) + 5, 340.0 * power)
	smoke(layer, pos, int(8 * power) + 4, 0.8 + power * 0.7)
	scorch(layer, pos, r * 0.8)
	Sfx.play_pitched("boom", clampf((1.2 - power) * 7.0, -7.0, 7.0), -2.0 + power * 2.0)


## Tumbling chunks thrown clear of a blast: stone, timber, iron.
static func debris(layer: Node2D, pos: Vector2, amount: int, speed: float) -> void:
	if Game.sim_mode:
		return
	for i in range(amount):
		var d := Debris.new()
		d.position = pos
		var a := randf() * TAU
		d.velocity = Vector2(cos(a), sin(a) * 0.75) * randf_range(speed * 0.35, speed)
		d.velocity.y -= randf_range(60.0, 230.0)
		d.size = randf_range(4.0, 11.0)
		d.spin = randf_range(-9.0, 9.0)
		d.tone = randf()
		layer.add_child(d)


## A short freeze that sells a heavy hit. Real-time, so it works at any speed.
static func hit_stop(layer: Node, duration: float = 0.07, scale: float = 0.08) -> void:
	if Game.sim_mode or layer == null or not layer.is_inside_tree():
		return
	if Engine.time_scale < 0.9:
		return
	Engine.time_scale = scale
	var t := layer.get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func(): Engine.time_scale = 1.0)


static func _reap(layer: Node2D, node: Node, after: float) -> void:
	var timer := layer.get_tree().create_timer(after)
	timer.timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())


# ------------------------------------------------------------------ nodes

class FloatText extends Node2D:
	var text := ""
	var color := Color.WHITE
	var font_size := 32
	var style := "plain"       # plain | crit | banner
	var _life := 0.0
	var _drift := 0.0
	const DUR := 0.95

	func _ready() -> void:
		_drift = randf_range(-22.0, 22.0)

	func _process(delta: float) -> void:
		_life += delta
		position.y -= (85.0 if style == "crit" else 55.0) * delta * (1.0 - _life / DUR * 0.6)
		position.x += _drift * delta
		if _life >= DUR:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := _life / DUR
		var a := 1.0 - smoothstep(0.55, 1.0, u)
		var pop := 1.0
		if style == "crit":
			pop = 1.0 + 0.5 * exp(-u * 14.0)
		var font := ThemeDB.fallback_font
		var w := 700.0
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(pop, pop))
		var pos := Vector2(-w / 2, 0)
		var fs := font_size
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, 8, Color(0, 0, 0, 0.85 * a))
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, fs, Color(color, a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Overlapping fire lobes that bloom out of a white core and collapse into soot.
## Deliberately chunky — this is the NES-explosion read, not a soft puff.
class Fireball extends Node2D:
	var radius := 90.0
	var tint := Config.C_FIRE
	var _life := 0.0
	var _lobes: Array = []
	const DUR := 0.6

	func _ready() -> void:
		for i in range(7):
			var a := randf() * TAU
			_lobes.append([
				Vector2(cos(a), sin(a) * 0.8) * randf_range(0.1, 0.62),
				randf_range(0.42, 0.78),
				randf_range(0.0, 0.35),
			])

	func _process(delta: float) -> void:
		_life += delta
		if _life >= DUR:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := clampf(_life / DUR, 0.0, 1.0)
		var grow := 1.0 - pow(1.0 - u, 2.6)
		var fade := 1.0 - smoothstep(0.45, 1.0, u)
		# Outer soot shell
		draw_circle(Vector2.ZERO, radius * grow * 1.12, Color(0.12, 0.08, 0.06, 0.4 * fade))
		for l in _lobes:
			var delay: float = l[2]
			if u < delay:
				continue
			var lu := (u - delay) / maxf(1.0 - delay, 0.01)
			var lr: float = radius * float(l[1]) * (0.35 + 0.75 * lu)
			var c: Vector2 = l[0] * radius * grow
			draw_circle(c, lr, Color(tint.darkened(0.25), 0.55 * fade))
			draw_circle(c - Vector2(0, lr * 0.2), lr * 0.66, Color(tint, 0.8 * fade))
			if lu < 0.55:
				draw_circle(c - Vector2(0, lr * 0.3), lr * 0.36, Color(Config.C_FIRE_HOT, fade))
		# White flash core, gone almost immediately
		if u < 0.22:
			var k := 1.0 - u / 0.22
			draw_circle(Vector2.ZERO, radius * (0.3 + 0.5 * u) , Color(1, 1, 1, k))


## A chunk of masonry or timber, thrown and tumbling, that lands and stays put
## for a moment before fading.
class Debris extends Node2D:
	var velocity := Vector2.ZERO
	var size := 7.0
	var spin := 4.0
	var tone := 0.5
	var _life := 0.0
	var _grounded := false
	const DUR := 1.9

	func _process(delta: float) -> void:
		_life += delta
		if not _grounded:
			velocity.y += 1400.0 * delta
			position += velocity * delta
			rotation += spin * delta
			# The mound is a flat read, so "landing" is just losing the throw.
			if velocity.y > 0.0 and _life > 0.42:
				_grounded = true
		if _life >= DUR:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var a := 1.0 - smoothstep(DUR - 0.6, DUR, _life)
		var col: Color = Config.C_SAND_DARK
		if tone > 0.66:
			col = Config.C_WOOD_DARK
		elif tone > 0.33:
			col = Config.C_IRON_DARK
		draw_colored_polygon(PackedVector2Array([
			Vector2(-size, size * 0.4), Vector2(-size * 0.5, -size),
			Vector2(size * 0.8, -size * 0.6), Vector2(size, size * 0.5),
		]), Color(col, a))
		draw_line(Vector2(-size * 0.5, -size), Vector2(size * 0.8, -size * 0.6), Color(col.lightened(0.35), a), 2.0)


class Ring extends Node2D:
	var radius := 60.0
	var color := Color.WHITE
	var _life := 0.0
	const DUR := 0.4

	func _process(delta: float) -> void:
		_life += delta
		if _life >= DUR:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := _life / DUR
		var r := radius * (0.3 + 0.7 * u)
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(color, 1.0 - u), 8.0 * (1.0 - u) + 2.0)
		draw_circle(Vector2.ZERO, r, Color(color, 0.25 * (1.0 - u)))


class Shockwave extends Node2D:
	var radius := 150.0
	var color := Color.WHITE
	var dur := 0.5
	var _life := 0.0

	func _process(delta: float) -> void:
		_life += delta
		if _life >= dur:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := clampf(_life / dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		var r := radius * e
		var a := (1.0 - u) * (1.0 - u)
		draw_arc(Vector2.ZERO, r, 0, TAU, 56, Color(color, 0.85 * a), 14.0 * (1.0 - u) + 2.0)
		draw_arc(Vector2.ZERO, r * 0.82, 0, TAU, 56, Color(1, 1, 1, 0.5 * a), 5.0 * (1.0 - u) + 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		draw_arc(Vector2.ZERO, r * 1.25, 0, TAU, 48, Color(color, 0.35 * a), 8.0 * (1.0 - u) + 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


class Scorch extends Node2D:
	var radius := 40.0
	var _life := 0.0
	const DUR := 6.0

	func _process(delta: float) -> void:
		_life += delta
		if _life >= DUR:
			queue_free()
		if _life > DUR - 1.5 or _life < 0.4:
			queue_redraw()

	func _draw() -> void:
		var a := 0.5 * clampf((DUR - _life) / 1.5, 0.0, 1.0) * clampf(_life / 0.25, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
		draw_circle(Vector2.ZERO, radius, Color(0.08, 0.06, 0.05, a * 0.8))
		draw_circle(Vector2(6, -3), radius * 0.62, Color(0.04, 0.03, 0.02, a))
		draw_circle(Vector2(-radius * 0.4, 4), radius * 0.35, Color(0.05, 0.04, 0.03, a * 0.7))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Arcs from the kill toward the rock counter, then pops.
class Coin extends Node2D:
	var delay := 0.0
	var spread := Vector2.ZERO
	var _t := 0.0
	var _from := Vector2.ZERO
	var _ctrl := Vector2.ZERO
	const DUR := 0.72

	func _ready() -> void:
		_from = position
		_ctrl = position + spread + Vector2(0, -120)
		visible = false

	func _process(delta: float) -> void:
		if delay > 0.0:
			delay -= delta
			return
		visible = true
		_t += delta
		var u := clampf(_t / DUR, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var a := _from.lerp(_ctrl, e)
		var b := _ctrl.lerp(Fx.HUD_ROCK_POS, e)
		position = a.lerp(b, e)
		if u >= 1.0:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var spin := absf(sin(_t * 11.0)) * 0.75 + 0.25
		draw_circle(Vector2.ZERO, 13, Color(Config.C_ROCK, 0.22))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(spin, 1.0))
		draw_circle(Vector2.ZERO, 10, Config.C_ROCK.darkened(0.32))
		draw_circle(Vector2.ZERO, 7.5, Config.C_ROCK)
		draw_circle(Vector2(-2, -2), 3.0, Config.C_FIRE_HOT)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
