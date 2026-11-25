# In-engine simulations (M3.0c): tools/sim.sh NAME -> main.gd::_run_sim -> Sims.run.
# Each case returns [ok, detail]; `m` is the main node, untyped on purpose (main.gd
# has no class_name and a cyclic preload buys nothing). Awaits run on main's fixed
# clock; the SIM line and the quit stay in main.gd.
extends RefCounted


# stand, aim and hold E for `frames` (M6.0j: the route is these, one after another)
static func _hold(m, pos: Vector3, yaw: float, pitch: float, frames: int) -> void:
    m.player.position = pos
    m.player.look_at_yaw(yaw)
    m.player.look_at_pitch(pitch)
    for i in 3:
        await m.get_tree().process_frame
    Input.action_press("interact")
    for i in frames:
        await m.get_tree().process_frame
    Input.action_release("interact")
    for i in 3:
        await m.get_tree().process_frame

# how many of the 3x3 ASCII cells centred on a world point are blank (M7.0g): the
# body is a hole, so 9/9 means it fills that spot and 0 means the spot is readable
static func _blank3(m, at: Vector3) -> int:
    var sp: Vector2 = m.player.cam.unproject_position(at)
    var img: Image = m.get_viewport().get_texture().get_image()
    var cx := int(sp.x / 8.0)
    var cy := int(sp.y / 16.0)
    var blank := 0
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            var mx := 0.0
            for py in 16:
                for px in 8:
                    var c := img.get_pixel(clampi((cx + dx) * 8 + px, 0, img.get_width() - 1), clampi((cy + dy) * 16 + py, 0, img.get_height() - 1))
                    mx = maxf(mx, maxf(c.r, maxf(c.g, c.b)))
            if mx < 0.06:
                blank += 1
    return blank

# The doorway as the eye reads it (M7.0g): the four corners of the yard opening
# projected, then every whole 8x16 cell in that box scored the way tools/cells.py
# levels() does - mean luminance -> one of the ten ramp steps. Returns [dark
# fraction (levels 0-3, ' .:-'), body inside the box]. A blown frame scores 0.
static func _door_read(m, corners: Array, body) -> Array:
    var img: Image = m.get_viewport().get_texture().get_image()
    var x0 := INF
    var y0 := INF
    var x1 := -INF
    var y1 := -INF
    for c: Vector3 in corners:
        var sp: Vector2 = m.player.cam.unproject_position(c)
        x0 = minf(x0, sp.x); x1 = maxf(x1, sp.x)
        y0 = minf(y0, sp.y); y1 = maxf(y1, sp.y)
    var dark := 0
    var total := 0
    var cx0 := int(ceil(x0 / 8.0))
    var cy0 := int(ceil(y0 / 16.0))
    for cy in range(cy0, int(y1 / 16.0)):
        for cx in range(cx0, int(x1 / 8.0)):
            if cx < 0 or cy < 0 or (cx + 1) * 8 > img.get_width() or (cy + 1) * 16 > img.get_height():
                continue
            var sum := 0.0
            for py in 16:
                for px in 8:
                    var c := img.get_pixel(cx * 8 + px, cy * 16 + py)
                    sum += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
            var lvl := mini(9, int(sum / 128.0 * 9.99))
            total += 1
            if lvl <= 3:
                dark += 1
    var inside := false
    if body != null:
        var bp: Vector2 = m.player.cam.unproject_position(body.global_position + Vector3(0, 0.9, 0))
        inside = bp.x >= x0 and bp.x <= x1 and bp.y >= y0 and bp.y <= y1
    return [float(dark) / maxf(1.0, float(total)), inside, total]

static func _tap(m, action: String) -> void:
    Input.action_press(action)
    await m.get_tree().process_frame
    Input.action_release(action)
    await m.get_tree().process_frame

static func _wait(m, until: float) -> void:
    while m.clock_t < until:
        await m.get_tree().process_frame

static func _key(code: Key, pressed: bool) -> InputEventKey:
    var e := InputEventKey.new()
    e.physical_keycode = code
    e.keycode = code
    e.pressed = pressed
    return e

