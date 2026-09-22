extends Node
## Local-first leaderboard with optional remote sync to server/worker.js.
## Runs fully offline: scores are stored in user:// and queued; when the
## venue wifi comes back, pending entries are pushed and the remote top list pulled.

signal boards_updated

const FILE_PATH := "user://leaderboard.json"
const TOP_N := 10
const NAME_MIN := 3
const NAME_MAX := 12

var entries: Array = []          # every local run that was submitted with a name
var pending: Array = []          # ids of entries not yet accepted by the server
var remote: Dictionary = {"daily": [], "alltime": []}
var status: String = "offline"   # offline | syncing | online | error

var _http: HTTPRequest
var _queue: Array = []           # [{ "kind": "post"|"top", ... }]
var _in_flight: Dictionary = {}
var _name_re: RegEx


func _ready() -> void:
	_name_re = RegEx.new()
	_name_re.compile("^[\\p{L}\\p{N} _\\-.]+$")
	_load()
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	if remote_enabled():
		refresh_remote()
		for id in pending:
			_enqueue_post(id)


func remote_enabled() -> bool:
	return Config.LEADERBOARD_URL != ""


func today() -> String:
	return Time.get_date_string_from_system(true)


## Validate and normalise a player name. Returns "" if unusable.
func clean_name(raw: String) -> String:
	var n := raw.strip_edges()
	while n.contains("  "):
		n = n.replace("  ", " ")
	if n.length() < NAME_MIN or n.length() > NAME_MAX:
		return ""
	if _name_re.search(n) == null:
		return ""
	return n


func run_hash(name: String, score: int, waves: int, lives: int, rock: int, duration: float) -> String:
	var s := "%s|%s|%d|%d|%d|%d|%d" % [Config.RUN_SALT, name, score, waves, lives, rock, int(duration)]
	return s.sha256_text()


## Store a finished run under a name. Returns rank info for the score screen.
func submit(name: String, result: Dictionary) -> Dictionary:
	var entry := {
		"id": _gen_id(),
		"name": name,
		"score": int(result["score"]),
		"waves": int(result["waves"]),
		"lives": int(result["lives"]),
		"rock": int(result["rock"]),
		"duration": float(result["duration"]),
		"won": bool(result["won"]),
		"date": today(),
		"ts": int(Time.get_unix_time_from_system()),
	}
	entry["hash"] = run_hash(name, entry["score"], entry["waves"], entry["lives"], entry["rock"], entry["duration"])
	entries.append(entry)
	pending.append(entry["id"])
	_save()
	if remote_enabled():
		_enqueue_post(entry["id"])
	var daily := top("daily", 1000)
	var alltime := top("alltime", 1000)
	return {
		"id": entry["id"],
		"rank_daily": _rank_in(daily, entry["id"]),
		"rank_alltime": _rank_in(alltime, entry["id"]),
		"top10": _rank_in(daily, entry["id"]) <= TOP_N,
		"claim_url": Config.CLAIM_URL + entry["id"],
	}


## Merged view: remote list (if we have one) + local entries the server does not know yet.
func top(board: String = "daily", n: int = TOP_N) -> Array:
	var merged: Array = []
	var seen: Dictionary = {}
	for e in remote.get(board, []):
		merged.append(e)
		seen[e.get("id", "")] = true
	for e in entries:
		if board == "daily" and e["date"] != today():
			continue
		if seen.has(e["id"]):
			continue
		merged.append(e)
	merged.sort_custom(func(a, b): return a["score"] > b["score"] if a["score"] != b["score"] else a["ts"] < b["ts"])
	if merged.size() > n:
		merged.resize(n)
	return merged


func refresh_remote() -> void:
	if not remote_enabled():
		return
	_queue.append({"kind": "top", "board": "daily"})
	_queue.append({"kind": "top", "board": "alltime"})
	_pump()


# ------------------------------------------------------------------ internals

func _rank_in(list: Array, id: String) -> int:
	for i in range(list.size()):
		if list[i].get("id", "") == id:
			return i + 1
	return list.size() + 1


func _gen_id() -> String:
	const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var s := ""
	for i in range(8):
		s += ALPHABET[randi() % ALPHABET.length()]
	return s


func _entry_by_id(id: String) -> Dictionary:
	for e in entries:
		if e["id"] == id:
			return e
	return {}


func _enqueue_post(id: String) -> void:
	_queue.append({"kind": "post", "id": id})
	_pump()


func _pump() -> void:
	if not _in_flight.is_empty() or _queue.is_empty():
		return
	var job: Dictionary = _queue.pop_front()
	_in_flight = job
	status = "syncing"
	var err := OK
	match job["kind"]:
		"post":
			var e := _entry_by_id(job["id"])
			if e.is_empty():
				_in_flight = {}
				_pump()
				return
			var body := JSON.stringify(e)
			err = _http.request(Config.LEADERBOARD_URL + "/score",
				["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
		"top":
			err = _http.request(Config.LEADERBOARD_URL + "/top?board=" + job["board"])
	if err != OK:
		status = "error"
		_in_flight = {}
		# Leave pending as is; retry on next refresh.
		_queue.clear()


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var job := _in_flight
	_in_flight = {}
	if result != HTTPRequest.RESULT_SUCCESS:
		status = "error"
		_queue.clear()
		boards_updated.emit()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	match job.get("kind", ""):
		"post":
			# 200 accepted, 409 duplicate, 422 rejected as impossible/profane: all mean "stop retrying".
			if code == 200 or code == 409 or code == 422:
				pending.erase(job["id"])
				_save()
			status = "online" if code == 200 else "error"
		"top":
			if code == 200 and parsed is Dictionary and parsed.has("entries"):
				remote[job["board"]] = parsed["entries"]
				status = "online"
			else:
				status = "error"
	boards_updated.emit()
	_pump()


func _load() -> void:
	if not FileAccess.file_exists(FILE_PATH):
		return
	var f := FileAccess.open(FILE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		entries = parsed.get("entries", [])
		pending = parsed.get("pending", [])
		# JSON turns ints into floats; normalise the fields we sort on.
		for e in entries:
			e["score"] = int(e["score"])
			e["ts"] = int(e["ts"])


func _save() -> void:
	var f := FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"entries": entries, "pending": pending}))
