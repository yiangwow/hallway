class_name Props extends RefCounted
# The world's builders (M4.0a): stateless, static, take main. Constants and
# the thing's runtime state stay in main.gd. Every M4 prop lands here.

static func _materials(m) -> void:
    m.mat_wall = StandardMaterial3D.new()
    m.mat_wall.albedo_color = Color(0.90, 0.90, 0.90)
    m.mat_wall.roughness = 0.95
    m.mat_floor = StandardMaterial3D.new()
    m.mat_floor.albedo_color = Color(0.62, 0.62, 0.62)
    m.mat_floor.roughness = 0.85
    m.mat_dark = StandardMaterial3D.new()
    m.mat_dark.albedo_color = Color(0.22, 0.22, 0.22)
    m.mat_dark.roughness = 0.7

static func _mat(m, albedo: float) -> StandardMaterial3D:
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(albedo, albedo, albedo)
    mat.roughness = 0.95
    return mat

# Axis-aligned solid slab from min corner to max corner, with collision.
static func slab(m, a: Vector3, b: Vector3, mat: StandardMaterial3D) -> StaticBody3D:
    var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
    var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
    var size := hi - lo
    var body := StaticBody3D.new()
    body.position = lo + size * 0.5
    var mesh := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mesh.mesh = bm
    mesh.material_override = mat
    mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
    body.add_child(mesh)
    var col := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    col.shape = bs
    body.add_child(col)
    m.add_child(body)
    return body

static func _floor(m) -> void:
    var x = m.HALL_W * 0.5 + m.WALL + m.ROOM + m.WALL
    var z = m.HALL_L * 0.5 + m.WALL
    # runs under the office, the plant room and YARD_D metres of sunlit yard beyond the
    # yard door: the keyhole shows that ground, not the sky's dark half (M4.1)
    Props.slab(m, Vector3(-x, -m.WALL, -(z + m.PLANT_D + m.WALL + m.YARD_D)), Vector3(x, 0, z + m.OFF_D + m.WALL), m.mat_floor)

static func _build_hallway(m) -> void:
    var hx = m.HALL_W * 0.5           # inner half width  (1.5)
    var hz = m.HALL_L * 0.5           # inner half length (12)
    var dz = m.DOOR_W * 0.5
    for s: float in [-1.0, 1.0]:
        var x0 = s * hx
        var x1 = s * (hx + m.WALL)
        # side walls, split around the doorway
        Props.slab(m, Vector3(x0, 0, -hz - m.WALL), Vector3(x1, m.HALL_H, -dz), m.mat_wall)
        Props.slab(m, Vector3(x0, 0, dz), Vector3(x1, m.HALL_H, hz + m.WALL), m.mat_wall)
        Props.slab(m, Vector3(x0, m.DOOR_H, -dz), Vector3(x1, m.HALL_H, dz), m.mat_wall)   # lintel
        # the room wall continues above the hallway ceiling up to room height
        var rz = m.ROOM * 0.5 + m.WALL
        Props.slab(m, Vector3(x0, m.HALL_H, -rz), Vector3(x1, m.ROOM_H + m.WALL, rz), m.mat_wall)
    # end walls: both split into two jambs and a lintel, -Z around the plant doorway, +Z around the office doorway
    var pdw = m.PLANT_DOOR_W * 0.5
    Props.slab(m, Vector3(-hx - m.WALL, 0, -hz), Vector3(-pdw, m.HALL_H + m.WALL, -(hz + m.WALL)), m.mat_wall)
    Props.slab(m, Vector3(pdw, 0, -hz), Vector3(hx + m.WALL, m.HALL_H + m.WALL, -(hz + m.WALL)), m.mat_wall)
    Props.slab(m, Vector3(-pdw, m.DOOR_H, -hz), Vector3(pdw, m.HALL_H + m.WALL, -(hz + m.WALL)), m.mat_wall)
    var dw = m.OFF_DOOR_W * 0.5
    Props.slab(m, Vector3(-hx - m.WALL, 0, hz), Vector3(-dw, m.HALL_H + m.WALL, hz + m.WALL), m.mat_wall)
    Props.slab(m, Vector3(dw, 0, hz), Vector3(hx + m.WALL, m.HALL_H + m.WALL, hz + m.WALL), m.mat_wall)
    Props.slab(m, Vector3(-dw, m.DOOR_H, hz), Vector3(dw, m.HALL_H + m.WALL, hz + m.WALL), m.mat_wall)
    # ceiling
    Props.slab(m, Vector3(-hx - m.WALL, m.HALL_H, -hz - m.WALL), Vector3(hx + m.WALL, m.HALL_H + m.WALL, hz + m.WALL), m.mat_wall)

