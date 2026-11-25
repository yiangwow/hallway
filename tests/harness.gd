extends RefCounted
# The screenshot/sim harness (M3.0a/M3.0c): stateless, static, takes main (`m`,
# untyped on purpose). Harness STATE (harness_t0, harness_frames, watchdog_frames,
# captured, ab_force, walk_until, etc.) stays on main.gd; these read/write it via
# `m.xxx`. tools/shot.sh -> main.gd::_maybe_screenshot -> Harness.shoot; tools/sim.sh
# -> main.gd::_run_sim -> Harness.run_sim; both print through Harness.lines (seat_line
# + numbers_line, same order the SHOT/SIM lines have always used).
const Sims := preload("res://tests/sims.gd")

# Harness (REF Shot): --shot=NAME [--ascii=0|1 --pos=x,y,z --yaw=deg --pitch=deg --t=SEC
#   --thing=x,y,z --res=WxH --ab=thing --seed=N --sun=N --shut=.. --lamp=1 --chores=N]
# Settle 120 frames (SDFGI, exposure), apply the scene args, zero the fixed clock,
# run to --t, capture. --ab=thing captures NAME_off.png (thing_on 0) then
# NAME_on.png (thing_on 1) on consecutive frames. Writes shots/ (user:// in the exe), quits.
# --bench=1 (M6.0k, was M6.1): after the settle, 120 frames' wall-clock deltas ->
# `BENCH mean=X 95th=Y ms over 120 frames`, then quit(0); nothing is captured
static func bench(m) -> void:
    # M7.0e: measure the GAME, not the monitor. Vsync and the frame cap held the old
    # number at exactly the 60 Hz beat (T113's 16.68 ms mean was the cap), which says
    # nothing about headroom on a friend's machine
    var vs := DisplayServer.window_get_vsync_mode()
    var cap := Engine.max_fps
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    for i in int(m.args.get("settle", "360")):
        await m.get_tree().process_frame
    var ts := []
    var prev := Time.get_ticks_usec()
    for i in 120:
        await m.get_tree().process_frame
        var now := Time.get_ticks_usec()
        ts.append((now - prev) / 1000.0)
        prev = now
    ts.sort()
    var mean := 0.0
    for v: float in ts:
        mean += v
    mean /= ts.size()
    print("BENCH mean=%.2f 95th=%.2f ms over 120 frames (vsync off, uncapped)" % [mean, ts[int(0.95 * (ts.size() - 1))]])
    DisplayServer.window_set_vsync_mode(vs)
    Engine.max_fps = cap
    m.get_tree().quit(0)

