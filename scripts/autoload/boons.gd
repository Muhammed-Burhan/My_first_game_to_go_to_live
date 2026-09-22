extends Node
## The roguelite layer. After every wave the player drafts one of three boons;
## each folds a few numbers into `mods`, and every system that cares reads them
## back through the helpers at the bottom of this file.
##
## Boons are the whole hook: they are what makes two runs of the same seed play
## differently, and what a player actually talks about afterwards. Keep each one
## legible in a single line of text — if it needs a paragraph, it is too clever.

signal picked(boon: Dictionary)
signal mods_changed

enum Rarity { COMMON, RARE, EPIC, CURSED }

const RARITY_NAME := {
	Rarity.COMMON: "COMMON", Rarity.RARE: "RARE",
	Rarity.EPIC: "EPIC", Rarity.CURSED: "CURSED",
}
const RARITY_COLOR := {
	Rarity.COMMON: Color("9fb0c4"), Rarity.RARE: Color("57a9e0"),
	Rarity.EPIC: Color("c07ae8"), Rarity.CURSED: Color("d63a2f"),
}
const RARITY_WEIGHT := {
	Rarity.COMMON: 100, Rarity.RARE: 44, Rarity.EPIC: 16, Rarity.CURSED: 26,
}

## Every numeric knob a boon can turn. Multipliers start at 1, adders at 0.
const DEFAULT_MODS := {
	"dmg_all": 1.0, "rate_all": 1.0, "range_all": 1.0, "splash_all": 1.0,
	"pierce_all": 0.0, "burn_all": 0.0, "burn_all_time": 0.0,
	"dmg_archer": 1.0, "dmg_guard": 1.0, "dmg_oil": 1.0,
	"dmg_naphtha": 1.0, "dmg_ballista": 1.0, "dmg_mangonel": 1.0,
	"rate_ballista": 1.0, "splash_oil": 1.0, "burn_oil": 0.0,
	"burn_naphtha_mult": 1.0, "splash_mangonel": 1.0,
	"garrison_extra": 0, "tower_hp": 1.0, "tower_taken": 1.0, "repair_cost": 1.0,
	"rock_kill": 1.0, "rock_wave": 1.0, "rock_per_wave": 0,
	"crit_chance": 0.0, "crit_mult": 2.5,
	"streak_rock": 0, "salvage": 0.0, "start_tier": 1,
	"enemy_hp": 1.0, "enemy_speed": 1.0,
	"cmd_dmg": 1.0, "cmd_rate": 1.0, "cmd_blast": 1.0,
	"barrage_every": 0,
}

var mods: Dictionary = {}
var taken: Array[String] = []      # boon ids, in the order they were drafted
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	reset()


func reset(seed_value: int = 0) -> void:
	mods = DEFAULT_MODS.duplicate(true)
	taken.clear()
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value if seed_value != 0 else randi()
	mods_changed.emit()


# ------------------------------------------------------------------ catalogue

