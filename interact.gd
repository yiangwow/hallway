extends Node
class_name Interact
# A 2.2 m ray from the camera on physics layer 2. Holding E on an Interactable
# fills its hold bar on the game clock; at 1.0 it fires `done` once. Releasing
# early drains the bar. Owns the HUD prompt and bar (layer 11, greyscale).

const REACH := 2.2

var main: Node3D
var ray: RayCast3D
var target: Interactable = null
var prompt: RichTextLabel
var backing: ColorRect
var found: RichTextLabel          # found text (M5.1): the target's `text`, above the prompt, only while E is held
var found_bg: ColorRect
var font: SystemFont
var hold_frac := 0.0

const DIM := "6a6a6a"
const LIT := "f2f2f2"

func setup(m: Node3D, cam: Camera3D, hud: CanvasLayer) -> void:
    main = m
    ray = RayCast3D.new()
    ray.target_position = Vector3(0, 0, -REACH)
    ray.collision_mask = 3   # walls (1) block the ray; only layer-2 hits become targets
    ray.collide_with_areas = false
    cam.add_child(ray)
    # the prompt lives in the glyph vocabulary: a monospace face on the 8x16 grid,
    # and the hold is told by its letters brightening left to right - no bar (3.16)
    font = SystemFont.new()
    font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "monospace"])
    backing = ColorRect.new()          # a ' ' strip behind the prompt (M2.0c)
    backing.color = Color(0, 0, 0)
    backing.visible = false
    hud.add_child(backing)
    prompt = RichTextLabel.new()
    prompt.bbcode_enabled = true
    prompt.scroll_active = false
    prompt.fit_content = true
    prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
    prompt.add_theme_font_override("normal_font", font)
    prompt.add_theme_font_size_override("normal_font_size", 16)
    prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
    prompt.visible = false
    hud.add_child(prompt)
    found_bg = ColorRect.new()
    found_bg.color = Color(0, 0, 0)
    found_bg.visible = false
    hud.add_child(found_bg)
    found = RichTextLabel.new()
    found.bbcode_enabled = true
    found.scroll_active = false
    found.fit_content = true
    found.autowrap_mode = TextServer.AUTOWRAP_OFF
    found.add_theme_font_override("normal_font", font)
    found.add_theme_font_size_override("normal_font_size", 16)
    found.add_theme_constant_override("line_separation", 0)
    found.mouse_filter = Control.MOUSE_FILTER_IGNORE
    found.visible = false
    hud.add_child(found)

# the found text (M5.1, GUARDRAILS 3.13): the target's own words, <= 25, in the
# glyph face on the cell grid, a ' ' strip behind, stacked above the prompt;
# on screen only while E is held on it - let go and it is gone
func _show_found(text: String) -> void:
    var lines := text.split("\n")
    var w := 0.0
    for l in lines:
        w = maxf(w, font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
    found.text = "[color=#bdbdbd]%s[/color]" % text
    var vp := found.get_viewport_rect().size
    var py: float = floor((vp.y - 96.0) / 16.0) * 16.0                 # the prompt's row
    found.position = Vector2(floor((vp.x - w) * 0.5 / 8.0) * 8.0, py - 16.0 * (lines.size() + 1))
    found_bg.position = found.position - Vector2(8, 0)
    found_bg.size = Vector2(ceil(w / 8.0) * 8.0 + 16.0, 16.0 * lines.size() + 8.0)
    found_bg.visible = true
    found.visible = true

func _hide_found() -> void:
    found.visible = false
    found_bg.visible = false
    Interact.register_actions()

# the three actions, registered at the top of main's _ready (M5.0k) so no prop
# built before the HUD asks the InputMap about a missing action
static func register_actions() -> void:
    for pair in [["interact", KEY_E], ["clipboard", KEY_C], ["lamp", KEY_L]]:
        if not InputMap.has_action(pair[0]):
            InputMap.add_action(pair[0])
            var ev := InputEventKey.new()
            ev.physical_keycode = pair[1]
            InputMap.action_add_event(pair[0], ev)

# letters up to `frac` of the word are lit; snapped to the cell grid, bottom centre
func _show_prompt(text: String, frac: float) -> void:
    var n := text.length()
    var lit := int(floor(frac * n + 1e-6))
    var bb := ""
    for i in n:
        bb += "[color=#%s]%s[/color]" % [LIT if i < lit else DIM, text[i]]
    prompt.text = bb
    var vp := prompt.get_viewport_rect().size
    var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
    prompt.position = Vector2(floor((vp.x - w) * 0.5 / 8.0) * 8.0, floor((vp.y - 96.0) / 16.0) * 16.0)
    backing.position = prompt.position - Vector2(8, 0)
    backing.size = Vector2(ceil(w / 8.0) * 8.0 + 16.0, 16.0 * 1.5)
    backing.visible = true
    prompt.visible = true

func _process(_dt: float) -> void:
    if main == null or ray == null:
        return
    var dt: float = main.clock_dt
    # the bleach (3.10, gate M2): the hand stops - progress drains, nothing fires, no prompt
    if main.player != null and main.player.frozen:
        if target != null:
            target.progress = maxf(target.progress - dt * 2.0, 0.0)
        prompt.visible = false
        backing.visible = false
        _hide_found()
        return
    ray.force_raycast_update()   # T119: the cast is exact for THIS frame's camera - after a teleport (every sim) the collider was a frame or two stale
    var hit := ray.get_collider() as Interactable if ray.is_colliding() else null
    if hit != null:
        var d := ray.global_position - ray.get_collision_point()
        if Vector2(d.x, d.z).length() > hit.reach:
            hit = null                            # beyond its reach along the floor (M4.4): a crank needs the hand beside it
    if hit != target:
        if target != null:
            target.progress = 0.0
        target = hit
    var ascii_on: bool = main.ascii_layer.visible
    var lamp_on: bool = main.lamp_where == "held"           # carried, lit or not (M4.5)
    if target == null:
        prompt.visible = false
        backing.visible = false
        _hide_found()
        return
    if target.text != "" and Input.is_action_pressed("interact"):
        _show_found(target.text)                 # reading is holding (M5.1); spent or not, the words are there
    else:
        _hide_found()
    var lbl := target.label(ascii_on, lamp_on)
    var lit: bool = lamp_on and main.lighting.lamp_on
    var usable := target.can_use(ascii_on, lamp_on) and not (target.needs_dark and lit)   # M5.7: the bolt waits for the dark; the prompt still shows
    if usable and Input.is_action_pressed("interact"):
        target.progress = minf(target.progress + dt / maxf(0.05, target.hold_s), 1.0)
        if target.progress >= 1.0 - 1e-6 and not target.fired:   # 180 x 1/60 sums to 0.99999...
            target.fired = true
            if main.audio != null and target.sound != "":
                main.audio.play(target.sound)  # the interactable's own sound (M4.0i); a read is silent
            target.done.emit()
    else:
        target.progress = maxf(target.progress - dt * 2.0, 0.0)
    if lbl == "":
        prompt.visible = false           # nothing on screen about the rule or the player's state (3.13)
        backing.visible = false
    else:
        _show_prompt(lbl, target.progress if usable else 0.0)
