class_name LeaderboardPanel
extends Control
## Top-10 list for the title screen and booth attract loop. Tap the header to
## switch between today's board and all-time. Top three get medals.

var board: String = "daily"
var highlight_id: String = ""
var _rows: Array = []
var _pulse := 0.0
var _box: StyleBoxTexture

const MEDALS := [Color("f2c14e"), Color("cfd6de"), Color("cd8e4a")]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_box = Gfx.gradient_box(Color(0.075, 0.105, 0.19, 0.94), Color(0.02, 0.035, 0.08, 0.96), Config.C_UI_LINE, 3.0, 30.0)
	Leaderboard.boards_updated.connect(refresh)
	refresh()


func refresh() -> void:
	_rows = Leaderboard.top(board, Leaderboard.TOP_N)
	queue_redraw()


func toggle_board() -> void:
	board = "alltime" if board == "daily" else "daily"
	refresh()


func _process(delta: float) -> void:
	if highlight_id != "":
		_pulse += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		Sfx.play("click")
		toggle_board()


func _draw() -> void:
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var title := "TODAY'S DEFENDERS" if board == "daily" else "ALL-TIME DEFENDERS"
	Gfx.draw_text(self, Vector2(0, 58), title, 38, Config.C_ROCK, HORIZONTAL_ALIGNMENT_CENTER, size.x, 6)
	Gfx.draw_text(self, Vector2(0, 92), "tap to switch", 22, Config.C_TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x, 4)
	draw_line(Vector2(40, 110), Vector2(size.x - 40, 110), Color(Config.C_UI_LINE, 0.45), 2.0)
	var y := 158.0
	var row_h := (size.y - 180.0) / float(Leaderboard.TOP_N)
	var fs := int(clampf(row_h * 0.6, 22.0, 40.0))
	if _rows.is_empty():
		Gfx.draw_text(self, Vector2(0, y + 40), "No defenders yet. Be the first.", 32, Config.C_TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 5)
		return
	for i in range(_rows.size()):
		var e: Dictionary = _rows[i]
		var col := Config.C_TEXT
		var is_me: bool = highlight_id != "" and e.get("id", "") == highlight_id
		if is_me:
			var a := 0.22 + 0.14 * sin(_pulse * 5.0)
			Gfx.draw_bar(self, Rect2(26, y - fs - 4, size.x - 52, fs + 14), 1.0, Color(0, 0, 0, 0), Color(Config.C_ROCK, a), false)
			col = Config.C_ROCK
		elif i < 3:
			col = MEDALS[i]
		# Rank: a medal disc for the top three, a plain number after.
		if i < 3:
			var mc := Vector2(60, y - fs * 0.34)
			draw_circle(mc + Vector2(0, 2), 19, Color(0, 0, 0, 0.4))
			draw_circle(mc, 17, MEDALS[i].darkened(0.32))
			draw_circle(mc, 13, MEDALS[i])
			Gfx.draw_text(self, Vector2(mc.x - 40, mc.y + 10), str(i + 1), 24, Color("2a1d10"), HORIZONTAL_ALIGNMENT_CENTER, 80, 0)
		else:
			draw_string(font, Vector2(46, y), "%d." % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Config.C_TEXT_DIM)
		draw_string(font, Vector2(110, y), str(e.get("name", "???")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 380, fs, col)
		draw_string(font, Vector2(size.x - 290, y), str(int(e.get("score", 0))), HORIZONTAL_ALIGNMENT_RIGHT, 250, fs, col)
		y += row_h
