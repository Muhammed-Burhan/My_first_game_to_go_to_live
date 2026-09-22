class_name Projectile
extends Node2D
## Everything in flight. Arrows and bolts home on a target; pots, naphtha and
## mangonel stones lob to a predicted point and splash. The same class carries
## incoming fire — manjaniq stones and horse-archer arrows aimed at your
## emplacements — because the flight maths is identical, only the victim differs.

const TRAIL_LEN := 10
const LOBBED := ["pot", "naft", "stone", "rock"]

var kind: String = "arrow"
var level: Level
var target: Enemy
var target_tower: Tower
var tower_damage: float = 0.0
var stats: Dictionary
var speed: float = 900.0
var _dir: Vector2 = Vector2.UP
var _life: float = 2.0
var _trail: PackedVector2Array = PackedVector2Array()
# Lob state
var _start: Vector2
var _end: Vector2
var _t: float = 0.0
var _dur: float = 0.5
var _arc: float = 120.0


func is_lobbed() -> bool:
	return LOBBED.has(kind)


## Outgoing: one of your emplacements shooting at an attacker.
func launch(lvl: Level, k: String, from: Vector2, tgt: Enemy, st: Dictionary) -> void:
	level = lvl
	kind = k
	target = tgt
	stats = st
	position = from
	_start = from
	match kind:
		"arrow":
			speed = 1000.0
		"bolt":
			speed = 1500.0
		"pot":
			_dur = 0.55
			_arc = 120.0
		"naft":
			_dur = 0.26
			_arc = 42.0
		"stone":
			_dur = 0.85
			_arc = 320.0
	if is_lobbed():
		_end = tgt.predict_position(_dur) if is_instance_valid(tgt) else from
	if is_instance_valid(tgt):
		_dir = (tgt.global_position - from).normalized()


## Incoming: a siege crew or horse archer shooting at one of your emplacements.
func launch_at_tower(lvl: Level, k: String, from: Vector2, t: Tower, dmg: float) -> void:
	level = lvl
	kind = k
	target_tower = t
	tower_damage = dmg
	stats = {"damage": dmg, "pierce": 0.0, "splash": 0.0}
	position = from
	_start = from
	_end = t.global_position + Vector2(0, -34)
	_dur = 0.95
	_arc = 260.0
	speed = 780.0
	_dir = (_end - from).normalized()
	z_index = 9


func _process(delta: float) -> void:
	var dt := delta * Game.speed
	_push_trail()
	if is_lobbed():
		_process_lob(dt)
		return
	_life -= dt
	if _life <= 0.0:
		queue_free()
		return
	if target_tower != null:
		_process_at_tower(dt)
		return
	if is_instance_valid(target) and target.alive:
		var to := target.global_position + Vector2(0, -target.radius * 0.6) - position
		var d := to.length()
		if d < 18.0 + target.radius or d <= speed * dt:
			_hit(target)
			return
		_dir = _dir.slerp(to.normalized(), minf(1.0, dt * 14.0))
	else:
		# Target gone: fly straight and hit anything in the way.
		for e in level.enemies_in_range(position, 26.0):
			_hit(e)
			return
	position += _dir * speed * dt
	rotation = _dir.angle()
	queue_redraw()


func _process_lob(dt: float) -> void:
	_t += dt
	var u := clampf(_t / _dur, 0.0, 1.0)
	var flat := _start.lerp(_end, u)
	position = flat + Vector2(0, -sin(u * PI) * _arc)
	rotation += dt * (9.0 if kind != "stone" else 5.0)
	if u >= 1.0:
		if target_tower != null:
			_land_on_tower()
		else:
			_splash()
		return
	queue_redraw()


func _process_at_tower(dt: float) -> void:
	if not is_instance_valid(target_tower) or target_tower.wrecked:
		queue_free()
		return
	var to := target_tower.global_position + Vector2(0, -34) - position
	if to.length() <= speed * dt + 14.0:
		_land_on_tower()
		return
	_dir = to.normalized()
	position += _dir * speed * dt
	rotation = _dir.angle()
	queue_redraw()


