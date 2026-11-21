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
	await hold(0.2, FORWARD, false, true)
	check(p.state != p.State.DASH, "burst ended with Shift held")


func test_space_held_aims_air_dash_up() -> void:
	await hold(0.08, NONE, true)
	await hold(0.04, FORWARD, true, true)
	check(p.velocity.y > 12.0, "aims up, got %f" % p.velocity.y)


func test_space_mid_dash_reaims_up() -> void:
	await get_airborne()
	await hold(0.03, FORWARD, false, true)
	check(p.velocity.y < 1.0, "starts flat, got %f" % p.velocity.y)
	await hold(0.02, FORWARD, true, true)
	check(p.velocity.y > 12.0, "re-aimed up, got %f" % p.velocity.y)


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
	await hold(0.1, FORWARD, false, true)
	check(p.horizontal_speed() < 1.0, "stopped by wall, got %f" % p.horizontal_speed())
	wall.queue_free()
	await hold(0.1, NONE)
	check(p.horizontal_speed() < 1.0, "old speed not restored, got %f" % p.horizontal_speed())


func test_ceiling_cancels_up_dash() -> void: # Review Focus 2
	add_box(Vector3(0, 3.5, 0), Vector3(20, 1, 20))
	await hold(0.12, NONE, true, true)
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
	await hold(0.08, FORWARD, false, true, true)
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
	check(fastest > 30.0, "chain builds speed, got %f" % fastest)
	check(fastest <= 35.001, "capped at 35, got %f" % fastest)


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
