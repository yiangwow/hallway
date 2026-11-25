extends Node3D
# Builds the whole scene in code: a dead-ended hallway with two identical
# skylit rooms, a sun + SDFGI environment, a first-person player, and the
# ASCII post-process layer. All dimensions in metres, Y up, hallway along Z.

# The --shot/--sim harness (M3.0a/M3.0c) lives in tests/harness.gd (Harness);
# main.gd keeps one-line trampolines of the same names.
const Harness := preload("res://tests/harness.gd")

const WALL := 0.3
const HALL_W := 3.0      # inner width
const HALL_L := 24.0     # inner length
const HALL_H := 3.2
const ROOM := 9.0        # inner width and depth
const ROOM_H := 6.0
const DOOR_W := 1.6
const DOOR_H := 2.4
const SKY := 6.0         # skylight opening, square
const MULLION := 0.12
# office beyond the +Z end wall (M1.2): inner 4 x 4 x 3.2, doorway 1.0 x 2.4, 1 x 1 pane at the ceiling centre
const OFF_W := 4.0
const OFF_D := 4.0
const OFF_H := 3.2
const OFF_DOOR_W := 1.0
const OFF_PANE := 1.0
# plant room beyond the -Z end wall (M4.1): inner 4 x 5 x 3.2, doorway 1.0 x 2.4, no skylight
const PLANT_W := 4.0
const PLANT_D := 5.0
const PLANT_H := 3.2
const PLANT_DOOR_W := 1.0
const YARD_D := 4.0        # sunlit ground beyond the yard door (seen through the keyhole)

var mat_wall: StandardMaterial3D
var mat_floor: StandardMaterial3D
var mat_dark: StandardMaterial3D
var ascii_layer: CanvasLayer
var ascii_mat: ShaderMaterial
var player: CharacterBody3D
var creature: Node3D
var lighting: Lighting
var audio: Audio
var game: Game
var seat := {}          # the thing's seat (Thing.seat dict), {} while absent
var cut_due := -1.0     # game clock at which a batched light change is acted on; -1 = none pending
var dose := 0.0         # Thing.dose_step; at DOSE_MAX the bleach starts
var bleach_t := -1.0    # game clock when the bleach started; -1 = not bleaching
var deaths := 0
var blank: ColorRect    # layer 12: the 0.5 s of nothing before the restart
var death_pos := Vector3.ZERO
var decals: Array[Vector3] = []   # where each bleach took the player; never cleared
var clipboard: RichTextLabel   # bbcode since M5.3: the one coloured word
var clipboard_bg: ColorRect
var start_line: Label
var start_font: SystemFont   # kept so _fit_hud can re-measure the line when the window changes (M7.0d)
var start_fade_t := -1.0   # game time the fade began; -1 = not yet
var _last_step_check := -1
var interact: Interact
var hud: CanvasLayer
var clock_dt := 0.0

# The one clock. Wall-time in play; under --shot/--sim it steps 1/60 per frame
# from the moment the scene args are applied, so a capture at --t=SEC is the
# same frame every run. Everything that animates reads this, never TIME.
var clock_t := 0.0
var clock_fixed := false
var clock_running := true

# Scene args from the command line (--key=value after "--"). Parsed once; every
# system reads what it needs from here. `harness` = --shot/--sim/--bench present.
var args := {}
var harness := false
var ab_force := -1.0   # --ab=thing: forces thing_on to 0 then 1 on consecutive captures
var seed := 1          # --seed=N: the dropout schedule (Thing.presence)
# harness numbers (M3.0a): the aura uniforms as last fed to the shader, and
# the wall clock / frame count behind the watchdog and the fps= field
var aura_px := Vector2.ZERO
var aura_r := 0.0
var aura_on := 0.0
var bleach_hue := 0.0        # 1 while this bleach is the hue (M5.5): set at its start from the colour gate
var d3_pos := Vector3.ZERO   # D3's rectangle (M5.1), for the harness
var d6_decal: Decal        # D6's burn (M7.0c): the probe toggles it to measure the burn against the bare floor
var d6_pos := Vector3.ZERO   # D6's absence, the feet (M6.0i), for the harness
var lamp_side := Thing.LAMP_SIDE   # the disc edge's side offset (M6.0i): eased at LAMP_SIDE_MS toward 0 over a targeted crank or the bolt, back after - never a snap to pace out
const LAMP_SIDE_MS := 0.4
var clip_auto_until := -1.0   # the clipboard rises by itself once, when C5 completes (M6.0n, OWNER default auto-rise)
const CLIP_RISE_S := 4.0
var clip_shown := false       # last frame's visibility: the gate's key turns on the RELEASE (the word was read)
var cf_t0 := -1.0             # the colour-before-shape choreography's start (Thing.colour_first); once
var cf_done := false
var hue_mix := 0.0      # 3.14: the hue's presence in the reading, 0 until game.colour_unlocked(); ramps while riding (M5.4); --hue=1 forces 1 (the probe)
const HUE_S := 2.0      # the tint's ramp, each way (GUARDRAILS 5: ramps >= 2 s)
var aura_world := Vector3.ZERO   # the lagged body point (M4.0b)
var gate_mix := 0.0              # seen/unseen ramp, >= GATE_S s each way
const GATE_S := 2.0
const MIN_CUT_M := 3.0           # a re-pick never lands within this of the player (M4.0f)
var presence_hint := [0, 0.0]    # Thing.presence's walk resumes here each frame (M4.0j)
# the lamp (M4.2): where it is - on the plant-room hook, held, or on the desk hook
var lamp_where := "plant"
var hook_plant: Interactable
var hook_desk: Interactable
var racks := {}         # M4.3: {room: [{body, sheet, inter}]}; a sheet is a light change
var shutters := {}      # M4.4: {room: [{mesh, crank, edge, sign, zc}]}; extent follows the crank
var card := {}          # M4.7: {card, dark, inter} on A's centre rack (C6, D4)
var sign: Interactable  # M4.7: "sign" at the desk log (C7); offered only with the lamp hung
var bolt_enabled := false   # C7 done: the yard door's bolt can be worked (M5)
var yard_door: Array = []   # the four slabs filling the yard doorway (M5.6)
var bolt: Interactable      # the bolt on its inner face
var ended := ""             # ""/"A"/"B": which ending has fired
var end_t := -1.0           # the clock when it fired; -1 = not ended
var exit_armed := false     # 3 s after the credits E quits (M6.0b); never under the harness
var _audio_zone := ""
var walk_until := 0.0            # --walk=SEC: the harness walks forward until this clock time
var ride_t0 := -1.0              # the clock when the lamp seat was taken; -1 = not riding (M4.6c)
var harness_t0 := 0
var harness_frames := 0
var watchdog_frames := 0
var captured := false
# aura radius in metres at the thing's depth. The owner approved this look on the
# trial5 shots (2026-09-02); REF Specs says 1.2 m - logged for him, not changed.
const AURA_M := 3.48   # the aura's radius in metres at the thing's distance: the owner's (trial5, 2026-09-02; LOG T15, M3.2 keeps it - REF's 1.2 is the projected patch, not this)

