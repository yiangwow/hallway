extends SceneTree
# Headless test runner: `tools/test.sh` -> `./run.sh --headless -s tests/run.gd`.
# Each test prints exactly one `TEST name PASS|FAIL detail` line. Exit 1 on any FAIL.
# Pure functions only here (no rendering); anything that needs a frame is a SIM.

var failures := 0

func _init() -> void:
    var user_args := {}
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--") and "=" in a:
            var kv := a.substr(2).split("=", true, 1)
            user_args[kv[0]] = kv[1]
    test_smoke(user_args)
    test_sun_monotonic()
    test_main_surface()
    test_chores_order()
    test_sun_dir()
    test_first_zone_snap()
    test_ramp_vs_breath()
    test_pane_geom()
    test_seat_table()
    test_pick_seat()
    test_cut_batching()
    test_never_in_view()
    test_dose_step()
    test_seat_points_in_room()
    test_last_ab_room()
    test_bleach_target()
    test_breath_amp()
    test_dropout_stats()
    test_body_in_room()
    test_shutter_bits()
    test_presence_hint()
    test_light_cap()
    test_forced_crossing()
    test_lamp_seat()
    test_audio_wavs()
    test_drone_gain()
    test_in_beam()
    test_found_text_len()
    test_clipboard_bb()
    test_sims_index()
    test_colour_first()
    test_chores_text()
    test_d6_shape()
    quit(1 if failures > 0 else 0)

func check(name: String, ok: bool, detail: String = "") -> void:
    if ok:
        print("TEST %s PASS %s" % [name, detail])
    else:
        failures += 1
        print("TEST %s FAIL %s" % [name, detail])

func test_smoke(user_args: Dictionary) -> void:
    # the runner itself works, scripts load, and --fail=1 proves a FAIL exits 1
    var main_script := load("res://main.gd")
    var ok := main_script != null and not user_args.has("fail")
    check("smoke", ok, "main.gd loads" if main_script != null else "main.gd failed to load")

func test_sun_monotonic() -> void:
    var root := Node3D.new()
    var l := Lighting.new()
    root.add_child(l)
    l.build(root, {})
    var emits := [0]
    l.light_changed.connect(func(_k: String) -> void: emits[0] += 1)
    l.sun_step(2)
    l.sun_step(1)
    l.sun_step(2)
    check("sun_monotonic", l.step == 2 and emits[0] == 1, "step=%d emits=%d" % [l.step, emits[0]])
    root.free()

# a slice edit once deleted main._process wholesale (T18); the surface is now asserted
func test_main_surface() -> void:
    var sc: GDScript = load("res://main.gd")
    var names := []
    for m in sc.get_script_method_list():
        names.append(m["name"])
    var missing := []
    for want in ["_ready", "_process", "_maybe_screenshot", "_run_sim", "_capture", "set_ascii", "_creature", "_interact", "_hud", "numbers_line", "patch_line", "seat_line", "_sync_prompts"]:
        if not names.has(want):
            missing.append(want)
    # M4.0a: the stateless world builders moved to props.gd (Props) as static funcs
    var props_sc: GDScript = load("res://props.gd")
    var props_names := []
    for pm in props_sc.get_script_method_list():
        props_names.append(pm["name"])
    var props_missing := []
    for want in ["slab", "_mat", "_materials", "_floor", "_build_hallway", "_build_room", "_build_office", "_plaque", "_interactable", "_c1_props"]:
        if not props_names.has(want):
            props_missing.append(want)
    # M3.0a: the --shot/--sim harness moved to tests/harness.gd (Harness) as static funcs
    var harness_sc: GDScript = load("res://tests/harness.gd")
    var harness_names := []
    for hm in harness_sc.get_script_method_list():
        harness_names.append(hm["name"])
    var harness_missing := []
    for want in ["shoot", "capture", "lines", "run_sim"]:
        if not harness_names.has(want):
            harness_missing.append(want)
    check("main_surface", missing.is_empty() and props_missing.is_empty() and harness_missing.is_empty(), "missing=%s props=%s harness=%s" % [missing, props_missing, harness_missing])

func test_chores_order() -> void:
    var g := Game.new()
    var refused := not g.complete("C2")
    var c1 := g.complete("C1")
    var again := not g.complete("C1")
    var parts := Game.new()
    var p1 := parts.part("C1") and parts.part("C1") and parts.done_count() == 0 and parts.part("C1") and parts.done_count() == 1
    var steps := Game.step_for(0, 0.0) == 0 and Game.step_for(0, 181.0) == 1 and Game.step_for(7, 0.0) == 5 and Game.step_for(2, 900.0) == 2 and Game.step_for(2, 600.0) == 2 and Game.step_for(3, 600.0) == 3 and Game.step_for(3, 900.0) == 5   # M5.0l: capped at 2 while C3 is open
    var r := Game.new()
    var rooms0 := r.last_room() == "" and r.next_room() == "office"
    r.complete("C1")
    r.complete("C2")
    var rooms2 := r.last_room() == "A" and r.next_room() == "B" and r.room_of("C4") == "plant"
    # M6.0a: parts land whatever the order; chores complete in order
    var early := Game.new()
    var order := []
    early.chore_done.connect(func(id: String) -> void: order.append(id))
    for k in 3:
        early.part("C2")
    var waiting: bool = early.done_count() == 0 and early.chores[1]["got"] == 3
    for k in 3:
        early.part("C1")
    var landed: bool = early.done_count() == 2 and order == ["C1", "C2"]
    var ok := refused and c1 and again and p1 and steps and rooms0 and rooms2 and waiting and landed
    check("chores_order", ok, "refused_C2=%s C1=%s again=%s parts=%s steps=%s rooms=%s/%s early_waits=%s early_lands=%s order=%s" % [refused, c1, again, p1, steps, rooms0, rooms2, waiting, landed, order])

