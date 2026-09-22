# Citadel Defense

A seeded roguelite siege on the Erbil Citadel. Mongol columns climb the mound;
you hold the gate with six kinds of emplacement, a garrison of spearmen, and a
repeater you aim yourself. Every wave you clear, you draft a boon. Built for the
HITEX booth and for phones.

Design spec: `# Citadel Defense — Game Design & B.txt` (it still says Phaser; the
engine decision is **Godot 4.6, GDScript, 2D, portrait, mobile-first**).

## The loop

1. Pick a mode. **Daily Siege** is the one that matters: one seed a day, so the
   mound, the wave order and the army are identical for everyone playing today.
2. Build and upgrade on the plinths. Twenty of them, two rings deep along the road.
3. During a wave, **hold anywhere to fire** the gatehouse repeater. It overheats
   in about four seconds, so the rhythm is burst, cool, burst.
4. Hold the wave, **draft one of three boons**. Commons stack, epics change how a
   run plays, cursed ones pay double and cost you something real.
5. Die. Get a share card with your depth, your build as icons and today's number.

## Modes

| Mode | Map | Waves | Lives | Rock |
| --- | --- | --- | --- | --- |
| **Campaign** | The authored road | 10, scripted | 3 | 180 |
| **Daily Siege** | Generated from today's seed | Endless depth | 4 | 220 |
| **Free Siege** | Generated from a random seed | Endless depth | 4 | 220 |

The Daily rolls over at midnight UTC (`Config.daily_seed`), so the whole board
turns over together. Campaign drafts a boon every other wave; the seeded modes
draft after every wave for the first ten, then every other.

## Defences

| | Cost | Role |
| --- | --- | --- |
| Archers | 50 | Cheap, fast, useless against plate |
| Guard Post | 90 | Fields spearmen who stand in the road and stop the column |
| Oil Pot | 75 | Splash, best on the hairpins |
| Naphtha | 115 | Sticky fire; burn ignores armour entirely |
| Ballista | 130 | Slow, punches through plate |
| Mangonel | 210 | Bombards the whole mound, blind inside 190px |

Emplacements have hit points now. Manjaniq crews shell them, horse archers
pepper them and sappers detonate on death. A wrecked one leaves rubble and frees
its plinth. Repair from the build sheet, or take Salvage and get the cost back.

## Attackers

Raider, Runner, Shieldman, Horse Archer, Keshik Rider, Sapper, Shaman, Manjaniq,
Siege Cart, Siege Tower. Horse archers and manjaniq crews shoot back at your
emplacements; shamans heal the column, so they are the real target; sappers blow
up whatever you built too close together.

## Run

Open the folder in Godot 4.6+ and press Play, or from a shell:

```
godot --path .
godot --path . -- --booth                              # attract loop, auto-restart after idle
godot --path . -- --daily                              # boot into today's siege
godot --headless --path . -- --sim --strategy=mixed    # balance bot, prints SIM_RESULT json
godot --path . --resolution 720x1280 -- --shot=C:/tmp/shots   # screenshot tour, prints FPS
```

After adding a script with a new `class_name`, run `godot --headless --path . --import`
once, or the main scene silently fails to load against a stale class cache.

Desktop: `Space` starts the wave, `F` toggles 2x, `Esc` pauses. Web builds accept
`?mode=booth`, `?game=daily` and `?game=free`.

## Layout

