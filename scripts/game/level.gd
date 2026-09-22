class_name Level
extends Node2D
## The single map: Erbil Citadel mound, one winding path, fixed tower slots,
## the gate at the top. Owns spawning, wave flow and tap handling, for both
## campaign (ten scripted waves) and endless (generated forever).
## Visuals are procedural (see background.gd, gate.gd, tower.gd, enemy.gd).

signal slot_tapped(slot: Slot)
signal tower_tapped(tower: Tower)
signal empty_tapped
signal phase_changed(phase: String)
signal wave_started(wave: int)
signal wave_cleared(wave: int)
signal milestone(wave: int, text: String)
signal draft_requested(wave: int)

const W := 1080.0
const H := 1920.0
const GATE_POS := Vector2(540, 458)
const TAP_RADIUS := 78.0
const MAX_SLOTS := 20

## The authored road, used by Campaign. Seeded modes generate their own.
const PATH_POINTS: Array[Vector2] = [
	Vector2(540, 1990), Vector2(525, 1770), Vector2(260, 1625), Vector2(165, 1470),
	Vector2(420, 1345), Vector2(800, 1285), Vector2(915, 1140), Vector2(690, 1030),
	Vector2(300, 985), Vector2(170, 845), Vector2(400, 725), Vector2(760, 695),
	Vector2(880, 585), Vector2(650, 505), Vector2(540, 458),
]

## Braziers lining the climb: light, plus a landmark for the eye. Derived from
## the road, so a seeded map gets its own.
var braziers: Array[Vector2] = []

var curve: Curve2D
var path: Path2D
var slots: Array[Slot] = []
var enemies: Node2D
var projectiles: Node2D
var fx_layer: Node2D
var gate: Gate
var commander: Commander
var background: Background
var post: PostFx

var phase: String = "idle"     # idle | prep | wave | done
var prep_left: float = 0.0
var next_wave: int = 1
var wave_size: int = 0         # how many spawns this wave had, for the HUD bar
var _spawn_list: Array = []
var _spawn_timer: float = 0.0
var _shake_time: float = 0.0
var _shake_strength: float = 0.0
var _shake_dir: Vector2 = Vector2.ZERO
var _shake_phase: float = 0.0
var _path_points_cache: PackedVector2Array
var _wave_scale: Dictionary = {}
var _current_seed: int = 0


func _ready() -> void:
	_build_path()
	_build_scene()
	_build_slots()
	Game.run_ended.connect(_on_run_ended)
	Game.lives_changed.connect(_on_lives_changed)
	set_process(true)


# ------------------------------------------------------------------ construction

## Rebuilds the road, the braziers and the emplacement slots for a seed.
## Campaign (seed 0) keeps the authored switchbacks; every other mode gets its
## own mound, which is what makes a Daily worth comparing.
func rebuild_for_seed(seed_value: int) -> void:
	for s in slots:
		s.queue_free()
	slots.clear()
	for c in get_children():
		if c is Brazier or c is Line2D or c is PathStones:
			c.queue_free()
	_build_path(seed_value)
	_build_road()
	if path != null:
		path.curve = curve
	_build_slots()


## A switchback climb: alternate left and right bands, always gaining height.
func _generate_path_points(seed_value: int) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pts: Array[Vector2] = [Vector2(540, 1990)]
	var legs := rng.randi_range(12, 15)
	var y := 1790.0
	var top := GATE_POS.y + 60.0
	var step := (y - top) / float(legs)
	var left := rng.randf() < 0.5
	for i in range(legs):
		# Squeeze the switchbacks inward as the mound narrows toward the gate.
		var k := float(i) / float(legs - 1)
		var band := lerpf(1.0, 0.55, k)
		var x: float
		if left:
			x = rng.randf_range(120.0, 380.0)
		else:
			x = rng.randf_range(700.0, 960.0)
		x = 540.0 + (x - 540.0) * band
		pts.append(Vector2(x, y))
		y -= step * rng.randf_range(0.82, 1.18)
		left = not left
	pts.append(Vector2(lerpf(pts[pts.size() - 1].x, GATE_POS.x, 0.55), GATE_POS.y + 70.0))
	pts.append(GATE_POS)
	return pts