func _ready() -> void:
    Interact.register_actions()   # first: props built below ask the InputMap (M5.0k)
    _parse_args()
    _materials()
    _build_hallway()
    for s: float in [-1.0, 1.0]:
        _build_room(s)
    _build_office()
    _build_plant()
    _floor()
    _environment()
    _player()
    _audio()          # after the player: it listens to its footfalls
    _game()
    _c1_props()
    d3_pos = Props._discoveries(self)   # M5.1: the note (D2) and B's second rectangle (D3); D6's burn sets d6_pos
    _hooks()
    _racks()
    _shutters()
    _card_and_sign()
    _bolt()
    _creature()
    Harness.decal_arg(self)   # M3.0a: --decal=x,y,z places one for shots
    _ascii()
    _hud()
    _interact()
    _maybe_screenshot()

func _parse_args() -> void:
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--") and "=" in a:
            var kv := a.substr(2).split("=", true, 1)
            args[kv[0]] = kv[1]
        elif a.begins_with("--"):
            args[a.substr(2)] = "1"
    harness = args.has("shot") or args.has("sim") or args.has("bench")
    seed = int(args.get("seed", "1"))
    if harness:
        # watchdog (M3.0a): counts frames, not seconds, so a slow but healthy run
        # is never killed: settle + 60 x (t + 30) frames without a capture = quit(2)
        harness_t0 = Time.get_ticks_msec()
        watchdog_frames = int(args.get("settle", "360")) + int(60.0 * (float(args.get("t", "0")) + 30.0))
    if not harness:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)   # play starts maximised (M6.0k); the harness keeps the project's 1600x900 window
    if args.has("res"):
        var wh := (args["res"] as String).split("x")
        if wh.size() == 2:
            get_window().call_deferred("set_size", Vector2i(int(wh[0]), int(wh[1])))   # deferred: set inside _ready it was lost (T113)
    var keys := args.keys()
    keys.sort()
    var parts := PackedStringArray()
    for k in keys:
        parts.append("%s=%s" % [k, args[k]])
    print("ARGS " + " ".join(parts))

# M4.0a: builders moved to props.gd (Props); these are one-line trampolines.
func _materials() -> void: Props._materials(self)
func _mat(albedo: float) -> StandardMaterial3D: return Props._mat(self, albedo)
func _interactable(at: Vector3, size: Vector3, prompt_text: String, hold: float, ascii_needed: bool) -> Interactable: return Props._interactable(self, at, size, prompt_text, hold, ascii_needed)
func _plaque(side: float) -> Interactable: return Props._plaque(self, side)
func slab(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void: Props.slab(self, a, b, mat)
func _floor() -> void: Props._floor(self)
func _build_hallway() -> void: Props._build_hallway(self)
func _build_room(s: float) -> void: Props._build_room(self, s)
func _build_office() -> void: Props._build_office(self)
func _build_plant() -> void: Props._build_plant(self)

func _environment() -> void:
    lighting = Lighting.new()
    lighting.name = "Lighting"
    add_child(lighting)
    lighting.build(self, args)

func _audio() -> void:
    audio = Audio.new()
    audio.name = "Audio"
    add_child(audio)
    audio.build(self, harness)
    player.stepped.connect(func() -> void: audio.play("step"))

func _game() -> void:
    game = Game.new()
    game.chore_done.connect(_on_chore_done)
    lighting.light_changed.connect(_on_light_changed)
    Harness.game_args(self)   # M3.0a: --chores=N / --shut=.. fast-forward state for a shot/sim

func _on_chore_done(_id: String) -> void:
    _sync_sun()
    if _id == "C5" and clipboard != null:
        clip_auto_until = clock_t + CLIP_RISE_S   # the list rises once by itself (M6.0n): the word is read before anything tints
    # absent until C2 (GUARDRAILS 3.9); the first seat is in B; it spawns once -
    # after a death the seat is kept, and any later absence ends by the cut rule
    if game.done_count() >= 2 and seat.is_empty() and deaths == 0:
        _spawn("B")

# The thing arrives as DIM only: a seat and its negative light. No body, no aura
# until M3 (pillar 5). --thing=x,y,z (harness) overrides the pick.
func _spawn(room: String) -> void:
    if args.has("thing"):
        var p := (args["thing"] as String).split(",")
        seat = {"room": room, "row": -1, "col": -1, "step": lighting.step, "pos": Vector3(float(p[0]), float(p[1]), float(p[2])), "normal": Vector3.UP, "surface": "floor"}
    else:
        seat = Thing.pick_seat(lighting.step, lighting.shut, lighting.lamp_on, player.position, room, true)   # far: across the room (M4.0f)
        if seat.is_empty() and game.done_count() >= 3:
            seat = Thing.pick_seat(lighting.step, lighting.shut, lighting.lamp_on, player.position, "", true)   # B shut: both rooms (harness states)
    if seat.is_empty() or seat.get("surface", "") == "lamp":
        seat = {}
        return
    cut_due = -1.0          # the step that spawns it is not a re-pick (gate M2)
    lighting.seat_omni(seat["pos"] + seat["normal"] * Thing.OMNI_OFF)
    # the body comes at the first cut, not the spawn (M4.0g): DIM -> BLACK in play
    # order whatever Tab says. The harness's --thing seat binds it at once.
    if args.has("thing"):
        _body_at(seat)

# rest -> light change -> one re-pick 1 s later (GUARDRAILS 3.9); the batch is
# never extended, and nothing happens while it is absent
func _on_light_changed(_kind: String) -> void:
    if game != null and game.done_count() >= 2:
        cut_due = Thing.due_after(cut_due, clock_t)

func _seat_seen(s: Dictionary) -> bool:
    var cam: Camera3D = player.cam
    var occluded := func(p: Vector3) -> bool:
        var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, 1, [player.get_rid()])
        return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()
    var rim: float = lighting.seat_light.omni_range if lighting.seat_light != null else 2.0
    var pts := Thing.seat_points(s, rim)
    # the real body too (M6.0e): while riding the mass trails behind the disc edge -
    # after a lamp-off it may stand nowhere near the seat's nominal body, in plain view
    if creature != null and not seat.is_empty() and s.get("pos") == seat.get("pos"):
        pts.append_array(Thing.body_points(creature.global_position, creature.rotation.y))
    return Thing.seen(pts, cam.get_camera_projection(), cam.global_transform, occluded)

