extends Node
class_name Lighting
# Owns every light in the building: the sun, the environment, the camera
# attributes, later the shutters and the lamp. Nothing else touches light.
# Auto-exposure is OFF: each zone has a fixed exposure, ramped >= 2 s when the
# player crosses into it, so "eyes failing" near the thing can be authored
# rather than fought (GUARDRAILS 3.3). Emits light_changed for the thing.

signal light_changed(kind: String)

# sun table (REF Specs, M1.4 refines): elevation and energy per step
const ELEV := [-62.0, -52.0, -42.0, -32.0, -22.0, -12.0]
const YAW := 28.0            # the sun's heading; light travels toward -X, -Z
const ENERGY := [2.2, 2.1, 2.0, 1.8, 1.6, 1.0]
# the sky and ambient fall with the sun, so bounce light dies too (pillar 2)
const SKY := [1.0, 0.85, 0.70, 0.55, 0.40, 0.25]
# the eye adapts a little as the day goes - never enough to bring the light back
const STEP_EXP := [1.0, 1.1, 1.25, 1.5, 2.2, 3.0]
const RAMP_S := 2.0

# per-zone exposure multipliers at sun step 0, tuned (M0.6) to match the
# auto-exposure references shots/ref_v1|v2|v4_gfx.png within 15% per 3x3 cell
# M1.0c (2026-09-03): rooms 1.0 -> sun patches at level 8-9, 14.6% clip inside them,
# no runaway (0.5 -> 0% clip); hall 3.0 -> doorway view from the hall clips ~9%
# (2.5 gave 6.9% but no hall wall read at all; 5.0 gave 18.9%). Office, plant and
# yard are placeholders until those rooms exist (M4.1, M5.6). Office 4.0 (M1.2): 1x1 pane, clip 0.6%, levels 1.7-3.8.
var zone_exposure := {"hall": 3.0, "A": 1.0, "B": 1.0, "office": 4.0, "plant": 3.0, "yard": 0.4}

var sun: DirectionalLight3D
var env: Environment
var we: WorldEnvironment
var ca: CameraAttributesPractical
var step := 0
var zone := ""
var lamp_on := false
var seat_light: OmniLight3D = null   # the DIM: a negative, shadowed omni over the thing's seat
const SEAT_ENERGY := 4.0
const SEAT_RANGE := 1.1       # M3.0k: with the omni 0.6 m off the seat the bite is a 0.92 m disc inside its patch (1.2 spilled 17 cells at V6)
const SEAT_ATTEN := 2.0
# exposure has one writer: _base_exp ramps between zone/step targets; tick()
# multiplies in `breath` (1.0 until M2.3) and writes the camera attribute
var _base_exp := 1.0
var breath := 1.0
# breathing (GUARDRAILS 3.3): the exposure loops with period BREATH_S; the
# amplitude is a little proximity and mostly dose - shade near it is felt, its
# light is what breathes. main.gd feeds
# breath_t (the game clock) and breath_dist (camera -> seat, INF with no seat).
const BREATH_S := 2.4
const BREATH_PROX := 0.05     # felt within BREATH_RANGE: <= 5% (gate M2 fear-3)
const BREATH_DOSE := 0.15     # breathes with dose: the tell points at its light, not at distance
const BREATH_RANGE := 6.0
var breath_t := 0.0
var breath_dist := INF
var dose := 0.0
# the bleach (3.10): main.gd drives bleach_mix 0 -> 1 over 1 s and holds it; the
# one exposure writer below lerps to BLEACH_EXP (LOG T38: the one 60-frame ramp
# allowed against GUARDRAILS 5)
const BLEACH_EXP := 8.0
var bleach_mix := 0.0
# the flood (3.10, T49): exposure alone cannot whiten a dark hall (step 5, x72:
# gfx mean 0.23), so the bleach also pours light from the eye - an unshadowed
# omni at the camera, energy FLOOD_ENERGY x bleach_mix, freed with the blank
const FLOOD_ENERGY := 16.0
var flood: OmniLight3D
var _ramp_from := 1.0
var _ramp_to := 1.0
var _ramp_t := RAMP_S
var end_mix := 0.0    # Ending A (M5.6): 0 -> 1 takes the exposure to black after the dusk read

