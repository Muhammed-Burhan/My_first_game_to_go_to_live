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


## True while naphtha or greek fire is still eating at it. The contracts ask
## for kills made with fire, and this is how a kill knows it was one.
func burning() -> bool:
	return _burn_left > 0.0


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
	# No backing radial: every mass now carries a real outline, which separates
	# far better than a dark pool behind it ever did.
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


## Top of the drawn art in local units, for the health bar and the elite crown.
## Humanoids are all drawn at one height whatever their hit radius; the siege
## engines scale with theirs. Placing the bar off `radius` alone put it through
## the middle of a siege tower and behind a raider's hat.
func _art_top() -> float:
	match type:
		Config.EnemyType.BOSS:
			return -radius * 4.8
		Config.EnemyType.CATAPULT:
			return -radius * 2.4
		Config.EnemyType.CART:
			return -radius * 2.0
		Config.EnemyType.HORSE_ARCHER, Config.EnemyType.CAVALRY:
			return -104.0
		_:
			return -92.0


func _draw_backing() -> void:
	var tex := Gfx.soft_light_texture()
	var r := radius * 2.3
	draw_texture_rect(tex, Rect2(-r, -r * 1.15 - radius * 0.25, r * 2.0, r * 2.0), false,
		Color(0.03, 0.02, 0.04, 0.55))


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
	var y := _art_top() - 4.0
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
	var y := _art_top() - (16.0 if elite else 8.0)
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


## A cold moon edge along the top of a mass. This is the cheap half of an
## outline: one arc per body part rather than a whole second black pass, and
## because it is cool light on a warm road it separates by temperature even
## where the values are close. It rides the facing flip, so it always runs down
## the leading edge of whatever is walking at you.
func _rim(c: Vector2, r: float, width: float = 2.6, alpha: float = 0.5) -> void:
	draw_arc(c, r - width * 0.5, -PI * 0.78, PI * 0.06, 8, Color(Config.C_FOE_RIM, alpha * 0.55), width)


# ---------------------------------------------------------------- the figure
#
# Every man on the mound is built from the same parts in the same proportions.
# The alternative is what this game had: ten units improvised out of stacked
# circles, none of which read as a person and several of which read as each
# other — the raider, the sapper and the shieldman were all "dark round blob".
#
# Three rules, all of them about being legible at 22px on a phone:
#
#   Big head.   A 12px head on a 22px unit is not anatomy, it is legibility.
#               It is the only part that still says "person" at thumbnail size,
#               so headgear sits on the crown and never covers the face.
#   One prop.   Each unit owns exactly one silhouette-defining object, held
#               clear of the body so it breaks the outline: a raised sabre, a
#               shield, a bomb, a drum. Two props make a blob again.
#   One accent. One saturated colour per unit, on cloth, so the eye sorts the
#               column by hue before it resolves a single shape.
#
# Local space: origin between the feet, -y is up, +x is the way they walk.
# Nothing in here may call draw_set_transform: _draw() has already set the
# facing flip, and a second call replaces it rather than composing with it.
# Rotate points with _rot() instead.


## Outline colour and weight. A heavy dark outline on every major mass is the
## single most identifiable thing about the look this is aiming at, and it does
## the separation job that the rim arc and the backing radial were both doing
## worse and more expensively.
const INK := Color("16121b")
const INK_W := 2.8


## Outlined circle, with a soft top-light. Three draws where there used to be
## one or two — affordable, because the background bake freed more than half
## the frame's draw calls and every unit on screen only ever accounted for 567
## of them.
func _oc(c: Vector2, r: float, col: Color, lit: float = 0.16) -> void:
	draw_circle(c, r + INK_W, INK)
	draw_circle(c, r, col)
	if lit > 0.0:
		draw_circle(c - Vector2(r * 0.14, r * 0.3), r * 0.68, col.lightened(lit))


## Outlined polygon. draw_polyline rides the edge, so the fill covers its inner
## half and what is left showing is one INK_W of outline.
func _op(pts: PackedVector2Array, col: Color) -> void:
	var ring := pts.duplicate()
	ring.append(pts[0])
	draw_polyline(ring, INK, INK_W * 2.0)
	draw_colored_polygon(pts, col)


