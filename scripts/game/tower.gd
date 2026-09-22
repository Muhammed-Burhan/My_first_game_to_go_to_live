class_name Tower
extends Node2D
## A defensive emplacement on a slot. Six kinds, three tiers each, drawn
## procedurally so every tier reads differently at a glance.
##
## Emplacements are no longer invulnerable scenery: manjaniq crews shell them,
## horse archers pepper them and sappers blow them up. A wrecked one frees its
## slot to be rebuilt.

signal destroyed(tower: Tower)

var type: int = 0
var tier: int = 1
var stats: Dictionary = {}
var slot: Slot
var level: Level
var hp: float = 100.0
var max_hp: float = 100.0
var wrecked: bool = false
var selected: bool = false:
	set(v):
		selected = v
		queue_redraw()

var defenders: Array[Defender] = []

var _cooldown: float = 0.0
var _aim: float = -PI / 2.0
var _recoil: float = 0.0
var _muzzle: float = 0.0
var _t: float = 0.0
var _target: Enemy = null
var _light: PointLight2D
var _idle_seed: float = 0.0
var _flash: float = 0.0
var _respawns: Array[float] = []
var _mat: ShaderMaterial
var _shots: int = 0


func setup(t: int, s: Slot, lvl: Level) -> void:
	type = t
	slot = s
	level = lvl
	tier = 1
	stats = Boons.tower_stats(type, tier)
	max_hp = Boons.tower_hp(type, tier)
	hp = max_hp


func _ready() -> void:
	_idle_seed = randf() * TAU
	_mat = Gfx.flash_material()
	material = _mat
	if type == Config.TowerType.OIL or type == Config.TowerType.NAPHTHA:
		_light = Gfx.make_light(Config.C_TORCH, 0.9, 210.0)
		_light.position = Vector2(0, -40)
		add_child(_light)
	scale = Vector2(0.2, 0.2)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * Config.UNIT_SCALE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if Config.has_garrison(type):
		call_deferred("_muster")


