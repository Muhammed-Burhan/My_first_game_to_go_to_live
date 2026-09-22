class_name Background
extends Node2D
## Painted backdrop: layered night sky, the Zagros ridgelines, the moon, the
## plain with the Mongol camp, the Citadel mound in terraces, and the continuous
## house-facade wall of the Erbil Citadel along the top.
##
## The static paint is drawn once. Stars twinkle, windows breathe, and torches
## are real 2D lights so the whole scene sits in a warm pool at the top and a
## cold one at the bottom.

const W := 1080.0
const H := 1920.0
const CX := 540.0
const HORIZON := 560.0

# Terraces: [y_bottom, y_top, half_width_bottom, half_width_top]
const TERRACES := [
	[1720.0, 1430.0, 600.0, 560.0],
	[1430.0, 1140.0, 560.0, 515.0],
	[1140.0, 860.0, 515.0, 470.0],
	[860.0, 600.0, 470.0, 430.0],
	[600.0, 490.0, 430.0, 410.0],
]

## Torch positions along the citadel wall.
const WALL_TORCHES := [260.0, 420.0, 660.0, 820.0]
const CAMP_FIRES := [Vector2(200, 1830), Vector2(920, 1810), Vector2(330, 1790)]
## Clear of the HUD bar, which covers the top 172px.
const MOON_POS := Vector2(852, 246)


func _ready() -> void:
	# One night grade for the whole battlefield canvas; the UI layer is separate.
	var tint := CanvasModulate.new()
	tint.color = Config.NIGHT_TINT
	add_child(tint)

	var stars := Stars.new()
	stars.z_index = -1
	add_child(stars)

	for x in WALL_TORCHES:
		var flame := Flicker.new()
		flame.position = Vector2(x, 318.0)
		flame.radius = 200.0
		flame.core = 7.0
		add_child(flame)
	for f in CAMP_FIRES:
		var fire := Flicker.new()
		fire.position = f
		fire.radius = 260.0
		fire.core = 11.0
		fire.rate = 8.0
		add_child(fire)
	# Cool fill from the moon so the right shoulder of the mound is not flat black.
	var moonlight := Gfx.make_light(Color(0.55, 0.66, 1.0), 0.55, 900.0, true)
	moonlight.position = MOON_POS
	add_child(moonlight)


func _draw() -> void:
	_draw_sky()
	_draw_mountains()
	_draw_moon()
	_draw_plain()
	_draw_camp()
	_draw_mound()
	_draw_citadel()


# ------------------------------------------------------------------ sky

func _draw_sky() -> void:
	# Three-stop vertical gradient, painted as two quads.
	var top := PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, 330), Vector2(0, 330)])
	draw_polygon(top, PackedColorArray([Config.C_SKY_TOP, Config.C_SKY_TOP, Config.C_SKY_MID, Config.C_SKY_MID]))
	var bot := PackedVector2Array([Vector2(0, 330), Vector2(W, 330), Vector2(W, HORIZON + 90), Vector2(0, HORIZON + 90)])
	draw_polygon(bot, PackedColorArray([Config.C_SKY_MID, Config.C_SKY_MID, Config.C_SKY_BOTTOM, Config.C_SKY_BOTTOM]))
	# Milky band across the upper sky.
	for i in range(7):
		var y := 90.0 + i * 16.0
		var a := 0.025 - absf(i - 3) * 0.006
		draw_colored_polygon(
			PackedVector2Array([Vector2(0, y - 40), Vector2(W, y + 120), Vector2(W, y + 160), Vector2(0, y)]),
			Color(Config.C_SKY_HAZE, maxf(a, 0.004)))
	# Warm haze sitting on the horizon behind the citadel.
	for i in range(8):
		var k := float(i) / 8.0
		draw_circle(Vector2(CX, HORIZON - 40), 300 + i * 85, Color(Config.C_SAND_LIGHT, 0.045 * (1.0 - k)))


