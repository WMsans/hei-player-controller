# Hei Feel Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the capsule controller Hei's long hang and carried momentum, then add rebounding wall kicks.

**Architecture:** All movement stays in the single `CharacterBody3D` script, `player/player.gd`. Stage 1 retunes gravity, replaces the hard cap with a soft limit plus ceiling, and makes dashes additive. Stage 2 adds wall kicks after the user approves Stage 1 by playing it.

**Tech Stack:** Godot 4.7, GDScript, Jolt, 120 physics ticks per second, headless `SceneTree` test script.

**Spec:** `docs/superpowers/specs/2026-11-21-hei-feel-pass-design.md`

## Global Constraints

- Run every task in the current working tree on `feat/hei-player-controller`. Do not use a worktree, because the user's input bindings are uncommitted and they need them to play.
- Never stage `project.godot` or `levels/test_level.tscn`. They hold the user's uncommitted edits. Keep left mouse as dash and Left Shift as squat.
- All new tuning values are `@export` vars in `player.gd`.
- Non-goals: no character model, poses, new visual effects, audio, gamepad, wall slide, grab, or camera behavior change.
- Test command: `godot --headless --fixed-fps 120 --path . --script tests/test_player.gd`. Passing output ends with `N tests, 0 failed checks`. The baseline is 61 tests with 0 failed.
- Change an existing test only where a task names it. Any other failure is a bug in the implementation.

## Review Focus

1. A backward dash that exactly cancels current speed leaves finite velocity and no NaN. Test in Task 3.
2. Hei at the 60 m/s ceiling does not tunnel through a thin wall. Test in Task 2.
3. A fast hyper up a ramp is not clipped by `max_rise` and leaves the ramp. Test in Task 3.
4. If a wall disappears or Hei has left it, remembered impact speed cannot fire a kick. Test in Task 5.
5. Falling out and returning to spawn clears the wall-kick timers. Test in Task 5.

---

## Stage 1: Momentum, limits, and hang

### Task 1: Long hang

**Files:**
- Modify: `player/player.gd:18-22,43-46`
- Test: `tests/test_player.gd`

**Interfaces:**
- Produces: new default values for the exports below. Later tasks rely on `jump_speed == 12.0`.

- [ ] **Step 1: Add the failing test and update the two tests whose numbers this task changes**

```gdscript
func test_full_jump_hangs_like_the_clips() -> void:
	var start: float = p.position.y
	var peak := start
	var apex_tick := 0
	var ticks := 0
	p.set_scripted_input(NONE, true, false, false)
	while ticks < 360:
		await physics_frame
		ticks += 1
		if p.position.y > peak:
			peak = p.position.y
			apex_tick = ticks
		if ticks > 4 and p.is_on_floor():
			break
	check(absf(peak - start - 4.6) < 0.3, "rises 4.6 m, got %f" % (peak - start))
	check(absf(apex_tick / 120.0 - 0.63) < 0.06, "apex at 0.63 s, got %f" % (apex_tick / 120.0))
	check(absf(ticks / 120.0 - 1.22) < 0.1, "airtime 1.22 s, got %f" % (ticks / 120.0))
```

In `test_brake_falls_faster`, change the expected speeds from `13.3` to `20.0` and from `20.0` to `30.0`. In `test_brake_cuts_rising_jump`, change `8.75 - 2.0` to `12.0 - 2.0`.

- [ ] **Step 2: Run the tests and confirm those three fail**

Run the test command. Expected: `FAIL` lines for `test_full_jump_hangs_like_the_clips`, `test_brake_falls_faster`, and `test_brake_cuts_rising_jump`.

- [ ] **Step 3: Change the export defaults in `player/player.gd`**

| Export | New value |
|---|---|
| `gravity` | `36.0` |
| `max_fall` | `20.0` |
| `fast_max_fall` | `30.0` |
| `jump_speed` | `12.0` |
| `air_brake_decel` | `150.0` |
| `air_brake_gravity_mult` | `3.0` |

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `62 tests, 0 failed checks`.