## Outlined limb.
func _ol(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	draw_line(a, b, INK, w + INK_W * 2.0)
	draw_line(a, b, col, w)


## Rotate a local polygon and plant it at `at`. Stands in for the transform
## stack, which the facing flip has already spent.
func _rot(pts: PackedVector2Array, at: Vector2, ang: float) -> PackedVector2Array:
	var c := cos(ang)
	var s := sin(ang)
	var out := PackedVector2Array()
	for p in pts:
		out.append(at + Vector2(p.x * c - p.y * s, p.x * s + p.y * c))
	return out


## Two legs that swing, each ending in a boot. The trailing leg is darkened
## rather than recoloured, which is all the depth cueing these need.
func _legs(hip_y: float, cloth: Color, stride: float = 9.0) -> void:
	var s := sin(_anim) * stride
	var boot := cloth.darkened(0.34)
	# Back leg first so the front one overlaps it cleanly.
	for i in [1, 0]:
		var swing := s if i == 0 else -s
		var col := cloth.darkened(0.3) if i == 1 else cloth
		var hip := Vector2(-2.5 if i == 1 else 2.5, hip_y)
		var foot := hip + Vector2(swing, 18.0)
		_ol(hip, foot, 10.0, col)
		# Big boot. Chunky feet are half of why this style reads as toy-like
		# rather than as a stick figure.
		_oc(foot + Vector2(1.0, 0.5), 5.0, boot if i == 0 else boot.darkened(0.2), 0.1)


## A coat: wide at the shoulder, narrow at the waist, with a sash across it.
func _torso(top_y: float, bot_y: float, cloth: Color, sash: Color,
		half_top: float = 13.0, half_bot: float = 9.5) -> void:
	# Rounded barrel rather than a flat trapezoid: the outline has to curve or
	# the figure reads as folded paper.
	_op(PackedVector2Array([
		Vector2(-half_bot, bot_y), Vector2(half_bot, bot_y),
		Vector2(half_top + 1.0, top_y + 5.0), Vector2(half_top - 2.0, top_y - 2.0),
		Vector2(-half_top + 2.0, top_y - 2.0), Vector2(-half_top - 1.0, top_y + 5.0),
	]), cloth)
	# Lit front half, so the figure has a light side without a second pass.
	draw_colored_polygon(PackedVector2Array([
		Vector2(1, bot_y - 1.0), Vector2(half_bot - 1.0, bot_y - 1.0),
		Vector2(half_top - 1.0, top_y + 3.0), Vector2(1, top_y + 1.0),
	]), cloth.lightened(0.13))
	if sash.a > 0.0:
		var y := lerpf(top_y, bot_y, 0.42)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-half_top, y - 3.5), Vector2(half_top, y - 6.5),
			Vector2(half_top, y + 2.0), Vector2(-half_top, y + 5.0),
		]), sash)


## An arm, shoulder to hand, with the hand drawn. `back` puts it behind the
## body in shade.
func _arm(from: Vector2, to: Vector2, cloth: Color, back: bool = false) -> void:
	var col := cloth.darkened(0.32) if back else cloth.lightened(0.1)
	_ol(from, to, 7.5, col)
	# Mitten hand. Oversized hands are the other half of the toy proportions.
	_oc(to, 5.2, Config.C_FOE_SKIN.darkened(0.12 if back else 0.0), 0.12)


## The head, and the reason a unit reads at all: skin, a shaded jaw, a brow
## band and one eye. Drawn in profile facing +x.
func _head(c: Vector2, r: float, skin: Color) -> void:
	_oc(c, r, skin, 0.14)
	# Jaw shadow under the cheek, so the head is a ball with a face on it
	# rather than a ball.
	draw_circle(c + Vector2(-r * 0.1, r * 0.42), r * 0.62, skin.darkened(0.16))
	_face(c, r)


## Two eyes and a pair of angry brows, in three-quarter view. This is the whole
## difference between a soldier and a bead: a unit with an expression reads as
## something that wants to kill you even at 22px.
func _face(c: Vector2, r: float) -> void:
	var near := c + Vector2(r * 0.42, -r * 0.02)
	var far := c + Vector2(r * 0.02, -r * 0.06)
	draw_circle(far, r * 0.21, Color("f4f0ea"))
	draw_circle(near, r * 0.26, Color("f4f0ea"))
	draw_circle(far + Vector2(r * 0.06, r * 0.02), r * 0.115, INK)
	draw_circle(near + Vector2(r * 0.07, r * 0.02), r * 0.145, INK)
	draw_line(far + Vector2(-r * 0.2, -r * 0.3), far + Vector2(r * 0.18, -r * 0.2), INK, r * 0.15)
	draw_line(near + Vector2(-r * 0.2, -r * 0.22), near + Vector2(r * 0.24, -r * 0.34), INK, r * 0.17)


## A Mongol fur cap: a dome on the crown with a turned-up brim. The old art
## dropped a full-size dark circle over the whole head, which is exactly how
## every raider became an anonymous ball.
func _cap_fur(c: Vector2, r: float, fur: Color) -> void:
	_oc(c + Vector2(0.5, -r * 0.62), r * 0.82, fur, 0.18)
	_op(PackedVector2Array([
		c + Vector2(-r * 1.02, -r * 0.5), c + Vector2(r * 1.02, -r * 0.5),
		c + Vector2(r * 0.96, -r * 0.82), c + Vector2(-r * 0.96, -r * 0.82),
	]), fur.lightened(0.24))
	_oc(c + Vector2(0.5, -r * 1.5), r * 0.16, Config.C_FOE_CLOTH, 0.0)


