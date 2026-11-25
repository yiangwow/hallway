extends RefCounted
class_name Thing
# The thing's geometry and rules, pure (no scene references) so tests run
# headless. Rooms A (x<0) and B (x>0) are mirror images; the skylight is a
# 3x3 grid of panes; a "seat" is where a pane's beam lands at a sun step.
# Constants duplicated from main.gd on purpose: this file must not load the scene.

const HALL_W := 3.0
const WALL := 0.3
const ROOM := 9.0
const ROOM_H := 6.0
const SKY := 6.0
const MULLION := 0.12
const REACH_Y := 1.7          # a wall seat is reachable if its centre is at or below this

static func room_sign(room: String) -> float:
    return -1.0 if room == "A" else 1.0

static func room_cx(room: String) -> float:
    return room_sign(room) * (HALL_W * 0.5 + WALL + ROOM * 0.5)

# inner volume of a room; empty (zero size) for the hall, plant room and office
# (M5.0i: a lamp seat there was being clamped into B's box)
static func room_box(room: String) -> AABB:
    var xin := HALL_W * 0.5 + WALL
    var xout := xin + ROOM
    if room == "A":
        return AABB(Vector3(-xout, 0, -ROOM * 0.5), Vector3(ROOM, ROOM_H, ROOM))
    if room == "B":
        return AABB(Vector3(xin, 0, -ROOM * 0.5), Vector3(ROOM, ROOM_H, ROOM))
    return AABB()

# the 3x3 panes as x/z rects at y = ROOM_H. row 0 = -z; col 0 = nearest the hall.
static func pane_rect(room: String, row: int, col: int) -> Rect2:
    var k := SKY * 0.5
    var m := MULLION * 0.5
    var edges := [-k, -1.0 - m, -1.0 + m, 1.0 - m, 1.0 + m, k]   # opening split by the two mullions
    var z0: float = edges[row * 2]
    var z1: float = edges[row * 2 + 1]
    # columns run away from the hall: for B that is +x, for A it is -x
    var c := col if room == "B" else 2 - col
    var x0: float = edges[c * 2] + room_cx(room)
    var x1: float = edges[c * 2 + 1] + room_cx(room)
    return Rect2(Vector2(x0, z0), Vector2(x1 - x0, z1 - z0))

static func pane_centre(room: String, row: int, col: int) -> Vector3:
    var r := pane_rect(room, row, col)
    var c := r.get_center()
    return Vector3(c.x, ROOM_H, c.y)

# bit index for the 18-bit shutter mask
static func bit(room: String, row: int, col: int) -> int:
    return (9 if room == "B" else 0) + row * 3 + col

# where the pane's beam lands at a sun step: the first hit of the floor or a
# wall of the room, or {} if it leaves the room first
static func seat(room: String, row: int, col: int, step: int) -> Dictionary:
    var d := Lighting.sun_dir(step)
    if d.y >= 0.0:
        return {}
    var o := pane_centre(room, row, col)
    var box := room_box(room)
    var lo := box.position
    var hi := box.position + box.size
    var best_t := o.y / -d.y                      # the floor
    var normal := Vector3.UP
    var surface := "floor"
    # walls in the direction of travel
    if d.x != 0.0:
        var wx := lo.x if d.x < 0.0 else hi.x
        var t := (wx - o.x) / d.x
        if t > 0.0 and t < best_t:
            best_t = t
            normal = Vector3.RIGHT if d.x < 0.0 else Vector3.LEFT
            surface = "wall"
    if d.z != 0.0:
        var wz := lo.z if d.z < 0.0 else hi.z
        var t := (wz - o.z) / d.z
        if t > 0.0 and t < best_t:
            best_t = t
            normal = Vector3.BACK if d.z < 0.0 else Vector3.FORWARD
            surface = "wall"
    var p := o + d * best_t
    if not box.grow(0.01).has_point(p):
        return {}
    return {"room": room, "row": row, "col": col, "step": step, "pos": p, "normal": normal, "surface": surface}

