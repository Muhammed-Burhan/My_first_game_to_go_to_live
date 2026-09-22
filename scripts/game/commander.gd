class_name Commander
extends Node2D
## The player's own gun: a repeating arbalest on the gatehouse roof. Drag
## anywhere on the mound to aim, hold to fire. Shots burst on impact.
##
## This is the part that makes the game something you *do* rather than watch,
## and it is where the arcade feel lives. It is deliberately heat-limited: a
## held finger overheats in about four seconds, so the rhythm is burst, cool,
## burst — and it can never simply replace the emplacements.
##
## It also runs itself. AUTO picks the attacker nearest the gate and keeps the
## barrel just below the red, which is what you want while both hands are busy
## building. It is deliberately the weaker option: slower rate, and it will not
## push into the heat a human is willing to spend. Convenience, not a free
## upgrade — taking hold of it by hand is still the higher-damage play.

const DAMAGE := 14.0
const RATE := 5.5             # shots per second
const BLAST := 44.0
const MUZZLE := 46.0
const HEAT_PER_SHOT := 0.14
const COOL_RATE := 0.5        # heat per second shed when not firing
const OVERHEAT_LOCK := 1.6    # seconds locked out after redlining
const SPREAD := 0.035
## Auto is worth roughly two thirds of a held finger, and stops short of the
## lockout instead of riding it.
const AUTO_RATE := 0.62
const AUTO_HEAT_STOP := 0.72
const AUTO_HEAT_RESUME := 0.34

signal overheated

var level: Level
var heat: float = 0.0
var locked: float = 0.0
var firing: bool = false
## Fires itself at the attacker nearest the gate when the player is not holding.
var auto: bool = false
var aim_point: Vector2 = Vector2(540, 1200)

var _aim: float = PI * 0.5
var _cooldown: float = 0.0
var _recoil: float = 0.0
var _t: float = 0.0
var _light: PointLight2D
var _auto_target: Enemy = null
var _auto_resting: bool = false
var _auto_scan: float = 0.0


func _ready() -> void:
	z_index = 9
	_light = Gfx.make_light(Config.C_FIRE_HOT, 0.0, 220.0)
	add_child(_light)


func can_fire() -> bool:
	return Game.running and level.phase == "wave" and locked <= 0.0


func aim_at(world: Vector2) -> void:
	aim_point = world


func set_firing(on: bool) -> void:
	firing = on
	if on:
		Game.note_commander_fired()


## Automatic fire counts as firing the repeater: the "quiet wave" contract asks
## for waves held without it, and letting AUTO shoot for free would be a lie.
func set_auto(on: bool) -> void:
	auto = on
	_auto_target = null
	_auto_resting = false
	if not on:
		return
	Save.data["commander_auto"] = true
	Save.save_profile()


func _process(delta: float) -> void:
	var dt := delta * Game.speed
	_t += dt
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - dt * 7.0)
	# Aim tracks the finger with a little lag, so sweeping reads as a turret.
	var want := (aim_point - global_position).angle()
	_aim = lerp_angle(_aim, want, minf(1.0, dt * 9.0))
	if locked > 0.0:
		locked = maxf(0.0, locked - dt)
		heat = maxf(0.0, heat - dt * COOL_RATE * 1.4)
		_auto_target = null
	elif firing and can_fire():
		# A hand on the trigger always wins: manual runs at full rate and is
		# allowed to redline, which is the whole reason to take hold of it.
		_cooldown -= dt
		if _cooldown <= 0.0:
			_shoot()
	elif auto and can_fire() and _auto_tick(dt):
		_cooldown -= dt
		if _cooldown <= 0.0:
			_shoot(AUTO_RATE)
	else:
		heat = maxf(0.0, heat - dt * COOL_RATE)
	_light.energy = maxf(0.0, _recoil * 1.2)
	queue_redraw()


## Runs the automatic gunner. Returns true when it wants to pull the trigger
## this frame. Re-targets a few times a second rather than every frame: a
## turret that snaps to a new man the instant one dies reads as a twitch.
func _auto_tick(dt: float) -> bool:
	heat = maxf(0.0, heat - dt * COOL_RATE)
	# Hysteresis around the red zone, so it eases off and comes back rather
	# than stuttering on the threshold.
	if _auto_resting:
		if heat > AUTO_HEAT_RESUME:
			return false
		_auto_resting = false
	elif heat >= AUTO_HEAT_STOP:
		_auto_resting = true
		return false
	_auto_scan -= dt
	if _auto_scan <= 0.0 or _auto_target == null or not is_instance_valid(_auto_target) \
			or not _auto_target.alive:
		_auto_scan = 0.22
		_auto_target = _pick_auto_target()
	if _auto_target == null:
		return false
	# Lead the shot a little: the tracer has travel time and the column moves.
	aim_point = _auto_target.predict_position(
		global_position.distance_to(_auto_target.global_position) / 1750.0)
	return true


## The attacker nearest the gate, which is the one about to cost a life.
func _pick_auto_target() -> Enemy:
	var best: Enemy = null
	var best_prog := -1.0
	for e in level.living_enemies():
		if e.progress > best_prog:
			best_prog = e.progress
			best = e
	return best