func _draw_mountains() -> void:
	_ridge(300.0, 470.0, 0.0041, 8.0, Config.C_MOUNTAIN_FAR, 0.85)
	_ridge(372.0, 520.0, 0.0067, 5.0, Config.C_MOUNTAIN_NEAR, 1.0)


## A deterministic ridgeline between y_peak and y_base.
func _ridge(y_peak: float, y_base: float, freq: float, octaves: int, col: Color, alpha: float) -> void:
	var pts := PackedVector2Array()
	var steps := 90
	for i in range(steps + 1):
		var x := -20.0 + (W + 40.0) * float(i) / steps
		var h := 0.0
		var amp := 1.0
		var f := freq
		for o in range(octaves):
			h += sin(x * f + float(o) * 2.399) * amp
			amp *= 0.55
			f *= 1.9
		h = h * 0.5 + 0.5
		pts.append(Vector2(x, lerpf(y_base, y_peak, clampf(h, 0.0, 1.0))))
	var poly := pts.duplicate()
	poly.append(Vector2(W + 20, y_base + 60))
	poly.append(Vector2(-20, y_base + 60))
	draw_colored_polygon(poly, Color(col, alpha))
	# Moonlit rim on the right-facing slopes.
	for i in range(pts.size() - 1):
		if pts[i + 1].y < pts[i].y:
			draw_line(pts[i], pts[i + 1], Color(Config.C_SKY_HAZE, 0.30 * alpha), 2.0)


func _draw_moon() -> void:
	var c := MOON_POS
	for i in range(7):
		draw_circle(c, 64 + i * 30, Color(Config.C_MOON, 0.055 - i * 0.007))
	draw_circle(c, 58, Config.C_MOON)
	draw_circle(c + Vector2(3, 3), 58, Color(Config.C_MOON.darkened(0.06), 0.5))
	draw_circle(c + Vector2(-18, -12), 11, Color(Config.C_MOON).darkened(0.13))
	draw_circle(c + Vector2(16, 14), 8, Color(Config.C_MOON).darkened(0.11))
	draw_circle(c + Vector2(8, -26), 5, Color(Config.C_MOON).darkened(0.1))
	draw_circle(c + Vector2(-8, 22), 4, Color(Config.C_MOON).darkened(0.09))


# ------------------------------------------------------------------ ground

func _draw_plain() -> void:
	draw_rect(Rect2(0, HORIZON, W, H - HORIZON), Config.C_PLAIN)
	var band := PackedVector2Array([Vector2(0, HORIZON), Vector2(W, HORIZON), Vector2(W, HORIZON + 80), Vector2(0, HORIZON + 80)])
	draw_polygon(band, PackedColorArray([Config.C_PLAIN_LIGHT, Config.C_PLAIN_LIGHT, Config.C_PLAIN, Config.C_PLAIN]))
	# Far tents of the besieging army on the horizon plain.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(18):
		var x := rng.randf_range(20, W - 20)
		var y := rng.randf_range(HORIZON + 15, HORIZON + 60)
		var s := rng.randf_range(6, 11)
		draw_colored_polygon(PackedVector2Array([Vector2(x - s, y), Vector2(x + s, y), Vector2(x, y - s * 1.3)]), Color("1c1a12"))
		if rng.randf() < 0.5:
			draw_circle(Vector2(x + s * 1.4, y - 2), 2.5, Config.C_FIRE)
	Gfx.draw_grain(self, Rect2(0, HORIZON, W, H - HORIZON), 420,
		Color(Config.C_PLAIN_LIGHT, 0.18), 3131, 1.0, 3.0)
	# Cold ground fog band right on the horizon line.
	draw_rect(Rect2(0, HORIZON - 6, W, 20), Color(Config.C_SKY_HAZE, 0.10))