## Brazier positions fall out of the road: one every few hundred pixels, set off
## to the side so they light the climb without standing in it.
func _place_braziers(rng: RandomNumberGenerator) -> void:
	braziers.clear()
	var length := curve.get_baked_length()
	var d := 320.0
	var side := 1.0
	while d < length - 240.0:
		var t := curve.sample_baked_with_rotation(d)
		var tangent: Vector2 = t.x.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var p: Vector2 = t.origin + normal * side * rng.randf_range(62.0, 78.0)
		if p.x > 70.0 and p.x < W - 70.0 and p.y > 560.0 and p.y < 1780.0:
			braziers.append(p)
		side = -side
		d += rng.randf_range(300.0, 420.0)


func _build_path(seed_value: int = 0) -> void:
	curve = Curve2D.new()
	curve.bake_interval = 8.0
	var pts: Array[Vector2] = PATH_POINTS
	if seed_value != 0:
		pts = _generate_path_points(seed_value)
	for i in range(pts.size()):
		var prev: Vector2 = pts[maxi(i - 1, 0)]
		var next: Vector2 = pts[mini(i + 1, pts.size() - 1)]
		var tangent := (next - prev) * 0.22
		curve.add_point(pts[i], -tangent, tangent)
	_path_points_cache = curve.get_baked_points()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 1258
	_place_braziers(rng)


func _build_scene() -> void:
	background = Background.new()
	background.z_index = -20
	add_child(background)

	var atmos := Atmosphere.new()
	add_child(atmos)

	_build_road()

	path = Path2D.new()
	path.curve = curve
	add_child(path)
	enemies = path  # enemies are PathFollow2D children of the Path2D

	gate = Gate.new()
	gate.position = GATE_POS
	gate.z_index = 5
	add_child(gate)

	projectiles = Node2D.new()
	projectiles.z_index = 8
	add_child(projectiles)

	fx_layer = Node2D.new()
	fx_layer.z_index = 20
	add_child(fx_layer)

	# The player's own gun, on the gatehouse roof.
	commander = Commander.new()
	commander.level = self
	commander.position = GATE_POS + Vector2(0, -214)
	add_child(commander)

	post = PostFx.new()
	add_child(post)


## The road itself plus its braziers. Rebuilt whenever the seed changes.
func _build_road() -> void:
	# Path ribbon: a dark trench, the worn track, then scattered stones.
	var trench := Line2D.new()
	trench.points = _path_points_cache
	trench.width = 86.0
	trench.default_color = Color(0.05, 0.04, 0.03, 0.45)
	trench.joint_mode = Line2D.LINE_JOINT_ROUND
	trench.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trench.end_cap_mode = Line2D.LINE_CAP_ROUND
	trench.z_index = -13
	add_child(trench)
	var edge := Line2D.new()
	edge.points = _path_points_cache
	edge.width = 74.0
	edge.default_color = Config.C_PATH_EDGE
	edge.joint_mode = Line2D.LINE_JOINT_ROUND
	edge.begin_cap_mode = Line2D.LINE_CAP_ROUND
	edge.end_cap_mode = Line2D.LINE_CAP_ROUND
	edge.z_index = -12
	add_child(edge)
	var fill := Line2D.new()
	fill.points = _path_points_cache
	fill.width = 58.0
	fill.default_color = Config.C_PATH
	fill.joint_mode = Line2D.LINE_JOINT_ROUND
	fill.begin_cap_mode = Line2D.LINE_CAP_ROUND
	fill.end_cap_mode = Line2D.LINE_CAP_ROUND
	fill.z_index = -11
	add_child(fill)
	var track := Line2D.new()
	track.points = _path_points_cache
	track.width = 26.0
	track.default_color = Color(Config.C_SAND_DARK, 0.35)
	track.joint_mode = Line2D.LINE_JOINT_ROUND
	track.begin_cap_mode = Line2D.LINE_CAP_ROUND
	track.end_cap_mode = Line2D.LINE_CAP_ROUND
	track.z_index = -10
	add_child(track)
	var stones := PathStones.new()
	stones.points = _path_points_cache
	stones.z_index = -9
	add_child(stones)

	for b in braziers:
		var br := Brazier.new()
		br.position = b
		br.z_index = 3
		add_child(br)


