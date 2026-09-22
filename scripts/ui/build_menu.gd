class_name BuildMenu
extends Control
## The build sheet. Slides up from the bottom when a plinth or an emplacement is
## tapped. Six defences no longer fit a radial, and a bottom sheet is where a
## thumb already is — so it is a row of cards, with the stats spelled out.

signal build_chosen(slot: Slot, type: int)
signal upgrade_chosen(tower: Tower)
signal sell_chosen(tower: Tower)
signal repair_chosen(tower: Tower)
signal closed

const VIEW_W := 1080.0
const VIEW_H := 1920.0
const SHEET_H := 500.0
const SHEET_Y := VIEW_H - SHEET_H

var _slot: Slot = null
var _tower: Tower = null
var _sheet: Sheet
var _cards: Array[TowerCard] = []
var _info: TowerInfo
var _upgrade_btn: Button
var _repair_btn: Button
var _sell_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	_sheet = Sheet.new()
	_sheet.position = Vector2(0, SHEET_Y)
	_sheet.size = Vector2(VIEW_W, SHEET_H)
	_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_sheet)

	# Build row: one card per defence, always in the same order.
	var n := Config.TOWER_ORDER.size()
	var cw := 165.0
	var gap := (VIEW_W - 48.0 - cw * n) / float(n - 1)
	for i in range(n):
		var card := TowerCard.new()
		card.tower_type = Config.TOWER_ORDER[i]
		card.position = Vector2(24 + i * (cw + gap), 96)
		card.size = Vector2(cw, 300)
		card.chosen.connect(_on_build)
		_sheet.add_child(card)
		_cards.append(card)

	_info = TowerInfo.new()
	_info.position = Vector2(24, 84)
	_info.size = Vector2(VIEW_W - 48, 210)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet.add_child(_info)

	_upgrade_btn = _button("UPGRADE", Vector2(24, 314), Vector2(370, 108))
	UiTheme.make_primary(_upgrade_btn)
	_upgrade_btn.pressed.connect(_on_upgrade)
	_repair_btn = _button("REPAIR", Vector2(410, 314), Vector2(300, 108))
	_repair_btn.pressed.connect(_on_repair)
	_sell_btn = _button("SELL", Vector2(726, 314), Vector2(330, 108))
	UiTheme.make_danger(_sell_btn)
	_sell_btn.pressed.connect(_on_sell)

	Game.rock_changed.connect(func(_v): _refresh())