# the due re-pick: cut (move the omni) only while origin and destination are
# both unseen; else keep waiting - stare and it never moves. Called every frame
# past the due time until it resolves.
func _try_cut() -> void:
    # B until the lamp (gate M2 fear-4): C3's cranks stand in its light, A is C5's
    var zone := Lighting.zone_at(player.position)
    var room := "B"
    if game.done_count() >= 3:                     # after C3 both rooms (M4.5): A's step-3 seats outrank the lamp
        var last := game.last_ab_room()
        room = "" if (zone == "A" or zone == "B" or not _room_open(last)) else last   # a fully shut room seats nothing (M6.0f: B shut stranded it while C4-C5 played in A)
    var next := Thing.pick_seat(lighting.step, lighting.shut, lighting.lamp_on, player.position, room, false, MIN_CUT_M, -player.cam.global_transform.basis.z, zone, _lamp_ahead())
    # riding (M4.6a, GUARDRAILS 3.5): a lamp destination is taken without the seen
    # test - it ramps in, nothing cuts - and the seat then follows the disc every
    # frame (_ride_tick) until the next light change
    if next.get("surface", "") == "lamp":
        if seat.get("surface", "") != "lamp":
            if not seat.is_empty() and _seat_seen(seat):
                return                            # M5.0c: 3.9 holds at the origin - watched, it stays; the due keeps asking
            seat = _lamp_seat_now()
            lighting.seat_omni(seat["pos"] + seat["normal"] * Thing.OMNI_OFF)
            _body_at(seat)
            ride_t0 = clock_t                     # the ride-in ramp starts (M4.6c)
        cut_due = -1.0
        return
    # same seat = same patch: a sun step under one pane moves the omni (gate M2 corr-5)
    var same: bool = not next.is_empty() and not seat.is_empty() and next["room"] == seat["room"] and next["row"] == seat["row"] and next["col"] == seat["col"] and next["surface"] == seat["surface"] and (next["pos"] as Vector3).is_equal_approx(seat["pos"])
    if same or (next.is_empty() and seat.is_empty()):
        cut_due = -1.0
        return
    if (not seat.is_empty() and _seat_seen(seat)) or (not next.is_empty() and _seat_seen(next)):
        return
    ride_t0 = -1.0              # only once the seat really changes (M6.0e: cleared before the seen test, a watched lamp-off snapped the ride-in to full)
    seat = next
    if seat.is_empty():
        lighting.free_seat()
        _body_free()
    else:
        lighting.seat_omni(seat["pos"] + seat["normal"] * Thing.OMNI_OFF)
        _body_at(seat)          # the first cut binds the body (M4.0g); later cuts move it
    cut_due = -1.0

# while riding the seat is the disc edge: refreshed every frame from the camera
# (the omni and, for now, the body with it - M4.6b makes the body walk)
func _ride_tick() -> void:
    if seat.get("surface", "") != "lamp" or player == null or player.cam == null:
        return
    if not lighting.lamp_on:
        return                                    # the lamp off: its light is gone, the seat stays put until the cut rule resolves
    var fresh := _lamp_seat_now()
    seat["pos"] = fresh["pos"]
    seat["room"] = fresh["room"]
    seat["step"] = lighting.step
    if lighting.seat_light != null:
        lighting.seat_light.position = seat["pos"] + Vector3.UP * Thing.OMNI_OFF
    if creature != null:
        creature.walk_to(seat["pos"], clock_dt, player.position)   # the knuckle-walk (M4.6b), round the caretaker (M5.0i)

# how far the disc edge can be: LAMP_AHEAD, or 0.3 m short of the first wall along
# the flattened forward (the seat never leaves the room)
func _lamp_ahead() -> float:
    var cam: Camera3D = player.cam
    var f: Vector3 = -cam.global_transform.basis.z
    f.y = 0.0
    if f.length() < 1e-4:
        return Thing.LAMP_AHEAD
    f = f.normalized()
    var from := Vector3(player.position.x, 0.5, player.position.z)
    var q := PhysicsRayQueryParameters3D.create(from, from + f * (Thing.LAMP_AHEAD + 0.3), 1, [player.get_rid()])
    var hit := get_world_3d().direct_space_state.intersect_ray(q)
    if hit.is_empty():
        return Thing.LAMP_AHEAD
    return minf(Thing.LAMP_AHEAD, from.distance_to(hit["position"]) - 0.3)

# the lamp seat from the camera, kept inside the room: the forward clamp (the
# wall ahead) and a second ray toward the seat point itself (a side wall)
func _lamp_seat_now() -> Dictionary:
    var cam: Camera3D = player.cam
    # over an A crank (M5.0f): while one is the target the disc edge snaps to the
    # view axis, so the body stands on the crank - it reads ` ` and works by feel (3.2)
    var want := Thing.LAMP_SIDE
    if interact != null and interact.target != null and (_a_crank(interact.target) or interact.target == bolt):   # the bolt too (M6.0h): End B's refusal is the mass on it
        want = 0.0
    lamp_side = move_toward(lamp_side, want, LAMP_SIDE_MS * clock_dt)   # 0.8 m in 2 s (M6.0i)
    var d := Thing.lamp_seat(player.position, -cam.global_transform.basis.z, Lighting.zone_at(player.position), lighting.step, _lamp_ahead(), lamp_side)
    var from := Vector3(player.position.x, 0.5, player.position.z)
    var to := Vector3(d["pos"].x, 0.5, d["pos"].z)
    var q := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
    var hit := get_world_3d().direct_space_state.intersect_ray(q)
    if not hit.is_empty():
        var back: Vector3 = (from - to).normalized() * 0.35
        var hp: Vector3 = hit["position"] + back
        d["pos"] = Vector3(hp.x, 0.0, hp.z)
    return d

func riding() -> bool:
    return seat.get("surface", "") == "lamp"