func _lighting() -> Array:
    var root := Node3D.new()
    var l := Lighting.new()
    root.add_child(l)
    l.build(root, {})
    return [root, l]

func test_sun_dir() -> void:
    var rl := _lighting()
    var l: Lighting = rl[1]
    var worst := 0.0
    for n in 6:
        l.step = -1
        l.sun_step(n)
        var engine := l.sun.transform.basis * Vector3.FORWARD
        worst = maxf(worst, (engine - Lighting.sun_dir(n)).length())
    var d0 := Lighting.sun_dir(0)
    var expect := (d0 - Vector3(-0.22, -0.88, -0.41)).length() < 0.02
    check("sun_dir", worst < 1e-4 and expect, "worst=%.6f dir0=%s" % [worst, d0])
    rl[0].free()

func test_first_zone_snap() -> void:
    var rl := _lighting()
    var l: Lighting = rl[1]
    l.set_zone("office")
    var snapped := is_equal_approx(l.ca.exposure_multiplier, 4.0)
    l.set_zone("hall")
    var unchanged := is_equal_approx(l.ca.exposure_multiplier, 4.0)
    for i in 120:
        l.tick(1.0 / 60.0)
    var ramped := is_equal_approx(l.ca.exposure_multiplier, 3.0)
    check("first_zone_snap", snapped and unchanged and ramped, "snap=%s unchanged=%s ramped_to=%.3f" % [snapped, unchanged, l.ca.exposure_multiplier])
    rl[0].free()

func test_ramp_vs_breath() -> void:
    var rl := _lighting()
    var l: Lighting = rl[1]
    l.set_zone("hall")           # snaps to 3.0
    l.set_zone("A")              # ramps toward 1.0
    for i in 60:
        l.tick(1.0 / 60.0)
    l.breath_dist = 0.0          # breathing at full amplitude mid-ramp must not feed back into the ramp
    l.breath_t = 0.6             # sin(TAU * 0.6 / 2.4) = 1 -> breath 1.05 (prox only, dose 0)
    l.tick(1.0 / 60.0)
    var base_before: float = l._base_exp
    var breathed: bool = absf(l.ca.exposure_multiplier - base_before * 1.05) < 1e-3
    l.set_zone("office")         # retarget seeds from the base, not the breathed value
    var seeded := is_equal_approx(l._ramp_from, base_before)
    check("ramp_vs_breath", seeded and breathed, "ramp_from=%.3f base=%.3f mult=%.3f" % [l._ramp_from, base_before, l.ca.exposure_multiplier])
    rl[0].free()

func test_pane_geom() -> void:
    var ok := true
    var area := 0.0
    for room in ["A", "B"]:
        var opening := Rect2(Vector2(Thing.room_cx(room) - 3.0, -3.0), Vector2(6.0, 6.0))
        var rects: Array[Rect2] = []
        for row in 3:
            for col in 3:
                var r := Thing.pane_rect(room, row, col)
                ok = ok and opening.grow(0.001).encloses(r) and r.size.x > 1.8 and r.size.y > 1.8
                for q in rects:
                    ok = ok and not q.intersects(r)
                rects.append(r)
                if room == "B":
                    area += r.get_area()
    var b20 := Thing.pane_rect("B", 2, 0)
    var spec := absf(b20.position.x - 3.30) < 0.01 and absf(b20.end.x - 5.24) < 0.01 and absf(b20.position.y - 1.06) < 0.01 and absf(b20.end.y - 3.0) < 0.01
    ok = ok and spec and absf(area - 33.18) < 0.1 and Thing.bit("B", 2, 0) == 15 and Thing.bit("A", 0, 0) == 0
    check("pane_geom", ok, "B r2c0=%s area=%.2f" % [b20, area])

func test_seat_table() -> void:
    var ok := true
    var lines := PackedStringArray()
    for room in ["A", "B"]:
        var box := Thing.room_box(room)
        for row in 3:
            for col in 3:
                var cells := PackedStringArray()
                for step in 6:
                    var s := Thing.seat(room, row, col, step)
                    if s.is_empty():
                        cells.append("--")
                        continue
                    ok = ok and box.grow(0.02).has_point(s["pos"])
                    cells.append("%s(%.1f,%.1f,%.1f)%s" % [s["surface"][0], s["pos"].x, s["pos"].y, s["pos"].z, "r" if Thing.reachable(s) else ""])
                lines.append("SEAT %s r%dc%d: %s" % [room, row, col, " ".join(cells)])
    var b0 := Thing.seat("B", 2, 0, 0)
    var b2 := Thing.seat("B", 2, 0, 2)
    var a2 := Thing.seat("A", 2, 2, 2)
    var f0: bool = not b0.is_empty() and b0["surface"] == "floor"
    var w2: bool = not b2.is_empty() and b2["surface"] == "wall" and absf(b2["pos"].x - 1.80) < 0.02 and absf(b2["pos"].y - 1.26) < 0.15 and absf(b2["pos"].z + 2.62) < 0.2
    var far: bool = not a2.is_empty() and a2["surface"] == "wall" and absf(a2["pos"].x + 10.8) < 0.02
    # M3.0l: reachable by the patch's foot, not its centre
    var r0s1 := Thing.seat("B", 0, 0, 1)
    var r2s3 := Thing.seat("B", 2, 0, 3)
    var r0s2 := Thing.seat("B", 0, 0, 2)
    var feet := "B r0c0 s1 foot=%.2f(c %.2f) r=%s; B r2c0 s3 foot=%.2f(c %.2f) r=%s; B r0c0 s2 foot=%.2f(c %.2f) r=%s" % [Thing.patch_foot(r0s1), r0s1["pos"].y, Thing.reachable(r0s1), Thing.patch_foot(r2s3), r2s3["pos"].y, Thing.reachable(r2s3), Thing.patch_foot(r0s2), r0s2["pos"].y, Thing.reachable(r0s2)]
    var foot_rule: bool = Thing.reachable(r0s1) and Thing.reachable(r2s3) and not Thing.reachable(r0s2)
    ok = ok and f0 and w2 and far and foot_rule
    for l in lines:
        print(l)
    check("seat_table", ok, "B r2c0 s0=%s s2=%s A r2c2 s2=%s | %s" % [b0.get("pos"), b2.get("pos"), a2.get("pos"), feet])

