extends Node
## Static game data: modes, towers, enemies, waves, economy, palette.
## Everything tunable lives here. Balance by editing numbers, not code.

# ---------------------------------------------------------------- modes
enum Mode { CAMPAIGN, DAILY, FREE }

const MODES := {
	Mode.CAMPAIGN: {
		"id": "campaign", "name": "CAMPAIGN", "tagline": "Ten Mongol waves on the old road.",
		"sub": "10 WAVES", "lives": 3, "rock": 180, "endless": false, "seeded": false,
	},
	Mode.DAILY: {
		"id": "daily", "name": "DAILY SIEGE", "tagline": "One siege a day. The same one for everyone.",
		"sub": "TODAY ONLY", "lives": 4, "rock": 220, "endless": true, "seeded": true,
	},
	Mode.FREE: {
		"id": "free", "name": "FREE SIEGE", "tagline": "A new mound, a new army, no witnesses.",
		"sub": "PRACTICE", "lives": 4, "rock": 220, "endless": true, "seeded": true,
	},
}

## The Daily rolls over at midnight UTC so the whole board changes together.
const DAILY_EPOCH := 20250101


static func days_since_epoch() -> int:
	var now := Time.get_datetime_dict_from_system(true)
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": now["year"], "month": now["month"], "day": now["day"],
		"hour": 0, "minute": 0, "second": 0,
	})
	var base := Time.get_unix_time_from_datetime_dict({
		"year": 2025, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0,
	})
	return int(floor((unix - base) / 86400.0))


## "Daily #128" — the number people put in the caption.
static func daily_index() -> int:
	return maxi(days_since_epoch() + 1, 1)


static func daily_seed() -> int:
	return 1258000 + daily_index() * 7919


## Campaign gets a pick every other wave; the seeded modes get one after every
## wave early on, then every other once builds are deep.
static func drafts_on_wave(wave: int, mode: int = Mode.CAMPAIGN) -> bool:
	if mode == Mode.CAMPAIGN:
		return wave % 2 == 0
	if wave <= 10:
		return true
	return wave % 2 == 0


## Per-wave stat ramp for the scripted campaign.
static func campaign_scale(wave: int) -> Dictionary:
	var w := float(maxi(wave - 1, 0))
	return {
		"hp": pow(1.065, w),
		"speed": minf(1.25, 1.0 + w * 0.013),
		"reward": 1.0,
		"elite_chance": 0.0,
	}


static func wave_scale(mode: int, wave: int) -> Dictionary:
	if bool(MODES[mode]["endless"]):
		return endless_scale(wave)
	return campaign_scale(wave)


# ---------------------------------------------------------------- economy
const START_ROCK := 180
const START_LIVES := 3
const MAX_LIVES := 5            # the HUD draws up to this many shields
const WAVE_COUNT := 10
const SELL_REFUND := 0.6
const PREP_TIME_FIRST := 10.0   # seconds before wave 1 (player reads the board)
const PREP_TIME := 6.0          # seconds between waves (tap Start to skip)
const PREP_TIME_ENDLESS := 8.0  # endless gives a little more room to spend
const SPAWN_GAP := 0.42         # seconds between spawns inside a wave
const UPGRADE_COST_MULT := 1.5
const UPGRADE_DAMAGE_MULT := 1.5
const UPGRADE_RATE_MULT := 1.2   # 1.5 * 1.2 = 1.8x DPS per tier
const UPGRADE_RANGE_MULT := 1.1
const MAX_TIER := 3
## Everything that stands on the mound is drawn at this scale. The art was sized
## for 12 emplacements; at 20 the units read too small against the terraces.
const UNIT_SCALE := 1.18
const BOOTH_IDLE_RESTART := 20.0
const SPEED_BONUS_PAR := 240.0  # seconds; faster wins earn bonus
const SPEED_BONUS_PER_SEC := 3
const COMBO_WINDOW := 2.2       # seconds between kills to keep a streak alive