- [ ] **Step 5: Commit**

```bash
git add player/player.gd tests/test_player.gd
git commit -m "feat: retune gravity and jump for a long hang"
```

### Task 2: Soft speed limit and low drag

**Files:**
- Modify: `player/player.gd` (`_apply_air`, `_apply_run`, `_update_dash_run`, `_jump`, exports)
- Modify: `player/player_camera.gd:45`
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: Task 1 values.
- Produces: exports `soft_speed := 35.0`, `air_drag := 1.0`, `ground_bleed := 10.8`, and `max_speed := 60.0`. Helper `_decay(speed: float, target: float, slow_rate: float, pull_rate: float, delta: float) -> float`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_soft_limit_pulls_back_without_input() -> void:
	await fly(50.0)
	await hold(0.5, NONE)
	check(absf(p.horizontal_speed() - 39.3) < 0.4, "pulled back, got %f" % p.horizontal_speed())


func test_soft_limit_pulls_back_with_wasd() -> void:
	await fly(50.0)
	await hold(0.5, FORWARD)
	check(absf(p.horizontal_speed() - 39.3) < 0.4, "pulled back, got %f" % p.horizontal_speed())


func test_max_speed_is_a_hard_ceiling() -> void:
	await fly(80.0)
	await hold(0.01, NONE)
	check(p.horizontal_speed() <= 60.001, "ceiling, got %f" % p.horizontal_speed())


func test_ceiling_speed_does_not_tunnel_thin_wall() -> void: # Review Focus 2
	add_box(Vector3(0, 60, -6), Vector3(40, 40, 0.2))
	await respawn(Vector3(0, 60, 0))
	p.velocity = Vector3(0, 0, -60)
	await hold(0.3, FORWARD)
	check(p.position.z > -6.0, "stopped by wall, z %f" % p.position.z)


func test_air_speed_barely_drops_without_input() -> void:
	await fly(20.0)
	await hold(1.0, NONE)
	check(absf(p.horizontal_speed() - 19.0) < 0.15, "coasts, got %f" % p.horizontal_speed())


func test_ground_bleed_takes_about_two_seconds() -> void:
	p.velocity = Vector3(0, 0, -35)
	await hold(2.0, FORWARD)
	check(absf(p.horizontal_speed() - 13.4) < 0.4, "slow bleed, got %f" % p.horizontal_speed())


func test_no_wasd_landing_coasts() -> void:
	await respawn(Vector3(0, 1.5, 0))
	p.velocity = Vector3(0, 0, -30)
	await hold(0.05, NONE)
	await land()
	await hold(0.2, NONE)
	check(p.horizontal_speed() > 26.0, "coasts on landing, got %f" % p.horizontal_speed())


func test_hopping_does_not_build_speed() -> void:
	await hold(0.5, FORWARD)
	var fastest := 0.0
	for hop in 8:
		await hold(0.02, FORWARD, true)
		p.set_scripted_input(FORWARD, false, false, false)
		for i in 240:
			await physics_frame
			fastest = maxf(fastest, p.horizontal_speed())
			if i > 4 and p.is_on_floor():
				break
	check(fastest <= 10.81, "hop limit, got %f" % fastest)


func test_fov_uses_soft_speed() -> void:
	await fly(35.0)
	await hold(0.5, NONE)
	var camera: Camera3D = p.get_node("CameraRig/SpringArm3D/Camera3D")
	check(camera.fov > 93.0, "full FOV at soft speed, got %f" % camera.fov)
```

In `test_chained_speed_never_exceeds_max`, replace the two final checks:

```gdscript
	check(fastest > 35.0, "chain passes the soft limit, got %f" % fastest)
	check(fastest <= 60.001, "capped at 60, got %f" % fastest)