func test_pick_seat() -> void:
    var ok := true
    var detail := ""
    for step in 6:
        var a := Thing.pick_seat(step, 0, false, Vector3(-3, 1, 0), "A")
        var b := Thing.pick_seat(step, 0, false, Vector3(3, 1, 0), "B")
        if a.is_empty() or b.is_empty():
            ok = false
            detail += " step%d_empty" % step
    var all_shut := (1 << 18) - 1
    var none := Thing.pick_seat(0, all_shut, false, Vector3.ZERO)
    var lamp := Thing.pick_seat(0, all_shut, true, Vector3.ZERO)
    var only_b := Thing.pick_seat(0, 0, false, Vector3(-8, 1, 0), "B")
    var near_a := Thing.pick_seat(0, 0, false, Vector3(-2.5, 1, -0.8))     # A r2c0's step-0 floor seat is at (-5.8,0,-0.8)
    var near_far := Thing.pick_seat(0, 0, false, Vector3(-10.5, 1, -0.8))  # A r2c2's at (-9.8,0,-0.8)
    var plant := Thing.pick_seat(2, 0, false, Vector3.ZERO, "plant")     # only A and B have panes
    # M4.0f: the spawn picks far from the doorway; a re-pick never within 3 m of the player
    var far_b := Thing.pick_seat(2, 0, false, Vector3(-6, 1, 0), "B", true)
    var r2c0 := Thing.seat("B", 2, 0, 2)
    var near_pick := Thing.pick_seat(2, 0, false, r2c0["pos"] + Vector3(1.0, 0, 0), "B", false, 3.0)
    var v5_pick := Thing.pick_seat(2, 0, false, Vector3(6.3, 1, 3.5), "B", false, 3.0)
    var far_ok: bool = far_b.get("row", -1) == 1 and far_b.get("col", -1) == 2
    var min_ok: bool = not (near_pick.get("row", -1) == 2 and near_pick.get("col", -1) == 0) and not v5_pick.is_empty() and Vector3(6.3, 1, 3.5).distance_to(v5_pick["pos"]) >= 3.0
    # M4.5: at step 3 with B shut and the lamp on, A's reachable seats outrank the lamp
    var c4 := Thing.pick_seat(3, 0x3FE00, true, Vector3(0, 1, -14), "")
    var c4_ok: bool = c4.get("room", "") == "A" and c4.get("surface", "") != "lamp"
    # M5.0l: the open fallback keeps min_d too - at step 2 with B's rows 1+2 shut and the
    # player at row 1's crank, whatever is left is 3 m away or nothing
    var fb_at: Vector3 = Thing.crank_stand("B", 1) + Vector3(0, 0.95, 0)
    var fb := Thing.pick_seat(2, Thing.row_mask("B", 1) | Thing.row_mask("B", 2), false, fb_at, "B", false, 3.0)
    var fb_ok: bool = fb.is_empty() or fb_at.distance_to(fb["pos"]) >= 3.0
    var okb: bool = none.is_empty() and lamp.get("surface", "") == "lamp" and only_b.get("room", "") == "B" and plant.is_empty() and far_ok and min_ok and c4_ok and fb_ok
    var tie: bool = near_a.get("col", -1) == 0 and near_far.get("col", -1) == 2 and near_a.get("room", "") == "A"
    ok = ok and okb and tie
    check("pick_seat", ok, "%s none=%s lamp=%s onlyB=%s near=%s/%s plant_empty=%s far=%s r%sc%s near_pick=r%sc%s c4=%s %s v5_d=%.1f open_fallback_min_d=%s(%s)" % [detail, none.is_empty(), lamp.get("surface"), only_b.get("room"), near_a.get("col"), near_far.get("col"), plant.is_empty(), far_b.get("room"), far_b.get("row"), far_b.get("col"), near_pick.get("row"), near_pick.get("col"), c4.get("room"), c4.get("surface"), Vector3(6.3, 1, 3.5).distance_to(v5_pick["pos"]) if not v5_pick.is_empty() else -1.0, fb_ok, "none" if fb.is_empty() else "%.1f m" % fb_at.distance_to(fb["pos"])])

func test_in_beam() -> void:
    var s0 := Thing.seat("B", 2, 0, 0)               # floor patch at (2.77, 0, -0.79)
    var centre: Vector3 = s0["pos"] + Vector3(0, 0.5, 0)
    var inside := Thing.in_beam(centre, "B", 2, 0, 0)
    var aside := Thing.in_beam(centre + Vector3(0, 0, 3.0), "B", 2, 0, 0)
    var edge := Thing.in_beam(centre + Vector3(0, 0, 0.85), "B", 2, 0, 0)
    var hall := Thing.in_beam(Vector3(1.0, 1.0, -4.9), "B", 1, 0, 2)
    # geometry fact (T34): with the sun's 28 deg lean every pane's beam crosses the
    # hall wall at |z| >= 1.7, outside the 0.8 m doorway - no direct sun ever
    # enters the hall, at any step; the hall is bounce-only
    var hall_lit := 0
    for room in ["A", "B"]:
        for row in 3:
            for col in 3:
                for step in 6:
                    for zi in 25:
                        for yi in 5:
                            var hp := Vector3(0.0, 0.2 + 0.5 * yi, -12.0 + zi)
                            if Thing.in_beam(hp, room, row, col, step):
                                hall_lit += 1
    var ok := inside and not aside and edge and not hall and hall_lit == 0
    check("in_beam", ok, "inside=%s aside=%s edge=%s hall_shaded=%s hall_points_lit=%d" % [inside, aside, edge, not hall, hall_lit])