func _draw_camp() -> void:
	var tents := [
		[120.0, 1860.0, 62.0], [270.0, 1900.0, 48.0], [860.0, 1850.0, 66.0], [990.0, 1895.0, 46.0],
		[60.0, 1760.0, 40.0], [1010.0, 1770.0, 42.0], [380.0, 1905.0, 34.0], [720.0, 1910.0, 36.0],
	]
	for t in tents:
		var x: float = t[0]
		var y: float = t[1]
		var s: float = t[2]
		Gfx.draw_shadow(self, Vector2(x, y + 4), s * 1.1, 0.24, 0.35)
		draw_colored_polygon(PackedVector2Array([Vector2(x - s, y), Vector2(x + s, y), Vector2(x, y - s * 1.25)]), Color("221a12"))
		# Lit side facing the nearest fire.
		draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + s, y), Vector2(x, y - s * 1.25)]), Color("2e2317"))
		draw_colored_polygon(PackedVector2Array([Vector2(x - s * 0.18, y), Vector2(x + s * 0.18, y), Vector2(x, y - s * 0.55)]), Color("120d08"))
		draw_line(Vector2(x, y - s * 1.25), Vector2(x, y - s * 1.7), Config.C_WOOD_DARK, 3.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x, y - s * 1.7), Vector2(x + s * 0.45, y - s * 1.55), Vector2(x, y - s * 1.4)]), Config.C_THREAT)
	for f in CAMP_FIRES:
		draw_circle(f + Vector2(0, 6), 34, Color(0.02, 0.02, 0.04, 0.3))
		for i in range(4):
			draw_circle(f, 30 - i * 7, Color(Config.C_FIRE, 0.08 + i * 0.05))
		draw_circle(f, 7, Config.C_FIRE_HOT)
		draw_circle(f + Vector2(-3, 1), 4.5, Config.C_FIRE)
		# Logs
		draw_line(f + Vector2(-16, 8), f + Vector2(10, 2), Config.C_WOOD_DARK, 5.0)
		draw_line(f + Vector2(14, 8), f + Vector2(-8, 1), Config.C_WOOD_DARK, 5.0)


func _draw_mound() -> void:
	var n := TERRACES.size()
	for i in range(n):
		var t: Array = TERRACES[i]
		var yb: float = t[0]
		var yt: float = t[1]
		var hwb: float = t[2]
		var hwt: float = t[3]
		var k := float(i) / float(n - 1)
		var col := Config.C_SAND_DEEP.lerp(Config.C_SAND, k)
		draw_colored_polygon(_terrace_poly(yb, yt, hwb, hwt), col)
		# Rim highlight along the top edge, shadow band below it, and a soft
		# occlusion gradient where this terrace meets the one below.
		draw_colored_polygon(_terrace_band(yt, hwt, 0.0, 9.0), col.lightened(0.16))
		draw_colored_polygon(_terrace_band(yt, hwt, 9.0, 22.0), col.lightened(0.05))
		draw_colored_polygon(_terrace_band(yt, hwt, 34.0, 96.0), Color(col.darkened(0.4), 0.5))
		draw_colored_polygon(_terrace_band(yt, hwt, 96.0, 150.0), Color(col.darkened(0.3), 0.2))
		_draw_gullies(yb, yt, hwt, col, 1200 + i * 31)
		# Sand grain and pebble speckle, so the face is not a flat fill.
		var band := Rect2(CX - hwb, yt + 30, hwb * 2.0, yb - yt - 30)
		Gfx.draw_grain(self, band, 260, Color(col.darkened(0.3), 0.22), 700 + i * 13, 1.0, 3.2)
		Gfx.draw_grain(self, band, 150, Color(col.lightened(0.28), 0.16), 900 + i * 17, 1.0, 2.4)
		# Dry-stone retaining course just under the lip.
		_retaining_wall(yt, hwt, col)
		# Vertical face shading at the flanks.
		draw_colored_polygon(_flank(yb, yt, hwb, hwt, -1.0), Color(col.darkened(0.4), 0.3))
		draw_colored_polygon(_flank(yb, yt, hwb, hwt, 1.0), Color(col.darkened(0.25), 0.15))
	_scatter()


