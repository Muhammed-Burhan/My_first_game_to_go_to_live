class_name QrView
extends Control
## Draws a QR code (from QrCode.encode) on a white card with a quiet zone.

var _qr: Dictionary = {}


func set_text(text: String) -> void:
	_qr = QrCode.encode(text)
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.set_corner_radius_all(18)
	draw_style_box(style, Rect2(Vector2.ZERO, Vector2(side, side)))
	if _qr.is_empty():
		return
	var n: int = _qr["size"]
	var quiet := 4
	var cell := side / float(n + quiet * 2)
	var off := cell * quiet
	var mods: Array = _qr["modules"]
	for y in range(n):
		var row: PackedByteArray = mods[y]
		for x in range(n):
			if row[x] == 1:
				draw_rect(Rect2(off + x * cell, off + y * cell, cell + 0.5, cell + 0.5), Color("0a1633"))