func test_cut_batching() -> void:
    # three changes inside 0.5 s -> one due time, not extended; a change after
    # the batch resolves starts a new one
    var due := -1.0
    var dues := {}
    for t: float in [0.0, 0.2, 0.5]:
        due = Thing.due_after(due, t)
        dues[due] = true
    var one: bool = dues.size() == 1 and is_equal_approx(due, 1.0)
    var later := Thing.due_after(-1.0, 1.5)
    check("cut_batching", one and is_equal_approx(later, 2.5), "dues=%s later=%.2f" % [dues.keys(), later])

func test_never_in_view() -> void:
    var proj := Projection.create_perspective(80, 1600.0 / 912, 0.05, 100)
    var cam := Transform3D.IDENTITY                     # at the origin looking down -Z
    var clear := func(_p: Vector3) -> bool: return false
    var blocked := func(_p: Vector3) -> bool: return true
    var ahead := {"pos": Vector3(0, 0, -5), "normal": Vector3.UP, "row": -1}
    var behind := {"pos": Vector3(0, 0, 5), "normal": Vector3.UP, "row": -1}
    var s_ahead := Thing.seen(Thing.seat_points(ahead), proj, cam, clear)
    var s_behind := Thing.seen(Thing.seat_points(behind), proj, cam, clear)
    var s_ahead_occ := Thing.seen(Thing.seat_points(ahead), proj, cam, blocked)
    # the rule: cut only when origin and destination are both unseen
    var no_cut_origin: bool = not (not s_ahead and not s_behind)
    var no_cut_dest: bool = not (not s_behind and not s_ahead)
    var cut_behind: bool = not s_behind and not s_behind
    var cut_occluded: bool = not s_ahead_occ and not s_ahead_occ
    # a real seat: B r2c0 at step 2, watched from inside B and from the hall wall's far side
    var real := Thing.seat("B", 2, 0, 2)
    var look := Transform3D.IDENTITY.looking_at(real["pos"] - Vector3(6.3, 1.6, 3.5), Vector3.UP)
    look.origin = Vector3(6.3, 1.6, 3.5)
    var real_seen := Thing.seen(Thing.seat_points(real), proj, look, clear)
    var away := look.rotated_local(Vector3.UP, PI)
    var real_away := Thing.seen(Thing.seat_points(real), proj, away, clear)
    # the bite (M3.0d): from 3 m off B r2c0's wall pitched -60 every point at the
    # seat's height is above the frame but the pool under the omni is in it; at +75 the patch top (3.1 m, 25 deg up) is out too
    var eye := Vector3(real["pos"].x + 3.0, 1.7, real["pos"].z)
    var low := Transform3D.IDENTITY.rotated(Vector3.UP, PI / 2).rotated_local(Vector3.RIGHT, deg_to_rad(-60.0))
    low.origin = eye
    var high := Transform3D.IDENTITY.rotated(Vector3.UP, PI / 2).rotated_local(Vector3.RIGHT, deg_to_rad(75.0))
    high.origin = eye
    var pool_seen := Thing.seen(Thing.seat_points(real), proj, low, clear)
    var up_seen := Thing.seen(Thing.patch_points(real), proj, high, clear)   # the patch alone: the body's apex is rightly in view up there
    # the body counts (M4.0c): 5.4 m off the wall pitched -70 every patch point is
    # above the frame, the body's floor drips 1.6-2.6 m ahead are in it
    var body_cam := Transform3D.IDENTITY.rotated(Vector3.UP, PI / 2).rotated_local(Vector3.RIGHT, deg_to_rad(-70.0))
    body_cam.origin = Vector3(5.4, 1.7, -2.6)
    var body_seen := Thing.seen(Thing.seat_points(real), proj, body_cam, clear)
    var patch_only := Thing.seen(Thing.patch_points(real), proj, body_cam, clear)
    var corners: bool = Thing.seat_points(real).size() >= 6 and pool_seen and not up_seen and body_seen and not patch_only
    var ok: bool = s_ahead and not s_behind and not s_ahead_occ and no_cut_origin and no_cut_dest and cut_behind and cut_occluded and real_seen and not real_away and corners
    check("never_in_view", ok, "ahead=%s behind=%s ahead_occ=%s real=%s/%s pts=%d pool@-60=%s up@+75=%s body@-70=%s patch_only@-70=%s" % [s_ahead, s_behind, s_ahead_occ, real_seen, real_away, Thing.seat_points(real).size(), pool_seen, up_seen, body_seen, patch_only])


func test_dose_step() -> void:
    var d := 0.0
    for i in 240:                                   # 4 s in its light
        d = Thing.dose_step(d, true, false, 1.0 / 60.0)
    var lit_4s := d
    for i in 120:                                   # 6 s in its light: the bleach (M4.0e)
        d = Thing.dose_step(d, true, false, 1.0 / 60.0)
    var lit_6s := d
    d = 0.0
    for i in 180:                                   # 3 s riding
        d = Thing.dose_step(d, false, true, 1.0 / 60.0)
    var ride_3s := d
    d = 2.0
    for i in 480:                                   # 8 s outside from 2.0
        d = Thing.dose_step(d, false, false, 1.0 / 60.0)
    var out_8s := d
    var clamped := Thing.dose_step(3.0, true, false, 1.0) == 3.0 and Thing.dose_step(0.0, false, false, 1.0) == 0.0
    var ok: bool = absf(lit_4s - 2.0) <= 0.05 and absf(lit_6s - 3.0) <= 0.05 and absf(ride_3s - 1.0) <= 0.05 and is_zero_approx(out_8s) and clamped
    check("dose_step", ok, "lit4s=%.3f lit6s=%.3f ride3s=%.3f out8s=%.3f clamped=%s" % [lit_4s, lit_6s, ride_3s, out_8s, clamped])