## Weathered stone courses along the lip of a terrace.
func _retaining_wall(yt: float, hwt: float, col: Color) -> void:
	var steps := 26
	var stone := col.darkened(0.18)
	for i in range(steps):
		var u := float(i) / float(steps - 1)
		var x := CX - hwt + 2.0 * hwt * u
		var y := yt + 30 - sin(u * PI) * 30.0 + 20.0
		var w := (2.0 * hwt / steps) * 0.92
		var shade := Gfx.hash01(x * 0.05, yt * 0.01)
		draw_rect(Rect2(x, y, w, 11), Color(stone.lerp(col.lightened(0.12), shade), 0.75))


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in range(110):
		var y := rng.randf_range(520, 1700)
		var hw := _half_width_at(y)
		var x := CX + rng.randf_range(-hw + 30, hw - 30)
		var r := rng.randf()
		if r < 0.5:
			# Scrub bush: two lobes plus a moonlit top
			var g := Color("3f4a24").lerp(Color("647537"), rng.randf())
			var s := rng.randf_range(7, 13)
			draw_circle(Vector2(x + 4, y + 4), s, Color(0.02, 0.02, 0.04, 0.25))
			draw_circle(Vector2(x, y), s, g)
			draw_circle(Vector2(x + s * 0.55, y + 2), s * 0.75, g.darkened(0.18))
			draw_circle(Vector2(x - 2, y - s * 0.4), s * 0.45, g.lightened(0.18))
		elif r < 0.78:
			# Loose rock with a lit facet
			var s2 := rng.randf_range(5, 11)
			draw_circle(Vector2(x + 3, y + 3), s2, Color(0.02, 0.02, 0.04, 0.22))
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - s2, y + s2 * 0.5), Vector2(x - s2 * 0.4, y - s2),
				Vector2(x + s2 * 0.7, y - s2 * 0.7), Vector2(x + s2, y + s2 * 0.4),
			]), Config.C_SAND_DARK)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - s2 * 0.4, y - s2), Vector2(x + s2 * 0.7, y - s2 * 0.7), Vector2(x, y - s2 * 0.1),
			]), Config.C_SAND_LIGHT.darkened(0.15))
		else:
			# Grass tufts
			var gc := Color("55622e")
			for b in range(3):
				var bx := x + (b - 1) * 5.0
				draw_line(Vector2(bx, y), Vector2(bx + rng.randf_range(-5, 5), y - rng.randf_range(8, 16)), gc, 2.0)


func _half_width_at(y: float) -> float:
	for t in TERRACES:
		if y <= t[0] and y >= t[1]:
			var u: float = (t[0] - y) / (t[0] - t[1])
			return lerpf(t[2], t[3], u)
	return 400.0