```

- [ ] **Step 2: Run the tests and confirm the new tests fail**

Expected: `FAIL` lines for the new tests except possibly the thin-wall test, plus the updated chain test.

- [ ] **Step 3: Implement the speed rules in `player/player.gd`**

Add `soft_speed`, `air_drag`, and `ground_bleed` to the Run group and set `max_speed` to `60.0`. Add this helper:

```gdscript
## Moves speed toward target: pull_rate above soft_speed, slow_rate below it.
func _decay(speed: float, target: float, slow_rate: float, pull_rate: float, delta: float) -> float:
	if speed > soft_speed:
		return maxf(speed - pull_rate * delta, maxf(soft_speed, target))
	return move_toward(speed, target, slow_rate * delta)
```

Use it with these branch orders:

- `_apply_air`: air brake first. Then no WASD: keep direction, `_decay(speed, 0.0, air_drag, run_reduce * air_mult, delta)`. Then `speed <= max_run`: accelerate as today. Then opposite input (`dot < -0.5`): brake as today. Otherwise `_steer`, then `_decay(speed, max_run, air_drag, run_reduce * air_mult, delta)`.
- `_apply_run`: at or below `max_run`, or with opposite input (`dot < -0.5`), use `move_toward(_move * max_run, run_accel * delta)`. Otherwise `_steer`, then `_decay(speed, max_run, ground_bleed, run_reduce, delta)`. No WASD above `max_run` takes the second path, because `_steer` is a no-op without input.
- `_update_dash_run`: above `dash_run_speed` use `_decay(speed, dash_run_speed, ground_bleed, run_reduce, delta)`. Below it, approach at `run_accel`.
- `_jump`: add the boost, then limit horizontal length to `maxf(speed_before_boost, max_run + jump_h_boost)`.

In `player_camera.gd:45`, divide by `_player.soft_speed` instead of `_player.max_speed`.

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `71 tests, 0 failed checks`.

- [ ] **Step 5: Commit**

```bash
git add player/player.gd player/player_camera.gd tests/test_player.gd
git commit -m "feat: add soft speed limit, low air drag, and slow ground bleed"
```

### Task 3: Additive dashes

**Files:**
- Modify: `player/player.gd` (`_start_dash`, `_land_wavedash`, `_update_dash`, `_end_dash`, `_physics_process`, `_return_to_spawn`, exports)
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: `soft_speed`, `max_speed` from Task 2.
- Produces: export `max_rise := 18.0`. Vars `_dash_base: Vector3`, `_ground_dash_ready := true`. Helper `_dash_velocity(direction: Vector3, amount: float, full_add: bool) -> Vector3`.
- Removes: `end_dash_up_mult`, `_dash_keep`, `_set_dash_velocity`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_sideways_dash_keeps_forward_speed() -> void:
	await fly(25.0)
	await hold(0.07, Vector2(1, 0), false, true)
	check(absf(p.velocity.x - 20.0) < 0.5, "adds sideways, got %s" % p.velocity)
	check(absf(p.velocity.z + 25.0) < 0.5, "keeps forward, got %s" % p.velocity)


func test_backward_dash_subtracts() -> void:
	await fly(25.0)
	await hold(0.07, Vector2(0, -1), false, true)
	check(absf(p.velocity.z + 5.0) < 0.5, "5 m/s forward, got %s" % p.velocity)


func test_exact_cancel_dash_stays_finite() -> void: # Review Focus 1
	await fly(20.0)
	await hold(0.07, Vector2(0, -1), false, true)
	check(p.velocity.is_finite(), "finite, got %s" % p.velocity)
	check(p.horizontal_speed() < 0.5, "cancelled, got %f" % p.horizontal_speed())
	await hold(0.2, NONE)
	check(p.velocity.is_finite(), "stays finite, got %s" % p.velocity)


func test_straight_up_dash_keeps_horizontal_speed() -> void:
	await fly(25.0)
	await hold(0.07, NONE, true, true)
	check(absf(p.horizontal_speed() - 25.0) < 0.5, "keeps speed, got %f" % p.horizontal_speed())
	check(p.velocity.y > 15.0, "rises, got %f" % p.velocity.y)


func test_up_dash_rises_while_falling() -> void:
	await fly(0.0)
	await hold(0.6, NONE)
	check(p.velocity.y < -10.0, "falling first, got %f" % p.velocity.y)
	await hold(0.07, NONE, true, true)
	check(absf(p.velocity.y - 18.0) < 0.1, "limited rise, got %f" % p.velocity.y)


func test_down_dash_falls_while_rising() -> void:
	await hold(0.05, NONE, true)
	await hold(0.07, NONE, false, true, true)
	check(absf(p.velocity.y + 20.0) < 0.5, "falls, got %f" % p.velocity.y)


func test_flat_dash_keeps_vertical_speed() -> void:
	await fly(10.0)
	await hold(0.3, NONE)
	var before: float = p.velocity.y
	await hold(0.07, FORWARD, false, true)
	check(absf(p.velocity.y - before) < 0.5, "%f vs %f" % [p.velocity.y, before])


func test_dash_speed_survives_the_burst() -> void:
	await fly(10.0)
	await hold(0.25, FORWARD, false, true)
	check(p.state != p.State.DASH, "burst over")
	check(p.horizontal_speed() > 29.0, "no end trim, got %f" % p.horizontal_speed())


func test_plain_dash_stops_adding_at_soft_limit() -> void:
	await fly(30.0)
	await hold(0.07, FORWARD, false, true)
	check(absf(p.horizontal_speed() - 35.0) < 0.1, "got %f" % p.horizontal_speed())


func test_dash_above_soft_limit_bends_and_keeps_speed() -> void:
	await fly(50.0)
	await hold(0.07, Vector2(1, 0), false, true)
	check(absf(p.horizontal_speed() - 50.0) < 0.5, "keeps 50, got %f" % p.horizontal_speed())
	check(p.velocity.x > 15.0, "path bends, got %s" % p.velocity)


func test_hyper_can_pass_soft_limit() -> void:
	p.velocity = Vector3(0, 0, -34)
	await hold(0.06, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	check(p.horizontal_speed() > 38.0, "hyper passes 35, got %f" % p.horizontal_speed())


func test_mashing_ground_dash_does_not_build_speed() -> void:
	var fastest := 0.0
	for press in 8:
		await hold(0.03, FORWARD, false, true)
		p.set_scripted_input(FORWARD, false, false, false)
		for i in 30:
			await physics_frame
			fastest = maxf(fastest, p.horizontal_speed())
	check(fastest <= 20.1, "mash stays at dash speed, got %f" % fastest)


func test_dash_and_hop_loop_stays_at_soft_limit() -> void:
	var fastest := 0.0
	for hop in 6:
		await hold(0.08, FORWARD, false, true)
		fastest = maxf(fastest, p.horizontal_speed())
		await hold(0.02, FORWARD, true, true)
		await hold(0.15, FORWARD)
		await hold(0.08, FORWARD, false, true)
		fastest = maxf(fastest, p.horizontal_speed())
		p.set_scripted_input(FORWARD, false, false, false)
		for i in 240:
			await physics_frame
			fastest = maxf(fastest, p.horizontal_speed())
			if i > 2 and p.is_on_floor():
				break
	check(fastest > 30.0, "loop is fast, got %f" % fastest)
	check(fastest <= 35.001, "loop stays at 35, got %f" % fastest)


func test_low_slide_multiplies_only_added_speed() -> void:
	p.velocity = Vector3(0, 0, -5)
	await hold(0.02, FORWARD, false, true, true)
	check(absf(p.horizontal_speed() - 29.0) < 0.5, "5 + 20 * 1.2, got %f" % p.horizontal_speed())


func test_straight_down_wavedash_adds_to_carried_speed() -> void:
	await respawn(Vector3(0, 1.8, 0))
	p.velocity = Vector3(0, 0, -10)
	await hold(0.03, NONE, false, true, true)
	p.set_scripted_input(FORWARD, false, false, true)
	await land()
	await hold(0.01, FORWARD, false, false, true)
	check(p.state == p.State.SLIDE, "slides, state %d" % p.state)
	check(p.horizontal_speed() > 26.0, "(10 + 14.1) * 1.2, got %f" % p.horizontal_speed())


func test_fast_hyper_up_ramp_is_not_rise_limited() -> void: # Review Focus 3
	await on_ramp(0.7)
	await land()
	await hold(0.1, NONE)
	p.velocity = Vector3(0, 0, -34)
	await hold(0.06, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	check(p.velocity.y > 18.0, "launch keeps slope rise, got %f" % p.velocity.y)
	await hold(0.05, FORWARD, true, true, true)
	check(not p.is_on_floor(), "left the ramp")
```