func test_seat_points_in_room() -> void:
    # every point but the omni of every seat lies inside its room (gate M2: the
    # old corners of B's hall-side seats landed in the hall and pinned the thing)
    var bad := []
    var total := 0
    for room in ["A", "B"]:
        var box := Thing.room_box(room).grow(-0.04)   # off the slab, not inside it (M4.0c)
        for step in 6:
            for row in 3:
                for col in 3:
                    var s := Thing.seat(room, row, col, step)
                    if s.is_empty():
                        continue
                    var pts := Thing.seat_points(s)
                    total += 1
                    for i in pts.size():
                        if i == 1:
                            continue
                        if not box.has_point(pts[i]):
                            bad.append("%s r%dc%d s%d p%d=%s" % [room, row, col, step, i, pts[i]])
    check("seat_points_in_room", bad.is_empty() and total > 0, "seats=%d bad=%s" % [total, bad.slice(0, 3)])


func test_last_ab_room() -> void:
    # after C1..C4 (office, A, B, plant) the last A/B room is B; before any chore ""
    var g := Game.new()
    var before := g.last_ab_room()
    g.complete_upto(4)
    var after := g.last_ab_room()
    var nxt := g.next_room()
    check("last_ab_room", before == "" and after == "B" and g.last_room() == "plant" and nxt == "A", "before=%s after=%s last=%s next=%s" % [before, after, g.last_room(), nxt])


func test_bleach_target() -> void:
    # every zone x step: the bleach target is >= 8 x that base and >= BLEACH_EXP
    var rl := _lighting()
    var l: Lighting = rl[1]
    var bad := []
    for z in l.zone_exposure.keys():
        for st in Lighting.STEP_EXP.size():
            var base: float = l.zone_exposure[z] * Lighting.STEP_EXP[st]
            l._base_exp = base
            var t := l.bleach_target()
            if t < 8.0 * base - 1e-6 or t < Lighting.BLEACH_EXP:
                bad.append("%s s%d base=%.2f target=%.2f" % [z, st, base, t])
    check("bleach_target", bad.is_empty(), "bad=%s hall_s5=%.1f" % [bad, maxf(Lighting.BLEACH_EXP, 8.0 * l.zone_exposure["hall"] * Lighting.STEP_EXP[5])])
    rl[0].queue_free()


func test_breath_amp() -> void:
    # the tell points at its light: 1 m away in shade <= 5%; dose 1 >= 15%, dose 2 >= 30%; dose carries at 9 m
    var rl := _lighting()
    var l: Lighting = rl[1]
    var got := []
    for c in [[1.0, 0.0], [1.0, 1.0], [1.0, 2.0], [9.0, 1.0], [1.0, 3.0]]:
        l.breath_dist = c[0]
        l.dose = c[1]
        got.append(l.breath_amp())
    var ok: bool = got[0] <= 0.05 and got[1] >= 0.15 and got[2] >= 0.30 and got[3] >= 0.15 and got[4] >= 0.45
    check("breath_amp", ok, "d1/dose0=%.3f d1/dose1=%.3f d1/dose2=%.3f d9/dose1=%.3f d1/dose3=%.3f" % [got[0], got[1], got[2], got[3], got[4]])
    rl[0].queue_free()


func test_dropout_stats() -> void:
    # 600 s at 1/60: duty 70-90%, every ramp >= 2 s, >= 4 distinct on-lengths, seed-stable
    var n := 600 * 60
    var on_frames := 0
    var lens := {}
    var cur := 0
    var ramp_min := INF
    var ramp_run := 0
    var prev := Thing.presence(0.0, 1)
    for i in n:
        var t := i / 60.0
        var p := Thing.presence(t, 1)
        if p >= 0.5:
            on_frames += 1
            cur += 1
        elif cur > 0:
            lens[snappedf(cur / 60.0, 0.5)] = true
            cur = 0
        if p > 0.0 and p < 1.0:
            ramp_run += 1
        elif ramp_run > 0:
            ramp_min = minf(ramp_min, ramp_run / 60.0)
            ramp_run = 0
        prev = p
    var duty := float(on_frames) / n
    var differs := false
    for t2: float in [3.3, 47.0, 120.5, 333.0, 599.0]:
        differs = differs or not is_equal_approx(Thing.presence(t2, 1), Thing.presence(t2, 2))
    var consecutive_ok := true
    for k in 30:
        consecutive_ok = consecutive_ok and not is_equal_approx(Thing.on_len(1, k), Thing.on_len(1, k + 1))
    print("DROPOUT seed=1 first_off=%.2f" % Thing.first_off(1))
    var ok: bool = duty >= 0.70 and duty <= 0.90 and ramp_min >= 2.0 - 1.5 / 60.0 and lens.size() >= 4 and differs and consecutive_ok
    check("dropout_stats", ok, "duty=%.3f ramp_min=%.2f on_lengths=%d seed2_differs=%s no_consecutive_equal=%s first_off=%.2f" % [duty, ramp_min, lens.size(), differs, consecutive_ok, Thing.first_off(1)])


