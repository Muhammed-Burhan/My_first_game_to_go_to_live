extends Node
## Player profile: best scores per mode, lifetime stats, audio preference.
## One small JSON file in user://. Booth mode still writes it (the booth wants
## "today's best" on the attract screen) but nothing here gates gameplay.

const FILE_PATH := "user://profile.json"

signal changed

var data: Dictionary = {
	"best": {"campaign": 0, "endless": 0},
	"best_wave": {"campaign": 0, "endless": 0},
	"runs": 0,
	"wins": 0,
	"kills": 0,
	"muted": false,
	"last_name": "",
	"seen_intro": false,
	# The progression layer (see meta.gd). These have to be declared here:
	# load_profile only restores keys that already exist in this dictionary, so
	# anything Meta adds afterwards would be wiped on every launch.
	"commander_auto": false,
	"renown": 0,
	"commander": "warden",
	"contracts": {"day": -1, "list": [], "day_stats": {}},
}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	if not FileAccess.file_exists(FILE_PATH):
		return
	var f := FileAccess.open(FILE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for k in data.keys():
			if parsed.has(k):
				data[k] = parsed[k]
		# JSON restores ints as floats; the UI compares and formats them.
		for group in ["best", "best_wave"]:
			var d: Dictionary = data[group]
			for k in d.keys():
				d[k] = int(d[k])
		for k in ["runs", "wins", "kills", "renown"]:
			data[k] = int(data[k])
		# JSON has no integer type, so the contract counters come back as
		# floats and would print as "12.0 / 200" in the UI.
		var c: Dictionary = data["contracts"]
		c["day"] = int(c.get("day", -1))
		for entry in c.get("list", []):
			entry["progress"] = int(entry.get("progress", 0))
		var day_stats: Dictionary = c.get("day_stats", {})
		for k in day_stats.keys():
			day_stats[k] = int(day_stats[k])


func save_profile() -> void:
	var f := FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))


func best(mode_id: String) -> int:
	return int(data["best"].get(mode_id, 0))


func best_wave(mode_id: String) -> int:
	return int(data["best_wave"].get(mode_id, 0))


func is_muted() -> bool:
	return bool(data.get("muted", false))


func set_muted(m: bool) -> void:
	data["muted"] = m
	save_profile()


func remember_name(n: String) -> void:
	data["last_name"] = n
	save_profile()


## Fold a finished run into the profile. Returns true if it beat the old best.
func record_run(result: Dictionary) -> bool:
	var mode_id: String = str(result.get("mode_id", "campaign"))
	var score: int = int(result.get("score", 0))
	var waves: int = int(result.get("waves", 0))
	data["runs"] = int(data["runs"]) + 1
	data["kills"] = int(data["kills"]) + int(result.get("kills", 0))
	if bool(result.get("won", false)):
		data["wins"] = int(data["wins"]) + 1
	var is_best := score > best(mode_id)
	if is_best:
		data["best"][mode_id] = score
	if waves > best_wave(mode_id):
		data["best_wave"][mode_id] = waves
	save_profile()
	changed.emit()
	return is_best