Replace `test_space_mid_dash_reaims_up`, because a flat dash now keeps its rise:

```gdscript
func test_space_mid_dash_reaims_up() -> void:
	await get_airborne()
	var before: float = p.velocity.y
	await hold(0.03, FORWARD, false, true)
	check(p.velocity.y <= before + 0.01, "starts flat, got %f" % p.velocity.y)
	await hold(0.04, FORWARD, true, true)
	check(p.velocity.y > before + 5.0, "re-aimed up, got %f" % p.velocity.y)
```

- [ ] **Step 2: Run the tests and confirm the new dash tests fail**

Expected: `FAIL` lines for most of the new tests.

- [ ] **Step 3: Implement `_dash_velocity` in `player/player.gd`**

```gdscript
## Stored velocity plus the dash. Plain dashes never add past soft_speed.
func _dash_velocity(direction: Vector3, amount: float, full_add: bool) -> Vector3:
	var base := _dash_base
	if base.y * direction.y < 0.0:
		base.y = 0.0
	var carried := Vector3(base.x, 0.0, base.z)
	var flat := Vector3(direction.x, 0.0, direction.z)
	var added := flat * amount
	if not full_add:
		var unit := flat.normalized()
		added = unit * maxf(amount - carried.dot(unit), 0.0)
	var horizontal := (carried + added).limit_length(maxf(soft_speed, carried.length()))
	var rise := base.y + direction.y * amount
	if direction.y > 0.0:
		rise = minf(rise, maxf(max_rise, base.y))
	return Vector3(horizontal.x, rise, horizontal.z)
```