# the lowest point of a wall seat's patch: the pane's corners carried down the
# beam to the wall plane (unclamped: below 0 means the patch runs onto the floor)
static func patch_foot(s: Dictionary) -> float:
    if s.is_empty() or s["surface"] == "floor" or s.get("row", -1) < 0:
        return 0.0
    var n: Vector3 = s["normal"]
    var pos: Vector3 = s["pos"]
    var d := Lighting.sun_dir(s.get("step", 0))
    var r := pane_rect(s["room"], s["row"], s["col"])
    var pc := pane_centre(s["room"], s["row"], s["col"])
    var foot := INF
    for cx: float in [r.position.x, r.end.x]:
        for cz: float in [r.position.y, r.end.y]:
            var c := Vector3(cx, pc.y, cz)
            var t := 0.0
            if absf(n.x) > 0.5 and d.x != 0.0:
                t = (pos.x - c.x) / d.x
            elif absf(n.z) > 0.5 and d.z != 0.0:
                t = (pos.z - c.z) / d.z
            foot = minf(foot, (c + d * t).y)
    return foot

# reachable = its beam passes below REACH_Y inside the room (REF): a floor seat,
# or a wall patch whose foot is at or below REACH_Y (M3.0l: the foot, not the centre)
static func reachable(s: Dictionary) -> bool:
    if s.is_empty():
        return false
    return s["surface"] == "floor" or patch_foot(s) <= REACH_Y

# --- rules -------------------------------------------------------------------

const DOOR_HALF_Z := 0.8
const DOOR_H := 2.4

static func is_shut(shut: int, room: String, row: int, col: int) -> bool:
    return (shut >> bit(room, row, col)) & 1 == 1

# a whole row's three bits (a shutter row is one crank)
static func row_mask(room: String, row: int) -> int:
    return 7 << bit(room, row, 0)

# `--shut=A:110,B:001`: per room three row chars (row 0 = -z first), 1 = shut
static func shut_bits(spec: String) -> int:
    var bits := 0
    for part in spec.split(","):
        var kv := part.strip_edges().split(":")
        if kv.size() != 2 or (kv[0] != "A" and kv[0] != "B"):
            continue
        for row in mini(3, kv[1].length()):
            if kv[1][row] == "1":
                bits |= row_mask(kv[0], row)
    return bits

# the props the chores hang on, as a table the headless tests can read (M4.0h):
# racks stand on the step-1 floor patches of the middle column; a B crank stands
# at its row's step-2 seat (in the beam), an A crank by the door (A's step-4
# seats are all high on the walls)
static func rack_pos(room: String, row: int) -> Vector3:
    var s := seat(room, row, 1, 1)
    if not s.is_empty() and s["surface"] == "floor":
        return Vector3(s["pos"].x, 0.0, s["pos"].z)
    return Vector3(room_sign(room) * 6.3, 0.0, -2.0 + 2.0 * row)   # the row's beam hits a wall at step 1: the rack stands mid-room

const CRANK_REACH := 0.8

# B's cranks stand in step-2 light (C3): row 2 at pane r2c0's wall seat, row 1 at
# r1c2's (the thing's first seat - the crossing 3.12 exists for), row 0 - whose
# step-2 beam lands 2.5 m up the -Z wall - as a floor post in r2c1's floor patch. A's sit on
# the hall-side wall by the door (C5 is done with the lamp).
static func _crank_pane(row: int) -> Array:
    if row == 0:
        return [2, 1]
    if row == 1:
        return [1, 2]      # r1c0's seat hugs the hall wall, r1c1's stand is the row-1 rack; r1c2 is the thing's own first seat (C3 crosses its light)
    return [2, 0]

static func crank_pos(room: String, row: int) -> Vector3:
    if room == "B":
        var pr: Array = _crank_pane(row)
        var s := seat("B", pr[0], pr[1], 2)
        if not s.is_empty():
            return s["pos"] if s["surface"] == "wall" else s["pos"] + Vector3(0, 0.8, 0)
    return Vector3(room_sign(room) * 1.85, 1.2, 1.4 + 1.0 * row)   # A: a panel of three on the hall-side wall beside the door (z 0 is the doorway itself)

# the crank's facing normal: the hand stands CRANK_REACH out along it, into the room
static func crank_normal(room: String, row: int) -> Vector3:
    if room == "B":
        var pr: Array = _crank_pane(row)
        var s := seat("B", pr[0], pr[1], 2)
        if not s.is_empty():
            return s["normal"] if s["surface"] == "wall" else Vector3.BACK
    return Vector3(room_sign(room), 0, 0)

static func crank_stand(room: String, row: int) -> Vector3:
    return crank_pos(room, row) + crank_normal(room, row) * CRANK_REACH

