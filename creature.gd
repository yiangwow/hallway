extends Node3D
# The thing, at rest. A faceted drape: a jagged hem on the floor whose points
# alternately pool and lift, a ridge ring at the shoulders, one hump apex, sharp
# creases running ridge-to-hem. Wedge head, prism arm hanging in front, wedge hand.
# Everything is unshaded black: it reflects nothing, so the ASCII reading shows
# a hole whose edge is the only thing it has. Local +X is its front.

var mat: StandardMaterial3D
var mass: Node3D
var arm_pivot: Node3D
var t := 0.0   # set by main.gd from the one clock every frame

# the knuckle-walk (M4.6b, GUARDRAILS 3.5): the hand plants at the target (the
# lamp's disc edge) at most once per STEP_S, then the mass drags after it over
# the step - fast off the mark, settling - while the hand stays pinned where it
# landed. Never more than STEP_MAX per plant. It faces the way it goes.
const STEP_S := 2.0
const STEP_MAX := 2.2
const SHOULDER := Vector3(0.55, 2.45, 0.52)
const HAND := Vector3(0.92, -2.42, 0.0)      # the knuckles, from the shoulder pivot
const HAND_REACH := 1.47                     # SHOULDER.x + HAND.x: the hand ahead of the origin
const AVOID_R := 0.9                         # never through the caretaker (M5.0i): a step's path keeps this far
const AVOID_STEP := 1.2                      # ...by first going to the point this far beside them
var plants := 0
var last_plant_t := -INF
var plant_world := Vector3.ZERO
var mass_from := Vector3.ZERO
var step_dest := Vector3.ZERO
var walking := false
var step_u := 0.0            # the step in hand, advanced by dt (M6.0d): a freeze (lamp off) resumes, never snaps
var since_plant := STEP_S    # dt since the last plant; the first step is free
const TURNS := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0]   # a blocked step tries these turns, else waits

# a cut or a re-seat: put down here, at rest, mid-step forgotten (M5.0i)
func place(p: Vector3, yaw: float) -> void:
    position = p
    rotation.y = yaw
    walking = false
    if arm_pivot != null:
        arm_pivot.position = SHOULDER

# nothing solid between here and there (knee height)
func _clear(from: Vector3, to: Vector3) -> bool:
    var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.3, Vector3(to.x, 0.3, to.z), 1)
    return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