- [ ] **Step 4: Wire it into the dash flow**

- `_physics_process`: set `_ground_dash_ready = true` whenever `not was_on_floor`.
- `_start_dash`: set `_dash_base = velocity`, and zero `_dash_base.y` if grounded. A dash with `grounded and direction.y <= 0.0` is a ground dash: `full_add = _ground_dash_ready`, then set `_ground_dash_ready = false`. Every other dash uses `full_add = true`.
- Low slide branch: `velocity = _dash_velocity(flat_direction, dash_speed * slide_mult, full_add)`.
- Normal branch: `velocity = _dash_velocity(direction, dash_speed, full_add)`.
- `_update_dash` re-aim: `velocity = _dash_velocity(_dash_dir, dash_speed, true)`.
- `_end_dash`: only set `state = State.NORMAL`.
- `_land_wavedash`, straight-down branch with WASD: `horizontal += _move.normalized() * dash_speed * sqrt(0.5)`.
- `_return_to_spawn`: set `_ground_dash_ready = true`.
- Add `max_rise` to the Dash group. Delete `end_dash_up_mult`, `_dash_keep`, and `_set_dash_velocity`.

- [ ] **Step 5: Run the tests and confirm they pass**

Expected: `87 tests, 0 failed checks`.

- [ ] **Step 6: Commit**

```bash
git add player/player.gd tests/test_player.gd
git commit -m "feat: make every dash add to current momentum"
```

### Task 4: User play check (gate)

- [ ] **Step 1: Stop and ask the user to play the game**

Launch nothing on their behalf unless asked. Tell them Stage 1 is ready and name the things to judge: jump hang, carried speed, ground bleed, soft limit pull-back, and squat drop.