# A's cranks are worked with the lamp (GUARDRAILS 3.12: an open pane's beam at its
# step, or the lamp); B's stand in their row's step-2 beam
static func crank_needs_lamp(room: String) -> bool:
    return room == "A"

# Where it sits: the nearest reachable seat under an open pane, else the lamp's
# disc edge if the lamp is on, else the nearest open seat of any kind, else {}.
# `room` restricts the candidates ("" = both rooms).
# far (M4.0f): the spawn ranks reachable open seats by their distance from the
# room's doorway, farthest first - the first sight is small and across the room.
# min_d: a re-pick skips reachable seats closer than that to the player - it is
# never at your back when you turn. Nothing reachable beyond -> lamp/open/{} as before.
# the lamp seat (M4.6a, GUARDRAILS 3.5): the disc edge LAMP_AHEAD m along the
# flattened forward, on the floor - a full seat dict so every reader of a seat
# (seat_line, patch_points, body_pos, breath_dist, in-light) needs no special case
const LAMP_AHEAD := 2.0

# ride-in (M4.6c, GUARDRAILS 3.5): the aura and the body ramp in over 2 s from the
# frame the lamp seat is taken (t0); t0 < 0 = not riding = 1
# colour before shape (M6.0n, 3.14 b): the first time the hue comes while riding,
# the body's rise and the aura's presence go down over 2 s as the tint rises,
# stay away 2 s (colour alone, no shape), then come back over 2 s - once
static func colour_first(u: float) -> float:
    if u < 0.0:
        return 1.0
    if u < 2.0:
        return 1.0 - u / 2.0
    if u < 4.0:
        return 0.0
    if u < 6.0:
        return (u - 4.0) / 2.0
    return 1.0

static func ride_mix(t: float, t0: float) -> float:
    return clampf((t - t0) / 2.0, 0.0, 1.0) if t0 >= 0.0 else 1.0

const LAMP_SIDE := 0.8       # off the view axis, to the left: the mass straddles the 22-deg cone edge (M5.0f) - in the light, in the corner of the eye, the view usable (T79: 1.2 sat outside the cone)

static func lamp_seat(cam_pos: Vector3, cam_fwd: Vector3, zone: String, step: int, ahead: float = LAMP_AHEAD, side: float = LAMP_SIDE) -> Dictionary:
    var f := Vector3(cam_fwd.x, 0.0, cam_fwd.z)
    f = f.normalized() if f.length() > 1e-4 else Vector3.FORWARD
    var left := f.rotated(Vector3.UP, PI * 0.5)
    var pos := Vector3(cam_pos.x, 0.0, cam_pos.z) + f * clampf(ahead, 0.6, LAMP_AHEAD) + left * side
    return {"room": zone, "row": -1, "col": -1, "step": step, "pos": pos, "normal": Vector3.UP, "surface": "lamp"}

static func pick_seat(step: int, shut: int, lamp_on: bool, player_pos: Vector3, room: String = "", far: bool = false, min_d: float = 0.0, cam_fwd: Vector3 = Vector3.FORWARD, zone: String = "", ahead: float = LAMP_AHEAD) -> Dictionary:
    if room != "" and room != "A" and room != "B":
        return {}                                 # only A and B have panes (gate M2 corr-6)
    var rooms := ["A", "B"] if room == "" else [room]
    var best_reach := {}
    var best_reach_d := INF
    var best_far := -INF
    var best_open := {}
    var best_open_d := INF
    for r in rooms:
        var door := Vector3(room_sign(r) * (HALL_W * 0.5 + WALL), 0.95, 0.0)
        for row in 3:
            for col in 3:
                if is_shut(shut, r, row, col):
                    continue
                var s := seat(r, row, col, step)
                if s.is_empty():
                    continue
                var dist: float = player_pos.distance_to(s["pos"])
                if reachable(s):
                    if far:
                        var dd: float = door.distance_to(s["pos"])
                        if dd > best_far:
                            best_reach = s
                            best_far = dd
                    elif dist >= min_d and dist < best_reach_d:
                        best_reach = s
                        best_reach_d = dist
                if dist >= min_d and dist < best_open_d:   # M5.0l: the open fallback keeps the distance too - nothing left -> the lamp or {}
                    best_open = s
                    best_open_d = dist
    if not best_reach.is_empty():
        return best_reach
    if lamp_on:
        return lamp_seat(player_pos, cam_fwd, zone if zone != "" else room, step, ahead)
    return best_open

