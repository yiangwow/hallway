extends Node
class_name Audio
# Every sound in the game is synthesised here from raw PCM - no imported audio
# assets (GUARDRAILS 5: zero-store-assets). The WAVs under Downloads are
# written by tests/run.gd only, so a human can listen to them; the game and
# the exported .exe never write a file, they only build AudioStreamWAVs in
# memory and play them.

const RATE := 22050

# One-pole low-pass (RC filter), discretised at RATE. Used to give white noise
# a body (the drone's low rumble, the pencil's softened scratch).
static func _lowpass(x: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
    var rc: float = 1.0 / (TAU * cutoff_hz)
    var dt: float = 1.0 / RATE
    var alpha: float = dt / (rc + dt)
    var y := PackedFloat32Array()
    y.resize(x.size())
    var prev := 0.0
    for i in x.size():
        prev = prev + alpha * (x[i] - prev)
        y[i] = prev
    return y

# Pure, deterministic PCM in [-1, 1]: same name + seed always makes the same
# samples. DC-free (the mean is subtracted) and peak-normalised to 0.8.
static func pcm(name: String, seed: int = 1) -> PackedFloat32Array:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed
    var dt: float = 1.0 / RATE
    var samples := PackedFloat32Array()
    match name:
        "drone":
            # 2.0 s exactly (44100 samples at RATE): 38 Hz + 76 Hz (-6 dB) sines,
            # each a whole number of cycles in 2 s (76 and 152), so the loop is
            # seamless; a low-passed noise bed rides under them.
            var n := int(round(2.0 * RATE))
            samples.resize(n)
            for i in n:
                var t: float = i * dt
                samples[i] = sin(TAU * 38.0 * t) + 0.5 * sin(TAU * 76.0 * t)
            var noise := PackedFloat32Array()
            noise.resize(n)
            for i in n:
                noise[i] = rng.randf_range(-1.0, 1.0)
            noise = _lowpass(noise, 120.0)
            var npeak := 0.0
            for i in n:
                npeak = maxf(npeak, absf(noise[i]))
            if npeak > 0.0:
                var nscale: float = 0.25 / npeak   # noise mixed at ~0.25 of the sines' level
                for i in n:
                    noise[i] *= nscale
            # 20 ms raised-cosine fade at both ends: only the noise is tapered,
            # so it is exactly 0 at the loop point and never clicks.
            var fade_n := int(round(0.02 * RATE))
            for i in fade_n:
                var w: float = 0.5 * (1.0 - cos(PI * float(i) / float(fade_n)))
                noise[i] *= w
                noise[n - 1 - i] *= w
            for i in n:
                samples[i] += noise[i]
        "click":
            # 30 ms noise burst, exponential decay tau 5 ms: a crank/valve/lamp click.
            var n := int(round(0.03 * RATE))
            samples.resize(n)
            for i in n:
                var t: float = i * dt
                samples[i] = rng.randf_range(-1.0, 1.0) * exp(-t / 0.005)
        "step":
            # 120 ms: 60 Hz thump decaying tau 40 ms, plus a short noise transient at the start.
            var n := int(round(0.12 * RATE))
            samples.resize(n)
            for i in n:
                var t: float = i * dt
                var thump: float = sin(TAU * 60.0 * t) * exp(-t / 0.04)
                var transient: float = rng.randf_range(-1.0, 1.0) * exp(-t / 0.0033)
                samples[i] = thump + transient
        "pencil":
            # 200 ms low-passed noise (~2 kHz, mostly raw): 10 ms attack, then decay tau 60 ms.
            var n := int(round(0.2 * RATE))
            samples.resize(n)
            var noise := PackedFloat32Array()
            noise.resize(n)
            for i in n:
                noise[i] = rng.randf_range(-1.0, 1.0)
            noise = _lowpass(noise, 2000.0)
            var attack_n := int(round(0.01 * RATE))
            for i in n:
                var t: float = i * dt
                var env: float
                if i < attack_n:
                    env = float(i) / float(attack_n)
                else:
                    env = exp(-(t - 0.01) / 0.06)
                samples[i] = noise[i] * env
        _:
            return PackedFloat32Array()
    # one writer for DC-removal + peak normalisation, common to every sound
    var mean := 0.0
    for v in samples:
        mean += v
    mean /= samples.size()
    var peak := 0.0
    for i in samples.size():
        samples[i] -= mean
        peak = maxf(peak, absf(samples[i]))
    if peak > 0.0:
        var scale: float = 0.8 / peak
        for i in samples.size():
            samples[i] = clampf(samples[i] * scale, -1.0, 1.0)
    return samples

# 16-bit mono WAV from pcm(); "drone" loops forward over its whole length.
static func wav(name: String, seed: int = 1) -> AudioStreamWAV:
    var samples := pcm(name, seed)
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = RATE
    stream.stereo = false
    var bytes := PackedByteArray()
    bytes.resize(samples.size() * 2)
    for i in samples.size():
        var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
        bytes.encode_s16(i * 2, v)
    stream.data = bytes
    if name == "drone":
        stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
        stream.loop_begin = 0
        stream.loop_end = samples.size()
    return stream

# amp is Lighting.breath_amp() (0.05 x proximity + 0.15 x dose): the drone
# follows DOSE, not distance - proximity alone barely moves it.
static func gain_target(amp: float) -> float:
    return clampf((amp - 0.05) / 0.2, 0.0, 1.0)

# exponential smoothing: slower to leave (release) than to arrive (attack).
static func gain_step(g: float, target: float, dt: float) -> float:
    var tau: float = 2.0 if target > g else 2.8
    return g + (target - g) * (1.0 - exp(-dt / tau))

var drone: AudioStreamPlayer      # non-positional (M4.0i): a 38 Hz sub has no direction, and a source that jumped at every cut told where it went
var _wavs := {}                   # name:seed -> AudioStreamWAV, built once
var step_i := 0
var sfx: AudioStreamPlayer
var gain := 0.0

# the whole game's loudness (T119, the owner asked for half): -6 dB is half the
# amplitude. One knob: the drone, the one-shots and the hall's reverb all ride
# the Master bus. Raise or lower this line to taste.
const MASTER_DB := -6.0

func build(parent: Node, harness: bool) -> void:
    AudioServer.set_bus_volume_db(0, MASTER_DB)
    # the hall bus (M3.5): a reverb the one-shots go through while the player is in the hall
    if AudioServer.get_bus_index("Hall") < 0:
        AudioServer.add_bus()
        var idx := AudioServer.get_bus_count() - 1
        AudioServer.set_bus_name(idx, "Hall")
        AudioServer.set_bus_send(idx, "Master")
        var rv := AudioEffectReverb.new()
        rv.room_size = 0.8
        rv.damping = 0.5
        rv.wet = 0.3
        rv.dry = 0.8
        AudioServer.add_bus_effect(idx, rv)
    drone = AudioStreamPlayer.new()
    drone.stream = wav("drone")
    drone.volume_db = -80.0
    drone.autoplay = false
    add_child(drone)
    drone.play()
    sfx = AudioStreamPlayer.new()
    add_child(sfx)
    if harness:
        AudioServer.set_bus_mute(0, true)   # the harness never makes a sound on the owner's desktop

# at is the thing's position (Vector3) or null while it is absent; the drone
# keeps looping at all times, only its gain and position move.
func drone_tick(amp: float, dt: float, at) -> void:
    gain = gain_step(gain, gain_target(amp) if at != null else 0.0, dt)
    if at != null:
        pass                                  # the source has no place: gain from dose alone
    drone.volume_db = linear_to_db(maxf(gain, 0.0001))

# one-shots (M3.5 wires the callers; nothing calls this yet)
# route the one-shots through the hall's reverb while the player is there
func set_zone(zone: String) -> void:
    if sfx != null:
        sfx.bus = "Hall" if zone == "hall" else "Master"

var plays := 0          # one-shots played (sims count them; the harness is muted anyway)

func play(name: String) -> void:
    plays += 1
    var seed := 1
    var db := 0.0
    if name == "step":
        # four seeded footfalls in rotation with a small seeded gain jitter (M4.0i)
        step_i = (step_i + 1) % 4
        seed = step_i + 1
        db = -2.0 + 4.0 * float(hash("step:%d" % plays) % 1000) / 1000.0
    var key := "%s:%d" % [name, seed]
    if not _wavs.has(key):
        _wavs[key] = wav(name, seed)
    sfx.stream = _wavs[key]
    sfx.volume_db = db
    sfx.play()
