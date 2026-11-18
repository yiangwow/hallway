extends Node3D
# Builds the whole scene in code: a dead-ended hallway with two identical
# skylit rooms, a sun + SDFGI environment, a first-person player, and the
# ASCII post-process layer. All dimensions in metres, Y up, hallway along Z.

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

var mat_wall: StandardMaterial3D
var mat_floor: StandardMaterial3D
var mat_dark: StandardMaterial3D
var ascii_layer: CanvasLayer
var ascii_mat: ShaderMaterial
var player: CharacterBody3D
var creature: Node3D

func _ready() -> void:
    _materials()
    _build_hallway()
    for s: float in [-1.0, 1.0]:
        _build_room(s)
    _floor()
    _environment()
    _player()
    _creature()
    _ascii()
    _hud()
    _maybe_screenshot()

func _materials() -> void:
    mat_wall = StandardMaterial3D.new()
    mat_wall.albedo_color = Color(0.90, 0.90, 0.90)
    mat_wall.roughness = 0.95
    mat_floor = StandardMaterial3D.new()
    mat_floor.albedo_color = Color(0.62, 0.62, 0.62)
    mat_floor.roughness = 0.85
    mat_dark = StandardMaterial3D.new()
    mat_dark.albedo_color = Color(0.22, 0.22, 0.22)
    mat_dark.roughness = 0.7

# Axis-aligned solid slab from min corner to max corner, with collision.
func slab(a: Vector3, b: Vector3, mat: StandardMaterial3D) -> void:
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
    add_child(body)

func _floor() -> void:
    var x := HALL_W * 0.5 + WALL + ROOM + WALL
    var z := HALL_L * 0.5 + WALL
    slab(Vector3(-x, -WALL, -z), Vector3(x, 0, z), mat_floor)

func _build_hallway() -> void:
    var hx := HALL_W * 0.5           # inner half width  (1.5)
    var hz := HALL_L * 0.5           # inner half length (12)
    var dz := DOOR_W * 0.5
    for s: float in [-1.0, 1.0]:
        var x0 := s * hx
        var x1 := s * (hx + WALL)
        # side walls, split around the doorway
        slab(Vector3(x0, 0, -hz - WALL), Vector3(x1, HALL_H, -dz), mat_wall)
        slab(Vector3(x0, 0, dz), Vector3(x1, HALL_H, hz + WALL), mat_wall)
        slab(Vector3(x0, DOOR_H, -dz), Vector3(x1, HALL_H, dz), mat_wall)   # lintel
        # the room wall continues above the hallway ceiling up to room height
        var rz := ROOM * 0.5 + WALL
        slab(Vector3(x0, HALL_H, -rz), Vector3(x1, ROOM_H + WALL, rz), mat_wall)
    # end walls
    for s: float in [-1.0, 1.0]:
        slab(Vector3(-hx - WALL, 0, s * hz), Vector3(hx + WALL, HALL_H + WALL, s * (hz + WALL)), mat_wall)
    # ceiling
    slab(Vector3(-hx - WALL, HALL_H, -hz - WALL), Vector3(hx + WALL, HALL_H + WALL, hz + WALL), mat_wall)

func _build_room(s: float) -> void:
    var xin := s * (HALL_W * 0.5 + WALL)        # room inner face on the hallway side
    var xout := s * (HALL_W * 0.5 + WALL + ROOM) # room inner face on the far side
    var xwall := xout + s * WALL
    var rz := ROOM * 0.5
    var top := ROOM_H
    # far wall, front and back walls
    slab(Vector3(xout, 0, -rz - WALL), Vector3(xwall, top + WALL, rz + WALL), mat_wall)
    for t: float in [-1.0, 1.0]:
        slab(Vector3(xin, 0, t * rz), Vector3(xwall, top + WALL, t * (rz + WALL)), mat_wall)
    # ceiling with a square skylight cut out of its centre
    var cx := (xin + xout) * 0.5
    var k := SKY * 0.5
    slab(Vector3(xin, top, -rz), Vector3(xout, top + WALL, -k), mat_wall)
    slab(Vector3(xin, top, k), Vector3(xout, top + WALL, rz), mat_wall)
    slab(Vector3(xin, top, -k), Vector3(cx - s * k, top + WALL, k), mat_wall)
    slab(Vector3(cx + s * k, top, -k), Vector3(xout, top + WALL, k), mat_wall)
    # mullions: 3 x 3 panes
    var m := MULLION * 0.5
    for i: float in [-1.0, 1.0]:
        var g := i * SKY / 6.0
        slab(Vector3(cx - k, top, g - m), Vector3(cx + k, top + WALL, g + m), mat_dark)
        slab(Vector3(cx + g - m, top, -k), Vector3(cx + g + m, top + WALL, k), mat_dark)