## Slots are generated once from the path: alternating sides, spaced along the
## climb, kept off the path and inside the mound. Deterministic, so "fixed".
func _build_slots() -> void:
	var length := curve.get_baked_length()
	var candidates: Array[Vector2] = []
	var d := 220.0
	var side := 1.0
	var alt := true
	while d < length - 110.0:
		var t := curve.sample_baked_with_rotation(d)
		var tangent: Vector2 = t.x.normalized()  # basis x = path direction
		var normal := Vector2(-tangent.y, tangent.x)
		alt = not alt
		for s in [side, -side]:
			# Alternate a near ring hugging the road with one set further back,
			# so twenty emplacements fit without crowding the same line.
			var p: Vector2 = t.origin + normal * (112.0 if alt else 172.0) * s
			if _slot_ok(p, candidates):
				candidates.append(p)
				break
		side = -side
		d += 104.0
	# Trim to MAX_SLOTS, spreading evenly along the climb.
	while candidates.size() > MAX_SLOTS:
		var worst := 1
		var worst_gap := INF
		for i in range(1, candidates.size() - 1):
			var gap := candidates[i - 1].distance_to(candidates[i]) + candidates[i].distance_to(candidates[i + 1])
			if gap < worst_gap:
				worst_gap = gap
				worst = i
		candidates.remove_at(worst)
	for i in range(candidates.size()):
		var slot := Slot.new()
		slot.index = i
		slot.position = candidates[i]
		slot.z_index = 2
		add_child(slot)
		slots.append(slot)


func _slot_ok(p: Vector2, existing: Array[Vector2]) -> bool:
	if p.x < 75.0 or p.x > W - 75.0 or p.y < 545.0 or p.y > 1730.0:
		return false
	if p.distance_to(GATE_POS) < 190.0:
		return false
	if dist_to_path(p) < 82.0:
		return false
	for q in existing:
		if q.distance_to(p) < 116.0:
			return false
	for b in braziers:
		if b.distance_to(p) < 78.0:
			return false
	return true


func dist_to_path(p: Vector2) -> float:
	var best := INF
	for q in _path_points_cache:
		best = minf(best, q.distance_to(p))
	return best


# ------------------------------------------------------------------ run flow

## Wipe the field: towers, attackers, shots and effects.
func clear_field() -> void:
	for s in slots:
		if s.tower != null:
			s.tower.queue_free()
			s.tower = null
	for e in enemies.get_children():
		if e is Enemy:
			e.queue_free()
	for p in projectiles.get_children():
		p.queue_free()
	for f in fx_layer.get_children():
		f.queue_free()


## Leave a run without scoring it (quit to title from the pause menu).
func abandon() -> void:
	clear_field()
	gate.reset()
	post.set_danger(0.0)
	_spawn_list.clear()
	_set_phase("idle")


func start_run(mode: int = -1) -> void:
	clear_field()
	gate.reset()
	Game.new_run(mode)
	# A seeded mode gets its own mound; the campaign keeps the authored one.
	if Game.run_seed != _current_seed:
		_current_seed = Game.run_seed
		rebuild_for_seed(Game.run_seed)
	post.set_danger(0.0)
	next_wave = 1
	wave_size = 0
	_spawn_list.clear()
	prep_left = Config.PREP_TIME_FIRST
	_set_phase("prep")
	Sfx.music("menu")


func skip_prep() -> void:
	if phase == "prep":
		prep_left = 0.0


func _set_phase(p: String) -> void:
	phase = p
	if commander != null and p != "wave":
		commander.set_firing(false)
	# Prep is the only time building matters, so that is the only time the
	# empty plinths are allowed to draw attention to themselves.
	for s in slots:
		s.hint = p == "prep" and s.tower == null
	phase_changed.emit(p)


func _process(delta: float) -> void:
	_process_shake(delta)
	if not Game.running or phase == "idle" or phase == "done":
		return
	var dt := delta * Game.speed
	Game.tick(dt)
	match phase:
		"prep":
			prep_left -= dt
			if prep_left <= 0.0:
				_begin_wave()
		"wave":
			_process_spawning(dt)
			if _spawn_list.is_empty() and living_enemies().is_empty():
				_finish_wave()