# ---------------------------------------------------------------- leaderboard
## Leave empty to run fully offline (local board only). Set to your Worker URL.
const LEADERBOARD_URL := ""
## Client-side salt for the run hash. Not a cryptographic secret; it just stops
## trivial curl spoofing. Must match server/worker.js.
const RUN_SALT := "erbil-1258-hold-the-gate"
const CLAIM_URL := "https://citadel.example/claim/"  # QR target; replace with real domain

# ---------------------------------------------------------------- palette
const C_SKY_TOP := Color("070d22")
const C_SKY_MID := Color("142348")
const C_SKY_BOTTOM := Color("2b4676")
const C_SKY_HAZE := Color("53608f")
const C_STAR := Color("f2e6c4")
const C_MOON := Color("f5ead0")
const C_MOUNTAIN_FAR := Color("1b2647")
const C_MOUNTAIN_NEAR := Color("141c35")
const C_PLAIN := Color("2d2c1e")
const C_PLAIN_LIGHT := Color("3d3a27")
const C_SAND := Color("c9a063")
const C_SAND_DARK := Color("9a7442")
const C_SAND_DEEP := Color("6e5230")
const C_SAND_LIGHT := Color("e3c48a")
const C_WALL := Color("d7b57a")
const C_WALL_SHADOW := Color("a17b48")
const C_WINDOW := Color("2a1d10")
const C_PATH := Color("8b6a3e")
const C_PATH_EDGE := Color("5a4226")
const C_THREAT := Color("d63a2f")
const C_THREAT_DARK := Color("8e1f18")
const C_ROCK := Color("f2c14e")
const C_WOOD := Color("7a4e2a")
const C_WOOD_DARK := Color("4a2e17")
const C_IRON := Color("6f7480")
const C_IRON_DARK := Color("3b3f48")
const C_FIRE := Color("ff9a2e")
const C_FIRE_HOT := Color("ffe08a")
const C_TORCH := Color("ffb347")
const C_UI_BG := Color(0.05, 0.08, 0.16, 0.9)
const C_UI_BG_DEEP := Color(0.02, 0.035, 0.08, 0.95)
const C_UI_LINE := Color("c9a063")
const C_TEXT := Color("f4ecd8")
const C_TEXT_DIM := Color("b9ad93")
const C_GOOD := Color("7fb069")
const C_ELITE := Color("b05ce0")

## Night grade: the battlefield canvas is multiplied by this, then torches and
## fires light it back up. Keep it above ~0.6 so shapes stay readable.
const NIGHT_TINT := Color(0.72, 0.76, 0.94, 1.0)

# ---------------------------------------------------------------- towers
enum TowerType { ARCHER, GUARD, OIL, NAPHTHA, BALLISTA, MANGONEL }

## Order the build sheet shows them in: cheapest and most familiar first.
const TOWER_ORDER := [
	TowerType.ARCHER, TowerType.GUARD, TowerType.OIL,
	TowerType.NAPHTHA, TowerType.BALLISTA, TowerType.MANGONEL,
]