## id, name, text, rarity, mods, and an `art` key the card uses to draw itself.
## `stack` = how many times it may be drafted in one run.
const CATALOGUE := [
	# ---- common -----------------------------------------------------------
	{"id": "keen_arrows", "name": "Keen Arrows", "text": "Archers deal +35% damage.",
		"rarity": Rarity.COMMON, "art": "arrow", "stack": 3, "mods": {"dmg_archer": 0.35}},
	{"id": "long_ropes", "name": "Long Ropes", "text": "Every emplacement gains +12% range.",
		"rarity": Rarity.COMMON, "art": "range", "stack": 3, "mods": {"range_all": 0.12}},
	{"id": "quick_hands", "name": "Quick Hands", "text": "Every emplacement fires 15% faster.",
		"rarity": Rarity.COMMON, "art": "rate", "stack": 3, "mods": {"rate_all": 0.15}},
	{"id": "wide_pots", "name": "Wide Pots", "text": "Oil pots splash 35% further.",
		"rarity": Rarity.COMMON, "art": "splash", "stack": 2, "mods": {"splash_oil": 0.35}},
	{"id": "tribute", "name": "Tribute", "text": "+25% rock from every kill.",
		"rarity": Rarity.COMMON, "art": "coin", "stack": 3, "mods": {"rock_kill": 0.25}},
	{"id": "deep_quarry", "name": "Deep Quarry", "text": "+45 rock at the start of each wave.",
		"rarity": Rarity.COMMON, "art": "coin", "stack": 3, "mods": {"rock_per_wave": 45}},
	{"id": "sharpened", "name": "Sharpened Heads", "text": "All shots gain +0.1 armour pierce.",
		"rarity": Rarity.COMMON, "art": "pierce", "stack": 3, "mods": {"pierce_all": 0.1}},
	{"id": "extra_spear", "name": "Levy", "text": "Guard posts field one more spearman.",
		"rarity": Rarity.COMMON, "art": "spear", "stack": 2, "mods": {"garrison_extra": 1}},
	{"id": "tar_pitch", "name": "Tar Pitch", "text": "Oil pots leave fire that burns for 2s.",
		"rarity": Rarity.COMMON, "art": "fire", "stack": 1, "mods": {"burn_oil": 11.0}},
	{"id": "masons", "name": "Masons", "text": "Emplacements +40% hp. Repairs cost half.",
		"rarity": Rarity.COMMON, "art": "shield", "stack": 2, "mods": {"tower_hp": 0.4, "repair_cost": -0.5}},

	# ---- rare -------------------------------------------------------------
	{"id": "naphtha_stores", "name": "Naphtha Stores", "text": "Naphtha burns twice as hot.",
		"rarity": Rarity.RARE, "art": "fire", "stack": 2, "mods": {"burn_naphtha_mult": 1.0}},
	{"id": "counterweights", "name": "Counterweights", "text": "Mangonels: +30% damage, +20% blast.",
		"rarity": Rarity.RARE, "art": "stone", "stack": 2, "mods": {"dmg_mangonel": 0.3, "splash_mangonel": 0.2}},
	{"id": "winch_drill", "name": "Winch Drill", "text": "Ballistas reload 40% faster.",
		"rarity": Rarity.RARE, "art": "rate", "stack": 2, "mods": {"rate_ballista": 0.4}},
	{"id": "war_drums", "name": "War Drums", "text": "Everything you own deals +20% damage.",
		"rarity": Rarity.RARE, "art": "drum", "stack": 3, "mods": {"dmg_all": 0.2}},
	{"id": "marksmen", "name": "Marksmen", "text": "15% of shots strike for 2.5x.",
		"rarity": Rarity.RARE, "art": "crit", "stack": 3, "mods": {"crit_chance": 0.15}},
	{"id": "iron_gate", "name": "Iron Gate", "text": "The gate holds one more breach.",
		"rarity": Rarity.RARE, "art": "gate", "stack": 2, "mods": {}, "lives": 1},
	{"id": "signal_fires", "name": "Signal Fires", "text": "Each kill in a streak pays its own number in rock.",
		"rarity": Rarity.RARE, "art": "coin", "stack": 1, "mods": {"streak_rock": 1}},
	{"id": "salvage", "name": "Salvage", "text": "Wrecked emplacements refund 80% of their cost.",
		"rarity": Rarity.RARE, "art": "shield", "stack": 1, "mods": {"salvage": 0.8}},
	{"id": "bulwark", "name": "Bulwark", "text": "Emplacements take 45% less damage.",
		"rarity": Rarity.RARE, "art": "shield", "stack": 2, "mods": {"tower_taken": -0.45}},

	# ---- epic -------------------------------------------------------------
	{"id": "greek_fire", "name": "Greek Fire", "text": "Every shot you fire sets its target alight.",
		"rarity": Rarity.EPIC, "art": "fire", "stack": 1, "mods": {"burn_all": 13.0, "burn_all_time": 2.5}},
	{"id": "barrage", "name": "Barrage", "text": "Every 6th shot from anything becomes a mangonel stone.",
		"rarity": Rarity.EPIC, "art": "stone", "stack": 1, "mods": {"barrage_every": 6}},
	{"id": "kings_purse", "name": "King's Purse", "text": "Double the rock paid for holding a wave.",
		"rarity": Rarity.EPIC, "art": "coin", "stack": 2, "mods": {"rock_wave": 1.0}},
	{"id": "zagros_wind", "name": "Zagros Wind", "text": "+25% range and +12% fire rate, everything.",
		"rarity": Rarity.EPIC, "art": "range", "stack": 2, "mods": {"range_all": 0.25, "rate_all": 0.12}},
	{"id": "veterans", "name": "Veterans", "text": "Newly built emplacements start at tier 2.",
		"rarity": Rarity.EPIC, "art": "star", "stack": 1, "mods": {"start_tier": 1}},
	{"id": "hand_cannon", "name": "Hand Cannon", "text": "Your own fire: +60% damage, +25% blast.",
		"rarity": Rarity.EPIC, "art": "crit", "stack": 2, "mods": {"cmd_dmg": 0.6, "cmd_blast": 0.25}},

	# ---- cursed: real upside, real cost -----------------------------------
	{"id": "blood_price", "name": "Blood Price", "text": "+50% damage. The gate holds one breach fewer.",
		"rarity": Rarity.CURSED, "art": "crit", "stack": 1, "mods": {"dmg_all": 0.5}, "lives": -1},
	{"id": "scorched_earth", "name": "Scorched Earth", "text": "+70% blast radius. Your emplacements take +30% damage.",
		"rarity": Rarity.CURSED, "art": "fire", "stack": 1, "mods": {"splash_all": 0.7, "tower_taken": 0.3}},
	{"id": "greed", "name": "Greed", "text": "+90% rock from kills. They come 15% faster.",
		"rarity": Rarity.CURSED, "art": "coin", "stack": 1, "mods": {"rock_kill": 0.9, "enemy_speed": 0.15}},
	{"id": "thin_walls", "name": "Thin Walls", "text": "+40% fire rate. Emplacements lose 40% of their hp.",
		"rarity": Rarity.CURSED, "art": "rate", "stack": 1, "mods": {"rate_all": 0.4, "tower_hp": -0.4}},
	{"id": "no_quarter", "name": "No Quarter", "text": "+45% damage. Every attacker has +25% health.",
		"rarity": Rarity.CURSED, "art": "drum", "stack": 1, "mods": {"dmg_all": 0.45, "enemy_hp": 0.25}},
]


