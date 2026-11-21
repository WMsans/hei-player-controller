# Hei Player Controller Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable third-person capsule controller with dash-run, super, hyper, wavedash, directional air dash, and a hard air brake.

**Architecture:** One `CharacterBody3D` script (`player.gd`) holds a `State` enum, timers, and every tunable as an `@export`. Camera and juice are separate small scripts that only read the player and listen to its signals. Input is sampled into plain fields once per tick, so a headless test can script it deterministically.

**Tech Stack:** Godot 4.7, GDScript, Jolt physics.

**Spec:** `docs/superpowers/specs/2026-11-20-hei-player-controller-design.md`. Its Behavior section and Starting values table are authoritative. Read them before every task.

## Global Constraints

- Godot 4.7, Jolt, Forward+, GDScript only, keyboard and mouse only.
- Keys: WASD move, Space jump, Left Shift dash, Left Ctrl squat, Esc releases mouse. Bind by physical keycode.
- No grab, climbing, wall jumps, gamepad, audio, combat, moving platforms, menus, or character model.
- Every value in the spec's Starting values table is an `@export` on `player.gd`, with that exact name and value.
- All horizontal speed is capped at `max_speed` (35 m/s).
- Squash, stretch, and the trail are visual only and never touch the collider.
- Physics tick 120 Hz with physics interpolation on (builder's call: reduces input latency and keeps a 35 m/s body under 0.3 m per tick).

## Review Focus

1. Dashing into a wall at full speed: Hei stops against it, leaves the dash normally, and does not regain the old speed when the wall ends.
2. Hitting a ceiling during a jump or up-dash: upward speed is cancelled and Hei falls at once.
3. Running off a ledge in a dash-run, then pressing Space within coyote time: still a super, and the air dash is still available.
4. Landing a wavedash on a slope: it still becomes a slide and keeps its speed instead of launching or sticking.
5. Dashing from a standstill with no keys held: goes flat along facing, with no zero-length direction or NaN.

---

### Task 1: Ground movement, jump, and test harness

**Files:**
- Modify: `project.godot` (input map, 120 Hz physics, physics interpolation)
- Create: `player/player.gd`, `player/player.tscn`
- Test: `tests/test_player.gd`

**Interfaces:**
- Produces in `player.gd` (`class_name Player extends CharacterBody3D`):
  - `enum State { NORMAL, DASH, DASH_RUN, SLIDE }`, `var state: State`
  - `var facing: Vector3` (unit, horizontal, default `Vector3.FORWARD`), `var view_yaw: float` (radians, set by the camera)
  - `var dash_available: bool`
  - `func set_scripted_input(move: Vector2, jump: bool, dash: bool, squat: bool) -> void`: once called, real input is ignored. `move.y` is forward.
  - `func horizontal_speed() -> float`
  - `signal jumped(kind: StringName)` with kind `&"jump"`, `&"super"`, or `&"hyper"`; `signal landed(impact_speed: float)`; `signal dash_started(direction: Vector3)`
- Input actions: `move_forward`, `move_back`, `move_left`, `move_right`, `jump`, `dash`, `squat`.
- Scene: capsule collider 1.8 m tall, 0.4 m radius; child `Visual` (`Node3D`) holding the capsule mesh.

- [ ] **Step 1: Write the failing tests**

`tests/test_player.gd` `extends SceneTree`. It builds a large static floor, spawns `player.tscn`, runs every `test_*` method on a fresh player, prints failures, and calls `quit(failure_count)`. Helper: `hold(seconds, move, jump, dash, squat)` sets scripted input and awaits that many physics frames.

```gdscript
func test_run_reaches_max_run():
    await hold(1.0, Vector2.UP * -1, false, false, false) # move.y = 1, forward
    check(is_equal_approx(p.horizontal_speed(), p.max_run), "reaches max_run")

func test_jump_height_varies_with_hold():
    # A full-hold jump peaks higher than a tapped jump.
    check(await peak_height(0.3) > await peak_height(0.02), "variable jump")

func test_coyote_jump():
    # Walk off a ledge, press Space 0.05 s later: Hei gains upward speed.
    check(await coyote_jump_velocity(0.05) > 0.0, "coyote")

func test_jump_buffer():
    # Space 0.05 s before landing fires a jump on landing.
    check(await buffered_jump_fired(0.05), "buffer")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: non-zero exit, because `player.tscn` does not exist.

- [ ] **Step 3: Implement the input map, scene, and `NORMAL` ground and jump logic in `player/player.gd`**

Declare all spec exports now. Move input is rotated by `view_yaw`. Use Celeste's approach logic (`Player.cs:2884-2965`): approach the target at `run_accel`, or `run_reduce` above max speed. Apply half gravity near the apex while Space is held. Coyote 0.1 s, jump buffer 0.1 s.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add project.godot player tests
git commit -m "feat: add player ground movement and jump"
```

---

### Task 2: Dash, aiming, and dash-run

**Files:**
- Modify: `player/player.gd`
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: Task 1 Player API.
- Produces: `func dash_direction(move_world: Vector3, up: bool, down: bool) -> Vector3` (unit length, implements the spec's aiming table), and the `DASH` and `DASH_RUN` states.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_aim_table():
    var f := Vector3.FORWARD
    check(p.dash_direction(f, false, false).is_equal_approx(f), "flat")
    check(p.dash_direction(f, true, false).y > 0.0, "up diagonal")
    check(p.dash_direction(f, false, true).y < 0.0, "down diagonal")
    check(p.dash_direction(Vector3.ZERO, true, false).is_equal_approx(Vector3.UP), "straight up")
    check(p.dash_direction(Vector3.ZERO, false, true).is_equal_approx(Vector3.DOWN), "straight down")
    check(p.dash_direction(f, true, true).is_equal_approx(f), "both cancel")

func test_standstill_dash_goes_along_facing(): # Review Focus 5
    await hold(0.05, Vector2.ZERO, false, true, false)
    check(p.velocity.is_finite() and p.velocity.dot(p.facing) > 0.0, "flat along facing")

func test_one_air_dash_per_airtime(): pass # second Shift press in the air starts no dash
func test_held_shift_does_not_extend_air_dash(): pass # state leaves DASH by dash_time + one tick
func test_space_held_aims_air_dash_up(): pass # velocity.y > 0 during burst
func test_space_mid_dash_reaims_up(): pass
func test_landing_with_shift_enters_dash_run_at_carried_speed(): pass
func test_ground_burst_needs_fresh_shift(): pass # re-pressing WASD with Shift held fires no dash_started
func test_dash_cooldown_blocks_retrigger(): pass # 0.2 s
func test_ground_shift_space_consumes_air_dash(): pass
func test_dash_into_wall_stops_cleanly(): pass # Review Focus 1: wall ends, speed not restored
func test_ceiling_cancels_up_dash(): pass # Review Focus 2
```

Replace each `pass` with assertions for the behavior named in its comment and the spec.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: failures naming the new tests.

- [ ] **Step 3: Implement dash states**

Burst lasts `dash_time`, one air dash per airtime, dash buffer 0.08 s, cooldown 0.2 s. Keep horizontal speed if already faster in the dash direction. On burst end for flat or upward dashes, use `dash_run_speed` along the direction with `end_dash_up_mult` on upward speed, as in `Player.cs:3625-3632`, without slowing a faster body. Sustained `DASH_RUN` holds `dash_run_speed` and bleeds any excess at `run_reduce`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add player/player.gd tests/test_player.gd
git commit -m "feat: add directional dash and dash-run"
```

---

### Task 3: Super, hyper, slide, wavedash, momentum cap

**Files:**
- Modify: `player/player.gd`
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: `DASH`, `DASH_RUN`, `jumped` signal.
- Produces: the `SLIDE` state.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_super_exceeds_dash_run(): pass # horizontal == super_jump_h, > dash_run_speed
func test_hyper_faster_and_lower_than_super(): pass # h == super_jump_h * 1.25, peak below super's
func test_wavedash_refills_dash(): pass # down-diagonal burst into floor: SLIDE, dash_available
func test_wavedash_grace_window(): pass # contact within 0.1 s after burst still slides; 0.2 s does not
func test_early_space_in_down_dash_fires_hyper(): pass # Ctrl held, jumped(&"hyper") on landing
func test_slide_stops_quickly(): pass # from wavedash speed to rest in <= 0.4 s while Ctrl held
func test_hyper_from_nearly_stopped_slide_is_full_power(): pass # h >= super_jump_h * 1.25
func test_chained_speed_never_exceeds_max(): pass # repeated hypers stay <= max_speed
func test_coyote_super_off_ledge(): pass # Review Focus 3, air dash still available
func test_wavedash_on_slope_keeps_speed(): pass # Review Focus 4, on a 20-degree ramp
```

Replace each `pass` with assertions for the behavior named in its comment and the spec.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: failures naming the new tests.

- [ ] **Step 3: Implement super, hyper, `SLIDE`, and the cap**

Use the spec's formulas: super `max(current, super_jump_h)`, hyper `max(current, super_jump_h) * hyper_h_mult`, both then clamped to `max_speed`. Slide enters at `slide_mult`, decelerates at `duck_friction`, and follows the spec's exit rules.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add player/player.gd tests/test_player.gd
git commit -m "feat: add super, hyper, wavedash, and momentum cap"
```

---

### Task 4: Air control and air brake

**Files:**
- Modify: `player/player.gd`
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: Task 3 launch speeds.
- Produces: `var is_air_braking: bool` (read by the juice in Task 6).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_air_steer_keeps_speed(): pass # super + side input: direction turns, speed loss < 15% over 0.3 s
func test_opposite_input_brakes(): pass # dot < -0.5 lowers speed
func test_brake_stops_quickly(): pass # fresh Ctrl in air: 27 m/s to rest in <= 0.35 s
func test_brake_faster_than_no_input(): pass
func test_brake_falls_faster(): pass # reaches fast_max_fall
func test_ctrl_through_hyper_does_not_brake(): pass # Ctrl never released, speed kept
func test_ctrl_after_down_dash_needs_repress(): pass
func test_brake_ignores_wasd(): pass
func test_brake_into_down_dash(): pass # Shift while braking dashes downward
```

Replace each `pass` with assertions for the behavior named in its comment and the spec.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: failures naming the new tests.

- [ ] **Step 3: Implement air control and the brake**

Follow the spec's Air control and Air brake sections. Arm the brake only on a Ctrl press that happens while airborne and outside a dash burst. Disarm on release and on landing.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add player/player.gd tests/test_player.gd
git commit -m "feat: add air control and air brake"
```

---

### Task 5: Camera and test level

**Files:**
- Create: `player/player_camera.gd`, `levels/test_level.tscn`
- Modify: `player/player.tscn`, `project.godot` (main scene)

**Interfaces:**
- Consumes: `Player.view_yaw`, `horizontal_speed()`, `max_speed`.
- Produces: playable main scene `res://levels/test_level.tscn`.

- [ ] **Step 1: Implement the orbit camera**

`SpringArm3D` rig that does not inherit player rotation. Mouse orbit writes `view_yaw`. Mouse is captured on start, Esc releases it, click recaptures. FOV goes from 75 at rest to 95 at `max_speed`, smoothed.

- [ ] **Step 2: Build the test level**

Include a 150 m runway, gaps of 8, 15, and 25 m, ledges of 2, 4, and 8 m, a 20-degree ramp, and a wall and low ceiling for dash testing. Add a directional light and environment.

- [ ] **Step 3: Verify the scene loads and runs**

Run: `timeout 5 godot --headless --path . res://levels/test_level.tscn 2>&1 | grep -E "ERROR|SCRIPT" ; godot --headless --path . --script tests/test_player.gd`
Expected: no error lines, test exit 0.

- [ ] **Step 4: Commit**

```bash
git add player levels project.godot
git commit -m "feat: add orbit camera and test level"
```

---

### Task 6: Juice

**Files:**
- Create: `player/player_juice.gd` (attached to `Visual`)
- Modify: `player/player.gd` (hit-freeze), `player/player.tscn`
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: `jumped`, `landed`, `dash_started`, `dash_available`, `is_air_braking`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_hit_freeze_holds_position_for_50ms(): pass # position unchanged for 0.05 s after dash start, then moves
func test_juice_never_scales_collider(): pass # CollisionShape3D scale stays ONE through jump and landing
```

Replace each `pass` with assertions for the behavior named in its comment.

- [ ] **Step 2: Run tests to verify they fail**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: the hit-freeze test fails.

- [ ] **Step 3: Implement the juice**

Hit-freeze skips the player's simulation for 0.05 s while still sampling input, so a jump pressed in the freeze is not lost. Stretch to (0.6, 1.4, 0.6) on jump, squash on landing scaled by impact speed, and recover quickly. Add a dash trail of fading capsule ghosts. Tint the capsule when `dash_available` is false.

- [ ] **Step 4: Run tests to verify they pass**

Run: `godot --headless --path . --script tests/test_player.gd`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add player tests/test_player.gd
git commit -m "feat: add squash, trail, hit-freeze, and dash tint"
```

- [ ] **Step 6: Hand over for playtest**

Ask the user to run the project and judge the feel against `jump reference 3.mp4` and `jump reference 4.mp4`. Automated checks cannot verify feel.