static func _build_room(m, s: float) -> void:
    var xin = s * (m.HALL_W * 0.5 + m.WALL)        # room inner face on the hallway side
    var xout = s * (m.HALL_W * 0.5 + m.WALL + m.ROOM) # room inner face on the far side
    var xwall = xout + s * m.WALL
    var rz = m.ROOM * 0.5
    var top = m.ROOM_H
    # far wall, front and back walls
    Props.slab(m, Vector3(xout, 0, -rz - m.WALL), Vector3(xwall, top + m.WALL, rz + m.WALL), m.mat_wall)
    for t: float in [-1.0, 1.0]:
        Props.slab(m, Vector3(xin, 0, t * rz), Vector3(xwall, top + m.WALL, t * (rz + m.WALL)), m.mat_wall)
    # ceiling with a square skylight cut out of its centre
    var cx = (xin + xout) * 0.5
    var k = m.SKY * 0.5
    Props.slab(m, Vector3(xin, top, -rz), Vector3(xout, top + m.WALL, -k), m.mat_wall)
    Props.slab(m, Vector3(xin, top, k), Vector3(xout, top + m.WALL, rz), m.mat_wall)
    Props.slab(m, Vector3(xin, top, -k), Vector3(cx - s * k, top + m.WALL, k), m.mat_wall)
    Props.slab(m, Vector3(cx + s * k, top, -k), Vector3(xout, top + m.WALL, k), m.mat_wall)
    # mullions: 3 x 3 panes
    var mh = m.MULLION * 0.5
    for i: float in [-1.0, 1.0]:
        var g = i * m.SKY / 6.0
        Props.slab(m, Vector3(cx - k, top, g - mh), Vector3(cx + k, top + m.WALL, g + mh), m.mat_dark)
        Props.slab(m, Vector3(cx + g - mh, top, -k), Vector3(cx + g + mh, top + m.WALL, k), m.mat_dark)

