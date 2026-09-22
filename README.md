# Citadel Defense

A seeded roguelite siege on the Erbil Citadel. Mongol columns climb the mound;
you hold the gate with six kinds of emplacement, a garrison of spearmen, and a
repeater you aim yourself. Every wave you clear, you draft a boon. Every run you
finish, win or lose, you earn renown and open something new. Built for the HITEX
booth and for phones.

Design spec: `# Citadel Defense — Game Design & B.txt` (it still says Phaser; the
engine decision is **Godot 4.6, GDScript, 2D, portrait, mobile-first**).

## The loop

There are two loops, and the game only works if both are running.

**Inside a run** — build, hold, draft, die:

1. Build and upgrade on the plinths. Twenty of them, two rings deep along the road.
2. During a wave, **hold anywhere to fire** the gatehouse repeater. It overheats
   in about four seconds, so the rhythm is burst, cool, burst. **AUTO** hands it
   to the game while both hands are busy building — deliberately the weaker
   option, at about two thirds the rate and never pushing into the red, so
   taking hold of it yourself is still the higher-damage play.
3. Hold the wave, **draft one of three boons**. Commons stack, epics change how a
   run plays, cursed ones pay double and cost you something real.
4. Die. Get a share card with your depth, your build as icons and today's number.

**Between runs** — the reason there is a second one:

1. Every run pays **renown**, win or lose, weighted heavily toward depth.
2. Renown buys **levels**, and levels hand over commanders, modes and new boons.
3. Three **contracts** a day, the same three for everyone, pay renown on top.

The score screen is built around this: the run's number, then the renown bar
filling past whatever it unlocks, then the contracts that ticked, then a very
large **DEFEND AGAIN**. If someone plays once and stops, this is the part that
failed, so it is the part to instrument first.

## Progression

All of it lives in `scripts/autoload/meta.gd` and persists in `user://profile.json`.

**Renown** per run: `waves × 14`, plus `kills / 4`, plus 60 for a campaign win,
40 for a personal best, 25 for the Daily. A good campaign win is about 250.

**Levels** cost `140n + 55·n(n−1)/2` cumulative (level 2 at 140, level 6 at 1250,
level 12 at 4565). Front-loaded so the first unlock lands after about one run,
then stretched so the track is a few days of play rather than one sitting.

| Level | Opens |
| --- | --- |
| 2 | **Quartermaster** · **Daily Siege** |
| 3 | Greek Fire, Barrage, King's Purse |
| 4 | **Master Mason** · **Free Siege** |
| 5 | Marksmen, Salvage, Bulwark |
| 6 | **Zealot of the Wall** |
| 7 | Zagros Wind, Veterans, Hand Cannon |
| 8 | **Marshal of the Column** |
| 9 | The five cursed boons |
| 10 | **Keeper of the Naphtha** |

**Commanders** are picked before a run and fold into the same `Boons.mods` table
the drafts use, so the two systems share one code path. Every one of them costs
something:

| | Gives | Costs |
| --- | --- | --- |
| Warden of the Gate | nothing | nothing |
| Quartermaster | +110 opening rock | kills pay 14% less |
| Master Mason | −45% damage taken, free repairs | +12% build cost |
| Zealot of the Wall | repeater +65% damage, +25% rate | one breach fewer |
| Marshal of the Column | +2 spearmen per post, +15% damage | −70 opening rock |
| Keeper of the Naphtha | every shot ignites | column moves 12% faster |

The **Warden is deliberately empty**. It is the baseline the balance sim measures
against, and the only pick with no downside to work around.

**Contracts** roll from the date, so everyone playing today gets the same three.
They pay the moment they complete, mid-run, not two menus later.

Both **booth mode and the sim opt out entirely** and run at the level cap with
everything unlocked. A stranger at a fair gets ninety seconds; gating content
behind a grind they will never do is just a worse demo. And a balance number
measured today should mean the same thing next month.

## Modes

| Mode | Map | Waves | Lives | Rock | Opens |
| --- | --- | --- | --- | --- | --- |
| **Campaign** | The authored road | 10, scripted | 3 | 180 | always |
| **Daily Siege** | Generated from today's seed | Endless depth | 4 | 220 | level 2 |
| **Free Siege** | Generated from a random seed | Endless depth | 4 | 220 | level 4 |

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

Emplacements have hit points. Manjaniq crews shell them, horse archers pepper
them and sappers detonate on death. A wrecked one leaves rubble and frees its
plinth. Repair from the build sheet, or take Salvage and get the cost back.

