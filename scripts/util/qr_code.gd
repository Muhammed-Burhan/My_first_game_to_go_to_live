class_name QrCode
extends RefCounted
## Minimal QR Code encoder: byte mode, versions 1-6, EC level M (falls back to L
## for long strings), automatic mask selection. Enough for a claim URL.
## Ported from the public-domain "Nayuki QR Code generator" structure.
##
## Usage: var qr := QrCode.encode("https://..."); qr["size"], qr["modules"][y][x] (1 = dark)

const ECL_L := 0
const ECL_M := 1

# [version] -> [ [ec_per_block, blocks] for L, [ec_per_block, blocks] for M ]
const EC_TABLE := {
	1: [[7, 1], [10, 1]],
	2: [[10, 1], [16, 1]],
	3: [[15, 1], [26, 1]],
	4: [[20, 1], [18, 2]],
	5: [[26, 1], [24, 2]],
	6: [[18, 2], [16, 4]],
}
const TOTAL_CW := {1: 26, 2: 44, 3: 70, 4: 100, 5: 134, 6: 172}


static func encode(text: String) -> Dictionary:
	var data := text.to_utf8_buffer()
	for ecl in [ECL_M, ECL_L]:
		for v in range(1, 7):
			if data.size() + 2 <= _data_cw(v, ecl):
				return _build(data, v, ecl)
	return {}


static func _data_cw(v: int, ecl: int) -> int:
	var t: Array = EC_TABLE[v][ecl]
	return TOTAL_CW[v] - t[0] * t[1]