static func shoot(m) -> void:
    if m.args.has("bench"):
        await bench(m)
        return
    # camera args first, so the settle (SDFGI cascades re-centre on the camera,
    # exposure snaps) happens at the final viewpoint. --sun and --chores apply
    # BEFORE the settle (a converged frame at that step); --step_at, --lamp and
    # --press apply AFTER it at t=0, so a light change can be watched arriving
    if m.args.has("ascii"):
        m.set_ascii(m.args["ascii"] == "1")
    if m.args.has("pos"):
        var p := (m.args["pos"] as String).split(",")
        m.player.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
    if m.args.has("yaw"):
        m.player.look_at_yaw(float(m.args["yaw"]))
    if m.args.has("pitch"):
        m.player.look_at_pitch(float(m.args["pitch"]))
    if m.args.has("sun"):
        m.lighting.sun_step(int(m.args["sun"]))       # before the settle: --t=0 is the converged step
    if m.harness:
        m.lighting.set_zone(Lighting.zone_at(m.player.position), true)   # no ramp under the harness
        m.clock_fixed = true
        m.clock_running = false
        var settle := int(m.args.get("settle", "360"))   # frames for SDFGI/fog/exposure to converge at the viewpoint (measured M1.0a: 120 -> 4.4% drift over 3 s, 240 -> 0.32%, 400 -> 0.01%)
        for i in settle:
            await m.get_tree().process_frame
    # light args that must be seen changing (bounce lag) and held inputs apply at t=0
    if m.args.has("step_at"):
        m.lighting.sun_step(int(m.args["step_at"]))
    if m.args.has("hue"):
        m.lighting.hue_lamp = m.args["hue"] == "1"     # M5.0g: the lamp takes the REF hue, harness only - the chroma pipe's probe
    if m.args.has("lamp"):
        var l: String = m.args["lamp"]
        if l in ["desk", "plant", "held"]:
            m.lamp_where = l                         # where it hangs (M5.0k), unlit
            m.lighting.lamp(false, m.player.cam)
        else:
            m.lamp_where = "held"                    # the harness carries it; 1 = lit
            m.lighting.lamp(l == "1", m.player.cam)
        m._sync_prompts()
    if m.args.has("press"):
        Input.action_press(m.args["press"])
    if m.args.has("walk"):
        m.walk_until = float(m.args["walk"])
    if m.args.has("sim"):
        m.clock_t = 0.0
        m.clock_running = true
        await run_sim(m, m.args["sim"])
        return
    if not m.args.has("shot"):
        return
    m.clock_t = 0.0
    m.clock_running = true
    var target := float(m.args.get("t", "0"))
    for i in 2:
        await m.get_tree().process_frame
    while m.clock_t < target:
        await m.get_tree().process_frame
    var name: String = m.args["shot"]
    if m.args.has("seq"):
        # --seq=N:DT (M3.0b): N (<= 8) captures DT s apart from --t on, NAME_0..N-1,
        # one SHOT line each; shot.sh tiles them into NAME_seq.png
        var nd := (m.args["seq"] as String).split(":")
        var n := clampi(int(nd[0]), 1, 8)
        var dt_s := float(nd[1]) if nd.size() > 1 else 0.5
        for i in n:
            capture(m, "%s_%d" % [name, i])
            if i < n - 1:
                var until: float = m.clock_t + dt_s
                while m.clock_t < until:
                    await m.get_tree().process_frame
        m.get_tree().quit()
        return
    var ab: String = m.args.get("ab", "")
    if ab != "":
        m.clock_running = false        # A/B pairs on a frozen clock: no breath, no swirl, no sag between the two frames (T55)
    if ab == "thing":
        m.ab_force = 0.0
        await m.get_tree().process_frame
        await m.get_tree().process_frame
        capture(m, name + "_off")
        m.ab_force = 1.0
        await m.get_tree().process_frame
        await m.get_tree().process_frame
        capture(m, name + "_on")
    elif ab == "bite" and m.lighting.seat_light != null:
        # the DIM off then on (M3.0k): the omni's energy, nothing else, on consecutive captures
        var e: float = m.lighting.seat_light.light_energy
        m.lighting.seat_light.light_energy = 0.0
        await m.get_tree().process_frame
        await m.get_tree().process_frame
        capture(m, name + "_off")
        m.lighting.seat_light.light_energy = e
        await m.get_tree().process_frame
        await m.get_tree().process_frame
        capture(m, name + "_on")
    elif ab == "body" and m.creature != null:
        m.ab_force = 0.0                # the aura off for both: the pair measures the body alone
        m.creature.visible = false
        await m.get_tree().process_frame
        await m.get_tree().process_frame
        capture(m, name + "_off")
        m.creature.visible = true
        await m.get_tree().process_frame
        await m.get_tree().process_frame
        capture(m, name + "_on")
    else:
        capture(m, name)
    m.get_tree().quit()

# In-engine simulations: `tools/sim.sh NAME`; the cases live in tests/sims.gd
# (M3.0c) and return [ok, detail]; this prints the one `SIM NAME PASS|FAIL` line
static func run_sim(m, name: String) -> void:
    # T119: a sim's clock is fixed-step, as REF promises, AND its frames are capped
    # at 60 so the physics ticks the sims' walking depends on keep pace with it.
    # Without this a fast machine ran 155 fps on real dt: every frame-counted hold
    # was worth a third of its seconds and the take/crank sims failed at random.
    m.clock_fixed = true
    Engine.max_fps = 60
    var r: Array = await Sims.run(m, name)
    var ok: bool = r[0]
    m.captured = true
    print("SIM %s %s %s step=%d pos=%.2f,%.2f,%.2f %s" % [name, "PASS" if ok else "FAIL", r[1], m.lighting.step, m.player.position.x, m.player.position.y, m.player.position.z, lines(m)])
    m.get_tree().quit(0 if ok else 1)