## A conical steel helm with a brow band and a nose guard.
func _helm(c: Vector2, r: float, steel: Color) -> void:
	_op(PackedVector2Array([
		c + Vector2(-r * 1.02, -r * 0.38), c + Vector2(r * 1.02, -r * 0.38),
		c + Vector2(r * 0.2, -r * 1.9),
	]), steel)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -r * 0.42), c + Vector2(r * 0.9, -r * 0.42),
		c + Vector2(r * 0.2, -r * 1.75),
	]), steel.lightened(0.3))
	_op(PackedVector2Array([
		c + Vector2(-r * 1.06, -r * 0.56), c + Vector2(r * 1.06, -r * 0.56),
		c + Vector2(r * 1.06, -r * 0.26), c + Vector2(-r * 1.06, -r * 0.26),
	]), steel.darkened(0.32))
	draw_rect(Rect2(c.x + r * 0.46, c.y - r * 0.5, r * 0.24, r * 0.86), steel.darkened(0.12))


## A curved sabre, filled rather than stroked: an arc at this size reads as a
## bent piece of wire.
func _sabre(hilt: Vector2, ang: float, length: float = 30.0) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for i in range(9):
		var a := lerpf(-0.3, 1.45, float(i) / 8.0)
		outer.append(Vector2(cos(a), -sin(a)) * length)
	for i in range(8, -1, -1):
		var t := float(i) / 8.0
		var a := lerpf(-0.3, 1.45, t)
		inner.append(Vector2(cos(a), -sin(a)) * (length - lerpf(6.0, 1.5, t)))
	draw_colored_polygon(_rot(outer + inner, hilt, ang), Config.C_IRON.lightened(0.2))
	draw_colored_polygon(_rot(inner, hilt, ang), Config.C_IRON.lightened(0.45))
	draw_colored_polygon(_rot(PackedVector2Array([
		Vector2(-4, -3.5), Vector2(8, -3.5), Vector2(8, 3.5), Vector2(-4, 3.5),
	]), hilt, ang), Config.C_FOE_TIMBER_DARK)


## A horse in profile. Both mounted units share it, so a horse reads as a horse
## either way and the difference between them is the rider and the barding.
func _horse(hide: Color, tack: Color, barded: bool = false) -> void:
	var g := sin(_anim * 1.25)
	var dark := hide.darkened(0.34)
	var g2 := sin(_anim * 1.25 + 2.3)
	# Far pair first, in shade.
	for spec in [[-15.0, g2], [17.0, -g2]]:
		var x: float = spec[0]
		var sw: float = spec[1]
		draw_line(Vector2(x, -14), Vector2(x + sw * 8.0, 11), dark.darkened(0.2), 5.5)
		draw_rect(Rect2(x + sw * 8.0 - 3.5, 9.0, 7.0, 4.0), dark.darkened(0.35))
	# Barrel, rump and chest.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-25, -13), Vector2(21, -15), Vector2(25, -29), Vector2(-21, -31),
	]), hide)
	draw_circle(Vector2(-20, -22), 12.0, hide)
	draw_circle(Vector2(19, -22), 11.0, hide.lightened(0.08))
	# Neck and head.
	draw_colored_polygon(PackedVector2Array([
		Vector2(15, -28), Vector2(26, -24), Vector2(38, -44), Vector2(28, -49),
	]), hide.lightened(0.05))
	draw_colored_polygon(PackedVector2Array([
		Vector2(28, -49), Vector2(38, -44), Vector2(48, -46), Vector2(46, -53),
		Vector2(34, -55),
	]), hide.lightened(0.1))
	draw_colored_polygon(PackedVector2Array([
		Vector2(31, -55), Vector2(35, -63), Vector2(38, -54),
	]), dark)
	draw_circle(Vector2(45, -49), 1.8, Color("120f16"))
	# Mane and tail.
	for i in range(5):
		var t := float(i) / 4.0
		var p := Vector2(28, -49).lerp(Vector2(17, -29), t)
		draw_line(p, p + Vector2(-5, -4), dark, 3.5)
	for i in range(3):
		draw_line(Vector2(-24, -27 + i * 2), Vector2(-38 - i * 2, -12 + i * 5 + g * 3), dark, 3.5)
	# Near pair, lit.
	for spec2 in [[-13.0, -g], [19.0, g]]:
		var x2: float = spec2[0]
		var sw2: float = spec2[1]
		draw_line(Vector2(x2, -14), Vector2(x2 + sw2 * 8.0, 11), hide.darkened(0.12), 6.0)
		draw_rect(Rect2(x2 + sw2 * 8.0 - 3.5, 9.0, 7.0, 4.5), dark.darkened(0.2))
	if barded:
		# Lamellar skirt over the flank.
		for i in range(4):
			draw_rect(Rect2(-18 + i * 11, -20, 9, 13), Color(Config.C_IRON, 0.75))
			draw_rect(Rect2(-18 + i * 11, -20, 9, 3), Color(Config.C_IRON.lightened(0.3), 0.8))
	# Saddle blanket: the accent that says which side this horse is on.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-12, -30), Vector2(10, -31), Vector2(13, -20), Vector2(-15, -19),
	]), tack)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-15, -19), Vector2(13, -20), Vector2(12, -16), Vector2(-14, -15),
	]), tack.darkened(0.3))
	_rim(Vector2(19, -22), 11.0, 2.4, 0.4)