static func _build_office(m) -> void:
    var z0 = m.HALL_L * 0.5 + m.WALL          # inner front face (the hall's end wall)
    var z1 = z0 + m.OFF_D                   # inner far face
    var hw = m.OFF_W * 0.5
    # fillers beside the hall's end wall, where the office is wider than the hall
    Props.slab(m, Vector3(m.HALL_W * 0.5 + m.WALL, 0, z0 - m.WALL), Vector3(hw + m.WALL, m.OFF_H + m.WALL, z0), m.mat_wall)
    Props.slab(m, Vector3(-hw - m.WALL, 0, z0 - m.WALL), Vector3(-(m.HALL_W * 0.5 + m.WALL), m.OFF_H + m.WALL, z0), m.mat_wall)
    # side walls, far wall
    Props.slab(m, Vector3(hw, 0, z0 - m.WALL), Vector3(hw + m.WALL, m.OFF_H + m.WALL, z1 + m.WALL), m.mat_wall)
    Props.slab(m, Vector3(-hw - m.WALL, 0, z0 - m.WALL), Vector3(-hw, m.OFF_H + m.WALL, z1 + m.WALL), m.mat_wall)
    Props.slab(m, Vector3(-hw - m.WALL, 0, z1), Vector3(hw + m.WALL, m.OFF_H + m.WALL, z1 + m.WALL), m.mat_wall)
    # ceiling with a 1 x 1 pane at its centre
    var cz = (z0 + z1) * 0.5
    var k = m.OFF_PANE * 0.5
    Props.slab(m, Vector3(-hw, m.OFF_H, z0), Vector3(hw, m.OFF_H + m.WALL, cz - k), m.mat_wall)
    Props.slab(m, Vector3(-hw, m.OFF_H, cz + k), Vector3(hw, m.OFF_H + m.WALL, z1), m.mat_wall)
    Props.slab(m, Vector3(-hw, m.OFF_H, cz - k), Vector3(-k, m.OFF_H + m.WALL, cz + k), m.mat_wall)
    Props.slab(m, Vector3(k, m.OFF_H, cz - k), Vector3(hw, m.OFF_H + m.WALL, cz + k), m.mat_wall)
    # furniture: desk against the far wall, the log on it, a chair, the lamp hook by the door
    Props.slab(m, Vector3(0.2, 0.70, z1 - 0.75), Vector3(1.8, 0.76, z1 - 0.05), m.mat_dark)        # desk top
    Props.slab(m, Vector3(0.25, 0.0, z1 - 0.70), Vector3(0.35, 0.70, z1 - 0.10), m.mat_dark)        # legs
    Props.slab(m, Vector3(1.65, 0.0, z1 - 0.70), Vector3(1.75, 0.70, z1 - 0.10), m.mat_dark)
    Props.slab(m, Vector3(0.7, 0.76, z1 - 0.55), Vector3(1.1, 0.79, z1 - 0.25), m.mat_wall)         # the log
    # D5 (M5.2): the chair is two-tone - thirty years of the pane's light bleached
    # its sun side (+X, the light comes from +X +Z) to 0.9 while the shadow side
    # kept its 0.3; the seat top carries both, dark near the door, pale beyond
    var sun := Props._mat(m, 0.9)
    var shade := Props._mat(m, 0.3)
    Props.slab(m, Vector3(0.75, 0.0, z1 - 1.55), Vector3(1.0, 0.45, z1 - 1.05), shade)               # chair seat, shadow half
    Props.slab(m, Vector3(1.0, 0.0, z1 - 1.55), Vector3(1.25, 0.45, z1 - 1.05), sun)                 # chair seat, sun half
    Props.slab(m, Vector3(0.75, 0.45, z1 - 1.15), Vector3(1.0, 0.95, z1 - 1.05), shade)              # chair back
    Props.slab(m, Vector3(1.0, 0.45, z1 - 1.15), Vector3(1.25, 0.95, z1 - 1.05), sun)
    Props.slab(m, Vector3(-hw + 0.02, 1.55, z0 + 0.4), Vector3(-hw + 0.10, 1.63, z0 + 0.48), m.mat_dark)   # lamp hook

