class_name RenownBar
extends RefCounted
## The progression readout: level chip, a bar, and the next thing worth playing
## for. It appears on the title, in the garrison and on the score screen, and it
## is the same drawing in all three so the number the player watched tick up at
## the end of a run is recognisably the same number on the menu afterwards.

const CHIP_W := 116.0


## Draws into `rect`. `verbose` adds the "next unlock" line underneath, which
## only fits where there is room for it.
## `override_frac` and `override_level` let the score screen animate the fill
## past the value actually stored in the profile.
static func draw_into(ci: CanvasItem, rect: Rect2, verbose: bool = false,
		override_frac: float = -1.0, override_level: int = -1) -> void:
	var prog := Meta.level_progress()
	var lv: int = override_level if override_level > 0 else int(prog["level"])
	var frac: float = override_frac if override_frac >= 0.0 else float(prog["frac"])

	# Level chip on the left: a struck coin, so a level reads as a thing you
	# were given rather than as a row in a table.
	var c := Vector2(rect.position.x + 44, rect.position.y + 40)
	ci.draw_circle(c + Vector2(0, 3), 40, Color(0, 0, 0, 0.45))
	ci.draw_circle(c, 38, Config.C_ROCK.darkened(0.42))
	ci.draw_circle(c, 32, Config.C_ROCK.darkened(0.12))
	ci.draw_circle(c - Vector2(5, 6), 20, Config.C_ROCK.lightened(0.18))
	Gfx.draw_text(ci, Vector2(c.x - 40, c.y + 14), str(lv), 38, Color("2a1d10"),
		HORIZONTAL_ALIGNMENT_CENTER, 80, 0, Fonts.ui(Fonts.W_BLACK))

	var bx := rect.position.x + 96.0
	var bw := rect.size.x - 96.0
	Gfx.draw_text(ci, Vector2(bx, rect.position.y + 24), "RENOWN", 22, Config.C_TEXT_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_BLACK, 4))

	var capped: bool = bool(prog.get("capped", false)) and override_frac < 0.0
	var bar := Rect2(bx, rect.position.y + 36, bw, 26)
	Gfx.draw_bar(ci, bar, 1.0 if capped else frac, Color(0, 0, 0, 0.55), Config.C_ROCK)
	if capped:
		Gfx.draw_text(ci, Vector2(bx, rect.position.y + 24), "EVERYTHING UNLOCKED", 22,
			Config.C_ROCK, HORIZONTAL_ALIGNMENT_RIGHT, bw, 5, Fonts.ui(Fonts.W_BLACK, 3))
	else:
		var have: int = int(prog["have"])
		var need: int = int(prog["need"])
		Gfx.draw_text(ci, Vector2(bx, rect.position.y + 24), "%d / %d" % [have, need], 22,
			Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, bw, 5, Fonts.ui(Fonts.W_BLACK, 2))
	if not verbose:
		return

	var next := Meta.next_unlock()
	if next.is_empty():
		Gfx.draw_text(ci, Vector2(bx, rect.position.y + 92), "Every commander is yours.", 25,
			Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_MED))
		return
	var item: Dictionary = next["items"][0]
	Gfx.draw_text(ci, Vector2(bx, rect.position.y + 92),
		"NEXT  ·  %s" % str(item["name"]), 26, Color(item["color"]),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_BLACK, 2))
	Gfx.draw_text(ci, Vector2(bx, rect.position.y + 92), "%d renown away" % int(next["remaining"]),
		25, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT, bw, 5, Fonts.ui(Fonts.W_MED))