## hp        = how much punishment the emplacement itself takes before it is wrecked.
## min_range = dead zone; siege engines cannot depress far enough to hit their own feet.
## burn      = [damage per second, seconds] left on anything the shot touches.
## garrison  = {count, hp, damage, rate, respawn, reach} for a post that fields real men.
const TOWERS := {
	TowerType.ARCHER: {
		"id": "archer", "name": "Archers", "cost": 50,
		"damage": 7.0, "rate": 2.4, "range": 270.0,
		"pierce": 0.0, "splash": 0.0, "projectile": "arrow", "hp": 90.0,
		"color": Color("7fb069"), "blurb": "Fast, cheap. Weak against armour.",
	},
	TowerType.GUARD: {
		"id": "guard", "name": "Guard Post", "cost": 90,
		"damage": 0.0, "rate": 0.0, "range": 165.0,
		"pierce": 0.0, "splash": 0.0, "projectile": "", "hp": 150.0,
		"garrison": {"count": 3, "hp": 80.0, "damage": 11.0, "rate": 1.2, "respawn": 7.0, "reach": 46.0},
		"color": Color("c9a063"), "blurb": "Spearmen hold the road and stop the column.",
	},
	TowerType.OIL: {
		"id": "oil", "name": "Oil Pot", "cost": 75,
		"damage": 22.0, "rate": 0.7, "range": 200.0,
		"pierce": 0.3, "splash": 95.0, "projectile": "pot", "hp": 100.0,
		"color": Color("ff9a2e"), "blurb": "Splash. Place it on the hairpins.",
	},
	TowerType.NAPHTHA: {
		"id": "naphtha", "name": "Naphtha", "cost": 115,
		"damage": 8.0, "rate": 3.2, "range": 195.0,
		"pierce": 0.55, "splash": 62.0, "projectile": "naft", "hp": 90.0,
		"burn": [14.0, 3.0],
		"color": Color("ffe08a"), "blurb": "Sticky fire. Burns armour off over time.",
	},
	TowerType.BALLISTA: {
		"id": "ballista", "name": "Ballista", "cost": 130,
		"damage": 70.0, "rate": 0.45, "range": 380.0,
		"pierce": 0.85, "splash": 0.0, "projectile": "bolt", "hp": 110.0,
		"color": Color("6f7480"), "blurb": "Slow. Punches straight through plate.",
	},
	TowerType.MANGONEL: {
		"id": "mangonel", "name": "Mangonel", "cost": 210,
		"damage": 115.0, "rate": 0.2, "range": 640.0,
		"pierce": 0.4, "splash": 165.0, "projectile": "stone", "hp": 140.0,
		"min_range": 190.0,
		"color": Color("a1724a"), "blurb": "Bombards the whole mound. Blind up close.",
	},
}


static func tower_hp(type: int, tier: int) -> float:
	return float(TOWERS[type]["hp"]) * pow(1.45, tier - 1)


static func has_garrison(type: int) -> bool:
	return TOWERS[type].has("garrison")


# ---------------------------------------------------------------- enemies
enum EnemyType { RAIDER, RUNNER, SHIELDMAN, HORSE_ARCHER, CAVALRY, SAPPER, SHAMAN, CATAPULT, CART, BOSS }