## The top edge of a terrace: a gentle dome plus deterministic erosion. Straight
## arcs were what made the mound read as stacked paper.
func _terrace_edge(yt: float, hwt: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 30
	for i in range(steps + 1):
		var u := float(i) / steps
		var x := CX - hwt + 2.0 * hwt * u
		var bulge := sin(u * PI) * 30.0
		var erosion := sin(x * 0.021 + yt * 0.05) * 7.0 + sin(x * 0.061 + yt * 0.11) * 4.0
		# Pin the ends so neighbouring terraces still line up at the flanks.
		erosion *= sin(u * PI)
		pts.append(Vector2(x, yt + 30 - bulge + erosion))
	return pts


## A strip following that edge, between two depths below it.
func _terrace_band(yt: float, hwt: float, d0: float, d1: float) -> PackedVector2Array:
	var edge := _terrace_edge(yt, hwt)
	var pts := PackedVector2Array()
	for p in edge:
		pts.append(p + Vector2(0, d0))
	for i in range(edge.size() - 1, -1, -1):
		pts.append(edge[i] + Vector2(0, d1))
	return pts


## The sloping side of a terrace, used to shade the left and right flanks.
func _flank(yb: float, yt: float, hwb: float, hwt: float, side: float) -> PackedVector2Array:
	var inset := 110.0
	return PackedVector2Array([
		Vector2(CX + side * hwb, yb),
		Vector2(CX + side * hwt, yt + 30),
		Vector2(CX + side * (hwt - inset), yt + 30),
		Vector2(CX + side * (hwb - inset), yb),
	])


## A terrace: the eroded top edge, closed down to the terrace below it.
func _terrace_poly(yb: float, yt: float, hwb: float, hwt: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(CX - hwb, yb))
	for p in _terrace_edge(yt, hwt):
		pts.append(p)
	pts.append(Vector2(CX + hwb, yb))
	return pts


## Water-cut channels running down a terrace face. Three or four per level is
## enough to stop the slope reading as a flat fill.
func _draw_gullies(yb: float, yt: float, hwt: float, col: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(rng.randi_range(3, 5)):
		var x := CX + rng.randf_range(-hwt * 0.85, hwt * 0.85)
		var top_y := yt + 34.0
		var w := rng.randf_range(9.0, 22.0)
		var drift := rng.randf_range(-26.0, 26.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x - w * 0.5, top_y), Vector2(x + w * 0.5, top_y),
			Vector2(x + drift + w * 0.15, yb), Vector2(x + drift - w * 0.15, yb),
		]), Color(col.darkened(0.3), 0.35))
		draw_line(Vector2(x - w * 0.4, top_y), Vector2(x + drift - w * 0.12, yb),
			Color(col.lightened(0.2), 0.18), 2.0)


# ------------------------------------------------------------------ citadel# ------------------------------------------------------------------ citadel