func _land_on_tower() -> void:
	if is_instance_valid(target_tower) and not target_tower.wrecked:
		target_tower.take_damage(tower_damage)
		if kind == "rock":
			Fx.explosion(level.fx_layer, position, 0.55, Config.C_SAND_LIGHT)
			level.shake(9.0, 0.25)
		else:
			Fx.sparks(level.fx_layer, position, -_dir, Config.C_SAND_LIGHT, 5, 200.0)
	queue_free()


func _push_trail() -> void:
	_trail.append(position)
	if _trail.size() > TRAIL_LEN:
		_trail.remove_at(0)


func _hit(e: Enemy) -> void:
	var roll := Boons.roll_damage(float(stats["damage"]))
	e.take_damage(float(roll[0]), float(stats["pierce"]), position)
	_burn(e)
	if bool(roll[1]):
		Fx.float_text(level.fx_layer, e.global_position + Vector2(0, -e.radius - 26),
			"CRIT", Config.C_FIRE_HOT, 34, "crit")
	if kind == "bolt":
		Fx.sparks(level.fx_layer, position, -_dir, Config.C_IRON, 10, 340.0)
		Fx.burst(level.fx_layer, position, Config.C_IRON, 6, 160.0)
		Fx.ring(level.fx_layer, position, 44.0, Config.C_SAND_LIGHT)
		var tw := e.create_tween()
		tw.tween_property(e, "scale", e.scale * Vector2(0.85, 1.15), 0.06)
		tw.tween_property(e, "scale", e.scale, 0.12)
	else:
		Fx.sparks(level.fx_layer, position, -_dir, Config.C_SAND_LIGHT, 4, 150.0)
	queue_free()


func _splash() -> void:
	var r := float(stats["splash"])
	var roll := Boons.roll_damage(float(stats["damage"]))
	for e in level.enemies_in_range(position, r):
		e.take_damage(float(roll[0]), float(stats["pierce"]), position)
		_burn(e)
	match kind:
		"stone":
			# The mangonel is the bombardment: everything about it is loud.
			Fx.explosion(level.fx_layer, position, 1.25, Config.C_SAND_LIGHT)
			level.shake(16.0, 0.4)
			Fx.hit_stop(level, 0.05, 0.15)
		"naft":
			Fx.burst(level.fx_layer, position, Config.C_FIRE_HOT, 14, 200.0, 120.0, 0.45)
			Fx.ring(level.fx_layer, position, r, Config.C_FIRE)
			_leave_fire(r * 0.75, 2.8)
		_:
			Fx.shockwave(level.fx_layer, position, r * 1.1, Config.C_FIRE, 0.45)
			Fx.burst(level.fx_layer, position, Config.C_FIRE, 24, 280.0)
			Fx.burst(level.fx_layer, position + Vector2(0, -10), Config.C_FIRE_HOT, 12, 190.0)
			Fx.smoke(level.fx_layer, position, 8, 0.8)
			Fx.scorch(level.fx_layer, position, r * 0.55)
			_leave_fire(r * 0.5, 2.2)
			Sfx.play("splash", -4.0)
			level.shake(6.0, 0.18)
	queue_free()


## Naphtha, tar pitch and Greek Fire all land here.
func _burn(e: Enemy) -> void:
	var burn: Array = stats.get("burn", [])
	if burn.size() == 2 and is_instance_valid(e) and e.alive:
		e.apply_burn(float(burn[0]), float(burn[1]))


func _leave_fire(radius: float, seconds: float) -> void:
	var pool := FirePool.new()
	pool.position = position
	pool.radius = radius
	pool.dur = seconds
	pool.z_index = -4
	level.fx_layer.add_child(pool)


