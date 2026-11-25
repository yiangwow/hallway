extends StaticBody3D
class_name Interactable
# Something the caretaker can hold E on. Physics layer 2 so the interaction ray
# sees it and nothing else. Prompts are <= 3 words (GUARDRAILS 3.13). `done`
# fires once per completed hold; `reset()` re-arms it (racks, cranks re-use it).

signal done

@export var prompt := "use"
@export var hold_s := 1.0
@export var needs_ascii := false
@export var needs_lamp := false   # the lamp CARRIED, lit or not (M4.5): the valve works by feel in the dark
@export var sound := "click"      # played on done (M4.0i): cranks/valve/lamp click; plaques "", the log "pencil"
@export var reach := 2.2          # the hand's reach (M4.4): cranks 0.8, so the hand stands where the crank stands
@export var needs_dark := false   # the lamp lit and carried freezes the hold (M5.7): the prompt shows, nothing fills - the yard door's bolt
@export var text := ""            # found text (M5.1, 3.13): <= 25 words, on layer 11 only while E is held on this; never about the thing, the rule or the player
var progress := 0.0
var fired := false

func _ready() -> void:
    collision_layer = 3   # the ray sees it (2) and the player collides with it (1)
    collision_mask = 0

# what the HUD shows: the verb, or nothing. A refused or spent interactable says
# nothing - the rule is told by the light, never by text (GUARDRAILS 3.13)
func label(ascii_on: bool, lamp_held: bool) -> String:
    if fired or (needs_ascii and not ascii_on) or (needs_lamp and not lamp_held):
        return ""
    return prompt

func can_use(ascii_on: bool, lamp_held: bool) -> bool:
    return not fired and (ascii_on or not needs_ascii) and (lamp_held or not needs_lamp)

func reset() -> void:
    fired = false
    progress = 0.0