func _a_crank(t: Interactable) -> bool:
    for sh in shutters.get("A", []):
        if sh["crank"] == t:
            return true
    return false

# any point of the capsule (feet to 1.7) in the seat's pane beam at this step;
# a harness --thing seat (row -1) counts within 1 m of its centre
func _in_seat_light() -> bool:
    if seat.is_empty() or riding():
        return false   # M5.0b: a lamp seat doses only by the riding branch (still and lit)
    var p := player.position
    if seat.get("row", -1) < 0:   # a harness --thing seat: within 1 m of its centre
        var sp: Vector3 = seat["pos"]
        return Vector2(p.x - sp.x, p.z - sp.z).length() < 1.0
    if Thing.is_shut(lighting.shut, seat["room"], seat["row"], seat["col"]):
        return false   # M5.0b: lit means open - a shut pane has no beam, whatever the geometry says
    var feet := p.y - 0.9
    for k: float in [0.05, 0.45, 0.85, 1.25, 1.65]:
        if Thing.in_beam(Vector3(p.x, feet + k, p.z), seat["room"], seat["row"], seat["col"], lighting.step):
            return true
    return false

# the bleach (3.10): exposure to max over 1 s, held 2 s with input ignored,
# 0.5 s blank, then the restart - the world unchanged, the lamp as it was
func _bleach_start() -> void:
    bleach_t = clock_t
    death_pos = player.position
    player.frozen = true
    player.look_frozen = true               # the bleach holds the eyes too (M6.0h)
    bleach_hue = 1.0 if game.colour_unlocked() else 0.0   # (c) after (a) (M5.5): the bleach is the hue, and so is its mark

func _bleach_tick() -> void:
    var u := clock_t - bleach_t
    if u < 1.0:
        lighting.bleach_mix = u
    elif u < 3.0:
        lighting.bleach_mix = 1.0
    elif u < 3.5:
        blank.visible = true
        lighting.bleach_mix = 0.0       # the eyes reset under the blank
    else:
        if _at_door_lit():
            _end_b()                    # Ending B (M5.7): no restart - the mark goes on the door
        else:
            _restart()
        return
    # under the hue the flood drains to white and full energy over the 2 s hold (M6.0m,
    # OWNER default taken): the hue first, then the bleach 3.10 promises
    var hue_now := bleach_hue * (1.0 - clampf((u - 1.0) / 2.0, 0.0, 1.0))
    lighting.bleach_flood(player.cam.global_position, lighting.bleach_mix, hue_now)

# Ending B's condition (M5.7): the bleach took the caretaker at the bolt with the
# lamp lit and carried - the door never opens on that light
func _at_door_lit() -> bool:
    return bolt_enabled and lamp_where == "held" and lighting.lamp_on and interact != null and interact.target == bolt

func _end_b() -> void:
    ended = "B"
    end_t = clock_t
    player.look_frozen = false             # the bleach held the eyes; now they may look at the mark (M6.0h)
    blank.visible = false
    lighting.bleach_mix = 0.0
    lighting.bleach_flood(Vector3.ZERO, 0.0)
    cut_due = -1.0
    if creature != null:
        creature.rise = 1.0   # M7.0f: _process returns once ended, so a bolt held inside
    cf_t0 = -1.0              # colour_first's fade would leave the body frozen mid-shrink
    var pz1 := -(HALL_L * 0.5 + WALL) - PLANT_D
    var d := _decal_node(bleach_hue)
    d.rotation_degrees.x = 90.0        # projects along -Z: onto the door's inner face
    d.position = Vector3(clampf(death_pos.x, -0.3, 0.3), 1.7, pz1 + 0.05)   # at eye height, where they stood
    add_child(d)
    decals.append(d.position)
    if creature != null:   # M7.0g: the mark is placed, now the body steps off the bolt so it can be read
        creature.place(Thing.step_aside(creature.global_position, player.cam.global_position), creature.rotation.y)
    _aura_off()
    _dose_down()

# the dose is over with the game (M6.0b): pinned at 3.0 it breathed the credits
# +-48% and held the drone at full gain for ever
func _dose_down() -> void:
    dose = 0.0
    lighting.dose = 0.0

# the reading's warp and tint end with the game (the aura block no longer runs)
func _aura_off() -> void:
    if ascii_mat != null:
        ascii_mat.set_shader_parameter("thing_on", 0.0)
        ascii_mat.set_shader_parameter("hue_mix", 0.0)

func _restart() -> void:
    deaths += 1
    _decal(Vector3(death_pos.x, 0.0, death_pos.z), bleach_hue)
    # the seat, the bite and the body are KEPT through a death (M4.0d, GUARDRAILS
    # 3.2): no light changed, so it has no reason to move - the floor says that
    # patch kills. Only the player resets; the drone fades with dose on its own.
    dose = 0.0
    lighting.dose = 0.0
    lighting.bleach_mix = 0.0
    lighting.bleach_flood(Vector3.ZERO, 0.0)
    bleach_t = -1.0
    blank.visible = false
    player.frozen = false
    player.look_frozen = false
    player.velocity = Vector3.ZERO
    player.position = Vector3(0, 0.95, 0)
    # facing the room you must return to: the chore in progress, the last one when all are done
    var r := game.next_room()
    if r == "":
        r = game.last_room()
    player.look_at_yaw({"A": 90.0, "B": -90.0, "plant": 0.0, "office": 180.0}.get(r, 0.0))
    player.look_at_pitch(0.0)
    lighting.set_zone("hall", true)     # the eyes reset under the blank, no ramp (gate M2 corr-10)
    # a riding death (M5.0e): the disc comes with the lamp, so it rises again 2 m
    # ahead of the new stand, placed under the blank - never walked through walls;
    # lamp off: the seat is kept like any other
    if riding() and lighting.lamp_on:
        seat = _lamp_seat_now()
        lighting.seat_omni(seat["pos"] + seat["normal"] * Thing.OMNI_OFF)
        _body_at(seat)
        ride_t0 = clock_t

# a pale 1 x 1 m mark on the floor where the bleach took the player (3.10):
# the floor's albedo becomes 0.9 there, lit like everything else; they
# accumulate across restarts. `--decal=x,y,z` places one for shots.
func _decal(at: Vector3, hue: float = 0.0) -> void:
    var d := _decal_node(hue)
    d.position = Vector3(at.x, 0.02, at.z)
    add_child(d)
    decals.append(Vector3(at.x, 0.0, at.z))