# Is p lit by pane (row, col) of `room` at `step`? The point pushed back along
# the beam to the ceiling must land inside the pane, and the beam must reach p:
# either p is inside the room, or p is in the hall and the beam crosses the
# room's doorway (x = +-1.8, |z| <= 0.8, y < 2.4) on its way - a wall shades
# everything else.
static func in_beam(p: Vector3, room: String, row: int, col: int, step: int) -> bool:
    var d := Lighting.sun_dir(step)
    if d.y >= 0.0:
        return false
    var s := (p.y - ROOM_H) / d.y          # distance back along the beam to the ceiling plane
    if s < 0.0:
        return false
    var o := p - d * s
    if not pane_rect(room, row, col).grow(-0.001).has_point(Vector2(o.x, o.z)):
        return false
    var box := room_box(room)
    if box.has_point(p):
        return true
    # in the hall: the beam must pass through the doorway in the hall-side wall
    var xwall := room_sign(room) * (HALL_W * 0.5 + WALL)
    if absf(d.x) < 1e-6:
        return false
    var t := (p.x - xwall) / d.x            # back along the beam to the wall plane
    if t < 0.0:
        return false
    var c := p - d * t
    return absf(c.z) <= DOOR_HALF_Z and c.y >= 0.0 and c.y < DOOR_H and absf(p.x) < HALL_W * 0.5 + WALL


# --- the cut rule (GUARDRAILS 3.9) ---------------------------------------------

# A light change starts a 1 s batch; changes inside it are one change and never
# extend it. Returns the due time (game clock) - unchanged while one is pending.
static func due_after(due: float, t: float) -> float:
    return due if due >= 0.0 else t + 1.0

# An ending's last image is the door or the mark, never the mass filling the frame
# (M7.0g). The body swings 90 deg about the eye, so it keeps its distance and its
# room but stands off the axis the player is looking down. Of the two swings, the
# one nearer the centreline: the plant room is narrow and its side walls are close.
static func step_aside(body: Vector3, eye: Vector3) -> Vector3:
    var d := body - eye
    var a := Vector3(eye.x - d.z, body.y, eye.z + d.x)
    var b := Vector3(eye.x + d.z, body.y, eye.z - d.x)
    return a if absf(a.x) <= absf(b.x) else b

# The points that give a seat away (M3.0d, gate M2): its centre, the omni above
# it, the four pane corners carried down the beam to the seat's own plane (the
# real patch corners; those beyond the room, e.g. a wall patch's foot that runs
# onto the floor, are dropped), four rim points `rim` metres along the surface
# tangents (the omni's reach), and for a wall seat the floor point under the
# omni (the pool). Every point but the omni lies inside room_box.grow(0.06).
# All are lifted 0.05 m off their surface so a ray to them does not hit it.
static func seat_points(s: Dictionary, rim: float = 2.0) -> Array:
    var pts := patch_points(s, rim)
    pts.append_array(body_points(body_pos(s), body_yaw(int(s.get("step", 0)))))
    return pts

# the patch's own points (the bite): centre, omni, corners, rim, pool
static func patch_points(s: Dictionary, rim: float = 2.0) -> Array:
    var pos: Vector3 = s["pos"]
    var n: Vector3 = s["normal"]
    var omni := pos + n * OMNI_OFF
    var pts := [pos + n * 0.05, omni]
    var cand := []
    if s.get("row", -1) >= 0:
        var d := Lighting.sun_dir(s.get("step", 0))
        var r := pane_rect(s["room"], s["row"], s["col"])
        var pc := pane_centre(s["room"], s["row"], s["col"])
        for cx: float in [r.position.x, r.end.x]:
            for cz: float in [r.position.y, r.end.y]:
                var c := Vector3(cx, pc.y, cz)
                var t := 0.0
                if absf(n.x) > 0.5 and d.x != 0.0:
                    t = (pos.x - c.x) / d.x
                elif absf(n.z) > 0.5 and d.z != 0.0:
                    t = (pos.z - c.z) / d.z
                elif d.y != 0.0:
                    t = (pos.y - c.y) / d.y
                cand.append(c + d * t + n * 0.05)
    # rim points along the two surface tangents
    var t1 := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.UP
    var t2 := Vector3.FORWARD if absf(n.z) < 0.5 else Vector3.UP
    for v: Vector3 in [t1, -t1, t2, -t2]:
        cand.append(pos + v * rim + n * 0.05)
    if absf(n.y) < 0.5:
        cand.append(Vector3(omni.x, 0.05, omni.z))
    var box := room_box(s.get("room", ""))       # the room's faces, then 0.05 off them (M4.0c: not inside the slab)
    if box.size != Vector3.ZERO:
        # a point beyond the room (a wall patch's foot that ran onto the floor, a
        # corner carried past the hall wall) is pulled back to the room's face,
        # not dropped: the patch's edge is where the light stops; no box (a lamp
        # seat in the hall, plant room or office): no clamp (M5.0i)
        var lo := box.position + Vector3(0.05, 0.05, 0.05)
        var hi := box.end - Vector3(0.05, 0.05, 0.05)
        for c: Vector3 in cand:
            pts.append(c.clamp(lo, hi))
    else:
        pts.append_array(cand)
    return pts

