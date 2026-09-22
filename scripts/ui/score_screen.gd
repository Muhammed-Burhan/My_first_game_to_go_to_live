class_name ScoreScreen
extends Control
## End-of-run screen. Stars, the score, and then the part that actually decides
## whether there is another run: renown counting up, the contracts that ticked
## while you were playing, and the next thing waiting one level away.
##
## The old version ended on a number and a leaderboard. A number is a verdict,
## not an invitation. Everything below the score is there to make the RETRY
## button the obvious thing to press.

signal play_again
signal back_to_title
signal share_requested

var _result: Dictionary = {}
var _panel: Panel
var _stars: StarRow
var _headline: Label
var _sub: Label
var _best_badge: Label
var _breakdown: Label
var _total: Label
var _progress: ProgressBlock
var _contracts: ContractStrip
var _name_edit: LineEdit
var _submit_btn: Button
var _rank_label: Label
var _qr: QrView
var _qr_hint: Label
var _again_btn: Button
var _menu_btn: Button
var _share_btn: Button
var _idle_label: Label
var _board: LeaderboardPanel
var _idle := 0.0
var _submitted := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.04, 0.09, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = Panel.new()
	_panel.position = Vector2(46, 92)
	_panel.size = Vector2(988, 1712)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_stars = StarRow.new()
	_stars.position = Vector2(340, 118)
	_stars.size = Vector2(400, 116)
	add_child(_stars)

	_headline = _label("THE GATE HELD", 68, 236, Config.C_ROCK)
	_best_badge = _label("NEW BEST", 30, 312, Config.C_GOOD)
	_sub = _label("", 28, 350, Config.C_TEXT)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.size.y = 70
	_total = _label("0", 108, 404, Config.C_TEXT)
	_breakdown = _label("", 26, 530, Config.C_TEXT_DIM)
	_breakdown.size.y = 40

	# The renown block: what this run was worth, and what it is worth more of.
	_progress = ProgressBlock.new()
	_progress.position = Vector2(80, 586)
	_progress.size = Vector2(920, 232)
	add_child(_progress)

	_contracts = ContractStrip.new()
	_contracts.position = Vector2(80, 834)
	_contracts.size = Vector2(920, 186)
	add_child(_contracts)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name (3-12)"
	_name_edit.max_length = Leaderboard.NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.position = Vector2(110, 1046)
	_name_edit.size = Vector2(540, 96)
	_name_edit.text_submitted.connect(func(_t): _on_submit())
	add_child(_name_edit)

	_submit_btn = Button.new()
	_submit_btn.text = "SUBMIT"
	_submit_btn.position = Vector2(672, 1046)
	_submit_btn.size = Vector2(298, 96)
	_submit_btn.pressed.connect(_on_submit)
	add_child(_submit_btn)
	UiTheme.make_primary(_submit_btn)
	UiTheme.add_press_feel(_submit_btn)

	_rank_label = _label("", 38, 1160, Config.C_ROCK)

	_qr = QrView.new()
	_qr.position = Vector2(370, 1210)
	_qr.size = Vector2(340, 340)
	_qr.visible = false
	add_child(_qr)
	_qr_hint = _label("Scan to claim your printed tower", 30, 1556, Config.C_TEXT)
	_qr_hint.visible = false

	_board = LeaderboardPanel.new()
	_board.position = Vector2(100, 1210)
	_board.size = Vector2(880, 380)
	add_child(_board)

	# RETRY is the whole point of this screen, so it is the widest, brightest
	# thing on it and it sits where a thumb already is.
	_again_btn = Button.new()
	_again_btn.text = "DEFEND AGAIN"
	_again_btn.position = Vector2(80, 1620)
	_again_btn.size = Vector2(620, 128)
	_again_btn.pressed.connect(func():
		Sfx.play("click")
		play_again.emit())
	add_child(_again_btn)
	UiTheme.make_primary(_again_btn)
	UiTheme.add_press_feel(_again_btn)

	_share_btn = Button.new()
	_share_btn.text = "SHARE"
	_share_btn.position = Vector2(716, 1620)
	_share_btn.size = Vector2(150, 128)
	_share_btn.add_theme_font_size_override("font_size", 26)
	_share_btn.pressed.connect(func():
		Sfx.play("click")
		share_requested.emit())
	add_child(_share_btn)
	UiTheme.add_press_feel(_share_btn)

	_menu_btn = Button.new()
	_menu_btn.text = "MENU"
	_menu_btn.position = Vector2(882, 1620)
	_menu_btn.size = Vector2(150, 128)
	_menu_btn.add_theme_font_size_override("font_size", 26)
	_menu_btn.pressed.connect(func():
		Sfx.play("back")
		back_to_title.emit())
	add_child(_menu_btn)
	UiTheme.add_press_feel(_menu_btn)

	_idle_label = _label("", 26, 1772, Config.C_TEXT_DIM)