func _shoot(rate_scale: float = 1.0) -> void:
	_cooldown = 1.0 / (RATE * Boons.m("cmd_rate") * rate_scale)
	_recoil = 1.0
	heat = minf(1.0, heat + HEAT_PER_SHOT)
	if heat >= 1.0:
		locked = OVERHEAT_LOCK
		firing = false
		Sfx.play("overheat", -6.0)
		Fx.smoke(level.fx_layer, global_position + Vector2(0, -20), 8, 0.9)
		overheated.emit()
		return
	var a := _aim + randf_range(-SPREAD, SPREAD)
	var b := Bullet.new()
	b.level = level
	b.position = global_position + Vector2(cos(a), sin(a)) * MUZZLE
	b.velocity = Vector2(cos(a), sin(a)) * 1750.0
	b.damage = DAMAGE * Boons.m("cmd_dmg")
	b.blast = BLAST * Boons.m("cmd_blast")
	level.projectiles.add_child(b)
	Sfx.play("shoot", -13.0, 0.10)
	Fx.sparks(level.fx_layer, b.position, Vector2(cos(a), sin(a)), Config.C_FIRE_HOT, 3, 190.0)


func _draw() -> void:
	# Mount
	draw_rect(Rect2(-26, -6, 52, 22), Config.C_IRON_DARK)
	draw_rect(Rect2(-26, -6, 52, 5), Config.C_IRON)
	draw_circle(Vector2(0, -6), 13, Config.C_IRON_DARK)
	# Swivelling arbalest
	draw_set_transform(Vector2(0, -6), _aim, Vector2.ONE)
	var back := 10.0 * _recoil
	draw_rect(Rect2(-22 - back, -7, 56, 14), Config.C_WOOD)
	draw_rect(Rect2(-22 - back, -7, 56, 4), Config.C_SAND_LIGHT.darkened(0.3))
	draw_rect(Rect2(18 - back, -5, 26, 10), Config.C_IRON_DARK)
	# Prod and string
	draw_arc(Vector2(14 - back, 0), 26, PI * 0.5 - 0.45, PI * 0.5 + 0.45, 8, Config.C_IRON_DARK, 5.0)
	draw_arc(Vector2(14 - back, 0), 26, -PI * 0.5 - 0.45, -PI * 0.5 + 0.45, 8, Config.C_IRON_DARK, 5.0)
	draw_line(Vector2(25 - back, -23), Vector2(-18 - back, 0), Config.C_SAND_LIGHT, 1.6)
	draw_line(Vector2(25 - back, 23), Vector2(-18 - back, 0), Config.C_SAND_LIGHT, 1.6)
	# Magazine box on top
	draw_rect(Rect2(-6 - back, -20, 20, 14), Config.C_WOOD_DARK)
	if _recoil > 0.3:
		var a := _recoil * _recoil
		Gfx.draw_glow(self, Vector2(MUZZLE - 6, 0), 34.0 * a, Config.C_FIRE_HOT, a * 1.6, 3)
		draw_colored_polygon(PackedVector2Array([
			Vector2(40, -9 * a), Vector2(40 + 30 * a, 0), Vector2(40, 9 * a),
		]), Color(Config.C_FIRE_HOT, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Crew: two men working the windlass
	for cx in [-30.0, 30.0]:
		draw_circle(Vector2(cx, -4), 9, Config.C_GOOD.darkened(0.2))
		draw_circle(Vector2(cx, -18), 7, Color("d9a372"))
		draw_circle(Vector2(cx, -22), 7, Config.C_IRON_DARK)


## A tracer that bursts where it lands. Small blast, but it is always available
## and it is the player's own, which is what makes it feel good.
class Bullet extends Node2D:
	var level: Level
	var velocity := Vector2.ZERO
	var damage := 14.0
	var blast := 44.0
	var _life := 1.4
	var _trail: PackedVector2Array = PackedVector2Array()

	func _ready() -> void:
		z_index = 9

	func _process(delta: float) -> void:
		var dt := delta * Game.speed
		_life -= dt
		if _life <= 0.0:
			queue_free()
			return
		_trail.append(position)
		if _trail.size() > 7:
			_trail.remove_at(0)
		var step := velocity * dt
		position += step
		rotation = velocity.angle()
		# Off the mound entirely: stop bothering.
		if position.y < 380.0 or position.x < -60.0 or position.x > 1140.0 or position.y > 1990.0:
			queue_free()
			return
		var hits := level.enemies_in_range(position, 26.0)
		if not hits.is_empty():
			_burst()
			return
		queue_redraw()

	func _burst() -> void:
		for e in level.enemies_in_range(position, blast):
			e.take_damage(damage, 0.45, position)
		Fx.explosion(level.fx_layer, position, 0.42, Config.C_FIRE_HOT)
		level.shake(3.5, 0.12)
		queue_free()

	func _draw() -> void:
		var inv := global_transform.affine_inverse()
		for i in range(_trail.size() - 1):
			var k := float(i) / maxf(float(_trail.size() - 1), 1.0)
			draw_line(inv * _trail[i], inv * _trail[i + 1], Color(Config.C_FIRE_HOT, k * 0.55), 5.0 * k)
		Gfx.draw_glow(self, Vector2.ZERO, 18.0, Config.C_FIRE_HOT, 0.9, 3)
		draw_line(Vector2(-16, 0), Vector2(10, 0), Config.C_FIRE_HOT, 4.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(10, -4), Vector2(20, 0), Vector2(10, 4),
		]), Config.C_IRON)
