class_name Enemy
extends PathFollow2D
## A Mongol attacker walking the path. Five kinds, each drawn procedurally, plus
## an "elite" roll in endless that makes a veteran worth chasing.
## Movement comes from PathFollow2D.progress; the level's Path2D is the parent.

signal died(enemy: Enemy)
signal reached_gate(enemy: Enemy)

var type: int = 0
var stats: Dictionary = {}
var hp: float = 1.0
var max_hp: float = 1.0
var speed: float = 100.0
var radius: float = 20.0
var alive: bool = true
var elite: bool = false
var level: Level
var facing: float = 1.0
## Set by a Defender that has this one by the throat; while it holds, we stop.
var blocked_by: Defender = null

var _flash: float = 0.0
var _anim: float = 0.0
var _spawn_timer: float = 0.0
var _last_pos: Vector2
var _chip: float = 1.0        # trailing health bar, drains toward hp
var _bar_show: float = 0.0
var _lean: float = 0.0
var _mat: ShaderMaterial
var _light: PointLight2D
var _flash_peak: float = 0.55
var _burn_dps: float = 0.0
var _burn_left: float = 0.0
var _attack_cd: float = 0.0
var _melee_cd: float = 0.0
var _aura_tick: float = 0.0
var _fire_flash: float = 0.0


## `scale_mods` carries the endless multipliers; campaign passes an empty dict.
func setup(t: int, lvl: Level, scale_mods: Dictionary = {}, is_elite: bool = false) -> void:
	type = t
	level = lvl
	elite = is_elite
	stats = Config.ENEMIES[t].duplicate()
	var hp_mul: float = float(scale_mods.get("hp", 1.0))
	var sp_mul: float = float(scale_mods.get("speed", 1.0))
	var rw_mul: float = float(scale_mods.get("reward", 1.0))
	if elite:
		hp_mul *= float(Config.ELITE["hp"])
		sp_mul *= float(Config.ELITE["speed"])
		rw_mul *= float(Config.ELITE["reward"])
		stats["armor"] = minf(0.95, float(stats["armor"]) + float(Config.ELITE["armor_bonus"]))
	stats["hp"] = float(stats["hp"]) * hp_mul * Boons.enemy_hp_mult()
	stats["speed"] = float(stats["speed"]) * sp_mul * Boons.enemy_speed_mult()
	stats["reward"] = int(round(float(stats["reward"]) * rw_mul))
	max_hp = stats["hp"]
	hp = max_hp
	speed = stats["speed"]
	radius = stats["radius"] * (1.12 if elite else 1.0)
	rotates = false
	loop = false
	z_index = 6 if t != Config.EnemyType.BOSS else 7
	_anim = randf() * TAU
	_spawn_timer = float(stats.get("spawn_every", 0.0))
	# A siege tower is ten times the area of a raider; the same flash strength
	# turns it into a white slab. Scale it down with size.
	_flash_peak = 0.55 * clampf(26.0 / radius, 0.30, 1.0)


func _ready() -> void:
	_last_pos = position
	_mat = Gfx.flash_material()
	if elite:
		_mat.set_shader_parameter("tint", Vector3(1.18, 0.86, 1.25))
	material = _mat
	scale = Vector2.ONE * Config.UNIT_SCALE * (1.12 if elite else 1.0)
	# Big siege engines carry their own fire.
	if type == Config.EnemyType.BOSS:
		_light = Gfx.make_light(Config.C_TORCH, 0.85, 260.0)
		_light.position = Vector2(0, -170)
		add_child(_light)
	elif type == Config.EnemyType.CART:
		_light = Gfx.make_light(Config.C_TORCH, 0.5, 150.0)
		_light.position = Vector2(0, -40)
		add_child(_light)
	# Spawn pop
	var target := scale
	scale = target * 0.4
	var tw := create_tween()
	tw.tween_property(self, "scale", target, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not Game.sim_mode and level != null:
		Fx.burst(level.fx_layer, global_position + Vector2(0, radius * 0.4), Config.C_SAND_DARK, 6, 90.0, 260.0, 0.4)


func _process(delta: float) -> void:
	if not alive:
		return
	var dt := delta * Game.speed
	_tick_burn(dt)
	if not alive:
		return
	var held := blocked_by != null and is_instance_valid(blocked_by) and blocked_by.alive
	if held:
		_fight(dt)
	else:
		blocked_by = null
		progress += speed * dt
	_tick_attack(dt)
	_tick_aura(dt)
	_anim += dt * (10.0 if type == Config.EnemyType.RUNNER else 6.0) * (0.6 if held else 1.0)
	var dx := position.x - _last_pos.x
	if absf(dx) > 0.3:
		facing = 1.0 if dx > 0.0 else -1.0
	_lean = lerpf(_lean, clampf(dx / maxf(dt, 0.001) / 900.0, -0.16, 0.16), minf(1.0, dt * 6.0))
	_last_pos = position
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 7.0)
		_mat.set_shader_parameter("flash", _flash * _flash_peak)
	if _bar_show > 0.0:
		_bar_show = maxf(0.0, _bar_show - delta)
	var target_frac := clampf(hp / max_hp, 0.0, 1.0)
	if _chip > target_frac:
		_chip = maxf(target_frac, _chip - delta * 0.55)
	if type == Config.EnemyType.BOSS and _spawn_timer > 0.0:
		_spawn_timer -= dt
		if _spawn_timer <= 0.0:
			_spawn_timer = float(stats["spawn_every"])
			var at := maxf(0.0, progress - 70.0)
			var r := level.spawn_enemy(Config.EnemyType.RAIDER, at)
			r.progress = at
	if progress_ratio >= 1.0:
		_arrive()
	queue_redraw()


