class_name Fonts
extends RefCounted
## The type system. Two families, loaded once and cached:
##
##   display  Cinzel, a Roman inscriptional face. Carved into stone, which is
##            what the Citadel is. Wordmark and screen titles only, always caps.
##   ui       Rubik. Geometric, heavy weights available, legible at 24px on a
##            phone and from ten metres at the booth. Everything else.
##
## Both are variable fonts, so a weight is a FontVariation over one base file
## rather than a separate download. Arabic and Kurdish fall back to Noto, which
## matters for leaderboard names.

const DISPLAY_PATH := "res://fonts/Cinzel.ttf"
const UI_PATH := "res://fonts/Rubik.ttf"
const ARABIC_PATH := "res://fonts/NotoSansArabic-Bold.ttf"

# Weights we actually use. Naming them stops magic numbers spreading.
const W_BODY := 500
const W_MED := 600
const W_BOLD := 700
const W_BLACK := 900

## OpenType axis tags are four bytes packed big-endian. name_to_tag() is an
## instance method on the text server, and this is a static class, so the one
## tag we need is spelled out.
const _WGHT := 0x77676874  # "wght"

static var _base_display: FontFile = null
static var _base_ui: FontFile = null
static var _cache: Dictionary = {}


static func _load(path: String) -> FontFile:
	var f: Variant = null
	if ResourceLoader.exists(path):
		f = ResourceLoader.load(path)
	if f is FontFile:
		return f
	# Import cache missing (fresh clone, or a --headless run before --import).
	# Reading the raw file keeps the game running instead of silently falling
	# back to the system font and looking like a prototype again.
	var raw := FontFile.new()
	if FileAccess.file_exists(path):
		raw.load_dynamic_font(path)
		return raw
	return null


static func _tune(f: FontFile) -> void:
	if f == null:
		return
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.allow_system_fallback = true


static func base_ui() -> FontFile:
	if _base_ui == null:
		_base_ui = _load(UI_PATH)
		_tune(_base_ui)
		if _base_ui != null:
			var ar := _load(ARABIC_PATH)
			if ar != null:
				_tune(ar)
				_base_ui.fallbacks = [ar] as Array[Font]
	return _base_ui


static func base_display() -> FontFile:
	if _base_display == null:
		_base_display = _load(DISPLAY_PATH)
		_tune(_base_display)
	return _base_display


static func _variation(base: FontFile, weight: int, spacing: int) -> Font:
	if base == null:
		return ThemeDB.fallback_font
	var key := "%s|%d|%d" % [base.get_instance_id(), weight, spacing]
	if _cache.has(key):
		return _cache[key]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {_WGHT: weight}
	if spacing != 0:
		fv.spacing_glyph = spacing
	_cache[key] = fv
	return fv


## Rubik at a weight. The default is what body copy and most labels use.
static func ui(weight: int = W_BOLD, spacing: int = 0) -> Font:
	return _variation(base_ui(), weight, spacing)


## Cinzel, always black weight. Caps are tracked out a little because
## inscriptional faces set tight and a wordmark wants air.
static func display(spacing: int = 3) -> Font:
	return _variation(base_display(), W_BLACK, spacing)


## Numbers that change every frame (rock, wave, timers). Same face as the UI,
## but heavy so a counter reads as a counter.
static func num(weight: int = W_BLACK) -> Font:
	return _variation(base_ui(), weight, 0)