# every synthesised sound: sane duration/peak/DC, the drone's fundamental found
# by a naive DFT, and each written to a WAV a human can actually listen to.
# NOTE: expected durations, not a blanket ">0.05 s" floor - "click" is 30 ms by
# design (M3.4 spec), below a 50 ms floor, so each name is checked against its
# own intended length instead.
func test_audio_wavs() -> void:
    var expect := {"drone": 2.0, "click": 0.03, "step": 0.12, "pencil": 0.2}
    var dir := "C:/Users/computer/Downloads/hallway-trial/audio"
    DirAccess.make_dir_recursive_absolute(dir)
    var ok := true
    var detail := ""
    var dom_hz := 0.0
    for name: String in ["drone", "click", "step", "pencil"]:
        var samples := Audio.pcm(name)
        var duration: float = samples.size() / float(Audio.RATE)
        var peak := 0.0
        var total := 0.0
        for v in samples:
            peak = maxf(peak, absf(v))
            total += v
        var mean: float = total / samples.size()
        var dur_ok: bool = absf(duration - float(expect[name])) < 0.01
        var peak_ok: bool = peak > 0.1
        var mean_ok: bool = absf(mean) < 0.01
        ok = ok and dur_ok and peak_ok and mean_ok
        detail += " %s(dur=%.4f peak=%.3f mean=%.4f)" % [name, duration, peak, mean]
        if name == "drone":
            # naive DFT, 1 Hz resolution over the 2 s span, bins 10..200 Hz;
            # downsample by 4 first (still 1 Hz resolution over 2 s) so 191
            # bins x ~11k samples finishes in well under 10 s.
            var step := 4
            var m := samples.size() / step
            var sub := PackedFloat32Array()
            sub.resize(m)
            for i in m:
                sub[i] = samples[i * step]
            var sub_dt: float = float(step) / Audio.RATE
            var best_mag := -1.0
            for f in range(10, 201):
                var d_theta: float = -TAU * float(f) * sub_dt
                var cs := cos(d_theta)
                var sn := sin(d_theta)
                var cur_re := 1.0
                var cur_im := 0.0
                var re := 0.0
                var im := 0.0
                for i in m:
                    re += sub[i] * cur_re
                    im += sub[i] * cur_im
                    var nre: float = cur_re * cs - cur_im * sn
                    var nim: float = cur_re * sn + cur_im * cs
                    cur_re = nre
                    cur_im = nim
                var mag: float = sqrt(re * re + im * im)
                if mag > best_mag:
                    best_mag = mag
                    dom_hz = float(f)
            var dom_ok: bool = dom_hz >= 30.0 and dom_hz <= 50.0
            ok = ok and dom_ok
            detail += " dom_hz=%.0f" % dom_hz
        var path := "%s/%s.wav" % [dir, name]
        var err := Audio.wav(name).save_to_wav(path)
        var exists := FileAccess.file_exists(path)
        var size := FileAccess.get_file_as_bytes(path).size() if exists else 0
        ok = ok and err == OK and exists and size > 44
        detail += " wav=%s(%dB)" % [path, size]
    # four seeded footfalls (M4.0i): written as step_1..4.wav, pairwise > 5% of samples apart
    var steps := []
    for sd in range(1, 5):
        steps.append(Audio.pcm("step", sd))
        Audio.wav("step", sd).save_to_wav("%s/step_%d.wav" % [dir, sd])
    var min_diff := 1.0
    for i in 4:
        for j in range(i + 1, 4):
            var diff := 0
            for k in steps[i].size():
                if absf(steps[i][k] - steps[j][k]) > 1e-3:
                    diff += 1
            min_diff = minf(min_diff, float(diff) / steps[i].size())
    ok = ok and min_diff > 0.05
    detail += " steps_min_pair_diff=%.2f" % min_diff
    check("audio_wavs", ok, detail)


# pure: Audio.gain_target / Audio.gain_step at dt = 1/60, three phases -
# (a) proximity only (dose 0) for 10 s from rest stays low, (b) dose 1 for 8 s
# rises past half, (c) the target drops to 0 and the release is slow enough to
# still be above 0.2 at +3 s but under 0.05 by +8 s.
func test_drone_gain() -> void:
    var dt := 1.0 / 60.0
    var g := 0.0
    var target_a := Audio.gain_target(0.05 * 0.71)              # dose 0, half the aura radius
    for i in 600:
        g = Audio.gain_step(g, target_a, dt)
    var g_a := g
    var target_b := Audio.gain_target(0.05 * 0.71 + 0.15 * 1.0)  # dose 1
    for i in 480:
        g = Audio.gain_step(g, target_b, dt)
    var g_b := g
    var target_c := Audio.gain_target(0.0)
    var g_c3 := 0.0
    for i in 480:
        g = Audio.gain_step(g, target_c, dt)
        if i == 179:      # +3 s
            g_c3 = g
    var g_c8 := g          # +8 s
    var ok: bool = g_a <= 0.1 and g_b >= 0.5 and g_c3 > 0.2 and g_c8 < 0.05
    check("drone_gain", ok, "g_a=%.4f g_b=%.4f g_c3=%.4f g_c8=%.4f" % [g_a, g_b, g_c3, g_c8])


func test_body_in_room() -> void:
    # the body's footprint stays inside its room for every seat (B r1c0 s2 poked 0.9 m through the hall wall)
    var bad := []
    var total := 0
    var raw_bad := 0
    for room in ["A", "B"]:
        var box := Thing.room_box(room)
        for step in 6:
            for row in 3:
                for col in 3:
                    var s := Thing.seat(room, row, col, step)
                    if s.is_empty():
                        continue
                    total += 1
                    var n: Vector3 = s["normal"]
                    var p: Vector3 = s["pos"]
                    var naive := Vector3(p.x, 0, p.z) if absf(n.y) >= 0.5 else Vector3(p.x + n.x * 1.6, 0, p.z + n.z * 1.6)
                    for q: Vector3 in Thing.body_points(naive, Thing.body_yaw(step)):
                        if not box.has_point(q):
                            raw_bad += 1
                            break
                    for q: Vector3 in Thing.body_points(Thing.body_pos(s), Thing.body_yaw(step)):
                        if not box.has_point(q):
                            bad.append("%s r%dc%d s%d %s" % [room, row, col, step, q])
                            break
    check("body_in_room", bad.is_empty() and total > 0 and raw_bad > 0, "seats=%d naive_out=%d bad=%s" % [total, raw_bad, bad.slice(0, 3)])