## Sticky fire: naphtha keeps working long after the pot has landed.
func apply_burn(dps: float, seconds: float) -> void:
	if not alive:
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_left = maxf(_burn_left, seconds)


func is_burning() -> bool:
	return _burn_left > 0.0


func _tick_burn(dt: float) -> void:
	if _burn_left <= 0.0:
		return
	_burn_left -= dt
	_fire_flash = fmod(_fire_flash + dt * 9.0, TAU)
	# Burn ignores armour entirely; that is what makes it the answer to plate.
	hp -= _burn_dps * dt
	if hp <= 0.0:
		_die()


## Trading blows with the spearman holding us.
func _fight(dt: float) -> void:
	_melee_cd -= dt
	if _melee_cd > 0.0:
		return
	_melee_cd = 1.0
	if blocked_by != null and is_instance_valid(blocked_by):
		blocked_by.take_damage(melee_damage())


func melee_damage() -> float:
	return 6.0 + float(stats["cost"]) * 2.4


## Siege engines and horse archers shoot the emplacements as they come up.
func _tick_attack(dt: float) -> void:
	if not stats.has("attack"):
		return
	var a: Dictionary = stats["attack"]
	_attack_cd -= dt
	if _attack_cd > 0.0:
		return
	var t: Tower = level.nearest_tower(global_position, float(a["range"]))
	if t == null:
		return
	_attack_cd = 1.0 / float(a["rate"])
	var from := global_position + Vector2(0, -radius * 0.8)
	var shot := Projectile.new()
	shot.launch_at_tower(level, "rock" if bool(a.get("lob", false)) else "war_arrow",
		from, t, float(a["damage"]))
	level.projectiles.add_child(shot)
	Sfx.play("stone" if bool(a.get("lob", false)) else "arrow", -12.0)


## A shaman keeps the column on its feet. Kill it first.
func _tick_aura(dt: float) -> void:
	if not stats.has("aura"):
		return
	_aura_tick -= dt
	if _aura_tick > 0.0:
		return
	_aura_tick = 0.5
	var au: Dictionary = stats["aura"]
	var healed := 0
	for e in level.enemies_in_range(global_position, float(au["radius"])):
		if e == self or e.hp >= e.max_hp:
			continue
		e.hp = minf(e.max_hp, e.hp + float(au["heal"]) * 0.5)
		e.queue_redraw()
		healed += 1
	if healed > 0 and randf() < 0.35:
		Fx.ring(level.fx_layer, global_position, float(au["radius"]) * 0.5, Config.C_GOOD)
		Sfx.play("heal", -22.0)


func can_be_blocked() -> bool:
	return type != Config.EnemyType.BOSS and type != Config.EnemyType.CART 		and type != Config.EnemyType.CATAPULT


func _arrive() -> void:
	alive = false
	reached_gate.emit(self)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.2, 0.2), 0.2)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(queue_free)


## Predicted world position after t seconds, for lobbed shots.
func predict_position(t: float) -> Vector2:
	var p := minf(progress + speed * t, level.curve.get_baked_length())
	return level.path.to_global(level.curve.sample_baked(p))