func by_id(id: String) -> Dictionary:
	for b in CATALOGUE:
		if b["id"] == id:
			return b
	return {}


func count_taken(id: String) -> int:
	var n := 0
	for t in taken:
		if t == id:
			n += 1
	return n


## Three distinct boons the player has not maxed out, weighted by rarity.
func offer(count: int = 3) -> Array:
	var pool: Array = []
	for b in CATALOGUE:
		if count_taken(b["id"]) >= int(b.get("stack", 1)):
			continue
		pool.append(b)
	var out: Array = []
	for i in range(count):
		if pool.is_empty():
			break
		var total := 0
		for b in pool:
			total += int(RARITY_WEIGHT[b["rarity"]])
		var roll := _rng.randi_range(0, maxi(total - 1, 0))
		var acc := 0
		var chosen: Dictionary = pool[0]
		for b in pool:
			acc += int(RARITY_WEIGHT[b["rarity"]])
			if roll < acc:
				chosen = b
				break
		out.append(chosen)
		pool.erase(chosen)
	return out


func take(boon: Dictionary) -> void:
	taken.append(str(boon["id"]))
	var m: Dictionary = boon.get("mods", {})
	for k in m.keys():
		if not mods.has(k):
			continue
		# Multiplier keys default to 1 and accumulate additively on top of it;
		# adder keys default to 0. Both are just "+= value".
		mods[k] = mods[k] + m[k]
	var lives: int = int(boon.get("lives", 0))
	if lives != 0:
		Game.grant_lives(lives)
	picked.emit(boon)
	mods_changed.emit()


# ------------------------------------------------------------------ readers