func _draw_citadel() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1258
	# Rooftops and domes rising behind the wall.
	var roof_col := Config.C_SAND_DARK.darkened(0.15)
	var x := 140.0
	while x < W - 140.0:
		var w := rng.randf_range(46, 105)
		var h := rng.randf_range(28, 84)
		var c := roof_col.lerp(Config.C_SAND_DEEP, rng.randf() * 0.5)
		draw_rect(Rect2(x, 340 - h, w, h + 10), c)
		draw_rect(Rect2(x, 340 - h, w, 5), c.lightened(0.16))
		x += w + rng.randf_range(4, 18)
	# Mosque dome and minaret.
	draw_circle(Vector2(700, 300), 46, Config.C_SAND_LIGHT.darkened(0.22))
	draw_circle(Vector2(690, 292), 34, Config.C_SAND_LIGHT.darkened(0.12))
	draw_rect(Rect2(654, 300, 92, 45), Config.C_SAND_LIGHT.darkened(0.22))
	draw_line(Vector2(700, 254), Vector2(700, 230), Config.C_ROCK, 3.0)
	draw_circle(Vector2(700, 228), 5, Config.C_ROCK)
	draw_rect(Rect2(330, 200, 30, 150), Config.C_SAND_LIGHT.darkened(0.26))
	draw_rect(Rect2(330, 200, 9, 150), Config.C_SAND_LIGHT.darkened(0.12))
	draw_rect(Rect2(322, 236, 46, 14), Config.C_SAND_LIGHT.darkened(0.08))
	draw_colored_polygon(PackedVector2Array([Vector2(322, 200), Vector2(368, 200), Vector2(345, 170)]), Config.C_SAND_LIGHT.darkened(0.2))

	# The continuous facade wall.
	var wall := Rect2(120, 345, W - 240, 145)
	draw_rect(wall, Config.C_WALL)
	# Mud-brick courses.
	for row in range(9):
		var y := 348.0 + row * 16.0
		draw_line(Vector2(122, y), Vector2(W - 122, y), Color(Config.C_WALL_SHADOW, 0.14), 1.0)
	# Perspective darkening toward the sides.
	for i in range(7):
		var k := float(i) / 7.0
		draw_rect(Rect2(120 + i * 20, 345, 20, 145), Color(Config.C_WALL_SHADOW, 0.34 * (1.0 - k)))
		draw_rect(Rect2(W - 140 - i * 20, 345, 20, 145), Color(Config.C_WALL_SHADOW, 0.34 * (1.0 - k)))
	Gfx.draw_grain(self, wall, 520, Color(Config.C_WALL_SHADOW, 0.16), 4242, 1.0, 2.6)
	Gfx.draw_grain(self, wall, 240, Color(Config.C_SAND_LIGHT, 0.12), 4343, 1.0, 2.0)
	Gfx.draw_weathering(self, Rect2(wall.position.x, wall.position.y, wall.size.x, wall.size.y * 0.8),
		34, Color(Config.C_WALL_SHADOW, 0.14), 5151)
	# Base shadow where the wall meets the plateau.
	draw_rect(Rect2(120, 476, W - 240, 16), Color(Config.C_WALL_SHADOW, 0.72))
	draw_rect(Rect2(120, 488, W - 240, 8), Color(0.05, 0.04, 0.03, 0.4))
	# Crenellations with a lit top face.
	var cx := 124.0
	while cx < W - 130.0:
		draw_rect(Rect2(cx, 325, 26, 22), Config.C_WALL)
		draw_rect(Rect2(cx, 325, 26, 5), Config.C_WALL.lightened(0.18))
		draw_rect(Rect2(cx + 21, 325, 5, 22), Color(Config.C_WALL_SHADOW, 0.4))
		cx += 44.0
	# House divisions and arched windows, some lit from inside.
	var hx := 128.0
	while hx < W - 140.0:
		var hw := rng.randf_range(58, 100)
		draw_line(Vector2(hx, 348), Vector2(hx, 478), Color(Config.C_WALL_SHADOW, 0.55), 2.0)
		var nwin := 1 if hw < 75 else 2
		for i in range(nwin):
			var wx := hx + hw * (float(i + 1) / (nwin + 1)) - 9
			for row in range(2):
				var wy := 365.0 + row * 52.0
				draw_rect(Rect2(wx - 3, wy + 5, 24, 27), Color(Config.C_WALL_SHADOW, 0.5))
				draw_rect(Rect2(wx, wy + 8, 18, 22), Config.C_WINDOW)
				draw_circle(Vector2(wx + 9, wy + 8), 9, Config.C_WINDOW)
				if rng.randf() < 0.38:
					var w2 := LitWindow.new()
					w2.position = Vector2(wx + 3, wy + 12)
					add_child(w2)
		hx += hw
	# Torch brackets on the wall (the flames themselves are Flicker nodes).
	for tx in WALL_TORCHES:
		draw_line(Vector2(tx, 345), Vector2(tx, 322), Config.C_IRON_DARK, 5.0)
		draw_rect(Rect2(tx - 7, 316, 14, 8), Config.C_IRON_DARK)
	# Banners.
	for bx in [200.0, 880.0]:
		draw_line(Vector2(bx, 325), Vector2(bx, 266), Config.C_WOOD_DARK, 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(bx, 268), Vector2(bx + 50, 282), Vector2(bx, 302)]), Config.C_ROCK)
		draw_colored_polygon(PackedVector2Array([Vector2(bx, 268), Vector2(bx + 24, 275), Vector2(bx, 285)]), Config.C_ROCK.lightened(0.2))