# The plant room (M4.1): mirror of the office beyond the hall's -Z end wall,
# but no skylight - lit only by hall bounce and the keyhole in its yard door.
static func _build_plant(m) -> void:
    var pz0 = -(m.HALL_L * 0.5 + m.WALL)      # inner near face (the hall's end wall)
    var pz1 = pz0 - m.PLANT_D                 # inner far face
    var hw = m.PLANT_W * 0.5
    # fillers beside the hall's end wall, where the room is wider than the hall
    Props.slab(m, Vector3(m.HALL_W * 0.5 + m.WALL, 0, pz0), Vector3(hw + m.WALL, m.PLANT_H + m.WALL, pz0 + m.WALL), m.mat_wall)
    Props.slab(m, Vector3(-hw - m.WALL, 0, pz0), Vector3(-(m.HALL_W * 0.5 + m.WALL), m.PLANT_H + m.WALL, pz0 + m.WALL), m.mat_wall)
    # side walls, running the room's full length behind the far wall
    Props.slab(m, Vector3(hw, 0, pz0 + m.WALL), Vector3(hw + m.WALL, m.PLANT_H + m.WALL, pz1 - m.WALL), m.mat_wall)
    Props.slab(m, Vector3(-hw - m.WALL, 0, pz0 + m.WALL), Vector3(-hw, m.PLANT_H + m.WALL, pz1 - m.WALL), m.mat_wall)
    # far wall, split around a doorway for the yard door
    var pdw = m.PLANT_DOOR_W * 0.5
    Props.slab(m, Vector3(-hw - m.WALL, 0, pz1), Vector3(-pdw, m.PLANT_H + m.WALL, pz1 - m.WALL), m.mat_wall)
    Props.slab(m, Vector3(pdw, 0, pz1), Vector3(hw + m.WALL, m.PLANT_H + m.WALL, pz1 - m.WALL), m.mat_wall)
    Props.slab(m, Vector3(-pdw, m.DOOR_H, pz1), Vector3(pdw, m.PLANT_H + m.WALL, pz1 - m.WALL), m.mat_wall)
    # solid ceiling - no skylight (M4.1)
    Props.slab(m, Vector3(-hw, m.PLANT_H, pz0), Vector3(hw, m.PLANT_H + m.WALL, pz1), m.mat_wall)
    # the yard door fills the far-wall opening, four slabs leaving a 0.04 x 0.12
    # keyhole slot at x=0, y=1.72 so the sky beyond shows through
    # the slot sits at eye height (1.66..1.78, 0.04 wide): from 1.7 m the line of
    # sight through it rises to the SKY, which is the only bright thing out there -
    # at 1.0 m it looked down into the building's own shadow (T70, measured)
    m.yard_door.append(Props.slab(m, Vector3(-0.5, 0.0, pz1), Vector3(0.5, 1.66, pz1 - m.WALL), m.mat_dark))
    m.yard_door.append(Props.slab(m, Vector3(-0.5, 1.78, pz1), Vector3(0.5, m.DOOR_H, pz1 - m.WALL), m.mat_dark))
    m.yard_door.append(Props.slab(m, Vector3(-0.5, 1.66, pz1), Vector3(-0.02, 1.78, pz1 - m.WALL), m.mat_dark))
    m.yard_door.append(Props.slab(m, Vector3(0.02, 1.66, pz1), Vector3(0.5, 1.78, pz1 - m.WALL), m.mat_dark))
    # the boiler: a standing cylinder
    var boiler := StaticBody3D.new()
    boiler.position = Vector3(-1.2, 0.8, -15.0)
    var bmesh := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = 0.45
    cyl.bottom_radius = 0.45
    cyl.height = 1.6
    bmesh.mesh = cyl
    bmesh.material_override = m.mat_dark
    bmesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC
    boiler.add_child(bmesh)
    var bcol := CollisionShape3D.new()
    var cshape := CylinderShape3D.new()
    cshape.radius = 0.45
    cshape.height = 1.6
    bcol.shape = cshape
    boiler.add_child(bcol)
    m.add_child(boiler)
    # the valve: needs the lamp
    var valve := Props._interactable(m, Vector3(-0.6, 1.0, -15.0), Vector3(0.24, 0.24, 0.24), "valve", 8.0, false)
    valve.needs_lamp = true
    valve.sound = "click"
    valve.done.connect(func() -> void: m.game.part("C4"))   # C4: the boiler drained, in the dark
    var vmesh := MeshInstance3D.new()
    var vbox := BoxMesh.new()
    vbox.size = Vector3(0.2, 0.2, 0.2)
    vmesh.mesh = vbox
    vmesh.material_override = m.mat_wall
    valve.add_child(vmesh)

# An Interactable box (collision only) with visible children added by the caller.
static func _interactable(m, at: Vector3, size: Vector3, prompt_text: String, hold: float, ascii_needed: bool) -> Interactable:
    var b := Interactable.new()
    b.prompt = prompt_text
    b.hold_s = hold
    b.needs_ascii = ascii_needed
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = size
    cs.shape = bs
    b.add_child(cs)
    b.position = at
    m.add_child(b)
    return b

