extends Node3D
# The thing, at rest. A faceted drape: a jagged hem on the floor whose points
# alternately pool and lift, a ridge ring at the shoulders, one hump apex, sharp
# creases running ridge-to-hem. Wedge head, prism arm hanging in front, wedge hand.
# Everything is unshaded black: it reflects nothing, so the ASCII reading shows
# a hole whose edge is the only thing it has. Local +X is its front.

var mat: StandardMaterial3D
var mass: Node3D
var arm_pivot: Node3D
var t := 0.0

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
    parent.add_child(m)

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

func _process(dt: float) -> void:
    t += dt
    mass.scale.y = 1.0 - 0.035 * (0.5 + 0.5 * sin(t * 0.7))          # settles and rises, slowly
    arm_pivot.rotation.z = deg_to_rad(2.5) * sin(t * 0.45)             # a pendulum that has almost stopped