## Fodder, and the unit the player sees a hundred times a run, so it carries
## the most design: crimson sash, fur cap, and a sabre held high where it
## breaks the head's outline and makes the silhouette unmistakable.
func _draw_raider() -> void:
	var b := _bob()
	var cloth := Config.C_FOE_BODY
	var hc := Vector2(1.0, -42.0 + b)
	_sabre(Vector2(-13, -38 + b), -1.05, 23.0)
	_arm(Vector2(-6, -30 + b), Vector2(-14, -40 + b), cloth, true)
	_legs(-11.0 + b, Config.C_FOE_DARK.lightened(0.1), 9.0)
	_torso(-33.0 + b, -9.0 + b, cloth, Config.C_FOE_CLOTH)
	_head(hc, 14.5, Config.C_FOE_SKIN)
	_cap_fur(hc, 14.5, Config.C_FOE_DARK)
	_arm(Vector2(6, -29 + b), Vector2(19, -22 + b), cloth)


## Punishes gaps in coverage, so it has to read as SPEED before it reads as
## anything else: thin, pitched forward, and trailing two ribbons of scarf.
func _draw_runner() -> void:
	var b := _bob() * 1.4
	var cloth := Config.C_FOE_BODY_HI.lightened(0.05)
	var hc := Vector2(3.0, -38.0 + b)
	var s := sin(_anim * 1.2) * 5.0
	var s2 := sin(_anim * 1.2 - 0.8) * 7.0
	# Scarf first: it is most of the silhouette. Tapered to a point and in the
	# faction's accent, against a plain leather body so it is clearly cloth in
	# the wind and not a limb.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, -37 + b), Vector2(-2, -25 + b), Vector2(-20, -20 + b + s2),
		Vector2(-34, -27 + b + s), Vector2(-19, -30 + b + s2 * 0.5),
	]), Config.C_FOE_CLOTH)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, -30 + b), Vector2(-2, -25 + b), Vector2(-20, -20 + b + s2),
	]), Config.C_FOE_CLOTH_DARK)
	_legs(-10.0 + b, Config.C_FOE_DARK.lightened(0.18), 13.0)
	_torso(-30.0 + b, -8.0 + b, cloth, Config.C_FOE_CLOTH, 10.5, 7.5)
	_head(hc, 13.0, Config.C_FOE_SKIN)
	# Topknot rather than a cap: bare-headed reads as light and fast.
	draw_circle(hc + Vector2(-1, -9), 5.0, Config.C_FOE_DARK)
	draw_line(hc + Vector2(-4, -11), hc + Vector2(-13, -16), Config.C_FOE_DARK, 3.5)
	# Knife, thrown forward.
	_arm(Vector2(5, -27 + b), Vector2(20, -31 + b), cloth)
	draw_colored_polygon(PackedVector2Array([
		Vector2(21, -33 + b), Vector2(36, -34 + b), Vector2(21, -29 + b),
	]), Config.C_IRON.lightened(0.25))


## Armour with legs. The shield is the whole silhouette, so it sits forward and
## low and the head is deliberately kept above its rim — a unit whose face you
## cannot see is a unit the player cannot read.
func _draw_shieldman() -> void:
	var b := _bob() * 0.55
	var cloth := Config.C_FOE_BODY.darkened(0.1)
	var hc := Vector2(-2.0, -46.0 + b)
	# Spear, angled back over the shoulder.
	draw_line(Vector2(-14, 8 + b), Vector2(-2, -70 + b), Config.C_FOE_TIMBER, 4.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-2, -70 + b), Vector2(-8, -80 + b), Vector2(4, -80 + b),
	]), Config.C_IRON.lightened(0.2))
	_legs(-13.0 + b, Config.C_FOE_DARK, 6.0)
	_torso(-36.0 + b, -11.0 + b, cloth, Config.C_FOE_CLOTH_DARK, 14.0, 10.5)
	_head(hc, 14.0, Config.C_FOE_SKIN)
	_helm(hc, 14.0, Config.C_IRON)
	# The shield: planted in front, rim proud, boss catching the light.
	var sc := Vector2(15, -24 + b)
	draw_circle(sc + Vector2(2, 3), 25.0, Color(0, 0, 0, 0.35))
	draw_circle(sc, 25.0, Config.C_IRON_DARK)
	draw_circle(sc, 21.5, Config.C_FOE_TIMBER)
	for i in range(5):
		var a := -PI * 0.5 + float(i) / 5.0 * TAU
		draw_line(sc, sc + Vector2(cos(a), sin(a)) * 21.0, Config.C_FOE_TIMBER_DARK, 2.5)
	draw_circle(sc, 8.5, Config.C_FOE_CLOTH)
	draw_circle(sc + Vector2(-2, -2), 5.0, Config.C_IRON.lightened(0.3))
	draw_arc(sc, 23.0, 0, TAU, 28, Config.C_IRON_DARK, 3.0)
	_rim(sc, 25.0, 3.0, 0.55)