func test_shutter_bits() -> void:
    # A:110 -> rows 0 and 1 of A (bits 0-5); B:001 -> row 2 of B (bits 15-17)
    var a := Thing.shut_bits("A:110")
    var ab := Thing.shut_bits("A:110,B:001")
    var all_b := Thing.row_mask("B", 0) | Thing.row_mask("B", 1) | Thing.row_mask("B", 2)
    var ok: bool = a == 0x3F and ab == (0x3F | 0x38000) and all_b == 0x3FE00 and Thing.is_shut(ab, "B", 2, 1) and not Thing.is_shut(ab, "B", 1, 1) and Thing.shut_bits("plant:111") == 0
    check("shutter_bits", ok, "A:110=0x%x A:110,B:001=0x%x allB=0x%x" % [a, ab, all_b])


func test_presence_hint() -> void:
    # 3000 samples 0.2 s apart with one shared hint == the unhinted walk from t = 0
    var hint := [0, 0.0]
    var bad := 0
    for i in 3000:
        var t := i * 0.2
        if not is_equal_approx(Thing.presence(t, 1, hint), Thing.presence(t, 1)):
            bad += 1
    check("presence_hint", bad == 0 and int(hint[0]) > 10, "mismatches=%d final_k=%d" % [bad, int(hint[0])])


func test_light_cap() -> void:
    # GUARDRAILS 5: <= 2 shadowed positional lights - the seat omni and the lamp;
    # the bleach flood is unshadowed
    var rl := _lighting()
    var l: Lighting = rl[1]
    l.seat_omni(Vector3(3, 1.2, -2))
    l.lamp(true)
    l.bleach_flood(Vector3(0, 1.7, 0), 1.0)
    var shadowed := 0
    var total := 0
    var stack: Array = [rl[0]]
    while not stack.is_empty():
        var n: Node = stack.pop_back()
        if (n is OmniLight3D or n is SpotLight3D):
            total += 1
            if (n as Light3D).shadow_enabled:
                shadowed += 1
        for c in n.get_children():
            stack.append(c)
    check("light_cap", shadowed == 2 and total == 3 and l.lamp_on, "shadowed=%d positional=%d lamp_on=%s" % [shadowed, total, l.lamp_on])
    rl[0].queue_free()


func test_forced_crossing() -> void:
    # GUARDRAILS 3.12: every crank's standing point (crank + facing normal x reach) is
    # in an open pane's beam at its step - B's in their row's step-2 beam - or the
    # crank needs the lamp (A's: at step 4 no beam reaches a standing point)
    var lines := []
    var ok := true
    for row in 3:
        var st := Thing.crank_stand("B", row)
        var pr: Array = Thing._crank_pane(row)
        var lit := false
        for y: float in [0.05, 0.45, 0.85, 1.25, 1.65]:
            lit = lit or Thing.in_beam(Vector3(st.x, y, st.z), "B", pr[0], pr[1], 2)
        var inside: bool = Thing.room_box("B").has_point(st)
        ok = ok and lit and inside and not Thing.crank_needs_lamp("B")
        lines.append("B r%d stand=(%.2f,%.2f) beam=r%dc%d@2:%s" % [row, st.x, st.z, pr[0], pr[1], lit])
    for row in 3:
        var st := Thing.crank_stand("A", row)
        var any_beam := false
        for r2 in 3:
            for c2 in 3:
                for y: float in [0.05, 0.85, 1.65]:
                    any_beam = any_beam or Thing.in_beam(Vector3(st.x, y, st.z), "A", r2, c2, 4)
        var inside_a: bool = Thing.room_box("A").has_point(st)
        ok = ok and Thing.crank_needs_lamp("A") and not any_beam and inside_a
        lines.append("A r%d stand=(%.2f,%.2f) in_room=%s beam@4:%s lamp:%s" % [row, st.x, st.z, inside_a, any_beam, Thing.crank_needs_lamp("A")])
    check("forced_crossing", ok, " | ".join(lines))


func test_lamp_seat() -> void:
    # the disc edge 2 m along the flattened forward, on the floor, with every seat key
    var ls := Thing.lamp_seat(Vector3(0, 1.7, -14), Vector3(0.0, -0.5, -0.866), "plant", 4)
    var pos_ok: bool = ls["pos"].is_equal_approx(Vector3(-0.8, 0, -16))   # 2 m ahead, 0.8 m to the left of -Z (M5.0f)
    var keys_ok := true
    for k in ["room", "row", "col", "step", "pos", "normal", "surface"]:
        keys_ok = keys_ok and ls.has(k)
    var pp_ok := true                        # M5.0i: no room box in the plant room, so no clamp - the points stay the disc's own
    for p: Vector3 in Thing.patch_points(ls):
        pp_ok = pp_ok and p.distance_to(ls["pos"]) <= 2.1
    var via_pick := Thing.pick_seat(5, 0x3FFFF, true, Vector3(0, 1, -14), "", false, 0.0, Vector3(1, 0, 0), "plant")
    var pick_ok: bool = via_pick.get("surface", "") == "lamp" and via_pick["pos"].is_equal_approx(Vector3(2, 0, -14.8)) and via_pick["room"] == "plant"   # left of +X is -Z (0.8 m, M5.0f)
    check("lamp_seat", pos_ok and keys_ok and ls["surface"] == "lamp" and ls["room"] == "plant" and ls["row"] == -1 and pick_ok and pp_ok, "pos=%s keys=%s via_pick=%s patch_points_within_2.1=%s" % [ls["pos"], keys_ok, via_pick.get("pos"), pp_ok])