static func _seg_dist(a: Vector3, b: Vector3, p: Vector3) -> float:
    var a2 := Vector2(a.x, a.z)
    var ab := Vector2(b.x, b.z) - a2
    var p2 := Vector2(p.x, p.z)
    var k := 0.0 if ab.length_squared() < 1e-6 else clampf((p2 - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
    return (a2 + ab * k).distance_to(p2)

func walk_to(target: Vector3, dt: float, avoid: Vector3 = Vector3(INF, 0, INF)) -> void:
    since_plant += dt
    var to := target - global_position
    to.y = 0.0
    if not walking and to.length() > 0.3 and since_plant >= STEP_S:
        var dir := to.normalized()
        var dest := global_position + dir * minf(to.length(), STEP_MAX)
        # a path passing within AVOID_R of the caretaker goes round instead: the
        # step aims AVOID_STEP beside them, on the arc halfway between where it
        # stands and where it is going (a turn-round would otherwise walk it through)
        var tgt_d := Vector2(target.x - avoid.x, target.z - avoid.z).length() if is_finite(avoid.x) else INF
        if tgt_d >= AVOID_R and _seg_dist(global_position, dest, avoid) < AVOID_R:   # a seat at their feet (a crank) is walked to straight
            var u0 := Vector3(global_position.x - avoid.x, 0.0, global_position.z - avoid.z)
            var u1 := Vector3(target.x - avoid.x, 0.0, target.z - avoid.z)
            u0 = u0.normalized() if u0.length() > 1e-3 else Vector3.RIGHT
            u1 = u1.normalized() if u1.length() > 1e-3 else -u0
            var mid := u0 + u1
            mid = mid.normalized() if mid.length() > 0.2 else u0.rotated(Vector3.UP, PI * 0.5)
            # either side of them; the first with a clear path wins (the boiler
            # stood on the near side once and it walked into it for ever)
            for side: Vector3 in [mid, mid.rotated(Vector3.UP, PI * 0.5) if mid.dot(u1) < 0.99 else -mid, -mid]:
                var way := Vector3(avoid.x, 0.0, avoid.z) + side * AVOID_STEP
                var tw := way - global_position
                tw.y = 0.0
                if tw.length() < 1e-3 or not _clear(global_position, way):
                    continue
                dir = tw.normalized()
                dest = global_position + dir * minf(tw.length(), STEP_MAX)
                break
        # the step itself must be clear at knee height (M6.0d: the mass walked through
        # jambs, racks and walls): else the same length turned 30, 60, 90 deg either
        # way, the first clear one; nothing clear - wait this frame (no navmesh)
        var reach := (dest - global_position).length()
        var found := false
        for deg: float in TURNS:
            var d2 := dir.rotated(Vector3.UP, deg_to_rad(deg))
            var dest2 := global_position + d2 * reach
            if _clear(global_position, dest2):
                dir = d2
                dest = dest2
                found = true
                break
        if not found:
            return
        rotation.y = atan2(-dir.z, dir.x)
        # the mass arrives at dest (the seat keeps its own distance from walls);
        # the hand plants HAND_REACH beyond it, in the direction of travel - never
        # through a wall: the first hit stops the hand 0.1 m short (M5.0i)
        var dest_along := (dest - global_position).dot(dir)
        var plant_along := dest_along + HAND_REACH
        var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3, global_position + Vector3.UP * 0.3 + dir * plant_along, 1)
        var hit := get_world_3d().direct_space_state.intersect_ray(q)
        step_dest = global_position + dir * dest_along
        step_dest.y = 0.0
        plant_world = global_position + dir * plant_along
        if not hit.is_empty():
            # 0.1 m off the face along its normal (M6.0i: along a shallow, turned path
            # 0.1 m of travel was 2 cm of clearance and the knuckles sat in the wall)
            plant_world = hit["position"] + (hit["normal"] as Vector3) * 0.1
        plant_world.y = 0.03
        last_plant_t = t
        since_plant = 0.0
        step_u = 0.0
        plants += 1
        mass_from = global_position
        walking = true
    if walking:
        step_u = minf(step_u + dt / STEP_S, 1.0)
        var ease := 1.0 - (1.0 - step_u) * (1.0 - step_u)
        global_position = mass_from.lerp(step_dest, ease)
        arm_pivot.position = mass.global_transform.affine_inverse() * plant_world - HAND
        if step_u >= 1.0:
            walking = false
            arm_pivot.position = SHOULDER

func _ready() -> void:
    mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0, 0, 0)
    mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    mass = Node3D.new()
    add_child(mass)
    _drape()
    _head()
    arm_pivot = Node3D.new()
    arm_pivot.position = Vector3(0.55, 2.45, 0.52)   # front of the near shoulder, clear of the drape
    mass.add_child(arm_pivot)
    _arm()

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
    st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

func _commit(st: SurfaceTool, parent: Node3D) -> void:
    st.generate_normals()
    var m := MeshInstance3D.new()
    m.mesh = st.commit()
    m.material_override = mat
    m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # a hole casts nothing
    m.layers = 2                                                      # visual layer 2: the body, nothing else (M3.1)
    parent.add_child(m)

# the body exists only in the reading: visible while ASCII is on (GUARDRAILS 3.6)
func set_ascii(on: bool) -> void:
    visible = on

func _drape() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var centre := Vector3(-0.30, 0, 0)
    # hem: 14 points; even ones are long thin drips that touch the floor, odd ones pull in hard and lift
    var hem: Array[Vector3] = []
    var hem_a: Array[float] = []
    for i: int in 14:
        var a := TAU * i / 14.0
        var fw := (1.0 - cos(a)) * 0.5                          # 0 at the front, 1 at the back
        var drip := (i % 2 == 0)
        var jag := (1.45 + 0.35 * fw) if drip else 0.55
        var front := 0.55 + 0.45 * fw                           # shorter in front: the knees
        var rx := 0.80 * jag * front
        var rz := 0.72 * jag
        var y := 0.0 if drip else (0.55 + 0.25 * fw)
        hem.append(centre + Vector3(rx * cos(a), y, rz * sin(a)))
        hem_a.append(a)
    # ridge ring: 6 points at shoulder height, narrow; one shoulder carried higher than the other
    var ridge: Array[Vector3] = []
    var ridge_a: Array[float] = []
    var rh := [2.10, 2.70, 2.80, 2.35, 2.75, 2.50]                # front, L, back-L, back, back-R, R
    for j: int in 6:
        var a := TAU * j / 6.0
        ridge.append(centre + Vector3(0.40 * cos(a) + 0.15, rh[j], 0.46 * sin(a)))
        ridge_a.append(a)
    var apex := centre + Vector3(-0.25, 3.25, 0.05)
    # roof: fan from the apex to the ridge ring
    for j: int in 6:
        _tri(st, apex, ridge[j], ridge[(j + 1) % 6])
    # skirt: merge-walk the two rings by angle
    var i := 0
    var j := 0
    while i < 14 or j < 6:
        var ha := hem_a[(i + 1) % 14] if i + 1 < 14 else TAU
        var ra := ridge_a[(j + 1) % 6] if j + 1 < 6 else TAU
        if i < 14 and (ha <= ra or j >= 6):
            _tri(st, hem[i % 14], hem[(i + 1) % 14], ridge[j % 6]); i += 1
        else:
            _tri(st, hem[i % 14], ridge[(j + 1) % 6], ridge[j % 6]); j += 1
    _commit(st, mass)