# The meter plaque: a near-black plate (reads ' ') carrying three bars of albedo
# 0.35 / 0.70 / 0.90 (read '.', '=', '*'). Tab is the meter; the plaque only says
# "read". side -1 = room A (facing -X), +1 = room B (facing +X).
static func _plaque(m, side: float) -> Interactable:
    var x = side * (m.HALL_W * 0.5 + m.WALL + 0.02)
    var pl := Props._interactable(m, Vector3(x, 1.5, -1.5), Vector3(0.06, 0.34, 0.64), "read", 1.0, true)
    pl.sound = ""                                   # a read is silent (M4.0i)
    var plate := MeshInstance3D.new()
    var pm := BoxMesh.new()
    pm.size = Vector3(0.02, 0.30, 0.60)
    plate.mesh = pm
    plate.material_override = Props._mat(m, 0.05)
    pl.add_child(plate)
    var albedos := [0.35, 0.70, 0.90]   # 0.2 read as the plate; these decode '.', '=', '*' (M2.0c)
    for i in 3:
        var bar := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.01, 0.20, 0.12)
        bar.mesh = bm
        bar.material_override = Props._mat(m, albedos[i])
        bar.position = Vector3(side * 0.015, 0.0, -0.18 + 0.18 * i)
        pl.add_child(bar)
    return pl

# the found texts (M5.1, GUARDRAILS 3.13): <= 25 words each, TEST found_text_len.
# D1 the log: monthly lux delivered against lux read, thirty years, the gap
# rising - numbers, two column heads. D2 the caretaker's own note.
const TEXTS := {
    "log": "         delivered   read\n1996-06      41000  40900\n2006-06      41000  33200\n2016-06      41000  19800\n2026-06      41000   4100",
    "note": "shutters stick - do B in the morning",
}

# D2: the note pinned on the hall side of the end wall, right of the plant-room
# doorway (a pale card; "read", never spent - reading is holding). D3: on B's
# floor, 2.2 m nearer the hall than row 0's rack, the darker unfaded rectangle
# where a second rack once stood - the one thing A does not have (3.15).
static func _discoveries(m) -> Vector3:
    var zw: float = -(m.HALL_L * 0.5)               # the hall side of its end wall
    var card := MeshInstance3D.new()
    var cb := BoxMesh.new()
    cb.size = Vector3(0.16, 0.22, 0.01)
    card.mesh = cb
    card.material_override = m.mat_wall
    card.position = Vector3(0.9, 1.45, zw + 0.006)
    m.add_child(card)
    var note = Props._interactable(m, Vector3(0.9, 1.45, zw + 0.03), Vector3(0.22, 0.28, 0.06), "read", 1e6, false)
    note.sound = ""
    note.text = TEXTS["note"]
    var d3: Vector3 = Thing.rack_pos("B", 0) + Vector3(-2.2, 0, 0)
    Props.slab(m, d3 + Vector3(-0.6, 0.001, -0.3), d3 + Vector3(0.6, 0.006, 0.3), Props._mat(m, 0.45))
    m.d6_pos = Props._burn(m)
    return d3

# D6 (M5.2): A's floor carries the faint burned 3x3 of the panes' patches as they
# lay for decades at one hour - the step-0 grid shifted (1.6, 1.2) m off the live
# one - and in the centre patch a person-shaped absence: the floor unbleached
# where someone stood in the light. One Decal over the room, alpha where it burned.
# the burn's texture, built pure so TEST d6_shape can measure the authored shape
# without a scene (M7.0c): returns [image, feet in texture px, px per metre]
static func burn_image(box: AABB, n: int) -> Array:
    var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
    img.fill(Color(1, 1, 1, 0))
    var d := Lighting.sun_dir(0)
    var h := Vector2(d.x, d.z).normalized() * (Thing.ROOM_H / tan(deg_to_rad(62.0)))   # the beam's floor travel at step 0
    var shift := h + Vector2(1.6, 1.2)
    var px := n / box.size.x
    var hole_c := Vector2.ZERO
    for row in 3:
        for col in 3:
            var r := Thing.pane_rect("A", row, col)
            var x0 := (r.position.x + shift.x - box.position.x) * px
            var z0 := (r.position.y + shift.y - box.position.z) * px
            var x1 := (r.end.x + shift.x - box.position.x) * px
            var z1 := (r.end.y + shift.y - box.position.z) * px
            if row == 1 and col == 1:
                hole_c = Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
            for y in range(maxi(int(z0), 0), mini(int(z1), n)):
                for x in range(maxi(int(x0), 0), mini(int(x1), n)):
                    img.set_pixel(x, y, Color(1, 1, 1, 0.75))
    # the absence (M6.0i): a standing shadow along the light, 0.94 m long at that
    # hour (1.7 m at 62 deg) - feet, a body widening to the shoulders, a neck, a
    # head: two dark lobes and a lighter waist, not a blob
    var ax := Vector2(d.x, d.z).normalized()
    var feet := hole_c - ax * 0.45 * px
    for y in n:
        for x in n:
            var q := (Vector2(x + 0.5, y + 0.5) - feet) / px
            var u := q.dot(ax)
            var v := absf(q.dot(Vector2(-ax.y, ax.x)))
            var inside := false
            if u >= 0.0 and u < 0.62:
                inside = v <= 0.12 + 0.11 * (u / 0.62)          # feet to the shoulders
            elif u >= 0.62 and u < 0.68:
                inside = v <= 0.23 - 0.14 * ((u - 0.62) / 0.06)   # the shoulders fall to the neck
            elif u >= 0.68 and u < 0.80:
                inside = v <= 0.09                               # the neck: a real waist between two lobes
            if (u - 0.95) * (u - 0.95) + v * v <= 0.17 * 0.17:   # the head, clear of the neck (M7.0c: at 0.12 it read as nothing, at 0.20 it swallowed the waist)
                inside = true
            if inside:
                img.set_pixel(x, y, Color(1, 1, 1, 0))
    return [img, feet, px]