func take_damage(amount: float, pierce: float, from: Vector2 = Vector2.INF) -> void:
	if not alive:
		return
	var blocked: float = maxf(0.0, float(stats["armor"]) - pierce)
	var dmg := amount * (1.0 - blocked)
	hp -= dmg
	_flash = 1.0
	_bar_show = 2.5
	_mat.set_shader_parameter("flash", _flash_peak)
	if blocked > 0.5:
		Sfx.play("armor", -10.0)
		if from != Vector2.INF:
			Fx.sparks(level.fx_layer, global_position + Vector2(0, -radius * 0.5),
				(global_position - from).normalized(), Config.C_IRON, 5, 260.0)
	else:
		Sfx.play("hit", -12.0)
	if hp <= 0.0:
		_die()
	queue_redraw()


func _die() -> void:
	if not alive:
		return
	alive = false
	if blocked_by != null and is_instance_valid(blocked_by) and blocked_by.target == self:
		blocked_by.target = null
	blocked_by = null
	if _light != null:
		_light.queue_free()
		_light = null
	_detonate()
	died.emit(self)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "scale", Vector2(1.35, 0.12) * Config.UNIT_SCALE * (1.12 if elite else 1.0), 0.2).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(queue_free)


## A sapper dies holding a charge. Anything built too close goes with him.
func _detonate() -> void:
	if not stats.has("blast"):
		return
	var b: Dictionary = stats["blast"]
	Fx.explosion(level.fx_layer, global_position, 0.85, Config.C_FIRE)
	level.shake(16.0, 0.4)
	level.damage_towers_in_range(global_position, float(b["radius"]), float(b["damage"]))


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	# Contact shadow, offset away from the moon (upper right).
	Gfx.draw_shadow(self, Vector2(-radius * 0.18, radius * 0.62), radius * 1.05, 0.36, 0.52)
	if elite:
		var pulse := 0.5 + 0.5 * sin(_anim * 0.9)
		draw_circle(Vector2(0, -radius * 0.3), radius * 1.5, Color(Config.C_ELITE, 0.10 + 0.06 * pulse))
	var step := sin(_anim)
	var heft: float = 0.055 if radius < 32.0 else 0.026
	var sq := Vector2(1.0 + heft * step, 1.0 - heft * step)
	draw_set_transform(Vector2(0, radius * 0.5 * heft * step), _lean, Vector2(facing * sq.x, sq.y))
	match type:
		Config.EnemyType.RAIDER:
			_draw_raider()
		Config.EnemyType.RUNNER:
			_draw_runner()
		Config.EnemyType.SHIELDMAN:
			_draw_shieldman()
		Config.EnemyType.HORSE_ARCHER:
			_draw_horse_archer()
		Config.EnemyType.CAVALRY:
			_draw_cavalry()
		Config.EnemyType.SAPPER:
			_draw_sapper()
		Config.EnemyType.SHAMAN:
			_draw_shaman()
		Config.EnemyType.CATAPULT:
			_draw_catapult()
		Config.EnemyType.CART:
			_draw_cart()
		Config.EnemyType.BOSS:
			_draw_boss()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _burn_left > 0.0:
		_draw_flames()
	if elite:
		_draw_crown()
	_draw_health()


## Flames licking off anything the naphtha has touched.
func _draw_flames() -> void:
	for i in range(4):
		var ph := _fire_flash + float(i) * 1.7
		var fx := sin(ph) * radius * 0.6
		var fy := -radius * (0.4 + 0.55 * absf(cos(ph * 0.7)))
		var sz := radius * 0.3 * (0.7 + 0.3 * sin(ph * 2.3))
		draw_circle(Vector2(fx, fy), sz * 1.7, Color(Config.C_FIRE, 0.18))
		draw_circle(Vector2(fx, fy), sz, Color(Config.C_FIRE, 0.8))
		draw_circle(Vector2(fx, fy - sz * 0.5), sz * 0.5, Color(Config.C_FIRE_HOT, 0.9))


func _draw_crown() -> void:
	var y := -radius * 2.0 - 6.0
	var pts := PackedVector2Array([
		Vector2(-15, y + 10), Vector2(-15, y), Vector2(-8, y + 5), Vector2(0, y - 4),
		Vector2(8, y + 5), Vector2(15, y), Vector2(15, y + 10),
	])
	draw_colored_polygon(pts, Config.C_ROCK)
	draw_circle(Vector2(0, y - 6), 3.0, Config.C_FIRE_HOT)


