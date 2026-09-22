class_name UnitSheet
extends Node2D
## Art review harness:
##   godot --path . --resolution 1080x1920 -- --units=C:/tmp/units
##
## Draws every attacker and every emplacement on a flat neutral ground at a
## large, honest scale, with a silhouette pass beside each one. Unit art is
## authored at about 22px on a phone, which is exactly the size at which you
## cannot tell a good shape from a bad one. This is where you find out.
##
## The silhouette column is the important half: if two units are not different
## as solid black shapes, they will never be different in play.

const COLS := 4
const CELL := Vector2(258, 330)
const ORIGIN := Vector2(150, 260)

var dir: String = "user://units"
var _shot := false
var _t := 0.0
var _enemies: Array = []
var _towers: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--units="):
			dir = a.substr(8)
	DirAccess.make_dir_recursive_absolute(dir)
	z_index = 100
	_spawn()
	set_process(true)


## Real Enemy and Tower nodes, parked on a grid and frozen. Drawing them for
## real is the point: a mock-up of the art would not catch the art.
func _spawn() -> void:
	var order := [
		Config.EnemyType.RAIDER, Config.EnemyType.RUNNER, Config.EnemyType.SHIELDMAN,
		Config.EnemyType.HORSE_ARCHER, Config.EnemyType.CAVALRY, Config.EnemyType.SAPPER,
		Config.EnemyType.SHAMAN, Config.EnemyType.CATAPULT, Config.EnemyType.CART,
		Config.EnemyType.BOSS,
	]
	for i in range(order.size()):
		var e := Enemy.new()
		e.setup(order[i], null, {}, false)
		e.process_mode = Node.PROCESS_MODE_DISABLED
		e.position = _cell(i) + Vector2(0, 58)
		add_child(e)
		# After add_child: _ready re-scales for the spawn pop.
		e.scale = Vector2.ONE * _fit(order[i])
		_enemies.append([e, str(Config.ENEMIES[order[i]]["name"]), _cell(i)])
	var row := 3
	for i in range(Config.TOWER_ORDER.size()):
		var t := Tower.new()
		# setup() fills the stats table the draw code reads; without it the
		# emplacement draws against an empty dictionary.
		t.setup(Config.TOWER_ORDER[i], null, null)
		t.tier = 2
		t.stats = Boons.tower_stats(t.type, 2)
		# Nothing on this sheet should hunt for targets: there is no level.
		t.process_mode = Node.PROCESS_MODE_DISABLED
		# Idle aim points straight up, which makes a ballista read as a thin
		# cross and a naphtha siphon as a banjo. Park them where they sit when
		# there is actually something on the road.
		t._aim = 0.55
		t.position = _cell(row * COLS + i) + Vector2(0, 58)
		add_child(t)
		t.scale = Vector2.ONE * 1.5
		_towers.append([t, str(Config.TOWERS[Config.TOWER_ORDER[i]]["name"]), _cell(row * COLS + i)])


## Big units need reining in so a siege tower and a runner share a page.
func _fit(type: int) -> float:
	var r: float = Config.ENEMIES[type]["radius"]
	return clampf(60.0 / r, 0.6, 2.8)


func _cell(i: int) -> Vector2:
	return ORIGIN + Vector2(float(i % COLS) * CELL.x, float(i / COLS) * CELL.y)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _t > 1.2 and not _shot:
		_shot = true
		_snap()


func _snap() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := dir.path_join("units.png")
	print("SHEET %s %s" % [path, "ok" if img.save_png(path) == OK else "ERR"])
	get_tree().quit()


func _draw() -> void:
	# Flat mid ground: neither the dark mound nor white, so a shape is judged
	# on itself rather than on whichever background flatters it. Drawn far
	# larger than the viewport because this node does not share the UI's
	# stretch transform and the edges would otherwise show the battlefield.
	draw_rect(Rect2(-3000, -3000, 9000, 9000), Color("2b2b30"))
	Gfx.draw_text(self, Vector2(0, 74), "UNIT SHEET", 54, Color("e8e8ee"),
		HORIZONTAL_ALIGNMENT_CENTER, 1080, 6, Fonts.display(4))
	Gfx.draw_text(self, Vector2(0, 116), "attackers, then emplacements at tier 2", 26,
		Color("9a9aa6"), HORIZONTAL_ALIGNMENT_CENTER, 1080, 4, Fonts.ui(Fonts.W_MED))
	for entry in _enemies + _towers:
		var cell: Vector2 = entry[2]
		draw_rect(Rect2(cell - Vector2(118, 186), Vector2(236, 310)), Color(0, 0, 0, 0.16))
		# A ground line, so a unit is judged standing on something.
		draw_rect(Rect2(cell.x - 118, cell.y + 74, 236, 2), Color(1, 1, 1, 0.08))
		Gfx.draw_text(self, cell + Vector2(-118, 112), str(entry[1]), 22, Color("d8d8e2"),
			HORIZONTAL_ALIGNMENT_CENTER, 236, 4, Fonts.ui(Fonts.W_BOLD))