func m(key: String) -> float:
	return float(mods.get(key, DEFAULT_MODS.get(key, 0.0)))


func i(key: String) -> int:
	return int(mods.get(key, DEFAULT_MODS.get(key, 0)))


## Config.tower_stats with the run's boons folded in. Towers call this, not Config.
func tower_stats(type: int, tier: int) -> Dictionary:
	var d := Config.tower_stats(type, tier)
	var id := str(Config.TOWERS[type]["id"])
	d["damage"] = float(d["damage"]) * m("dmg_all") * m("dmg_" + id)
	d["rate"] = float(d["rate"]) * m("rate_all")
	if type == Config.TowerType.BALLISTA:
		d["rate"] = float(d["rate"]) * m("rate_ballista")
	d["range"] = float(d["range"]) * m("range_all")
	d["pierce"] = minf(0.98, float(d["pierce"]) + m("pierce_all"))
	if float(d["splash"]) > 0.0:
		var sp := float(d["splash"]) * m("splash_all")
		if type == Config.TowerType.OIL:
			sp *= m("splash_oil")
		elif type == Config.TowerType.MANGONEL:
			sp *= m("splash_mangonel")
		d["splash"] = sp
	# Burn: the tower's own, boosted, plus anything Greek Fire adds on top.
	var burn: Array = []
	if d.has("burn"):
		burn = [float(d["burn"][0]) * (1.0 + m("burn_naphtha_mult") - 1.0), float(d["burn"][1])]
	if type == Config.TowerType.OIL and m("burn_oil") > 0.0:
		burn = [m("burn_oil"), 2.0]
	if m("burn_all") > 0.0:
		var dps := m("burn_all")
		var secs := m("burn_all_time")
		if burn.size() == 2:
			burn = [maxf(float(burn[0]), dps), maxf(float(burn[1]), secs)]
		else:
			burn = [dps, secs]
	if burn.size() == 2:
		d["burn"] = burn
	return d


func tower_hp(type: int, tier: int) -> float:
	return Config.tower_hp(type, tier) * maxf(0.2, m("tower_hp"))


func tower_damage_taken(amount: float) -> float:
	return amount * maxf(0.05, m("tower_taken"))


func repair_cost(base: int) -> int:
	return maxi(5, int(round(float(base) * maxf(0.1, m("repair_cost")))))


func garrison_count(base: int) -> int:
	return base + i("garrison_extra")


func start_tier() -> int:
	return clampi(i("start_tier"), 1, Config.MAX_TIER)


func kill_reward(base: int) -> int:
	return int(round(float(base) * m("rock_kill")))


func wave_bonus(base: int) -> int:
	return int(round(float(base) * m("rock_wave")))


func wave_income() -> int:
	return i("rock_per_wave")


func streak_rock(streak: int) -> int:
	return streak * i("streak_rock")


func salvage_fraction() -> float:
	return m("salvage")


func enemy_hp_mult() -> float:
	return m("enemy_hp")


func enemy_speed_mult() -> float:
	return m("enemy_speed")


## Rolls a strike. Returns [damage, was_critical].
func roll_damage(base: float) -> Array:
	if m("crit_chance") > 0.0 and randf() < m("crit_chance"):
		return [base * m("crit_mult"), true]
	return [base, false]


## Every Nth shot from anything becomes a mangonel stone, or 0 if not drafted.
func barrage_every() -> int:
	return i("barrage_every")


## Short ids for the share card's emoji line, in draft order.
func emoji_line() -> String:
	const ART_EMOJI := {
		"arrow": "🏹", "range": "🎯", "rate": "⚡", "splash": "💥", "coin": "🪙",
		"pierce": "🗡️", "spear": "🛡️", "fire": "🔥", "shield": "🧱", "stone": "🪨",
		"drum": "🥁", "crit": "⚔️", "gate": "🚪", "star": "⭐",
	}
	var out := ""
	for id in taken:
		var b := by_id(id)
		if b.is_empty():
			continue
		out += str(ART_EMOJI.get(str(b.get("art", "star")), "⭐"))
	return out