func _draw_health() -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	if frac >= 0.999 and _bar_show <= 0.0:
		return
	var w := radius * 2.3
	var h := 9.0 if type != Config.EnemyType.BOSS else 14.0
	var y := -radius * 1.95 - (16.0 if elite else 10.0)
	var rect := Rect2(-w / 2, y, w, h)
	# Trailing "chip" bar makes each hit legible.
	if _chip > frac:
		Gfx.draw_bar(self, rect, _chip, Color(0, 0, 0, 0.62), Color(1, 1, 1, 0.55), false)
		Gfx.draw_bar(self, rect, frac, Color(0, 0, 0, 0.0), _hp_color(frac))
	else:
		Gfx.draw_bar(self, rect, frac, Color(0, 0, 0, 0.62), _hp_color(frac))
	# Armour pips: one per 25% blocked.
	var armor := float(stats["armor"])
	if armor > 0.05:
		var pips := int(round(armor * 4.0))
		for i in range(pips):
			draw_circle(Vector2(-w / 2 + 5 + i * 9, y - 7), 3.0, Config.C_IRON)


func _hp_color(frac: float) -> Color:
	if frac > 0.55:
		return Config.C_THREAT
	if frac > 0.28:
		return Config.C_FIRE
	return Config.C_ROCK


func _bob() -> float:
	return sin(_anim) * 2.5


func _legs(y: float, c: Color, spread: float = 7.0) -> void:
	var s := sin(_anim) * spread
	draw_line(Vector2(-4, y), Vector2(-4 + s * 0.6, y + 10), c, 5.0)
	draw_line(Vector2(4, y), Vector2(4 - s * 0.6, y + 10), c, 5.0)


func _draw_raider() -> void:
	var b := _bob()
	var body := Color("4a3222")
	var skin := Color("d9a372")
	_legs(2, Color("2b1f14"))
	# Torso with a lit shoulder
	draw_circle(Vector2(0, -12 + b), 16, body)
	draw_circle(Vector2(-4, -16 + b), 11, body.lightened(0.12))
	draw_rect(Rect2(-14, -14 + b, 28, 8), Config.C_THREAT)
	draw_rect(Rect2(-14, -14 + b, 28, 3), Config.C_THREAT.lightened(0.25))
	# Head and fur hat
	draw_circle(Vector2(0, -34 + b), 11, skin)
	draw_circle(Vector2(-3, -36 + b), 7, skin.lightened(0.12))
	draw_circle(Vector2(0, -40 + b), 11, Color("2b1f14"))
	draw_rect(Rect2(-13, -40 + b, 26, 6), Color("3a2a1c"))
	# Curved sword catching the moon
	draw_arc(Vector2(18, -24 + b), 14, -1.9, -0.3, 8, Config.C_IRON, 3.5)
	draw_arc(Vector2(18, -24 + b), 14, -1.6, -0.7, 6, Config.C_IRON.lightened(0.4), 1.4)
	draw_line(Vector2(14, -14 + b), Vector2(19, -12 + b), Config.C_WOOD_DARK, 4.0)


func _draw_runner() -> void:
	var b := _bob()
	var body := Color("c9a63a")
	_legs(0, Color("6b5a2a"), 11.0)
	draw_circle(Vector2(0, -12 + b), 12, body)
	draw_circle(Vector2(-3, -15 + b), 8, body.lightened(0.14))
	draw_circle(Vector2(0, -31 + b), 9, Color("d9a372"))
	# Trailing scarf, two ribbons out of phase
	var s := sin(_anim * 1.3) * 4.0
	var s2 := sin(_anim * 1.3 - 0.9) * 5.0
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -30 + b), Vector2(-26, -26 + b + s), Vector2(-24, -20 + b + s), Vector2(-4, -24 + b)]), Config.C_THREAT)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -27 + b), Vector2(-32, -19 + b + s2), Vector2(-30, -14 + b + s2), Vector2(-4, -21 + b)]), Config.C_THREAT_DARK)
	draw_line(Vector2(6, -18 + b), Vector2(20, -30 + b), Config.C_IRON, 2.5)


