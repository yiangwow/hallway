extends CharacterBody3D
# First-person walker. WASD, mouse look, Shift to run, Esc frees the mouse.

const WALK := 3.2
const RUN := 5.6
const LAMP_WALK := 1.6     # with the lamp lit you walk at its pace (M4.6b); Shift is ignored. T120 (owner: "no need to make lamp walk so slow"): 1.0 -> 1.6, half of WALK. Not higher: the thing rides at 2.2 m per 2 s step = 1.1 m/s, so past ~1.6 it simply falls behind and the ride stops reading
var lamp_lit := false      # main.gd sets it from lighting.lamp_on
const SENS := 0.0022
const EYE := 0.75   # camera height above the capsule centre (centre sits at 0.9)

var yaw := 0.0
var pitch := 0.0
var cam: Camera3D
var capture_mouse := true   # main.gd sets false under the harness
var has_moved := false      # first movement input; the start line fades on it
var frozen := false         # walking and the hands held: the bleach, and either ending
var look_frozen := false    # the look too (M6.0h): only the bleach; the endings leave the eyes free to look up
signal stepped              # a footfall (M3.5): main plays the step
const STRIDE := 0.75        # metres per footfall; the pace follows the speed
var stride := 0.0

func _ready() -> void:
    cam = Camera3D.new()
    cam.position = Vector3(0, EYE, 0)
    cam.fov = 80.0
    cam.near = 0.05
    add_child(cam)
    cam.make_current()
    if capture_mouse:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func look_at_yaw(deg: float) -> void:
    yaw = deg_to_rad(deg)
    rotation.y = yaw

func look_at_pitch(deg: float) -> void:
    pitch = clampf(deg_to_rad(deg), -1.45, 1.45)
    cam.rotation.x = pitch

func _unhandled_input(e: InputEvent) -> void:
    if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
        # the system key works frozen too (M6.0b): the mouse is freed after either ending
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
        return
    if look_frozen:
        return
    if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= e.relative.x * SENS
        pitch = clampf(pitch - e.relative.y * SENS, -1.45, 1.45)
        rotation.y = yaw
        cam.rotation.x = pitch
    elif e is InputEventMouseButton and e.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(dt: float) -> void:
    var d := Vector3.ZERO
    if frozen:
        velocity.x = 0.0
        velocity.z = 0.0
        velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * dt
        move_and_slide()
        return
    if Input.is_physical_key_pressed(KEY_W): d.z -= 1
    if Input.is_physical_key_pressed(KEY_S): d.z += 1
    if Input.is_physical_key_pressed(KEY_A): d.x -= 1
    if Input.is_physical_key_pressed(KEY_D): d.x += 1
    if d != Vector3.ZERO:
        has_moved = true
    d = (transform.basis * d).normalized()
    var sp := LAMP_WALK if lamp_lit else (RUN if Input.is_physical_key_pressed(KEY_SHIFT) else WALK)
    velocity.x = d.x * sp
    velocity.z = d.z * sp
    velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * dt
    move_and_slide()
    var ground := Vector2(velocity.x, velocity.z).length()
    if is_on_floor() and ground > 0.5:
        stride += ground * dt
        if stride >= STRIDE:
            stride -= STRIDE
            stepped.emit()
    else:
        stride = 0.0
