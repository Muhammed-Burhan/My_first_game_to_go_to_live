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
	# An empty plinth is furniture. It is cut from the mound it stands on, one
	# step lighter and no more, so twenty of them do not out-shout the column
	# climbing past. It only lifts while the build sheet is offering it.
	var lift: float = 1.0 if tower != null else (0.62 if hint else 0.0)
	var deep: Color = Config.C_GROUND_LOW.lerp(Config.C_SAND_DEEP, lift)
	var mid: Color = Config.C_PLINTH.lerp(Config.C_SAND_DARK, lift)
	var top: Color = Config.C_PLINTH_TOP.lerp(Config.C_SAND_LIGHT, lift)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.62))
	draw_circle(Vector2(0, 10), 42, Color(0.02, 0.02, 0.05, 0.45))
	draw_circle(Vector2.ZERO, 40, deep)
	draw_circle(Vector2(0, -6), 40, mid)
	draw_circle(Vector2(0, -8), 32, top)
	draw_circle(Vector2(-8, -12), 20, top.lightened(0.05))
	# Mortar joints on the top face
	for i in range(3):
		var a := float(i) / 3.0 * TAU + 0.3
		draw_line(Vector2(0, -8), Vector2(0, -8) + Vector2(cos(a), sin(a)) * 32.0, Color(deep, 0.45), 1.8)
	draw_arc(Vector2(0, -8), 32, 0, TAU, 36, Color(deep, 0.7), 2.0)
	# Chisel speckle on the cut face, keyed to the slot so it never shimmers.
	# Deliberately sparse: at 58 specks a plinth, twenty of these were 1,324
	# draw calls a frame — 45% of everything left after the background bake —
	# for texture that is invisible at this size. Measured with --hide=slots.
	Gfx.draw_grain(self, Rect2(-28, -28, 56, 40), 7, Color(deep, 0.4), 400 + index, 1.2, 2.6)
	Gfx.draw_grain(self, Rect2(-28, -28, 56, 40), 4, Color(top.lightened(0.25), 0.2), 600 + index, 1.0, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tower == null and rubble:
		_draw_rubble()
	elif tower == null:
		# The plus is an affordance, not decoration: barely there until the
		# build sheet is open, then gold.
		var c: Color = Color(Config.C_ROCK, 0.85) if hint else Color(top.lightened(0.18), 0.5)
		draw_line(Vector2(-11, -5), Vector2(11, -5), c, 4.0)
		draw_line(Vector2(0, -16), Vector2(0, 6), c, 4.0)
	if hint and tower == null:
		_draw_hint()


## Twelve of these are on screen at once during prep, so it is one slow ring
## and a wash. The expanding pulse each plinth used to fire made the whole
## mound strobe.
func _draw_hint() -> void:
	var a := 0.26 + 0.20 * sin(_t * 2.6)
	draw_arc(Vector2(0, -6), 44, 0, TAU, 40, Color(Config.C_ROCK, a), 3.0)
	draw_circle(Vector2(0, -6), 26, Color(Config.C_ROCK, 0.07 + 0.04 * sin(_t * 2.6)))


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
