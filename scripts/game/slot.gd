class_name Slot
extends Node2D
## A fixed build position on the mound: a stone plinth. Holds at most one tower.
## When `hint` is on it pulses a ring so first-timers know where to tap.

var index: int = 0
var tower: Tower = null
## Set when an emplacement here was wrecked; cleared by rebuilding.
var rubble: bool = false
var hint: bool = false:
	set(v):
		hint = v
		set_process(v)
		queue_redraw()
var _t: float = 0.0


func _ready() -> void:
	_t = randf() * TAU
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	# An empty plinth is scenery, not a button: it stays dark so the emplacements
	# and the attackers own the contrast. It only lifts when it is being offered.
	var lift: float = 1.0 if tower != null else (0.55 if hint else 0.28)
	var deep := Config.C_SAND_DEEP.darkened(0.35 * (1.0 - lift))
	var mid := Config.C_SAND_DARK.darkened(0.4 * (1.0 - lift))
	var top := Config.C_SAND_LIGHT.darkened(0.08 + 0.4 * (1.0 - lift))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.62))
	draw_circle(Vector2(0, 10), 42, Color(0.02, 0.02, 0.05, 0.38))
	draw_circle(Vector2.ZERO, 40, deep)
	draw_circle(Vector2(0, -6), 40, mid)
	draw_circle(Vector2(0, -8), 32, top)
	draw_circle(Vector2(-8, -12), 20, top.lightened(0.06))
	# Mortar joints on the top face
	for i in range(6):
		var a := float(i) / 6.0 * TAU + 0.3
		draw_line(Vector2(0, -8), Vector2(0, -8) + Vector2(cos(a), sin(a)) * 32.0, Color(Config.C_SAND_DEEP, 0.4), 1.6)
	draw_arc(Vector2(0, -8), 32, 0, TAU, 36, Color(Config.C_SAND_DEEP, 0.6), 2.0)
	# Chisel speckle on the cut face, keyed to the slot so it never shimmers.
	Gfx.draw_grain(self, Rect2(-30, -30, 60, 44), 44, Color(Config.C_SAND_DEEP, 0.3), 400 + index, 0.8, 2.0)
	Gfx.draw_grain(self, Rect2(-30, -30, 60, 44), 22, Color(Config.C_SAND_LIGHT, 0.22), 600 + index, 0.8, 1.6)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Re-light the plinth when something is standing on it.
	if tower == null and rubble:
		_draw_rubble()
	elif tower == null:
		var c := Config.C_SAND_DEEP
		draw_line(Vector2(-11, -5), Vector2(11, -5), c, 4.0)
		draw_line(Vector2(0, -16), Vector2(0, 6), c, 4.0)
	if hint and tower == null:
		_draw_hint()


func _draw_hint() -> void:
	var pulse := fmod(_t * 0.75, 1.0)
	# An expanding ring that fades, plus a steady breathing ring.
	var r := lerpf(30.0, 72.0, pulse)
	draw_arc(Vector2(0, -4), r, 0, TAU, 44, Color(Config.C_ROCK, 0.55 * (1.0 - pulse)), 5.0 * (1.0 - pulse) + 1.0)
	var a := 0.35 + 0.35 * sin(_t * 4.0)
	draw_arc(Vector2(0, -4), 48 + 4 * sin(_t * 4.0), 0, TAU, 40, Color(Config.C_ROCK, a), 4.0)
	draw_circle(Vector2(0, -6), 26, Color(Config.C_ROCK, 0.10 + 0.05 * sin(_t * 4.0)))


## What is left after a manjaniq stone or a sapper finds the emplacement.
func _draw_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + index
	for i in range(7):
		var p := Vector2(rng.randf_range(-26, 26), rng.randf_range(-14, 8))
		var r := rng.randf_range(4.0, 10.0)
		draw_circle(p + Vector2(2, 2), r, Color(0, 0, 0, 0.3))
		draw_colored_polygon(PackedVector2Array([
			p + Vector2(-r, r * 0.5), p + Vector2(-r * 0.4, -r),
			p + Vector2(r * 0.7, -r * 0.6), p + Vector2(r, r * 0.4),
		]), Config.C_SAND_DARK.darkened(rng.randf_range(0.0, 0.25)))
	# Charred timber
	draw_line(Vector2(-18, 2), Vector2(12, -8), Color("2a2018"), 5.0)
	draw_line(Vector2(-6, -10), Vector2(20, 4), Color("2a2018"), 4.0)