# the mark itself: a radial bleach, brightest where you stood, gone at the rim
# (gate M2 fear-12); pale grey, or the hue after (a) (M5.5)
func _decal_node(hue: float) -> Decal:
    var d := Decal.new()
    var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
    for y in 32:
        for x in 32:
            var rr := Vector2(x + 0.5 - 16.0, y + 0.5 - 16.0).length() / 16.0
            img.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - rr, 0.0, 1.0)))
    d.texture_albedo = ImageTexture.create_from_image(img)
    d.modulate = Color(0.9, 0.9, 0.9).lerp(Lighting.HUE.lerp(Color(1, 1, 1), 0.5), clampf(hue, 0.0, 1.0))   # the mark takes the hue after (a) (M5.5), lifted toward white (M6.0m: it reads pale, still violet)
    d.albedo_mix = 1.0
    d.size = Vector3(0.8, 0.5, 0.8)
    d.cull_mask = 1
    return d

# M3.0a: the SHOT/SIM line builders moved to tests/harness.gd (Harness); these
# are one-line trampolines (tests/sims.gd calls m.seat_line() directly).
func numbers_line() -> String: return Harness.numbers_line(self)
func patch_line() -> String: return Harness.patch_line(self)
func seat_line() -> String: return Harness.seat_line(self)

# the sun follows chores done and wall-time; re-checked once a second of game clock
func _sync_sun() -> void:
    if lighting != null and game != null:
        lighting.sun_step(Game.step_for(game.done_count(), clock_t))

func _c1_props() -> void: Props._c1_props(self)  # M4.0a: moved to Props._c1_props

func _card_and_sign() -> void:
    card = Props._card(self)
    card["inter"].done.connect(_on_card)
    sign = Props._sign(self)
    sign.done.connect(_on_sign)
    Harness.card_sign_args(self)   # M3.0a: --chores>=6/7 fast-forwards C6/C7 as play would leave them
    _sync_prompts()

func _show_card() -> void:
    if card.is_empty():
        return
    card["card"].visible = true
    card["dark"].visible = true
    if not card["inter"].fired:
        card["inter"].collision_layer = 3

func _lift_card() -> void:
    card["card"].position += Vector3(0.45, 0.0, 0.0)   # set aside on the sheet: D4 shows
    card["inter"].fired = true
    card["inter"].collision_layer = 0

func _on_card() -> void:
    _lift_card()
    game.part("C6")

func _on_sign() -> void:
    game.part("C7")
    bolt_enabled = true
    _sync_prompts()

# "sign" is offered only while the lamp hangs on the desk hook and C7 is next;
# spent otherwise (no prompt, no hold); re-armed only while E is up
func _sync_sign() -> void:
    if sign == null:
        return
    var offer: bool = lamp_where == "desk" and game.next_id() == "C7"
    sign.prompt = "sign" if offer else ""
    sign.collision_layer = 3 if offer else 0   # M5.0a: a spent sign no longer catches the ray; the log (inside its box) is aimed
    if not offer:
        sign.fired = true
        sign.progress = 0.0
    elif not (InputMap.has_action("interact") and Input.is_action_pressed("interact")):
        sign.fired = false

func _bolt() -> void:
    bolt = Props._bolt(self)
    bolt.done.connect(_on_bolt)
    _sync_prompts()

# offered only once C7 is done (bolt_enabled); spent otherwise; re-armed only
# while E is up, same pattern as the hooks and the sign
func _sync_bolt() -> void:
    if bolt == null:
        return
    bolt.prompt = "bolt" if bolt_enabled else ""
    if not bolt_enabled:
        bolt.fired = true
        bolt.progress = 0.0
    elif not (InputMap.has_action("interact") and Input.is_action_pressed("interact")):
        bolt.fired = false

# E 4 s on the bolt: with the lamp lit and carried this is Ending B's door (next
# item) - re-arm and wait; otherwise it is Ending A, dusk (M5.6)
func _on_bolt() -> void:
    if lamp_where == "held" and lighting.lamp_on:
        bolt.reset()   # Ending B (M5.7): the lit case is the next item's
        return
    _end_a()

# Ending A (M5.6): the yard door opens on dusk - the eyes read it, then the
# light goes; the clipboard becomes the credits; ended stops the restart, the
# dose and the cut rule (main._process early-returns while ended != "")
func _end_a() -> void:
    ended = "A"
    end_t = clock_t
    player.frozen = true   # the caretaker stands; this also stops Interact's prompts
    player.look_frozen = false             # but may look up at the dusk (M6.0h)
    for body in yard_door:                 # the four slabs and the bolt's (M6.0h): nothing floats in the opening
        body.visible = false
        body.collision_layer = 0
    bolt.collision_layer = 0
    lighting.set_zone("yard", true)   # M7.0g: SNAP - plant 9.0 -> yard 1.2 over 2 s read as a bleach on the door's first frames
    cut_due = -1.0
    if creature != null:
        creature.rise = 1.0   # M7.0f: _process returns once ended, so a bolt held inside
        creature.place(Thing.step_aside(creature.global_position, player.cam.global_position), creature.rotation.y)   # M7.0g: out of the last frame
    cf_t0 = -1.0              # colour_first's fade would leave the body frozen mid-shrink
    _aura_off()
    _dose_down()

func _end_tick() -> void:
    var u := clock_t - end_t
    var credits_at := 5.0
    if ended == "A":
        lighting.set_zone("yard")   # the player's position would put it back to "plant"
        lighting.end_mix = clampf((u - 3.0) / 2.0, 0.0, 1.0)   # 3 s of dusk read, then 2 s to dark
    else:
        credits_at = 2.0            # B (M5.7): the door and its mark stay in the lamp's light; the list comes sooner
    if u >= credits_at:
        clipboard.visible = true
        clipboard_bg.visible = true
        clipboard.text = game.clipboard_bb("sample")   # the credits: the list, all ticked
    if u >= credits_at + 3.0:
        exit_armed = true                                # a real stop (M6.0b): E quits from here

func _shutters() -> void:
    shutters = Props._shutters(self)
    for room in shutters:
        for row in 3:
            shutters[room][row]["crank"].done.connect(_on_crank.bind(room, row))
            shutters[room][row]["crank"].fired = Thing.is_shut(lighting.shut, room, row, 0)   # M6.0f: a row the harness shut has a spent crank, as play leaves it
    _shutter_meshes()