func upgrade() -> void:
	tier += 1
	stats = Boons.tower_stats(type, tier)
	var frac := hp / max_hp
	max_hp = Boons.tower_hp(type, tier)
	hp = max_hp * maxf(frac, 0.6)
	if _light != null:
		_light.energy = 0.9 + 0.25 * (tier - 1)
		_light.texture_scale = (210.0 + 40.0 * (tier - 1)) / 128.0
	if Config.has_garrison(type):
		_muster()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE * Config.UNIT_SCALE * 1.2, 0.1)
	tw.tween_property(self, "scale", Vector2.ONE * Config.UNIT_SCALE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func total_invested() -> int:
	return Config.tower_total_invested(type, tier)


## What it costs to put this emplacement back to full. Free when undamaged.
func repair_cost() -> int:
	var missing := 1.0 - hp / max_hp
	if missing < 0.02:
		return 0
	return Boons.repair_cost(int(round(total_invested() * 0.45 * missing)))


func repair() -> void:
	hp = max_hp
	_flash = 0.0
	queue_redraw()


## 0 at the moment of firing, 1 when fully reloaded. Drives the archer's draw.
func reload_ratio() -> float:
	if float(stats["rate"]) <= 0.0:
		return 1.0
	var period := 1.0 / float(stats["rate"])
	return clampf(1.0 - _cooldown / period, 0.0, 1.0)


func damage_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


# ------------------------------------------------------------------ combat

func take_damage(amount: float) -> void:
	if wrecked:
		return
	hp -= Boons.tower_damage_taken(amount)
	_flash = 1.0
	_mat.set_shader_parameter("flash", 0.85)
	_mat.set_shader_parameter("flash_color", Vector3(1.0, 0.45, 0.3))
	Sfx.play("tower_hit", -10.0)
	Fx.sparks(level.fx_layer, global_position + Vector2(0, -40), Vector2(0, -1), Config.C_SAND_LIGHT, 6, 220.0)
	if hp <= 0.0:
		_wreck()
	queue_redraw()


func _wreck() -> void:
	if wrecked:
		return
	wrecked = true
	for d in defenders:
		if is_instance_valid(d):
			d.queue_free()
	defenders.clear()
	Fx.explosion(level.fx_layer, global_position + Vector2(0, -30), 1.0, Config.C_FIRE)
	Fx.float_text(level.fx_layer, global_position + Vector2(0, -90), "WRECKED", Config.C_THREAT, 40, "crit")
	Sfx.play("tower_down", -2.0)
	level.shake(18.0, 0.5)
	var back := int(round(total_invested() * Boons.salvage_fraction()))
	if back > 0:
		Game.add_rock(back, false)
		Fx.float_text(level.fx_layer, global_position + Vector2(0, -50), "+%d SALVAGE" % back, Config.C_ROCK, 32)
	if slot != null:
		slot.tower = null
		slot.rubble = true
		slot.queue_redraw()
	destroyed.emit(self)
	queue_free()


func _process(delta: float) -> void:
	var dt := delta * Game.speed
	_t += dt
	if _recoil > 0.0:
		_recoil = maxf(0.0, _recoil - dt * 6.0)
	if _muzzle > 0.0:
		_muzzle = maxf(0.0, _muzzle - dt * 9.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		_mat.set_shader_parameter("flash", _flash * 0.7)
	if Config.has_garrison(type):
		_tick_garrison(dt)
	elif Game.running and level.phase == "wave" and float(stats["rate"]) > 0.0:
		_cooldown -= dt
		_acquire()
		if _target != null:
			var dir := _target.global_position - global_position
			_aim = lerp_angle(_aim, dir.angle(), minf(1.0, dt * 12.0))
			if _cooldown <= 0.0:
				_fire()
	if _light != null:
		var f := 0.8 + 0.2 * sin(_t * 9.0 + _idle_seed) + 0.08 * sin(_t * 21.0)
		_light.energy = (0.75 + 0.2 * (tier - 1)) * f
	# Archers only redraw when something is actually moving.
	if type != Config.TowerType.ARCHER or _recoil > 0.0 or _muzzle > 0.0 or selected \
			or _target != null or _flash > 0.0 or hp < max_hp:
		queue_redraw()


func _acquire() -> void:
	var reach: float = stats["range"]
	var dead_zone: float = float(stats.get("min_range", 0.0))
	if _target != null and (not is_instance_valid(_target) or not _target.alive
			or _target.global_position.distance_to(global_position) > reach * 1.05):
		_target = null
	if _target != null:
		return
	var best: Enemy = null
	var best_prog := -1.0
	for e in level.enemies_in_range(global_position, reach):
		# Siege engines cannot depress onto their own feet.
		if dead_zone > 0.0 and e.global_position.distance_to(global_position) < dead_zone:
			continue
		# Furthest along the path first: it is the one about to hurt the gate.
		if e.progress > best_prog:
			best_prog = e.progress
			best = e
	_target = best


func _fire() -> void:
	_cooldown = 1.0 / float(stats["rate"])
	_recoil = 1.0
	_muzzle = 1.0
	var from := global_position + Vector2(0, -60)
	if type == Config.TowerType.BALLISTA or type == Config.TowerType.MANGONEL:
		from = global_position + Vector2(cos(_aim), sin(_aim)) * 30.0 + Vector2(0, -34)
	_shots += 1
	var p := Projectile.new()
	var every := Boons.barrage_every()
	if every > 0 and _shots % every == 0:
		p.launch(level, "stone", from, _target, _barrage_stats())
		Sfx.play("stone", -3.0)
		level.shake(8.0, 0.22)
	else:
		p.launch(level, stats["projectile"], from, _target, stats)
	level.projectiles.add_child(p)
	match type:
		Config.TowerType.ARCHER:
			Sfx.play("arrow", -8.0, 0.12)
		Config.TowerType.OIL:
			Sfx.play("pot", -6.0)
		Config.TowerType.NAPHTHA:
			Sfx.play("naft", -9.0, 0.14)
		Config.TowerType.BALLISTA:
			Sfx.play("bolt", -2.0)
			level.shake(3.0, 0.12)
		Config.TowerType.MANGONEL:
			Sfx.play("stone", -1.0)
			level.shake(7.0, 0.2)
	queue_redraw()


## Borrowed mangonel shell for the Barrage boon, scaled off this emplacement.
func _barrage_stats() -> Dictionary:
	var d := Boons.tower_stats(Config.TowerType.MANGONEL, tier)
	d["damage"] = maxf(float(d["damage"]) * 0.55, float(stats["damage"]) * 1.6)
	return d


# ------------------------------------------------------------------ garrison

## Rally points sit on the road itself, spread either side of the post.
func _rally_point(i: int, count: int) -> Vector2:
	var spread := 52.0
	var offset := (float(i) - float(count - 1) * 0.5) * spread
	return level.path_point_near(global_position, offset)


func _muster() -> void:
	if level == null or not is_inside_tree():
		return
	var g: Dictionary = Config.TOWERS[type]["garrison"]
	var want := Boons.garrison_count(int(g["count"])) + (tier - 1)
	_prune()
	for i in range(defenders.size(), want):
		_spawn_defender(i, want)


func _spawn_defender(i: int, count: int) -> void:
	var g: Dictionary = Config.TOWERS[type]["garrison"]
	var d := Defender.new()
	var scaled := {
		"hp": float(g["hp"]) * pow(1.4, tier - 1),
		"damage": float(g["damage"]) * pow(Config.UPGRADE_DAMAGE_MULT, tier - 1),
		"rate": float(g["rate"]),
		"reach": float(g["reach"]),
	}
	d.setup(self, level, _rally_point(i, count), scaled)
	d.fell.connect(_on_defender_fell)
	level.add_child(d)
	defenders.append(d)


func _prune() -> void:
	var keep: Array[Defender] = []
	for d in defenders:
		if is_instance_valid(d) and d.alive:
			keep.append(d)
	defenders = keep


func _on_defender_fell(_d: Defender) -> void:
	var g: Dictionary = Config.TOWERS[type]["garrison"]
	_respawns.append(float(g["respawn"]))


func _tick_garrison(dt: float) -> void:
	_prune()
	var g: Dictionary = Config.TOWERS[type]["garrison"]
	var want := Boons.garrison_count(int(g["count"])) + (tier - 1)
	for i in range(_respawns.size() - 1, -1, -1):
		_respawns[i] -= dt
		if _respawns[i] <= 0.0:
			_respawns.remove_at(i)
			if defenders.size() < want:
				_spawn_defender(defenders.size(), want)
	# Between waves the post refills itself, so a bad wave is not permanent.
	if level.phase == "prep" and defenders.size() < want:
		_respawns.clear()
		_muster()


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if selected:
		_draw_range()
	Gfx.draw_shadow(self, Vector2(-8, 18), 46.0, 0.32, 0.55)
	match type:
		Config.TowerType.ARCHER:
			_draw_archer()
		Config.TowerType.GUARD:
			_draw_guard()
		Config.TowerType.OIL:
			_draw_oil()
		Config.TowerType.NAPHTHA:
			_draw_naphtha()
		Config.TowerType.BALLISTA:
			_draw_ballista()
		Config.TowerType.MANGONEL:
			_draw_mangonel()
	if _muzzle > 0.0:
		_draw_muzzle()
	_draw_tier_pips()
	_draw_damage()


## Dashed, slowly rotating range ring, with the dead zone marked for siege engines.
func _draw_range() -> void:
	var r: float = stats["range"]
	draw_circle(Vector2.ZERO, r, Color(Config.C_ROCK, 0.07))
	var segs := 48
	var spin := _t * 0.25
	for i in range(segs):
		if i % 2 == 1:
			continue
		var a0 := spin + float(i) / segs * TAU
		var a1 := spin + float(i + 0.85) / segs * TAU
		draw_arc(Vector2.ZERO, r, a0, a1, 4, Color(Config.C_ROCK, 0.8), 4.0)
	draw_arc(Vector2.ZERO, r, 0, TAU, 64, Color(Config.C_ROCK, 0.18), 2.0)
	var dead := float(stats.get("min_range", 0.0))
	if dead > 0.0:
		draw_circle(Vector2.ZERO, dead, Color(Config.C_THREAT, 0.10))
		draw_arc(Vector2.ZERO, dead, 0, TAU, 48, Color(Config.C_THREAT, 0.7), 3.0)


## A health bar plus smoke once the emplacement is really suffering.
func _draw_damage() -> void:
	var frac := damage_fraction()
	if frac > 0.995:
		return
	var w := 78.0
	Gfx.draw_bar(self, Rect2(-w / 2, 44, w, 9), frac, Color(0, 0, 0, 0.62),
		Config.C_GOOD if frac > 0.5 else (Config.C_FIRE if frac > 0.25 else Config.C_THREAT))
	if frac < 0.45:
		for i in range(3):
			var ph := _t * 1.4 + float(i) * 2.1
			var sy := -50.0 - fmod(ph * 26.0, 60.0)
			var sa := (1.0 - absf(sy + 80.0) / 60.0) * 0.28
			draw_circle(Vector2(sin(ph) * 14.0, sy), 11.0, Color(0.22, 0.2, 0.2, maxf(sa, 0.0)))


func _draw_muzzle() -> void:
	var a := _muzzle * _muzzle
	var at := Vector2(0, -60)
	if type == Config.TowerType.BALLISTA or type == Config.TowerType.MANGONEL:
		at = Vector2(cos(_aim), sin(_aim)) * 40.0 + Vector2(0, -34)
	Gfx.draw_glow(self, at, 46.0 * a, Config.C_FIRE_HOT, a * 1.4, 3)


func _draw_tier_pips() -> void:
	for i in range(tier):
		var p := Vector2(-12 + i * 12, 30)
		draw_circle(p, 5.5, Color(0, 0, 0, 0.45))
		draw_circle(p, 4.5, Config.C_ROCK)
		draw_circle(p + Vector2(-1.2, -1.2), 2.0, Config.C_FIRE_HOT)


func _draw_archer() -> void:
	var h := 40.0 + (tier - 1) * 18.0
	var wood := Config.C_WOOD
	var dark := Config.C_WOOD_DARK
	for lx in [-24.0, 24.0]:
		draw_line(Vector2(lx, 8), Vector2(lx * 0.8, -h), dark, 6.0)
	draw_line(Vector2(-20, -h * 0.5), Vector2(20, -h * 0.5), dark, 4.0)
	draw_line(Vector2(-22, 4), Vector2(20, -h * 0.75), Color(dark, 0.7), 3.0)
	draw_rect(Rect2(-32, -h - 12, 64, 12), wood)
	draw_rect(Rect2(-32, -h - 12, 64, 4), Config.C_SAND_LIGHT.darkened(0.25))
	draw_rect(Rect2(-32, -h - 2, 64, 3), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(-32, -h - 26, 4, 14), dark)
	draw_rect(Rect2(28, -h - 26, 4, 14), dark)
	draw_line(Vector2(-30, -h - 24), Vector2(30, -h - 24), dark, 2.5)
	var archers := 1 if tier < 3 else 2
	var draw_amt := reload_ratio() if _target != null else 0.0
	for i in range(archers):
		var ax := 0.0 if archers == 1 else (-14.0 + i * 28.0)
		var top := -h - 12.0
		var sway := sin(_t * 1.6 + _idle_seed + i) * 1.2
		draw_circle(Vector2(ax, top - 16 + sway), 11, Config.C_GOOD)
		draw_circle(Vector2(ax - 3, top - 19 + sway), 7, Config.C_GOOD.lightened(0.15))
		draw_circle(Vector2(ax, top - 33 + sway), 8, Color("d9a372"))
		draw_rect(Rect2(ax - 8, top - 40 + sway, 16, 5), Config.C_SAND_LIGHT)
		var bc := Vector2(ax + 14, top - 22 + sway)
		draw_arc(bc, 16, -1.35, 1.35, 10, dark, 3.0)
		var nock := bc + Vector2(-4.0 - 6.0 * draw_amt, 0)
		draw_line(bc + Vector2(cos(-1.35), sin(-1.35)) * 16, nock, Config.C_SAND_LIGHT, 1.5)
		draw_line(bc + Vector2(cos(1.35), sin(1.35)) * 16, nock, Config.C_SAND_LIGHT, 1.5)
		if draw_amt > 0.35:
			draw_line(nock, bc + Vector2(14, 0), Config.C_WOOD, 2.0)
	if tier >= 2:
		var ry := -h - 44.0
		draw_colored_polygon(PackedVector2Array([Vector2(-40, ry + 16), Vector2(40, ry + 16), Vector2(0, ry - 18)]), dark)
		draw_colored_polygon(PackedVector2Array([Vector2(-34, ry + 14), Vector2(34, ry + 14), Vector2(0, ry - 14)]), Config.C_THREAT_DARK.lerp(wood, 0.5))
		draw_colored_polygon(PackedVector2Array([Vector2(-34, ry + 14), Vector2(0, ry + 14), Vector2(0, ry - 14)]), Color(Config.C_SAND_LIGHT, 0.12))
		draw_line(Vector2(-42, ry + 16), Vector2(-32, -h - 26), dark, 4.0)
		draw_line(Vector2(42, ry + 16), Vector2(32, -h - 26), dark, 4.0)
	if tier >= 3:
		_draw_pennant(Vector2(0, -h - 62.0), 34.0)


## A walled post with a banner: the men themselves stand out on the road.
func _draw_guard() -> void:
	var stone := Config.C_SAND_DARK
	var lit := Config.C_SAND_LIGHT.darkened(0.18)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-34, 12), Vector2(34, 12), Vector2(28, -34), Vector2(-28, -34),
	]), stone)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-34, 12), Vector2(-14, 12), Vector2(-12, -34), Vector2(-28, -34),
	]), lit)
	# Course lines
	for row in range(4):
		draw_line(Vector2(-32 + row, 6 - row * 11), Vector2(32 - row, 6 - row * 11), Color(Config.C_SAND_DEEP, 0.4), 1.5)
	# Parapet with merlons
	draw_rect(Rect2(-36, -44, 72, 12), stone)
	draw_rect(Rect2(-36, -44, 72, 3), lit)
	var mx := -36.0
	while mx < 30.0:
		draw_rect(Rect2(mx, -56, 14, 13), stone)
		draw_rect(Rect2(mx, -56, 14, 3), lit)
		mx += 22.0
	# Weapon rack against the wall
	draw_line(Vector2(-24, -34), Vector2(-20, -66), Config.C_WOOD_DARK, 2.5)
	draw_line(Vector2(-16, -34), Vector2(-13, -66), Config.C_WOOD_DARK, 2.5)
	draw_colored_polygon(PackedVector2Array([Vector2(-22, -66), Vector2(-18, -74), Vector2(-16, -64)]), Config.C_IRON)
	# Brazier so the post reads at night
	var f := 1.0 + 0.18 * sin(_t * 9.0 + _idle_seed)
	draw_rect(Rect2(14, -58, 16, 6), Config.C_IRON_DARK)
	draw_circle(Vector2(22, -62), 12 * f, Color(Config.C_FIRE, 0.16))
	draw_circle(Vector2(22, -62), 6 * f, Config.C_FIRE)
	# Strength banner: one stripe per man still standing
	var g: Dictionary = Config.TOWERS[type]["garrison"]
	var want := Boons.garrison_count(int(g["count"])) + (tier - 1)
	for i in range(want):
		var alive_i := i < defenders.size() and is_instance_valid(defenders[i]) and defenders[i].alive
		draw_rect(Rect2(-34 + i * 12, -30, 9, 5), Config.C_GOOD if alive_i else Color(0.2, 0.2, 0.22, 0.8))
	if tier >= 3:
		_draw_pennant(Vector2(0, -56.0), 32.0)