- [ ] **Step 2: Apply their tuning feedback**

Change export defaults or rules as they direct, update affected tests, and commit `player/player.gd` and `tests/test_player.gd`.

- [ ] **Step 3: Do not start Task 5 until the user says Stage 1 feels right.**

---

## Stage 2: Wall kicks

### Task 5: Wall kicks

**Files:**
- Modify: `player/player.gd` (exports, `_physics_process`, `_apply_air`, `_return_to_spawn`)
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: `_decay`, `jump_speed`, `_jump_buffer`, `_coyote`, `jumped` signal.
- Produces: exports `wall_kick_speed := 10.8`, `wall_kick_reach := 0.25`, `wall_kick_lock := 0.16`, `wall_retain_time := 0.15` in a "Wall Kick" group. Vars `_wall_normal: Vector3`, `_wall_impact: float`, `_wall_retain: float`, `_wall_lock: float`. Helpers `_find_wall() -> Vector3` and `_try_wall_kick() -> bool`. Jump kind `&"wall"`.

- [ ] **Step 1: Write the failing tests**

```gdscript
## Flies Hei with no input into a wall ahead, stopping on first contact.
func hit_wall(speed: float, side := 0.0) -> StaticBody3D:
	var wall := add_box(Vector3(0, 60, -4), Vector3(60, 80, 1))
	await respawn(Vector3(0, 60, 0))
	p.velocity = Vector3(side, 0, -speed)
	p.set_scripted_input(NONE, false, false, false)
	for i in 240:
		await physics_frame
		if p.is_on_wall():
			break
	return wall


func test_wall_kick_rebounds_with_impact_speed() -> void:
	await hit_wall(30.0)
	var kinds := record_jumps()
	await hold(0.02, NONE, true)
	check(kinds == [&"wall"], "kicked, got %s" % [kinds])
	check(absf(p.velocity.z - 30.0) < 1.0, "rebounds at 30, got %s" % p.velocity)
	check(p.velocity.y >= 11.5, "rises, got %f" % p.velocity.y)


func test_slow_touch_uses_kick_speed() -> void:
	await hit_wall(4.0)
	await hold(0.02, NONE, true)
	check(absf(p.velocity.z - 10.8) < 0.5, "base kick, got %s" % p.velocity)


func test_kick_carries_speed_along_wall() -> void:
	await hit_wall(20.0, 12.0)
	await hold(0.02, NONE, true)
	check(absf(p.velocity.x - 12.0) < 1.0, "keeps along-wall speed, got %s" % p.velocity)
	check(absf(p.velocity.z - 20.0) < 1.0, "rebounds, got %s" % p.velocity)


func test_kick_refills_air_dash() -> void:
	await hit_wall(20.0)
	p.dash_available = false
	await hold(0.02, NONE, true)
	check(p.dash_available, "refilled")


func test_holding_toward_wall_does_not_cancel_rebound() -> void:
	await hit_wall(20.0)
	await hold(0.02, FORWARD, true)
	await hold(0.12, FORWARD)
	check(p.velocity.z > 15.0, "still rebounding, got %s" % p.velocity)


func test_same_wall_can_be_kicked_repeatedly() -> void:
	await hit_wall(15.0)
	var kinds := record_jumps()
	for kick in 3:
		await hold(0.02, NONE, true)
		await hold(0.1, FORWARD)
		for i in 360:
			if p.is_on_wall():
				break
			await physics_frame
	check(kinds.size() == 3, "three kicks, got %d" % kinds.size())


func test_alternating_walls_work() -> void:
	add_box(Vector3(0, 60, 4), Vector3(60, 80, 1))
	await hit_wall(20.0)
	var kinds := record_jumps()
	await hold(0.02, NONE, true)
	await hold(0.05, NONE)
	for i in 120:
		if p.is_on_wall():
			break
		await physics_frame
	await hold(0.02, NONE, true)
	check(kinds.size() == 2, "two kicks, got %d" % kinds.size())
	check(p.velocity.z < -15.0, "rebounds off second wall, got %s" % p.velocity)


func test_floor_jump_beats_wall_kick() -> void:
	add_box(Vector3(0, 5, -1), Vector3(20, 10, 1))
	var kinds := record_jumps()
	await hold(0.02, NONE, true)
	check(kinds == [&"jump"], "floor jump, got %s" % [kinds])


func test_kick_beats_dash_reaim() -> void:
	add_box(Vector3(0, 60, -1), Vector3(60, 80, 1))
	await respawn(Vector3(0, 60, 0))
	var kinds := record_jumps()
	await hold(0.03, Vector2(1, 0), false, true)
	await hold(0.04, Vector2(1, 0), true, true)
	check(kinds == [&"wall"], "kicked mid-dash, got %s" % [kinds])
	check(p.state != p.State.DASH, "dash ended")
	check(p.velocity.z > 5.0, "away from wall, got %s" % p.velocity)


func test_down_dash_with_squat_near_wall_keeps_hyper() -> void:
	add_box(Vector3(0, 5, -1), Vector3(40, 10, 1))
	await respawn(Vector3(0, 1.8, 0))
	var kinds := record_jumps()
	var side := Vector2(1, 0)
	await hold(0.02, side, false, true, true)
	await hold(0.03, side, true, true, true)
	p.set_scripted_input(side, true, false, true)
	await land()
	await hold(0.02, side, true, false, true)
	check(kinds == [&"hyper"], "hyper on landing, got %s" % [kinds])


func test_no_kick_after_wall_is_gone() -> void: # Review Focus 4
	var wall: StaticBody3D = await hit_wall(30.0)
	var kinds := record_jumps()
	wall.queue_free()
	await hold(0.02, NONE)
	await hold(0.02, NONE, true)
	check(kinds.is_empty(), "no wall, no kick, got %s" % [kinds])
	check(p.velocity.z < 5.0, "no stored rebound, got %s" % p.velocity)


func test_return_to_spawn_clears_wall_state() -> void: # Review Focus 5
	await hit_wall(30.0)
	await hold(0.02, NONE, true)
	p.position = Vector3(0, -100, 0)
	await hold(0.01, NONE)
	check(p._wall_lock == 0.0, "lock cleared, got %f" % p._wall_lock)
	check(p._wall_retain == 0.0, "impact cleared, got %f" % p._wall_retain)
```

