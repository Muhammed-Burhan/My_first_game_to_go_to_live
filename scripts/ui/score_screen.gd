class_name ScoreScreen
extends Control
## End-of-run screen: stars, result, score breakdown, name entry, rank, QR claim
## code, play again. In booth mode it restarts automatically after idling.

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
var _name_edit: LineEdit
var _submit_btn: Button
var _rank_label: Label
var _stats: Label
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
	dim.color = Color(0.02, 0.04, 0.09, 0.74)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = Panel.new()
	_panel.position = Vector2(55, 150)
	_panel.size = Vector2(970, 1630)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_stars = StarRow.new()
	_stars.position = Vector2(340, 176)
	_stars.size = Vector2(400, 130)
	add_child(_stars)

	_headline = _label("THE GATE HELD", 82, 300, Config.C_ROCK)
	_best_badge = _label("NEW BEST", 34, 392, Config.C_GOOD)
	_sub = _label("", 34, 436, Config.C_TEXT)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.size.y = 90
	_total = _label("0", 126, 520, Config.C_TEXT)
	_breakdown = _label("", 32, 672, Config.C_TEXT_DIM)
	_breakdown.size.y = 200

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name (3-12)"
	_name_edit.max_length = Leaderboard.NAME_MAX
	_name_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_edit.position = Vector2(120, 880)
	_name_edit.size = Vector2(540, 104)
	_name_edit.text_submitted.connect(func(_t): _on_submit())
	add_child(_name_edit)

	_submit_btn = Button.new()
	_submit_btn.text = "SUBMIT"
	_submit_btn.position = Vector2(688, 880)
	_submit_btn.size = Vector2(272, 104)
	_submit_btn.pressed.connect(_on_submit)
	add_child(_submit_btn)
	UiTheme.make_primary(_submit_btn)
	UiTheme.add_press_feel(_submit_btn)

	_rank_label = _label("", 42, 1006, Config.C_ROCK)
	_stats = _label("", 30, 1068, Config.C_TEXT_DIM)
	_stats.size.y = 130

	_qr = QrView.new()
	_qr.position = Vector2(340, 1076)
	_qr.size = Vector2(400, 400)
	_qr.visible = false
	add_child(_qr)
	_qr_hint = _label("Scan to claim your printed tower", 32, 1486, Config.C_TEXT)
	_qr_hint.visible = false

	_board = LeaderboardPanel.new()
	_board.position = Vector2(110, 1070)
	_board.size = Vector2(860, 460)
	_board.visible = false
	add_child(_board)

	_again_btn = Button.new()
	_again_btn.text = "DEFEND AGAIN"
	_again_btn.position = Vector2(110, 1580)
	_again_btn.size = Vector2(420, 118)
	_again_btn.pressed.connect(func():
		Sfx.play("click")
		play_again.emit())
	add_child(_again_btn)
	UiTheme.make_primary(_again_btn)
	UiTheme.add_press_feel(_again_btn)

	_menu_btn = Button.new()
	_menu_btn.text = "MENU"
	_menu_btn.position = Vector2(810, 1580)
	_menu_btn.size = Vector2(160, 118)
	_menu_btn.add_theme_font_size_override("font_size", 32)
	_menu_btn.pressed.connect(func():
		Sfx.play("back")
		back_to_title.emit())
	add_child(_menu_btn)
	UiTheme.add_press_feel(_menu_btn)

	_share_btn = Button.new()
	_share_btn.text = "SHARE"
	_share_btn.position = Vector2(548, 1580)
	_share_btn.size = Vector2(244, 118)
	_share_btn.pressed.connect(func():
		Sfx.play("click")
		share_requested.emit())
	add_child(_share_btn)
	UiTheme.add_press_feel(_share_btn)

	_idle_label = _label("", 28, 1716, Config.C_TEXT_DIM)


func _label(text: String, size: int, y: float, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.position = Vector2(80, y)
	l.size = Vector2(920, size + 30)
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
		_sub.text = "You held %d waves  ·  %s tier  ·  %d kills" % [
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
	if endless:
		_breakdown.text = "Waves held  %d  ×1000  =  %d\nKills  %d  ×12  =  %d\nRock earned  %d\nBest streak  x%d" % [
			result["waves"], b["waves_bonus"], result["kills"], b["kill_bonus"],
			b["rock"], result.get("best_combo", 0)]
	else:
		_breakdown.text = "Rock earned  %d\nLives kept  %d  ×500  =  %d\nWaves cleared  %d  ×250  =  %d\nSpeed bonus  %d" % [
			b["rock"], result["lives"], b["lives_bonus"], result["waves"], b["waves_bonus"], b["speed_bonus"]]
	_total.text = "0"
	_name_edit.text = str(Save.data.get("last_name", ""))
	_name_edit.editable = true
	_name_edit.visible = true
	_submit_btn.visible = true
	_rank_label.text = ""
	_qr.visible = false
	_qr_hint.visible = false
	_board.visible = false
	_stats.visible = true
	var mins := int(float(result["duration"])) / 60
	var secs := int(float(result["duration"])) % 60
	var tag := str(Config.MODES[int(result.get("mode", Config.Mode.CAMPAIGN))]["name"])
	var mode_id := str(result.get("mode_id", "campaign"))
	if mode_id == "daily":
		tag += " #%d" % int(result.get("daily", 0))
	elif mode_id == "free":
		tag += "  seed %d" % int(result.get("seed", 0))
	_stats.text = "%s
KILLS %d     BEST STREAK x%d     TIME %d:%02d" % [
		tag, result["kills"], result.get("best_combo", 0), mins, secs]
	_idle_label.text = ""
	_panel.scale = Vector2(0.9, 0.9)
	_panel.pivot_offset = _panel.size / 2
	var tw := create_tween()
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Count the score up, then drop the stars in one at a time.
	var ct := create_tween()
	ct.tween_method(func(v): _total.text = str(int(v)), 0.0, float(result["score"]), 1.1).set_ease(Tween.EASE_OUT)
	_stars.play(Config.stars_for(result))


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
	if info["top10"]:
		_qr.set_text(info["claim_url"])
		_qr.visible = true
		_qr_hint.visible = true
		_stats.visible = false
		_qr_hint.text = "Top 10!  Scan to claim your printed tower"
	else:
		_board.highlight_id = info["id"]
		_board.board = "daily"
		_board.refresh()
		_board.visible = true
		_stats.visible = false


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
			var c := Vector2(70 + i * 130, 66)
			var lit := i < earned
			var appear := clampf((_t - float(i) * 0.3) / 0.3, 0.0, 1.0) if _t >= 0.0 else 0.0
			var s := 1.0
			if lit:
				if appear <= 0.0:
					continue
				s = lerpf(2.0, 1.0, appear) * (1.0 + 0.12 * sin(appear * PI))
			var outer := 52.0 * s
			var inner := 22.0 * s
			if lit:
				Gfx.draw_glow(self, c, outer * 1.5, Config.C_ROCK, appear, 4)
			var col: Color = Config.C_ROCK if lit else Color(0.12, 0.14, 0.2, 0.85)
			draw_colored_polygon(Gfx.star_points(c + Vector2(0, 4), outer, inner, 5), Color(0, 0, 0, 0.45))
			draw_colored_polygon(Gfx.star_points(c, outer, inner, 5), col)
			if lit:
				draw_colored_polygon(Gfx.star_points(c - Vector2(0, outer * 0.18), outer * 0.5, inner * 0.5, 5),
					Color(1, 1, 1, 0.35))