```
scripts/autoload/
  config.gd        ALL tunable numbers: modes, seeds, towers, enemies, waves, economy, palette
  boons.gd         the roguelite layer: catalogue, draft weighting, and every run modifier
  save_data.gd     profile: best score and best wave per mode, mute, last name
  game_state.gd    run state: mode, seed, rock, lives, wave, streak, repairs
  sfx.gd           procedural sound, synthesized in steps so the loader can drive it
  leaderboard.gd   local-first board, syncs to server/ when LEADERBOARD_URL is set
scripts/game/
  level.gd         seeded map generation, slots, wave flow, tap and drag routing
  commander.gd     the repeater you aim; heat, overheat, bursting tracers
  tower.gd         six emplacements, hit points, garrison, repair, wrecking
  defender.gd      guard-post spearmen: block the column and trade blows
  enemy.gd         ten attackers, plus burn, auras, tower fire and death blasts
  background.gd    sky, ridgelines, eroded terraces, citadel wall, torch lights
  atmosphere.gd    clouds, terrace mist, embers, dust
  post_fx.gd       vignette, impact flash, last-life pulse, baked CRT grade
  gate.gd / slot.gd / projectile.gd / fx.gd
scripts/ui/
  loading_screen.gd  boot screen; the bar drives the real synthesis work
  draft_screen.gd    one of three boons, and the icon set the share card reuses
  share_card.gd      the portrait card people screenshot, plus the emoji line
  title_screen.gd    wordmark, Daily hero card, Campaign and Free beneath
  hud.gd             top bar, wave progress, heat meter, streak, wave banner
  build_menu.gd      bottom sheet: six build cards, or stats plus upgrade/repair/sell
  pause_menu.gd, score_screen.gd, leaderboard_panel.gd, qr_view.gd, ui_theme.gd
scripts/util/
  gfx.gd           lights, glows, shadows, bars, grain, baked gradient styleboxes
  chiptune.gd      the NES-voiced music sequencer (two pulses, triangle, noise)
  qr_code.gd, sim_player.gd, shot_runner.gd
```

All art and sound is procedural — the build has zero asset dependencies.

### Notes for whoever touches this next

- `Gfx.gradient_box` rasterises an image. Bake styleboxes in `_ready`, never in `_draw`.
- Towers read their numbers through `Boons.tower_stats`, not `Config.tower_stats`.
  Config is the base table; Boons folds the run's drafts in.
- The battlefield canvas is graded by one `CanvasModulate` and lit back by real
  `PointLight2D`s. Keep the light count bounded — elites use a drawn aura rather
  than a light because endless can field a dozen at once.
- The CRT grade is one baked 60px tile blitted once. It was 380 `draw_rect` calls
  a frame before that, which cost about 15fps.
- `Defender._strike` caches the victim's position before swinging: a killing blow
  clears `target` out from under it.

## Balance

Tune with the sim, then on strangers. Current state, campaign, bots only (they
never fire the commander, so a human has headroom on top):

| Strategy | Result |
| --- | --- |
| `archers` (mono-archer) | falls on wave 6, on armour |
| `naive` (archers, one guard post, a late ballista) | falls on wave 9 |
| `mixed` (uses the whole kit) | wins with 3 lives |
| `greedy` (buys the most expensive thing affordable) | wins with 3 lives |

The knobs: `Config.campaign_scale` (per-wave stat ramp), `Config.WAVES`
(composition), `Config.endless_scale`, and the boon numbers in `Boons.CATALOGUE`.

## Booth / leaderboard setup

1. `cd server && npx wrangler kv namespace create BOARD`, paste the id into `wrangler.toml`.
2. `npx wrangler deploy`. Copy the URL.
3. Set `Config.LEADERBOARD_URL` to that URL and `Config.CLAIM_URL` to `<url>/claim/`.
4. Fill `BAD_WORDS` in `worker.js` (Kurdish, Arabic, English) before the event.
5. Offline is fine: scores queue in `user://leaderboard.json` and sync when wifi returns.

## Export

Install Android and Web export templates (Editor > Manage Export Templates), then:
- Android: portrait, min SDK 24.
- Web: single-threaded export for iOS Safari.

## Known TODOs

- Kurdish name (gate signage, domain, store listing).
- The server has no notion of the daily seed yet: `server/worker.js` still takes a
  plain score. For a real Daily board it should record and validate `seed` and
  reject scores whose seed is not today's.
- Unit outlines. Units read well now at `Config.UNIT_SCALE`, but a true dark
  outline pass would make them pop the way NES sprites do. It needs the body
  draws routed through a target `CanvasItem` so a black-modulated child can
  redraw them; it was left out because a per-unit extra draw pass costs frames.
- Recorded SFX. The synthesized set is a placeholder that already hits the right
  beats; `Chiptune` covers the music.
- Perf: about 55fps at 720x1280 on a desktop with a boss wave on screen. Worth
  profiling on a real phone before the event.
