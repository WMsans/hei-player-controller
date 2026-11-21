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
	await hold(0.02, NONE)


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