func _begin_wave() -> void:
	Game.set_wave(next_wave)
	_spawn_list = Config.wave_spawn_list(next_wave, Game.mode)
	wave_size = _spawn_list.size()
	_wave_scale = Config.wave_scale(Game.mode, next_wave)
	var income := Boons.wave_income()
	if income > 0:
		Game.add_rock(income)
		Fx.float_text(fx_layer, Vector2(W * 0.5, 330.0), "QUARRY  +%d" % income, Config.C_ROCK, 40)
	_spawn_timer = 0.0
	_set_phase("wave")
	wave_started.emit(next_wave)
	Sfx.music("battle")
	var is_boss := _spawn_list.has(Config.EnemyType.BOSS)
	Sfx.play("boss" if is_boss else "wave_start")
	if is_boss:
		post.flash(Config.C_THREAT, 0.35)
		shake(14.0, 0.6)


func _process_spawning(dt: float) -> void:
	if _spawn_list.is_empty():
		return
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		var t: int = _spawn_list.pop_front()
		spawn_enemy(t)
		var heavy: bool = t == Config.EnemyType.BOSS or t == Config.EnemyType.CART
		var gap := Config.SPAWN_GAP * (1.6 if heavy else 1.0)
		# Endless keeps the pressure up: waves compress as they grow.
		if Game.is_endless():
			gap *= clampf(1.0 - Game.wave * 0.012, 0.55, 1.0)
		_spawn_timer = gap


func _finish_wave() -> void:
	var w := Game.wave
	wave_cleared.emit(w)
	Game.wave_cleared()
	if not Game.running:
		return
	Sfx.play("wave_clear")
	Sfx.music("menu")
	Fx.float_text(fx_layer, Vector2(W * 0.5, 780.0),
		"WAVE %d HELD   +%d" % [w, Config.wave_clear_bonus(w)], Config.C_ROCK, 62, "crit")
	if Game.is_endless():
		_endless_milestone(w)
	next_wave = w + 1
	if Config.drafts_on_wave(w, Game.mode):
		draft_requested.emit(w)
	prep_left = Config.PREP_TIME_ENDLESS if Game.is_endless() else Config.PREP_TIME
	_set_phase("prep")


## Endless rewards depth: a rock purse every 5 waves, a repaired life every 10.
func _endless_milestone(w: int) -> void:
	if w % 10 == 0 and Game.lives < Game.max_lives:
		Game.lives += 1
		Game.lives_changed.emit(Game.lives, 1)
		gate.damage = maxi(0, gate.damage - 1)
		gate.queue_redraw()
		milestone.emit(w, "GATE REPAIRED")
		Fx.float_text(fx_layer, GATE_POS + Vector2(0, 120), "+1 LIFE", Config.C_GOOD, 54, "crit")
		Sfx.play("star")
	elif w % 5 == 0:
		var purse := 60 + w * 8
		Game.add_rock(purse)
		milestone.emit(w, "%s TIER" % Config.endless_tier(w + 1))
		Fx.coin(fx_layer, GATE_POS + Vector2(0, 140), 5)
		Sfx.play("coin", -2.0)


func _on_run_ended(result: Dictionary) -> void:
	_set_phase("done")
	Sfx.music("menu")
	post.set_danger(0.0)
	if result["won"]:
		Sfx.play("win")
		post.flash(Config.C_ROCK, 0.5)
	else:
		Sfx.play("lose")
		gate.breach()
		shake(30.0, 1.0)
		post.flash(Config.C_THREAT, 0.85)
		Fx.hit_stop(self, 0.18, 0.12)


func _on_lives_changed(value: int, _delta: int) -> void:
	post.set_danger(1.0 if value == 1 and Game.running else 0.0)


# ------------------------------------------------------------------ enemies

func spawn_enemy(type: int, at_progress: float = 0.0) -> Enemy:
	var e := Enemy.new()
	var is_elite := false
	if Game.is_endless() and type != Config.EnemyType.BOSS:
		is_elite = randf() < float(_wave_scale.get("elite_chance", 0.0))
	e.setup(type, self, _wave_scale, is_elite)
	e.progress = at_progress
	e.died.connect(_on_enemy_died)
	e.reached_gate.connect(_on_enemy_reached_gate)
	enemies.add_child(e)
	return e


func living_enemies() -> Array:
	var out: Array = []
	for c in enemies.get_children():
		if c is Enemy and c.alive:
			out.append(c)
	return out