func _head() -> void:
    # an octahedron pulled forward: muzzle and back-of-skull are the poles
    var A := Vector3(1.55, 1.35, 0.0)     # muzzle tip, long
    var F := Vector3(0.10, 1.95, 0.0)     # back of skull, inside the drape
    var B := Vector3(0.70, 2.05, 0.0)     # crown
    var C := Vector3(0.65, 1.62, 0.26)
    var D := Vector3(0.65, 1.62, -0.26)
    var E := Vector3(0.85, 1.12, 0.0)     # chin
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for f: Array in [[A,B,C],[A,C,E],[A,E,D],[A,D,B],[F,C,B],[F,E,C],[F,D,E],[F,B,D]]:
        _tri(st, f[0], f[1], f[2])
    _commit(st, mass)

func _arm() -> void:
    var st := SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    # triangular prism from the shoulder to the wrist, thicker at the top
    var top := Vector3.ZERO
    var bot := Vector3(0.62, -2.28, 0.02)
    var ax := (bot - top).normalized()
    var u := ax.cross(Vector3.FORWARD).normalized()
    var v := ax.cross(u)
    var ring_t: Array[Vector3] = []
    var ring_b: Array[Vector3] = []
    for k: int in 3:
        var a := TAU * k / 3.0
        ring_t.append(top + (u * cos(a) + v * sin(a)) * 0.13)
        ring_b.append(bot + (u * cos(a) + v * sin(a)) * 0.08)
    for k: int in 3:
        var n := (k + 1) % 3
        _tri(st, ring_t[k], ring_b[k], ring_b[n])
        _tri(st, ring_t[k], ring_b[n], ring_t[n])
    _tri(st, ring_t[0], ring_t[1], ring_t[2])
    # hand: a flat wedge on the floor, knuckles forward, three finger spikes
    var hy := -2.42
    var base := [Vector3(0.45, hy, -0.16), Vector3(0.92, hy, -0.20), Vector3(0.98, hy, 0.16), Vector3(0.48, hy, 0.18)]
    var peak := Vector3(0.66, hy + 0.22, 0.0)
    for k: int in 4:
        _tri(st, base[k], base[(k + 1) % 4], peak)
    _tri(st, base[0], base[2], base[1]); _tri(st, base[0], base[3], base[2])
    for k: int in 3:
        var z := -0.16 + 0.16 * k
        var r0 := Vector3(0.92, hy + 0.10, z)
        var r1 := Vector3(1.62, hy - 0.02, z + 0.03 * (k - 1))
        _tri(st, r0 + Vector3(0, 0.06, 0), r0 + Vector3(0, -0.04, 0.05), r1)
        _tri(st, r0 + Vector3(0, -0.04, -0.05), r0 + Vector3(0, 0.06, 0), r1)
        _tri(st, r0 + Vector3(0, -0.04, 0.05), r0 + Vector3(0, -0.04, -0.05), r1)
    _commit(st, arm_pivot)

var rise := 1.0   # the ride-in (M4.6c): the mass rises from the floor over 2 s; unshaded black has no alpha

func _process(_dt: float) -> void:
    mass.scale.y = maxf(rise, 0.01) * (1.0 - 0.035 * (0.5 + 0.5 * sin(t * 0.7)))   # settles and rises, slowly
    arm_pivot.rotation.z = deg_to_rad(2.5) * sin(t * 0.45)             # a pendulum that has almost stopped