func _draw_oil() -> void:
	var s := 1.0 + (tier - 1) * 0.22
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var stone := Color("8a8580")
	var stone_dark := Color("55504c")
	draw_colored_polygon(PackedVector2Array([Vector2(-30, 8), Vector2(30, 8), Vector2(22, -30), Vector2(-22, -30)]), stone)
	draw_colored_polygon(PackedVector2Array([Vector2(-30, 8), Vector2(-12, 8), Vector2(-8, -30), Vector2(-22, -30)]), stone_dark)
	draw_colored_polygon(PackedVector2Array([Vector2(12, 8), Vector2(30, 8), Vector2(22, -30), Vector2(14, -30)]), stone.lightened(0.1))
	draw_rect(Rect2(-34, -34, 68, 8), stone_dark)
	draw_rect(Rect2(-34, -34, 68, 2), stone.lightened(0.2))
	var fl := 1.0 + sin(_t * 14.0 + _idle_seed) * 0.15
	draw_circle(Vector2(0, -14), 22 * fl, Color(Config.C_FIRE, 0.18))
	draw_circle(Vector2(0, -14), 14 * fl, Config.C_FIRE)
	draw_circle(Vector2(-4, -18), 8 * fl, Config.C_FIRE_HOT)
	draw_circle(Vector2(0, -46), 24, Config.C_IRON_DARK)
	draw_circle(Vector2(-7, -52), 14, Color(Config.C_IRON, 0.35))
	draw_rect(Rect2(-26, -52, 52, 8), Config.C_IRON)
	draw_rect(Rect2(-20, -52, 40, 4), Color("2a1d10"))
	for i in range(tier + 1):
		var a := _t * 3.0 + i * 2.1
		var bx := sin(a) * 12.0
		var by := -54.0 - fmod(a * 9.0, 22.0)
		draw_circle(Vector2(bx, by), 3.0 + (i % 2), Color(Config.C_FIRE, 0.7))
	if tier >= 2:
		for fx in [-30.0, 30.0]:
			draw_line(Vector2(fx, 4), Vector2(fx, -50), Config.C_IRON_DARK, 4.0)
			var f2 := 1.0 + sin(_t * 11.0 + fx + _idle_seed) * 0.2
			draw_circle(Vector2(fx, -56), 14 * f2, Color(Config.C_FIRE, 0.16))
			draw_circle(Vector2(fx, -56), 8 * f2, Config.C_FIRE)
			draw_circle(Vector2(fx, -60), 4 * f2, Config.C_FIRE_HOT)
	if tier >= 3:
		draw_rect(Rect2(-40, -70, 80, 6), Config.C_IRON_DARK)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_pennant(Vector2(0, -70.0 * s), 30.0)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Naffatun: a pressurised siphon that throws sticky fire down the road.