## Hunched around the charge he is carrying. The bomb is the silhouette and the
## lit fuse is the warning: both are held out front where they cannot be missed.
func _draw_sapper() -> void:
	var b := _bob()
	var cloth := Config.C_FOE_BODY.darkened(0.18)
	var hc := Vector2(-1.0, -38.0 + b)
	var fuse := 0.5 + 0.5 * sin(_anim * 4.0)
	_legs(-10.0 + b, Config.C_FOE_DARK, 7.0)
	_torso(-30.0 + b, -8.0 + b, cloth, Color(0, 0, 0, 0), 12.5, 10.0)
	_head(hc, 13.5, Config.C_FOE_SKIN)
	# Hood, drawn over the crown and down the back of the neck.
	draw_colored_polygon(PackedVector2Array([
		hc + Vector2(-13, 4), hc + Vector2(-13, -9), hc + Vector2(-2, -15),
		hc + Vector2(6, -11), hc + Vector2(-3, -8), hc + Vector2(-5, 7),
	]), cloth.lightened(0.18))
	draw_circle(hc + Vector2(-5, -9), 6.0, cloth.lightened(0.26))
	# The charge, hugged to the chest.
	var bc := Vector2(17, -22 + b)
	draw_circle(bc + Vector2(1, 2), 13.0, Color(0, 0, 0, 0.3))
	draw_circle(bc, 12.5, Config.C_IRON_DARK)
	draw_circle(bc + Vector2(-3, -4), 6.0, Config.C_IRON.lightened(0.15))
	draw_rect(Rect2(bc.x - 3, bc.y - 16, 7, 6), Config.C_FOE_TIMBER_DARK)
	_arm(Vector2(6, -26 + b), Vector2(12, -20 + b), cloth)
	# Fuse, sparking.
	draw_line(bc + Vector2(0, -15), bc + Vector2(8, -27), Config.C_FOE_TIMBER_DARK, 2.5)
	draw_circle(bc + Vector2(8, -27), 4.5 * fuse + 2.0, Color(Config.C_FIRE, 0.35))
	draw_circle(bc + Vector2(8, -27), 2.4 * fuse + 1.2, Config.C_FIRE_HOT)


## Heals the column, so it is the real target and has to announce itself: the
## tallest humanoid, robed in the colour of the aura it projects, with an
## antlered headdress breaking the outline.
func _draw_shaman() -> void:
	var b := _bob() * 0.7
	var pulse := 0.5 + 0.5 * sin(_anim * 1.3)
	var robe := Config.C_GOOD.darkened(0.42)
	var hc := Vector2(0.0, -46.0 + b)
	draw_circle(Vector2(0, -24 + b), radius * 1.55, Color(Config.C_GOOD, 0.07 + 0.05 * pulse))
	# Staff, held back, with a ring of bone at the top.
	draw_line(Vector2(-18, 10 + b), Vector2(-14, -56 + b), Config.C_FOE_TIMBER, 4.5)
	draw_arc(Vector2(-14, -62 + b), 7.0, 0, TAU, 18, Color("d8cbb0"), 3.2)
	draw_circle(Vector2(-14, -62 + b), 3.0, Config.C_GOOD)
	for i in range(3):
		var fa := float(i) / 3.0 * TAU + _anim * 0.3
		draw_line(Vector2(-14, -62 + b), Vector2(-14, -62 + b) + Vector2(cos(fa), sin(fa)) * 11.0,
			Color(Config.C_GOOD, 0.45), 1.8)
	_legs(-12.0 + b, robe.darkened(0.3), 5.0)
	# A robe, not a coat: it falls to the ankles.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-17, 8 + b), Vector2(17, 8 + b), Vector2(12, -34 + b), Vector2(-12, -34 + b),
	]), robe)
	draw_colored_polygon(PackedVector2Array([
		Vector2(1, 8 + b), Vector2(17, 8 + b), Vector2(12, -34 + b), Vector2(1, -34 + b),
	]), robe.lightened(0.14))
	draw_circle(Vector2(0, -32 + b), 13.0, robe)
	_rim(Vector2(0, -32 + b), 13.0)
	_head(hc, 13.5, Config.C_FOE_SKIN)
	# Antlered headdress.
	_oc(hc + Vector2(0, -9), 9.5, Config.C_FOE_DARK, 0.15)
	# Antlers, rooted in the headdress rather than hovering over it, and thick
	# enough to survive being 22px tall.
	for side in [-1.0, 1.0]:
		var root := hc + Vector2(side * 6, -12)
		var mid := hc + Vector2(side * 14, -24)
		var tip := hc + Vector2(side * 13, -34)
		draw_line(root, mid, Color("d8cbb0"), 4.0)
		draw_line(mid, tip, Color("d8cbb0"), 3.4)
		draw_line(mid, hc + Vector2(side * 24, -25), Color("d8cbb0"), 3.0)
		draw_circle(tip, 1.8, Color("efe6d2"))
	# Frame drum, struck on the beat.
	var beat := 1.0 + 0.1 * sin(_anim * 3.0)
	var dc := Vector2(19, -22 + b)
	draw_circle(dc + Vector2(1, 2), 15.0 * beat, Color(0, 0, 0, 0.3))
	draw_circle(dc, 14.5 * beat, Config.C_FOE_TIMBER_DARK)
	draw_circle(dc, 11.5 * beat, Color("c8ab84"))
	draw_arc(dc, 11.5 * beat, 0, TAU, 20, Config.C_FOE_TIMBER_DARK, 1.6)
	draw_line(Vector2(-6, -26 + b), Vector2(9, -20 + b + sin(_anim * 3.0) * 4.0),
		Config.C_FOE_TIMBER, 2.8)