## Twinkling stars and the occasional shooting star.
class Stars extends Node2D:
	var _stars: Array = []
	var _t := 0.0
	var _shoot := -1.0
	var _shoot_from := Vector2.ZERO
	var _shoot_dir := Vector2(1, 0.35)
	var _next_shoot := 6.0

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 314
		for i in range(130):
			_stars.append([
				Vector2(rng.randf_range(6, 1074), rng.randf_range(6, 540)),
				rng.randf_range(1.0, 3.2),
				rng.randf() * TAU,
				rng.randf(),
			])

	func _process(delta: float) -> void:
		_t += delta
		if _shoot >= 0.0:
			_shoot += delta
			if _shoot > 1.1:
				_shoot = -1.0
		else:
			_next_shoot -= delta
			if _next_shoot <= 0.0:
				_next_shoot = randf_range(9.0, 22.0)
				_shoot = 0.0
				_shoot_from = Vector2(randf_range(100, 900), randf_range(40, 260))
				_shoot_dir = Vector2(randf_range(0.6, 1.0), randf_range(0.2, 0.5)).normalized()
		queue_redraw()

	func _draw() -> void:
		for s in _stars:
			var a: float = 0.5 + 0.5 * sin(_t * (1.2 + float(s[3]) * 1.8) + float(s[2]))
			var col: Color = Config.C_STAR if float(s[3]) < 0.8 else Color("bcd2ff")
			if float(s[1]) > 2.6:
				draw_circle(s[0], float(s[1]) * 2.6, Color(col, 0.10 * a))
			draw_circle(s[0], float(s[1]), Color(col, 0.35 + 0.65 * a))
		if _shoot >= 0.0:
			var u := _shoot / 1.1
			var head: Vector2 = _shoot_from + _shoot_dir * 620.0 * u
			var tail: Vector2 = head - _shoot_dir * 150.0
			var a := sin(u * PI)
			draw_line(tail, head, Color(Config.C_STAR, 0.0), 1.0)
			for i in range(6):
				var k := float(i) / 6.0
				draw_line(tail.lerp(head, k), tail.lerp(head, k + 0.17), Color(Config.C_STAR, a * k * 0.8), 1.0 + k * 2.0)
			draw_circle(head, 3.0, Color(Config.C_STAR, a))


## A flame plus its point light: torches on the wall and the camp fires.
class Flicker extends Node2D:
	var radius := 180.0
	var core := 7.0
	var rate := 11.0
	var _light: PointLight2D
	var _t := 0.0

	func _ready() -> void:
		_t = randf() * 10.0
		_light = Gfx.make_light(Config.C_TORCH, 1.0, radius)
		add_child(_light)

	func _process(delta: float) -> void:
		_t += delta
		var f := 0.78 + 0.22 * sin(_t * rate) + 0.08 * sin(_t * rate * 2.7 + 1.3)
		_light.energy = 0.75 * f
		_light.texture_scale = (radius / 128.0) * (0.94 + 0.06 * f)
		queue_redraw()

	func _draw() -> void:
		var f := 1.0 + 0.18 * sin(_t * rate) + 0.08 * sin(_t * rate * 2.3)
		draw_circle(Vector2(0, -core * 0.4), core * 2.4 * f, Color(Config.C_FIRE, 0.16))
		draw_circle(Vector2.ZERO, core * f, Config.C_FIRE)
		draw_circle(Vector2(0, -core * 0.5), core * 0.62 * f, Config.C_FIRE_HOT)


## A window whose lamp breathes, so the citadel looks inhabited.
class LitWindow extends Node2D:
	var _t := 0.0
	var _rate := 1.0

	func _ready() -> void:
		_t = randf() * 6.0
		_rate = randf_range(0.7, 2.2)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var a := 0.42 + 0.16 * sin(_t * _rate) + 0.06 * sin(_t * _rate * 3.1)
		draw_circle(Vector2(6, 8), 18, Color(Config.C_FIRE, 0.07 * a))
		draw_rect(Rect2(0, 0, 12, 15), Color(Config.C_FIRE_HOT, a))
		draw_rect(Rect2(0, 0, 12, 5), Color(Config.C_FIRE_HOT, a * 0.6))