# Seen = any point inside the frustum (clip-space test against `proj`, the
# camera's projection, with `cam` its global transform) and not occluded;
# `occluded(p) -> bool` asks the physics world. A seat that is seen never cuts.
static func seen(points: Array, proj: Projection, cam: Transform3D, occluded: Callable) -> bool:
    var inv := cam.affine_inverse()
    for p: Vector3 in points:
        var l := inv * p
        var c := proj * Vector4(l.x, l.y, l.z, 1.0)
        if c.w <= 0.0 or absf(c.x) > c.w or absf(c.y) > c.w or absf(c.z) > c.w:
            continue
        if not occluded.call(p):
            return true
    return false


# --- dose (GUARDRAILS 3.10) ---------------------------------------------------
# In its light +0.5/s, riding +0.33/s, outside -0.25/s, clamped 0..DOSE_MAX;
# at DOSE_MAX main.gd bleaches.
const DOSE_MAX := 3.0        # M4.0e: 6 s in its light (three breaths), 9 s riding; one crank in its light subsides, two kill
# the DIM omni sits OMNI_OFF metres off the seat along its normal (M3.0k: 0.6 with
# range 1.2 - the bite stays inside its patch and never pools on the floor
# under a wall seat: 1.26 m down > the range)
const OMNI_OFF := 0.6

# the body's yaw at a step: its front (+X) turned to the heading the light comes
# from (M3.1: it sits in the sun, facing it); rotation about Y maps +X to (cos, -sin)
# --- the body's geometry (M4.0c) ------------------------------------------------
# The drape's give-away points in its own frame (+X = its front): origin +1.6,
# the hump apex, the hand tip, and the four floor drips at the sides and back
# (the hem formula of creature.gd: even hem points touch the floor).
static func body_local_points() -> Array:
    var centre := Vector3(-0.30, 0, 0)
    var pts := [Vector3(0, 1.6, 0), centre + Vector3(-0.25, 3.25, 0.05), Vector3(0.55, 2.45, 0.52) + Vector3(1.62, -2.42, 0.0)]
    for i: int in [4, 6, 8, 10]:
        var a := TAU * i / 14.0
        var fw := (1.0 - cos(a)) * 0.5
        var jag := 1.45 + 0.35 * fw
        var front := 0.55 + 0.45 * fw
        pts.append(centre + Vector3(0.80 * jag * front * cos(a), 0.0, 0.72 * jag * sin(a)))
    return pts

static func body_points(pos: Vector3, yaw: float) -> Array:
    var out := []
    for p: Vector3 in body_local_points():
        var r := p.rotated(Vector3.UP, yaw) + pos
        out.append(Vector3(r.x, maxf(r.y, 0.05), r.z))
    return out