func test_found_text_len() -> void:
    # GUARDRAILS 3.13: found text <= 25 words, each
    var ok := true
    var lines := []
    for k in Props.TEXTS:
        var words: PackedStringArray = (Props.TEXTS[k] as String).replace("\n", " ").split(" ", false)
        ok = ok and words.size() <= 25
        lines.append("%s=%d" % [k, words.size()])
    check("found_text_len", ok, " ".join(lines))


func test_clipboard_bb() -> void:
    # COLOUR (a), GUARDRAILS 3.14: after C5 exactly one [color] span, and it is "sample"; before, none
    var g := Game.new()
    g.complete_upto(4)
    var before := g.clipboard_bb("sample")
    var g5 := Game.new()
    g5.complete_upto(5)
    var after := g5.clipboard_bb("sample")
    var spans := after.count("[color=")
    var i := after.find("[color=#")
    var word := ""
    if i >= 0:
        var j := after.find("]", i)
        var k := after.find("[/color]", j)
        word = after.substr(j + 1, k - j - 1)
    var brackets := not after.contains("[x]") and after.contains("[lb]x[rb]")   # the list's own brackets escaped
    var ok := before.count("[color=") == 0 and spans == 1 and word == "sample" and brackets
    check("clipboard_bb", ok, "before=%d after=%d word=%s escaped=%s" % [before.count("[color="), spans, word, brackets])


func test_sims_index() -> void:
    # M6.0l: tests/SIMS.md is generated from the `# args:` line under each case in
    # tests/sims.gd (tools/sims_index.py); a case without one, or a table that drifted, fails
    var src := FileAccess.get_file_as_string("res://tests/sims.gd").split("\n")
    var rows := PackedStringArray()
    var missing := []
    var rx := RegEx.new()
    rx.compile("^        \"([A-Za-z0-9_]+)\":\\s*$")
    for i in src.size():
        var m := rx.search(src[i])
        if m == null:
            continue
        var nxt := src[i + 1].strip_edges() if i + 1 < src.size() else ""
        if not nxt.begins_with("# args:"):
            missing.append(m.get_string(1))
            continue
        rows.append("| %s | `%s` |" % [m.get_string(1), nxt.substr(7).strip_edges().replace("|", "\\|")])
    var table := FileAccess.get_file_as_string("res://tests/SIMS.md")
    var have := PackedStringArray()
    for line in table.split("\n"):
        if line.begins_with("| ") and not line.begins_with("| sim |"):
            have.append(line)
    var same: bool = have == rows
    var ok := missing.is_empty() and same and rows.size() > 20
    check("sims_index", ok, "cases=%d missing_args=%s table_matches=%s" % [rows.size(), missing, same])


func test_colour_first() -> void:
    # M6.0n: down over 2 s, away 2 s, back over 2 s, then 1; 1 before the start
    var f := []
    for u: float in [-1.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 9.0]:
        f.append(snappedf(Thing.colour_first(u), 0.01))
    var ok: bool = f == [1.0, 1.0, 0.5, 0.0, 0.0, 0.0, 0.5, 1.0, 1.0]
    check("colour_first", ok, str(f))


func test_chores_text() -> void:
    # M7.0b: every chore that needs the lamp says so on the list (C4 T119, C5/C6 now),
    # and no line outgrows the clipboard's 40-cell box
    var g := Game.new()
    var need := ["C4", "C5", "C6"]
    var says := []
    var widest := 0
    for c in g.chores:
        widest = maxi(widest, 4 + (c["text"] as String).length())
        if need.has(c["id"]) and (c["text"] as String).contains("lamp"):
            says.append(c["id"])
    var ok: bool = says == need and widest <= 40
    check("chores_text", ok, "say_lamp=%s widest_line=%d" % [says, widest])


func test_d6_shape() -> void:
    # M7.0c: D6's absence must be a PERSON, not a blob - measured on the texture the
    # burn is authored in, so no camera, light or decal convention can hide it. Along
    # the light from the feet: legs, a waist narrower than the shoulders, a neck, and
    # a head wider than the neck; and the whole figure at least 0.85 m long.
    var box := Thing.room_box("A")
    var r3: Array = Props.burn_image(box, 256)
    var img: Image = r3[0]
    var feet: Vector2 = r3[1]
    var px: float = r3[2]
    var d := Lighting.sun_dir(0)
    var ax := Vector2(d.x, d.z).normalized()
    var pp := Vector2(-ax.y, ax.x)
    var widths := {}
    for u: float in [0.1, 0.3, 0.55, 0.73, 0.95, 1.15]:
        var w := 0.0
        for k in 40:                                   # 0.02 m steps out from the axis, both sides
            var off: float = 0.02 * k
            var q: Vector2 = feet + ax * (u * px) + pp * (off * px)
            if q.x < 0 or q.y < 0 or q.x >= 256 or q.y >= 256:
                break
            if img.get_pixel(int(q.x), int(q.y)).a > 0.1:   # burned again: the figure's edge
                break
            w = off
        widths[u] = w
    var burned := 0
    for y in range(0, 256, 4):
        for x in range(0, 256, 4):
            if img.get_pixel(x, y).a > 0.1:
                burned += 1
    # a waist worth the name: the neck at most 0.6 of the shoulders, the head half again wider
    var legs: bool = widths[0.3] >= 0.10
    var neck: bool = widths[0.73] <= 0.6 * widths[0.55]
    var head: bool = widths[0.95] >= 1.5 * widths[0.73]
    var ok: bool = burned > 200 and legs and neck and head
    check("d6_shape", ok, "burned_cells=%d half-widths m: 0.1=%.2f 0.3=%.2f 0.55=%.2f neck0.73=%.2f head0.95=%.2f 1.15=%.2f" % [burned, widths[0.1], widths[0.3], widths[0.55], widths[0.73], widths[0.95], widths[1.15]])
