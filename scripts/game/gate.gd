class_name Gate
extends Node2D
## The Citadel main gate: two flanking towers and an arched door. Shows damage
## as lives are lost: cracks, then smoke and a broken door, then fire and breach.
## Two braziers light it, and they gutter as the gate takes hits.

var damage: int = 0           # 0..3
var _smoke: CPUParticles2D
var _fire: CPUParticles2D
var _dust: CPUParticles2D
var _flash: float = 0.0
var _shudder: float = 0.0
var _t: float = 0.0
var _lights: Array[PointLight2D] = []


func _ready() -> void:
	_smoke = CPUParticles2D.new()
	_smoke.position = Vector2(0, -60)
	_smoke.amount = 26
	_smoke.lifetime = 2.2
	_smoke.emitting = false
	_smoke.direction = Vector2(0, -1)
	_smoke.spread = 22.0
	_smoke.gravity = Vector2(6, -40)
	_smoke.initial_velocity_min = 40.0
	_smoke.initial_velocity_max = 90.0
	_smoke.scale_amount_min = 6.0
	_smoke.scale_amount_max = 14.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(0.35, 0.33, 0.34, 0.0), Color(0.3, 0.28, 0.3, 0.6), Color(0.2, 0.2, 0.22, 0.0)])
	_smoke.color_ramp = g
	add_child(_smoke)

	_fire = CPUParticles2D.new()
	_fire.position = Vector2(0, -20)
	_fire.amount = 34
	_fire.lifetime = 0.9
	_fire.emitting = false
	_fire.direction = Vector2(0, -1)
	_fire.spread = 30.0
	_fire.gravity = Vector2(0, -160)
	_fire.initial_velocity_min = 60.0
	_fire.initial_velocity_max = 140.0
	_fire.scale_amount_min = 4.0
	_fire.scale_amount_max = 9.0
	_fire.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_fire.emission_rect_extents = Vector2(40, 8)
	var fg := Gradient.new()
	fg.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	fg.colors = PackedColorArray([Config.C_FIRE_HOT, Config.C_FIRE, Color(Config.C_THREAT, 0.0)])
	_fire.color_ramp = fg
	add_child(_fire)

	# Mortar dust knocked loose on every impact.
	_dust = CPUParticles2D.new()
	_dust.position = Vector2(0, -10)
	_dust.amount = 22
	_dust.lifetime = 1.1
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.emitting = false
	_dust.direction = Vector2(0, -1)
	_dust.spread = 70.0
	_dust.gravity = Vector2(0, 220)
	_dust.initial_velocity_min = 60.0
	_dust.initial_velocity_max = 210.0
	_dust.scale_amount_min = 3.0
	_dust.scale_amount_max = 8.0
	var dg := Gradient.new()
	dg.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	dg.colors = PackedColorArray([Config.C_SAND_LIGHT, Config.C_SAND_DARK, Color(Config.C_SAND_DARK, 0.0)])
	_dust.color_ramp = dg
	add_child(_dust)

	for sx in [-1.0, 1.0]:
		var l := Gfx.make_light(Config.C_TORCH, 0.75, 280.0)
		l.position = Vector2(sx * 92.0, -196.0)
		add_child(l)
		_lights.append(l)
	var glow := Gfx.make_light(Config.C_FIRE, 0.34, 320.0, true)
	glow.position = Vector2(0, -70)
	add_child(glow)
	_lights.append(glow)


func reset() -> void:
	damage = 0
	_smoke.emitting = false
	_fire.emitting = false
	_shudder = 0.0
	queue_redraw()


func hit() -> void:
	damage = mini(damage + 1, 3)
	_flash = 1.0
	_shudder = 1.0
	_smoke.emitting = damage >= 2
	_fire.emitting = damage >= 3
	_dust.restart()
	_dust.emitting = true
	queue_redraw()


func breach() -> void:
	damage = 3
	_smoke.emitting = true
	_fire.emitting = true
	_flash = 1.0
	_shudder = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		queue_redraw()
	if _shudder > 0.0:
		_shudder = maxf(0.0, _shudder - delta * 2.2)
		position.x = sin(_t * 60.0) * 5.0 * _shudder
		position.y = sin(_t * 71.0) * 3.0 * _shudder
		if _shudder <= 0.0:
			position = Vector2.ZERO
	# Braziers gutter and go redder as the gate is battered.
	var f := 0.82 + 0.18 * sin(_t * 9.5) + 0.07 * sin(_t * 23.0)
	var health := 1.0 - float(damage) / 3.0
	for i in range(_lights.size()):
		_lights[i].energy = (0.42 + 0.3 * health) * f
		_lights[i].color = Config.C_TORCH.lerp(Config.C_THREAT, float(damage) / 4.0)
	if damage > 0 or _flash > 0.0:
		queue_redraw()