static func _build(data: PackedByteArray, v: int, ecl: int) -> Dictionary:
	var data_cw := _data_cw(v, ecl)
	# --- bit stream: mode 0100, 8-bit count, bytes, terminator, pad
	var bits: Array = []
	_append_bits(bits, 0b0100, 4)
	_append_bits(bits, data.size(), 8)
	for b in data:
		_append_bits(bits, b, 8)
	var cap_bits := data_cw * 8
	_append_bits(bits, 0, mini(4, cap_bits - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var pad := 0xEC
	while bits.size() < cap_bits:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var cw := PackedByteArray()
	cw.resize(data_cw)
	for i in range(data_cw):
		var b := 0
		for k in range(8):
			b = (b << 1) | bits[i * 8 + k]
		cw[i] = b
	# --- split into blocks, compute EC, interleave
	var ec_len: int = EC_TABLE[v][ecl][0]
	var nb: int = EC_TABLE[v][ecl][1]
	var short_count := nb - (data_cw % nb)
	var short_len := data_cw / nb
	var blocks: Array = []
	var ecs: Array = []
	var divisor := _rs_divisor(ec_len)
	var k := 0
	for i in range(nb):
		var blen := short_len if i < short_count else short_len + 1
		var blk := cw.slice(k, k + blen)
		k += blen
		blocks.append(blk)
		ecs.append(_rs_remainder(blk, divisor))
	var final := PackedByteArray()
	for i in range(short_len + 1):
		for j in range(nb):
			var blk: PackedByteArray = blocks[j]
			if i < blk.size():
				final.append(blk[i])
	for i in range(ec_len):
		for j in range(nb):
			final.append(ecs[j][i])
	# --- matrix
	var size := 17 + 4 * v
	var modules: Array = []
	var is_func: Array = []
	for y in range(size):
		var row := PackedByteArray()
		row.resize(size)
		modules.append(row)
		var frow := PackedByteArray()
		frow.resize(size)
		is_func.append(frow)
	var m := {"size": size, "modules": modules, "func": is_func, "version": v, "ecl": ecl}
	_draw_function_patterns(m)
	_draw_codewords(m, final)
	var best_mask := 0
	var best_pen := 1 << 62
	for mask in range(8):
		_apply_mask(m, mask)
		_draw_format_bits(m, mask)
		var pen := _penalty(m)
		if pen < best_pen:
			best_pen = pen
			best_mask = mask
		_apply_mask(m, mask)  # undo (XOR)
	_apply_mask(m, best_mask)
	_draw_format_bits(m, best_mask)
	m["mask"] = best_mask
	m.erase("func")
	return m


static func _append_bits(bits: Array, value: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((value >> i) & 1)


# ------------------------------------------------------------------ Reed-Solomon

static func _gf_mul(x: int, y: int) -> int:
	# Russian-peasant multiplication in GF(2^8) with reducer 0x11D; z stays < 256.
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in range(degree):
		for j in range(degree):
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor: int = b ^ result[0]
		result.remove_at(0)
		result.append(0)
		for i in range(divisor.size()):
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


# ------------------------------------------------------------------ matrix drawing

static func _set_func(m: Dictionary, x: int, y: int, dark: bool) -> void:
	m["modules"][y][x] = 1 if dark else 0
	m["func"][y][x] = 1


static func _draw_function_patterns(m: Dictionary) -> void:
	var size: int = m["size"]
	for i in range(size):
		_set_func(m, 6, i, i % 2 == 0)
		_set_func(m, i, 6, i % 2 == 0)
	_draw_finder(m, 3, 3)
	_draw_finder(m, size - 4, 3)
	_draw_finder(m, 3, size - 4)
	if m["version"] >= 2:
		var p := size - 7
		_draw_alignment(m, p, p)
	_draw_format_bits(m, 0)  # reserve


static func _draw_finder(m: Dictionary, x: int, y: int) -> void:
	var size: int = m["size"]
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var dist := maxi(absi(dx), absi(dy))
			var xx := x + dx
			var yy := y + dy
			if xx >= 0 and xx < size and yy >= 0 and yy < size:
				_set_func(m, xx, yy, dist != 2 and dist != 4)


static func _draw_alignment(m: Dictionary, x: int, y: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_func(m, x + dx, y + dy, maxi(absi(dx), absi(dy)) != 1)


static func _draw_format_bits(m: Dictionary, mask: int) -> void:
	var size: int = m["size"]
	var ecl_bits := 1 if m["ecl"] == ECL_L else 0
	var data := (ecl_bits << 3) | mask
	var rem := data
	for i in range(10):
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_func(m, 8, i, (bits >> i) & 1 == 1)
	_set_func(m, 8, 7, (bits >> 6) & 1 == 1)
	_set_func(m, 8, 8, (bits >> 7) & 1 == 1)
	_set_func(m, 7, 8, (bits >> 8) & 1 == 1)
	for i in range(9, 15):
		_set_func(m, 14 - i, 8, (bits >> i) & 1 == 1)
	for i in range(0, 8):
		_set_func(m, size - 1 - i, 8, (bits >> i) & 1 == 1)
	for i in range(8, 15):
		_set_func(m, 8, size - 15 + i, (bits >> i) & 1 == 1)
	_set_func(m, 8, size - 8, true)


static func _draw_codewords(m: Dictionary, data: PackedByteArray) -> void:
	var size: int = m["size"]
	var i := 0
	var total := data.size() * 8
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in range(size):
			for j in range(2):
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if m["func"][y][x] == 0 and i < total:
					m["modules"][y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


static func _apply_mask(m: Dictionary, mask: int) -> void:
	var size: int = m["size"]
	for y in range(size):
		for x in range(size):
			if m["func"][y][x] == 1:
				continue
			var inv := false
			match mask:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = (x * y) % 2 + (x * y) % 3 == 0
				6: inv = ((x * y) % 2 + (x * y) % 3) % 2 == 0
				7: inv = ((x + y) % 2 + (x * y) % 3) % 2 == 0
			if inv:
				m["modules"][y][x] ^= 1


static func _penalty(m: Dictionary) -> int:
	var size: int = m["size"]
	var mods: Array = m["modules"]
	var result := 0
	var dark := 0
	# Rows and columns: runs and finder-like patterns
	for y in range(size):
		var run_color := -1
		var run_len := 0
		var history := [0, 0, 0, 0, 0, 0, 0]
		for x in range(size):
			var c: int = mods[y][x]
			dark += c
			if c == run_color:
				run_len += 1
				if run_len == 5:
					result += 3
				elif run_len > 5:
					result += 1
			else:
				result += _finder_penalty_push(history, run_len, run_color)
				run_color = c
				run_len = 1
		result += _finder_penalty_push(history, run_len, run_color)
		result += _finder_penalty_push(history, 0, -1)
	for x in range(size):
		var run_color := -1
		var run_len := 0
		var history := [0, 0, 0, 0, 0, 0, 0]
		for y in range(size):
			var c: int = mods[y][x]
			if c == run_color:
				run_len += 1
				if run_len == 5:
					result += 3
				elif run_len > 5:
					result += 1
			else:
				result += _finder_penalty_push(history, run_len, run_color)
				run_color = c
				run_len = 1
		result += _finder_penalty_push(history, run_len, run_color)
		result += _finder_penalty_push(history, 0, -1)
	# 2x2 blocks
	for y in range(size - 1):
		for x in range(size - 1):
			var c: int = mods[y][x]
			if c == mods[y][x + 1] and c == mods[y + 1][x] and c == mods[y + 1][x + 1]:
				result += 3
	# Balance
	var total := size * size
	var k := (absi(dark * 20 - total * 10) + total - 1) / total - 1
	result += k * 10
	return result


## Shift a run into the 7-slot history; return 40 if it forms 1:1:3:1:1 with 4+ light padding.
static func _finder_penalty_push(history: Array, run_len: int, run_color: int) -> int:
	if run_color == -1 and run_len == 0:
		# flush: pad with light run of 4 so a trailing pattern is detected
		history.pop_back()
		history.push_front(4)
	else:
		history.pop_back()
		history.push_front(run_len)
	var n: int = history[1]
	var core: bool = n > 0 and history[2] == n and history[3] == n * 3 and history[4] == n and history[5] == n
	var a := 0
	if core and history[0] >= n * 4 and history[6] >= n:
		a += 40
	if core and history[6] >= n * 4 and history[0] >= n:
		a += 40
	return a
