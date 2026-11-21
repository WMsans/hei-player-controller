extends SceneTree
## Headless controller checks. Run:
## godot --headless --fixed-fps 120 --path . --script tests/test_player.gd

const PLAYER_SCENE := "res://player/player.tscn"
const NONE := Vector2.ZERO
const FORWARD := Vector2(0, 1)

var p: Node
var world: Node3D
var failures := 0
var current := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if not ResourceLoader.exists(PLAYER_SCENE):
		printerr("FAIL: missing ", PLAYER_SCENE)
		quit(1)
		return
	var count := 0
	for method in get_script().get_script_method_list():
		if not method.name.begins_with("test_"):
			continue
		current = method.name
		count += 1
		await _setup_world()
		await call(method.name)
		world.queue_free()
		await physics_frame
		await physics_frame
	print("%d tests, %d failed checks" % [count, failures])
	quit(1 if failures > 0 else 0)


func _setup_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	add_box(Vector3(0, -1, 0), Vector3(800, 2, 800))
	spawn(Vector3(0, 0.02, 0))
	await hold(0.05, NONE)


func spawn(at: Vector3) -> void:
	if p:
		p = null
	p = load(PLAYER_SCENE).instantiate()
	p.position = at
	world.add_child(p)
	p.set_scripted_input(NONE, false, false, false)


func respawn(at: Vector3) -> void:
	p.queue_free()
	spawn(at)
	await hold(0.05, NONE) # a spawn near the floor settles before the test acts