func enemies_in_range(from: Vector2, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for e in living_enemies():
		if e.global_position.distance_squared_to(from) <= r2:
			out.append(e)
	return out


## Fraction of this wave still to come, for the HUD progress bar.
func wave_progress() -> float:
	if wave_size <= 0:
		return 0.0
	var left := _spawn_list.size() + living_enemies().size()
	return clampf(1.0 - float(left) / float(wave_size), 0.0, 1.0)


## Every emplacement still standing.
func towers() -> Array:
	var out: Array = []
	for s in slots:
		if s.tower != null and is_instance_valid(s.tower) and not s.tower.wrecked:
			out.append(s.tower)
	return out


## What an attacking siege crew shoots at: nearest emplacement inside its reach.
func nearest_tower(from: Vector2, radius: float) -> Tower:
	var best: Tower = null
	var best_d := radius
	for t in towers():
		var d: float = t.global_position.distance_to(from)
		if d < best_d:
			best_d = d
			best = t
	return best


## A sapper going up takes the line with it.
func damage_towers_in_range(from: Vector2, radius: float, amount: float) -> void:
	for t in towers():
		var d: float = t.global_position.distance_to(from)
		if d <= radius:
			# Full force at the centre, half at the rim.
			t.take_damage(amount * lerpf(1.0, 0.5, d / radius))


## A point on the road near `p`, shifted `offset` pixels along it. Guard posts
## put their men here so they stand in the way rather than beside it.
func path_point_near(p: Vector2, offset: float) -> Vector2:
	if _path_points_cache.is_empty():
		return p
	var best_i := 0
	var best_d := INF
	for i in range(_path_points_cache.size()):
		var d: float = _path_points_cache[i].distance_to(p)
		if d < best_d:
			best_d = d
			best_i = i
	# The curve is baked at a fixed interval, so an index step is a fixed length.
	var step := maxf(curve.bake_interval, 1.0)
	var idx := clampi(best_i + int(round(offset / step)), 0, _path_points_cache.size() - 1)
	return _path_points_cache[idx]


func _on_enemy_died(e: Enemy) -> void:
	var streak := Game.register_kill()
	var reward: int = Boons.kill_reward(int(e.stats["reward"]))
	Game.add_rock(reward)
	var bounty := Boons.streak_rock(streak)
	if bounty > 0:
		Game.add_rock(bounty)
	var col: Color = Config.C_ELITE if e.elite else Config.C_ROCK
	Fx.float_text(fx_layer, e.global_position + Vector2(0, -30), "+%d" % reward, col, 36 if not e.elite else 44,
		"crit" if e.elite else "plain")
	Fx.coin(fx_layer, e.global_position, 1 if reward < 40 else 3)
	var heavy: bool = e.type == Config.EnemyType.BOSS or e.type == Config.EnemyType.CART 		or e.type == Config.EnemyType.CATAPULT
	if heavy:
		Meta.track("kills_heavy")
	if e.burning():
		Meta.track("kills_fire")
	Fx.burst(fx_layer, e.global_position, Config.C_THREAT, 14 if not heavy else 50, 220.0)
	if e.elite:
		Fx.shockwave(fx_layer, e.global_position, 110.0, Config.C_ELITE, 0.4)
	if heavy:
		# Siege engines do not die quietly.
		var power: float = 1.6 if e.type == Config.EnemyType.BOSS else 1.1
		Fx.explosion(fx_layer, e.global_position, power, Config.C_FIRE)
		shake(16.0 * power, 0.45 + 0.2 * power)
		post.flash(Config.C_FIRE, 0.25 * power)
		Fx.hit_stop(self, 0.09 + 0.04 * power, 0.1)
	if streak >= 5 and streak % 5 == 0:
		Fx.float_text(fx_layer, e.global_position + Vector2(0, -100), "%d STREAK!" % streak, Config.C_FIRE_HOT, 52, "crit")
		Sfx.play_pitched("combo", minf(float(streak - 5) * 0.7, 14.0), -4.0)
	else:
		Sfx.play("coin", -8.0)


func _on_enemy_reached_gate(e: Enemy) -> void:
	var cost: int = e.stats["lives"]
	gate.hit()
	Sfx.play("gate_hit")
	shake(20.0 if cost == 1 else 34.0, 0.55, (GATE_POS - e.global_position).normalized())
	post.flash(Config.C_THREAT, 0.4 if cost == 1 else 0.7)
	Fx.hit_stop(self, 0.07, 0.12)
	Fx.float_text(fx_layer, GATE_POS + Vector2(0, 90), "BREACH" if cost >= 99 else "-%d" % cost, Config.C_THREAT, 58, "crit")
	Game.lose_lives(cost)


# ------------------------------------------------------------------ towers

func place_tower(slot: Slot, type: int) -> bool:
	if slot.tower != null:
		return false
	var cost := Boons.tower_cost(type, 1)
	if not Game.spend(cost):
		Sfx.play("deny")
		return false
	var t := Tower.new()
	t.setup(type, slot, self)
	slot.rubble = false
	t.position = slot.position
	t.z_index = 4
	add_child(t)
	slot.tower = t
	slot.hint = false
	var free_tiers := Boons.start_tier() - 1
	for i in range(free_tiers):
		if t.tier < Config.MAX_TIER:
			t.upgrade()
	Meta.track("builds")
	if type == Config.TowerType.MANGONEL:
		Meta.track("builds_mangonel")
	Sfx.play("build")
	Fx.burst(fx_layer, slot.position, Config.C_SAND_LIGHT, 16, 180.0)
	Fx.ring(fx_layer, slot.position, 90.0, Config.C_SAND_LIGHT)
	Fx.float_text(fx_layer, slot.position + Vector2(0, -70), "-%d" % cost, Config.C_TEXT_DIM, 30)
	return true


func upgrade_tower(t: Tower) -> bool:
	if t.tier >= Config.MAX_TIER:
		return false
	var cost := Boons.tower_cost(t.type, t.tier + 1)
	if not Game.spend(cost):
		Sfx.play("deny")
		return false
	t.upgrade()
	Sfx.play("upgrade")
	Fx.burst(fx_layer, t.position, Config.C_ROCK, 22, 220.0, 320.0)
	Fx.shockwave(fx_layer, t.position, 120.0, Config.C_ROCK, 0.4)
	Fx.float_text(fx_layer, t.position + Vector2(0, -90), "TIER %d" % t.tier, Config.C_ROCK, 42, "crit")
	return true


## Paying to put a battered emplacement back to full.
func repair_tower(t: Tower) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var cost := t.repair_cost()
	if cost <= 0:
		return false
	if not Game.spend(cost):
		Sfx.play("deny")
		return false
	t.repair()
	Sfx.play("build")
	Fx.burst(fx_layer, t.position, Config.C_GOOD, 14, 170.0)
	Fx.float_text(fx_layer, t.position + Vector2(0, -80), "REPAIRED", Config.C_GOOD, 34)
	return true


func sell_tower(t: Tower) -> void:
	var refund := int(round(t.total_invested() * Config.SELL_REFUND))
	Game.add_rock(refund, false)
	t.slot.tower = null
	Fx.float_text(fx_layer, t.position + Vector2(0, -60), "+%d" % refund, Config.C_TEXT_DIM, 32)
	Fx.burst(fx_layer, t.position, Config.C_WOOD, 14, 160.0)
	Fx.smoke(fx_layer, t.position, 5, 0.6)
	Sfx.play("sell")
	t.queue_free()


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if phase == "idle" or phase == "done":
		return
	# Touch arrives as emulated mouse events (project setting), so one handler
	# covers both. A press near a plinth is a build tap; anywhere else it takes
	# hold of the commander and starts shooting.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			if commander != null:
				commander.set_firing(false)
			return
		var world := _to_world(mb.position)
		var best := _slot_at(world)
		if best != null:
			get_viewport().set_input_as_handled()
			if commander != null:
				commander.set_firing(false)
			if best.tower != null:
				tower_tapped.emit(best.tower)
			else:
				slot_tapped.emit(best)
			return
		empty_tapped.emit()
		if commander != null and phase == "wave":
			commander.aim_at(world)
			commander.set_firing(true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and commander != null and commander.firing:
		commander.aim_at(_to_world((event as InputEventMouseMotion).position))


func _to_world(screen: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen


func _slot_at(world: Vector2) -> Slot:
	var best: Slot = null
	var best_d := TAP_RADIUS
	for s in slots:
		var d := s.position.distance_to(world)
		if d < best_d:
			best_d = d
			best = s
	return best


# ------------------------------------------------------------------ camera shake

## `dir`, when given, is the direction the force came from: the screen kicks
## along it and rings out, instead of jittering at random. A random shake reads
## as noise; a directed one reads as a blow landing somewhere.
func shake(strength: float, duration: float = 0.35, dir: Vector2 = Vector2.ZERO) -> void:
	if Game.sim_mode:
		return
	if strength >= _shake_strength:
		_shake_dir = dir.normalized() if dir.length_squared() > 0.001 else Vector2.ZERO
		_shake_phase = 0.0
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, duration)


func _process_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		if position != Vector2.ZERO:
			position = Vector2.ZERO
		return
	_shake_time -= delta
	_shake_phase += delta
	# Exponential decay rather than linear: the first frame carries the punch
	# and it settles fast, which is what stops a shake feeling like a wobble.
	var k := clampf(_shake_time / 0.35, 0.0, 1.0)
	k = k * k
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1))
	if _shake_dir == Vector2.ZERO:
		position = jitter * _shake_strength * k
	else:
		var ring := sin(_shake_phase * 46.0)
		position = (_shake_dir * ring * 1.15 + jitter * 0.35) * _shake_strength * k
	if _shake_time <= 0.0:
		_shake_strength = 0.0
		_shake_dir = Vector2.ZERO
		position = Vector2.ZERO