# where the body stands: on a floor seat's patch, 1.6 m out from a wall seat;
# then pushed in x/z so its footprint stays inside the room (B r1c0 s2 poked
# 0.9 m through the hall wall before this)
static func body_pos(s: Dictionary) -> Vector3:
    var n: Vector3 = s["normal"]
    var p: Vector3 = s["pos"]
    var pos := Vector3(p.x, 0.0, p.z) if absf(n.y) >= 0.5 else Vector3(p.x + n.x * 1.6, 0.0, p.z + n.z * 1.6)
    if not s.has("room") or (s["room"] != "A" and s["room"] != "B"):
        return pos
    var box := room_box(s["room"])
    var lo := box.position + Vector3(0.1, 0, 0.1)
    var hi := box.end - Vector3(0.1, 0, 0.1)
    var yaw := body_yaw(int(s.get("step", 0)))
    for _k in 2:
        var shift := Vector3.ZERO
        for q: Vector3 in body_points(pos, yaw):
            shift.x = maxf(shift.x, lo.x - q.x) if q.x < lo.x else shift.x
            shift.x = minf(shift.x, hi.x - q.x) if q.x > hi.x else shift.x
            shift.z = maxf(shift.z, lo.z - q.z) if q.z < lo.z else shift.z
            shift.z = minf(shift.z, hi.z - q.z) if q.z > hi.z else shift.z
        pos += shift
    return pos

static func body_yaw(step: int) -> float:
    var to_sun := -Lighting.sun_dir(step)
    return atan2(-to_sun.z, to_sun.x)

static func dose_step(dose: float, in_light: bool, riding: bool, dt: float) -> float:
    var rate := 0.33 if riding else (0.5 if in_light else -0.25)
    return clampf(dose + rate * dt, 0.0, DOSE_MAX)


# --- unreliability (GUARDRAILS 3.8, M3.3) ------------------------------------
# The aura's presence is a pure function of the clock and a seed: cycles of
# [on L_k] [ramp down RAMP] [off O_k] [ramp up RAMP], L_k in 6-16 s and O_k in
# 2-4 s from a seeded hash, quantised to 0.5 s with no two consecutive on-lengths
# equal. Duty ~72% (measured TEST dropout_stats). Nothing about it is periodic.
const PRES_RAMP := 2.0
const PRES_ON_MIN := 6.0
const PRES_ON_SPAN := 10.0
const PRES_OFF_MIN := 2.0
const PRES_OFF_SPAN := 2.0

static func _hash01(seed: int, k: int) -> float:
    return float(hash("%d:%d" % [seed, k]) % 10000) / 10000.0

static func on_len(seed: int, k: int) -> float:
    var l := PRES_ON_MIN + snappedf(_hash01(seed, 2 * k) * PRES_ON_SPAN, 0.5)
    if k > 0 and is_equal_approx(l, on_len(seed, k - 1)):
        l = PRES_ON_MIN + fmod(l - PRES_ON_MIN + 0.5, PRES_ON_SPAN + 0.5)
    return l

static func off_len(seed: int, k: int) -> float:
    return PRES_OFF_MIN + snappedf(_hash01(seed, 2 * k + 1) * PRES_OFF_SPAN, 0.5)

# `hint` = [k, t0] of the last cycle found (an Array, updated in place): main
# hands it back every frame so the walk starts where it left off (M4.0j) - the
# clock is monotonic. Without it the walk starts at t = 0.
static func presence(t: float, seed: int, hint: Array = []) -> float:
    var t0 := 0.0
    var k := 0
    if hint.size() == 2 and float(hint[1]) <= t:
        k = int(hint[0])
        t0 = float(hint[1])
    while k < 100000:
        var l := on_len(seed, k)
        var o := off_len(seed, k)
        var cyc := l + PRES_RAMP + o + PRES_RAMP
        if t < t0 + cyc:
            if hint.size() == 2:
                hint[0] = k
                hint[1] = t0
            var u := t - t0
            if u < l:
                return 1.0
            u -= l
            if u < PRES_RAMP:
                return 1.0 - u / PRES_RAMP
            u -= PRES_RAMP
            if u < o:
                return 0.0
            u -= o
            return u / PRES_RAMP
        t0 += cyc
        k += 1
    return 1.0

# the first time presence drops below 0.5 (the harness shoots around it)
static func first_off(seed: int) -> float:
    return on_len(seed, 0) + PRES_RAMP * 0.5

# the aura's screen position follows the body with a 0.3 s time constant
static func lag(prev: Vector2, target: Vector2, dt: float) -> Vector2:
    return prev + (target - prev) * (1.0 - exp(-dt / 0.3))

static func lag3(prev: Vector3, target: Vector3, dt: float) -> Vector3:
    return prev + (target - prev) * (1.0 - exp(-dt / 0.3))