Prices go through `Boons.tower_cost`, never `Config.tower_cost`, so a commander's
surcharge reaches the build sheet, the wallet and the sell refund together.

## Attackers

Raider, Runner, Shieldman, Horse Archer, Keshik Rider, Sapper, Shaman, Manjaniq,
Siege Cart, Siege Tower. Horse archers and manjaniq crews shoot back at your
emplacements; shamans heal the column, so they are the real target; sappers blow
up whatever you built too close together.

## Look

Three rules do most of the work, and breaking any of them is what made the
earlier build read as mush at phone size.

**Warm road, cold army.** The mound is a dark, low-chroma night landscape
(`C_GROUND_*`), deliberately below the road in value. The road is the one warm
channel through it. The column is charcoal and steel with hot crimson cloth
(`C_FOE_*`), so an attacker separates from the ground it walks on by temperature
as well as by value. Godot cannot outline procedural `draw_*` calls the way a
sprite pipeline would, and a second black pass on every limb costs more frames
than it is worth with thirty attackers on screen — so each unit gets one soft
dark backing radial and a cool rim arc down its leading edge instead. That buys
most of the separation of a real outline for two draw calls.

**An empty plinth is furniture.** Twenty bright discs used to out-shout the fight
happening between them. They now sit one step off the ground they are cut from
and only light up during the build phase, which is the only time they matter.

**Every figure is built from one kit.** See the block comment above `_rot` in
`enemy.gd`. Units were previously improvised out of stacked circles, which is
how the raider, the sapper and the shieldman all ended up as the same dark
blob. They now share legs, torso, arms and head in fixed proportions, and three
rules decide everything else:

- *Big head.* A 12px head on a 22px unit is not anatomy, it is legibility — it
  is the only part that still says "person" at thumbnail size. Headgear sits on
  the crown and never covers the face.
- *One prop.* Each unit owns exactly one silhouette-defining object held clear
  of the body: a raised sabre, a shield, a bomb, a drum, a lance. Two props and
  it is a blob again.
- *One accent.* One saturated colour per unit, on cloth, so the eye sorts the
  column by hue before it resolves a single shape.

Nothing inside a body-draw function may call `draw_set_transform`: `_draw()`
has already spent it on the facing flip, and a second call replaces that rather
than composing with it. Rotate points through `_rot()` instead.

**The HUD is chips, not a plate.** A full-width slab is the heaviest possible
way to show two numbers, and it was taking 150px off the top of a portrait
screen to do it. Rock and wave are separate chips, lives get their own pill on
a second row, and the wave’s progress is an unlabelled bar — a percentage
printed inside a 22px bar is unreadable at arm’s length and says nothing the
bar does not.

**Two faces, used for different jobs.** Cinzel (`Fonts.display`) names a screen
and nothing else. Rubik (`Fonts.ui`, weights 500/600/700/900) does everything
else. Both are variable fonts in `fonts/`, so a weight is a `FontVariation` over
one file rather than another download; Noto Sans Arabic is wired in as a fallback
so Kurdish and Arabic leaderboard names render. `Wordmark.draw` is the single
lockup, shared by the loading screen, the title and the share card — three
screens setting the title in whatever font was handy is most of what "looks
unfinished" actually means.

## Run

Open the folder in Godot 4.6+ and press Play, or from a shell:

```
godot --path .
godot --path . -- --booth                              # attract loop, auto-restart after idle
godot --path . -- --daily                              # boot into today's siege
godot --headless --path . -- --metatest                # progression self-test, exits non-zero on failure
godot --headless --path . -- --sim --strategy=mixed    # balance bot, prints SIM_RESULT json
godot --path . --resolution 720x1280 -- --shot=C:/tmp/shots   # screenshot tour, prints FPS
godot --path . --resolution 720x1280 -- --shot=DIR --fresh    # the same tour as a first-time player
godot --path . --resolution 1080x1920 -- --units=DIR          # every unit, large, on flat ground
```

`--units` writes a sheet of every attacker and emplacement at a readable scale
on a neutral background. Unit art is authored at about 22px on a phone, which
is exactly the size at which you cannot tell a good shape from a bad one; this
is where you find out. Run it after touching any `_draw_*` in `enemy.gd` or
`tower.gd`.

`--fresh` is worth running whenever the progression numbers move: it shoots the
tour at level 1 with no contracts, which is the state that decides whether
anyone gets as far as a second run.

