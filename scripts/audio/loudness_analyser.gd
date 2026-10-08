extends RefCounted
## Loudness analyser for the AudioDirector debug checker (spec 11.1). Reads an AudioStreamWAV's
## 16-bit PCM samples once and measures the two numbers the rules use: the normalised peak in dBFS,
## and the attack, the time until a 1 ms RMS envelope first reaches 90% of its maximum.
## Reads the loaded stream, not the raw .wav, so it also works in exported debug builds.
## Static functions only.

const FULL_SCALE := 32768.0
const ATTACK_FRACTION := 0.9


## Returns {ok, peak_db, attack_ms, length_s}. ok is false for streams it cannot read.
static func analyse(stream: AudioStreamWAV) -> Dictionary:
	var out := {"ok": false, "peak_db": -120.0, "attack_ms": 0.0, "length_s": 0.0}
	if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS:
		return out
	var data: PackedByteArray = stream.data
	var channels := 2 if stream.stereo else 1
	var frames := data.size() / (2 * channels)
	var rate := int(stream.mix_rate)
	if frames <= 0 or rate <= 0:
		return out
	var window := maxi(1, rate / 1000)
	var envelope := PackedFloat32Array()
	var peak := 0.0
	var acc := 0.0
	var count := 0
	for f in frames:
		var x := 0.0
		for c in channels:
			x += float(data.decode_s16((f * channels + c) * 2))
		x /= FULL_SCALE * channels
		peak = maxf(peak, absf(x))
		acc += x * x
		count += 1
		if count == window:
			envelope.append(sqrt(acc / window))
			acc = 0.0
			count = 0
	var env_max := 0.0
	for v in envelope:
		env_max = maxf(env_max, v)
	var attack_index := 0
	if env_max > 0.0:
		for i in envelope.size():
			if envelope[i] >= ATTACK_FRACTION * env_max:
				attack_index = i
				break
	out["ok"] = true
	out["peak_db"] = linear_to_db(peak) if peak > 0.0 else -120.0
	out["attack_ms"] = float(attack_index * window) * 1000.0 / rate
	out["length_s"] = float(frames) / rate
	return out