func _label(text: String, size: int, y: float, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.position = Vector2(70, y)
	l.size = Vector2(940, size + 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func show_result(result: Dictionary) -> void:
	_result = result
	_submitted = false
	_idle = 0.0
	visible = true
	var won: bool = result["won"]
	var endless: bool = bool(Config.MODES[int(result.get("mode", Config.Mode.CAMPAIGN))]["endless"])
	if endless:
		_headline.text = "THE GATE FELL"
		_headline.add_theme_color_override("font_color", Config.C_THREAT)
		_sub.text = "%d waves held  ·  %s tier  ·  %d broken" % [
			result["waves"], Config.endless_tier(maxi(int(result["waves"]), 1)), result["kills"]]
	else:
		_headline.text = "THE GATE HELD" if won else "THE GATE FELL"
		_headline.add_theme_color_override("font_color", Config.C_ROCK if won else Config.C_THREAT)
		if won:
			_sub.text = "All %d waves broken on the mound" % Config.WAVE_COUNT
		else:
			_sub.text = "Fell on wave %d of %d  ·  the second run is the one" % [
				int(result["waves"]) + 1, Config.WAVE_COUNT]
	_best_badge.visible = bool(result.get("new_best", false))
	var b: Dictionary = result["breakdown"]
	var mins := int(float(result["duration"])) / 60
	var secs := int(float(result["duration"])) % 60
	# One line instead of five: the breakdown was never the reason anyone
	# stayed on this screen, and it was eating the room that is.
	if endless:
		_breakdown.text = "%d rock  ·  %d kills  ·  best streak x%d  ·  %d:%02d" % [
			b["rock"], result["kills"], result.get("best_combo", 0), mins, secs]
	else:
		_breakdown.text = "%d rock  ·  %d lives kept  ·  %d kills  ·  %d:%02d" % [
			b["rock"], result["lives"], result["kills"], mins, secs]
	_total.text = "0"
	_name_edit.text = str(Save.data.get("last_name", ""))
	_name_edit.editable = true
	_name_edit.visible = true
	_submit_btn.visible = true
	_rank_label.text = ""
	_qr.visible = false
	_qr_hint.visible = false
	_board.highlight_id = ""
	_board.board = "daily"
	_board.refresh()
	_board.visible = true
	_idle_label.text = ""
	_panel.scale = Vector2(0.92, 0.92)
	_panel.pivot_offset = _panel.size / 2
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Count the score up, then drop the stars in one at a time.
	var ct := create_tween()
	ct.tween_method(func(v): _total.text = str(int(v)), 0.0, float(result["score"]), 1.0).set_ease(Tween.EASE_OUT)
	_stars.play(Config.stars_for(result))
	_progress.play(result.get("meta", {}))
	_contracts.refresh()


func _on_submit() -> void:
	if _submitted:
		return
	var player_name := Leaderboard.clean_name(_name_edit.text)
	if player_name == "":
		Sfx.play("deny")
		_rank_label.text = "Name: 3 to 12 letters or numbers"
		_rank_label.add_theme_color_override("font_color", Config.C_THREAT)
		return
	_submitted = true
	_idle = 0.0
	Sfx.play("coin")
	Save.remember_name(player_name)
	var info := Leaderboard.submit(player_name, _result)
	_name_edit.editable = false
	_name_edit.visible = false
	_submit_btn.visible = false
	_rank_label.add_theme_color_override("font_color", Config.C_ROCK)
	_rank_label.text = "%s  ·  #%d today  ·  #%d all-time" % [player_name, info["rank_daily"], info["rank_alltime"]]
	# The board and the QR live where the contracts were: by the time someone
	# is submitting a name they have already read them.
	_contracts.visible = false
	_progress.visible = false
	if info["top10"]:
		_qr.set_text(info["claim_url"])
		_qr.visible = true
		_qr_hint.visible = true
		_qr_hint.text = "Top 10!  Scan to claim your printed tower"
		_board.visible = false
	else:
		_board.highlight_id = info["id"]
		_board.refresh()


func _process(delta: float) -> void:
	if not visible or not Game.booth_mode:
		return
	_idle += delta
	var left := Config.BOOTH_IDLE_RESTART - _idle
	_idle_label.text = "Next defender in %d" % int(ceil(left))
	if left <= 0.0:
		visible = false
		back_to_title.emit()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_idle = 0.0


# ------------------------------------------------------------------ renown

## "+186 RENOWN", a bar that fills, and the next unlock. The bar animates past
## the level boundary rather than snapping, because watching it cross is the
## moment that sells the whole system.
class ProgressBlock extends Control:
	var _meta: Dictionary = {}
	var _shown := 0        # renown counted so far
	var _target := 0
	var _t := 0.0
	var _unlocked: Array = []
	var _box: StyleBoxTexture
	## Seconds since play() began, and when the unlock banner is allowed in.
	var _elapsed := 0.0
	var _banner_at := 0.0
	var _banner_rung := false
	const COUNT_DELAY := 0.55
	const COUNT_TIME := 1.1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_box = Gfx.gradient_box(Color(0.06, 0.09, 0.17, 0.95), Color(0.025, 0.04, 0.09, 0.96),
			Color(Config.C_ROCK, 0.45), 2.0, 24.0)
		set_process(true)

	func play(meta: Dictionary) -> void:
		visible = true
		_meta = meta
		_shown = 0
		_target = int(meta.get("gained", 0))
		_t = 0.0
		_elapsed = 0.0
		_banner_rung = false
		_unlocked = []
		for lv in meta.get("levels", []):
			for item in Meta.unlocks_at(int(lv)):
				_unlocked.append(item)
		# The banner waits for the bar. Watching the fill cross the level line
		# is the whole moment; covering it with the prize before it gets there
		# throws the payoff away.
		_banner_at = COUNT_DELAY + COUNT_TIME + 0.15
		if _target > 0:
			var tw := create_tween()
			tw.tween_interval(COUNT_DELAY)
			tw.tween_method(func(v): _set_shown(int(v)), 0.0, float(_target), COUNT_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		queue_redraw()

	func _set_shown(v: int) -> void:
		if v != _shown:
			_shown = v
			queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		_elapsed += delta
		if _unlocked.is_empty():
			return
		if not _banner_rung and _elapsed >= _banner_at:
			_banner_rung = true
			Sfx.play("star", -2.0)
		queue_redraw()

	## Where the bar sits partway through the count-up, including any level
	## boundary it crosses on the way.
	func _animated() -> Dictionary:
		var before := int(_meta.get("before", Meta.renown()))
		var total := before + _shown
		var lv := Meta.level_for_renown(total)
		var from := Meta.renown_for_level(lv)
		var to := Meta.renown_for_level(lv + 1)
		if lv >= Meta.LEVEL_CAP:
			return {"level": lv, "frac": 1.0}
		return {"level": lv, "frac": clampf(float(total - from) / maxf(float(to - from), 1.0), 0.0, 1.0)}

	func _draw() -> void:
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		if _meta.is_empty():
			Gfx.draw_text(self, Vector2(0, 74), "RENOWN IS NOT AWARDED AT THE BOOTH", 26,
				Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 5, Fonts.ui(Fonts.W_MED))
			return
		var anim := _animated()
		Gfx.draw_text(self, Vector2(30, 52), "+%d RENOWN" % _shown, 44, Config.C_ROCK,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 7)
		# What it was earned for, on one line.
		var parts: Array = []
		for line in _meta.get("lines", []):
			parts.append("%s +%d" % [str(line[0]), int(line[1])])
		Gfx.draw_text(self, Vector2(30, 88), "  ·  ".join(parts), 23, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_MED))
		RenownBar.draw_into(self, Rect2(20, 104, size.x - 40, 96), true,
			float(anim["frac"]), int(anim["level"]))
		if not _unlocked.is_empty() and _elapsed >= _banner_at:
			_draw_unlock_banner()

	## A level crossed during the count-up gets its own gold banner over the
	## block. This is the payoff, so it is allowed to shout.
	func _draw_unlock_banner() -> void:
		var item: Dictionary = _unlocked[0]
		var col: Color = item["color"]
		var pulse := 0.5 + 0.5 * sin(_t * 3.4)
		# Slams in and settles, rather than simply appearing.
		var age := _elapsed - _banner_at
		var pop := 1.0
		if age < 0.35:
			var u := age / 0.35
			pop = 1.0 + 0.10 * (1.0 - u) * cos(u * 12.0)
		draw_set_transform(size * 0.5 * (1.0 - pop), 0.0, Vector2(pop, pop))
		var r := Rect2(12, 8, size.x - 24, size.y - 16)
		draw_rect(r, Color(0.05, 0.04, 0.015, 1.0))
		Gfx.draw_panel(self, r, Color(col, 0.14), Color(col, 0.7 + 0.3 * pulse), 22.0, 3.0)
		Gfx.draw_text(self, Vector2(0, 62), "UNLOCKED", 30, Color(col, 0.85 + 0.15 * pulse),
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 6, Fonts.ui(Fonts.W_BLACK, 8))
		Gfx.draw_text(self, Vector2(0, 122), str(item["name"]), 52, Config.C_TEXT,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 9, Fonts.display(4))
		Gfx.draw_text(self, Vector2(0, 170), str(item["desc"]), 26, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 5, Fonts.ui(Fonts.W_MED))
		if _unlocked.size() > 1:
			Gfx.draw_text(self, Vector2(0, 208), "+%d more in the garrison" % (_unlocked.size() - 1),
				22, Color(col, 0.8), HORIZONTAL_ALIGNMENT_CENTER, size.x, 5, Fonts.ui(Fonts.W_BOLD))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ contracts

## Today's three, with whatever this run moved. A contract that finished mid-run
## is shown claimed, so the renown above it is accounted for.
class ContractStrip extends Control:
	var _rows: Array = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(true)

	func refresh() -> void:
		visible = true
		_rows = Meta.contracts()
		_t = 0.0
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if _t < 2.0:
			queue_redraw()

	func _draw() -> void:
		Gfx.draw_text(self, Vector2(30, 28), "TODAY'S CONTRACTS", 24, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 5, Fonts.ui(Fonts.W_BLACK, 5))
		if _rows.is_empty():
			return
		var y := 52.0
		for row in _rows:
			var done: bool = bool(row["done"])
			var accent: Color = Config.C_GOOD if done else Config.C_ROCK
			var label_font := Fonts.ui(Fonts.W_MED)
			var label := Gfx.fit_text(str(row["text"]), 25, size.x - 460.0, label_font)
			Gfx.draw_text(self, Vector2(30, y + 28), label, 25,
				Config.C_TEXT_DIM if done else Config.C_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 5,
				label_font)
			var bar := Rect2(size.x - 420, y + 12, 300, 18)
			var frac := float(row["progress"]) / maxf(float(row["target"]), 1.0)
			Gfx.draw_bar(self, bar, frac, Color(0, 0, 0, 0.5), accent, false)
			var tail := "CLAIMED  +%d" % int(row["renown"]) if done else "%d / %d" % [
				int(row["progress"]), int(row["target"])]
			Gfx.draw_text(self, Vector2(size.x - 108, y + 30), tail, 22, accent,
				HORIZONTAL_ALIGNMENT_RIGHT, 100, 5, Fonts.ui(Fonts.W_BLACK, 1))
			y += 44.0


# ------------------------------------------------------------------ stars

## Three stars that thump in one by one, like the end of a Clash match.
class StarRow extends Control:
	var earned := 0
	var _t := -1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func play(n: int) -> void:
		earned = n
		_t = 0.0
		set_process(true)
		queue_redraw()

	func _process(delta: float) -> void:
		if _t < 0.0:
			return
		var before := int(_t / 0.3)
		_t += delta
		var after := int(_t / 0.3)
		if after != before and after <= earned and after >= 1:
			Sfx.play_pitched("star", float(after - 1) * 3.0, -4.0)
		if _t > 1.6:
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		for i in range(3):
			var c := Vector2(70 + i * 130, 60)
			var lit := i < earned
			var appear := clampf((_t - float(i) * 0.3) / 0.3, 0.0, 1.0) if _t >= 0.0 else 0.0
			var s := 1.0
			if lit:
				if appear <= 0.0:
					continue
				s = lerpf(2.0, 1.0, appear) * (1.0 + 0.12 * sin(appear * PI))
			var outer := 48.0 * s
			var inner := 20.0 * s
			if lit:
				Gfx.draw_glow(self, c, outer * 1.5, Config.C_ROCK, appear, 4)
			var col: Color = Config.C_ROCK if lit else Color(0.12, 0.14, 0.2, 0.85)
			draw_colored_polygon(Gfx.star_points(c + Vector2(0, 4), outer, inner, 5), Color(0, 0, 0, 0.45))
			draw_colored_polygon(Gfx.star_points(c, outer, inner, 5), col)
			if lit:
				draw_colored_polygon(Gfx.star_points(c - Vector2(0, outer * 0.18), outer * 0.5, inner * 0.5, 5),
					Color(1, 1, 1, 0.35))