func add_box(center: Vector3, size: Vector3, rotation_x := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	body.rotation.x = rotation_x
	world.add_child(body)
	return body


func hold(seconds: float, move: Vector2, jump := false, dash := false, squat := false) -> void:
	p.set_scripted_input(move, jump, dash, squat)
	for i in maxi(1, roundi(seconds * Engine.physics_ticks_per_second)):
		await physics_frame


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL %s: %s" % [current, what])


func land(timeout := 3.0) -> void:
	var left := roundi(timeout * Engine.physics_ticks_per_second)
	while left > 0 and not p.is_on_floor():
		left -= 1
		await physics_frame


func peak_height(jump_seconds: float) -> float:
	var start: float = p.position.y
	var peak := start
	p.set_scripted_input(NONE, true, false, false)
	for i in roundi(jump_seconds * Engine.physics_ticks_per_second):
		await physics_frame
		peak = maxf(peak, p.position.y)
	p.set_scripted_input(NONE, false, false, false)
	for i in 240:
		await physics_frame
		peak = maxf(peak, p.position.y)
		if i > 2 and p.is_on_floor():
			break
	return peak - start


## Walks off a 5 m platform, waits, presses jump, returns vertical speed.
func coyote_jump_velocity(delay: float) -> float:
	add_box(Vector3(0, 4, 0), Vector3(10, 2, 10))
	await respawn(Vector3(0, 5.02, -4))
	p.set_scripted_input(FORWARD, false, false, false)
	for i in 240:
		await physics_frame
		if not p.is_on_floor():
			break
	await hold(delay, FORWARD)
	await hold(1.0 / 60.0, FORWARD, true)
	return p.velocity.y


## Drops from height and presses jump `lead` seconds before touchdown.
func buffered_jump_fired(lead: float) -> bool:
	var fired := [false]
	await respawn(Vector3(0, 6, 0))
	p.jumped.connect(func(_kind): fired[0] = true)
	for i in 480:
		await physics_frame
		if p.position.y <= -p.velocity.y * lead:
			break
	await hold(0.4, NONE, true)
	return fired[0]


func test_run_reaches_max_run() -> void:
	await hold(1.0, FORWARD)
	check(absf(p.horizontal_speed() - 7.5) < 0.01, "runs at 7.5, got %f" % p.horizontal_speed())
	check(p.velocity.z < 0.0, "forward is -Z")


func test_move_is_camera_relative() -> void:
	p.view_yaw = PI / 2.0
	await hold(0.5, FORWARD)
	check(p.velocity.x < -7.0, "yaw 90 turns forward to -X, got %s" % p.velocity)


func test_stops_when_input_released() -> void:
	await hold(0.5, FORWARD)
	await hold(0.5, NONE)
	check(p.horizontal_speed() < 0.01, "stops")


func test_jump_height_varies_with_hold() -> void:
	var tapped: float = await peak_height(0.02)
	await hold(0.1, NONE)
	var full: float = await peak_height(0.3)
	check(full > tapped + 0.5, "full %f vs tapped %f" % [full, tapped])


## Holds a full jump from the floor at `speed`, returns its rise, apex time, and airtime.
func jump_arc(speed: float) -> Dictionary:
	p.velocity = Vector3(0, 0, -speed)
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
	return {"rise": peak - start, "apex": apex_tick / 120.0, "air": ticks / 120.0}


func test_full_jump_hangs_like_the_clips() -> void:
	var arc: Dictionary = await jump_arc(25.0)
	check(absf(arc.rise - 4.6) < 0.3, "rises 4.6 m, got %f" % arc.rise)
	check(absf(arc.apex - 0.63) < 0.06, "apex at 0.63 s, got %f" % arc.apex)
	check(absf(arc.air - 1.22) < 0.1, "airtime 1.22 s, got %f" % arc.air)


func test_standing_jump_is_tight() -> void:
	var arc: Dictionary = await jump_arc(0.0)
	check(absf(arc.rise - 4.72) < 0.3, "rises 4.72 m, got %f" % arc.rise)
	check(absf(arc.apex - 0.46) < 0.05, "apex at 0.46 s, got %f" % arc.apex)
	check(absf(arc.air - 0.88) < 0.08, "airtime 0.88 s, got %f" % arc.air)


func test_run_speed_jump_is_tight() -> void:
	var arc: Dictionary = await jump_arc(7.5)
	check(absf(arc.air - 0.88) < 0.08, "airtime 0.88 s, got %f" % arc.air)


func test_mid_speed_jump_blends_toward_hang() -> void:
	var arc: Dictionary = await jump_arc(16.0)
	check(arc.air > 0.92 and arc.air < 1.18, "between tight and hang, got %f" % arc.air)


func test_coyote_jump() -> void:
	check(await coyote_jump_velocity(0.05) > 0.0, "jump 0.05 s after leaving ledge")


func test_coyote_expires() -> void:
	check(await coyote_jump_velocity(0.2) < 0.0, "no jump 0.2 s after leaving ledge")


func test_jump_buffer() -> void:
	check(await buffered_jump_fired(0.05), "space 0.05 s before landing jumps")


func test_jump_buffer_expires() -> void:
	check(not await buffered_jump_fired(0.25), "space 0.25 s before landing is ignored")


func count_dashes() -> Array:
	var dashes := [0]
	p.dash_started.connect(func(_direction): dashes[0] += 1)
	return dashes


## Jumps, releases Space, and waits until clearly airborne.
func get_airborne() -> void:
	await hold(0.05, NONE, true)
	await hold(0.05, NONE)


func test_aim_table() -> void:
	var f := Vector3.FORWARD
	var diagonal := sqrt(0.5)
	check(p.dash_direction(f, false, false).is_equal_approx(f), "flat")
	check(p.dash_direction(f, true, false).is_equal_approx(Vector3(0, diagonal, -diagonal)), "up diagonal")
	check(p.dash_direction(f, false, true).is_equal_approx(Vector3(0, -diagonal, -diagonal)), "down diagonal")
	check(p.dash_direction(Vector3.ZERO, true, false).is_equal_approx(Vector3.UP), "straight up")
	check(p.dash_direction(Vector3.ZERO, false, true).is_equal_approx(Vector3.DOWN), "straight down")
	check(p.dash_direction(f, true, true).is_equal_approx(f), "both cancel")
	check(p.dash_direction(Vector3.ZERO, false, false).is_equal_approx(p.facing), "nothing uses facing")


func test_standstill_dash_goes_along_facing() -> void: # Review Focus 5
	await hold(0.05, NONE, false, true)
	check(p.velocity.is_finite(), "finite velocity")
	check(p.velocity.dot(p.facing) > 15.0, "dashes along facing, got %s" % p.velocity)


func test_one_air_dash_per_airtime() -> void:
	await respawn(Vector3(0, 12, 0))
	var dashes := count_dashes()
	await hold(0.05, FORWARD, false, true)
	await hold(0.25, FORWARD)
	await hold(0.05, FORWARD, false, true)
	check(dashes[0] == 1, "dashed %d times" % dashes[0])


func test_landing_refills_air_dash() -> void:
	await get_airborne()
	await hold(0.05, FORWARD, false, true)
	check(not p.dash_available, "air dash spent")
	await hold(0.3, NONE)
	await land()
	await hold(0.02, NONE)
	check(p.dash_available, "refilled on landing")


func test_held_shift_does_not_extend_air_dash() -> void:
	await get_airborne()
	await hold(0.25, FORWARD, false, true) # 0.05 freeze + 0.15 burst + margin
	check(p.state != p.State.DASH, "burst ended with Shift held")


func test_space_held_aims_air_dash_up() -> void:
	await hold(0.08, NONE, true)
	await hold(0.04, FORWARD, true, true)
	check(p.velocity.y > 12.0, "aims up, got %f" % p.velocity.y)


func test_space_mid_dash_reaims_up() -> void:
	await get_airborne()
	var before: float = p.velocity.y
	await hold(0.03, FORWARD, false, true)
	check(p.velocity.y <= before + 0.01, "starts flat, got %f" % p.velocity.y)
	await hold(0.04, FORWARD, true, true) # lands after the 0.05 freeze
	check(p.velocity.y > before + 5.0, "re-aimed up, got %f" % p.velocity.y)


func test_landing_with_shift_enters_dash_run_at_carried_speed() -> void:
	await respawn(Vector3(0, 1.5, 0))
	p.velocity = Vector3(0, 0, -30)
	await hold(0.2, FORWARD, false, true)
	await land()
	await hold(0.02, FORWARD, false, true)
	check(p.state == p.State.DASH_RUN, "in dash-run, state %d" % p.state)
	check(p.horizontal_speed() > 20.0, "kept speed, got %f" % p.horizontal_speed())


func test_dash_run_sustains_while_held() -> void:
	await hold(1.0, FORWARD, false, true)
	check(p.state == p.State.DASH_RUN, "still dash-running")
	check(absf(p.horizontal_speed() - 13.3) < 0.1, "at 13.3, got %f" % p.horizontal_speed())


func test_releasing_shift_leaves_dash_run() -> void:
	await hold(0.5, FORWARD, false, true)
	await hold(1.0, FORWARD)
	check(p.state == p.State.NORMAL, "normal movement")
	check(absf(p.horizontal_speed() - 7.5) < 0.1, "back to run speed, got %f" % p.horizontal_speed())


func test_ground_burst_needs_fresh_shift() -> void:
	var dashes := count_dashes()
	await hold(0.4, FORWARD, false, true)
	await hold(0.1, NONE, false, true)
	await hold(0.2, FORWARD, false, true)
	check(dashes[0] == 1, "one burst, got %d" % dashes[0])
	check(p.state == p.State.DASH_RUN, "resumed dash-run")


func test_dash_cooldown_blocks_retrigger() -> void:
	var dashes := count_dashes()
	await hold(0.05, FORWARD, false, true)
	await hold(0.02, FORWARD)
	await hold(0.02, FORWARD, false, true)
	await hold(0.08, FORWARD)
	check(dashes[0] == 1, "blocked during cooldown, got %d" % dashes[0])
	await hold(0.2, FORWARD)
	await hold(0.02, FORWARD, false, true)
	check(dashes[0] == 2, "allowed after cooldown, got %d" % dashes[0])


func test_ground_shift_space_consumes_air_dash() -> void:
	await hold(0.04, FORWARD, true, true)
	check(not p.dash_available, "air dash consumed")
	check(p.velocity.y > 12.0, "launched up, got %f" % p.velocity.y)


func test_dash_into_wall_stops_cleanly() -> void: # Review Focus 1
	var wall := add_box(Vector3(0, 5, -2), Vector3(20, 10, 1))
	await hold(0.15, FORWARD, false, true)
	check(p.horizontal_speed() < 1.0, "stopped by wall, got %f" % p.horizontal_speed())
	wall.queue_free()
	await hold(0.1, NONE)
	check(p.horizontal_speed() < 1.0, "old speed not restored, got %f" % p.horizontal_speed())


func test_ceiling_cancels_up_dash() -> void: # Review Focus 2
	add_box(Vector3(0, 3.5, 0), Vector3(20, 1, 20))
	await hold(0.2, NONE, true, true)
	check(p.state != p.State.DASH, "dash ended at ceiling")
	check(p.velocity.y <= 0.0, "falling, got %f" % p.velocity.y)


func record_jumps() -> Array:
	var kinds := []
	p.jumped.connect(func(kind): kinds.append(kind))
	return kinds


## Launches from a ground dash and returns the height reached.
func launch_peak(squat: bool) -> float:
	await hold(0.08, FORWARD, false, true, squat)
	var start: float = p.position.y
	var peak := start
	p.set_scripted_input(FORWARD, true, true, squat)
	for i in 120:
		await physics_frame
		peak = maxf(peak, p.position.y)
	return peak - start


## Down-dashes from a height, keeps Ctrl, returns the jump kind Space gives on the floor.
func landing_jump_kind(height: float) -> StringName:
	await respawn(Vector3(0, height, 0))
	var kinds := record_jumps()
	await hold(0.03, FORWARD, false, true, true)
	p.set_scripted_input(FORWARD, false, false, true)
	await land()
	await hold(0.02, FORWARD, false, false, true)
	await hold(0.02, FORWARD, true, false, true)
	return kinds[0] if not kinds.is_empty() else &"none"


func wavedash() -> void:
	await respawn(Vector3(0, 1.8, 0))
	await hold(0.03, FORWARD, false, true, true)
	p.set_scripted_input(FORWARD, false, false, true)
	await land()
	await hold(0.01, FORWARD, false, false, true)


func test_super_exceeds_dash_run() -> void:
	var kinds := record_jumps()
	await hold(0.3, FORWARD, false, true)
	await hold(0.02, FORWARD, true, true)
	check(kinds == [&"super"], "super fired, got %s" % [kinds])
	check(absf(p.horizontal_speed() - 21.7) < 0.5, "at 21.7, got %f" % p.horizontal_speed())


func test_hyper_faster_than_super() -> void:
	var kinds := record_jumps()
	await hold(0.12, FORWARD, false, true, true) # slide friction brings it under super speed
	await hold(0.02, FORWARD, true, true, true)
	check(kinds == [&"hyper"], "hyper fired, got %s" % [kinds])
	check(absf(p.horizontal_speed() - 27.125) < 0.5, "at 27.1, got %f" % p.horizontal_speed())


func test_hyper_lower_than_super() -> void:
	var super_peak: float = await launch_peak(false)
	await respawn(Vector3(0, 0.02, 0))
	var hyper_peak: float = await launch_peak(true)
	check(hyper_peak < super_peak - 0.3, "hyper %f vs super %f" % [hyper_peak, super_peak])


func test_wavedash_refills_dash() -> void:
	await wavedash()
	check(p.state == p.State.SLIDE, "sliding, state %d" % p.state)
	check(p.dash_available, "dash refilled")
	check(p.horizontal_speed() > 15.0, "slide speed, got %f" % p.horizontal_speed())


func test_wavedash_grace_window() -> void:
	var near: StringName = await landing_jump_kind(3.0)
	check(near == &"hyper", "landing just after burst, got %s" % near)
	var far: StringName = await landing_jump_kind(7.0)
	check(far == &"jump", "landing long after burst, got %s" % far)


func test_early_space_in_down_dash_fires_hyper() -> void:
	await respawn(Vector3(0, 1.8, 0))
	var kinds := record_jumps()
	await hold(0.02, FORWARD, false, true, true)
	await hold(0.03, FORWARD, true, true, true)
	check(p.velocity.y < 0.0 or not kinds.is_empty(), "Space did not re-aim up")
	p.set_scripted_input(FORWARD, true, false, true)
	await land()
	await hold(0.02, FORWARD, true, false, true)
	check(kinds == [&"hyper"], "hyper on landing, got %s" % [kinds])


func test_straight_down_dash_without_wasd_is_plain_landing() -> void:
	await respawn(Vector3(0, 1.8, 0))
	await hold(0.03, NONE, false, true, true)
	p.set_scripted_input(NONE, false, false, false)
	await land()
	await hold(0.02, NONE)
	check(p.state == p.State.NORMAL, "normal landing, state %d" % p.state)
	check(p.dash_available, "dash refilled")


func test_slide_stops_quickly() -> void:
	await wavedash()
	await hold(0.4, NONE, false, false, true)
	check(p.horizontal_speed() < 0.1, "stopped, got %f" % p.horizontal_speed())


func test_hyper_from_nearly_stopped_slide_is_full_power() -> void:
	await wavedash()
	await hold(0.18, NONE, false, false, true)
	check(p.horizontal_speed() < 5.0, "nearly stopped, got %f" % p.horizontal_speed())
	await hold(0.02, FORWARD, true, false, true)
	check(p.horizontal_speed() > 26.5, "full hyper, got %f" % p.horizontal_speed())


func test_plain_squat_never_hypers() -> void:
	var kinds := record_jumps()
	await hold(0.2, FORWARD, false, false, true)
	await hold(0.02, FORWARD, true, false, true)
	check(kinds == [&"jump"], "plain jump, got %s" % [kinds])
	check(p.horizontal_speed() < 8.0, "no boost, got %f" % p.horizontal_speed())


func test_rested_slide_loses_hyper() -> void:
	await wavedash()
	var kinds := record_jumps()
	await hold(1.0, NONE, false, false, true)
	await hold(0.02, NONE, true, false, true)
	check(kinds == [&"jump"], "plain jump after resting, got %s" % [kinds])


func test_chained_speed_never_exceeds_max() -> void:
	var fastest := 0.0
	await hold(0.08, FORWARD, false, true, true)
	for chain in 12: # tap Space just before each landing so it buffers into the next hyper
		await hold(0.02, FORWARD, true, true, true)
		p.set_scripted_input(FORWARD, false, true, true)
		for i in 240:
			await physics_frame
			fastest = maxf(fastest, p.horizontal_speed())
			if p.velocity.y < 0.0 and p.position.y < 0.3:
				break
	check(fastest > 35.0, "chain passes the soft limit, got %f" % fastest)
	check(fastest <= 60.001, "capped at 60, got %f" % fastest)


func test_coyote_super_off_ledge() -> void: # Review Focus 3
	add_box(Vector3(0, 4, 0), Vector3(10, 2, 10))
	await respawn(Vector3(0, 5.02, 4))
	var kinds := record_jumps()
	p.set_scripted_input(FORWARD, false, true, false)
	for i in 240:
		await physics_frame
		if not p.is_on_floor():
			break
	await hold(0.03, FORWARD, false, true)
	await hold(0.02, FORWARD, true, true)
	check(kinds == [&"super"], "super after ledge, got %s" % [kinds])
	check(p.dash_available, "air dash still available")


func test_wavedash_on_slope_keeps_speed() -> void: # Review Focus 4
	add_box(Vector3(0, 5, 0), Vector3(80, 1, 80), deg_to_rad(20.0))
	await respawn(Vector3(0, 8, 0))
	await hold(0.03, FORWARD, false, true, true)
	p.set_scripted_input(FORWARD, false, false, true)
	await land()
	await hold(0.02, FORWARD, false, false, true)
	check(p.state == p.State.SLIDE, "slides on slope, state %d" % p.state)
	check(p.is_on_floor(), "stays on slope")
	check(p.horizontal_speed() > 10.0, "keeps speed, got %f" % p.horizontal_speed())


## Places Hei high in the air moving forward at `speed`, with no input.
func fly(speed: float) -> void:
	await respawn(Vector3(0, 60, 0))
	p.velocity = Vector3(0, 0, -speed)


func test_air_steer_keeps_speed() -> void:
	await fly(21.7)
	await hold(0.3, Vector2(1, 0))
	check(p.velocity.x > 10.0, "turned toward input, got %s" % p.velocity)
	check(p.horizontal_speed() > 14.5, "kept speed, got %f" % p.horizontal_speed())


func test_no_input_keeps_air_momentum() -> void:
	await fly(21.7)
	await hold(0.2, NONE)
	check(p.horizontal_speed() > 17.0, "momentum kept, got %f" % p.horizontal_speed())


func test_opposite_input_brakes() -> void:
	await fly(21.7)
	await hold(0.1, Vector2(0, -1))
	check(p.horizontal_speed() < 17.5, "brakes, got %f" % p.horizontal_speed())
	check(p.velocity.z < 0.0, "does not rotate around")


func test_brake_stops_quickly() -> void:
	await fly(27.0)
	await hold(0.35, NONE, false, false, true)
	check(p.is_air_braking, "braking")
	check(p.horizontal_speed() < 0.1, "stopped, got %f" % p.horizontal_speed())


func test_brake_faster_than_no_input() -> void:
	await fly(27.0)
	await hold(0.15, NONE)
	var coasting: float = p.horizontal_speed()
	await fly(27.0)
	await hold(0.15, NONE, false, false, true)
	check(p.horizontal_speed() < coasting - 8.0, "brake %f vs coast %f" % [p.horizontal_speed(), coasting])


func test_brake_falls_faster() -> void:
	await fly(0.0)
	await hold(1.0, NONE)
	check(absf(p.velocity.y + 20.0) < 0.01, "normal max fall, got %f" % p.velocity.y)
	await hold(1.0, NONE, false, false, true)
	check(absf(p.velocity.y + 30.0) < 0.01, "fast max fall, got %f" % p.velocity.y)


func test_brake_cuts_rising_jump() -> void:
	await hold(0.05, NONE, true)
	await hold(0.1, NONE, true, false, true)
	check(p.velocity.y < 12.0 - 2.0, "brake overrides held jump, got %f" % p.velocity.y)


func test_ctrl_through_hyper_does_not_brake() -> void:
	await hold(0.08, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	await hold(0.08, FORWARD, true, true, true)
	check(not p.is_on_floor(), "airborne")
	check(not p.is_air_braking, "held Ctrl does not brake")
	check(p.horizontal_speed() > 24.0, "kept hyper speed, got %f" % p.horizontal_speed())


func test_ctrl_after_down_dash_needs_repress() -> void:
	await respawn(Vector3(0, 60, 0))
	await hold(0.25, FORWARD, false, true, true)
	check(p.state == p.State.NORMAL, "burst over")
	check(not p.is_air_braking, "Ctrl held through dash does not brake")
	await hold(0.02, FORWARD, false, true, false)
	await hold(0.02, FORWARD, false, true, true)
	check(p.is_air_braking, "fresh press brakes")


func test_brake_ignores_wasd() -> void:
	await fly(0.0)
	await hold(0.1, FORWARD, false, false, true)
	check(p.horizontal_speed() < 0.01, "WASD adds nothing, got %f" % p.horizontal_speed())


func test_brake_into_down_dash() -> void:
	await fly(10.0)
	await hold(0.05, FORWARD, false, false, true)
	await hold(0.02, FORWARD, false, true, true)
	check(p.state == p.State.DASH, "dashing")
	check(p.velocity.y < -12.0, "dash aims down, got %f" % p.velocity.y)


func test_hit_freeze_holds_position_for_50ms() -> void:
	var start: Vector3 = p.position
	await hold(0.03, FORWARD, false, true)
	check(p.position.distance_to(start) < 0.001, "frozen, moved %f" % p.position.distance_to(start))
	await hold(0.06, FORWARD, false, true)
	check(p.position.distance_to(start) > 0.2, "moves after freeze, moved %f" % p.position.distance_to(start))


func test_space_during_freeze_is_not_lost() -> void:
	var kinds := record_jumps()
	await hold(0.02, FORWARD, false, true)
	await hold(0.01, FORWARD, true, true)
	await hold(0.08, FORWARD, false, true)
	check(kinds == [&"super"], "super after freeze, got %s" % [kinds])


func test_juice_stretches_visual_not_collider() -> void:
	var visual: Node3D = p.get_node("Visual")
	await hold(0.02, NONE, true)
	check(visual.scale.y > 1.15, "stretched on jump, got %s" % visual.scale)
	check(p.get_node("CollisionShape3D").scale == Vector3.ONE, "collider unscaled")
	await hold(0.1, NONE)
	await land()
	await hold(0.02, NONE)
	check(visual.scale.y < 1.0, "squashed on landing, got %s" % visual.scale)
	check(p.get_node("CollisionShape3D").scale == Vector3.ONE, "collider unscaled")
	await hold(0.6, NONE)
	check(visual.scale.distance_to(Vector3.ONE) < 0.01, "recovers, got %s" % visual.scale)


func test_spent_dash_changes_capsule_color() -> void:
	var mesh: MeshInstance3D = p.get_node("Visual/Mesh")
	await hold(0.02, NONE)
	var ready_color: Color = mesh.get_surface_override_material(0).albedo_color
	await respawn(Vector3(0, 30, 0))
	mesh = p.get_node("Visual/Mesh")
	await hold(0.1, FORWARD, false, true)
	var spent_color: Color = mesh.get_surface_override_material(0).albedo_color
	check(not ready_color.is_equal_approx(spent_color), "color changes when dash is spent")


func on_ramp(height_above_center: float) -> void:
	add_box(Vector3(0, 5, 0), Vector3(80, 1, 80), deg_to_rad(20.0))
	await respawn(Vector3(0, 5 + height_above_center, 0))


func test_hyper_launches_off_uphill_slope() -> void:
	await on_ramp(0.7)
	await land()
	await hold(0.1, NONE)
	await hold(0.1, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	await hold(0.1, FORWARD, true, true, true)
	check(not p.is_on_floor(), "left the ramp")
	check(p.horizontal_speed() > 24.0, "kept hyper speed, got %f" % p.horizontal_speed())


func test_fresh_ctrl_during_flat_air_dash_brakes() -> void:
	await fly(0.0)
	await hold(0.1, FORWARD, false, true)
	await hold(0.2, FORWARD, false, false, true)
	check(p.state != p.State.DASH, "burst over")
	check(p.is_air_braking, "Ctrl pressed mid-dash brakes after it")


func test_early_space_on_straight_down_dash_fires_hyper() -> void:
	await respawn(Vector3(0, 1.8, 0))
	var kinds := record_jumps()
	await hold(0.02, NONE, false, true, true)
	await hold(0.06, NONE, true, true, true)
	p.set_scripted_input(NONE, true, false, true)
	await land()
	await hold(0.02, NONE, true, false, true)
	check(kinds == [&"hyper"], "hyper on landing, got %s" % [kinds])


func test_ground_burst_off_ledge_gets_no_free_up_dash() -> void:
	add_box(Vector3(0, 4, 0), Vector3(10, 2, 10))
	await respawn(Vector3(0, 5.02, -4.8))
	p.set_scripted_input(FORWARD, false, true, false)
	for i in 120:
		await physics_frame
		if not p.is_on_floor():
			break
	await hold(0.105, FORWARD, false, true)
	check(p.state == p.State.DASH, "still in burst")
	await hold(0.02, FORWARD, true, true)
	check(p.velocity.y < 1.0, "Space does not re-aim, got %f" % p.velocity.y)


func test_reaim_keeps_carried_speed() -> void:
	await fly(32.0)
	await hold(0.08, FORWARD, false, true)
	await hold(0.02, FORWARD, true, true)
	check(p.velocity.y > 12.0, "re-aimed up, got %f" % p.velocity.y)
	check(p.horizontal_speed() > 31.5, "kept speed, got %f" % p.horizontal_speed())


func test_flat_air_dash_into_ramp_can_super() -> void:
	await on_ramp(1.0)
	var kinds := record_jumps()
	p.set_scripted_input(FORWARD, false, true, false)
	for i in 60:
		await physics_frame
		if p.is_on_floor():
			break
	check(p.state == p.State.DASH, "contact during burst")
	await hold(0.02, FORWARD, true, true)
	check(kinds == [&"super"], "super on contact, got %s" % [kinds])


func test_falling_out_returns_to_spawn() -> void:
	var spawn_point: Vector3 = p.position
	p.position = Vector3(50, -100, 50)
	p.velocity = Vector3(5, -13, 5)
	await hold(0.05, NONE)
	check(p.position.distance_to(spawn_point) < 0.5, "back at spawn, got %s" % p.position)
	check(p.velocity.length() < 2.0, "velocity cleared, got %s" % p.velocity)


func test_mouse_look_ignores_window_scale() -> void:
	var rig: Node = p.get_node("CameraRig")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50, 0)
	motion.screen_relative = Vector2(100, 0)
	rig.apply_look(motion)
	check(absf(p.view_yaw + 0.25) < 0.0001, "uses screen motion, got %f" % p.view_yaw)


func test_forgiveness_timers_are_tunable() -> void:
	var exported := []
	for property in p.get_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR:
			exported.append(property.name)
	for name in ["coyote_time", "jump_buffer_time", "dash_buffer_time", "dash_cooldown", "wavedash_grace", "hyper_rest_grace"]:
		check(name in exported, "%s is exported" % name)


func test_soft_limit_pulls_back_without_input() -> void:
	await fly(50.0)
	await hold(0.5, NONE)
	check(absf(p.horizontal_speed() - 46.0) < 0.4, "gentle pull-back, got %f" % p.horizontal_speed())


func test_soft_limit_pulls_back_with_wasd() -> void:
	await fly(50.0)
	await hold(0.5, FORWARD)
	check(absf(p.horizontal_speed() - 46.0) < 0.4, "gentle pull-back, got %f" % p.horizontal_speed())


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


func test_sideways_dash_keeps_forward_speed() -> void:
	await fly(15.0)
	await hold(0.07, Vector2(1, 0), false, true)
	check(absf(p.velocity.x - 20.0) < 0.5, "adds sideways, got %s" % p.velocity)
	check(absf(p.velocity.z + 15.0) < 0.5, "keeps forward, got %s" % p.velocity)


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
	await fly(5.0)
	await hold(0.25, FORWARD, false, true)
	check(p.state != p.State.DASH, "burst over")
	check(p.horizontal_speed() > 24.0, "no end trim, got %f" % p.horizontal_speed())


func test_plain_dash_stops_adding_at_dash_limit() -> void:
	await fly(20.0)
	await hold(0.07, FORWARD, false, true)
	check(absf(p.horizontal_speed() - 28.0) < 0.1, "got %f" % p.horizontal_speed())


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


func test_dash_and_hop_loop_stays_at_dash_limit() -> void:
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
	check(fastest > 25.0, "loop is fast, got %f" % fastest)
	check(fastest <= 28.001, "loop stays at 28, got %f" % fastest)


func test_low_slide_multiplies_only_added_speed() -> void:
	p.velocity = Vector3(0, 0, -3)
	await hold(0.02, FORWARD, false, true, true)
	check(absf(p.horizontal_speed() - 27.0) < 0.5, "3 + 20 * 1.2, got %f" % p.horizontal_speed())


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


## From a fresh launch, holds Space, then does an up-forward dash.
func dash_after_launch() -> float:
	await hold(0.2, FORWARD, true)
	await hold(0.1, FORWARD, true, true)
	return p.horizontal_speed()


func test_super_dash_reaches_plain_limit() -> void:
	await hold(0.08, FORWARD, false, true)
	await hold(0.02, FORWARD, true, true)
	var speed: float = await dash_after_launch()
	check(absf(speed - 28.0) < 0.2, "super route stops at 28, got %f" % speed)


func test_hyper_dash_reaches_hyper_limit() -> void:
	await hold(0.08, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	var speed: float = await dash_after_launch()
	check(absf(speed - 42.0) < 0.5, "hyper route reaches 42, got %f" % speed)


func test_wavedash_hyper_launches_faster() -> void:
	await wavedash()
	await hold(0.02, FORWARD, true, false, true)
	check(absf(p.horizontal_speed() - 32.55) < 0.5, "20%% wave bonus, got %f" % p.horizontal_speed())


func test_wavedash_hyper_dash_passes_hyper_limit() -> void:
	await wavedash()
	await hold(0.02, FORWARD, true, false, true)
	var speed: float = await dash_after_launch()
	check(absf(speed - 46.5) < 0.7, "wave route reaches 46.5, got %f" % speed)


func test_wave_bonus_ends_with_the_slide() -> void:
	await wavedash()
	await hold(2.0, NONE)
	check(p.horizontal_speed() < 0.01, "stopped first, got %f" % p.horizontal_speed())
	await hold(0.12, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	check(absf(p.horizontal_speed() - 27.125) < 0.5, "plain hyper, got %f" % p.horizontal_speed())


func test_landing_resets_dash_limit() -> void:
	await hold(0.08, FORWARD, false, true, true)
	await hold(0.02, FORWARD, true, true, true)
	check(p._dash_limit == p.hyper_dash_limit, "hyper limit in flight, got %f" % p._dash_limit)
	await hold(0.05, FORWARD)
	await land()
	await hold(0.01, FORWARD)
	check(p._dash_limit == p.dash_limit, "plain limit after landing, got %f" % p._dash_limit)


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


func test_level_has_wall_kick_course() -> void:
	var level: Node = load("res://levels/test_level.tscn").instantiate()
	for node_name in ["KickFloor", "KickWallL", "KickWallR", "KickPillarA", "KickPillarB", "KickPillarC"]:
		var box := level.get_node_or_null("Geometry/" + node_name) as CSGBox3D
		check(box != null, "%s exists" % node_name)
		if box:
			check(box.use_collision, "%s collides" % node_name)
	level.free()