static func capture(m, name: String) -> void:
    var img: Image = m.get_viewport().get_texture().get_image()
    # whole 8x16 cells only: the window is 1600x923 on Windows and the sliver
    # row would be a clipped line of glyph tops that cells.py silently drops
    var w := img.get_width() - img.get_width() % 8
    var h := img.get_height() - img.get_height() % 16
    if w != img.get_width() or h != img.get_height():
        img = img.get_region(Rect2i(0, 0, w, h))
    # res:// is read-only inside an exported build, so fall back to user://
    var path := "res://shots/%s.png" % name
    if not OS.has_feature("editor"):
        path = "user://%s.png" % name
    var err := img.save_png(path)
    m.captured = true
    var pp: Vector3 = m.player.position
    print("SHOT %s -> %s (%dx%d) t=%.3f step=%d exp=%.3f pos=%.2f,%.2f,%.2f %s at %s" % [path, error_string(err), img.get_width(), img.get_height(), m.clock_t, m.lighting.step, m.lighting.ca.exposure_multiplier, pp.x, pp.y, pp.z, lines(m), ProjectSettings.globalize_path(path)])

# the text appended to SHOT/SIM lines: seat_line + " " + numbers_line, the exact
# combination the two printers above have always used
static func lines(m) -> String:
    return "%s %s" % [seat_line(m), numbers_line(m)]

# `aura=px,py,r,on wall=SEC fps=N` for SHOT/SIM lines (M3.0a)
static func numbers_line(m) -> String:
    var wall: float = (Time.get_ticks_msec() - m.harness_t0) / 1000.0
    var fps: float = m.harness_frames / maxf(wall, 0.001)
    var lamp_s := "%s,%s" % [m.lamp_where, "on" if (m.lighting != null and m.lighting.lamp_on) else "off"]
    return "aura=%.0f,%.0f,%.0f,%.2f %s lamp=%s shut=0x%x wall=%.1f fps=%.0f" % [m.aura_px.x, m.aura_px.y, m.aura_r, m.aura_on, patch_line(m), lamp_s, m.lighting.shut if m.lighting != null else 0, wall, fps]

# `patch=x0,y0,x1,y1` (px): the seat's patch points (centre, corners, rim; not the
# omni or the pool) projected to the screen - the box the bite must stay inside
static func patch_line(m) -> String:
    if m.seat.is_empty() or m.riding() or m.player == null or m.player.cam == null:
        return "patch=-"                          # a lamp seat has no patch box (M5.0i)
    var cam: Camera3D = m.player.cam
    var lo := Vector2(INF, INF)
    var hi := Vector2(-INF, -INF)
    var pts := Thing.patch_points(m.seat, 0.0)    # rim 0: the patch itself, no body
    var wall: bool = absf(m.seat["normal"].y) < 0.5
    for i in pts.size():
        if i == 1 or (wall and i == pts.size() - 1):
            continue                              # the omni, and a wall seat's pool point
        var p: Vector3 = pts[i]
        if cam.is_position_behind(p):
            continue
        var sp := cam.unproject_position(p)
        lo = Vector2(minf(lo.x, sp.x), minf(lo.y, sp.y))
        hi = Vector2(maxf(hi.x, sp.x), maxf(hi.y, sp.y))
    if lo.x == INF:
        return "patch=-"
    return "patch=%.0f,%.0f,%.0f,%.0f" % [lo.x, lo.y, hi.x, hi.y]

static func seat_line(m) -> String:
    if m.seat.is_empty():
        return "SEAT none"
    return "SEAT %s r%dc%d %s %.2f,%.2f,%.2f" % [m.seat["room"], m.seat["row"], m.seat["col"], m.seat["surface"], m.seat["pos"].x, m.seat["pos"].y, m.seat["pos"].z]