- [ ] **Step 2: Run the tests and confirm the new kick tests fail**

Expected: `FAIL` lines for the wall-kick tests. `test_floor_jump_beats_wall_kick` and `test_no_kick_after_wall_is_gone` may already pass.

- [ ] **Step 3: Record wall impacts in `_physics_process`**

Tick `_wall_retain` and `_wall_lock` down with the other timers. Store `velocity` before `move_and_slide()`. Immediately after it, and before the `kill_y` check, if `is_on_wall()`, flatten `get_wall_normal()` and compute `into = -before_flat.dot(normal)`. When `into > 0.01` and either `_wall_retain <= 0.0` or `into > _wall_impact`, store `_wall_normal`, `_wall_impact = into`, and `_wall_retain = wall_retain_time`.

- [ ] **Step 4: Implement `_find_wall` and `_try_wall_kick`**

`_find_wall() -> Vector3`: cast in 8 horizontal directions with `test_move(global_transform, dir * wall_kick_reach, hit, safe_margin, true)`, using a `KinematicCollision3D`. Keep hits where `absf(hit.get_normal().y) < cos(floor_max_angle)`. Return the flattened normal of the hit with the shortest `get_travel()`, or `Vector3.ZERO`.

```gdscript
func _try_wall_kick() -> bool:
	if _jump_buffer <= 0.0 or _coyote > 0.0 or is_on_floor():
		return false
	var normal := _find_wall()
	if normal == Vector3.ZERO:
		return false
	var impact := _wall_impact if _wall_retain > 0.0 and normal.dot(_wall_normal) > 0.7 else 0.0
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var away := horizontal.dot(normal)
	var along := horizontal - normal * away
	var out := along + normal * maxf(maxf(impact, wall_kick_speed), away)
	velocity = Vector3(out.x, maxf(velocity.y, jump_speed), out.z)
	state = State.NORMAL
	dash_available = true
	_brake_armed = false
	is_air_braking = false
	_jump_buffer = 0.0
	_wall_retain = 0.0
	_wall_lock = wall_kick_lock
	_var_jump = var_jump_time
	_var_jump_speed = jump_speed
	jumped.emit(&"wall")
	return true
```