static func _burn(m) -> Vector3:
    var box := Thing.room_box("A")
    var r3: Array = Props.burn_image(box, 256)
    var img: Image = r3[0]
    var feet: Vector2 = r3[1]
    var px: float = r3[2]
    var feet_world := Vector3(box.position.x + feet.x / px, 0.0, box.position.z + feet.y / px)
    var dec := Decal.new()
    dec.texture_albedo = ImageTexture.create_from_image(img)
    dec.modulate = Color(0.85, 0.85, 0.85)
    dec.albedo_mix = 1.0
    dec.size = Vector3(box.size.x, 0.5, box.size.z)
    dec.cull_mask = 1
    dec.position = Vector3(box.get_center().x, 0.02, box.get_center().z)
    m.add_child(dec)
    m.d6_decal = dec        # M7.0c: the probe hides it to measure the burn alone, clear of the room's own gradient
    return feet_world

# C1 = plaque A, plaque B, the desk log: three parts
static func _c1_props(m) -> void:
    var spent: bool = int(m.args.get("chores", "0")) >= 1   # M5.0a: --chores>=1 spends them as play would
    for side: float in [-1.0, 1.0]:
        var pl := Props._plaque(m, side)
        pl.done.connect(func() -> void: m.game.part("C1"))
        pl.fired = spent
    var z1 = m.HALL_L * 0.5 + m.WALL + m.OFF_D
    var log_body := Props._interactable(m, Vector3(0.9, 0.82, z1 - 0.40), Vector3(0.44, 0.20, 0.34), "log entry", 3.0, false)
    log_body.sound = "pencil"                       # the log is written (M4.0i)
    log_body.done.connect(func() -> void: m.game.part("C1"))
    log_body.fired = spent
    log_body.text = TEXTS["log"]                    # D1 (M5.1): thirty years of the gap