func _draw_shieldman() -> void:
	var b := _bob() * 0.6
	_legs(6, Color("2b1f14"))
	draw_circle(Vector2(0, -10 + b), 18, Color("3a2a1c"))
	draw_circle(Vector2(-5, -14 + b), 12, Color("48362a"))
	draw_circle(Vector2(0, -36 + b), 11, Color("d9a372"))
	draw_rect(Rect2(-12, -50 + b, 24, 10), Config.C_IRON_DARK)  # helmet
	draw_rect(Rect2(-12, -50 + b, 24, 3), Config.C_IRON)
	# Spear
	draw_line(Vector2(-16, 10 + b), Vector2(-10, -62 + b), Config.C_WOOD, 3.5)
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -62 + b), Vector2(-16, -70 + b), Vector2(-4, -70 + b)]), Config.C_IRON)
	# Big round shield, riveted
	draw_circle(Vector2(8, -14 + b), 28, Color(0, 0, 0, 0.3))
	draw_circle(Vector2(6, -16 + b), 26, Config.C_IRON_DARK)
	draw_circle(Vector2(6, -16 + b), 22, Config.C_IRON)
	draw_circle(Vector2(2, -20 + b), 14, Config.C_IRON.lightened(0.14))
	draw_circle(Vector2(6, -16 + b), 8, Config.C_THREAT)
	draw_arc(Vector2(6, -16 + b), 15, 0, TAU, 20, Config.C_IRON_DARK, 2.0)
	for i in range(6):
		var a := float(i) / 6.0 * TAU
		draw_circle(Vector2(6, -16 + b) + Vector2(cos(a), sin(a)) * 19.0, 2.0, Config.C_IRON_DARK)


func _draw_cart() -> void:
	var wob := sin(_anim * 0.7) * 1.5
	for wx in [-26.0, 26.0]:
		draw_circle(Vector2(wx, 14), 15, Config.C_WOOD_DARK)
		draw_circle(Vector2(wx, 14), 10, Config.C_WOOD)
		var a := _anim * 0.5
		draw_line(Vector2(wx, 14) + Vector2(cos(a), sin(a)) * 10, Vector2(wx, 14) - Vector2(cos(a), sin(a)) * 10, Config.C_WOOD_DARK, 3.0)
		draw_line(Vector2(wx, 14) + Vector2(-sin(a), cos(a)) * 10, Vector2(wx, 14) - Vector2(-sin(a), cos(a)) * 10, Config.C_WOOD_DARK, 3.0)
	draw_rect(Rect2(-40, -30 + wob, 80, 44), Config.C_WOOD)
	draw_rect(Rect2(-40, -30 + wob, 80, 8), Config.C_WOOD_DARK)
	draw_rect(Rect2(-40, -22 + wob, 80, 4), Color(Config.C_SAND_LIGHT, 0.18))
	for i in range(3):
		draw_rect(Rect2(-38 + i * 28, -32 + wob, 6, 48), Config.C_IRON_DARK)
	for i in range(3):
		var y := -22.0 + i * 14.0 + wob
		draw_colored_polygon(PackedVector2Array([Vector2(40, y - 5), Vector2(58, y), Vector2(40, y + 5)]), Config.C_IRON)
		draw_line(Vector2(44, y - 2), Vector2(56, y), Config.C_IRON.lightened(0.4), 1.2)
	# Brazier on the deck
	var f := 1.0 + sin(_anim * 3.0) * 0.2
	draw_circle(Vector2(0, -36 + wob), 9 * f, Config.C_FIRE)
	draw_circle(Vector2(0, -40 + wob), 5 * f, Config.C_FIRE_HOT)
	draw_line(Vector2(-30, -30 + wob), Vector2(-30, -70 + wob), Config.C_WOOD_DARK, 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-30, -70 + wob), Vector2(-6, -62 + wob), Vector2(-30, -52 + wob)]), Config.C_THREAT)