# a room with any pane still open (M6.0f): the hall's re-pick is confined to the
# last chore's room only while that room can still seat it
func _room_open(r: String) -> bool:
    for row in 3:
        if lighting.shut & Thing.row_mask(r, row) != Thing.row_mask(r, row):
            return true
    return false

# a crank held to the end shuts its row (lighting.shut: one light change); B's
# three are C3, A's three are C5 (game.part ignores a chore out of order)
func _on_crank(room: String, row: int) -> void:
    lighting.shutter(room, row, true)
    game.part("C3" if room == "B" else "C5")

# the slabs follow the state every frame: shut rows are covered; an open row's
# slab reaches across the opening by the crank's hold progress and springs back
# as the hold drains (Interact drains a released hold at 2/s)
func _shutter_meshes() -> void:
    for room in shutters:
        for row in 3:
            var sh: Dictionary = shutters[room][row]
            var e: float = 1.0 if Thing.is_shut(lighting.shut, room, row, 0) else sh["crank"].progress
            var mesh: MeshInstance3D = sh["mesh"]
            mesh.visible = e > 0.01
            mesh.scale.x = maxf(e, 0.001)
            mesh.position = Vector3(sh["edge"] + sh["sign"] * SKY * 0.5 * e, ROOM_H - 0.05, sh["zc"])

func _racks() -> void:
    racks = Props._racks(self)
    for room in racks:
        for row in 3:
            racks[room][row]["inter"].done.connect(_on_sheet.bind(room, row))
    Harness.racks_args(self)   # M3.0a: --chores>=2 / --sheets=A,B throw sheets before the settle

# a sheet over a rack (M4.3): a white surface in the patch - a light change by
# the cut rule (three within a second are one); A's three are C2
func _on_sheet(room: String, row: int) -> void:
    racks[room][row]["sheet"].visible = true
    racks[room][row]["inter"].collision_layer = 0     # a thrown sheet no longer catches the ray (the card behind it can)
    if room == "A" and row == 1:
        _show_card()                                  # the card rests on this sheet (M5.0j)
    lighting.light_changed.emit("sheet")
    if room == "A":
        game.part("C2")

func _hooks() -> void:
    var hs: Array = Props._hooks(self)
    hook_plant = hs[0]
    hook_desk = hs[1]
    hook_plant.done.connect(_on_hook.bind("plant"))
    hook_desk.done.connect(_on_hook.bind("desk"))
    _sync_hooks()

# E on a hook: take the lamp if it hangs there, hang it if it is held (M4.2)
func _on_hook(which: String) -> void:
    if lamp_where == which:
        lamp_where = "held"
    elif lamp_where == "held":
        lamp_where = which
        lighting.lamp(false, player.cam)          # hung lamps are off
    _sync_prompts()

# the hooks' prompts follow the lamp; a hook with nothing to offer is spent
# (no prompt, no hold). Re-armed only while E is up, so a hold never rolls
# from "take" straight into "hang".
func _sync_hooks() -> void:
    for pair in [[hook_plant, "plant"], [hook_desk, "desk"]]:
        var h: Interactable = pair[0]
        var here: bool = lamp_where == pair[1]
        h.prompt = "take" if here else ("hang" if lamp_where == "held" else "")
        h.get_node("lamp").visible = here
        var spent: bool = h.prompt == ""
        if spent:
            h.fired = true
            h.progress = 0.0
        elif not (InputMap.has_action("interact") and Input.is_action_pressed("interact")):
            h.fired = false                       # (the InputMap action exists once Interact is set up; at build it does not)

# the hooks and the sign both key off lamp_where; wherever one is refreshed the
# other should be too, so every call site shares this one entry point
func _sync_prompts() -> void:
    _sync_hooks()
    _sync_sign()
    _sync_bolt()
    _sync_cranks()

# a crank is offered only while its own chore is the next one (M7.0a): B's are
# C3's, A's are C5's. Before that the house cannot be shut - the gate M6 critics
# found a route where B's rows are turned in minute one, so the thing's first
# seat has no open pane and it never spawns at all. A shut row's crank stays
# spent (M6.0f). Re-armed only while E is up, like the hooks and the sign.
func _sync_cranks() -> void:
    if shutters.is_empty() or game == null:
        return
    var next := game.next_id()
    for room in shutters:
        var mine: bool = next == ("C3" if room == "B" else "C5")
        for row in 3:
            var c: Interactable = shutters[room][row]["crank"]
            var shut: bool = Thing.is_shut(lighting.shut, room, row, 0)
            c.prompt = "crank" if (mine and not shut) else ""
            if not mine or shut:
                c.fired = true
                c.progress = 0.0
            elif not (InputMap.has_action("interact") and Input.is_action_pressed("interact")):
                c.fired = false

func _player() -> void:
    player = CharacterBody3D.new()
    player.set_script(load("res://player.gd"))
    player.set("capture_mouse", not harness)
    var col := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.32
    cap.height = 1.8
    col.shape = cap
    player.add_child(col)
    player.position = Vector3(0.3, 0.95, 15.0)  # at the office desk; the doorway frames the hall (M1.6)
    add_child(player)

func _creature() -> void:
    # absent until spawned (GUARDRAILS 3.9: nothing until C2; M2 spawns it). The
    # harness's --thing=x,y,z sets the SEAT (M3.1); the body follows the seat
    if args.has("thing") and seat.is_empty():
        _spawn("B")

# the body under its patch (M3.1): on a floor seat it stands on the patch, off a
# wall seat 1.6 m out along the normal; its front (+X) faces the light - the
# heading of -sun_dir at the seat's step - fixed per seat: it only moves at a
# cut, which by rule nobody sees (3.9). Black, unshaded, only while ASCII is on.
func _body_at(s: Dictionary) -> void:
    if creature == null:
        var c := Node3D.new()
        c.set_script(load("res://creature.gd"))
        add_child(c)
        creature = c
        creature.set_ascii(ascii_layer.visible if ascii_layer != null else true)
    creature.place(Thing.body_pos(s), Thing.body_yaw(int(s.get("step", lighting.step))))   # at rest, mid-step forgotten (M5.0i)

func _body_free() -> void:
    if creature != null:
        creature.queue_free()
        creature = null
    # the aura dies with the body (M4.0b): _process returns before its write
    gate_mix = 0.0
    aura_on = 0.0
    if ascii_mat != null:
        ascii_mat.set_shader_parameter("thing_on", 0.0)
        ascii_mat.set_shader_parameter("hue_mix", 0.0)