# the two lamp hooks (M4.2): by the plant-room door (the lamp hangs here at the
# start, REF C4) and by the office desk (C7 hangs it back). Each is an
# Interactable whose prompt main.gd sets from where the lamp is ("take", "hang"
# or nothing), with a small lamp body child shown while the lamp hangs on it.
static func _hooks(m) -> Array:
    var out := []
    # the plant hook is on the HALL side of the -Z end wall, left of the plant doorway
    # (M6.0g: 0.56 m inside a room that is black by design it was found by sweeping
    # for a prompt); it mirrors D2's note on the right; REF C4 "by the plant-room door"
    # each hook: where it hangs, and where its pale plate sits flush on ITS wall
    # (the plant hook faces down the hall off the -Z end wall; the desk hook off the
    # office's -X side wall). M7.0b: the plate mirrors D2's card, so when light does
    # reach the hook it has a shape; the box is panel-wide (1.0 x 0.6) so a level
    # sweep meets it in the dark, where the prompt is the only finder (T109)
    for spec: Array in [
            [Vector3(-0.9, 1.59, -(m.HALL_L * 0.5) + 0.16), Vector3(0, 0, -0.15), Vector3(0.16, 0.30, 0.02)],
            [Vector3(-1.94, 1.59, m.HALL_L * 0.5 + m.WALL + 0.44), Vector3(-0.05, 0, 0), Vector3(0.02, 0.30, 0.16)]]:
        var at: Vector3 = spec[0]
        var h = Props._interactable(m, at, Vector3(1.0, 0.6, 0.3), "take", 1.0, false)
        h.sound = "click"
        var plate := MeshInstance3D.new()
        var pb := BoxMesh.new()
        pb.size = spec[2]
        plate.mesh = pb
        plate.material_override = m.mat_wall
        plate.position = at + (spec[1] as Vector3)
        m.add_child(plate)
        var body := MeshInstance3D.new()
        var bm := BoxMesh.new()
        bm.size = Vector3(0.12, 0.22, 0.12)
        body.mesh = bm
        body.material_override = m.mat_wall
        body.position = Vector3(0, -0.2, 0)
        body.name = "lamp"
        h.add_child(body)
        out.append(h)
    return out


# the racks (M4.3): three dark boxes per room on the step-1 floor patches of the
# middle column (Thing.rack_pos), each with a white sheet (hidden until thrown)
# and a "sheet" Interactable (E 2 s). Returns {room: [{body, sheet, inter}]}.
static func _racks(m) -> Dictionary:
    var out := {}
    for room in ["A", "B"]:
        var rs := []
        for row in 3:
            var at: Vector3 = Thing.rack_pos(room, row)
            var size := Vector3(1.2, 0.9, 0.6)
            Props.slab(m, at - Vector3(size.x * 0.5, 0, size.z * 0.5), at + Vector3(size.x * 0.5, size.y, size.z * 0.5), m.mat_dark)
            var sheet := MeshInstance3D.new()
            var bm := BoxMesh.new()
            bm.size = size + Vector3(0.1, 0.06, 0.1)
            sheet.mesh = bm
            sheet.material_override = m.mat_wall
            sheet.gi_mode = GeometryInstance3D.GI_MODE_STATIC
            sheet.position = at + Vector3(0, size.y * 0.5 + 0.03, 0)
            sheet.visible = false
            m.add_child(sheet)
            var inter = Props._interactable(m, at + Vector3(0, size.y + 0.2, 0), Vector3(1.0, 0.3, 0.5), "sheet", 2.0, false)
            inter.sound = "click"
            rs.append({"body": at, "sheet": sheet, "inter": inter})
        out[room] = rs
    return out


# the shutters (M4.4): one slab per skylight row that grows across the opening
# from the hall side as its crank is held (main.gd drives the extent from the
# crank's progress; the return spring is the hold draining). Each crank is an
# Interactable at Thing.crank_pos with reach CRANK_REACH. Returns
# {room: [{mesh, crank, edge, sign, zc}]}.
static func _shutters(m) -> Dictionary:
    var out := {}
    for room in ["A", "B"]:
        var rows := []
        var sign: float = Thing.room_sign(room)
        var cx: float = Thing.room_cx(room)
        for row in 3:
            var r: Rect2 = Thing.pane_rect(room, row, 0)
            var zc: float = r.position.y + r.size.y * 0.5
            var mesh := MeshInstance3D.new()
            var bm := BoxMesh.new()
            bm.size = Vector3(m.SKY, 0.06, r.size.y + m.MULLION)
            mesh.mesh = bm
            mesh.material_override = m.mat_dark
            mesh.gi_mode = GeometryInstance3D.GI_MODE_STATIC      # in the SDF: a shut row blocks the sky's bounce too (the SDF follows with a lag - 3.4)
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            mesh.visible = false
            m.add_child(mesh)
            var crank = Props._interactable(m, Thing.crank_pos(room, row), Vector3(0.28, 0.28, 0.28), "crank", 3.0, false)
            crank.reach = Thing.CRANK_REACH
            crank.needs_lamp = Thing.crank_needs_lamp(room)
            crank.sound = "click"
            var handle := MeshInstance3D.new()
            var hb := BoxMesh.new()
            hb.size = Vector3(0.08, 0.3, 0.08)
            handle.mesh = hb
            handle.material_override = m.mat_dark
            crank.add_child(handle)
            rows.append({"mesh": mesh, "crank": crank, "edge": cx - sign * m.SKY * 0.5, "sign": sign, "zc": zc})
        out[room] = rows
    return out