## armor  = fraction of damage blocked unless the tower's pierce covers it.
##          effective = damage * (1 - max(0, armor - pierce))
## cost   = budget weight used by the endless wave generator.
## attack = {range, damage, rate, lob} for attackers that shoot back at emplacements.
## aura   = {radius, heal} for a shaman keeping the column on its feet.
## blast  = {radius, damage} detonated on death, against towers only.
const ENEMIES := {
	EnemyType.RAIDER: {
		"id": "raider", "name": "Raider", "hp": 30.0, "speed": 190.0,
		"armor": 0.0, "reward": 8, "lives": 1, "radius": 22.0, "cost": 1.0,
	},
	EnemyType.RUNNER: {
		"id": "runner", "name": "Runner", "hp": 16.0, "speed": 330.0,
		"armor": 0.0, "reward": 6, "lives": 1, "radius": 18.0, "cost": 0.9,
	},
	EnemyType.SHIELDMAN: {
		"id": "shieldman", "name": "Shieldman", "hp": 150.0, "speed": 120.0,
		"armor": 0.8, "reward": 25, "lives": 1, "radius": 28.0, "cost": 3.2,
	},
	EnemyType.HORSE_ARCHER: {
		"id": "horse_archer", "name": "Horse Archer", "hp": 52.0, "speed": 265.0,
		"armor": 0.1, "reward": 14, "lives": 1, "radius": 28.0, "cost": 2.0,
		"attack": {"range": 235.0, "damage": 7.0, "rate": 0.85, "lob": false},
	},
	EnemyType.CAVALRY: {
		"id": "cavalry", "name": "Keshik Rider", "hp": 190.0, "speed": 245.0,
		"armor": 0.5, "reward": 36, "lives": 2, "radius": 32.0, "cost": 4.6,
	},
	EnemyType.SAPPER: {
		"id": "sapper", "name": "Sapper", "hp": 58.0, "speed": 205.0,
		"armor": 0.2, "reward": 18, "lives": 1, "radius": 22.0, "cost": 1.9,
		"blast": {"radius": 155.0, "damage": 42.0},
	},
	EnemyType.SHAMAN: {
		"id": "shaman", "name": "Shaman", "hp": 130.0, "speed": 145.0,
		"armor": 0.2, "reward": 42, "lives": 1, "radius": 26.0, "cost": 3.6,
		"aura": {"radius": 210.0, "heal": 11.0},
	},
	EnemyType.CATAPULT: {
		"id": "catapult", "name": "Manjaniq", "hp": 380.0, "speed": 85.0,
		"armor": 0.55, "reward": 75, "lives": 2, "radius": 42.0, "cost": 7.6,
		"attack": {"range": 430.0, "damage": 36.0, "rate": 0.22, "lob": true},
	},
	EnemyType.CART: {
		"id": "cart", "name": "Siege Cart", "hp": 420.0, "speed": 95.0,
		"armor": 0.5, "reward": 60, "lives": 2, "radius": 40.0, "cost": 8.0,
	},
	EnemyType.BOSS: {
		"id": "boss", "name": "Siege Tower", "hp": 1300.0, "speed": 70.0,
		"armor": 0.8, "reward": 200, "lives": 99, "radius": 58.0, "cost": 26.0,
		"spawn_every": 3.5,
		"attack": {"range": 400.0, "damage": 30.0, "rate": 0.35, "lob": false},
	},
}


## Endless "elite" roll: a gold-crowned veteran worth far more rock.
const ELITE := {"hp": 2.4, "speed": 1.12, "reward": 2.6, "armor_bonus": 0.1}

# ---------------------------------------------------------------- waves
## Each wave is a list of [EnemyType, count]. Groups are interleaved on spawn.
const WAVES := [
	[[EnemyType.RAIDER, 7]],
	[[EnemyType.RAIDER, 13]],
	[[EnemyType.RAIDER, 10], [EnemyType.RUNNER, 7]],
	[[EnemyType.RAIDER, 12], [EnemyType.HORSE_ARCHER, 4]],
	[[EnemyType.SHIELDMAN, 3], [EnemyType.RAIDER, 12]],
	[[EnemyType.CAVALRY, 4], [EnemyType.RUNNER, 13], [EnemyType.RAIDER, 12]],
	[[EnemyType.SAPPER, 7], [EnemyType.SHIELDMAN, 6], [EnemyType.RAIDER, 13]],
	[[EnemyType.CATAPULT, 2], [EnemyType.SHIELDMAN, 7], [EnemyType.RUNNER, 15], [EnemyType.RAIDER, 15]],
	[[EnemyType.CART, 2], [EnemyType.SHAMAN, 2], [EnemyType.CAVALRY, 7], [EnemyType.SHIELDMAN, 7]],
	[[EnemyType.BOSS, 1], [EnemyType.CATAPULT, 1], [EnemyType.SHAMAN, 2], [EnemyType.CAVALRY, 6], [EnemyType.RAIDER, 12]],
]

# ---------------------------------------------------------------- endless
## Endless keeps generating waves from a growing budget. Every fifth wave is a
## siege-tower wave; every tenth leans on raw numbers.
const ENDLESS_TIERS := ["SKIRMISH", "RAID", "SIEGE", "STORM", "RUIN", "LEGEND", "MYTH"]
const ENDLESS_ELITE_FROM := 12
const ENDLESS_BOSS_EVERY := 5
const ENDLESS_FIRST_BOSS := 10   # the first ten waves mirror the campaign's ramp


static func endless_tier(wave: int) -> String:
	var i := clampi((wave - 1) / 10, 0, ENDLESS_TIERS.size() - 1)
	return ENDLESS_TIERS[i]