## Mounted bowman: fast, and harasses emplacements from outside oil range. The
## read is the Parthian shot — twisted in the saddle, bow drawn.
func _draw_horse_archer() -> void:
	var b := _bob() * 0.4
	var cloth := Config.C_FOE_BODY
	var hc := Vector2(-2.0, -58.0 + b)
	_horse(Config.C_FOE_HORSE, Config.C_FOE_CLOTH)
	# Rider: legs astride, torso, head.
	draw_line(Vector2(0, -32 + b), Vector2(8, -18 + b), cloth.darkened(0.25), 7.0)
	_torso(-48.0 + b, -28.0 + b, cloth, Config.C_FOE_CLOTH, 11.0, 9.0)
	_head(hc, 13.5, Config.C_FOE_SKIN)
	_cap_fur(hc, 13.5, Config.C_FOE_DARK)
	# Recurve bow, drawn.
	var pull: float = 1.0 if _attack_cd > 0.45 else 0.45
	# Held high and inboard so it clears the horse's neck entirely.
	var bc := Vector2(10, -58 + b)
	for arc in [[-2.1, -0.2], [0.2, 2.1]]:
		var a0: float = arc[0]
		var a1: float = arc[1]
		draw_arc(bc, 14.0, a0, a1, 10, Config.C_FOE_TIMBER_DARK, 3.4)
	draw_line(bc + Vector2(cos(-2.1), sin(-2.1)) * 14.0, bc + Vector2(-6 * pull, 0),
		Color("e8dcc0"), 1.6)
	draw_line(bc + Vector2(cos(2.1), sin(2.1)) * 14.0, bc + Vector2(-6 * pull, 0),
		Color("e8dcc0"), 1.6)
	draw_line(bc + Vector2(-6 * pull, 0), bc + Vector2(18, 0), Color("e8dcc0"), 2.0)
	_arm(Vector2(4, -48 + b), bc + Vector2(-4, 2), cloth)
	# Quiver on the back.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-16, -44 + b), Vector2(-8, -46 + b), Vector2(-6, -30 + b), Vector2(-14, -28 + b),
	]), Config.C_FOE_TIMBER_DARK)
	for i in range(3):
		draw_line(Vector2(-14 + i * 3, -45 + b), Vector2(-17 + i * 3, -57 + b), Color("e8dcc0"), 1.6)


## Keshik heavy horse: armoured, quick, and two lives at the gate. Barded horse,
## couched lance, and a tall plume so it stands above everything around it.
func _draw_cavalry() -> void:
	var b := _bob() * 0.35
	var hc := Vector2(-2.0, -58.0 + b)
	_horse(Config.C_FOE_HORSE.darkened(0.12), Config.C_FOE_CLOTH_DARK, true)
	draw_line(Vector2(0, -32 + b), Vector2(8, -18 + b), Config.C_IRON_DARK, 7.5)
	# Lamellar coat rather than cloth.
	_torso(-48.0 + b, -28.0 + b, Config.C_IRON_DARK, Color(0, 0, 0, 0), 12.5, 10.0)
	for i in range(3):
		draw_rect(Rect2(-12, -45 + b + i * 6, 25, 4.5), Color(Config.C_IRON, 0.85))
	_head(hc, 13.5, Config.C_FOE_SKIN)
	_helm(hc, 13.5, Config.C_IRON.lightened(0.1))
	# Plume: the tallest thing in the wave, which is the point.
	for i in range(4):
		var t := float(i) / 3.0
		draw_line(hc + Vector2(2, -21 - i * 4), hc + Vector2(6 - t * 10, -28 - i * 5),
			Config.C_FOE_CLOTH, 3.0 - t)
	# Couched lance, levelled forward.
	draw_line(Vector2(-22, -36 + b), Vector2(44, -44 + b), Config.C_FOE_TIMBER, 4.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(44, -48 + b), Vector2(60, -44 + b), Vector2(44, -40 + b),
	]), Config.C_IRON.lightened(0.3))
	draw_colored_polygon(PackedVector2Array([
		Vector2(28, -43 + b), Vector2(40, -41 + b), Vector2(28, -35 + b),
	]), Config.C_FOE_CLOTH)
	_arm(Vector2(4, -42 + b), Vector2(16, -40 + b), Config.C_IRON_DARK)