func _draw_boss() -> void:
	var wob := sin(_anim * 0.5) * 2.0
	for wx in [-44.0, -15.0, 15.0, 44.0]:
		draw_circle(Vector2(wx, 26), 13, Config.C_WOOD_DARK)
		draw_circle(Vector2(wx, 26), 8, Config.C_WOOD)
	var base := Rect2(-55, -150 + wob, 110, 176)
	draw_rect(base, Config.C_WOOD)
	draw_rect(Rect2(-55, -150 + wob, 14, 176), Config.C_WOOD_DARK)
	draw_rect(Rect2(-30, -150 + wob, 10, 176), Color(Config.C_SAND_LIGHT, 0.08))
	for i in range(3):
		var y := -140.0 + i * 56.0 + wob
		draw_rect(Rect2(-55, y + 46, 110, 8), Config.C_WOOD_DARK)
		draw_rect(Rect2(-18, y + 10, 36, 22), Config.C_WINDOW)
		draw_rect(Rect2(-16, y + 12, 32, 18), Color(Config.C_FIRE, 0.35))
		draw_rect(Rect2(-48, y + 14, 8, 14), Config.C_WINDOW)
		draw_rect(Rect2(40, y + 14, 8, 14), Config.C_WINDOW)
	# Iron plating on the leading face
	draw_rect(Rect2(41, -150 + wob, 14, 176), Config.C_IRON_DARK)
	for i in range(6):
		draw_circle(Vector2(48, -140 + wob + i * 30), 2.5, Config.C_IRON)
	# Top platform with crew
	draw_rect(Rect2(-62, -166 + wob, 124, 18), Config.C_WOOD_DARK)
	draw_rect(Rect2(-62, -166 + wob, 124, 4), Color(Config.C_SAND_LIGHT, 0.15))
	for i in range(4):
		draw_rect(Rect2(-60 + i * 34, -176 + wob, 14, 12), Config.C_WOOD_DARK)
	for hx in [-30.0, 0.0, 30.0]:
		draw_circle(Vector2(hx, -186 + wob), 7, Color("d9a372"))
		draw_circle(Vector2(hx, -192 + wob), 7, Color("2b1f14"))
	# Signal fire on the roof
	var f := 1.0 + sin(_anim * 4.0) * 0.22
	draw_circle(Vector2(0, -172 + wob), 16 * f, Color(Config.C_FIRE, 0.25))
	draw_circle(Vector2(0, -174 + wob), 8 * f, Config.C_FIRE)
	draw_circle(Vector2(0, -178 + wob), 4 * f, Config.C_FIRE_HOT)
	for bx in [-50.0, 50.0]:
		draw_line(Vector2(bx, -166 + wob), Vector2(bx, -230 + wob), Config.C_WOOD_DARK, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(bx, -230 + wob), Vector2(bx + 34, -218 + wob), Vector2(bx, -200 + wob)]), Config.C_THREAT)


## Mounted bowman: fast, harasses emplacements from outside oil range.
func _draw_horse_archer() -> void:
	var b := _bob() * 0.5
	var gallop := sin(_anim * 1.4)
	# Horse
	draw_line(Vector2(-20, 8), Vector2(-22 + gallop * 7, 22), Color("2f2118"), 5.0)
	draw_line(Vector2(14, 8), Vector2(16 - gallop * 7, 22), Color("2f2118"), 5.0)
	draw_line(Vector2(-8, 10), Vector2(-10 - gallop * 5, 22), Color("241a12"), 5.0)
	draw_line(Vector2(22, 10), Vector2(24 + gallop * 5, 22), Color("241a12"), 5.0)
	draw_rect(Rect2(-24, -8 + b * 0.5, 50, 20), Color("4a3626"))
	draw_rect(Rect2(-24, -8 + b * 0.5, 50, 6), Color("5c4431"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(24, -6 + b * 0.5), Vector2(40, -20 + b * 0.5), Vector2(46, -12 + b * 0.5),
		Vector2(34, -2 + b * 0.5), Vector2(24, 4 + b * 0.5),
	]), Color("4a3626"))
	draw_circle(Vector2(41, -17 + b * 0.5), 3.0, Color("120d08"))
	# Tail
	draw_line(Vector2(-24, -4 + b * 0.5), Vector2(-38, 8 + gallop * 3), Color("2f2118"), 4.0)
	# Rider
	draw_circle(Vector2(-2, -24 + b), 12, Color("6b4a2c"))
	draw_rect(Rect2(-14, -26 + b, 24, 6), Config.C_THREAT)
	draw_circle(Vector2(-2, -42 + b), 9, Color("d9a372"))
	draw_circle(Vector2(-2, -47 + b), 9, Color("2b1f14"))
	# Recurve bow, drawn back
	var pull := 1.0 if _attack_cd > 0.45 else 0.4
	var bc := Vector2(12, -32 + b)
	draw_arc(bc, 15, -2.0, 2.0, 12, Config.C_WOOD_DARK, 3.0)
	draw_line(bc + Vector2(cos(-2.0), sin(-2.0)) * 15, bc + Vector2(-6 * pull, 0),
		Config.C_SAND_LIGHT, 1.5)
	draw_line(bc + Vector2(cos(2.0), sin(2.0)) * 15, bc + Vector2(-6 * pull, 0),
		Config.C_SAND_LIGHT, 1.5)
	# Quiver
	draw_rect(Rect2(-20, -30 + b, 9, 18), Config.C_WOOD_DARK)
	for i in range(3):
		draw_line(Vector2(-18 + i * 3, -30 + b), Vector2(-20 + i * 3, -42 + b), Config.C_SAND_LIGHT, 1.5)