func _environment() -> void:
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-62, 28, 0)
    sun.light_energy = 2.2
    sun.light_color = Color(1, 1, 1)
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 60.0
    sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
    add_child(sun)

    var env := Environment.new()
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
    var we := WorldEnvironment.new()
    we.environment = env
    # eye adaptation: the hall is lit only by bounce through two doorways and is
    # physically very dark next to the skylit rooms; let exposure follow the eye
    var ca := CameraAttributesPractical.new()
    ca.auto_exposure_enabled = true
    ca.auto_exposure_scale = 0.32
    ca.auto_exposure_min_sensitivity = 5.0
    ca.auto_exposure_max_sensitivity = 900.0
    ca.auto_exposure_speed = 1.5
    we.camera_attributes = ca
    add_child(we)

func _player() -> void:
    player = CharacterBody3D.new()
    player.set_script(load("res://player.gd"))
    var col := CollisionShape3D.new()
    var cap := CapsuleShape3D.new()
    cap.radius = 0.32
    cap.height = 1.8
    col.shape = cap
    player.add_child(col)
    player.position = Vector3(0, 0.95, 10.0)   # far end of the hall, looking down it
    add_child(player)

func _creature() -> void:
    # trial placement: seated in the left room near the far wall, facing the doorway
    var c := Node3D.new()
    c.set_script(load("res://creature.gd"))
    c.position = Vector3(-8.2, 0.0, -0.9)
    c.rotation.y = -0.55   # turned so the doorway sees it three-quarter, hanging arm on the near side
    add_child(c)
    creature = c

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
    ascii_layer.add_child(rect)
    add_child(ascii_layer)

func _hud() -> void:
    var layer := CanvasLayer.new()
    layer.layer = 11
    var l := Label.new()
    l.text = "TAB  ascii / graphics      ESC  mouse      SHIFT  run"
    l.position = Vector2(14, 10)
    l.modulate = Color(0.7, 0.7, 0.7, 0.8)
    layer.add_child(l)
    add_child(layer)

# feed the thing's screen position and apparent size to the ASCII shader every frame
func _process(_dt: float) -> void:
    if creature == null or ascii_mat == null or player == null or player.cam == null:
        return
    var cam: Camera3D = player.cam
    var centre := creature.global_position + Vector3(0, 1.6, 0)
    if cam.is_position_behind(centre):
        ascii_mat.set_shader_parameter("thing_on", 0.0)
        return
    var sp := cam.unproject_position(centre)
    var up := cam.unproject_position(centre + cam.global_basis.y * 2.4)
    ascii_mat.set_shader_parameter("thing_px", sp)
    ascii_mat.set_shader_parameter("thing_r", maxf(40.0, sp.distance_to(up) * 1.45))
    ascii_mat.set_shader_parameter("thing_on", 1.0)

func _unhandled_input(e: InputEvent) -> void:
    if e is InputEventKey and e.pressed and e.keycode == KEY_TAB:
        ascii_layer.visible = not ascii_layer.visible

# --shot=NAME [--ascii=0|1] [--pos=x,y,z] [--yaw=deg] [--pitch=deg]
# Waits for SDFGI to settle, writes shots/NAME.png, quits.
func _maybe_screenshot() -> void:
    var args := {}
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--") and "=" in a:
            var kv := a.substr(2).split("=", true, 1)
            args[kv[0]] = kv[1]
    if args.has("ascii"):
        ascii_layer.visible = args["ascii"] == "1"
    if args.has("pos"):
        var p := (args["pos"] as String).split(",")
        player.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
    if args.has("yaw"):
        player.look_at_yaw(float(args["yaw"]))
    if args.has("pitch"):
        player.cam.rotation.x = deg_to_rad(float(args["pitch"]))
    if not args.has("shot"):
        return
    for i in 120:
        await get_tree().process_frame
    var img := get_viewport().get_texture().get_image()
    # res:// is read-only inside an exported build, so fall back to user://
    var path := "res://shots/%s.png" % args["shot"]
    if not OS.has_feature("editor"):
        path = "user://%s.png" % args["shot"]
    var err := img.save_png(path)
    print("SHOT %s -> %s (%dx%d) at %s" % [path, error_string(err), img.get_width(), img.get_height(), ProjectSettings.globalize_path(path)])
    get_tree().quit()