func _draw() -> void:
	var stone := Config.C_WALL.lightened(0.05)
	var shadow := Config.C_WALL_SHADOW
	# Ground shadow under the whole gatehouse.
	Gfx.draw_shadow(self, Vector2(0, 22), 160.0, 0.22, 0.4)
	# Flanking towers
	for sx in [-1.0, 1.0]:
		var x: float = sx * 92.0
		draw_rect(Rect2(x - 46, -180, 92, 200), stone)
		draw_rect(Rect2(x - 46, -180, 14, 200), Color(Config.C_SAND_LIGHT, 0.12))
		draw_rect(Rect2(x - 46 + (0 if sx < 0 else 66), -180, 26, 200), Color(shadow, 0.45))
		for row in range(10):
			draw_line(Vector2(x - 46, -176 + row * 20), Vector2(x + 46, -176 + row * 20), Color(shadow, 0.16), 1.0)
		for i in range(3):
			draw_rect(Rect2(x - 44 + i * 32, -200, 20, 22), stone)
			draw_rect(Rect2(x - 44 + i * 32, -200, 20, 4), stone.lightened(0.16))
		draw_rect(Rect2(x - 5, -140, 10, 34), Config.C_WINDOW)
		draw_rect(Rect2(x - 5, -80, 10, 34), Config.C_WINDOW)
		# Brazier on the tower top
		var f := 1.0 + sin(_t * 10.0 + sx) * 0.2
		draw_rect(Rect2(x - 12, -202, 24, 8), Config.C_IRON_DARK)
		draw_circle(Vector2(x, -206), 18 * f, Color(Config.C_FIRE, 0.2))
		draw_circle(Vector2(x, -206), 9 * f, Config.C_FIRE)
		draw_circle(Vector2(x, -211), 5 * f, Config.C_FIRE_HOT)
	# Arch between the towers
	draw_rect(Rect2(-46, -120, 92, 140), stone)
	draw_circle(Vector2(0, -120), 46, stone)
	draw_rect(Rect2(-46, -120, 92, 8), Color(shadow, 0.4))
	# Voussoir stones around the arch
	for i in range(9):
		var a := PI + float(i) / 8.0 * PI
		var p := Vector2(0, -120) + Vector2(cos(a), sin(a)) * 41.0
		draw_circle(p, 6.0, Color(shadow, 0.35))
	# Door opening
	draw_circle(Vector2(0, -95), 34, Config.C_WINDOW)
	draw_rect(Rect2(-34, -95, 68, 115), Config.C_WINDOW)
	# Wooden door planks (missing when damaged)
	for i in range(4):
		if damage >= 2 and (i == 1 or (damage >= 3 and i == 2)):
			continue
		var px := -32 + i * 17
		draw_rect(Rect2(px, -92, 15, 110), Config.C_WOOD_DARK if damage < 3 else Config.C_WOOD_DARK.darkened(0.4))
		draw_rect(Rect2(px, -92, 15, 110), Color(Config.C_WOOD, 0.35))
		draw_rect(Rect2(px, -92, 3, 110), Color(Config.C_SAND_LIGHT, 0.08))
	draw_rect(Rect2(-32, -50, 66, 6), Config.C_IRON_DARK)
	draw_rect(Rect2(-32, -10, 66, 6), Config.C_IRON_DARK)
	for bx in [-24.0, 24.0]:
		draw_circle(Vector2(bx, -47), 4.0, Config.C_IRON)
		draw_circle(Vector2(bx, -7), 4.0, Config.C_IRON)
	# Cracks
	if damage >= 1:
		var cr := Color(Config.C_WINDOW, 0.9)
		draw_polyline(PackedVector2Array([Vector2(-120, -170), Vector2(-108, -140), Vector2(-118, -110), Vector2(-100, -70)]), cr, 3.0)
		draw_polyline(PackedVector2Array([Vector2(70, -30), Vector2(84, -60), Vector2(76, -95)]), cr, 3.0)
	if damage >= 2:
		var cr2 := Color(Config.C_WINDOW, 0.9)
		draw_polyline(PackedVector2Array([Vector2(120, -175), Vector2(104, -150), Vector2(118, -120), Vector2(96, -84), Vector2(110, -40)]), cr2, 3.5)
		draw_polyline(PackedVector2Array([Vector2(-60, -120), Vector2(-40, -140), Vector2(-52, -160)]), cr2, 3.0)
		for i in range(6):
			draw_circle(Vector2(-70 + i * 26, 22 + (i % 2) * 6), 7, shadow)
	if damage >= 3:
		draw_rect(Rect2(-138, -200, 22, 24), Config.C_PLAIN)
		draw_rect(Rect2(116, -200, 22, 24), Config.C_PLAIN)
		draw_circle(Vector2(0, -60), 60, Color(0.1, 0.08, 0.06, 0.45))
		# Embers glowing in the wreck
		for i in range(5):
			var ex := -40.0 + i * 20.0
			var g := 0.4 + 0.6 * absf(sin(_t * 3.0 + i))
			draw_circle(Vector2(ex, 10), 5.0, Color(Config.C_FIRE, 0.5 * g))
	# Impact flash
	if _flash > 0.0:
		draw_rect(Rect2(-150, -215, 300, 245), Color(Config.C_THREAT, 0.45 * _flash))
		Gfx.draw_glow(self, Vector2(0, -90), 150.0 * _flash, Config.C_THREAT, _flash, 4)