After adding a script with a new `class_name`, run `godot --headless --path . --import`
once, or the main scene silently fails to load against a stale class cache.

Desktop: `Space` starts the wave, `F` toggles 2x, `Esc` pauses. Web builds accept
`?mode=booth`, `?game=daily` and `?game=free`. A link naming a mode the profile
has not opened falls back to Campaign rather than dropping someone into a screen
the menu says is locked.

Both `--metatest` and `--shot` snapshot the progression fields of your profile
and put them back before quitting, so neither one quietly rewrites your own save.

## Layout

```
fonts/                 Cinzel (display), Rubik (UI), Noto Sans Arabic (fallback)
scripts/autoload/
  config.gd        ALL tunable numbers: modes, seeds, towers, enemies, waves, economy, palette
  boons.gd         the in-run roguelite layer: catalogue, draft weighting, every run modifier
  meta.gd          the between-run layer: renown, levels, unlocks, commanders, contracts
  save_data.gd     profile: bests, lifetime stats, renown, commander, contracts
  game_state.gd    run state: mode, seed, rock, lives, wave, streak, repairs
  sfx.gd           procedural sound, synthesized in steps so the loader can drive it
  leaderboard.gd   local-first board, syncs to server/ when LEADERBOARD_URL is set
scripts/game/
  level.gd         seeded map generation, slots, wave flow, tap routing, directional shake
  commander.gd     the repeater you aim; heat, overheat, AUTO, bursting tracers
  tower.gd         six emplacements, hit points, garrison, repair, wrecking
  defender.gd      guard-post spearmen: block the column and trade blows
  enemy.gd         ten attackers, plus burn, auras, tower fire and death blasts
  background.gd    the lights, and the one quad the baked backdrop is drawn as
  background_paint.gd  every static pixel of that backdrop, rendered once at load
  atmosphere.gd    clouds, terrace mist, embers, dust
  post_fx.gd       vignette, impact flash, last-life pulse, baked CRT grade
  gate.gd / slot.gd / projectile.gd / fx.gd
scripts/ui/
  fonts.gd           the two families, cached as FontVariations by weight
  wordmark.gd        the one title lockup, shared by every screen that shows it
  renown_bar.gd      level chip + bar + next unlock, shared by title/garrison/score
  garrison.gd        commanders, contracts and the unlock track
  loading_screen.gd  boot screen; the bar drives the real synthesis work
  draft_screen.gd    one of three boons, and the icon set the share card reuses
  score_screen.gd    result, renown, contracts, next unlock, and a very large retry
  share_card.gd      the portrait card people screenshot, plus the emoji line
  title_screen.gd    renown strip, wordmark, Daily hero card, modes, garrison row, board
  hud.gd             top bar, wave progress, heat meter, streak, wave banner
  build_menu.gd      bottom sheet: six build cards, or stats plus upgrade/repair/sell
  pause_menu.gd, leaderboard_panel.gd, qr_view.gd, ui_theme.gd
scripts/util/
  gfx.gd           lights, glows, shadows, bars, grain, text fitting, baked styleboxes
  chiptune.gd      the NES-voiced music sequencer (two pulses, triangle, noise)
  meta_test.gd     the progression self-test behind --metatest
  unit_sheet.gd    the art review harness behind --units
  qr_code.gd, sim_player.gd, shot_runner.gd
```

All art and sound is procedural. The only binary assets are the three fonts.

### Notes for whoever touches this next

- `Gfx.gradient_box` rasterises an image. Bake styleboxes in `_ready`, never in `_draw`.
- Towers read their numbers through `Boons.tower_stats` and their prices through
  `Boons.tower_cost`, not through `Config`. Config is the base table; Boons folds
  the run's commander and drafts in.
- New profile fields must be declared in `Save.data`'s default dictionary.
  `load_profile` only restores keys that already exist there, so a field added
  anywhere else is silently wiped on every launch.
- The battlefield canvas is graded by one `CanvasModulate` and lit back by real
  `PointLight2D`s. Keep the light count bounded — elites use a drawn aura rather
  than a light because endless can field a dozen at once.
- The CRT grade is one baked 60px tile blitted once. It was 380 `draw_rect` calls
  a frame before that, which cost about 15fps.
- `Defender._strike` caches the victim's position before swinging: a killing blow
  clears `target` out from under it.