func _ascii() -> void:
    ascii_layer = CanvasLayer.new()
    ascii_layer.layer = 10
    var rect := ColorRect.new()
    rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var sm := ShaderMaterial.new()
    sm.shader = load("res://ascii/ascii.gdshader")
    sm.set_shader_parameter("atlas", load("res://ascii/atlas.png"))
    rect.material = sm
    ascii_mat = sm
    set_ascii(false)          # play starts in graphics; Tab (or --ascii=1) turns the reading on
    ascii_layer.add_child(rect)
    add_child(ascii_layer)

func _hud() -> void:
    # layer 11 carries the only text the game has (GUARDRAILS 3.13): the prompt,
    # the clipboard, the start line. No legend - the keys are shown once (M1.6).
    var layer := CanvasLayer.new()
    hud = layer
    layer.layer = 11
    add_child(layer)
    # the clipboard: the only text that changes (GUARDRAILS 3.13); held on C
    var font := SystemFont.new()
    font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
    # a cell-aligned black strip under the clipboard so it reads over a glyph field
    clipboard_bg = ColorRect.new()
    clipboard_bg.color = Color(0, 0, 0)
    clipboard_bg.position = Vector2(56, 96)
    clipboard_bg.size = Vector2(8 * 40, 16 * 8)
    clipboard_bg.visible = false
    layer.add_child(clipboard_bg)
    clipboard = RichTextLabel.new()                # bbcode (M5.3): same face, size and cell position as the Label it replaces
    clipboard.bbcode_enabled = true
    clipboard.scroll_active = false
    clipboard.autowrap_mode = TextServer.AUTOWRAP_OFF
    clipboard.add_theme_font_override("normal_font", font)
    clipboard.add_theme_font_size_override("normal_font_size", 16)
    clipboard.add_theme_constant_override("line_separation", -3)   # M6.0n: seven lines fit the 128 px box
    clipboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
    clipboard.modulate = Color(0.88, 0.88, 0.88)
    clipboard.position = Vector2(64, 96)           # on the cell grid
    clipboard.size = Vector2(8 * 40, 16 * 8)
    clipboard.visible = false
    layer.add_child(clipboard)
    # the start line (3.13): shown once at the desk, fades 2 s after the first move or at 8 s
    start_line = Label.new()
    start_line.add_theme_font_override("font", font)
    start_line.add_theme_font_size_override("font_size", 16)
    start_line.text = "LIGHTFAST   Tab reads   E holds   C the list   L the lamp"   # M6.0g: the lamp's key is said once, here
    start_line.modulate = Color(0.92, 0.92, 0.92)
    start_line.visible = not harness or args.get("start", "0") == "1"
    layer.add_child(start_line)
    start_font = font
    # the blank (3.10): above everything, shown for 0.5 s before the restart. It is
    # ANCHORED, not sized once (M7.0d): play maximises itself and the window is
    # resizable, so a blank cut to the project's 1600x900 left live world showing in
    # an L round it on any bigger screen - at every death
    var blank_layer := CanvasLayer.new()
    blank_layer.layer = 12
    add_child(blank_layer)
    blank = ColorRect.new()
    blank.color = Color(0, 0, 0)
    blank.set_anchors_preset(Control.PRESET_FULL_RECT)
    blank.visible = false
    blank_layer.add_child(blank)
    get_viewport().size_changed.connect(_fit_hud)
    _fit_hud()