- [ ] **Step 5: Wire the kick into the frame**

In `_physics_process`, immediately before `match state`:

```gdscript
var holds_hyper := state == State.DASH and _dash_dir.y < 0.0 and _squat_down
var kicked := not was_on_floor and not holds_hyper and _try_wall_kick()
```

Run the `match` only when `not kicked`. In `_apply_air`, extend the no-WASD branch to `_move == Vector3.ZERO or _wall_lock > 0.0`, placed after the air brake branch. In `_return_to_spawn`, zero `_wall_retain`, `_wall_lock`, and `_wall_impact`.

- [ ] **Step 6: Run the tests and confirm they pass**

Expected: `99 tests, 0 failed checks`.

- [ ] **Step 7: Commit**

```bash
git add player/player.gd tests/test_player.gd
git commit -m "feat: add rebounding wall kicks that refill the air dash"
```

### Task 6: Wall-kick course

**Files:**
- Modify: `levels/test_level.tscn` (leave uncommitted)
- Test: `tests/test_player.gd`

**Interfaces:**
- Consumes: the level's existing `ShaderMaterial_ground` and `ShaderMaterial_block` sub-resources and `Geometry` node.

- [ ] **Step 1: Write the failing test**

```gdscript
func test_level_has_wall_kick_course() -> void:
	var level: Node = load("res://levels/test_level.tscn").instantiate()
	for node_name in ["KickFloor", "KickWallL", "KickWallR", "KickPillarA", "KickPillarB", "KickPillarC"]:
		var box := level.get_node_or_null("Geometry/" + node_name) as CSGBox3D
		check(box != null, "%s exists" % node_name)
		if box:
			check(box.use_collision, "%s collides" % node_name)
	level.free()
```

- [ ] **Step 2: Run the tests and confirm it fails**

Expected: `FAIL test_level_has_wall_kick_course` for each missing node.

- [ ] **Step 3: Append the course to the `Geometry` node in the working copy of `levels/test_level.tscn`**

Use `CSGBox3D` nodes with `use_collision = true`, matching the existing format. Do not change any other line.

| Node | Center | Size | Material |
|---|---|---|---|
| `KickFloor` | (0, -1, 30) | (24, 2, 50) | ground |
| `KickWallL` | (-5.5, 10, 30) | (1, 20, 30) | block |
| `KickWallR` | (5.5, 10, 30) | (1, 20, 30) | block |
| `KickPillarA` | (-4, 8, 48.5) | (2, 16, 2) | block |
| `KickPillarB` | (3, 8, 50) | (2, 16, 2) | block |
| `KickPillarC` | (-2, 8, 53) | (2, 16, 2) | block |

- [ ] **Step 4: Run the tests and confirm they pass**

Expected: `100 tests, 0 failed checks`. Check `git diff --stat levels/test_level.tscn` shows only added course lines beyond the user's earlier node ID changes.

- [ ] **Step 5: Commit the test only**

```bash
git add tests/test_player.gd
git commit -m "test: cover the wall-kick course"
```

Tell the user the course is in their uncommitted `levels/test_level.tscn`, alongside their own changes, for them to commit.

- [ ] **Step 6: Final user play check**

Ask the user to play the course and judge the wall kicks against `jump reference 1.mp4`. Apply their tuning feedback as in Task 4.