func _draw_naphtha() -> void:
	var s := 1.0 + (tier - 1) * 0.16
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var brass := Color("b8863f")
	var brass_dark := Color("7a5628")
	# Timber trestle
	draw_line(Vector2(-26, 10), Vector2(-16, -20), Config.C_WOOD_DARK, 6.0)
	draw_line(Vector2(26, 10), Vector2(16, -20), Config.C_WOOD_DARK, 6.0)
	draw_rect(Rect2(-28, 8, 56, 7), Config.C_WOOD_DARK)
	# Copper reservoir, banded
	draw_circle(Vector2(0, -32), 25, brass_dark)
	draw_circle(Vector2(0, -32), 21, brass)
	draw_circle(Vector2(-7, -39), 10, brass.lightened(0.3))
	for i in range(3):
		draw_arc(Vector2(0, -32), 21 - i * 7, PI * 0.15, PI * 0.85, 14, brass_dark, 2.0)
	# Siphon nozzle, aimed down the road
	draw_set_transform(Vector2(0, -38), _aim * 0.35 - 0.35, Vector2(s, s))
	draw_rect(Rect2(0, -6, 40, 11), brass_dark)
	draw_rect(Rect2(0, -6, 40, 4), brass)
	draw_colored_polygon(PackedVector2Array([
		Vector2(40, -9), Vector2(56, -4), Vector2(56, 4), Vector2(40, 8),
	]), brass_dark)
	# Pilot flame at the muzzle
	var f := 1.0 + 0.28 * sin(_t * 17.0 + _idle_seed)
	draw_circle(Vector2(58, 0), 12 * f, Color(Config.C_FIRE, 0.2))
	draw_circle(Vector2(58, 0), 6 * f, Config.C_FIRE)
	draw_circle(Vector2(61, -1), 3 * f, Config.C_FIRE_HOT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# Pump handle, rocking as it fires
	var rock := sin(_t * 6.0) * 0.25 + _recoil * 0.5
	draw_line(Vector2(-18, -28), Vector2(-40, -44 + rock * 14.0), Config.C_IRON_DARK, 4.0)
	draw_circle(Vector2(-40, -44 + rock * 14.0), 5, Config.C_WOOD_DARK)
	if tier >= 2:
		# Spare naphtha jars
		for jx in [-30.0, 30.0]:
			draw_circle(Vector2(jx, 0), 9, Color("4a3a2a"))
			draw_rect(Rect2(jx - 5, -8, 10, 5), brass_dark)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tier >= 3:
		_draw_pennant(Vector2(26, -50.0), 34.0)


func _draw_ballista() -> void:
	var wood := Config.C_WOOD
	var dark := Config.C_WOOD_DARK
	draw_rect(Rect2(-34, -10, 68, 18), dark)
	draw_rect(Rect2(-30, -12, 60, 8), wood)
	draw_rect(Rect2(-30, -12, 60, 2), Color(Config.C_SAND_LIGHT, 0.25))
	draw_rect(Rect2(-8, -40, 16, 32), dark)
	if tier >= 2:
		draw_rect(Rect2(-36, -6, 72, 6), Config.C_IRON_DARK)
		draw_rect(Rect2(-10, -40, 20, 6), Config.C_IRON)
	var pivot := Vector2(0, -34)
	draw_set_transform(pivot, _aim, Vector2.ONE)
	var arm := 34.0 + (tier - 1) * 6.0
	var draw_back := 14.0 * _recoil
	draw_rect(Rect2(-30, -5, 60, 10), wood)
	draw_rect(Rect2(-30, -5, 60, 3), Config.C_SAND_LIGHT.darkened(0.3))
	draw_arc(Vector2(4, 0), arm, PI * 0.5 - 0.35, PI * 0.5 + 0.35, 8, dark, 6.0)
	draw_arc(Vector2(4, 0), arm, -PI * 0.5 - 0.35, -PI * 0.5 + 0.35, 8, dark, 6.0)
	draw_line(Vector2(4, -arm), Vector2(4, arm), dark, 5.0)
	var tip_a := Vector2(4 + arm * sin(0.35), -arm * cos(0.35))
	var tip_b := Vector2(4 + arm * sin(0.35), arm * cos(0.35))
	var nock := Vector2(-14 + draw_back, 0)
	draw_line(tip_a, nock, Config.C_SAND_LIGHT, 2.0)
	draw_line(tip_b, nock, Config.C_SAND_LIGHT, 2.0)
	if _recoil < 0.5:
		draw_line(Vector2(-14, 0), Vector2(30, 0), Config.C_IRON, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(30, -5), Vector2(40, 0), Vector2(30, 5)]), Config.C_IRON_DARK)
	if tier >= 3:
		draw_rect(Rect2(-30, -8, 12, 16), Config.C_IRON)
		draw_rect(Rect2(14, -8, 12, 16), Config.C_IRON)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tier >= 3:
		_draw_pennant(Vector2(-30, -10.0), 70.0)