- `Gfx.fit_text` exists because `draw_string`'s width argument is for alignment
  and will happily overflow it. Any variable-length copy next to a fixed-width
  gauge needs it.

## Performance

Every frame-rate number in this file before now was wrong, including the
original "about 55fps". `Engine.get_frames_per_second()` is a single-frame
sample that swings by fifteen frames between reads; the screenshot tour was
printing whatever it happened to catch. `--shot` now averages over a window and
prints the draw call count beside it, which is the number that actually means
something.

`--hide=bg,lights,slots,units,towers,atmos` strips layers out before the
measurement, which is how to find out what is costing the frame instead of
guessing. What that found, in one batch:

| | draw calls | note |
| --- | --- | --- |
| everything (before) | 6095 | |
| background hidden | 2709 | **the backdrop was 56% of all draw calls** |
| every unit and emplacement hidden | 5528 | all the art together: 567 |
| plinths hidden | 1630 | twenty plinths were 1324 |

The backdrop was ~3,400 individual grain specks that Godot replayed every
frame, forever, for texture nobody can see. It is now rendered once into a
texture at load (`background_paint.gd` → `background.gd`). The plinth speckle
went from 58 specks each to 11. The moon fill was a radius-900 additive light
re-rendering most of the screen every frame and is now painted into the bake.
Together: **6095 → 2143 draw calls, a 65% cut**, which is what paid for the
outlines on every unit.

The remaining lever is 2D lights. Hiding them is worth about a third of the
frame rate at identical draw calls, so they are pure GPU cost — braziers and
tower fires are the ones left. Cut their radius before cutting art.

Absolute fps here is unreliable while the Godot editor is open on the project,
which is most of the time during development. Trust the draw call count, and
trust same-batch comparisons; do not trust an fps number measured on its own.

## Balance

Tune with the sim, then on strangers. `--sim` pins the boon draft *and* the
global RNG, so a run reproduces exactly: four runs per strategy gave four
identical results. Sweep other draws with `--boonseed=N`. Campaign, bots only —
they never fire the repeater, so a human has headroom on top of all of this:

| Strategy | Result |
| --- | --- |
| `archers` (mono-archer) | falls on wave 5–6, on armour |
| `naive` (archers, one guard post, a late ballista) | falls on wave 7 |
| `mixed` (uses the whole kit) | wins, 2–3 lives |
| `greedy` (buys the most expensive thing affordable) | wins, 3 lives |

Pinning reproduces a run exactly *within one build*: repeat the same binary and
you get the same wave. It does not reproduce across builds. Everything shares
one global RNG stream, so any change that alters how many `randf()` calls
happen before the draft shifts the whole run — and a wave of combat is chaotic
enough that a one-frame difference compounds. Treat the table as a band, not as
a fingerprint, and re-measure after any change rather than assuming.

The knobs: `Config.campaign_scale` (per-wave stat ramp), `Config.WAVES`
(composition), `Config.endless_scale`, the boon numbers in `Boons.CATALOGUE`, and
the commander numbers in `Meta.COMMANDERS`.

## Booth / leaderboard setup

1. `cd server && npx wrangler kv namespace create BOARD`, paste the id into `wrangler.toml`.
2. `npx wrangler deploy`. Copy the URL.
3. Set `Config.LEADERBOARD_URL` to that URL and `Config.CLAIM_URL` to `<url>/claim/`.
4. Fill `BAD_WORDS` in `worker.js` (Kurdish, Arabic, English) before the event.
5. Offline is fine: scores queue in `user://leaderboard.json` and sync when wifi returns.

Run the booth build with `--booth`. It unlocks everything and awards no renown,
so the machine's profile stays clean across a day of strangers.

## Export

Install Android and Web export templates (Editor > Manage Export Templates), then:
- Android: portrait, min SDK 24.
- Web: single-threaded export for iOS Safari.

## Known TODOs

- Kurdish name (gate signage, domain, store listing).
- The server has no notion of the daily seed yet: `server/worker.js` still takes a
  plain score. For a real Daily board it should record and validate `seed` and
  reject scores whose seed is not today's.
- Recorded SFX. The synthesized set is a placeholder that already hits the right
  beats; `Chiptune` covers the music.
- Perf on a real phone is still unmeasured. See **Performance** above for what
  the desktop numbers do and do not mean.
- The garrison's tab bodies are fixed-height and assume their rows fit. Adding a
  seventh commander or a thirteenth level will need a scroll container.