func _draw_cart() -> void:
	var wob := sin(_anim * 0.7) * 1.5
	for wx in [-26.0, 26.0]:
		draw_circle(Vector2(wx, 14), 15, Config.C_FOE_TIMBER_DARK)
		draw_circle(Vector2(wx, 14), 10, Config.C_FOE_TIMBER)
		var a := _anim * 0.5
		draw_line(Vector2(wx, 14) + Vector2(cos(a), sin(a)) * 10, Vector2(wx, 14) - Vector2(cos(a), sin(a)) * 10, Config.C_FOE_TIMBER_DARK, 3.0)
		draw_line(Vector2(wx, 14) + Vector2(-sin(a), cos(a)) * 10, Vector2(wx, 14) - Vector2(-sin(a), cos(a)) * 10, Config.C_FOE_TIMBER_DARK, 3.0)
	draw_rect(Rect2(-40, -30 + wob, 80, 44), Config.C_FOE_TIMBER)
	draw_rect(Rect2(-40, -30 + wob, 80, 8), Config.C_FOE_TIMBER_DARK)
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
	draw_line(Vector2(-30, -30 + wob), Vector2(-30, -70 + wob), Config.C_FOE_TIMBER_DARK, 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-30, -70 + wob), Vector2(-6, -62 + wob), Vector2(-30, -52 + wob)]), Config.C_FOE_CLOTH)


## The siege tower, and the campaign's last wave. It has to read as a machine
## coming to kill you, not as a chest of drawers: so it tapers like a tower,
## carries a hide-clad face against fire, and the boarding ramp is already
## half-down before it reaches the gate.
func _draw_boss() -> void:
	var wob := sin(_anim * 0.5) * 2.0
	var timber := Config.C_FOE_TIMBER
	var dark := Config.C_FOE_TIMBER_DARK
	for wx in [-46.0, -16.0, 16.0, 46.0]:
		draw_circle(Vector2(wx, 28), 14, dark)
		draw_circle(Vector2(wx, 28), 9, timber)
		draw_circle(Vector2(wx, 28), 3, dark)
	# Tapered body. A rectangle reads as a cupboard; a taper reads as a tower.
	var top := -176.0 + wob
	var bot := 26.0 + wob
	draw_colored_polygon(PackedVector2Array([
		Vector2(-58, bot), Vector2(58, bot), Vector2(46, top), Vector2(-46, top),
	]), timber)
	# Lit leading half.
	draw_colored_polygon(PackedVector2Array([
		Vector2(4, bot), Vector2(58, bot), Vector2(46, top), Vector2(4, top),
	]), timber.lightened(0.09))
	# Cross-bracing: the single thing that says "built in a hurry out of beams".
	for i in range(3):
		var y0 := bot - (bot - top) * float(i) / 3.0
		var y1 := bot - (bot - top) * float(i + 1) / 3.0
		var w0 := lerpf(58.0, 46.0, float(i) / 3.0)
		var w1 := lerpf(58.0, 46.0, float(i + 1) / 3.0)
		draw_line(Vector2(-w0 + 8, y0 - 6), Vector2(w1 - 8, y1 + 6), dark, 5.0)
		draw_line(Vector2(w0 - 8, y0 - 6), Vector2(-w1 + 8, y1 + 6), dark, 5.0)
		draw_rect(Rect2(-w1, y1 - 5, w1 * 2.0, 10), dark)
	# Fire-proofing: soaked ox hides pegged over the leading face.
	for i in range(4):
		var hy := top + 16.0 + i * 44.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(30, hy), Vector2(54, hy - 3), Vector2(54, hy + 40), Vector2(30, hy + 42),
		]), Color("6b5a44"))
		draw_line(Vector2(32, hy + 2), Vector2(52, hy - 1), Color("50412f"), 2.5)
	# Archer slits with crew behind them.
	for i in range(3):
		var y := top + 34.0 + i * 52.0
		draw_rect(Rect2(-24, y, 34, 26), Config.C_WINDOW)
		draw_rect(Rect2(-22, y + 2, 30, 22), Color(Config.C_FIRE, 0.30))
		draw_circle(Vector2(-7, y + 16), 8, Config.C_FOE_DARK)
		draw_circle(Vector2(-7, y + 8), 6, Config.C_FOE_SKIN.darkened(0.3))
	# Fighting top, crowded with men.
	var pt := top - 16.0
	draw_rect(Rect2(-64, pt, 128, 18), dark)
	draw_rect(Rect2(-64, pt, 128, 4), Color(Config.C_SAND_LIGHT, 0.16))
	for i in range(5):
		draw_rect(Rect2(-62 + i * 28, pt - 12, 15, 13), dark)
	for hx in [-34.0, -2.0, 30.0]:
		draw_circle(Vector2(hx, pt - 12), 8, Config.C_FOE_BODY)
		draw_circle(Vector2(hx + 2, pt - 24), 7.5, Config.C_FOE_SKIN)
		draw_circle(Vector2(hx + 2, pt - 29), 7.5, Config.C_FOE_DARK)
		draw_line(Vector2(hx - 7, pt - 4), Vector2(hx - 11, pt - 44), Config.C_IRON_DARK, 2.5)
	# The boarding ramp, already coming down.
	var drop := 0.55 + 0.12 * sin(_anim * 0.7)
	var hinge := Vector2(50, pt + 6)
	var tip := hinge + Vector2(cos(-drop), sin(-drop)) * 62.0
	draw_line(hinge, tip, timber.lightened(0.05), 11.0)
	draw_line(hinge, tip, dark, 3.0)
	draw_line(hinge + Vector2(-6, -10), tip, Color("6b5a44"), 2.0)
	# Signal fire and banners.
	var f := 1.0 + sin(_anim * 4.0) * 0.22
	draw_circle(Vector2(-2, pt - 40), 18 * f, Color(Config.C_FIRE, 0.22))
	draw_circle(Vector2(-2, pt - 42), 9 * f, Config.C_FIRE)
	draw_circle(Vector2(-2, pt - 46), 4.5 * f, Config.C_FIRE_HOT)
	for bx in [-56.0, 56.0]:
		draw_line(Vector2(bx, pt + 16), Vector2(bx, pt - 76), dark, 4.5)
		var flap := sin(_anim * 1.4 + bx) * 5.0
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx, pt - 76), Vector2(bx + 38, pt - 62 + flap), Vector2(bx, pt - 44),
		]), Config.C_FOE_CLOTH)
		draw_colored_polygon(PackedVector2Array([
			Vector2(bx, pt - 76), Vector2(bx + 18, pt - 69 + flap * 0.5), Vector2(bx, pt - 58),
		]), Config.C_FOE_CLOTH_DARK)