func build(parent: Node3D, args: Dictionary) -> void:
    # --exp=hall:1.2,A:0.8 overrides zone exposure (harness tuning)
    if args.has("exp"):
        for pair in (args["exp"] as String).split(","):
            var kv := pair.split(":")
            if kv.size() == 2 and zone_exposure.has(kv[0]):
                zone_exposure[kv[0]] = float(kv[1])
    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(ELEV[0], YAW, 0)
    sun.light_energy = ENERGY[0]
    sun.light_color = Color(1, 1, 1)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 60.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    parent.add_child(sun)

    env = Environment.new()
    var sky := Sky.new()
    var skymat := ProceduralSkyMaterial.new()
    # greyscale sky so the skylights admit no colour
    skymat.sky_top_color = Color(0.50, 0.50, 0.50)
    skymat.sky_horizon_color = Color(0.78, 0.78, 0.78)
    skymat.ground_bottom_color = Color(0.20, 0.20, 0.20)
    skymat.ground_horizon_color = Color(0.45, 0.45, 0.45)
    skymat.sun_angle_max = 8.0
    sky.sky_material = skymat
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.ambient_light_sky_contribution = 1.0
    env.sdfgi_enabled = true
    env.sdfgi_use_occlusion = true
    env.sdfgi_bounce_feedback = 0.9
    env.sdfgi_energy = 1.4
    env.sdfgi_min_cell_size = 0.12
    env.sdfgi_cascades = 4
    env.ssao_enabled = true
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.tonemap_exposure = 1.0
    env.volumetric_fog_enabled = true
    env.volumetric_fog_density = 0.006
    env.volumetric_fog_albedo = Color(0.9, 0.9, 0.9)
    env.volumetric_fog_emission_energy = 0.0
    env.volumetric_fog_length = 48.0
    we = WorldEnvironment.new()
    we.environment = env
    ca = CameraAttributesPractical.new()
    ca.auto_exposure_enabled = false
    ca.exposure_multiplier = _base_exp
    we.camera_attributes = ca
    parent.add_child(we)

# monotonic: light never returns (pillar 2); emits only when the step changes
func sun_step(n: int) -> void:
    var s := clampi(n, 0, ELEV.size() - 1)
    if s <= step:
        return
    step = s
    sun.rotation_degrees.x = ELEV[step]
    sun.light_energy = ENERGY[step]
    env.background_energy_multiplier = SKY[step]
    env.ambient_light_energy = SKY[step]
    if zone != "":
        _retarget(false)
    light_changed.emit("sun")

# the direction light travels at a step: the same Euler the DirectionalLight3D uses (YXZ)
static func sun_dir(n: int) -> Vector3:
    var k := clampi(n, 0, ELEV.size() - 1)
    return Basis.from_euler(Vector3(deg_to_rad(ELEV[k]), deg_to_rad(YAW), 0.0)) * Vector3.FORWARD

func target_exposure() -> float:
    return zone_exposure[zone] * STEP_EXP[step]

func _retarget(snap: bool) -> void:
    _ramp_from = _base_exp
    _ramp_to = target_exposure()
    _ramp_t = 0.0
    if snap:
        _ramp_t = RAMP_S
        _base_exp = _ramp_to
        ca.exposure_multiplier = lerpf(_base_exp * breath, bleach_target(), bleach_mix) * (1.0 - end_mix)

# which zone a world position is in; the hall is everything the rooms are not
static func zone_at(p: Vector3) -> String:
    if p.x < -1.8: return "A"
    if p.x > 1.8: return "B"
    if p.z > 12.3: return "office"
    if p.z < -12.3: return "plant"
    return "hall"

func set_zone(z: String, snap: bool = false) -> void:
    if z == zone and not snap:
        return
    var first := zone == ""
    zone = z
    _retarget(snap or first)     # the first assignment (boot) snaps; only changes ramp

# called by main.gd with the one clock's delta, so the ramp is fixed-step under the harness
func tick(dt: float) -> void:
    if _ramp_t < RAMP_S:
        _ramp_t = minf(_ramp_t + dt, RAMP_S)
        _base_exp = lerpf(_ramp_from, _ramp_to, _ramp_t / RAMP_S)
    breath = 1.0 + breath_amp() * sin(TAU * breath_t / BREATH_S)
    ca.exposure_multiplier = lerpf(_base_exp * breath, bleach_target(), bleach_mix) * (1.0 - end_mix)

# the bleach is relative to the eye (gate M2 corr-3): 8x the current base, never
# below BLEACH_EXP - the hall at step 5 sits at 9.0 already
func breath_amp() -> float:
    var prox := clampf(1.0 - breath_dist / BREATH_RANGE, 0.0, 1.0)
    return BREATH_PROX * prox + BREATH_DOSE * dose

func bleach_target() -> float:
    var white := maxf(BLEACH_EXP, 8.0 * _base_exp)
    # under the hue (M5.5) the eyes open less: x8 clipped every pixel white and the
    # colour with it (T99: gfx mean 1.000 at any flood energy); HUE_EXP keeps the frame
    # below clip so the flood's colour is what the bleach is
    return lerpf(white, HUE_EXP * _base_exp, flood_hue)