func _button(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.add_theme_font_size_override("font_size", 36)
	_sheet.add_child(b)
	UiTheme.add_press_feel(b)
	return b


func is_open() -> bool:
	return visible


func open_slot(slot: Slot) -> void:
	_clear()
	_slot = slot
	_sheet.title = "BUILD"
	_sheet.subtitle = "Plinth %d" % (slot.index + 1)
	_sheet.queue_redraw()
	_set_mode(true)
	_show()


func open_tower(tower: Tower) -> void:
	_clear()
	_tower = tower
	tower.selected = true
	_sheet.title = str(Config.TOWERS[tower.type]["name"]).to_upper()
	_sheet.subtitle = "Tier %d" % tower.tier
	_sheet.queue_redraw()
	_info.tower = tower
	_set_mode(false)
	_show()


func close() -> void:
	if not visible:
		return
	_clear()
	visible = false
	closed.emit()


func _set_mode(building: bool) -> void:
	for c in _cards:
		c.visible = building
	_info.visible = not building
	_upgrade_btn.visible = not building
	_repair_btn.visible = not building
	_sell_btn.visible = not building


func _show() -> void:
	visible = true
	_refresh()
	_sheet.position.y = VIEW_H
	var tw := create_tween()
	tw.tween_property(_sheet, "position:y", SHEET_Y, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("click")


func _clear() -> void:
	if _tower != null and is_instance_valid(_tower):
		_tower.selected = false
	_tower = null
	_slot = null
	_info.tower = null


func _refresh() -> void:
	for c in _cards:
		c.affordable = Game.can_afford(Config.tower_cost(c.tower_type, 1))
		c.queue_redraw()
	if _tower == null or not is_instance_valid(_tower):
		return
	var maxed := _tower.tier >= Config.MAX_TIER
	var up_cost := 0 if maxed else Config.tower_cost(_tower.type, _tower.tier + 1)
	_upgrade_btn.text = "MAX TIER" if maxed else "UPGRADE  %d" % up_cost
	_upgrade_btn.disabled = maxed or not Game.can_afford(up_cost)
	var rep := _tower.repair_cost()
	_repair_btn.text = "REPAIRED" if rep == 0 else "REPAIR  %d" % rep
	_repair_btn.disabled = rep == 0 or not Game.can_afford(rep)
	_sell_btn.text = "SELL  +%d" % int(round(_tower.total_invested() * Config.SELL_REFUND))
	_info.queue_redraw()


func _process(_delta: float) -> void:
	if visible and _tower != null and is_instance_valid(_tower):
		_info.queue_redraw()


## A tap outside the sheet closes it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		close()


func _on_build(type: int) -> void:
	var s := _slot
	if s == null:
		return
	if not Game.can_afford(Config.tower_cost(type, 1)):
		Sfx.play("deny")
		return
	close()
	build_chosen.emit(s, type)


func _on_upgrade() -> void:
	var t := _tower
	if t == null or t.tier >= Config.MAX_TIER:
		Sfx.play("deny")
		return
	close()
	upgrade_chosen.emit(t)


func _on_repair() -> void:
	var t := _tower
	if t == null or t.repair_cost() == 0:
		Sfx.play("deny")
		return
	close()
	repair_chosen.emit(t)


func _on_sell() -> void:
	var t := _tower
	close()
	if t != null:
		sell_chosen.emit(t)


# ------------------------------------------------------------------ widgets

## The sheet body: a raised slab with a grab handle and a title.
class Sheet extends Control:
	var title := "BUILD"
	var subtitle := ""
	var _box: StyleBoxTexture

	func _ready() -> void:
		_box = Gfx.gradient_box(Color(0.10, 0.14, 0.24, 0.98), Color(0.03, 0.05, 0.11, 0.99),
			Config.C_UI_LINE, 4.0, 34.0)

	func _draw() -> void:
		draw_style_box(_box, Rect2(Vector2(-8, 0), size + Vector2(16, 40)))
		Gfx.draw_bar(self, Rect2(size.x * 0.5 - 60, 16, 120, 10), 1.0, Color(0, 0, 0, 0),
			Color(Config.C_UI_LINE, 0.5), false)
		Gfx.draw_text(self, Vector2(24, 68), title, 40, Config.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
		if subtitle != "":
			var w := ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
			Gfx.draw_text(self, Vector2(40 + w, 66), subtitle, 28, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 5)


## One buildable defence: icon, name, cost, and a one-word role.
class TowerCard extends Control:
	signal chosen(type: int)

	var tower_type := 0
	var affordable := true
	var _down := false
	var _box: StyleBoxTexture
	var _box_off: StyleBoxTexture

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var tint: Color = Config.TOWERS[tower_type]["color"]
		_box = Gfx.gradient_box(Color("22324f"), Color("0b1122"), tint.lightened(0.3), 3.0, 22.0)
		_box_off = Gfx.gradient_box(Color(0.08, 0.09, 0.13, 0.9), Color(0.04, 0.05, 0.08, 0.9),
			Color(tint, 0.3), 2.0, 22.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if event.pressed:
				_down = true
				queue_redraw()
			elif _down:
				_down = false
				queue_redraw()
				chosen.emit(tower_type)

	func _draw() -> void:
		var t: Dictionary = Config.TOWERS[tower_type]
		var tint: Color = t["color"]
		draw_style_box(_box if affordable else _box_off, Rect2(Vector2.ZERO, size))
		if _down and affordable:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.12))
		var a := 1.0 if affordable else 0.42
		BuildMenu.draw_tower_icon(self, Vector2(size.x * 0.5, 96), tower_type, a)
		Gfx.draw_text(self, Vector2(0, 186), str(t["name"]).to_upper(), 23,
			Color(Config.C_TEXT, a), HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		var pill := Rect2(18, 210, size.x - 36, 40)
		Gfx.draw_bar(self, pill, 1.0, Color(0, 0, 0, 0), Color(0.02, 0.03, 0.07, 0.8), false)
		Gfx.draw_text(self, Vector2(0, 240), str(int(t["cost"])), 30,
			Config.C_ROCK if affordable else Config.C_THREAT, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		# A one-word role, so the row reads without reading.
		var role := "SPLASH"
		match tower_type:
			Config.TowerType.ARCHER:
				role = "CHEAP"
			Config.TowerType.GUARD:
				role = "BLOCKS"
			Config.TowerType.NAPHTHA:
				role = "BURNS"
			Config.TowerType.BALLISTA:
				role = "PIERCES"
			Config.TowerType.MANGONEL:
				role = "SIEGE"
		Gfx.draw_text(self, Vector2(0, 280), role, 20, Color(tint, a), HORIZONTAL_ALIGNMENT_CENTER, size.x, 4)


## Stats for the selected emplacement: bars, not just numbers.
class TowerInfo extends Control:
	var tower: Tower = null

	func _draw() -> void:
		if tower == null or not is_instance_valid(tower):
			return
		var t: Dictionary = Config.TOWERS[tower.type]
		BuildMenu.draw_tower_icon(self, Vector2(80, 96), tower.type, 1.0)
		Gfx.draw_text(self, Vector2(160, 44), str(t["blurb"]), 26, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 5)
		var frac := tower.damage_fraction()
		Gfx.draw_text(self, Vector2(160, 84), "CONDITION", 20, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		Gfx.draw_bar(self, Rect2(300, 64, 300, 22), frac, Color(0, 0, 0, 0.55),
			Config.C_GOOD if frac > 0.5 else (Config.C_FIRE if frac > 0.25 else Config.C_THREAT))
		var rows := [
			["DAMAGE", float(tower.stats["damage"]) / 200.0, "%d" % int(tower.stats["damage"])],
			["RATE", float(tower.stats["rate"]) / 4.0, "%.1f/s" % float(tower.stats["rate"])],
			["RANGE", float(tower.stats["range"]) / 700.0, "%d" % int(tower.stats["range"])],
		]
		for i in range(rows.size()):
			var y := 120.0 + i * 30.0
			Gfx.draw_text(self, Vector2(160, y + 18), str(rows[i][0]), 20, Config.C_TEXT_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
			Gfx.draw_bar(self, Rect2(300, y, 300, 20), clampf(float(rows[i][1]), 0.0, 1.0),
				Color(0, 0, 0, 0.55), Config.C_ROCK)
			Gfx.draw_text(self, Vector2(620, y + 18), str(rows[i][2]), 22, Config.C_TEXT,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 4)
		if Config.has_garrison(tower.type):
			var alive := 0
			for d in tower.defenders:
				if is_instance_valid(d) and d.alive:
					alive += 1
			Gfx.draw_text(self, Vector2(760, 138), "GARRISON  %d" % alive, 26, Config.C_GOOD,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 5)


## Shared emplacement icon, used by the build cards and the info panel.
static func draw_tower_icon(ci: CanvasItem, c: Vector2, type: int, a: float = 1.0) -> void:
	match type:
		Config.TowerType.ARCHER:
			ci.draw_rect(Rect2(c.x - 26, c.y + 4, 52, 9), Color(Config.C_WOOD, a))
			ci.draw_line(c + Vector2(-19, 13), c + Vector2(-15, 38), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_line(c + Vector2(19, 13), c + Vector2(15, 38), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_circle(c + Vector2(0, -10), 12, Color(Config.C_GOOD, a))
			ci.draw_circle(c + Vector2(0, -28), 9, Color(Color("d9a372"), a))
			ci.draw_arc(c + Vector2(15, -16), 17, -1.3, 1.3, 10, Color(Config.C_WOOD_DARK, a), 3.0)
		Config.TowerType.GUARD:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-28, 38), c + Vector2(28, 38), c + Vector2(23, -8), c + Vector2(-23, -8)]),
				Color(Config.C_SAND_DARK, a))
			var mx := -28.0
			while mx < 20.0:
				ci.draw_rect(Rect2(c.x + mx, c.y - 22, 13, 14), Color(Config.C_SAND_DARK, a))
				mx += 20.0
			ci.draw_line(c + Vector2(0, -34), c + Vector2(0, 16), Color(Config.C_WOOD, a), 4.0)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-7, -32), c + Vector2(7, -32), c + Vector2(0, -46)]), Color(Config.C_IRON, a))
		Config.TowerType.OIL:
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-24, 38), c + Vector2(24, 38), c + Vector2(18, 6), c + Vector2(-18, 6)]),
				Color(Color("8a8580"), a))
			ci.draw_circle(c + Vector2(0, 16), 10, Color(Config.C_FIRE, a))
			ci.draw_circle(c + Vector2(0, -12), 21, Color(Config.C_IRON_DARK, a))
			ci.draw_rect(Rect2(c.x - 23, c.y - 18, 46, 7), Color(Config.C_IRON, a))
			ci.draw_circle(c + Vector2(6, -34), 6, Color(Config.C_FIRE, a))
		Config.TowerType.NAPHTHA:
			ci.draw_line(c + Vector2(-20, 38), c + Vector2(-12, 10), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_line(c + Vector2(20, 38), c + Vector2(12, 10), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_circle(c + Vector2(0, -4), 20, Color(Color("b8863f"), a))
			ci.draw_circle(c + Vector2(-6, -10), 9, Color(Color("d8a860"), a))
			ci.draw_rect(Rect2(c.x + 14, c.y - 16, 30, 10), Color(Color("7a5628"), a))
			ci.draw_circle(c + Vector2(48, -11), 8, Color(Config.C_FIRE, a))
			ci.draw_circle(c + Vector2(50, -13), 4, Color(Config.C_FIRE_HOT, a))
		Config.TowerType.BALLISTA:
			ci.draw_rect(Rect2(c.x - 26, c.y + 20, 52, 13), Color(Config.C_WOOD_DARK, a))
			ci.draw_rect(Rect2(c.x - 5, c.y - 8, 10, 30), Color(Config.C_WOOD_DARK, a))
			ci.draw_line(c + Vector2(-30, -6), c + Vector2(30, -6), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_line(c + Vector2(-30, -6), c + Vector2(0, -26), Color(Config.C_SAND_LIGHT, a), 2.0)
			ci.draw_line(c + Vector2(30, -6), c + Vector2(0, -26), Color(Config.C_SAND_LIGHT, a), 2.0)
			ci.draw_line(c + Vector2(0, -2), c + Vector2(0, -44), Color(Config.C_IRON, a), 4.0)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(-6, -40), c + Vector2(0, -52), c + Vector2(6, -40)]), Color(Config.C_IRON_DARK, a))
		Config.TowerType.MANGONEL:
			ci.draw_rect(Rect2(c.x - 30, c.y + 24, 60, 12), Color(Config.C_WOOD_DARK, a))
			ci.draw_line(c + Vector2(-18, 24), c + Vector2(0, -14), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_line(c + Vector2(18, 24), c + Vector2(0, -14), Color(Config.C_WOOD_DARK, a), 6.0)
			ci.draw_line(c + Vector2(0, -14), c + Vector2(34, -40), Color(Config.C_WOOD, a), 6.0)
			ci.draw_line(c + Vector2(0, -14), c + Vector2(-16, -2), Color(Config.C_WOOD_DARK, a), 9.0)
			ci.draw_circle(c + Vector2(-18, 0), 11, Color(Config.C_IRON_DARK, a))
			ci.draw_circle(c + Vector2(36, -30), 9, Color(Color("8a8580"), a))
