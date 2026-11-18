extends CharacterBody3D
# First-person walker. WASD, mouse look, Shift to run, Esc frees the mouse.

const WALK := 3.2
const RUN := 5.6
const SENS := 0.0022
const EYE := 0.75   # camera height above the capsule centre (centre sits at 0.9)

var yaw := 0.0
var pitch := 0.0
var cam: Camera3D

func _ready() -> void:
    cam = Camera3D.new()
    cam.position = Vector3(0, EYE, 0)
    cam.fov = 80.0
    cam.near = 0.05
    add_child(cam)
    cam.make_current()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func look_at_yaw(deg: float) -> void:
    yaw = deg_to_rad(deg)
    rotation.y = yaw

func _unhandled_input(e: InputEvent) -> void:
    if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= e.relative.x * SENS
        pitch = clampf(pitch - e.relative.y * SENS, -1.45, 1.45)
        rotation.y = yaw
        cam.rotation.x = pitch
    elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
    elif e is InputEventMouseButton and e.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(dt: float) -> void:
    var d := Vector3.ZERO
    if Input.is_physical_key_pressed(KEY_W): d.z -= 1
    if Input.is_physical_key_pressed(KEY_S): d.z += 1
    if Input.is_physical_key_pressed(KEY_A): d.x -= 1
    if Input.is_physical_key_pressed(KEY_D): d.x += 1
    d = (transform.basis * d).normalized()
    var sp := RUN if Input.is_physical_key_pressed(KEY_SHIFT) else WALK
    velocity.x = d.x * sp
    velocity.z = d.z * sp
    velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * dt
    move_and_slide()