## Small decorative stones and old cart ruts along the path edges.
class PathStones extends Node2D:
	var points: PackedVector2Array

	func _draw() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 42
		var i := 0
		while i < points.size() - 1:
			var p := points[i]
			var q := points[mini(i + 1, points.size() - 1)]
			var tangent := (q - p).normalized()
			var normal := Vector2(-tangent.y, tangent.x)
			for s in [-1.0, 1.0]:
				if rng.randf() < 0.55:
					var c: Vector2 = p + normal * s * rng.randf_range(30.0, 40.0)
					var r := rng.randf_range(3.0, 6.5)
					draw_circle(c + Vector2(1.5, 1.5), r, Color(0, 0, 0, 0.28))
					draw_circle(c, r, Config.C_SAND_LIGHT if rng.randf() < 0.5 else Config.C_SAND_DARK)
			# Occasional boot print scuff in the middle of the track
			if rng.randf() < 0.35:
				var c2: Vector2 = p + normal * rng.randf_range(-12.0, 12.0)
				draw_set_transform(c2, tangent.angle(), Vector2.ONE)
				draw_circle(Vector2.ZERO, rng.randf_range(3.0, 5.0), Color(Config.C_PATH_EDGE, 0.5))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			i += rng.randi_range(3, 7)


## A stone brazier beside the path: light, flame, and a marker for the climb.
class Brazier extends Node2D:
	var _t := 0.0
	var _light: PointLight2D

	func _ready() -> void:
		_t = randf() * 8.0
		_light = Gfx.make_light(Config.C_TORCH, 0.95, 300.0)
		_light.position = Vector2(0, -34)
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		var f := 0.8 + 0.2 * sin(_t * 8.5) + 0.07 * sin(_t * 19.0 + 1.1)
		_light.energy = 0.8 * f
		queue_redraw()

	func _draw() -> void:
		Gfx.draw_shadow(self, Vector2(-4, 10), 22.0, 0.35, 0.35)
		# Stone column
		draw_colored_polygon(PackedVector2Array([
			Vector2(-13, 8), Vector2(13, 8), Vector2(9, -26), Vector2(-9, -26),
		]), Config.C_SAND_DARK)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-13, 8), Vector2(-3, 8), Vector2(-2, -26), Vector2(-9, -26),
		]), Config.C_SAND_LIGHT.darkened(0.25))
		# Iron bowl
		draw_rect(Rect2(-17, -34, 34, 9), Config.C_IRON_DARK)
		draw_rect(Rect2(-17, -34, 34, 3), Config.C_IRON)
		# Flame
		var f := 1.0 + 0.2 * sin(_t * 9.0) + 0.09 * sin(_t * 21.0)
		draw_circle(Vector2(0, -40), 26 * f, Color(Config.C_FIRE, 0.14))
		draw_circle(Vector2(0, -40), 12 * f, Config.C_FIRE)
		draw_circle(Vector2(0, -46), 6.5 * f, Config.C_FIRE_HOT)