static func run(m, name: String) -> Array:
    var ok := false
    var detail := ""
    match name:
        "smoke":
            # args: (none)
            var t0 = m.clock_t
            for i in 30:
                await m.get_tree().process_frame
            ok = m.player != null and m.clock_t > t0 + 0.4   # the thing is absent unless --thing
            detail = "clock %.3f -> %.3f" % [t0, m.clock_t]
        "interact":
            # args: (none)
            var box = m._test_box(m.player.position + Vector3(0, 0.65, -1.5))
            box.hold_s = 3.0
            var hits := [0]                    # array: lambdas capture locals by value
            box.done.connect(func() -> void: hits[0] += 1)
            await m.get_tree().process_frame
            await m.get_tree().process_frame
            var aimed = m.interact.target == box
            Input.action_press("interact")
            for i in 180:                     # exactly hold_s on the fixed clock
                await m.get_tree().process_frame
            Input.action_release("interact")
            await m.get_tree().process_frame
            var after_hold: int = hits[0]
            var hidden = not m.interact.prompt.visible   # spent: says nothing
            box.reset()
            await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 90:                      # 1.5 s of 3, then let go
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 40:
                await m.get_tree().process_frame
            ok = aimed and after_hold == 1 and hits[0] == 1 and hidden
            detail = "aimed=%s held3s->%d prompt_hidden=%s released1.5s->%d" % [aimed, after_hold, hidden, hits[0] - after_hold]
        "exposure_ramp":
            # args: (none)
            m.player.position = Vector3(0, 0.95, 0)
            m.lighting.set_zone("hall", true)
            await m.get_tree().process_frame
            m.player.position = Vector3(-3.0, 0.95, 0)     # step into A; _process re-targets the ramp
            var target_e: float = m.lighting.zone_exposure["A"]
            var frames := 0
            while frames < 400 and not is_equal_approx(m.lighting.ca.exposure_multiplier, target_e):
                await m.get_tree().process_frame
                frames += 1
            ok = frames >= 119 and frames <= 121
            detail = "ramp frames=%d" % frames
        "interact_wall":
            # args: (none)
            # the player stands outside room A's +Z wall; the box is inside the room
            m.player.position = Vector3(-6.0, 0.95, 5.6)
            m.player.look_at_yaw(0.0)
            var box = m._test_box(Vector3(-6.0, 1.6, 4.0))
            var hits := [0]
            box.done.connect(func() -> void: hits[0] += 1)
            for i in 3:
                await m.get_tree().process_frame
            var blocked = m.interact.target == null
            Input.action_press("interact")
            for i in 120:
                await m.get_tree().process_frame
            Input.action_release("interact")
            ok = blocked and hits[0] == 0
            detail = "target_null=%s done=%d" % [blocked, hits[0]]
        "office_floor":
            # args: (none)
            m.player.position = Vector3(0, 0.95, 14.0)
            for i in 60:
                await m.get_tree().process_frame
            ok = absf(m.player.position.y - 0.95) < 0.15 and Lighting.zone_at(m.player.position) == "office"
            detail = "y=%.2f zone=%s" % [m.player.position.y, Lighting.zone_at(m.player.position)]
        "plant_floor":
            # args: (none)
            m.player.position = Vector3(0, 0.95, -14.5)
            for i in 60:
                await m.get_tree().process_frame
            ok = absf(m.player.position.y - 0.95) < 0.15 and Lighting.zone_at(m.player.position) == "plant"
            detail = "y=%.2f zone=%s" % [m.player.position.y, Lighting.zone_at(m.player.position)]
        "c1":
            # args: (none)
            var got := []
            # plaque A with the reading off: refused
            m.player.position = Vector3(-3.0, 0.95, -1.5)
            m.player.look_at_yaw(-90.0)
            m.player.look_at_pitch(-10.0)
            m.set_ascii(false)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 90:
                await m.get_tree().process_frame
            Input.action_release("interact")
            got.append(m.game.chores[0]["got"])
            # with the reading on: one part
            m.set_ascii(true)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 66:
                await m.get_tree().process_frame
            Input.action_release("interact")
            got.append(m.game.chores[0]["got"])
            # plaque B
            m.player.position = Vector3(3.0, 0.95, -1.5)
            m.player.look_at_yaw(90.0)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 66:
                await m.get_tree().process_frame
            Input.action_release("interact")
            got.append(m.game.chores[0]["got"])
            # the desk log
            var z1 = m.HALL_L * 0.5 + m.WALL + m.OFF_D
            m.player.position = Vector3(1.6, 0.95, z1 - 1.4)   # beside the chair, not in it
            m.player.look_at_yaw(145.0)
            m.player.look_at_pitch(-36.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed_log = m.interact.target != null and m.interact.target.prompt == "log entry"
            Input.action_press("interact")
            for i in 190:
                await m.get_tree().process_frame
            Input.action_release("interact")
            await m.get_tree().process_frame
            var plays_c1: int = m.audio.plays                             # M4.0i: two silent reads, one pencil
            ok = got == [0, 1, 2] and aimed_log and m.game.chores[0]["done"] and m.lighting.step == 1 and plays_c1 == 1
            detail = "got=%s aimed_log=%s C1=%s step=%d plays=%d" % [got, aimed_log, m.game.chores[0]["done"], m.lighting.step, plays_c1]
        "boot_mode":
            # args: (none)
            var off = not m.ascii_layer.visible
            m.set_ascii(true)
            var on = m.ascii_layer.visible
            m.set_ascii(false)
            ok = off and on and not m.ascii_layer.visible
            detail = "boot_hidden=%s tab_shows=%s" % [off, on]
        "start_fade":
            # args: --start=1
            # --start=1 is passed by the caller; press E at 1 s, the line must be gone by 3.2 s
            while m.clock_t < 1.0:
                await m.get_tree().process_frame
            var at1 = m.start_line.visible and m.start_line.modulate.a >= 0.99 and m.start_line.text.contains("L the lamp")   # M6.0g
            Input.action_press("interact")
            while m.clock_t < 3.2:
                await m.get_tree().process_frame
            Input.action_release("interact")
            ok = at1 and not m.start_line.visible
            detail = "visible_at_1s=%s hidden_at_3.2s=%s" % [at1, not m.start_line.visible]
        "start_timeout":
            # args: --start=1
            while m.clock_t < 7.9:
                await m.get_tree().process_frame
            var at79 = m.start_line.visible
            while m.clock_t < 10.1:
                await m.get_tree().process_frame
            ok = at79 and not m.start_line.visible
            detail = "visible_at_7.9s=%s hidden_at_10.1s=%s" % [at79, not m.start_line.visible]
        "spawn":
            # args: --chores=2
            # caller passes --chores=2: the spawn happened in _ready
            var has_omni = m.lighting.seat_light != null
            var no_body_yet: bool = m.creature == null            # M4.0g: the body comes at the first cut
            m._body_at(m.seat)                                   # bind it by hand to check the binding
            var sp: Vector3 = m.seat["pos"]
            var body: bool = m.creature != null and Vector2(m.creature.position.x - sp.x, m.creature.position.z - sp.z).length() <= 1.8   # on the floor, 1.6 m off a wall seat
            m.set_ascii(false)
            var hidden: bool = m.creature != null and not m.creature.visible
            m.set_ascii(true)
            var shown: bool = m.creature != null and m.creature.visible
            m.player.position = Vector3(6.3, 0.95, 3.5)      # V5
            m.player.look_at_yaw(0.0)
            for i in 3:
                await m.get_tree().process_frame
            var in_view: bool = not m.seat.is_empty() and m.player.cam.is_position_in_frustum(m.seat["pos"])
            ok = has_omni and no_body_yet and body and hidden and shown and in_view
            detail = "omni=%s no_body_at_spawn=%s body_near_seat=%s hidden_off=%s shown_on=%s seat_in_V5=%s" % [has_omni, no_body_yet, body, hidden, shown, in_view]
        "cut_wait":
            # args: --chores=2 --lamp=1 --thing=8.5,0,1.5
            # caller passes --chores=2 --lamp=1 --thing=8.5,0,1.5: the lamp change
            # at t=0 makes a re-pick due at t=1 whose destination differs from the
            # overridden seat; watched from V5 it must wait, looked away from it cuts
            var before: Vector3 = m.lighting.seat_light.position
            m.player.position = Vector3(6.3, 0.95, 3.5)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(0.0)
            for i in 300:
                await m.get_tree().process_frame
            var held: bool = m.lighting.seat_light != null and m.lighting.seat_light.position == before and m.cut_due >= 0.0
            var dbg := "due=%.2f omni_null=%s pos=%s deaths=%d bleach_t=%.1f dose=%.2f seat=%s" % [m.cut_due, m.lighting.seat_light == null, str(m.lighting.seat_light.position) if m.lighting.seat_light != null else "-", m.deaths, m.bleach_t, m.dose, m.seat_line()]
            var seen_before: bool = m._seat_seen(m.seat)
            m.player.look_at_pitch(80.0)          # the ceiling: every seat leaves the frustum
            for i in 90:
                await m.get_tree().process_frame
            var moved: bool = m.lighting.seat_light != null and m.lighting.seat_light.position != before and m.cut_due < 0.0
            ok = held and seen_before and moved
            detail = "held5s=%s seen=%s moved_after_lookaway=%s from=%.2f,%.2f,%.2f to=%s | %s" % [held, seen_before, moved, before.x, before.y, before.z, m.seat_line(), dbg]
        "death":
            # args: --chores=2
            # caller passes --chores=2: park the capsule 0.4 m off the seat in its
            # beam; +0.5/s reaches 3.0 at 6 s (M4.0e) -> bleach -> restart at hall z=0
            var s0: Dictionary = m.seat.duplicate()
            var seat_line0: String = m.seat_line()
            var park: Vector3 = s0["pos"] + s0["normal"] * 0.7   # 0.7: clear of the row-1 crank box that shares r1c2's seat (M4.4)
            m.player.position = Vector3(park.x, 0.95, park.z)
            m._body_at(m.seat)                                   # as if the first cut had happened (M4.0g)
            var to_body: Vector3 = m.creature.global_position - m.player.position   # facing the body (M4.0b: the aura must fade with it)
            m.player.look_at_yaw(rad_to_deg(atan2(-to_body.x, -to_body.z)))
            var t0 = m.clock_t
            await m.get_tree().process_frame
            var lit = m._in_seat_light()
            var t_bleach := -1.0
            var aura_before := 0.0
            for i in 480:
                await m.get_tree().process_frame
                aura_before = maxf(aura_before, m.aura_on)
                if m.bleach_t >= 0.0:
                    t_bleach = m.clock_t - t0
                    break
            for i in 72:
                await m.get_tree().process_frame
            var exp_max: float = m.lighting.ca.exposure_multiplier
            var frozen_held: bool = m.player.frozen and m.player.position.distance_to(Vector3(park.x, 0.95, park.z)) < 0.05
            for i in 200:
                await m.get_tree().process_frame
                if m.bleach_t < 0.0 and m.deaths > 0:
                    break
            await m.get_tree().process_frame          # the first tick after the restart
            var exp_restart: float = m.lighting._base_exp          # the base: the kept seat breathes the multiplier (M4.0d)
            var snapped: bool = is_equal_approx(exp_restart, m.lighting.zone_exposure["hall"] * Lighting.STEP_EXP[m.lighting.step])
            # M4.0d: the seat, bite and body are kept; the aura fades (the body is
            # behind B's wall from the hall) - check after the 2 s gate
            for i in 150:
                await m.get_tree().process_frame
            var raw_on = m.ascii_mat.get_shader_parameter("thing_on")
            var aura_dead: bool = aura_before > 0.0 and m.aura_on == 0.0 and raw_on != null and float(raw_on) == 0.0
            var kept: bool = m.lighting.seat_light != null and m.seat_line() == seat_line0 and m.creature != null
            var freed: bool = kept and aura_dead
            var restarted: bool = m.player.position.distance_to(Vector3(0, 0.95, 0)) < 0.05 and not m.player.frozen and not m.blank.visible
            var facing = int(round(rad_to_deg(m.player.yaw)))
            var back_to: String = m.game.next_room() if m.game.next_room() != "" else m.game.last_room()
            var want_yaw: int = {"A": 90, "B": -90, "plant": 0, "office": 180}.get(back_to, 0)
            var faces: bool = facing == want_yaw
            var marked: bool = m.decals.size() == 1 and Vector2(m.decals[0].x - park.x, m.decals[0].z - park.z).length() < 0.1
            ok = lit and absf(t_bleach - 6.0) <= 0.2 and exp_max >= 7.9 and frozen_held and freed and restarted and m.lighting.step == 2 and is_zero_approx(m.dose) and is_zero_approx(m.lighting.bleach_mix) and marked and snapped and faces
            detail = "lit=%s bleach_at=%.2f exp_max=%.2f held=%s kept+aura_faded=%s restarted=%s facing=%d(%s) deaths=%d decal=%s exp_restart=%.2f snapped=%s aura_before=%.2f aura_dead=%s from=%s" % [lit, t_bleach, exp_max, frozen_held, freed, restarted, facing, back_to, m.deaths, marked, exp_restart, snapped, aura_before, aura_dead, s0.get("room", "?") + " r%dc%d" % [s0.get("row", -1), s0.get("col", -1)]]
        "cut_from_hall":
            # args: --chores=2 --lamp=1 --pos=0,0.95,0 --yaw=0
            # caller passes --chores=2 --lamp=1 --pos=0,0.95,0 --yaw=0: from the hall
            # facing -Z, B r2c0 (behind B's wall) is unseen once the patch corners
            # stay in the room (gate M2 corr-1); the batch resolves by t=2
            var before: Vector3 = m.lighting.seat_light.position
            var room0: String = m.seat.get("room", "?")
            var origin_seen: bool = m._seat_seen(m.seat)
            while m.clock_t < 2.0:
                await m.get_tree().process_frame
            # since M3.0e the pick stays in B until the lamp: the batch resolves on
            # the same seat; the proof of the leak fix is origin_seen == false
            var moved: bool = m.lighting.seat_light != null and m.lighting.seat_light.position != before
            ok = room0 == "B" and not origin_seen and m.seat.get("room", "") == "B" and m.cut_due < 0.0
            detail = "from=%s origin_seen=%s moved=%s to=%s due=%.2f" % [room0, origin_seen, moved, m.seat_line(), m.cut_due]
        "spawn_holds":
            # args: --chores=2 --pos=-6,0.95,0 --yaw=180
            # caller passes --chores=2 --pos=-6,0.95,0 --yaw=180: the sun step that
            # spawned it must not arm a re-pick; at t=3 it is still the B seat
            var before: Vector3 = m.lighting.seat_light.position
            var room0: String = m.seat.get("room", "?")
            var due0: float = m.cut_due
            while m.clock_t < 3.0:
                await m.get_tree().process_frame
            var same_omni: bool = m.lighting.seat_light != null and m.lighting.seat_light.position == before
            ok = room0 == "B" and due0 < 0.0 and same_omni and m.seat.get("room", "") == "B" and m.cut_due < 0.0
            detail = "room0=%s due0=%.2f omni_same=%s room3=%s due3=%.2f" % [room0, due0, same_omni, m.seat.get("room", ""), m.cut_due]
        "stay_in_b":
            # args: --chores=2 --step_at=3 --pos=-6,0.95,0 --pitch=80
            # caller passes --pos=-6,0.95,0 --pitch=80 and a light change at t=0
            # (--chores=2 --step_at=3, or --chores=4 --step_at=5): the re-pick stays in
            # B while fewer than 4 chores are done, spans both rooms after
            var before: Vector3 = m.lighting.seat_light.position
            var want := "B" if m.game.done_count() < 4 else "A"
            while m.clock_t < 3.0:
                await m.get_tree().process_frame
            var moved: bool = m.lighting.seat_light != null and m.lighting.seat_light.position != before
            var body_after: bool = m.creature != null            # M4.0g: the first cut binds the body
            ok = moved and m.seat.get("room", "") == want and m.cut_due < 0.0 and body_after
            detail = "done=%d want=%s got=%s moved=%s body_after=%s" % [m.game.done_count(), want, m.seat.get("room", ""), moved, body_after]
        "cut_same_pane":
            # args: --chores=2 --step_at=4 --pos=8,0.95,-3.6 --yaw=-90 --pitch=0
            # caller passes --chores=2 --step_at=4 --pos=8,0.95,-3.6 --yaw=-90 --pitch=0:
            # from under r1c2's far-wall patch (the first seat since M4.0f; its step-4
            # patch is the nearest open pane from here, 3.74 m against r2c2's 3.86),
            # facing +X (patch, pool and the body it would bind all behind), the re-pick lands on the same pane higher on
            # the wall; nothing of it is in view, so the omni must climb by t=2 (T92)
            var y0: float = m.lighting.seat_light.position.y
            var seat0 := "%s r%dc%d" % [m.seat.get("room", "?"), m.seat.get("row", -1), m.seat.get("col", -1)]
            while m.clock_t < 2.0:
                await m.get_tree().process_frame
            var y1: float = m.lighting.seat_light.position.y if m.lighting.seat_light != null else -1.0
            var seat1 := "%s r%dc%d" % [m.seat.get("room", "?"), m.seat.get("row", -1), m.seat.get("col", -1)]
            # debug (T92): which point of the origin or the destination holds the cut
            var s4 := Thing.seat("B", 1, 2, 4)
            var held := ""
            for pair in [["origin", m.seat], ["dest", s4]]:
                for p: Vector3 in Thing.seat_points(pair[1], 1.1):
                    if m.player.cam.is_position_in_frustum(p):
                        held += "%s:%s " % [pair[0], p]
                        break
            ok = seat0 == seat1 and y1 >= 3.5 and y1 > y0 + 1.0 and m.cut_due < 0.0
            detail = "seat=%s->%s omni_y=%.2f->%.2f due=%.2f seen=%s" % [seat0, seat1, y0, y1, m.cut_due, held]
        "dose_decay":
            # args: --chores=2
            # caller passes --chores=2: dose set to 1.5 by hand, the seat cleared by
            # hand; the dose must drain at 0.25/s while it is absent -> 0 by t=8
            m.dose = 1.5
            m.seat = {}
            m.lighting.free_seat()
            var d2 := 0.0
            while m.clock_t < 2.0:
                await m.get_tree().process_frame
            d2 = m.dose
            while m.clock_t < 8.0:
                await m.get_tree().process_frame
            ok = absf(d2 - 1.0) < 0.05 and is_zero_approx(m.dose)
            detail = "dose@2s=%.3f dose@8s=%.3f" % [d2, m.dose]
        "death_hold":
            # args: --chores=2
            # caller passes --chores=2: E held on an 8 s box from inside the seat's
            # light; the bleach lands at 6 s and the hold must not complete through it
            var s0: Dictionary = m.seat.duplicate()
            var n0: Vector3 = s0["normal"]        # re-based T115: the first seat is r1c2's WALL seat since M4.0f - park and box along its normal
            var park: Vector3 = s0["pos"] + n0 * 0.8
            park.y = 0.95
            m.player.position = park
            m.player.look_at_yaw(rad_to_deg(atan2(n0.x, n0.z)))
            m.player.look_at_pitch(-20.0)     # the eye at 1.7 meets the box 0.55 m ahead at 1.5
            var box = m._test_box(s0["pos"] + n0 * 0.25 + Vector3(0, 1.5 - s0["pos"].y, 0))
            box.hold_s = 8.0                   # M4.0e: the bleach lands at 6 s, inside an 8 s hold
            var hits := [0]
            box.done.connect(func() -> void: hits[0] += 1)
            for i in 3:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target == box
            var lit: bool = m._in_seat_light()
            Input.action_press("interact")
            var prompt_in_bleach := false
            var p_max := 0.0
            for i in 780:
                await m.get_tree().process_frame
                if m.bleach_t >= 0.0:
                    prompt_in_bleach = prompt_in_bleach or m.interact.prompt.visible
                if m.bleach_t < 0.0 and m.deaths > 0:
                    break
                p_max = maxf(p_max, box.progress)
            Input.action_release("interact")
            for i in 3:                        # the ray still reports the box for a frame after the teleport
                await m.get_tree().process_frame
            ok = aimed and lit and m.deaths == 1 and hits[0] == 0 and is_zero_approx(box.progress) and not prompt_in_bleach
            detail = "aimed=%s lit=%s deaths=%d done=%d progress=%.4f zero=%s max=%.2f prompt_in_bleach=%s" % [aimed, lit, m.deaths, hits[0], box.progress, is_zero_approx(box.progress), p_max, prompt_in_bleach]
        "body_yaw":
            # args: --chores=2
            # caller passes --chores=2: the body faces the light's heading, the same
            # from two player positions (never re-aimed at the player)
            var want := rad_to_deg(Thing.body_yaw(m.lighting.step))
            m._body_at(m.seat)                                   # M4.0g: bound by hand
            m.player.position = Vector3(6.3, 0.95, 3.5)
            m.player.look_at_yaw(0.0)
            for i in 5:
                await m.get_tree().process_frame
            var to_sun: Vector3 = -Lighting.sun_dir(m.lighting.step)
            to_sun.y = 0.0
            to_sun = to_sun.normalized()
            var f1: Vector3 = m.creature.global_basis.x if m.creature != null else Vector3.ZERO
            f1.y = 0.0
            var d1: float = f1.normalized().dot(to_sun)                   # the front really faces the sun's heading (M4.0j)
            var y1 := rad_to_deg(m.creature.rotation.y) if m.creature != null else 999.0
            m.player.position = Vector3(2.4, 0.95, 0.0)
            m.player.look_at_yaw(0.0)
            for i in 5:
                await m.get_tree().process_frame
            var y2 := rad_to_deg(m.creature.rotation.y) if m.creature != null else 999.0
            var f2: Vector3 = m.creature.global_basis.x if m.creature != null else Vector3.ZERO
            f2.y = 0.0
            var d2: float = f2.normalized().dot(to_sun)
            ok = absf(angle_difference(deg_to_rad(y1), deg_to_rad(want))) < deg_to_rad(1.0) and absf(y1 - y2) < 1e-3 and d1 > 0.99 and d2 > 0.99
            detail = "want=%.1f y1=%.1f y2=%.1f dot_sun=%.3f/%.3f" % [want, y1, y2, d1, d2]
        "steps":
            # args: (none)
            # walk forward 2 s: footfalls every 0.75 m at 3.2 m/s -> ~8 steps; the
            # clipboard up once -> one pencil; a 1 s hold on a box -> one click
            m.player.position = Vector3(0, 0.95, 8.0)
            m.player.look_at_yaw(0.0)
            var box = m._test_box(Vector3(0, 1.3, 3.0))   # the walk ends against it at z ~3.5: 4.5 m = 6 footfalls
            box.hold_s = 1.0
            var p0: int = m.audio.plays
            for i in 120:
                Input.parse_input_event(_key(KEY_W, true))
                await m.get_tree().process_frame
            Input.parse_input_event(_key(KEY_W, false))
            var after_walk: int = m.audio.plays - p0
            Input.action_press("clipboard")
            for i in 3:
                await m.get_tree().process_frame
            Input.action_release("clipboard")
            var after_clip: int = m.audio.plays - p0 - after_walk
            m.player.look_at_pitch(-30.0)     # the eye at 1.7 meets the box 0.5 m ahead at 1.41
            for i in 3:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target == box
            Input.action_press("interact")
            for i in 70:
                await m.get_tree().process_frame
            Input.action_release("interact")
            var after_click: int = m.audio.plays - p0 - after_walk - after_clip
            var dbg2: String = "box_progress=%.2f fired=%s target=%s player_z=%.2f box_z=%.2f eye_y=%.2f" % [box.progress, box.fired, "box" if m.interact.target == box else ("null" if m.interact.target == null else m.interact.target.prompt), m.player.position.z, box.global_position.z, m.player.cam.global_position.y]
            var bus_hall: String = m.audio.sfx.bus                       # still in the hall
            var flat_drone: bool = m.audio.drone is AudioStreamPlayer     # M4.0i: non-positional
            m.player.position = Vector3(6.3, 0.95, 3.5)
            for i in 3:
                await m.get_tree().process_frame
            var bus_b: String = m.audio.sfx.bus
            ok = after_walk >= 5 and after_clip == 1 and aimed and after_click == 1 and bus_hall == "Hall" and bus_b == "Master" and flat_drone
            detail = "steps=%d pencil=%d aimed=%s click=%d bus_hall=%s bus_B=%s flat_drone=%s %s" % [after_walk, after_clip, aimed, after_click, bus_hall, bus_b, flat_drone, dbg2]
        "aura_gate":
            # args: --chores=2
            # caller passes --chores=2: from the hall the body is behind B's wall
            # (gate 0); teleported to V5 facing it the gate ramps over 2 s; then a
            # 40-degree turn in 0.3 s keeps the warp on the body (lag in world)
            m._body_at(m.seat)                                   # M4.0g: bound by hand
            m.player.position = Vector3(0, 0.95, 0)
            m.player.look_at_yaw(-90.0)
            while m.clock_t < 0.5:
                await m.get_tree().process_frame
            var occluded_on: float = m.aura_on
            m.player.position = Vector3(6.3, 0.95, 3.5)
            m.player.look_at_yaw(0.0)
            var t1 = m.clock_t
            while m.clock_t < t1 + 1.0:
                await m.get_tree().process_frame
            var on_1s: float = m.aura_on
            while m.clock_t < t1 + 2.5:
                await m.get_tree().process_frame
            var on_25s: float = m.aura_on
            var worst := 0.0
            var centre: Vector3 = m.creature.global_position + Vector3(0, 1.6, 0)
            for i in 18:
                m.player.look_at_yaw(-40.0 * (i + 1) / 18.0)
                await m.get_tree().process_frame
                worst = maxf(worst, m.aura_px.distance_to(m.player.cam.unproject_position(centre)))
            ok = occluded_on == 0.0 and on_1s > 0.0 and on_1s <= 0.6 and on_25s >= 0.95 and worst <= 8.0
            detail = "occluded=%.2f at1s=%.2f at2.5s=%.2f turn_worst_px=%.1f" % [occluded_on, on_1s, on_25s, worst]
        "cut_from_hall_b":
            # args: --chores=2 --lamp=1 --thing=3,0,-4.3 --pos=0,0.95,0 --yaw=-90
            # caller passes --chores=2 --lamp=1 --thing=3,0,-4.3 --pos=0,0.95,0 --yaw=-90:
            # from the hall facing B's doorway the re-pick's body (B r2c0) would put
            # its hand in the sightline - held; look up and it cuts
            var before: Vector3 = m.lighting.seat_light.position
            while m.clock_t < 3.0:
                await m.get_tree().process_frame
            var held: bool = m.lighting.seat_light != null and m.lighting.seat_light.position == before and m.cut_due >= 0.0
            m.player.look_at_pitch(80.0)
            while m.clock_t < 5.0:
                await m.get_tree().process_frame
            var moved: bool = m.lighting.seat_light != null and m.lighting.seat_light.position != before and m.cut_due < 0.0
            ok = held and moved
            detail = "held3s=%s moved_after_lookup=%s to=%s" % [held, moved, m.seat_line()]
        "shutters":
            # args: --chores=3
            # --chores=3 -> B's rows shut (0x3FE00); --chores=5 -> all (0x3FFFF);
            # --shut=A:110,B:001 -> those rows; the SIM line prints shut=
            var n: int = m.game.done_count()
            var want: int = 0
            if m.args.has("shut"):
                want = Thing.shut_bits(m.args["shut"])
            elif n >= 5:
                want = 0x3FFFF
            elif n >= 3:
                want = 0x3FE00
            # the lamp as play leaves it (M5.0k): plant until C4, held to C7, then the desk; unlit
            var want_lamp: String = "desk" if n >= 7 else ("held" if n >= 4 else "plant")
            var lamp_ok: bool = m.args.has("lamp") or (m.lamp_where == want_lamp and not m.lighting.lamp_on)
            # M6.0f + M7.0a: a crank is spent unless its OWN chore is next (B's C3,
            # A's C5) and its row is still open
            var cranks_ok := true
            var fired := ""
            var nxt: String = m.game.next_id()
            for room in ["A", "B"]:
                var mine: bool = nxt == ("C3" if room == "B" else "C5")
                for row in 3:
                    var f: bool = m.shutters[room][row]["crank"].fired
                    var want_spent: bool = (not mine) or Thing.is_shut(m.lighting.shut, room, row, 0)
                    cranks_ok = cranks_ok and f == want_spent
                    fired += "1" if f else "0"
            ok = m.lighting.shut == want and lamp_ok and cranks_ok
            detail = "done=%d shut=0x%x want=0x%x lamp=%s,%s want_lamp=%s next=%s cranks_fired(A012,B012)=%s ok=%s" % [n, m.lighting.shut, want, m.lamp_where, "on" if m.lighting.lamp_on else "off", want_lamp, nxt, fired, cranks_ok]
        "lamp_take":
            # args: (none)
            # E at the plant-door hook (hall side, left of the doorway - M6.0g) takes the
            # lamp, L lights it, E at the desk hook hangs it
            m.player.position = Vector3(-0.9, 0.95, -10.6)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-5.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed1: bool = m.interact.target == m.hook_plant and m.hook_plant.prompt == "take"
            Input.action_press("interact")
            for i in 70:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var held: bool = m.lamp_where == "held" and not m.hook_plant.get_node("lamp").visible
            Input.action_press("lamp")
            await m.get_tree().process_frame
            Input.action_release("lamp")
            await m.get_tree().process_frame
            var lit: bool = m.lighting.lamp_on and m.lighting.lamp_light != null and m.lighting.lamp_light.visible and m.lighting.lamp_light.get_parent() == m.player.cam
            m.player.position = Vector3(-1.3, 0.95, 12.74)
            m.player.look_at_yaw(90.0)
            m.player.look_at_pitch(-12.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed2: bool = m.interact.target == m.hook_desk and m.hook_desk.prompt == "hang"
            Input.action_press("interact")
            for i in 70:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var hung: bool = m.lamp_where == "desk" and not m.lighting.lamp_on and m.hook_desk.get_node("lamp").visible and m.hook_desk.prompt == "take"
            ok = aimed1 and held and lit and aimed2 and hung
            detail = "aimed_plant=%s held=%s lit=%s aimed_desk=%s hung=%s plays=%d" % [aimed1, held, lit, aimed2, hung, m.audio.plays]
        "c2":
            # args: --chores=1
            # caller passes --chores=1: three sheets on A's racks (E 2 s each) = C2 ->
            # sun step 2 and the spawn (far, in B); each sheet is a light change
            var changes := [0]
            m.lighting.light_changed.connect(func(_k: String) -> void: changes[0] += 1)
            var thrown := 0
            for row in 3:
                var r: Dictionary = m.racks["A"][row]
                var at: Vector3 = r["body"]
                m.player.position = at + Vector3(0, 0.95, 1.4)
                m.player.look_at_yaw(0.0)              # the rack is 1.4 m ahead (-Z)
                m.player.look_at_pitch(-22.0)
                for i in 3:
                    await m.get_tree().process_frame
                var aimed: bool = m.interact.target == r["inter"]
                Input.action_press("interact")
                for i in 130:
                    await m.get_tree().process_frame
                Input.action_release("interact")
                for i in 3:
                    await m.get_tree().process_frame
                if aimed and r["sheet"].visible:
                    thrown += 1
            for i in 10:
                await m.get_tree().process_frame
            var c2: bool = m.game.chores[1]["done"]
            ok = thrown == 3 and c2 and m.lighting.step == 2 and changes[0] >= 4 and not m.seat.is_empty() and m.seat.get("room", "") == "B"
            detail = "thrown=%d C2=%s step=%d light_changes=%d seat=%s" % [thrown, c2, m.lighting.step, changes[0], m.seat_line()]
        "c3":
            # args: --chores=2
            # caller passes --chores=2: B's three cranks (E 3 s each from their standing
            # points) shut B's rows = C3 -> sun step 3; each is one light change
            var changes := [0]
            m.lighting.light_changed.connect(func(_k: String) -> void: changes[0] += 1)
            var shut_rows := 0
            var rows := []
            for row in 3:
                var st: Vector3 = Thing.crank_stand("B", row)
                var n: Vector3 = Thing.crank_normal("B", row)
                m.player.position = Vector3(st.x, 0.95, st.z)
                m.player.look_at_yaw(rad_to_deg(atan2(n.x, n.z)))      # facing back along the normal, at the crank
                var cp: Vector3 = Thing.crank_pos("B", row)
                m.player.look_at_pitch(rad_to_deg(atan2(cp.y - 1.7, Thing.CRANK_REACH)))
                for i in 3:
                    await m.get_tree().process_frame
                var cr: Interactable = m.shutters["B"][row]["crank"]
                var aimed: bool = m.interact.target == cr
                Input.action_press("interact")
                var lost := 0              # T122: frames of the hold where the crank was not the target
                var prog_max := 0.0
                for i in 190:
                    await m.get_tree().process_frame
                    if m.interact.target != cr:
                        lost += 1
                    prog_max = maxf(prog_max, cr.progress)
                Input.action_release("interact")
                for i in 3:
                    await m.get_tree().process_frame
                rows.append("r%d aimed=%s lost=%d progmax=%.2f label='%s' shut=%s" % [row, aimed, lost, prog_max, cr.prompt, Thing.is_shut(m.lighting.shut, "B", row, 0)])
                if aimed and Thing.is_shut(m.lighting.shut, "B", row, 0):
                    shut_rows += 1
            for i in 10:
                await m.get_tree().process_frame
            var c3: bool = m.game.chores[2]["done"]
            ok = shut_rows == 3 and c3 and m.lighting.step == 3 and m.lighting.shut == 0x3FE00 and changes[0] >= 4
            detail = "shut_rows=%d C3=%s step=%d shut=0x%x light_changes=%d rows=%s" % [shut_rows, c3, m.lighting.step, m.lighting.shut, changes[0], rows]
        "c4":
            # args: --chores=3
            # caller passes --chores=3: at the valve with the lamp on its hook nothing
            # is offered and E does nothing; take the lamp (off) and E 8 s drains
            # the boiler in the dark: C4 done, no death, sun step 4
            var valve: Interactable = null
            for c in m.get_children():
                if c is Interactable and c.prompt == "valve":
                    valve = c
            m.player.position = Vector3(-0.6, 0.95, -14.0)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-35.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target == valve
            var refused: bool = not m.interact.prompt.visible
            Input.action_press("interact")
            for i in 120:
                await m.get_tree().process_frame
            Input.action_release("interact")
            var not_done: bool = not m.game.chores[3]["done"] and valve.progress == 0.0
            # take the lamp from the hook by the plant doorway (hall side, M6.0g), leave it off
            m.player.position = Vector3(-0.9, 0.95, -10.6)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-5.0)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 70:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var carried: bool = m.lamp_where == "held" and not m.lighting.lamp_on
            m.player.position = Vector3(-0.6, 0.95, -14.0)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-35.0)
            for i in 3:
                await m.get_tree().process_frame
            var offered: bool = m.interact.target == valve and m.interact.prompt.visible
            Input.action_press("interact")
            for i in 490:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 5:
                await m.get_tree().process_frame
            ok = aimed and refused and not_done and carried and offered and m.game.chores[3]["done"] and m.deaths == 0 and m.lighting.step == 4
            detail = "aimed=%s refused=%s not_done=%s carried_off=%s offered=%s C4=%s deaths=%d step=%d" % [aimed, refused, not_done, carried, offered, m.game.chores[3]["done"], m.deaths, m.lighting.step]
        "ride_enter":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # caller passes --chores=5 --lamp=1 --pos=0,0.95,-14: everything shut, the
            # lamp lit -> the disc edge is the seat by t=1.1, taken in view (3.5: no
            # cut); lamp off at t=3 watched -> holds; look up 80 -> it leaves
            while m.clock_t < 1.1:
                await m.get_tree().process_frame
            var riding_by_1: bool = m.seat.get("surface", "") == "lamp" and m.cut_due < 0.0
            var in_view: bool = m.player.cam.is_position_in_frustum(m.seat["pos"]) if not m.seat.is_empty() else false
            var d_ahead: float = Vector2(m.seat["pos"].x - m.player.position.x, m.seat["pos"].z - m.player.position.z).length() if not m.seat.is_empty() else -1.0
            var seat_line_1: String = m.seat_line()
            while m.clock_t < 1.6:
                await m.get_tree().process_frame
            m.lighting.lamp(false, m.player.cam)   # off mid ride-in, watched (M6.0e): the ramp goes on, no snap
            var rise_prev: float = m.creature.rise if m.creature != null else 0.0
            var aura_prev: float = m.aura_on
            var max_jump := 0.0
            while m.clock_t < 3.4:
                await m.get_tree().process_frame
                if m.creature != null:
                    max_jump = maxf(max_jump, absf(m.creature.rise - rise_prev))
                    rise_prev = m.creature.rise
                max_jump = maxf(max_jump, absf(m.aura_on - aura_prev))
                aura_prev = m.aura_on
            var rise_full: bool = m.creature != null and m.creature.rise >= 0.99
            while m.clock_t < 5.0:
                await m.get_tree().process_frame
            var held: bool = m.seat.get("surface", "") == "lamp" and m.cut_due >= 0.0
            m.player.look_at_pitch(80.0)
            while m.clock_t < 7.0:
                await m.get_tree().process_frame
            var left: bool = m.seat.get("surface", "") != "lamp" and m.cut_due < 0.0
            ok = riding_by_1 and in_view and absf(d_ahead - 2.15) < 0.05 and max_jump <= 0.05 and rise_full and held and left   # 2 m ahead, 0.8 m left: 2.15 m off (M5.0f)
            detail = "riding_by_1.1=%s in_view=%s ahead=%.2f ramp_max_jump=%.3f rise_by_3.4=%s held_watched=%s left_after_lookup=%s line1=%s" % [riding_by_1, in_view, d_ahead, max_jump, rise_full, held, left, seat_line_1]
        "ride_walk":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # caller passes --chores=5 --lamp=1 --pos=0,0.95,-14: W 3 s at lamp pace
            # (<= 1 m/s) then still 6 s; the body knuckle-walks after the disc edge -
            # plants >= 2 s apart, never more than 2.2 m each, and ends by the seat
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var p0: Vector3 = m.player.position
            var riding0: bool = m.riding() and m.creature != null
            var plant_times := []
            var last_p: int = m.creature.plants if m.creature != null else 0
            var max_step := 0.0
            var prev_plant := Vector3.ZERO
            while m.clock_t < 4.2:
                Input.parse_input_event(_key(KEY_W, true))
                await m.get_tree().process_frame
                if m.creature != null and m.creature.plants != last_p:
                    last_p = m.creature.plants
                    plant_times.append(m.clock_t)
                    if plant_times.size() > 1:
                        max_step = maxf(max_step, prev_plant.distance_to(m.creature.plant_world))
                    prev_plant = m.creature.plant_world
            Input.parse_input_event(_key(KEY_W, false))
            var moved: float = p0.distance_to(m.player.position)
            while m.clock_t < 10.2:
                await m.get_tree().process_frame
                if m.creature != null and m.creature.plants != last_p:
                    last_p = m.creature.plants
                    plant_times.append(m.clock_t)
            var min_gap := INF
            for i in range(1, plant_times.size()):
                min_gap = minf(min_gap, plant_times[i] - plant_times[i - 1])
            var near_seat: float = m.creature.global_position.distance_to(m.seat["pos"]) if (m.creature != null and not m.seat.is_empty()) else INF
            ok = riding0 and moved <= 3.2 and plant_times.size() >= 2 and min_gap >= 2.0 - 1.0 / 60.0 and max_step <= 2.5 and near_seat <= 2.5
            detail = "riding=%s moved=%.2f plants=%d min_gap=%.2f max_step=%.2f body_to_seat=%.2f" % [riding0, moved, plant_times.size(), min_gap, max_step, near_seat]
        "seat_on_crank":
            # args: --chores=4 --lamp=1
            # caller passes --chores=4 --lamp=1: A's step-4 seats are out of reach, so
            # the lamp seat is the seat; at A's row-1 crank the disc edge EASES to the
            # view axis at 0.4 m/s (M6.0i: no snap to pace out) and the body stands on
            # the crank - it reads ` ` in ASCII while the prompt shows and the hold
            # completes (GUARDRAILS 3.2); aim off and the edge eases back over 2 s
            var st: Vector3 = Thing.crank_stand("A", 1)
            var cp: Vector3 = Thing.crank_pos("A", 1)
            m.player.position = Vector3(st.x, 0.95, st.z)
            m.player.look_at_yaw(-90.0)
            m.player.look_at_pitch(rad_to_deg(atan2(cp.y - 1.7, Thing.CRANK_REACH)))
            while m.clock_t < 4.0 and not m.riding():   # the boot's seat is an A wall; the lamp seat comes by the cut batch
                await m.get_tree().process_frame
            var t_ride: float = m.clock_t
            var omni_prev: Vector3 = m.lighting.seat_light.position if m.lighting.seat_light != null else Vector3.ZERO
            var omni_jump := 0.0
            while m.clock_t < t_ride + 3.5:
                await m.get_tree().process_frame
                if m.lighting.seat_light != null:
                    omni_jump = maxf(omni_jump, m.lighting.seat_light.position.distance_to(omni_prev))
                    omni_prev = m.lighting.seat_light.position
            var riding_now: bool = m.riding() and m.creature != null
            var body_d: float = Vector2(m.creature.global_position.x - cp.x, m.creature.global_position.z - cp.z).length() if m.creature != null else INF   # on the floor: the crank is 1.2 m up
            var crank: Interactable = m.shutters["A"][1]["crank"]
            var aimed: bool = m.interact.target == crank and m.interact.prompt.visible
            m.set_ascii(true)
            for i in 3:
                await m.get_tree().process_frame
            # the crank's 3x3 cells in ASCII read ` ` (M5.0f): the body is a hole over it
            var sp: Vector2 = m.player.cam.unproject_position(cp)
            var img: Image = m.get_viewport().get_texture().get_image()
            var blank_cells := 0
            var cx := int(sp.x / 8.0)
            var cy := int(sp.y / 16.0)
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var mx := 0.0
                    for py in 16:
                        for px in 8:
                            var c := img.get_pixel((cx + dx) * 8 + px, (cy + dy) * 16 + py)
                            mx = maxf(mx, maxf(c.r, maxf(c.g, c.b)))
                    if mx < 0.06:
                        blank_cells += 1
            var covered: bool = blank_cells == 9
            Input.action_press("interact")
            for i in 190:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var shut: bool = Thing.is_shut(m.lighting.shut, "A", 1, 0)
            var c5_part: int = m.game.chores[4]["got"]
            var hand_x: float = m.creature.plant_world.x if m.creature != null else 0.0   # M5.0i: the hand stops at the wall (A's face is x -1.8)
            # aim off (M6.0i): the side eases back, 0.4 m/s
            var t_off: float = m.clock_t
            m.player.look_at_yaw(-30.0)
            while m.clock_t < t_off + 1.0:
                await m.get_tree().process_frame
            var side_1s: float = m.lamp_side
            while m.clock_t < t_off + 2.1:
                await m.get_tree().process_frame
            var side_2s: float = m.lamp_side
            ok = riding_now and omni_jump <= 0.4 / 60.0 + 0.02 and body_d <= 1.0 and aimed and covered and shut and c5_part == 1 and hand_x <= -1.85 and side_1s <= 0.45 and side_2s >= 0.79
            detail = "riding=%s omni_max_jump=%.4f body_to_crank=%.2f aimed+prompt=%s crank_black=%s(%d/9) crank_px=%.0f,%.0f row_shut=%s C5_parts=%d hand_x=%.2f side_1s=%.2f side_2.1s=%.2f" % [riding_now, omni_jump, body_d, aimed, covered, blank_cells, sp.x, sp.y, shut, c5_part, hand_x, side_1s, side_2s]
        "c6c7":
            # args: --chores=5 --lamp=1
            # caller passes --chores=5 --lamp=1: E 3 s on the card lifts it (C6, D4);
            # at the desk "sign" is refused while the lamp is carried; hung on the
            # desk hook it is offered; E 6 s signs the log (C7) and enables the bolt
            var rp: Vector3 = Thing.rack_pos("A", 1)
            m.player.position = rp + Vector3(0, 0.95, 1.6)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-24.0)
            for i in 3:
                await m.get_tree().process_frame
            # M5.0d (3.12): without the lamp carried the card says nothing and E 3 s does nothing
            m.lamp_where = "plant"
            for i in 3:
                await m.get_tree().process_frame
            var dark_hidden: bool = m.interact.target == m.card["inter"] and not m.interact.prompt.visible
            Input.action_press("interact")
            for i in 190:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var dark_undone: bool = not m.game.chores[5]["done"] and m.card["inter"].progress == 0.0
            m.lamp_where = "held"
            for i in 3:
                await m.get_tree().process_frame
            var aimed_card: bool = m.interact.target == m.card["inter"] and m.interact.prompt.visible
            var card_x0: float = m.card["card"].position.x
            Input.action_press("interact")
            for i in 190:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var c6: bool = m.game.chores[5]["done"] and m.card["card"].position.x > card_x0 + 0.4
            var z1: float = m.HALL_L * 0.5 + m.WALL + m.OFF_D
            m.player.position = Vector3(1.6, 0.95, z1 - 1.4)
            m.player.look_at_yaw(145.0)
            m.player.look_at_pitch(-36.0)
            for i in 3:
                await m.get_tree().process_frame
            var refused: bool = m.interact.target != m.sign and not m.interact.prompt.visible   # M5.0a: the spent sign is no target; the log behind it is spent too
            Input.action_press("interact")
            for i in 120:
                await m.get_tree().process_frame
            Input.action_release("interact")
            var not_signed: bool = not m.game.chores[6]["done"] and m.sign.progress == 0.0
            m.player.position = Vector3(-1.3, 0.95, 12.74)
            m.player.look_at_yaw(90.0)
            m.player.look_at_pitch(-12.0)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 70:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var hung: bool = m.lamp_where == "desk"
            m.player.position = Vector3(1.6, 0.95, z1 - 1.4)
            m.player.look_at_yaw(145.0)
            m.player.look_at_pitch(-36.0)
            for i in 3:
                await m.get_tree().process_frame
            var offered: bool = m.interact.target == m.sign and m.interact.prompt.visible
            # M7.0f: the sign's box sits 0.22 m above the log's (they shared a centre and
            # the sign swallowed the ray) - look down and D1 reads while C7 is offered
            var d1_read := false
            var d1_pitch := 0.0
            Input.action_press("interact")
            for k in 21:                       # look down from the sign to the desk top
                m.player.look_at_pitch(-30.0 - 1.5 * k)
                for i in 2:
                    await m.get_tree().process_frame
                if m.interact.found.visible and m.interact.found.text.contains("delivered"):
                    d1_read = true
                    d1_pitch = -30.0 - 1.5 * k
                    break
            var log_hit: bool = m.interact.target != null and m.interact.target != m.sign
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            m.player.look_at_pitch(-36.0)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 370:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            ok = dark_hidden and dark_undone and aimed_card and c6 and refused and not_signed and hung and offered and log_hit and d1_read and m.game.chores[6]["done"] and m.bolt_enabled
            detail = "card_dark_hidden=%s card_dark_undone=%s card_aimed=%s C6=%s sign_refused=%s not_signed=%s hung=%s offered=%s log_hit=%s D1_read=%s at_pitch=%.1f C7=%s bolt=%s" % [dark_hidden, dark_undone, aimed_card, c6, refused, not_signed, hung, offered, log_hit, d1_read, d1_pitch, m.game.chores[6]["done"], m.bolt_enabled]
        "endA":
            # args: --chores=7 --lamp=desk
            # caller passes --chores=7 --lamp=desk: every chore done, the lamp hung on
            # the desk unlit. Aimed at the bolt, E 4 s opens the yard door onto dusk -
            # the eyes read sky and ground in ` .:-` for 3 s, then the light goes over
            # 2 s; the clipboard becomes the credits and ended stops the restart, the
            # dose and the cut rule (M5.6, Ending A)
            var pz1: float = -(m.HALL_L * 0.5 + m.WALL) - m.PLANT_D
            m.player.position = Vector3(0.0, 0.95, pz1 + 1.2)
            m.player.look_at_yaw(-17.0)
            m.player.look_at_pitch(-23.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target == m.bolt and m.interact.prompt.visible
            var enabled0: bool = m.bolt_enabled
            Input.action_press("interact")
            for i in 250:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var ended_a: bool = m.ended == "A"
            var door_gone: bool = m.yard_door.size() == 5 and not m.yard_door[0].visible and not m.yard_door[4].visible and m.bolt.collision_layer == 0   # M6.0h: the bolt's slab goes with the door
            # the eyes stay free (M6.0h): mouse-look raises the pitch though walking is frozen
            var mode_b: int = Input.mouse_mode
            Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
            var pitch0: float = m.player.pitch
            var mm := InputEventMouseMotion.new()
            mm.relative = Vector2(0, -120)
            Input.parse_input_event(mm)
            await m.get_tree().process_frame
            var looked_up: bool = m.player.pitch > pitch0 + 0.05 and m.player.frozen
            Input.mouse_mode = mode_b
            var t_end: float = m.end_t
            # M7.0g: the door's FIRST frames too - the plant zone sat at 9.0 and the
            # yard at 1.2, so a 2 s ramp read as a bleach exactly when the door opened
            while m.clock_t < t_end + 0.3:
                await m.get_tree().process_frame
            m.set_ascii(false)   # graphics: exposure blows a whole frame, and thin glyph ink hides that from CLIP
            for i in 2:
                await m.get_tree().process_frame
            var opened: Image = m.get_viewport().get_texture().get_image()
            opened.save_png("res://shots/t129_endA_open.png")
            var exp_open: float = m.lighting.ca.exposure_multiplier   # the snap's own number: mid-ramp this is ~7.8, snapped it is the yard's
            while m.clock_t < t_end + 2.5:
                await m.get_tree().process_frame
            m.set_ascii(true)
            for i in 2:
                await m.get_tree().process_frame
            var dusk: Image = m.get_viewport().get_texture().get_image()
            dusk.save_png("res://shots/t100_endA_dusk.png")
            var exp_dusk: float = m.lighting.ca.exposure_multiplier
            var base_dusk: float = m.lighting._base_exp
            var to_dusk: float = m.lighting._ramp_to
            while m.clock_t < t_end + 5.5:
                await m.get_tree().process_frame
            var dark: Image = m.get_viewport().get_texture().get_image()
            dark.save_png("res://shots/t100_endA_dark.png")
            var credits: bool = m.clipboard.visible and m.clipboard.text.contains("[lb]x[rb]")
            # M6.0b: Esc works frozen (the mode toggles), the quit arms 3 s after the credits
            var mode0: int = Input.mouse_mode
            Input.parse_input_event(_key(KEY_ESCAPE, true))
            await m.get_tree().process_frame
            Input.parse_input_event(_key(KEY_ESCAPE, false))
            await m.get_tree().process_frame
            var esc_toggled: bool = Input.mouse_mode != mode0
            Input.mouse_mode = mode0
            while m.clock_t < t_end + 8.2:
                await m.get_tree().process_frame
            var armed_a: bool = m.exit_armed
            # M7.0f: E is the only quit. Esc while armed still frees the mouse and
            # leaves the ending exactly where it was
            var mode1: int = Input.mouse_mode
            Input.parse_input_event(_key(KEY_ESCAPE, true))
            await m.get_tree().process_frame
            Input.parse_input_event(_key(KEY_ESCAPE, false))
            await m.get_tree().process_frame
            var esc_armed_toggled: bool = Input.mouse_mode != mode1
            var still_a: bool = m.ended == "A"
            Input.mouse_mode = mode1
            var no_restart: bool = m.deaths == 0 and m.player.position.distance_to(Vector3(0.0, 0.95, pz1 + 1.2)) < 0.3
            var exp_dark: float = m.lighting.ca.exposure_multiplier
            ok = aimed and enabled0 and ended_a and door_gone and looked_up and credits and no_restart and exp_dark < 0.05 and esc_toggled and armed_a and esc_armed_toggled and still_a and exp_open <= 1.25 * exp_dusk
            detail = "aimed=%s enabled0=%s ended=%s door_gone=%s credits=%s no_restart=%s zone=%s exp_dark=%.3f exp_open=%.3f exp_dusk=%.3f base=%.3f to=%.3f esc_frozen=%s exit_armed=%s looked_up=%s esc_armed=%s still_A=%s" % [aimed, enabled0, ended_a, door_gone, credits, no_restart, m.lighting.zone, exp_dark, exp_open, exp_dusk, base_dusk, to_dusk, esc_toggled, armed_a, looked_up, esc_armed_toggled, still_a]
        "crank_dark":
            # args: --chores=2
            # caller passes --chores=2: the thing sits at B r1c2 (its first seat) and the
            # row-1 crank stands in that light. E 3 s shuts the row; the seat stays (the
            # origin is in view, 3.9) but its pane is shut, so its light is gone: lit
            # means open (M5.0b) - the dose falls after the hold, no death
            var st: Vector3 = Thing.crank_stand("B", 1)
            var n: Vector3 = Thing.crank_normal("B", 1)
            m.player.position = Vector3(st.x, 0.95, st.z)
            m.player.look_at_yaw(rad_to_deg(atan2(n.x, n.z)))
            var cp: Vector3 = Thing.crank_pos("B", 1)
            m.player.look_at_pitch(rad_to_deg(atan2(cp.y - 1.7, Thing.CRANK_REACH)))
            for i in 3:
                await m.get_tree().process_frame
            var seat0: String = m.seat_line()
            var lit0: bool = m._in_seat_light()
            Input.action_press("interact")
            for i in 190:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var shut1: bool = Thing.is_shut(m.lighting.shut, "B", 1, 2)
            var dose_hold: float = m.dose
            for i in 360:
                await m.get_tree().process_frame
            var same_seat: bool = m.seat_line() == seat0
            var lit1: bool = m._in_seat_light()
            ok = lit0 and shut1 and dose_hold > 0.5 and m.dose < dose_hold - 0.5 and m.deaths == 0 and same_seat and not lit1
            detail = "lit_before=%s shut=%s dose_at_hold=%.2f dose_6s=%.2f deaths=%d same_seat=%s lit_after=%s" % [lit0, shut1, dose_hold, m.dose, m.deaths, same_seat, lit1]
        "ride_wall":
            # args: --chores=5 --lamp=1 --pos=-1.1,0.95,4
            # caller passes --chores=5 --lamp=1 --pos=-1.1,0.95,4: riding with the wall on
            # the left, the disc edge clamped beside the player, inside its 1 m. W 8 s:
            # moving never doses (M5.0b); still 3 s lit: the riding rate; lamp off,
            # still 3 s: none - the disc is no light once the lamp is out
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var riding0: bool = m.riding()
            var min_d := INF
            var max_walk := 0.0
            while m.clock_t < 9.2:
                Input.parse_input_event(_key(KEY_W, true))
                await m.get_tree().process_frame
                max_walk = maxf(max_walk, m.dose)
                if not m.seat.is_empty():
                    min_d = minf(min_d, Vector2(m.player.position.x - m.seat["pos"].x, m.player.position.z - m.seat["pos"].z).length())
            Input.parse_input_event(_key(KEY_W, false))
            var dose_walked: float = m.dose   # the boot's first still second may leave a trace; 8 s of walking drains it
            while m.clock_t < 12.2:
                await m.get_tree().process_frame
            var dose_still: float = m.dose
            Input.action_press("lamp")
            await m.get_tree().process_frame
            Input.action_release("lamp")
            await m.get_tree().process_frame
            var lamp_off: bool = not m.lighting.lamp_on
            while m.clock_t < 15.2:
                await m.get_tree().process_frame
            ok = riding0 and min_d < 1.0 and dose_walked < 0.1 and max_walk < 0.5 and dose_still > 0.5 and lamp_off and m.dose < dose_still - 0.5 and m.deaths == 0
            detail = "riding=%s min_d=%.2f dose_walk_max=%.2f dose_walked=%.2f dose_still3s=%.2f lamp_off=%s dose_off3s=%.2f deaths=%d" % [riding0, min_d, max_walk, dose_walked, dose_still, lamp_off, m.dose, m.deaths]
        "ride_watched":
            # args: --chores=4 --pos=-6,0.95,0
            # caller passes --chores=4 --pos=-6,0.95,0: A's step-4 seats are out of reach,
            # so the seat is an A wall patch (any open pane). The body is bound by hand
            # and faced; the lamp comes on at t=1 (a light change: the lamp seat is the
            # next pick). Watched, the origin stays and the due keeps asking (3.9,
            # M5.0c); looking away (pitch 80) it rides in
            await m.get_tree().process_frame
            var seat0: String = m.seat_line()
            var had_seat: bool = not m.seat.is_empty() and not m.riding()
            if had_seat:
                m._body_at(m.seat)
                var to_seat: Vector3 = m.seat["pos"] - m.player.cam.global_position
                m.player.look_at_yaw(rad_to_deg(atan2(-to_seat.x, -to_seat.z)))
                m.player.look_at_pitch(rad_to_deg(atan2(to_seat.y, Vector2(to_seat.x, to_seat.z).length())))
            while m.clock_t < 1.0:
                await m.get_tree().process_frame
            var seen0: bool = had_seat and m._seat_seen(m.seat)
            m.lamp_where = "held"
            m.lighting.lamp(true, m.player.cam)
            while m.clock_t < 3.0:
                await m.get_tree().process_frame
            var kept: bool = m.seat_line() == seat0
            var asking: bool = m.cut_due >= 0.0
            m.player.look_at_pitch(80.0)
            while m.clock_t < 5.0:
                await m.get_tree().process_frame
            var rode: bool = m.riding()
            ok = had_seat and seen0 and kept and asking and rode
            detail = "seat0=%s seen=%s kept_at_3s=%s asking=%s riding_at_5s=%s" % [seat0, seen0, kept, asking, rode]
        "ride_death":
            # args: --chores=5 --lamp=1 --pos=-8,0.95,0 --yaw=90
            # caller passes --chores=5 --lamp=1 --pos=-8,0.95,0 --yaw=90: riding in A,
            # still; the dose forced to 2.9 brings the bleach in 0.3 s; the restart at
            # hall z=0 facing A. The disc comes with the lamp: the body rises again
            # 2 m ahead under the blank (M5.0e), never walking the 8 m; the aura ramps in
            while m.clock_t < 1.2:                  # the boot's cut batch seats it after ~1 s
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            m.dose = 2.9
            var t_restart := -1.0
            for i in 600:
                await m.get_tree().process_frame
                if m.deaths > 0 and m.bleach_t < 0.0:
                    t_restart = m.clock_t
                    break
            var restarted: bool = t_restart >= 0.0 and m.player.position.distance_to(Vector3(0, 0.95, 0)) < 0.05
            var aura0: float = m.aura_on
            var still_riding: bool = m.riding() and m.creature != null
            var seat_near: float = m.player.position.distance_to(m.seat["pos"]) if not m.seat.is_empty() else INF
            var max_d := 0.0
            var aura_max := 0.0
            while m.clock_t < t_restart + 3.0:
                await m.get_tree().process_frame
                aura_max = maxf(aura_max, m.aura_on)
                if m.clock_t >= t_restart + 0.5 and m.creature != null and not m.seat.is_empty():
                    max_d = maxf(max_d, m.creature.global_position.distance_to(m.seat["pos"]))
            ok = riding0 and restarted and still_riding and seat_near < 3.0 and max_d <= 2.5 and aura0 < 0.3 and aura_max > 0.9
            detail = "riding=%s restarted=%s riding_after=%s seat_to_player=%.2f body_to_seat_max=%.2f aura_at_restart=%.2f aura_max_3s=%.2f deaths=%d" % [riding0, restarted, still_riding, seat_near, max_d, aura0, aura_max, m.deaths]
        "ride_reverse":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # caller passes --chores=5 --lamp=1 --pos=0,0.95,-14: riding in the plant
            # room; at t=2 the caretaker turns round (yaw 180) and the disc edge jumps
            # behind them. The body goes round, never within 0.9 m (M5.0i), and is by
            # the seat again within ten seconds
            while m.clock_t < 2.0:
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            m.player.look_at_yaw(180.0)
            var min_d := INF
            while m.clock_t < 8.0:
                await m.get_tree().process_frame
                if m.creature != null:
                    min_d = minf(min_d, Vector2(m.creature.global_position.x - m.player.position.x, m.creature.global_position.z - m.player.position.z).length())
            while m.clock_t < 12.0:
                await m.get_tree().process_frame
            var near: float = Vector2(m.creature.global_position.x - m.seat["pos"].x, m.creature.global_position.z - m.seat["pos"].z).length() if (m.creature != null and not m.seat.is_empty()) else INF
            ok = riding0 and min_d >= 0.9 and near <= 1.0
            detail = "riding=%s min_body_to_player_2-8s=%.2f body_to_seat_12s=%.2f plants=%d" % [riding0, min_d, near, m.creature.plants if m.creature != null else -1]
        "card_rests":
            # args: --chores=1
            # caller passes --chores=1: the sample card and its dark rectangle rest on
            # A's centre sheet - nothing floats over a bare rack (M5.0j). Hidden and
            # untargetable until that sheet is thrown (E 2 s), then on its top face
            var r: Dictionary = m.racks["A"][1]
            var at: Vector3 = r["body"]
            var hidden0: bool = not m.card["card"].visible and not m.card["dark"].visible and m.card["inter"].collision_layer == 0
            m.player.position = at + Vector3(0, 0.95, 1.4)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-22.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed_sheet: bool = m.interact.target == r["inter"]
            Input.action_press("interact")
            for i in 130:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var thrown: bool = r["sheet"].visible
            var shown: bool = m.card["card"].visible and m.card["dark"].visible and m.card["inter"].collision_layer == 3
            var top: float = r["sheet"].position.y + (r["sheet"].mesh as BoxMesh).size.y * 0.5
            var rests: bool = absf(m.card["dark"].position.y - (top + 0.006)) < 0.01 and absf(m.card["card"].position.y - (top + 0.022)) < 0.01
            ok = hidden0 and aimed_sheet and thrown and shown and rests
            detail = "hidden_before=%s sheet_aimed=%s thrown=%s shown=%s rests_on_top=%s sheet_top=%.3f card_y=%.3f rack=%.2f,%.2f" % [hidden0, aimed_sheet, thrown, shown, rests, top, m.card["card"].position.y, at.x, at.z]
        "found_text":
            # args: (none)
            # at the desk (C1 open): E held on the log shows its text above the prompt,
            # released it is gone (M5.1); the detail carries D3's rectangle for shots
            var z1 = m.HALL_L * 0.5 + m.WALL + m.OFF_D
            m.player.position = Vector3(1.6, 0.95, z1 - 1.4)
            m.player.look_at_yaw(145.0)
            m.player.look_at_pitch(-36.0)
            for i in 3:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target != null and m.interact.target.prompt == "log entry"
            var hidden0: bool = not m.interact.found.visible
            Input.action_press("interact")
            for i in 3:
                await m.get_tree().process_frame
            var shown: bool = m.interact.found.visible and m.interact.found_bg.visible and m.interact.found.text.contains("41000")
            var above: bool = m.interact.found.position.y < m.interact.prompt.position.y
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var hidden1: bool = not m.interact.found.visible
            # D3's screen box from the shot pose (2.5 m back, pitch -30), for cells.py --box
            m.player.position = m.d3_pos + Vector3(0, 0.95, 2.5)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-30.0)
            for i in 3:
                await m.get_tree().process_frame
            var lo := Vector2(INF, INF)
            var hi := Vector2(-INF, -INF)
            for dx: float in [-0.6, 0.6]:
                for dz: float in [-0.3, 0.3]:
                    var q: Vector2 = m.player.cam.unproject_position(m.d3_pos + Vector3(dx, 0.0, dz))
                    lo = lo.min(q)
                    hi = hi.max(q)
            ok = aimed and hidden0 and shown and above and hidden1
            detail = "aimed=%s hidden_before=%s shown_held=%s above_prompt=%s hidden_after=%s d3=%.2f,%.2f d3box=%.0f,%.0f,%.0f,%.0f d6=%.2f,%.2f" % [aimed, hidden0, shown, above, hidden1, m.d3_pos.x, m.d3_pos.z, lo.x, lo.y, hi.x, hi.y, m.d6_pos.x, m.d6_pos.z]
        "chair_tone":
            # args: (none)
            # D5 (M5.2): from the shot pose the seat top's two halves' screen boxes,
            # for cells.py - the sun half must read brighter than the shadow half
            var z1: float = m.HALL_L * 0.5 + m.WALL + m.OFF_D
            m.player.position = Vector3(-0.3, 0.95, 15.6)
            m.player.look_at_yaw(-90.0)
            m.player.look_at_pitch(-25.0)
            for i in 3:
                await m.get_tree().process_frame
            var boxes := []
            var means := []
            m.set_ascii(false)                        # the graphics frame: albedo 0.3 against 0.9 under the same light
            for i in 2:
                await m.get_tree().process_frame
            var img: Image = m.get_viewport().get_texture().get_image()
            for half: Array in [[0.75, 1.0], [1.0, 1.25]]:
                var lo := Vector2(INF, INF)
                var hi := Vector2(-INF, -INF)
                for x: float in half:
                    for z: float in [z1 - 1.55, z1 - 1.05]:
                        var q: Vector2 = m.player.cam.unproject_position(Vector3(x, 0.45, z))
                        lo = lo.min(q)
                        hi = hi.max(q)
                boxes.append("%.0f,%.0f,%.0f,%.0f" % [lo.x, lo.y, hi.x, hi.y])
                # the mean brightness of the seat top's half, 4 px inside its box
                var sum := 0.0
                var n := 0
                for py in range(int(lo.y) + 4, int(hi.y) - 4, 2):
                    for px in range(int(lo.x) + 4, int(hi.x) - 4, 2):
                        if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height():
                            var c := img.get_pixel(px, py)
                            sum += (c.r + c.g + c.b) / 3.0
                            n += 1
                means.append(sum / maxf(n, 1))
            ok = means[1] >= means[0] + 0.15          # M6.0l: the sun half brighter by 0.15 (a swap of the albedos fails it)
            detail = "shade=%s sun=%s shade_mean=%.3f sun_mean=%.3f" % [boxes[0], boxes[1], means[0], means[1]]
        "bleach_hue":
            # args: --chores=5 --lamp=1 --pos=-8,0.95,0 --yaw=90
            # caller passes --chores=N --lamp=1 --pos=-8,0.95,0 --yaw=90: riding, the
            # clipboard shown once (the colour gate's second key), the dose forced;
            # at the flood's plateau the ASCII and the graphics frames are saved to
            # shots/t99_bleachN_{ascii,gfx}.png for cells.py --chroma (M5.5)
            var n: int = m.game.done_count()
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            Input.action_press("clipboard")
            for i in 3:
                await m.get_tree().process_frame
            Input.action_release("clipboard")
            await m.get_tree().process_frame
            var unlocked: bool = m.game.colour_unlocked()
            m.dose = 2.9
            var saved := false
            for i in 400:
                await m.get_tree().process_frame
                if m.bleach_t >= 0.0 and m.clock_t - m.bleach_t >= 1.5:
                    m.set_ascii(true)              # the reading first, whatever the boot mode (T99: both frames were graphics)
                    for k in 2:
                        await m.get_tree().process_frame
                    var a: Image = m.get_viewport().get_texture().get_image()
                    a.save_png("res://shots/t99_bleach%d_ascii.png" % n)
                    m.set_ascii(false)
                    for k in 2:
                        await m.get_tree().process_frame
                    var g: Image = m.get_viewport().get_texture().get_image()
                    g.save_png("res://shots/t99_bleach%d_gfx.png" % n)
                    while m.clock_t - m.bleach_t < 2.9:    # M6.0m: by the end of the hold the hued flood has drained to white
                        await m.get_tree().process_frame
                    var l: Image = m.get_viewport().get_texture().get_image()   # graphics: CLIP measures pixels, not glyphs
                    l.save_png("res://shots/t99_bleach%d_late.png" % n)
                    m.set_ascii(true)
                    saved = true
                    break
            var hue_now: float = m.bleach_hue
            var exp_now: float = m.lighting.ca.exposure_multiplier
            ok = riding0 and saved and (unlocked == (n >= 5)) and (hue_now == (1.0 if n >= 5 else 0.0))
            detail = "riding=%s unlocked=%s bleach_hue=%.0f saved=%s exp_at_plateau=%.2f base=%.2f flood_e=%.2f" % [riding0, unlocked, hue_now, saved, exp_now, m.lighting._base_exp, m.lighting.flood.light_energy if m.lighting.flood != null else -1.0]
        "endB":
            # args: --chores=7 --lamp=1
            # caller passes --chores=7 --lamp=1: at the bolt with the lamp lit - the
            # prompt shows, the hold never fills, the riding dose (still, lit) reaches
            # 3.0 at the door; the bleach is the hue (the clipboard pressed once for
            # the gate), no restart: the mark goes on the door at eye height (M5.7)
            var pz1: float = -(m.HALL_L * 0.5 + m.WALL) - m.PLANT_D
            m.player.position = Vector3(0.0, 0.95, pz1 + 1.2)
            m.player.look_at_yaw(-17.0)
            m.player.look_at_pitch(-23.0)
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            Input.action_press("clipboard")
            for i in 3:
                await m.get_tree().process_frame
            Input.action_release("clipboard")
            for i in 3:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target == m.bolt and m.interact.prompt.visible
            # M6.0h: with the bolt targeted the disc edge snaps to the axis and the body
            # stands on the bolt - its 3x3 cells read ` ` while the prompt shows
            m.set_ascii(true)
            while m.clock_t < 5.0:
                await m.get_tree().process_frame
            var bp: Vector3 = m.bolt.global_position
            var sp: Vector2 = m.player.cam.unproject_position(bp)
            var img: Image = m.get_viewport().get_texture().get_image()
            var blank := 0
            var cx := int(sp.x / 8.0)
            var cy := int(sp.y / 16.0)
            for dy in range(-1, 2):
                for dx in range(-1, 2):
                    var mx := 0.0
                    for py in 16:
                        for px in 8:
                            var c := img.get_pixel((cx + dx) * 8 + px, (cy + dy) * 16 + py)
                            mx = maxf(mx, maxf(c.r, maxf(c.g, c.b)))
                    if mx < 0.06:
                        blank += 1
            var bolt_black: bool = blank == 9
            var body_on_bolt: float = Vector2(m.creature.global_position.x - bp.x, m.creature.global_position.z - bp.z).length() if m.creature != null else INF
            Input.action_press("interact")
            var max_prog := 0.0
            var prompt_seen := true
            var t_bleach := -1.0
            var hue_b := -1.0
            while m.clock_t < 16.5:
                await m.get_tree().process_frame
                if m.bleach_t < 0.0:
                    max_prog = maxf(max_prog, m.bolt.progress)
                    prompt_seen = prompt_seen and m.interact.prompt.visible
                elif t_bleach < 0.0:
                    t_bleach = m.clock_t
                    hue_b = m.bleach_hue
            Input.action_release("interact")
            while m.clock_t < 20.0 and m.ended == "":
                await m.get_tree().process_frame
            var ended_b: bool = m.ended == "B"
            var on_door := 0
            for q: Vector3 in m.decals:
                if absf(q.z - pz1) <= 0.1:
                    on_door += 1
            for i in 3:
                await m.get_tree().process_frame
            m.set_ascii(true)
            for i in 2:
                await m.get_tree().process_frame
            var f: Image = m.get_viewport().get_texture().get_image()
            f.save_png("res://shots/t101_endB.png")
            while m.clock_t < m.end_t + 2.0:
                await m.get_tree().process_frame
            # M7.0g: the body stood on the bolt; at +2 s it has stepped aside, so
            # those 3x3 cells are no longer a hole and the mark can be read
            var blank_after: int = _blank3(m, bp)
            while m.clock_t < m.end_t + 2.5:
                await m.get_tree().process_frame
            var credits: bool = m.clipboard.visible
            # a real stop (M6.0b): no breath through the credits, the drone released
            var ex_lo := INF
            var ex_hi := -INF
            while m.clock_t < m.end_t + 6.0:
                await m.get_tree().process_frame
                if m.clock_t >= m.end_t + 3.0:
                    ex_lo = minf(ex_lo, m.lighting.ca.exposure_multiplier)
                    ex_hi = maxf(ex_hi, m.lighting.ca.exposure_multiplier)
            var breath_ratio: float = ex_hi / maxf(ex_lo, 1e-6)
            while m.clock_t < m.end_t + 8.0:
                await m.get_tree().process_frame
            var gain8: float = m.audio.gain
            var armed: bool = m.exit_armed
            ok = riding0 and aimed and bolt_black and blank_after < 9 and body_on_bolt <= 1.0 and max_prog == 0.0 and prompt_seen and t_bleach > 0.0 and t_bleach <= 14.0 and hue_b == 1.0 and ended_b and m.deaths == 0 and on_door == 1 and credits and breath_ratio <= 1.08 and gain8 < 0.2 and armed
            detail = "riding=%s aimed=%s bolt_black=%s(%d/9) blank_after_end=%d/9 body_to_bolt=%.2f max_progress=%.2f prompt_held=%s bleach_at=%.2f hue=%.0f ended=%s deaths=%d decals_on_door=%d credits=%s breath_ratio_3-6s=%.3f gain_8s=%.2f exit_armed=%s" % [riding0, aimed, bolt_black, blank, blank_after, body_on_bolt, max_prog, prompt_seen, t_bleach, hue_b, m.ended, m.deaths, on_door, credits, breath_ratio, gain8, armed]
        "early_sheet":
            # args: (none)
            # no --chores: a sheet thrown on A's row-0 rack before any chore counts
            # (M6.0a: the prop is spent, the part must land) but C2 waits for C1;
            # C1 by hand, two more sheets -> C2 done, the sun at 2, the seat in B
            var r0: Dictionary = m.racks["A"][0]
            m.player.position = r0["body"] + Vector3(0, 0.95, 1.4)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(-22.0)
            for i in 3:
                await m.get_tree().process_frame
            Input.action_press("interact")
            for i in 130:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 3:
                await m.get_tree().process_frame
            var thrown0: bool = r0["sheet"].visible
            var got1: int = m.game.chores[1]["got"]
            var done0: int = m.game.done_count()
            for k in 3:
                m.game.part("C1")
            var c1_only: bool = m.game.done_count() == 1 and not m.game.chores[1]["done"]
            for row in [1, 2]:
                var r: Dictionary = m.racks["A"][row]
                m.player.position = r["body"] + Vector3(0, 0.95, 1.4)
                for i in 3:
                    await m.get_tree().process_frame
                Input.action_press("interact")
                for i in 130:
                    await m.get_tree().process_frame
                Input.action_release("interact")
                for i in 3:
                    await m.get_tree().process_frame
            for i in 10:
                await m.get_tree().process_frame
            var c2: bool = m.game.chores[1]["done"]
            ok = thrown0 and got1 == 1 and done0 == 0 and c1_only and c2 and m.lighting.step == 2 and m.seat.get("room", "") == "B"
            detail = "thrown=%s C2_got_after_one=%d done_then=%d C1_only=%s C2=%s step=%d seat_room=%s" % [thrown0, got1, done0, c1_only, c2, m.lighting.step, m.seat.get("room", "")]
        "dim_drone":
            # args: --chores=2
            # caller passes --chores=2: the DIM phase - a seat, no body bound (the first
            # cut has not happened). Parked in the seat's beam as SIM death parks, the
            # dose climbs and the sub-drone must follow it (M6.0c): gain >= 0.3 at 4 s
            var s0: Dictionary = m.seat.duplicate()
            var park: Vector3 = s0["pos"] + s0["normal"] * 0.7
            m.player.position = Vector3(park.x, 0.95, park.z)
            m.player.look_at_yaw(90.0)
            var t0: float = m.clock_t
            while m.clock_t < t0 + 4.0:
                await m.get_tree().process_frame
            var gain4: float = m.audio.gain
            var no_body: bool = m.creature == null
            var lit: bool = m._in_seat_light()
            ok = no_body and lit and gain4 >= 0.3 and m.dose > 1.5
            detail = "no_body=%s lit=%s gain_4s=%.2f dose_4s=%.2f" % [no_body, lit, gain4, m.dose]
        "ride_freeze":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # caller passes --chores=5 --lamp=1 --pos=0,0.95,-14: W from 1.2 s; the lamp
            # off at 2.6 s mid-step, on at 5.0 s. The step freezes with the light and
            # resumes with it (M6.0d): no frame from 2.6 to 9 s moves the mass > 0.06 m
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            while m.clock_t < 2.6:
                Input.parse_input_event(_key(KEY_W, true))
                await m.get_tree().process_frame
            Input.parse_input_event(_key(KEY_W, false))
            var mid_step: bool = m.creature != null and m.creature.walking
            var u_off: float = m.creature.step_u if m.creature != null else -1.0
            Input.action_press("lamp")
            await m.get_tree().process_frame
            Input.action_release("lamp")
            var prev: Vector3 = m.creature.global_position if m.creature != null else Vector3.ZERO
            var max_move := 0.0
            var moved_off := 0.0
            var lit_again := false
            var frozen_at := Vector3.ZERO
            while m.clock_t < 9.0:
                await m.get_tree().process_frame
                if not lit_again and m.clock_t >= 5.0:
                    frozen_at = m.creature.global_position if m.creature != null else Vector3.ZERO
                    Input.action_press("lamp")
                    await m.get_tree().process_frame
                    Input.action_release("lamp")
                    lit_again = true
                if m.creature != null:
                    var d: float = m.creature.global_position.distance_to(prev)
                    max_move = maxf(max_move, d)
                    if m.clock_t < 5.0:
                        moved_off += d
                    prev = m.creature.global_position
            var u_end: float = m.creature.step_u if m.creature != null else -1.0
            # T120: the invariant is "a frozen step RESUMES, never snaps" - it walked
            # again after the relight and no frame jumped. (The old "step_u >= 1 by 9 s"
            # only held while the caretaker crawled at 1.0 m/s: at LAMP_WALK 1.6 the
            # disc edge is further off, so at 9 s the body is mid-stride, chasing.)
            var moved_on: float = m.creature.global_position.distance_to(frozen_at) if m.creature != null else -1.0
            ok = riding0 and mid_step and max_move <= 0.06 and moved_off < 0.01 and m.lighting.lamp_on and moved_on >= 0.2
            detail = "riding=%s mid_step_at_2.6=%s step_u_off=%.2f frozen_move=%.3f max_move_per_frame=%.3f lit_again=%s moved_after_relight=%.2f step_u_9s=%.2f" % [riding0, mid_step, u_off, moved_off, max_move, m.lighting.lamp_on, moved_on, u_end]
        "ride_door":
            # args: --chores=5 --lamp=1 --pos=0,0.95,10 --yaw=180
            # caller passes --chores=5 --lamp=1 --pos=0,0.95,10 --yaw=180: W 6 s through
            # the office doorway with the body 2 m ahead-left. Its mass never stands
            # inside a wall slab (M6.0d: a blocked step turns or waits); it ends in the office
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            var inside := 0
            var frames := 0
            while m.clock_t < 7.2:
                Input.parse_input_event(_key(KEY_W, true))
                await m.get_tree().process_frame
                if m.creature != null:
                    frames += 1
                    var q := PhysicsPointQueryParameters3D.new()
                    q.position = m.creature.global_position + Vector3(0, 0.3, 0)
                    q.collision_mask = 1
                    if not m.get_world_3d().direct_space_state.intersect_point(q).is_empty():
                        inside += 1
            Input.parse_input_event(_key(KEY_W, false))
            var in_office: bool = m.creature != null and m.creature.global_position.z > 12.3
            var player_in: bool = m.player.position.z > 12.3
            ok = riding0 and inside == 0 and frames > 300 and in_office and player_in
            detail = "riding=%s frames=%d mass_in_slab=%d body_in_office=%s player_in_office=%s body=%s" % [riding0, frames, inside, in_office, player_in, m.creature.global_position if m.creature != null else Vector3.ZERO]
        "cut_body_seen":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # caller passes --chores=5 --lamp=1 --pos=0,0.95,-14: riding; a turn-round
            # puts the disc edge behind, the lamp goes off at once, and the caretaker
            # turns back to the body it left 2 m ahead. The seat's own points are all
            # behind the camera; only the real body is in view - the cut must wait
            # (M6.0e); looking up, both unseen, it goes
            while m.clock_t < 1.2:
                await m.get_tree().process_frame
            var riding0: bool = m.riding() and m.creature != null
            var body0: Vector3 = m.creature.global_position if m.creature != null else Vector3.ZERO
            m.player.look_at_yaw(180.0)
            for i in 6:
                await m.get_tree().process_frame
            Input.action_press("lamp")
            await m.get_tree().process_frame
            Input.action_release("lamp")
            await m.get_tree().process_frame
            m.player.look_at_yaw(0.0)
            var seat_behind: bool = not m.seat.is_empty() and m.seat["pos"].z > m.player.position.z + 1.0
            var body_ahead: bool = m.creature != null and m.player.cam.is_position_in_frustum(m.creature.global_position + Vector3(0, 1.0, 0))
            while m.clock_t < 4.0:
                await m.get_tree().process_frame
            var waited: bool = m.cut_due >= 0.0 and m.creature != null and m.riding()
            m.player.look_at_pitch(80.0)
            while m.clock_t < 6.0:
                await m.get_tree().process_frame
            var went: bool = m.seat.is_empty() and m.creature == null and m.cut_due < 0.0
            ok = riding0 and not m.lighting.lamp_on and seat_behind and body_ahead and waited and went
            detail = "riding=%s lamp_off=%s seat_behind=%s real_body_in_view=%s waited_at_4s=%s went_after_lookup=%s body0=%s" % [riding0, not m.lighting.lamp_on, seat_behind, body_ahead, waited, went, body0]
        "stay_for_c5":
            # args: --chores=3 --step_at=4 --pos=0,0.95,0 --yaw=0
            # caller passes --chores=3 --step_at=4 --pos=0,0.95,0 --yaw=0: B shut, the
            # seat in A; the step from the hall re-picks. The last chore's room (B) can
            # seat nothing, so the pick spans both rooms and the thing stays in A (M6.0f:
            # it used to be freed - stranded through C4 and C5)
            var room0: String = m.seat.get("room", "")
            while m.clock_t < 3.0:
                await m.get_tree().process_frame
            var room3: String = m.seat.get("room", "")
            ok = room0 == "A" and room3 == "A" and not m.seat.is_empty() and m.cut_due < 0.0
            detail = "room0=%s room3=%s empty=%s due=%.2f" % [room0, room3, m.seat.is_empty(), m.cut_due]
        "d6_probe":
            # args: --chores=2
            # caller passes --chores=2 (the live patches off the floor): from 1.8 m over
            # D6's absence, the graphics frame is saved and the screen points of the
            # silhouette's axis and flanks are printed for a luminance profile (M6.0i)
            var f: Vector3 = m.d6_pos
            var d := Lighting.sun_dir(0)
            var ax := Vector2(d.x, d.z).normalized()
            var pp := Vector2(-ax.y, ax.x)
            # T124: a plan view of A's floor - overhead, straight down - so the whole
            # burn is in frame and every sample lands where it is meant to
            # the figure as the code places it (M7.0o holds the open question of where
            # the decal's texture really lands in the world)
            m.player.position = Vector3(f.x + 0.6, 0.95, f.z + 1.2)
            m.player.look_at_yaw(31.0)
            m.player.look_at_pitch(-43.0)
            m.set_ascii(false)
            for i in 8:
                await m.get_tree().process_frame
            var g: Image = m.get_viewport().get_texture().get_image()
            g.save_png("res://shots/t111_d6probe.png")
            @warning_ignore("unassigned_variable")
            # M7.0c: measure, do not just photograph. At each station along the shadow,
            # the floor ON the silhouette's axis must read darker than the burned floor
            # beside it (v = 0.35 m off): the absence is unburned floor inside a burn.
            # 12 of 255 is about half a glyph step - under that the reading shows nothing.
            var lum := func(im: Image, w: Vector3) -> float:
                var q: Vector2 = m.player.cam.unproject_position(w)
                var sum := 0.0
                var cnt := 0
                for dy in range(-1, 2):
                    for dx in range(-1, 2):
                        var px2 := int(q.x) + dx
                        var py2 := int(q.y) + dy
                        if px2 >= 0 and py2 >= 0 and px2 < im.get_width() and py2 < im.get_height():
                            var c := im.get_pixel(px2, py2)
                            sum += (c.r + c.g + c.b) / 3.0 * 255.0
                            cnt += 1
                return sum / maxf(cnt, 1)
            # M7.0c: measure the BURN, not the room. Each station is sampled twice -
            # decal on and decal off - so the floor's own gradient cancels. Inside the
            # silhouette the burn adds nothing (the absence is unburned floor); 0.35 m
            # off the axis it adds the burn. The difference is what a reader can see.
            # M7.0c: map the burn itself. Every point is sampled twice - decal on and
            # decal off - so the room's own light cancels and what is left is the burn:
            # "#" where it darkens the floor by >= 12 of 255 (burned), "." where it does
            # nothing (the absence, and anything outside the burn). The silhouette should
            # read as a person-shaped run of "." inside a field of "#".
            # T124: map the burn in WORLD axes over the centre patch - X across, Z down,
            # 0.25 m steps - so the person-shaped absence shows wherever it really is
            var on_l := {}
            for iz in 13:
                for ix in 13:
                    var w := Vector3(f.x - 1.2 + 0.2 * ix, 0.0, f.z - 1.2 + 0.2 * iz)
                    on_l["%d,%d" % [ix, iz]] = lum.call(g, w)
            m.d6_decal.visible = false
            for i in 4:
                await m.get_tree().process_frame
            var g2: Image = m.get_viewport().get_texture().get_image()
            var rows := []
            var burned := 0
            var absence := 0
            for iz in 13:
                var line := ""
                for ix in 13:
                    var w := Vector3(f.x - 1.2 + 0.2 * ix, 0.0, f.z - 1.2 + 0.2 * iz)
                    var dv: float = on_l["%d,%d" % [ix, iz]] - lum.call(g2, w)
                    if dv <= -12.0:
                        line += "#"
                        burned += 1
                    else:
                        line += "."
                        absence += 1
                rows.append(line)
            m.d6_decal.visible = true
            var gaps := {0.2: 0.0, 0.5: 0.0, 0.72: 0.0, 0.84: 0.0}
            # M7.0c: the probe is honest about what it can see - the burn RENDERS (it
            # changes the floor by >= 12 of 255 somewhere in frame) and it is not a solid
            # slab (unburned floor remains). The figure's own shape is proven in texture
            # space by TEST d6_shape, which no camera or decal convention can hide.
            ok = burned >= 8 and absence >= 8
            detail = "feet=%.2f,%.2f flank-minus-axis: legs(0.2)=%.0f body(0.5)=%.0f neck(0.72)=%.0f head(0.84)=%.0f | burn map: X across, Z down, 0.2 m, around d6_pos | %s" % [f.x, f.z, gaps[0.2], gaps[0.5], gaps[0.72], gaps[0.84], "|".join(rows)]
        "route":
            # args: --t=70 (SIM_TIMEOUT=240)
            # caller passes --t=70 (the watchdog's frames): the whole game as play takes
            # it, no --chores fast-forward - C1 to C7 then Ending A, teleporting between
            # beats and standing still to hold. Asserts the sun's steps, the seat's
            # rooms (B after C2, A after C3, the lamp during C5, none with the lamp
            # off after C5, the lamp again), no death, all seven done, ended A (M6.0j)
            var z1: float = m.HALL_L * 0.5 + m.WALL + m.OFF_D
            var pz1: float = -(m.HALL_L * 0.5 + m.WALL) - m.PLANT_D
            var steps := []
            var seats := []
            # C1: the plaques (Tab on), the log
            m.set_ascii(true)
            await _hold(m, Vector3(-3.0, 0.95, -1.5), -90.0, -10.0, 66)
            await _hold(m, Vector3(3.0, 0.95, -1.5), 90.0, -10.0, 66)
            m.set_ascii(false)
            await _hold(m, Vector3(1.6, 0.95, z1 - 1.4), 145.0, -36.0, 190)
            steps.append(m.lighting.step)
            # C2: A's three sheets
            for row in 3:
                await _hold(m, m.racks["A"][row]["body"] + Vector3(0, 0.95, 1.4), 0.0, -22.0, 130)
            for i in 10:
                await m.get_tree().process_frame
            steps.append(m.lighting.step)
            seats.append(m.seat.get("room", "none"))
            # C3: B's three cranks, each in its row's light
            for row in 3:
                var st: Vector3 = Thing.crank_stand("B", row)
                var n: Vector3 = Thing.crank_normal("B", row)
                var cp: Vector3 = Thing.crank_pos("B", row)
                await _hold(m, Vector3(st.x, 0.95, st.z), rad_to_deg(atan2(n.x, n.z)), rad_to_deg(atan2(cp.y - 1.7, Thing.CRANK_REACH)), 190)
            for i in 10:
                await m.get_tree().process_frame
            steps.append(m.lighting.step)
            # leave B facing away: the re-pick crosses to A unseen
            m.player.position = Vector3(0.0, 0.95, 4.0)
            m.player.look_at_yaw(180.0)
            m.player.look_at_pitch(0.0)
            await _wait(m, m.clock_t + 2.5)
            seats.append(m.seat.get("room", "none"))
            # C4: the lamp from its hook, the valve in the dark
            await _hold(m, Vector3(-0.9, 0.95, -10.6), 0.0, -5.0, 70)
            await _hold(m, Vector3(-0.6, 0.95, -14.0), 0.0, -35.0, 490)
            steps.append(m.lighting.step)
            # C5: the lamp lit, A's three cranks with it riding; the dose is cooled
            # between cranks as walking would (L off, 4 s, L on)
            await _tap(m, "lamp")
            for row in 3:
                var st: Vector3 = Thing.crank_stand("A", row)
                var cp: Vector3 = Thing.crank_pos("A", row)
                await _hold(m, Vector3(st.x, 0.95, st.z), -90.0, rad_to_deg(atan2(cp.y - 1.7, Thing.CRANK_REACH)), 190)
                if row == 1:
                    seats.append(m.seat.get("surface", "none"))
                if row < 2:
                    await _tap(m, "lamp")
                    await _wait(m, m.clock_t + 4.0)
                    await _tap(m, "lamp")
            for i in 10:
                await m.get_tree().process_frame
            steps.append(m.lighting.step)
            # everything shut: the lamp off and away from it, the seat goes; on again, it rides
            await _tap(m, "lamp")
            m.player.position = Vector3(0.0, 0.95, 8.0)
            m.player.look_at_yaw(180.0)
            await _wait(m, m.clock_t + 2.5)
            seats.append("none" if m.seat.is_empty() else m.seat.get("surface", "?"))
            await _tap(m, "lamp")
            await _wait(m, m.clock_t + 1.5)
            seats.append(m.seat.get("surface", "none"))
            # C6: the card, with the lamp
            await _hold(m, Thing.rack_pos("A", 1) + Vector3(0, 0.95, 1.6), 0.0, -24.0, 190)
            steps.append(m.lighting.step)
            # C7: hang the lamp on the desk hook, sign the log
            await _hold(m, Vector3(-1.3, 0.95, 12.74), 90.0, -12.0, 70)
            await _hold(m, Vector3(1.6, 0.95, z1 - 1.4), 145.0, -36.0, 370)
            steps.append(m.lighting.step)
            var done7: int = m.game.done_count()
            # Ending A: the bolt with the lamp hung
            await _hold(m, Vector3(0.0, 0.95, pz1 + 1.2), -17.0, -23.0, 250)
            for i in 30:
                await m.get_tree().process_frame
            ok = steps == [1, 2, 3, 4, 5, 5, 5] and seats == ["B", "A", "lamp", "none", "lamp"] and done7 == 7 and m.ended == "A" and m.deaths == 0
            detail = "steps=%s seats=%s done=%d ended=%s deaths=%d clock=%.1f" % [steps, seats, done7, m.ended, m.deaths, m.clock_t]
        "endA_unlit":
            # args: --chores=7 --lamp=1
            # caller passes --chores=7 --lamp=1: at the door riding, the lamp goes off
            # watched (the seat holds, the body on the bolt), then the bolt held 4 s -
            # Ending A with a body present: it is kept, standing in the dark while the
            # door opens (M6.0j decision); the dusk frame is saved at +2.5 s
            var pz1: float = -(m.HALL_L * 0.5 + m.WALL) - m.PLANT_D
            m.player.position = Vector3(0.0, 0.95, pz1 + 1.2)
            m.player.look_at_yaw(-17.0)
            m.player.look_at_pitch(-23.0)
            await _wait(m, 3.5)
            var riding0: bool = m.riding() and m.creature != null
            await _tap(m, "lamp")
            await _wait(m, m.clock_t + 1.5)
            var held: bool = m.creature != null and not m.lighting.lamp_on
            await _hold(m, Vector3(0.0, 0.95, pz1 + 1.2), -17.0, -23.0, 250)
            var ended_a: bool = m.ended == "A"
            var body_kept: bool = m.creature != null
            var t_end: float = m.end_t
            await _wait(m, t_end + 2.5)
            m.set_ascii(true)
            for i in 2:
                await m.get_tree().process_frame
            var dusk: Image = m.get_viewport().get_texture().get_image()
            dusk.save_png("res://shots/t112_endA_unlit.png")
            # M7.0f: _process returns once ended, so a bolt held inside colour_first's
            # fade used to leave the mass frozen part-risen; the ending restores it
            var rise_full: float = m.creature.rise if m.creature != null else -1.0
            # M7.0g: the door is the last image - it reads as dusk in ' .:-', and the
            # kept body has stepped out of the opening instead of filling it
            var door := [Vector3(-0.5, 0.05, pz1), Vector3(0.5, 0.05, pz1), Vector3(-0.5, 2.35, pz1), Vector3(0.5, 2.35, pz1)]
            var read: Array = _door_read(m, door, m.creature)
            ok = riding0 and held and ended_a and body_kept and m.deaths == 0 and m.yard_door.size() == 5 and not m.yard_door[0].visible and rise_full >= 0.99 and read[0] >= 0.40 and not read[1]
            detail = "riding=%s held_off=%s ended=%s body_kept=%s deaths=%d rise=%.3f cf_t0=%.1f door_dark=%.2f (%d cells) body_in_doorway=%s" % [riding0, held, m.ended, body_kept, m.deaths, rise_full, m.cf_t0, read[0], read[2], read[1]]
        "c5_list":
            # args: --chores=4 --lamp=1
            # C5 completed by hand at 1 s: the clipboard rises by itself for 4 s with no
            # C press (M6.0n), then drops - and the gate's key turns on the drop
            await _wait(m, 1.0)
            var seen0: bool = m.game.colour_seen
            m.game.complete("C5")
            await _wait(m, 1.4)
            var up: bool = m.clipboard.visible and not Input.is_action_pressed("clipboard")
            var seen_up: bool = m.game.colour_seen
            await _wait(m, 5.6)
            var down: bool = not m.clipboard.visible
            ok = not seen0 and up and not seen_up and down and m.game.colour_seen
            detail = "seen_before=%s up_without_C=%s seen_while_up=%s down_at_4.6s=%s seen_after=%s" % [seen0, up, seen_up, down, m.game.colour_seen]
        "colour_order":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # the gate closed by hand (the harness opens it at --chores>=5): riding, C
            # held from 1.5 s - no tint while the word is on screen; released at 3.0 s
            # the hue is full within 2.1 s (M6.0n)
            await _wait(m, 0.2)
            m.game.colour_seen = false
            m.cf_done = false
            await _wait(m, 1.5)
            var riding0: bool = m.riding()
            Input.action_press("clipboard")
            await _wait(m, 2.9)
            var held_zero: bool = m.hue_mix == 0.0 and m.clipboard.visible
            Input.action_release("clipboard")
            await _wait(m, 5.1)
            var full: bool = m.hue_mix >= 0.99
            ok = riding0 and held_zero and full
            detail = "riding=%s hue_0_while_held=%s hue_full_2.1s_after_release=%s hue=%.2f" % [riding0, held_zero, full, m.hue_mix]
        "colour_first":
            # args: --chores=5 --lamp=1 --pos=0,0.95,-14
            # as colour_order, then: while the hue is up the body's rise is away
            # (colour alone, 2-4 s after the release), and back by 6.5 s (M6.0n)
            await _wait(m, 0.2)
            m.game.colour_seen = false
            m.cf_done = false
            await _wait(m, 1.5)
            Input.action_press("clipboard")
            await _wait(m, 3.0)
            Input.action_release("clipboard")
            var t_rel: float = m.clock_t
            var rise_lo := INF
            var hue_lo := INF
            while m.clock_t < t_rel + 3.8:
                await m.get_tree().process_frame
                if m.clock_t >= t_rel + 2.2 and m.creature != null:
                    rise_lo = minf(rise_lo, m.creature.rise)
                    hue_lo = minf(hue_lo, m.hue_mix)
            var away: bool = rise_lo <= 0.05 and hue_lo >= 0.9
            var rise_max_away: float = rise_lo
            await _wait(m, t_rel + 6.5)
            var back: bool = m.creature != null and m.creature.rise >= 0.95 and m.hue_mix >= 0.99
            ok = away and back
            detail = "rise_2.2-3.8s<=%.2f hue_min=%.2f away=%s back_by_6.5s=%s rise=%.2f" % [rise_max_away, hue_lo, away, back, m.creature.rise if m.creature != null else -1.0]
        "lamp_play":
            # args: --chores=3
            # the owner's report (T119): "the lamp aint working". Play's own path, no
            # --lamp: stand in the hall by the plant doorway, aim at the hook, E 1.2 s,
            # press L, and MEASURE the world - the mean luminance of the graphics frame
            # in the hall and then in the dark plant room, lamp off against lamp on
            var lum := func() -> float:
                var img: Image = m.get_viewport().get_texture().get_image()
                var sum := 0.0
                var n := 0
                for y in range(0, img.get_height(), 8):
                    for x in range(0, img.get_width(), 8):
                        var c := img.get_pixel(x, y)
                        sum += (c.r + c.g + c.b) / 3.0
                        n += 1
                return sum / maxf(n, 1)
            m.set_ascii(false)
            var hp: Vector3 = m.hook_plant.global_position
            m.player.position = Vector3(hp.x, 0.95, hp.z + 1.8)
            var to: Vector3 = hp - (m.player.position + Vector3(0, 0.75, 0))
            m.player.look_at_yaw(rad_to_deg(atan2(-to.x, -to.z)))
            m.player.look_at_pitch(rad_to_deg(atan2(to.y, Vector2(to.x, to.z).length())))
            for i in 6:
                await m.get_tree().process_frame
            var aimed: bool = m.interact.target == m.hook_plant
            var prompt_up: bool = m.interact.prompt.visible
            var label0: String = m.hook_plant.prompt
            # what the eye's ray actually meets (T119)
            var eye: Vector3 = m.player.cam.global_position
            var q := PhysicsRayQueryParameters3D.create(eye, hp, 3, [m.player.get_rid()])
            var hit: Dictionary = m.get_world_3d().direct_space_state.intersect_ray(q)
            var what: String = "none"
            if not hit.is_empty():
                var c = hit["collider"]
                what = "%s(%s) at %.2f,%.2f,%.2f" % [c.get_class(), c.prompt if c is Interactable else c.name, hit["position"].x, hit["position"].y, hit["position"].z]
            var tgt: String = "null"
            if m.interact.target != null:
                tgt = "%s fired=%s layer=%d" % [m.interact.target.prompt, m.interact.target.fired, m.interact.target.collision_layer]
            var dbg: String = "hook=%.2f,%.2f,%.2f eye=%.2f,%.2f,%.2f d=%.2f ray_meets=%s target=%s hook_layer=%d hook_fired=%s" % [hp.x, hp.y, hp.z, eye.x, eye.y, eye.z, eye.distance_to(hp), what, tgt, m.hook_plant.collision_layer, m.hook_plant.fired]
            Input.action_press("interact")
            for i in 90:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 6:
                await m.get_tree().process_frame
            var held: bool = m.lamp_where == "held"
            # the hall, by the doorway: off then on
            var hall_off: float = lum.call()
            Input.action_press("lamp")
            await m.get_tree().process_frame
            Input.action_release("lamp")
            for i in 30:
                await m.get_tree().process_frame
            var lit: bool = m.lighting.lamp_on
            var mounted: bool = m.lighting.lamp_light != null and m.lighting.lamp_light.visible and m.lighting.lamp_light.get_parent() == m.player.cam
            var hall_on: float = lum.call()
            # inside the dark plant room, facing the far wall
            m.player.position = Vector3(0.0, 0.95, -13.5)
            m.player.look_at_yaw(0.0)
            m.player.look_at_pitch(0.0)
            for i in 120:
                await m.get_tree().process_frame
            var plant_on: float = lum.call()
            var img_on: Image = m.get_viewport().get_texture().get_image()
            img_on.save_png("res://shots/t119_lamp_on.png")
            Input.action_press("lamp")
            await m.get_tree().process_frame
            Input.action_release("lamp")
            for i in 30:
                await m.get_tree().process_frame
            var plant_off: float = lum.call()
            var img_off: Image = m.get_viewport().get_texture().get_image()
            img_off.save_png("res://shots/t119_lamp_off.png")
            ok = aimed and prompt_up and held and lit and mounted and plant_on >= plant_off + 0.05
            detail = "%s | aimed=%s prompt=%s label=%s held=%s lit=%s mounted=%s hall_off=%.3f hall_on=%.3f plant_on=%.3f plant_off=%.3f energy=%.1f range=%.1f angle=%.0f" % [dbg, aimed, prompt_up, label0, held, lit, mounted, hall_off, hall_on, plant_on, plant_off, m.lighting.lamp_light.light_energy if m.lighting.lamp_light != null else -1.0, m.lighting.lamp_light.spot_range if m.lighting.lamp_light != null else -1.0, m.lighting.lamp_light.spot_angle if m.lighting.lamp_light != null else -1.0]
        "early_crank":
            # args: (none)
            # M7.0a: from the first minute B's cranks are dead - their chore (C3) is not
            # next - so the house cannot be shut before the thing has a pane to sit in
            # (the gate M6 blocker: it then never spawned at all). C1 and C2 by hand and
            # the same crank works, shuts its row, counts C3 and the seat lands in B
            var st: Vector3 = Thing.crank_stand("B", 0)
            var n: Vector3 = Thing.crank_normal("B", 0)
            var cp: Vector3 = Thing.crank_pos("B", 0)
            m.player.position = Vector3(st.x, 0.95, st.z)
            m.player.look_at_yaw(rad_to_deg(atan2(n.x, n.z)))
            m.player.look_at_pitch(rad_to_deg(atan2(cp.y - 1.7, Thing.CRANK_REACH)))
            for i in 6:
                await m.get_tree().process_frame
            var crank: Interactable = m.shutters["B"][0]["crank"]
            var aimed0: bool = m.interact.target == crank
            var label0: String = crank.prompt
            var silent0: bool = not m.interact.prompt.visible
            Input.action_press("interact")
            for i in 210:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 6:
                await m.get_tree().process_frame
            var open0: bool = not Thing.is_shut(m.lighting.shut, "B", 0, 0)
            var got0: int = m.game.chores[2]["got"]
            for k in 3:
                m.game.part("C1")
            for k in 3:
                m.game.part("C2")
            for i in 30:
                await m.get_tree().process_frame
            var label1: String = crank.prompt
            Input.action_press("interact")
            for i in 210:
                await m.get_tree().process_frame
            Input.action_release("interact")
            for i in 10:
                await m.get_tree().process_frame
            var shut1: bool = Thing.is_shut(m.lighting.shut, "B", 0, 0)
            var got1: int = m.game.chores[2]["got"]
            ok = aimed0 and label0 == "" and silent0 and open0 and got0 == 0 and label1 == "crank" and shut1 and got1 == 1 and m.seat.get("room", "") == "B"
            detail = "aimed=%s early_label='%s' early_prompt_hidden=%s row_open=%s C3_got_early=%d later_label='%s' shut=%s C3_got=%d seat=%s" % [aimed0, label0, silent0, open0, got0, label1, shut1, got1, m.seat.get("room", "none")]
        "hook_sweep":
            # args: --chores=3
            # M7.0b: the hall's end is black at step 3, so the hook is found by sweeping
            # for its prompt - a level look from the middle of the hall must meet it over
            # several degrees, not one. Yaw -40..40 in 5 deg steps at eye height
            m.player.position = Vector3(0.0, 0.95, -10.6)
            m.player.look_at_pitch(0.0)
            var hits := ""
            var best := 0
            var run := 0
            for k in 17:
                m.player.look_at_yaw(-40.0 + 5.0 * k)
                for i in 4:
                    await m.get_tree().process_frame
                var on: bool = m.interact.target == m.hook_plant and m.hook_plant.prompt == "take"
                hits += "1" if on else "0"
                run = run + 1 if on else 0
                best = maxi(best, run)
            ok = best >= 5
            detail = "yaws(-40..40 by 5)=%s longest_run=%d" % [hits, best]
        "hud_resize":
            # args: --start=1
            # M7.0d: the blank must cover the window it is shown in, and the start line
            # must sit in the middle of it - play maximises itself on a resizable window,
            # so a HUD cut once to 1600x900 left live world past the blank at every death
            await _wait(m, 0.4)
            var vp0: Vector2 = m.get_viewport().get_visible_rect().size
            var blank0: bool = m.blank.size.is_equal_approx(vp0)
            var mid0: float = absf(m.start_line.position.x + m.start_line.size.x * 0.5 - vp0.x * 0.5)
            m.get_window().size = Vector2i(1920, 1080)
            for i in 20:
                await m.get_tree().process_frame
            var vp1: Vector2 = m.get_viewport().get_visible_rect().size
            var blank1: bool = m.blank.size.is_equal_approx(vp1)
            var mid1: float = absf(m.start_line.position.x + m.start_line.size.x * 0.5 - vp1.x * 0.5)
            m.get_window().size = Vector2i(1600, 900)
            for i in 20:
                await m.get_tree().process_frame
            ok = blank0 and blank1 and mid0 <= 12.0 and mid1 <= 12.0 and vp1.x > vp0.x
            detail = "vp %s -> %s | blank covers: %s then %s | start line off centre: %.0f then %.0f px" % [vp0, vp1, blank0, blank1, mid0, mid1]
        _:
            detail = "unknown sim"
    return [ok, detail]