## Keshik heavy horse: armoured, quick, costs two lives at the gate.
func _draw_cavalry() -> void:
	var b := _bob() * 0.4
	var gallop := sin(_anim * 1.2)
	for lx in [-22.0, 16.0, -6.0, 26.0]:
		draw_line(Vector2(lx, 8), Vector2(lx + gallop * 6, 24), Color("241a12"), 6.0)
	# Barded horse
	draw_rect(Rect2(-28, -10 + b, 58, 24), Color("3a2a1c"))
	draw_rect(Rect2(-28, -10 + b, 58, 7), Config.C_IRON_DARK)
	for i in range(5):
		draw_rect(Rect2(-26 + i * 12, -3 + b, 9, 16), Color(Config.C_IRON, 0.55))
	draw_colored_polygon(PackedVector2Array([
		Vector2(28, -8 + b), Vector2(46, -24 + b), Vector2(53, -15 + b),
		Vector2(39, -3 + b), Vector2(28, 5 + b),
	]), Color("3a2a1c"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(36, -18 + b), Vector2(48, -23 + b), Vector2(44, -12 + b),
	]), Config.C_IRON)
	draw_circle(Vector2(46, -19 + b), 3.0, Config.C_THREAT)
	# Rider in lamellar
	draw_circle(Vector2(-4, -28 + b), 14, Config.C_IRON_DARK)
	for i in range(3):
		draw_rect(Rect2(-17, -34 + b + i * 8, 26, 5), Color(Config.C_IRON, 0.8))
	draw_circle(Vector2(-4, -48 + b), 10, Color("d9a372"))
	draw_rect(Rect2(-14, -58 + b, 20, 11), Config.C_IRON_DARK)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-14, -58 + b), Vector2(6, -58 + b), Vector2(-4, -70 + b),
	]), Config.C_IRON)
	draw_line(Vector2(-4, -70 + b), Vector2(-4, -80 + b), Config.C_THREAT, 3.0)
	# Lance couched forward
	draw_line(Vector2(-24, -14 + b), Vector2(48, -30 + b), Config.C_WOOD, 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(48, -34 + b), Vector2(62, -30 + b), Vector2(48, -26 + b),
	]), Config.C_IRON)


## Sapper hauling a powder charge. Killing him near your line is a mistake.
func _draw_sapper() -> void:
	var b := _bob()
	var fuse := 0.5 + 0.5 * sin(_anim * 3.0)
	_legs(2, Color("2b1f14"))
	draw_circle(Vector2(0, -12 + b), 15, Color("3f3226"))
	draw_circle(Vector2(-4, -15 + b), 10, Color("4c3d2d"))
	draw_circle(Vector2(0, -32 + b), 10, Color("d9a372"))
	# Rag over the face
	draw_rect(Rect2(-10, -32 + b, 20, 7), Color("6d5a45"))
	draw_circle(Vector2(0, -38 + b), 10, Color("2b1f14"))
	# The charge, slung under one arm
	draw_circle(Vector2(15, -8 + b), 13, Config.C_IRON_DARK)
	draw_circle(Vector2(12, -11 + b), 7, Color(Config.C_IRON, 0.5))
	draw_rect(Rect2(10, -22 + b, 10, 6), Config.C_WOOD_DARK)
	# Lit fuse, sparking
	draw_line(Vector2(15, -22 + b), Vector2(22, -34 + b), Config.C_WOOD_DARK, 2.0)
	draw_circle(Vector2(22, -34 + b), 3.5 * fuse + 1.5, Color(Config.C_FIRE, 0.35))
	draw_circle(Vector2(22, -34 + b), 2.2 * fuse + 1.0, Config.C_FIRE_HOT)