# the sample card (M4.7, C6/D4): a pale card on A's centre rack's sheet; under it
# a dark unfaded rectangle - the only dark thing on the rack. E 3 s lifts the
# card aside. Returns {card, dark, inter}.
static func _card(m) -> Dictionary:
    # on A's centre sheet's top face, hidden until that sheet is thrown (M5.0j:
    # nothing floats over a bare rack); main.gd shows it with the sheet
    var sh: MeshInstance3D = m.racks["A"][1]["sheet"]
    var top: float = sh.position.y + (sh.mesh as BoxMesh).size.y * 0.5
    var rp: Vector3 = Thing.rack_pos("A", 1)
    var at := Vector3(rp.x, top, rp.z)
    var dark := MeshInstance3D.new()
    var db := BoxMesh.new()
    db.size = Vector3(0.30, 0.012, 0.20)
    dark.mesh = db
    dark.material_override = m.mat_dark
    dark.position = at + Vector3(0, 0.006, 0)
    m.add_child(dark)
    var card := MeshInstance3D.new()
    var cb := BoxMesh.new()
    cb.size = Vector3(0.32, 0.02, 0.22)
    card.mesh = cb
    card.material_override = m.mat_wall
    card.position = at + Vector3(0, 0.022, 0)
    m.add_child(card)
    var inter = Props._interactable(m, at + Vector3(0, 0.08, 0), Vector3(0.36, 0.12, 0.26), "card", 3.0, false)
    inter.sound = "pencil"
    inter.needs_lamp = true   # M5.0d (3.12): C6 needs the lamp carried - at step 5 no beam reaches A's racks
    var shown: bool = sh.visible   # the harness may have thrown the sheets already (--chores>=2, --sheets=A)
    card.visible = shown
    dark.visible = shown
    inter.collision_layer = 3 if shown else 0
    return {"card": card, "dark": dark, "inter": inter}

# the signature (M4.7, C7): a second, larger box around the desk log; main.gd
# offers "sign" only while the lamp hangs on the desk hook and C7 is next
static func _sign(m) -> Interactable:
    var z1 = m.HALL_L * 0.5 + m.WALL + m.OFF_D
    var sg = Props._interactable(m, Vector3(0.9, 1.04, z1 - 0.40), Vector3(0.52, 0.28, 0.42), "sign", 6.0, false)
    # M7.0f: 0.22 m above the log's box (they shared a centre), so D1 stays readable
    # while "sign" is offered - the sign swallowed the ray and the log said nothing
    sg.sound = "pencil"
    return sg

# the bolt on the yard door's inner face (M5.6, C7 done: bolt_enabled): a small
# pale slab, drawn back with E 4 s to open the door onto dusk (Ending A/B)
static func _bolt(m) -> Interactable:
    var pz1: float = -(m.HALL_L * 0.5 + m.WALL) - m.PLANT_D   # the door's inner face
    var c := Vector3(0.35, 1.20, pz1 + 0.03)
    var h := Vector3(0.06, 0.025, 0.02)
    m.yard_door.append(Props.slab(m, c - h, c + h, m.mat_wall))   # M6.0h: the bolt goes with the door when it opens
    var b := Props._interactable(m, Vector3(0.35, 1.20, pz1 + 0.05), Vector3(0.18, 0.10, 0.10), "bolt", 4.0, false)
    b.sound = "click"
    b.needs_dark = true   # M5.7: with the lamp lit the hold never fills - Ending B's door
    return b