## Per-wave stat multipliers in endless. Campaign always uses 1.0.
static func endless_scale(wave: int) -> Dictionary:
	var w := float(maxi(wave - 1, 0))
	return {
		"hp": pow(1.072, w),
		"speed": minf(1.5, 1.0 + w * 0.009),
		"reward": minf(4.0, pow(1.04, w)),
		"elite_chance": 0.0 if wave < ENDLESS_ELITE_FROM else minf(0.42, (wave - ENDLESS_ELITE_FROM) * 0.028 + 0.06),
	}


## Endless wave composition for wave n (1-based). Deterministic, so two players
## on the same wave meet the same army.
static func endless_wave(wave: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1258 * 7919 + wave * 104729
	# Tuned to sit on the campaign's difficulty curve for the first ten waves,
	# then keep climbing. See the --sim runs in the README.
	var budget := 4.5 + wave * 2.2 + pow(float(wave), 1.6) * 0.45
	var groups: Array = []
	var boss_wave := wave >= ENDLESS_FIRST_BOSS and wave % ENDLESS_BOSS_EVERY == 0
	if boss_wave:
		var bosses := 1 + int(maxi(wave - ENDLESS_FIRST_BOSS, 0) / 20)
		groups.append([EnemyType.BOSS, bosses])
		budget -= float(ENEMIES[EnemyType.BOSS]["cost"]) * bosses
	var pool: Array = [EnemyType.RAIDER]
	if wave >= 3:
		pool.append(EnemyType.RUNNER)
	if wave >= 4:
		pool.append(EnemyType.HORSE_ARCHER)
	if wave >= 5:
		pool.append(EnemyType.SHIELDMAN)
	if wave >= 6:
		pool.append(EnemyType.CAVALRY)
	if wave >= 7:
		pool.append(EnemyType.SAPPER)
	if wave >= 8:
		pool.append(EnemyType.CART)
	if wave >= 9:
		pool.append(EnemyType.SHAMAN)
	if wave >= 11:
		pool.append(EnemyType.CATAPULT)
	var horde := wave % 10 == 0 and not boss_wave
	var counts := {}
	var guard := 0
	while budget > 0.5 and guard < 400:
		guard += 1
		var t: int = pool[rng.randi() % pool.size()]
		if horde and rng.randf() < 0.6:
			t = EnemyType.RAIDER if rng.randf() < 0.6 else EnemyType.RUNNER
		var c: float = ENEMIES[t]["cost"]
		if c > budget:
			t = EnemyType.RAIDER
			c = ENEMIES[EnemyType.RAIDER]["cost"]
		counts[t] = counts.get(t, 0) + 1
		budget -= c
	# Heaviest first so the preview reads big-to-small.
	var keys: Array = counts.keys()
	keys.sort_custom(func(a, b): return float(ENEMIES[a]["cost"]) > float(ENEMIES[b]["cost"]))
	for k in keys:
		groups.append([k, counts[k]])
	return groups


static func wave_groups(mode: int, wave: int) -> Array:
	if bool(MODES[mode]["endless"]):
		return endless_wave(maxi(wave, 1))
	if wave < 1 or wave > WAVE_COUNT:
		return []
	return WAVES[wave - 1]


static func wave_clear_bonus(wave: int) -> int:
	return 20 + wave * 5


## Cost to BUY tier 1, or to UPGRADE from (tier-1) to tier.
static func tower_cost(type: int, tier: int) -> int:
	var base: int = TOWERS[type]["cost"]
	return int(round(base * pow(UPGRADE_COST_MULT, tier - 1)))


static func tower_total_invested(type: int, tier: int) -> int:
	var total := 0
	for t in range(1, tier + 1):
		total += tower_cost(type, t)
	return total


static func tower_stats(type: int, tier: int) -> Dictionary:
	var d: Dictionary = TOWERS[type].duplicate()
	var k := tier - 1
	d["damage"] = d["damage"] * pow(UPGRADE_DAMAGE_MULT, k)
	d["rate"] = d["rate"] * pow(UPGRADE_RATE_MULT, k)
	d["range"] = d["range"] * pow(UPGRADE_RANGE_MULT, k)
	if d["splash"] > 0.0:
		d["splash"] = d["splash"] * pow(1.15, k)
	d["tier"] = tier
	return d


## Build the interleaved spawn list for a wave (1-based).
static func wave_spawn_list(wave: int, mode: int = Mode.CAMPAIGN) -> Array:
	var groups: Array = wave_groups(mode, wave)
	var out: Array = []
	var remaining: Array = []
	for g in groups:
		remaining.append(g[1])
	var any := true
	while any:
		any = false
		for i in range(groups.size()):
			if remaining[i] > 0:
				out.append(groups[i][0])
				remaining[i] -= 1
				any = true
	return out


## [[type, count], ...] for the HUD preview.
static func wave_preview(wave: int, mode: int = Mode.CAMPAIGN) -> Array:
	return wave_groups(mode, wave)


static func compute_score(rock_earned: int, lives: int, waves_cleared: int, duration: float,
		won: bool, mode: int = Mode.CAMPAIGN, kills: int = 0) -> Dictionary:
	if bool(MODES[mode]["endless"]):
		var wave_pts := waves_cleared * 1000
		var kill_pts := kills * 12
		return {
			"rock": rock_earned, "lives_bonus": lives * 250,
			"waves_bonus": wave_pts, "speed_bonus": 0, "kill_bonus": kill_pts,
			"total": rock_earned + lives * 250 + wave_pts + kill_pts,
		}
	var speed_bonus := 0
	if won:
		speed_bonus = int(max(0.0, SPEED_BONUS_PAR - duration)) * SPEED_BONUS_PER_SEC
	var total := rock_earned + lives * 500 + waves_cleared * 250 + speed_bonus
	return {
		"rock": rock_earned, "lives_bonus": lives * 500,
		"waves_bonus": waves_cleared * 250, "speed_bonus": speed_bonus, "kill_bonus": 0,
		"total": total,
	}


## Stars awarded on the result screen (0-3). Campaign: lives kept. Endless: depth.
static func stars_for(result: Dictionary) -> int:
	if bool(MODES[int(result.get("mode", Mode.CAMPAIGN))]["endless"]):
		var w: int = result.get("waves", 0)
		if w >= 25:
			return 3
		if w >= 15:
			return 2
		if w >= 8:
			return 1
		return 0
	if not bool(result.get("won", false)):
		return 0
	var lives: int = result.get("lives", 0)
	if lives >= 3:
		return 3
	if lives >= 2:
		return 2
	return 1


# ---------------------------------------------------------------- loading tips
const TIPS := [
	"Ballistas pierce armour. Shieldmen fold to them.",
	"Oil pots splash. Put them on the hairpin corners.",
	"Archers are cheap. Three early beat one late.",
	"Towers shoot whoever is closest to the gate first.",
	"Tap START to skip the prep timer and bank the clock.",
	"Selling refunds 60%. Re-shape your line between waves.",
	"One tier 3 tower outguns two tier 1s, and takes one slot.",
	"Siege carts cost two lives. Never let one through.",
	"The 2x button also doubles how fast rock comes in.",
	"Runners outrun your back line. Cover the first bend.",
	"Erbil's citadel has been lived in for six thousand years.",
	"Endless has no last wave. Only your last mistake.",
	"A guard post stops the column dead. Everything else kills it.",
	"Naphtha burns armour off. Light them up, then shoot them.",
	"The mangonel out-ranges everything and is blind up close.",
	"Sappers blow up when they die. Do not stack towers.",
	"Manjaniq crews shell your emplacements. Kill them first.",
	"Shamans heal the column. They are the real target.",
	"Wrecked towers leave the slot empty. Rebuild between waves.",
]
