class_name Wordmark
extends RefCounted
## The one lockup, drawn the same way everywhere it appears: the loading screen,
## the title, and the share card people post. Having three screens re-type the
## title in whatever font was handy is what made the old build look unfinished.
##
##        C I T A D E L        Cinzel, tracked out, gold on a cut shadow
##   ═══   DEFENSE   ═══       Rubik black, small, flanked by rules
##    ERBIL · 1258 · ...       caption
##
## `t` drives a shine that sweeps across the letters; pass 0.0 for a still.

const GOLD_HI := Color("ffe9b0")
const GOLD := Color("e9c37a")
const GOLD_LO := Color("a9762f")
const CUT := Color("120a04")


## Draws centred inside `width`, with `y` the baseline of CITADEL.
## `s` scales the whole lockup. Returns the y below the caption.
static func draw(ci: CanvasItem, y: float, width: float, s: float = 1.0, t: float = 0.0,
		caption: String = "ERBIL  ·  1258  ·  HOLD THE GATE") -> float:
	var big := int(round(132.0 * s))
	var disp := Fonts.display(int(round(10.0 * s)))
	var main := "CITADEL"

	# Cut shadow: the letters look chiselled into the panel rather than laid on
	# top of it, so the drop goes down-right and a light edge goes up-left.
	ci.draw_string(disp, Vector2(0, y + 7.0 * s), main, HORIZONTAL_ALIGNMENT_CENTER, width, big, CUT)
	ci.draw_string_outline(disp, Vector2(0, y), main, HORIZONTAL_ALIGNMENT_CENTER, width, big,
		int(round(14.0 * s)), CUT)
	ci.draw_string(disp, Vector2(0, y - 3.0 * s), main, HORIZONTAL_ALIGNMENT_CENTER, width, big,
		Color(1, 1, 1, 0.14))
	ci.draw_string(disp, Vector2(0, y), main, HORIZONTAL_ALIGNMENT_CENTER, width, big, GOLD)

	# Shine: a soft band travelling across the letters, clipped to their row.
	if t > 0.0:
		var band := Rect2(0, y - big * 0.88, width, big * 1.0)
		var sweep := fmod(t * 0.32, 2.8) / 2.8
		var sx := lerpf(-width * 0.35, width * 1.2, sweep)
		for i in range(5):
			var k := float(i) / 4.0
			var w := 30.0 * s
			var a := 0.085 * (1.0 - absf(k - 0.5) * 2.0)
			var x := sx + k * 90.0 * s
			ci.draw_colored_polygon(PackedVector2Array([
				Vector2(x - w, band.position.y), Vector2(x + w, band.position.y),
				Vector2(x + w - 52.0 * s, band.end.y), Vector2(x - w - 52.0 * s, band.end.y),
			]), Color(GOLD_HI, a))

	# DEFENSE, small and wide, between two rules. The contrast in size and
	# tracking is what stops the lockup reading as two lines of the same word.
	var sub_size := int(round(44.0 * s))
	var sub_font := Fonts.ui(Fonts.W_BLACK, int(round(14.0 * s)))
	var sub_y := y + 62.0 * s
	var word := "DEFENSE"
	var wmeasure := sub_font.get_string_size(word, HORIZONTAL_ALIGNMENT_CENTER, -1, sub_size).x
	ci.draw_string_outline(sub_font, Vector2(0, sub_y), word, HORIZONTAL_ALIGNMENT_CENTER, width,
		sub_size, int(round(8.0 * s)), CUT)
	ci.draw_string(sub_font, Vector2(0, sub_y), word, HORIZONTAL_ALIGNMENT_CENTER, width, sub_size, GOLD_HI)
	var rule_y := sub_y - sub_size * 0.32
	var gap := wmeasure * 0.5 + 34.0 * s
	var rule_len := 150.0 * s
	for d_any in [-1.0, 1.0]:
		var dir: float = d_any
		var x0: float = width * 0.5 + dir * gap
		var x1: float = x0 + dir * rule_len
		ci.draw_line(Vector2(x0, rule_y), Vector2(x1, rule_y), Color(GOLD_LO, 0.9), 4.0 * s)
		ci.draw_line(Vector2(x0, rule_y + 7.0 * s), Vector2(x0 + dir * rule_len * 0.55, rule_y + 7.0 * s),
			Color(GOLD_LO, 0.45), 2.5 * s)
		# A small diamond terminal, so the rules read as ornament, not underline.
		var d := 7.0 * s
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(x1 + dir * d, rule_y), Vector2(x1, rule_y - d),
			Vector2(x1 - dir * d, rule_y), Vector2(x1, rule_y + d),
		]), GOLD)

	if caption == "":
		return sub_y + 30.0 * s
	var cap_size := int(round(30.0 * s))
	var cap_y := sub_y + 76.0 * s
	Gfx.draw_text(ci, Vector2(0, cap_y), caption, cap_size, Color(GOLD, 0.92),
		HORIZONTAL_ALIGNMENT_CENTER, width, int(round(7.0 * s)), Fonts.ui(Fonts.W_BOLD, int(round(6.0 * s))))
	return cap_y + 24.0 * s