# the start line re-centres on the window it is shown in (M7.0d)
func _fit_hud() -> void:
    if start_line == null or start_font == null:
        return
    var vp := get_viewport().get_visible_rect().size
    var w := start_font.get_string_size(start_line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
    start_line.position = Vector2(floor((vp.x - w) * 0.5 / 8.0) * 8.0, floor(vp.y * 0.5 / 16.0) * 16.0 + 96.0)

# advance the clock, then feed the thing's screen position and apparent size to the shader
func _process(dt: float) -> void:
    if harness and Harness.watchdog_tick(self):   # M3.0a: counts frames, quits a hung harness run
        return
    clock_dt = ((1.0 / 60.0) if clock_fixed else dt) if clock_running else 0.0
    if clock_running:
        clock_t += clock_dt
    if ascii_mat != null:
        ascii_mat.set_shader_parameter("t", clock_t)
    if creature != null:
        creature.t = clock_t
    if lighting != null and player != null:
        lighting.set_zone("yard" if ended == "A" else Lighting.zone_at(player.global_position))   # the ending owns the zone (T100: plant/yard flipped every frame and the ramp never ran)
        lighting.breath_t = clock_t
        lighting.breath_dist = player.cam.global_position.distance_to(seat["pos"]) if (not seat.is_empty() and player.cam != null) else INF
        lighting.tick(clock_dt)
        if audio != null:
            audio.drone_tick(lighting.breath_amp(), clock_dt, seat.get("pos") if (not seat.is_empty() and ended == "") else null)   # with any seat, DIM or BLACK (M6.0c: the body's presence is not the sound's); null once ended (M6.0b)
            if lighting.zone != _audio_zone:      # only on a change (M4.0j)
                _audio_zone = lighting.zone
                audio.set_zone(lighting.zone)
    if ended != "":
        _end_tick()
        if exit_armed and not harness and Input.is_action_just_pressed("interact"):   # M7.0f: E only - Esc frees the mouse (player.gd) and must not also quit
            get_tree().quit()
        return
    if int(clock_t) != _last_step_check:
        _last_step_check = int(clock_t)
        _sync_sun()
    if cut_due >= 0.0 and clock_t >= cut_due:
        _try_cut()
    _ride_tick()
    # the hue (3.14 b, M5.4): while riding with the lamp lit after the gate has
    # opened, hue_mix ramps up over HUE_S; otherwise back down. The probe forces it.
    var want_hue := 1.0 if (riding() and lighting.lamp_on and game.colour_unlocked()) else 0.0
    hue_mix = 1.0 if lighting.hue_lamp else move_toward(hue_mix, want_hue, clock_dt / HUE_S)
    if not cf_done and want_hue > 0.0:            # colour before shape, once (M6.0n)
        cf_done = true
        cf_t0 = clock_t
    lighting.seat_hue(hue_mix)                    # the bite's rim shows it by the omni's complement
    # dose (3.10): only its light counts, it decays while it is absent; the bleach freezes the count
    if bleach_t < 0.0:
        var still: bool = Vector2(player.velocity.x, player.velocity.z).length() < 0.1
        dose = Thing.dose_step(dose, not seat.is_empty() and _in_seat_light(), riding() and still and lighting.lamp_on, clock_dt)   # riding doses only while the lamp is lit
        lighting.dose = dose
        if dose >= Thing.DOSE_MAX and ended == "":
            _bleach_start()
    if bleach_t >= 0.0:
        _bleach_tick()
    if start_line != null and start_line.visible:
        if start_fade_t < 0.0 and (player.has_moved or Input.is_anything_pressed() or clock_t >= 8.0):
            start_fade_t = clock_t
        if start_fade_t >= 0.0:
            var a := 1.0 - (clock_t - start_fade_t) / 2.0
            start_line.modulate.a = maxf(a, 0.0)
            if a <= 0.0:
                start_line.visible = false
    if hook_plant != null and not Input.is_action_pressed("interact"):
        _sync_prompts()
    if not shutters.is_empty():
        _shutter_meshes()
    if lamp_where == "held" and Input.is_action_just_pressed("lamp") and not player.frozen:
        lighting.lamp(not lighting.lamp_on, player.cam)   # L: the carried lamp lit or off (M4.2)
    player.lamp_lit = lighting.lamp_on
    if walk_until > 0.0:                                   # --walk=SEC (M4.6b): W held from t=0
        var k := InputEventKey.new()
        k.physical_keycode = KEY_W
        k.keycode = KEY_W
        k.pressed = clock_t < walk_until
        Input.parse_input_event(k)
        if clock_t >= walk_until:
            walk_until = 0.0
    if clipboard != null and game != null:
        var want_clip: bool = Input.is_action_pressed("clipboard") or clock_t < clip_auto_until   # M6.0n: it rises by itself once after C5
        if want_clip and not clipboard.visible and audio != null:
            audio.play("pencil")              # the clipboard comes up: the pencil (M3.5)
        clipboard.visible = want_clip
        if clip_shown and not clipboard.visible and game.done_count() >= 5:
            game.colour_seen = true       # the gate's second key (M5.0h), on the release (M6.0n): the word was read before anything tints
        clip_shown = clipboard.visible
        clipboard_bg.visible = clipboard.visible
        if clipboard.visible:
            clipboard.text = game.clipboard_bb("sample")   # M5.3: one word takes the hue after C5
    if ascii_mat == null or player == null or player.cam == null:
        return
    if creature == null:
        gate_mix = 0.0
        aura_on = 0.0
        ascii_mat.set_shader_parameter("thing_on", 0.0)
        ascii_mat.set_shader_parameter("hue_mix", 0.0)
        return
    var cam: Camera3D = player.cam
    var centre := creature.global_position + Vector3(0, 1.6, 0)
    # the aura exists only where the thing could be seen: inside the frustum and
    # with nothing between the eye and it (GUARDRAILS 3.8); the player capsule is
    # excluded because the camera sits inside it. Seen/unseen never snaps: a gate
    # ramps over >= 2 s on the one clock (M4.0b), so a jamb or the frame edge
    # fades the warp instead of cutting it
    var seen := cam.is_position_in_frustum(centre)
    if seen:
        var q := PhysicsRayQueryParameters3D.create(cam.global_position, centre, 1, [player.get_rid()])
        seen = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
    gate_mix = move_toward(gate_mix, 1.0 if seen else 0.0, clock_dt / GATE_S)
    # the lag is in the world (M4.0b): the aura follows the body's point 0.3 s
    # behind and is unprojected every frame, so a head turn never drags it
    aura_world = centre if gate_mix <= 0.0 else Thing.lag3(aura_world, centre, clock_dt)
    if gate_mix <= 0.0 and ab_force < 0.0:
        aura_on = 0.0
        ascii_mat.set_shader_parameter("thing_on", 0.0)
        ascii_mat.set_shader_parameter("hue_mix", 0.0)
        return
    if not cam.is_position_behind(aura_world):
        aura_px = cam.unproject_position(aura_world)       # else the last px holds
    # radius from depth, not a second unproject: AURA_M metres at the thing's distance
    var depth := maxf(0.2, cam.global_position.distance_to(aura_world))
    var vh := float(get_viewport().get_visible_rect().size.y)
    var r := AURA_M / depth * (vh * 0.5) / tan(deg_to_rad(cam.fov * 0.5))
    aura_r = maxf(40.0, r)
    # presence: the seeded dropout schedule (3.8) x the gate; --ab forces it for A/B pairs
    var ride := Thing.ride_mix(clock_t, ride_t0)
    if cf_t0 >= 0.0:
        ride *= Thing.colour_first(clock_t - cf_t0)   # the shape steps aside while the colour arrives (M6.0n)
    creature.rise = ride
    aura_on = Thing.presence(clock_t, seed, presence_hint) * gate_mix * ride if ab_force < 0.0 else ab_force
    ascii_mat.set_shader_parameter("thing_px", aura_px)
    ascii_mat.set_shader_parameter("thing_r", aura_r)
    ascii_mat.set_shader_parameter("thing_on", aura_on)
    ascii_mat.set_shader_parameter("hue_mix", hue_mix * gate_mix)   # the tint follows the seen gate, not the dropouts (M5.4)

func _interact() -> void:
    interact = Interact.new()
    interact.name = "Interact"
    add_child(interact)
    interact.setup(self, player.cam, hud)
    if args.has("testbox"):
        _test_box(player.position + Vector3(0, 0.65, -1.5))

# M3.0a: the sims/shots test box moved to tests/harness.gd (Harness); tests/sims.gd
# calls m._test_box(...) directly, so the trampoline keeps that name.
func _test_box(at: Vector3) -> Interactable: return Harness.test_box(self, at)

# Tab reads, never acts (GUARDRAILS 3.11): graphics shows the bite, ASCII the body
func set_ascii(on: bool) -> void:
    ascii_layer.visible = on
    if creature != null:
        creature.set_ascii(on)

func _unhandled_input(e: InputEvent) -> void:
    if e is InputEventKey and e.pressed and e.keycode == KEY_TAB:
        set_ascii(not ascii_layer.visible)


# M3.0a/M3.0c: the --shot/--sim harness (screenshot capture, in-engine sims,
# and the SHOT/SIM line builders) moved to tests/harness.gd (Harness); these
# are one-line trampolines with the same names and signatures.
func _maybe_screenshot() -> void: Harness.shoot(self)
func _run_sim(name: String) -> void: await Harness.run_sim(self, name)
func _capture(name: String) -> void: Harness.capture(self, name)