## Manjaniq: a traction trebuchet. Its arm falls as it throws and winches back up.
func _draw_mangonel() -> void:
	var wood := Config.C_WOOD
	var dark := Config.C_WOOD_DARK
	var s := 1.0 + (tier - 1) * 0.12
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	# Heavy timber bed
	draw_rect(Rect2(-46, -4, 92, 20), dark)
	draw_rect(Rect2(-46, -4, 92, 6), wood)
	for i in range(4):
		draw_rect(Rect2(-42 + i * 24, -2, 7, 18), Color(Config.C_SAND_LIGHT, 0.1))
	# A-frame
	draw_line(Vector2(-26, -4), Vector2(0, -62), dark, 8.0)
	draw_line(Vector2(26, -4), Vector2(0, -62), dark, 8.0)
	draw_line(Vector2(-15, -32), Vector2(15, -32), dark, 5.0)
	if tier >= 2:
		draw_rect(Rect2(-30, -8, 60, 6), Config.C_IRON_DARK)
	# Throwing arm, keyed to the reload cycle
	var load_k := reload_ratio()
	var arm_a := lerpf(-2.75, -0.35, 1.0 - load_k) if _recoil > 0.0 else lerpf(-0.35, -2.75, load_k)
	var pivot := Vector2(0, -60)
	var tip := pivot + Vector2(cos(arm_a), sin(arm_a)) * (56.0 + (tier - 1) * 5.0)
	var butt := pivot - Vector2(cos(arm_a), sin(arm_a)) * 24.0
	draw_line(pivot, tip, wood, 8.0)
	draw_line(pivot, butt, dark, 11.0)
	draw_circle(butt, 14, Config.C_IRON_DARK)
	draw_circle(butt + Vector2(-3, -3), 7, Color(Config.C_IRON, 0.4))
	draw_circle(pivot, 7, Config.C_IRON)
	# Sling with a stone in it while loaded
	if load_k > 0.4:
		var sling := tip + Vector2(4, 20)
		draw_line(tip, sling, Config.C_SAND_LIGHT, 1.8)
		draw_circle(sling, 10, Color("8a8580"))
		draw_circle(sling + Vector2(-3, -3), 5, Color("a9a49e"))
	# Haul ropes
	for rx in [-34.0, 34.0]:
		draw_line(butt, Vector2(rx, 6), Color(Config.C_SAND_LIGHT, 0.45), 1.5)
	# Ammunition pile
	for i in range(3):
		draw_circle(Vector2(-40 + i * 9, 12 - (i % 2) * 7), 7, Color("7d7873"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tier >= 3:
		_draw_pennant(Vector2(34, -20.0), 60.0)


## Mast plus a wind-rippled pennant, used as the tier 3 badge on every tower.
func _draw_pennant(base: Vector2, height: float) -> void:
	var top := base + Vector2(0, -height)
	draw_line(base, top, Config.C_WOOD_DARK, 3.0)
	var f := sin(_t * 6.0 + _idle_seed) * 3.0
	draw_colored_polygon(PackedVector2Array([
		top, top + Vector2(30, 8 + f), top + Vector2(26, 12 + f * 0.6), top + Vector2(0, 18),
	]), Config.C_ROCK)
	draw_circle(top + Vector2(0, -3), 3.0, Config.C_FIRE_HOT)