## Manjaniq: a crewed stone-thrower that shells your emplacements from range.
func _draw_catapult() -> void:
	var wob := sin(_anim * 0.6) * 1.2
	var fired := clampf(_attack_cd * 1.2, 0.0, 1.0)
	for wx in [-30.0, 30.0]:
		draw_circle(Vector2(wx, 20), 14, Config.C_FOE_TIMBER_DARK)
		draw_circle(Vector2(wx, 20), 9, Config.C_FOE_TIMBER)
		var a := _anim * 0.4
		draw_line(Vector2(wx, 20) + Vector2(cos(a), sin(a)) * 9,
			Vector2(wx, 20) - Vector2(cos(a), sin(a)) * 9, Config.C_FOE_TIMBER_DARK, 2.5)
	# Frame
	draw_rect(Rect2(-40, -6 + wob, 80, 22), Config.C_FOE_TIMBER)
	draw_rect(Rect2(-40, -6 + wob, 80, 6), Config.C_FOE_TIMBER_DARK)
	draw_line(Vector2(-22, -6 + wob), Vector2(0, -48 + wob), Config.C_FOE_TIMBER_DARK, 6.0)
	draw_line(Vector2(22, -6 + wob), Vector2(0, -48 + wob), Config.C_FOE_TIMBER_DARK, 6.0)
	# Throwing arm: down after a shot, cocked back as it reloads
	var arm_a := lerpf(-2.5, -0.7, fired)
	var pivot := Vector2(0, -46 + wob)
	var tip := pivot + Vector2(cos(arm_a), sin(arm_a)) * 46.0
	draw_line(pivot, tip, Config.C_FOE_TIMBER, 7.0)
	draw_line(pivot, pivot - Vector2(cos(arm_a), sin(arm_a)) * 18.0, Config.C_FOE_TIMBER_DARK, 9.0)
	# Counterweight
	draw_circle(pivot - Vector2(cos(arm_a), sin(arm_a)) * 22.0, 11, Config.C_IRON_DARK)
	# Sling and stone, only while loaded
	if fired > 0.45:
		draw_line(tip, tip + Vector2(6, 18), Config.C_SAND_LIGHT, 1.5)
		draw_circle(tip + Vector2(6, 22), 8, Color("8a8580"))
	draw_circle(pivot, 6, Config.C_IRON)
	# Crew hauling the ropes. Two stacked circles read as pebbles; these at
	# least lean into the pull.
	for spec in [[-32.0, 1.0], [34.0, -1.0]]:
		var cx: float = spec[0]
		var face: float = spec[1]
		var pull := sin(_anim * 0.9 + cx) * 3.0
		var base := Vector2(cx + pull * face, 14 + wob)
		draw_line(base + Vector2(-4, 0), base + Vector2(-7, -14), Config.C_FOE_DARK, 5.0)
		draw_line(base + Vector2(4, 0), base + Vector2(6, -14), Config.C_FOE_DARK, 5.0)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-8, -12), base + Vector2(8, -12),
			base + Vector2(9 * face, -32), base + Vector2(-5 * face, -32),
		]), Config.C_FOE_BODY)
		draw_circle(base + Vector2(2 * face, -38), 8.5, Config.C_FOE_SKIN)
		draw_circle(base + Vector2(2 * face, -42), 8.0, Config.C_FOE_DARK)
		draw_line(base + Vector2(4 * face, -30), Vector2(0, -42 + wob), Color("c8b48c"), 2.0)