## Shaman with a drum: heals the column while it climbs.
func _draw_shaman() -> void:
	var b := _bob() * 0.8
	var pulse := 0.5 + 0.5 * sin(_anim * 1.3)
	draw_circle(Vector2(0, -14 + b), radius * 1.5, Color(Config.C_GOOD, 0.07 + 0.05 * pulse))
	_legs(4, Color("2b1f14"))
	# Long robe
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 8), Vector2(16, 8), Vector2(11, -26 + b), Vector2(-11, -26 + b),
	]), Color("5a4a6b"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, 8), Vector2(-2, 8), Vector2(-4, -26 + b), Vector2(-11, -26 + b),
	]), Color("6d5c80"))
	draw_circle(Vector2(0, -34 + b), 10, Color("d9a372"))
	# Antlered headdress
	draw_circle(Vector2(0, -40 + b), 10, Color("3a2a1c"))
	for sx in [-1.0, 1.0]:
		draw_line(Vector2(sx * 6, -46 + b), Vector2(sx * 15, -62 + b), Color("d8cbb0"), 2.5)
		draw_line(Vector2(sx * 11, -54 + b), Vector2(sx * 21, -56 + b), Color("d8cbb0"), 2.0)
	# Frame drum, struck on the beat
	var beat := 1.0 + 0.12 * sin(_anim * 3.0)
	draw_circle(Vector2(16, -18 + b), 15 * beat, Config.C_WOOD_DARK)
	draw_circle(Vector2(16, -18 + b), 12 * beat, Color("c8ab84"))
	draw_arc(Vector2(16, -18 + b), 12 * beat, 0, TAU, 18, Config.C_WOOD_DARK, 1.5)
	draw_line(Vector2(-14, -20 + b), Vector2(4, -14 + b + sin(_anim * 3.0) * 4.0), Config.C_WOOD, 2.5)


## Manjaniq: a crewed stone-thrower that shells your emplacements from range.
func _draw_catapult() -> void:
	var wob := sin(_anim * 0.6) * 1.2
	var fired := clampf(_attack_cd * 1.2, 0.0, 1.0)
	for wx in [-30.0, 30.0]:
		draw_circle(Vector2(wx, 20), 14, Config.C_WOOD_DARK)
		draw_circle(Vector2(wx, 20), 9, Config.C_WOOD)
		var a := _anim * 0.4
		draw_line(Vector2(wx, 20) + Vector2(cos(a), sin(a)) * 9,
			Vector2(wx, 20) - Vector2(cos(a), sin(a)) * 9, Config.C_WOOD_DARK, 2.5)
	# Frame
	draw_rect(Rect2(-40, -6 + wob, 80, 22), Config.C_WOOD)
	draw_rect(Rect2(-40, -6 + wob, 80, 6), Config.C_WOOD_DARK)
	draw_line(Vector2(-22, -6 + wob), Vector2(0, -48 + wob), Config.C_WOOD_DARK, 6.0)
	draw_line(Vector2(22, -6 + wob), Vector2(0, -48 + wob), Config.C_WOOD_DARK, 6.0)
	# Throwing arm: down after a shot, cocked back as it reloads
	var arm_a := lerpf(-2.5, -0.7, fired)
	var pivot := Vector2(0, -46 + wob)
	var tip := pivot + Vector2(cos(arm_a), sin(arm_a)) * 46.0
	draw_line(pivot, tip, Config.C_WOOD, 7.0)
	draw_line(pivot, pivot - Vector2(cos(arm_a), sin(arm_a)) * 18.0, Config.C_WOOD_DARK, 9.0)
	# Counterweight
	draw_circle(pivot - Vector2(cos(arm_a), sin(arm_a)) * 22.0, 11, Config.C_IRON_DARK)
	# Sling and stone, only while loaded
	if fired > 0.45:
		draw_line(tip, tip + Vector2(6, 18), Config.C_SAND_LIGHT, 1.5)
		draw_circle(tip + Vector2(6, 22), 8, Color("8a8580"))
	draw_circle(pivot, 6, Config.C_IRON)
	# Crew hauling the ropes
	for cx in [-30.0, 32.0]:
		draw_circle(Vector2(cx, -18 + wob), 8, Color("4a3222"))
		draw_circle(Vector2(cx, -30 + wob), 6, Color("d9a372"))
