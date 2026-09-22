class_name Chiptune
extends RefCounted
## A small NES-voiced sequencer. The old menu loop was a drone with an oud over
## it, which sits under the mix and drifts; this is built the way the 2A03 did
## it — two pulse channels, a triangle bass and a noise channel — because that
## is what gives a Contra-era track its drive and why it stays listenable on a
## loop for ten minutes at a booth.
##
## Channels are deliberately sparse: at most one note each per step, no reverb,
## no stacked oscillators. Chip music reads as clean because it cannot afford
## to be muddy.

const RATE := 11025

## D natural minor, the scale the rest of the game's art is already sitting in.
## Index 0 = D3 and index 7 the octave above; the sequencer transposes from there.
const SCALE := [146.83, 164.81, 174.61, 196.00, 220.00, 233.08, 261.63, 293.66]

## -1 is a rest, otherwise a scale degree. One entry per sixteenth.
const LEAD_A := [
	0, -1, 0, 2, 3, -1, 2, 0, 4, -1, 3, 2, 0, -1, -1, -1,
	3, -1, 3, 4, 5, -1, 4, 3, 2, -1, 3, 2, 0, -1, -1, -1,
]
const LEAD_B := [
	7, -1, 6, 5, 4, -1, 3, 4, 5, -1, 4, 3, 2, -1, 0, -1,
	4, -1, 5, 6, 7, -1, 6, 5, 4, 3, 2, -1, 0, -1, -1, -1,
]
## The counter-line: mostly thirds under the lead, thinner and quieter.
const HARM := [
	-1, -1, 4, -1, 0, -1, -1, 4, 2, -1, -1, 0, 4, -1, -1, -1,
	0, -1, -1, 2, 3, -1, -1, 0, 4, -1, -1, 2, 0, -1, -1, -1,
]
## Driving eighths under everything. This is what makes it move.
const BASS := [
	0, 0, 4, 0, 2, 2, 4, 0, 0, 0, 4, 0, 5, 5, 4, 4,
	0, 0, 4, 0, 3, 3, 4, 0, 6, 6, 5, 5, 4, 4, 2, 2,
]


## `battle` doubles the drums, brightens the lead and pushes the tempo.
static func build(battle: bool) -> PackedFloat32Array:
	var bpm := 132.0 if not battle else 158.0
	var sixteenth := 60.0 / bpm / 4.0
	var steps := LEAD_A.size() * 2          # two 8-bar phrases
	var dur := sixteenth * steps
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)

	var lead_oct := 2.0 if battle else 1.0
	var lead_duty := 0.25 if battle else 0.5
	var drum_gain := 1.0 if battle else 0.45
	var lead_amp := 0.20 if battle else 0.15

	# Per-channel running state. Phases are carried across notes so the loop
	# point never clicks.
	var ph_lead := 0.0
	var ph_harm := 0.0
	var ph_bass := 0.0
	var f_lead := SCALE[0]
	var f_harm := SCALE[0]
	var f_bass := SCALE[0]
	var env_lead := 0.0
	var env_harm := 0.0
	var env_bass := 0.0
	var note_age := 0.0
	var last_step := -1

	var rng := RandomNumberGenerator.new()
	rng.seed = 1258
	var ny := 0.0
	var hat := 0.0
	var snare := 0.0
	var kick := 0.0
	var kick_f := 90.0

	for i in range(n):
		var t := float(i) / RATE
		var step := int(t / sixteenth) % steps
		if step != last_step:
			last_step = step
			var phrase := step / LEAD_A.size()
			var s16 := step % LEAD_A.size()
			var lead_row: Array = LEAD_A if phrase == 0 else LEAD_B
			var li: int = lead_row[s16]
			if li >= 0:
				f_lead = SCALE[li] * 2.0 * lead_oct
				env_lead = 1.0
				note_age = 0.0
			var hi: int = HARM[s16]
			if hi >= 0:
				f_harm = SCALE[hi] * 2.0
				env_harm = 1.0
			var bi: int = BASS[s16]
			if bi >= 0:
				f_bass = SCALE[bi] * 0.5
				env_bass = 1.0
			# Percussion: snare on 2 and 4, hat on every offbeat sixteenth.
			if s16 % 8 == 4:
				snare = 1.0
			if s16 % 4 == 0:
				kick = 1.0
				kick_f = 90.0
			if s16 % 2 == 1:
				hat = 0.55
		note_age += 1.0 / RATE

		# Lead: pulse with delayed vibrato, the signature NES lead articulation.
		var vib := 1.0 + 0.010 * sin(note_age * TAU * 6.0) * clampf((note_age - 0.06) * 6.0, 0.0, 1.0)
		ph_lead += (f_lead * vib) / RATE
		env_lead *= 0.99965
		var lead := (1.0 if fmod(ph_lead, 1.0) < lead_duty else -1.0) * env_lead * lead_amp

		ph_harm += f_harm / RATE
		env_harm *= 0.9994
		var harm := (1.0 if fmod(ph_harm, 1.0) < 0.5 else -1.0) * env_harm * 0.075

		# Bass on a triangle: rounder than a pulse, so it holds the bottom
		# without fighting the lead.
		ph_bass += f_bass / RATE
		env_bass *= 0.99975
		var bt := fmod(ph_bass, 1.0)
		var bass := (4.0 * absf(bt - 0.5) - 1.0) * env_bass * 0.24

		var x := rng.randf_range(-1.0, 1.0)
		ny += (x - ny) * 0.5
		hat *= 0.9965
		snare *= 0.9982
		kick *= 0.9975
		kick_f = maxf(42.0, kick_f * 0.9990)
		var drums := ny * hat * 0.05 + ny * snare * 0.14
		drums += sin(fmod(t * kick_f, 1.0) * TAU) * kick * 0.22
		out[i] = lead + harm + bass + drums * drum_gain
	return out
