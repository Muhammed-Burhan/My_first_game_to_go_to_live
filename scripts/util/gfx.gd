class_name Gfx
extends RefCounted
## Shared drawing helpers: cached gradient textures for 2D lights, soft glows,
## contact shadows, rounded bars and panels. Everything here is procedural so
## the build still needs zero image assets.

static var _light_tex: GradientTexture2D = null
static var _soft_tex: GradientTexture2D = null
static var _vignette_tex: GradientTexture2D = null
static var _flash_shader: Shader = null

const FLASH_SHADER_CODE := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec3 flash_color : source_color = vec3(1.0);
uniform vec3 tint : source_color = vec3(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb *= tint;
	c.rgb = mix(c.rgb, flash_color, clamp(flash, 0.0, 1.0));
	COLOR = c;
}
"""


## Per-node material that can flash a unit white on hit and tint it (elites).
static func flash_material() -> ShaderMaterial:
	if _flash_shader == null:
		_flash_shader = Shader.new()
		_flash_shader.code = FLASH_SHADER_CODE
	var m := ShaderMaterial.new()
	m.shader = _flash_shader
	m.set_shader_parameter("flash", 0.0)
	m.set_shader_parameter("flash_color", Vector3(1, 1, 1))
	m.set_shader_parameter("tint", Vector3(1, 1, 1))
	return m


## Tight falloff, for torches and muzzle flashes.
static func light_texture() -> GradientTexture2D:
	if _light_tex == null:
		_light_tex = _radial([0.0, 0.22, 0.55, 1.0], [1.0, 0.72, 0.24, 0.0], 256)
	return _light_tex


## Wide, gentle falloff, for area glow (the gate, a bonfire).
static func soft_light_texture() -> GradientTexture2D:
	if _soft_tex == null:
		_soft_tex = _radial([0.0, 0.45, 1.0], [0.85, 0.35, 0.0], 256)
	return _soft_tex


## Transparent centre to opaque edge: the screen vignette.
static func vignette_texture() -> GradientTexture2D:
	if _vignette_tex == null:
		_vignette_tex = _radial([0.0, 0.55, 0.8, 1.0], [0.0, 0.0, 0.35, 1.0], 128)
	return _vignette_tex


static func _radial(offsets: Array, alphas: Array, px: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	var cols := PackedColorArray()
	for a in alphas:
		cols.append(Color(1, 1, 1, a))
	g.colors = cols
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = px
	t.height = px
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## A flickering point light. `scale` is the radius in pixels / 128.
static func make_light(color: Color, energy: float, radius: float, soft: bool = false) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = soft_light_texture() if soft else light_texture()
	l.color = color
	l.energy = energy
	l.texture_scale = radius / 128.0
	l.blend_mode = Light2D.BLEND_MODE_ADD
	l.shadow_enabled = false
	return l


# ------------------------------------------------------------------ drawing

## Flattened contact shadow under a unit or a building.
static func draw_shadow(ci: CanvasItem, pos: Vector2, rx: float, squash: float = 0.42, alpha: float = 0.3) -> void:
	ci.draw_set_transform(pos, 0.0, Vector2(1.0, squash))
	ci.draw_circle(Vector2.ZERO, rx, Color(0.02, 0.02, 0.05, alpha * 0.55))
	ci.draw_circle(Vector2.ZERO, rx * 0.72, Color(0.02, 0.02, 0.05, alpha * 0.6))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Layered translucent discs: a cheap bloom that reads well on flat colour.
static func draw_glow(ci: CanvasItem, pos: Vector2, radius: float, color: Color, strength: float = 1.0, steps: int = 5) -> void:
	for i in range(steps):
		var k := float(i) / float(steps)
		var r := radius * (0.35 + k)
		var a := (0.20 * strength) * (1.0 - k) * (1.0 - k)
		ci.draw_circle(pos, r, Color(color, a))


## A rounded capsule bar. `frac` 0..1 fills from the left.
static func draw_bar(ci: CanvasItem, rect: Rect2, frac: float, bg: Color, fg: Color, gloss: bool = true) -> void:
	var r := rect.size.y * 0.5
	_capsule(ci, rect, r, bg)
	var f := clampf(frac, 0.0, 1.0)
	if f > 0.001:
		var inner := Rect2(rect.position + Vector2(2, 2), Vector2(maxf((rect.size.x - 4) * f, rect.size.y - 4), rect.size.y - 4))
		_capsule(ci, inner, inner.size.y * 0.5, fg)
		if gloss:
			var g := Rect2(inner.position + Vector2(r * 0.4, 2), Vector2(maxf(inner.size.x - r * 0.8, 1), inner.size.y * 0.34))
			_capsule(ci, g, g.size.y * 0.5, Color(1, 1, 1, 0.22))


static func _capsule(ci: CanvasItem, rect: Rect2, r: float, col: Color) -> void:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	ci.draw_rect(Rect2(rect.position + Vector2(r, 0), Vector2(maxf(rect.size.x - r * 2, 0), rect.size.y)), col)
	ci.draw_circle(rect.position + Vector2(r, r), r, col)
	ci.draw_circle(rect.position + Vector2(rect.size.x - r, r), r, col)


## Rounded panel with a gold rim and an inner top highlight.
static func draw_panel(ci: CanvasItem, rect: Rect2, bg: Color, line: Color, radius: float = 26.0, border: float = 3.0) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(int(border))
	s.set_corner_radius_all(int(radius))
	s.anti_aliasing = true
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 10
	ci.draw_style_box(s, rect)


static func style_panel(bg: Color, line: Color, radius: int = 26, border: int = 3, shadow: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = line
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.5)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, 4)
	return s


## Text with an outline, centred in `width` at `pos`. Returns nothing; pure draw.
## Defaults to the heavy UI face; pass `Fonts.display()` for a title.
static func draw_text(ci: CanvasItem, pos: Vector2, text: String, size: int, col: Color,
		align: int = HORIZONTAL_ALIGNMENT_CENTER, width: float = -1.0, outline: int = 7,
		font: Font = null) -> void:
	if font == null:
		font = Fonts.ui(Fonts.W_BLACK)
	if outline > 0:
		ci.draw_string_outline(font, pos, text, align, width, size, outline, Color(0, 0, 0, 0.85))
	ci.draw_string(font, pos, text, align, width, size, col)


## Truncate `text` with an ellipsis so it fits `max_width` at `size`. Godot's
## draw_string takes a width for alignment but will happily overflow it, which
## is how contract copy ended up running through its own progress bar.
static func fit_text(text: String, size: int, max_width: float, font: Font = null) -> String:
	if font == null:
		font = Fonts.ui(Fonts.W_MED)
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_width:
		return text
	var out := text
	while out.length() > 1:
		out = out.substr(0, out.length() - 1)
		if font.get_string_size(out + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_width:
			return out.strip_edges() + "…"
	return out


## A rounded-rect sprite with a vertical gradient and a rim, baked once and
## served through a 9-slice StyleBoxTexture. This is what gives buttons and
## panels a moulded look instead of a flat fill.
static func rounded_gradient(top: Color, bottom: Color, border: Color, bw: float,
		radius: float, px: int = 96) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var size := Vector2(px, px)
	for y in range(px):
		var t := float(y) / float(px - 1)
		for x in range(px):
			var d := _rrect_sdf(Vector2(x + 0.5, y + 0.5), size, radius)
			var cover := clampf(0.5 - d, 0.0, 1.0)
			if cover <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var c := top.lerp(bottom, t)
			if bw > 0.0 and d > -bw:
				var edge := clampf((d + bw) / maxf(bw, 0.001), 0.0, 1.0)
				c = c.lerp(border, edge)
			c.a *= cover
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func _rrect_sdf(p: Vector2, size: Vector2, radius: float) -> float:
	var half := size * 0.5
	var q := (p - half).abs() - (half - Vector2(radius, radius))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


static func gradient_box(top: Color, bottom: Color, border: Color, bw: float = 3.0,
		radius: float = 26.0, margins: Vector4 = Vector4(30, 18, 30, 18)) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = rounded_gradient(top, bottom, border, bw, radius)
	var m := radius + 6.0
	s.set_texture_margin(SIDE_LEFT, m)
	s.set_texture_margin(SIDE_RIGHT, m)
	s.set_texture_margin(SIDE_TOP, m)
	s.set_texture_margin(SIDE_BOTTOM, m)
	s.content_margin_left = margins.x
	s.content_margin_top = margins.y
	s.content_margin_right = margins.z
	s.content_margin_bottom = margins.w
	return s


## Speckled grain over a region. Flat fills read as plastic; a few hundred
## deterministic specks read as stone, sand or plaster. Seeded, so it is painted
## once and never shimmers.
static func draw_grain(ci: CanvasItem, rect: Rect2, count: int, col: Color, seed_value: int,
		min_r: float = 1.0, max_r: float = 2.6) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(count):
		var p := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		ci.draw_circle(p, rng.randf_range(min_r, max_r), col)


## Fine parallel scoring: tool marks in stone, grain in timber.
static func draw_hatch(ci: CanvasItem, rect: Rect2, spacing: float, col: Color, width: float = 1.0,
		slant: float = 0.0) -> void:
	var x := rect.position.x
	while x < rect.position.x + rect.size.x:
		ci.draw_line(Vector2(x, rect.position.y),
			Vector2(x + slant * rect.size.y, rect.position.y + rect.size.y), col, width)
		x += spacing


## Vertical weathering streaks: rain and smoke staining a wall from the top down.
static func draw_weathering(ci: CanvasItem, rect: Rect2, count: int, col: Color, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(count):
		var x := rect.position.x + rng.randf() * rect.size.x
		var h := rect.size.y * rng.randf_range(0.25, 0.9)
		var w := rng.randf_range(2.0, 7.0)
		ci.draw_rect(Rect2(x, rect.position.y, w, h), Color(col, col.a * rng.randf_range(0.3, 1.0)))


## Deterministic value noise in [0,1] for terrain scatter. Cheap and stable.
static func hash01(x: float, y: float) -> float:
	var v := sin(x * 127.1 + y * 311.7) * 43758.5453
	return v - floor(v)


static func star_points(center: Vector2, outer: float, inner: float, points: int, phase: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(points * 2):
		var r := outer if i % 2 == 0 else inner
		var a := phase - PI * 0.5 + float(i) * PI / float(points)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
