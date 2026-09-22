class_name Defender
extends Node2D
## A spearman fielded by a Guard Post. He stands on the road, grabs the first
## attacker that walks into reach and holds it there while the pair trade blows.
## Everything else on the mound shoots past him, which is the whole point.

signal fell(defender: Defender)

var hp: float = 80.0
var max_hp: float = 80.0
var damage: float = 11.0
var rate: float = 1.2
var reach: float = 46.0
var post: Tower
var level: Level
var home: Vector2 = Vector2.ZERO

var target: Enemy = null
var alive: bool = true
var _cooldown: float = 0.0
var _swing: float = 0.0
var _anim: float = 0.0
var _flash: float = 0.0
var _mat: ShaderMaterial


func setup(p: Tower, lvl: Level, at: Vector2, stats: Dictionary) -> void:
	post = p
	level = lvl
	home = at
	position = at
	max_hp = float(stats["hp"])
	hp = max_hp
	damage = float(stats["damage"])
	rate = float(stats["rate"])
	reach = float(stats["reach"])
	z_index = 6


func _ready() -> void:
	_anim = randf() * TAU
	_mat = Gfx.flash_material()
	material = _mat
	scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * Config.UNIT_SCALE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not alive:
		return
	var dt := delta * Game.speed
	_anim += dt * 4.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 7.0)
		_mat.set_shader_parameter("flash", _flash * 0.55)
	if _swing > 0.0:
		_swing = maxf(0.0, _swing - dt * 5.0)
	_acquire()
	if target != null:
		_cooldown -= dt
		if _cooldown <= 0.0:
			_strike()
	queue_redraw()


## Hold whoever is in reach; release anything that dies or slips past.
func _acquire() -> void:
	if target != null:
		if not is_instance_valid(target) or not target.alive or target.blocked_by != self:
			_release()
		elif target.global_position.distance_to(global_position) > reach * 2.6:
			_release()
	if target != null:
		return
	for e in level.enemies_in_range(global_position, reach):
		if e.blocked_by == null and e.can_be_blocked():
			target = e
			e.blocked_by = self
			return


func _release() -> void:
	if target != null and is_instance_valid(target) and target.blocked_by == self:
		target.blocked_by = null
	target = null


func _strike() -> void:
	_cooldown = 1.0 / rate
	_swing = 1.0
	if target == null or not is_instance_valid(target):
		return
	# The blow can kill, and a kill clears `target` out from under us, so take
	# everything we need off the victim before swinging.
	var at: Vector2 = target.global_position
	var reach_up := at + Vector2(0, -target.radius * 0.4)
	target.take_damage(damage, 0.35, global_position)
	Sfx.play("spear", -14.0)
	Fx.sparks(level.fx_layer, reach_up, (at - global_position).normalized(), Config.C_IRON, 4, 180.0)


## Taking a hit from whatever he is holding.
func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	_flash = 1.0
	_mat.set_shader_parameter("flash", 0.55)
	if hp <= 0.0:
		_die()
	queue_redraw()


func _die() -> void:
	alive = false
	_release()
	fell.emit(self)
	Fx.burst(level.fx_layer, global_position, Config.C_THREAT, 12, 190.0)
	Fx.float_text(level.fx_layer, global_position + Vector2(0, -50), "FALLEN", Config.C_TEXT_DIM, 26)
	Sfx.play("hit", -6.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.25, 0.15) * Config.UNIT_SCALE, 0.22).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.22)
	tw.chain().tween_callback(queue_free)


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	Gfx.draw_shadow(self, Vector2(-4, 16), 21.0, 0.4, 0.52)
	var facing := 1.0
	if target != null and is_instance_valid(target):
		facing = 1.0 if target.global_position.x >= global_position.x else -1.0
	var bob := sin(_anim) * 1.6
	var sq := 1.0 + 0.05 * sin(_anim)
	draw_set_transform(Vector2(0, 0), 0.0, Vector2(facing * sq, 2.0 - sq))
	# Legs and body
	draw_line(Vector2(-5, 4), Vector2(-6, 16), Color("3b2d1e"), 5.0)
	draw_line(Vector2(5, 4), Vector2(7, 16), Color("3b2d1e"), 5.0)
	draw_circle(Vector2(0, -6 + bob), 13, Config.C_GOOD.darkened(0.25))
	draw_circle(Vector2(-3, -9 + bob), 8, Config.C_GOOD.darkened(0.1))
	# Head with a mail coif
	draw_circle(Vector2(0, -24 + bob), 9, Color("d9a372"))
	draw_circle(Vector2(0, -28 + bob), 9, Config.C_IRON_DARK)
	draw_rect(Rect2(-9, -28 + bob, 18, 4), Config.C_IRON)
	# Spear, thrust forward on the swing
	var reach_px := 16.0 + 16.0 * _swing
	var sy := -12.0 + bob
	draw_line(Vector2(-12, sy + 10), Vector2(reach_px, sy - 2), Config.C_WOOD, 3.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(reach_px, sy - 6), Vector2(reach_px + 11, sy - 2), Vector2(reach_px, sy + 2),
	]), Config.C_IRON)
	# Small shield on the off arm
	draw_circle(Vector2(-9, -8 + bob), 11, Config.C_WOOD_DARK)
	draw_circle(Vector2(-9, -8 + bob), 8, Config.C_WOOD)
	draw_circle(Vector2(-9, -8 + bob), 3, Config.C_ROCK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if hp < max_hp:
		Gfx.draw_bar(self, Rect2(-17, -46, 34, 6), hp / max_hp, Color(0, 0, 0, 0.6), Config.C_GOOD)