func _draw() -> void:
	_draw_trail()
	match kind:
		"arrow", "war_arrow":
			var shaft: Color = Config.C_WOOD if kind == "arrow" else Config.C_THREAT_DARK
			draw_line(Vector2(-16, 0), Vector2(12, 0), shaft, 3.0)
			draw_colored_polygon(PackedVector2Array([Vector2(12, -3), Vector2(19, 0), Vector2(12, 3)]), Config.C_IRON)
			draw_line(Vector2(12, -1), Vector2(18, 0), Config.C_IRON.lightened(0.5), 1.0)
			draw_line(Vector2(-16, -3), Vector2(-10, 0), Config.C_SAND_LIGHT, 2.0)
			draw_line(Vector2(-16, 3), Vector2(-10, 0), Config.C_SAND_LIGHT, 2.0)
		"bolt":
			Gfx.draw_glow(self, Vector2(6, 0), 22.0, Config.C_SAND_LIGHT, 0.5, 3)
			draw_line(Vector2(-26, 0), Vector2(18, 0), Config.C_IRON, 6.0)
			draw_line(Vector2(-26, -1), Vector2(18, -1), Config.C_IRON.lightened(0.3), 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(18, -6), Vector2(32, 0), Vector2(18, 6)]), Config.C_IRON_DARK)
			draw_line(Vector2(-26, -6), Vector2(-16, 0), Config.C_THREAT, 3.0)
			draw_line(Vector2(-26, 6), Vector2(-16, 0), Config.C_THREAT, 3.0)
		"pot":
			Gfx.draw_glow(self, Vector2(0, -12), 26.0, Config.C_FIRE, 0.8, 4)
			draw_circle(Vector2.ZERO, 13, Config.C_IRON_DARK)
			draw_circle(Vector2(-4, -4), 7, Color(Config.C_IRON, 0.4))
			draw_rect(Rect2(-9, -15, 18, 5), Config.C_IRON)
			draw_circle(Vector2(0, -14), 6, Config.C_FIRE)
			draw_circle(Vector2(0, -16), 3, Config.C_FIRE_HOT)
		"naft":
			# A gout of burning naphtha rather than a projectile with edges.
			Gfx.draw_glow(self, Vector2.ZERO, 30.0, Config.C_FIRE, 1.1, 4)
			for i in range(3):
				var a := _t * 22.0 + float(i) * 2.1
				var o := Vector2(cos(a), sin(a)) * 6.0
				draw_circle(o, 9.0 - i * 1.5, Color(Config.C_FIRE, 0.85))
				draw_circle(o + Vector2(0, -3), 5.0 - i, Config.C_FIRE_HOT)
		"stone", "rock":
			var tint: Color = Color("8a8580") if kind == "stone" else Color("6f6a64")
			draw_circle(Vector2(0, 3), 15, Color(0, 0, 0, 0.3))
			draw_colored_polygon(PackedVector2Array([
				Vector2(-14, 5), Vector2(-9, -12), Vector2(6, -15), Vector2(15, -3),
				Vector2(11, 12), Vector2(-5, 14),
			]), tint)
			draw_colored_polygon(PackedVector2Array([
				Vector2(-9, -12), Vector2(6, -15), Vector2(8, -4), Vector2(-6, -1),
			]), tint.lightened(0.25))


## Fading streak behind the shot, drawn in local space.
func _draw_trail() -> void:
	if _trail.size() < 3:
		return
	var col := Config.C_SAND_LIGHT
	var width := 3.0
	match kind:
		"bolt":
			width = 5.0
		"pot", "naft":
			col = Config.C_FIRE
			width = 7.0
		"stone", "rock":
			col = Config.C_SAND_DARK
			width = 9.0
		"war_arrow":
			col = Config.C_THREAT
			width = 3.0
	var inv := global_transform.affine_inverse()
	for i in range(_trail.size() - 1):
		var k := float(i) / float(_trail.size() - 1)
		var a := k * k * 0.45
		draw_line(inv * _trail[i], inv * _trail[i + 1], Color(col, a), width * k)


## A short-lived pool of burning oil or naphtha. Cosmetic; the burn itself is
## applied to whatever the shot touched.
class FirePool extends Node2D:
	var radius := 50.0
	var dur := 2.2
	var _life := 0.0

	func _process(delta: float) -> void:
		_life += delta
		if _life >= dur:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := _life / dur
		var a := (1.0 - u) * (1.0 - u)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, radius, Color(Config.C_FIRE, 0.18 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in range(6):
			var ang := float(i) / 6.0 * TAU + _life * 1.4
			var p := Vector2(cos(ang), sin(ang) * 0.5) * radius * 0.62
			var f := 1.0 + sin(_life * 13.0 + i * 2.0) * 0.3
			draw_circle(p, 9.0 * f * a, Color(Config.C_FIRE, 0.7 * a))
			draw_circle(p + Vector2(0, -5), 5.0 * f * a, Color(Config.C_FIRE_HOT, 0.8 * a))