# a plain interactable box for sims and shots
static func test_box(m, at: Vector3) -> Interactable:
    var b := Interactable.new()
    b.prompt = "press"
    b.hold_s = 1.0
    var mi := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = Vector3(0.4, 0.4, 0.4)
    mi.mesh = bm
    mi.material_override = m.mat_dark
    b.add_child(mi)
    var cs := CollisionShape3D.new()
    var bs := BoxShape3D.new()
    bs.size = Vector3(0.4, 0.4, 0.4)
    cs.shape = bs
    b.add_child(cs)
    b.position = at
    m.add_child(b)
    return b

# harness watchdog (M3.0a): counts frames, not seconds, so a slow but healthy run
# is never killed: settle + 60 x (t + 30) frames without a capture = quit(2).
# Returns true when it fired (the caller's _process should return without
# doing anything else that frame, matching the original inline behaviour).
static func watchdog_tick(m) -> bool:
    m.harness_frames += 1
    if m.harness_frames > m.watchdog_frames and not m.captured:
        print("HARNESS watchdog: %d frames without a capture, quitting" % m.harness_frames)
        m.get_tree().quit(2)
        return true
    return false

# --chores=N completes C1..CN before the settle (with --sun=N the sun steps
# first, so a --thing seat picked at the spawn survives); N >= 3 shuts B's
# rows and N >= 5 A's first, as the cranks would. --shut=A:110,B:001 applies
# row shutters directly.
static func game_args(m) -> void:
    if m.args.has("chores"):
        if m.args.has("sun"):
            m.lighting.sun_step(int(m.args["sun"]))   # the sun first: a --thing seat picked at the spawn then survives (no light change after it)
        # as the cranks would (M4.0h): C3 shuts B's rows, C5 A's - before the settle
        var n := int(m.args["chores"])
        if n >= 3:
            for row in 3:
                m.lighting.shutter("B", row, true)
        if n >= 5:
            for row in 3:
                m.lighting.shutter("A", row, true)
        m.game.complete_upto(n)                     # before the settle: the light converges at that step
        # the lamp as play leaves it (M5.0k): C4 takes it, C7 hangs it on the desk; lit only by --lamp=1
        m.lamp_where = "desk" if n >= 7 else ("held" if n >= 4 else "plant")
        if n >= 5:                                  # as play leaves it (M6.0n): the list rose and dropped at C5, the gate is open, the colour-first moment is spent
            m.game.colour_seen = true
            m.cf_done = true
    if m.args.has("shut"):
        var bits := Thing.shut_bits(m.args["shut"])
        for room in ["A", "B"]:
            for row in 3:
                if bits & Thing.row_mask(room, row):
                    m.lighting.shutter(room, row, true)

# the harness: --chores>=2 has C2's sheets on A's racks; --sheets=A,B throws a room's
static func racks_args(m) -> void:
    if int(m.args.get("chores", "0")) >= 2:
        sheets_on(m, "A")
    if m.args.has("sheets"):
        for room in (m.args["sheets"] as String).split(","):
            if m.racks.has(room):
                sheets_on(m, room)

# the harness: --sheets=A,B throws all of a room's sheets before the settle
static func sheets_on(m, room: String) -> void:
    for row in 3:
        var r: Dictionary = m.racks[room][row]
        r["sheet"].visible = true
        r["inter"].fired = true
        r["inter"].collision_layer = 0

# --chores>=6 lifts the card, >=7 enables the bolt, as play would leave them
static func card_sign_args(m) -> void:
    if int(m.args.get("chores", "0")) >= 6:
        m._lift_card()
    if int(m.args.get("chores", "0")) >= 7:
        m.bolt_enabled = true

# `--decal=x,y,z` places one for shots
static func decal_arg(m) -> void:
    if m.args.has("decal"):
        var p := (m.args["decal"] as String).split(",")
        if p.size() == 3:
            m._decal(Vector3(float(p[0]), float(p[1]), float(p[2])))
