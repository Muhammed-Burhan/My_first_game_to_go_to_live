extends SceneTree
## Dumps the QR matrix for a string as rows of 0/1, for cross-checking with a
## real decoder:  godot --headless --path . -s tests/qr_dump.gd -- "https://..."


func _init() -> void:
	var text := "https://citadel.example/claim/ABCD2345"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		text = args[0]
	var qr := QrCode.encode(text)
	if qr.is_empty():
		print("QR_EMPTY")
	else:
		print("QR_SIZE %d MASK %d VERSION %d ECL %d" % [qr["size"], qr["mask"], qr["version"], qr["ecl"]])
		for row in qr["modules"]:
			var s := ""
			for v in row:
				s += "1" if v == 1 else "0"
			print("QR_ROW " + s)
	quit()