const HUE_EXP := 1.0
var flood_hue := 0.0   # the current bleach's hue share, set by bleach_flood; 0 between bleaches

# COLOUR (c) (M5.5, 3.14): after (a) the bleach is the hue - the flood's colour
# lerps to HUE by `hue`, and its energy scales by FLOOD_HUE_SCALE there so the
# frame keeps its colour instead of clipping to white (gfx mean <= 0.9, T99)
const FLOOD_HUE_SCALE := 0.06

func bleach_flood(at: Vector3, mix: float, hue: float = 0.0) -> void:
    flood_hue = clampf(hue, 0.0, 1.0) if mix > 0.0 else 0.0
    if mix <= 0.0:
        if flood != null:
            flood.queue_free()
            flood = null
        return
    if flood == null:
        flood = OmniLight3D.new()
        flood.shadow_enabled = false
        flood.omni_range = 40.0
        flood.omni_attenuation = 0.25
        flood.light_indirect_energy = 0.0
        flood.light_volumetric_fog_energy = 0.0
        get_parent().add_child(flood)
    flood.position = at
    flood.light_color = Color(1, 1, 1).lerp(HUE, clampf(hue, 0.0, 1.0))
    flood.light_energy = FLOOD_ENERGY * mix * lerpf(1.0, FLOOD_HUE_SCALE, clampf(hue, 0.0, 1.0))

# The DIM (GUARDRAILS 3.2): a negative shadowed omni 1.2 m off the seat along its
# normal eats part of the lit patch - a hole with no caster. Bounce is left alone
# (indirect energy 0: Godot injects lights into SDFGI without the sign).
func seat_omni(p: Vector3) -> void:
    if seat_light == null:
        seat_light = OmniLight3D.new()
        seat_light.light_negative = true
        seat_light.shadow_enabled = true
        seat_light.omni_range = SEAT_RANGE
        seat_light.omni_attenuation = SEAT_ATTEN
        seat_light.light_indirect_energy = 0.0
        seat_light.light_volumetric_fog_energy = 0.0
        seat_light.light_energy = SEAT_ENERGY
        get_parent().add_child(seat_light)
    seat_light.position = p

# the bite's colour (M5.0h, 3.14): a negative light subtracts, so its colour is
# the hue's complement - what remains at the bite's rim is the hue itself. White
# (no colour) until hue_mix > 0; no bounce clause (indirect energy is 0)
const BITE_COMP := Color(0.39, 0.42, 0.30)   # the bite's colour under the hue (M6.0m): a MEASURED complement - see LOG T115

func seat_hue(mix: float) -> void:
    if seat_light != null:
        seat_light.light_color = Color(1, 1, 1).lerp(BITE_COMP, clampf(mix, 0.0, 1.0))

func free_seat() -> void:
    if seat_light != null:
        seat_light.queue_free()
        seat_light = null

# shutters and the lamp are built in M4; the light-change events exist now
# the shutter state's one home (M4.0h): 18 bits, Thing.bit; a crank sets or
# clears its row's three bits; the slabs themselves are M4.4
var shut := 0

func shutter(room: String, row: int, on: bool) -> void:
    var mask := Thing.row_mask(room, row)
    var before := shut
    shut = (shut | mask) if on else (shut & ~mask)
    if shut != before:
        light_changed.emit("shutter")

# the lamp (M4.2, REF Specs): a shadowed SpotLight3D, 22 deg, energy 3, mounted on
# the camera while carried - the 2nd shadowed positional light (GUARDRAILS 5 cap;
# the seat omni is the 1st). `mount` = the camera; null (tests) parents it here.
const LAMP_DEG := 22.0
const LAMP_E := 3.0
var lamp_light: SpotLight3D

const HUE := Color(0.72, 0.58, 0.92)   # REF Q4: the one hue (pale violet), M5.3+; never red
var hue_lamp := false                  # harness --hue=1 only: the lamp takes HUE to prove the chroma pipe (M5.0g); never in play

func lamp(on: bool, mount: Node3D = null) -> void:
    if lamp_light == null:
        lamp_light = SpotLight3D.new()
        lamp_light.shadow_enabled = true
        lamp_light.spot_angle = LAMP_DEG
        lamp_light.spot_range = 12.0
        lamp_light.light_energy = LAMP_E
        lamp_light.light_volumetric_fog_energy = 0.0
        (mount if mount != null else self).add_child(lamp_light)
    elif mount != null and lamp_light.get_parent() != mount:
        lamp_light.get_parent().remove_child(lamp_light)
        mount.add_child(lamp_light)
    lamp_light.visible = on
    lamp_light.light_color = HUE if hue_lamp else Color(1, 1, 1)
    if on != lamp_on:
        lamp_on = on
        light_changed.emit("lamp")
