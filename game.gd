extends RefCounted
class_name Game
# The caretaker's list. Pure state, no scene references, so tests can build one
# headless. Chores complete in order; each completion is a light change (the
# building is the clock, pillar 2). The sun step is the larger of chores done
# and wall-time periods, capped at 5.

signal chore_done(id: String)

const STEP_S := 180.0        # wall-time per sun step
const MAX_STEP := 5

# id, the line on the clipboard, how many parts it takes, the room it ends in
const LIST := [
    ["C1", "read the meters", 3, "office"],
    ["C2", "sheets on A's racks", 3, "A"],
    ["C3", "shutters, B", 3, "B"],
    ["C4", "lamp by the plant door. boiler", 1, "plant"],   # T119: the list says WHERE the lamp hangs - the hall's end is black at step 3 (measured), and the caretaker wrote this list
    ["C5", "shutters, A, with the lamp", 3, "A"],      # M7.0b: A's cranks need it carried
    ["C6", "sample card, A, with the lamp", 1, "A"],   # M7.0b: so does the card (M5.0d)
    ["C7", "hang the lamp. sign the log", 1, "office"],
]

var chores: Array[Dictionary] = []

func _init() -> void:
    for row in LIST:
        chores.append({"id": row[0], "text": row[1], "done": false, "parts": row[2], "got": 0, "room": row[3]})

static func step_for(done: int, t: float) -> int:
    # wall-time steps the sun (Q2) but never past 2 while C3 is open (M5.0l):
    # C3's cranks stand in their rows' step-2 light - the first death's lesson
    # is told there, and a clock that moved the light off them would untell it
    var wall := int(t / STEP_S)
    if done < 3:
        wall = mini(wall, 2)
    return mini(MAX_STEP, maxi(done, wall))

func index_of(id: String) -> int:
    for i in chores.size():
        if chores[i]["id"] == id:
            return i
    return -1

# COLOUR's gate (3.14, M5.0h): five chores done AND the clipboard shown since -
# the word takes the hue first (a), the aura and the bleach only after (b, c)
var colour_seen := false

func colour_unlocked() -> bool:
    return colour_seen and done_count() >= 5

func done_count() -> int:
    var n := 0
    for c in chores:
        if c["done"]:
            n += 1
    return n

func room_of(id: String) -> String:
    var i := index_of(id)
    return chores[i]["room"] if i >= 0 else ""

# where the next chore ends ("" when all done) and where the last finished one was ("" before C1)
func next_room() -> String:
    var n := next_id()
    return room_of(n) if n != "" else ""

# the room of the last done chore that was in A or B ("" before any): the
# thing's re-pick room when the player is in the hall, office or plant room
func last_ab_room() -> String:
    var last := ""
    for c in chores:
        if c["done"] and (c["room"] == "A" or c["room"] == "B"):
            last = c["room"]
    return last

func last_room() -> String:
    var last := ""
    for c in chores:
        if c["done"]:
            last = c["room"]
    return last

func next_id() -> String:
    for c in chores:
        if not c["done"]:
            return c["id"]
    return ""

# one part of a chore (a plaque read, a sheet thrown). It lands whatever the
# order (M6.0a: the prop is already spent when this is asked - a sheet thrown
# before plaque B used to strand C2 for good); chores still COMPLETE in list
# order, so an early part waits for its turn
func part(id: String) -> bool:
    var i := index_of(id)
    if i < 0 or chores[i]["done"]:
        return false
    chores[i]["got"] += 1
    _settle()
    return true

# while the next chore in order has all its parts, complete it (one sun step each)
func _settle() -> void:
    while true:
        var n := next_id()
        if n == "":
            return
        var i := index_of(n)
        if chores[i]["got"] < chores[i]["parts"]:
            return
        complete(n)

# refuses anything but the next chore in order
func complete(id: String) -> bool:
    var i := index_of(id)
    if i < 0 or chores[i]["done"] or id != next_id():
        return false
    chores[i]["done"] = true
    chores[i]["got"] = chores[i]["parts"]
    chore_done.emit(id)
    return true

func complete_upto(n: int) -> void:
    for i in mini(n, chores.size()):
        complete(chores[i]["id"])

# the clipboard as the caretaker reads it
func clipboard_text() -> String:
    var lines := PackedStringArray()
    for c in chores:
        lines.append("%s %s" % ["[x]" if c["done"] else "[ ]", c["text"]])
    return "\n".join(lines)

# COLOUR (a) (M5.3, GUARDRAILS 3.14): the clipboard as bbcode; once C5 is done the
# first word of the next line - `word`, "sample" - carries the hue for the rest
# of the game. One word, once, nowhere else. The brackets are escaped: "[x]" is text.
const HUE_HEX := "b894eb"   # Lighting.HUE, Color(0.72, 0.58, 0.92)

func clipboard_bb(word: String) -> String:
    var lines := PackedStringArray()
    var coloured := false
    for c in chores:
        var text: String = c["text"]
        if not coloured and done_count() >= 5 and c["id"] == "C6" and text.begins_with(word):
            text = "[color=#%s]%s[/color]%s" % [HUE_HEX, word, text.substr(word.length())]
            coloured = true
        lines.append("%s %s" % ["[lb]x[rb]" if c["done"] else "[lb] [rb]", text])
    return "\n".join(lines)
