class_name Player
extends CharacterBody3D
## Celeste-style 3D controller. Values start from Celeste at 12 px = 1 m.

signal jumped(kind: StringName)
signal landed(impact_speed: float)
signal dash_started(direction: Vector3)

enum State { NORMAL, DASH, DASH_RUN, SLIDE }

@export_group("Run")
@export var max_run := 7.5
@export var run_accel := 83.0
@export var run_reduce := 33.0
@export var air_mult := 0.65
@export var soft_speed := 35.0
@export var max_speed := 60.0
@export var air_drag := 1.0
@export var ground_bleed := 10.8

@export_group("Gravity")
@export var gravity := 36.0
@export var max_fall := 20.0
@export var fast_max_fall := 30.0
@export var half_grav_threshold := 3.3

@export_group("Jump")
@export var jump_speed := 12.0
@export var jump_h_boost := 3.3
@export var var_jump_time := 0.2

@export_group("Dash")
@export var dash_speed := 20.0
@export var dash_run_speed := 13.3
@export var dash_time := 0.15
@export var end_dash_up_mult := 0.75
@export var hit_freeze_time := 0.05

@export_group("Super")
@export var super_jump_h := 21.7
@export var hyper_h_mult := 1.25
@export var hyper_v_mult := 0.5
@export var slide_mult := 1.2
@export var duck_friction := 80.0

@export_group("Air")
@export var air_turn_rate := 270.0
@export var air_brake_decel := 150.0
@export var air_brake_gravity_mult := 3.0

@export_group("Forgiveness")
@export var coyote_time := 0.1
@export var jump_buffer_time := 0.1
@export var dash_buffer_time := 0.08
@export var dash_cooldown := 0.2
@export var wavedash_grace := 0.1
@export var hyper_rest_grace := 0.15

@export_group("Level")
@export var kill_y := -30.0

var state := State.NORMAL
var facing := Vector3.FORWARD
var view_yaw := 0.0
var dash_available := true
var is_air_braking := false

var _scripted := false
var _script_move := Vector2.ZERO
var _script_jump := false
var _script_dash := false
var _script_squat := false

var _move := Vector3.ZERO
var _jump_down := false
var _jump_pressed := false
var _dash_down := false
var _dash_pressed := false
var _squat_down := false
var _squat_pressed := false

var _coyote := 0.0
var _jump_buffer := 0.0
var _var_jump := 0.0
var _var_jump_speed := 0.0
var _dash_buffer := 0.0
var _dash_cooldown := 0.0
var _dash_timer := 0.0
var _dash_dir := Vector3.FORWARD
var _dash_keep := 0.0
var _dash_grounded := false
var _coyote_kind := &"jump"
var _wave_window := 0.0
var _wave_jump := false
var _can_hyper := false
var _hyper_rest := 0.0
var _brake_armed := false
var _freeze := 0.0
var _spawn_point := Vector3.ZERO
var _pending_jump := false
var _pending_dash := false
var _pending_squat := false


## Unit dash direction: WASD horizontal, Space up, Ctrl down, both cancel.
func dash_direction(move_world: Vector3, up: bool, down: bool) -> Vector3:
	var horizontal := move_world.normalized()
	var vertical := float(up) - float(down)
	if horizontal == Vector3.ZERO and vertical == 0.0:
		return facing
	return (horizontal + Vector3.UP * vertical).normalized()


func set_scripted_input(move: Vector2, jump: bool, dash: bool, squat: bool) -> void:
	_scripted = true
	_script_move = move
	_script_jump = jump
	_script_dash = dash
	_script_squat = squat


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _ready() -> void:
	_spawn_point = global_position


func _return_to_spawn() -> void:
	global_position = _spawn_point
	velocity = Vector3.ZERO
	state = State.NORMAL
	dash_available = true
	is_air_braking = false
	_brake_armed = false
	_coyote = 0.0
	_jump_buffer = 0.0
	_dash_buffer = 0.0
	_var_jump = 0.0
	_wave_window = 0.0
	_wave_jump = false
	_freeze = 0.0
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	_sample_input()
	if _freeze > 0.0:
		# Hit-freeze pauses the simulation but keeps presses for when it ends.
		_freeze -= delta
		_pending_jump = _pending_jump or _jump_pressed
		_pending_dash = _pending_dash or _dash_pressed
		_pending_squat = _pending_squat or _squat_pressed
		return
	_jump_pressed = _jump_pressed or _pending_jump
	_dash_pressed = _dash_pressed or _pending_dash
	_squat_pressed = _squat_pressed or _pending_squat
	_pending_jump = false
	_pending_dash = false
	_pending_squat = false

	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_dash_buffer = maxf(_dash_buffer - delta, 0.0)
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	if _jump_pressed:
		_jump_buffer = jump_buffer_time
	if _dash_pressed:
		_dash_buffer = dash_buffer_time
	_wave_window = maxf(_wave_window - delta, 0.0)
	if _wave_window <= 0.0:
		_wave_jump = false
	elif _jump_pressed and _squat_down:
		_wave_jump = true

	var was_on_floor := is_on_floor()
	if was_on_floor:
		_coyote = coyote_time
		if _wave_window > 0.0:
			_land_wavedash()
		if state != State.DASH:
			dash_available = true

	if _dash_buffer > 0.0 and _dash_cooldown <= 0.0 and (was_on_floor or dash_available):
		_start_dash()
		if _freeze > 0.0:
			return

	# The brake needs a fresh Ctrl press in the air, so held Ctrl never cuts a hyper.
	if was_on_floor or not _squat_down or (state == State.DASH and _dash_dir.y < 0.0):
		_brake_armed = false
	elif _squat_pressed:
		_brake_armed = true
	is_air_braking = _brake_armed and state != State.DASH

	match state:
		State.DASH:
			_update_dash(delta)
		State.DASH_RUN:
			_update_dash_run(delta)
		State.SLIDE:
			_update_slide(delta)
		_:
			_update_normal(delta)

	if was_on_floor and _coyote > 0.0:
		_coyote_kind = _ground_jump_kind()
	var capped := Vector2(velocity.x, velocity.z).limit_length(max_speed)
	velocity.x = capped.x
	velocity.z = capped.y

	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_ceiling():
		_var_jump = 0.0
	if is_on_floor() and not was_on_floor:
		landed.emit(fall_speed)
	if global_position.y < kill_y:
		_return_to_spawn()


func _sample_input() -> void:
	var move := _script_move
	var jump := _script_jump
	var dash := _script_dash
	var squat := _script_squat
	if not _scripted:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		jump = Input.is_action_pressed("jump")
		dash = Input.is_action_pressed("dash")
		squat = Input.is_action_pressed("squat")
	_move = Vector3(move.x, 0.0, -move.y).limit_length().rotated(Vector3.UP, view_yaw)
	if _move.length_squared() > 0.0001:
		facing = _move.normalized()
	_jump_pressed = jump and not _jump_down
	_dash_pressed = dash and not _dash_down
	_squat_pressed = squat and not _squat_down
	_jump_down = jump
	_dash_down = dash
	_squat_down = squat


func _update_normal(delta: float) -> void:
	if is_on_floor() and _coyote > 0.0:
		if _dash_down and _move != Vector3.ZERO:
			state = State.DASH_RUN
			_update_dash_run(delta)
			return
		if _squat_down:
			_enter_slide(false)
			_update_slide(delta)
			return
	_try_jump()
	if is_on_floor() and _coyote > 0.0:
		_apply_run(delta)
	else:
		_apply_air(delta)
	_apply_gravity(delta)


func _apply_air(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	if is_air_braking:
		horizontal = horizontal.move_toward(Vector3.ZERO, air_brake_decel * delta)
	elif _move == Vector3.ZERO:
		horizontal = horizontal.normalized() * _decay(speed, 0.0, air_drag, run_reduce * air_mult, delta)
	elif speed <= max_run:
		horizontal = horizontal.move_toward(_move * max_run, run_accel * air_mult * delta)
	elif horizontal.normalized().dot(_move.normalized()) < -0.5:
		horizontal = horizontal.move_toward(_move * max_run, run_accel * air_mult * delta)
	else:
		horizontal = _steer(horizontal, delta)
		horizontal = horizontal.normalized() * _decay(speed, max_run, air_drag, run_reduce * air_mult, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Moves speed toward target: pull_rate above soft_speed, slow_rate below it.
func _decay(speed: float, target: float, slow_rate: float, pull_rate: float, delta: float) -> float:
	if speed > soft_speed:
		return maxf(speed - pull_rate * delta, maxf(soft_speed, target))
	return move_toward(speed, target, slow_rate * delta)


func _start_dash() -> void:
	var grounded := is_on_floor()
	var direction := dash_direction(_move, _jump_down, _squat_down)
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	_dash_keep = maxf(horizontal.dot(flat_direction), 0.0)
	_dash_buffer = 0.0
	_dash_cooldown = dash_cooldown
	_var_jump = 0.0
	_freeze = hit_freeze_time
	_brake_armed = false
	is_air_braking = false

	if grounded and direction.y < 0.0:
		var slide_speed := maxf(dash_speed, _dash_keep) * slide_mult
		velocity = flat_direction * slide_speed
		_enter_slide(true)
		dash_started.emit(flat_direction if flat_direction != Vector3.ZERO else facing)
		return

	if not grounded or direction.y > 0.0:
		dash_available = false
		_coyote = 0.0
		_jump_buffer = 0.0
	if not grounded and direction.y < 0.0:
		_wave_window = dash_time + wavedash_grace

	_set_dash_velocity(direction)
	_dash_dir = direction
	_dash_timer = dash_time
	_dash_grounded = grounded and direction.y == 0.0
	state = State.DASH
	dash_started.emit(direction)


## Dash speed along a direction, never slowing a body already moving faster.
func _set_dash_velocity(direction: Vector3) -> void:
	var flat_direction := Vector3(direction.x, 0.0, direction.z).normalized()
	velocity = direction * dash_speed
	if _dash_keep > Vector2(velocity.x, velocity.z).length():
		velocity.x = flat_direction.x * _dash_keep
		velocity.z = flat_direction.z * _dash_keep


func _land_wavedash() -> void:
	_wave_window = 0.0
	dash_available = true
	var flat := Vector3(_dash_dir.x, 0.0, _dash_dir.z)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if flat == Vector3.ZERO:
		if _move == Vector3.ZERO:
			state = State.NORMAL
			if _wave_jump:
				_wave_jump = false
				_launch(&"hyper")
			return
		horizontal = _move.normalized() * dash_speed * sqrt(0.5)
	velocity = horizontal * slide_mult
	_enter_slide(true)
	if _wave_jump:
		_wave_jump = false
		_launch(&"hyper")


func _enter_slide(can_hyper: bool) -> void:
	state = State.SLIDE
	_can_hyper = can_hyper
	_hyper_rest = hyper_rest_grace


func _update_slide(delta: float) -> void:
	if _can_hyper and horizontal_speed() < 0.01:
		_hyper_rest -= delta
		_can_hyper = _hyper_rest > 0.0
	if _try_jump():
		_apply_gravity(delta)
		return
	if not _squat_down or not is_on_floor():
		state = State.NORMAL
		_update_normal(delta)
		return
	var horizontal := _steer(Vector3(velocity.x, 0.0, velocity.z), delta)
	var speed := move_toward(horizontal.length(), 0.0, duck_friction * delta)
	horizontal = horizontal.normalized() * speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_apply_gravity(delta)


func _ground_jump_kind() -> StringName:
	match state:
		State.DASH_RUN:
			return &"hyper" if _squat_down else &"super"
		State.DASH:
			if _dash_grounded:
				return &"hyper" if _squat_down else &"super"
		State.SLIDE:
			if _can_hyper:
				return &"hyper"
	return &"jump"


## Fires a buffered jump if allowed, as a jump, super, or hyper.
func _try_jump() -> bool:
	if _jump_buffer <= 0.0 or _coyote <= 0.0:
		return false
	_launch(_ground_jump_kind() if is_on_floor() else _coyote_kind)
	return true


func _launch(kind: StringName) -> void:
	state = State.NORMAL
	if kind == &"jump":
		_jump()
		return
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var direction := facing
	if _move != Vector3.ZERO:
		direction = _move.normalized()
	elif horizontal.length_squared() > 0.0001:
		direction = horizontal.normalized()
	var speed := maxf(horizontal.length(), super_jump_h)
	var rise := jump_speed
	if kind == &"hyper":
		speed *= hyper_h_mult
		rise *= hyper_v_mult
	speed = minf(speed, max_speed)
	if is_on_floor():
		# Uphill, the launch must out-climb the slope or the floor swallows it.
		var normal := get_floor_normal()
		rise += maxf(-direction.dot(normal) / normal.y * speed, 0.0)
	velocity = direction * speed
	velocity.y = rise
	_jump_buffer = 0.0
	_coyote = 0.0
	_var_jump = var_jump_time
	_var_jump_speed = rise
	jumped.emit(kind)


func _update_dash(delta: float) -> void:
	_dash_timer -= delta
	if is_on_floor() and _dash_dir.y == 0.0 and not _dash_grounded:
		_dash_grounded = true # a flat air dash that meets rising ground has landed
		dash_available = true
	if _dash_grounded and _try_jump():
		return
	if _jump_pressed and not _dash_grounded and not _squat_down and not is_on_floor():
		var flat_direction := Vector3(_dash_dir.x, 0.0, _dash_dir.z)
		_dash_dir = dash_direction(flat_direction, true, false)
		_set_dash_velocity(_dash_dir)
		_jump_buffer = 0.0
	var hit_wall := is_on_wall() and get_wall_normal().dot(_dash_dir) < -0.5
	var hit_ceiling := is_on_ceiling() and _dash_dir.y > 0.0
	if _dash_timer <= 0.0 or hit_wall or hit_ceiling:
		_end_dash()


func _end_dash() -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.limit_length(maxf(dash_run_speed, _dash_keep))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if _dash_dir.y > 0.0:
		velocity.y = minf(velocity.y, _dash_dir.y * dash_run_speed * end_dash_up_mult)
	state = State.NORMAL


func _update_dash_run(delta: float) -> void:
	if not is_on_floor() or not _dash_down or _move == Vector3.ZERO:
		state = State.NORMAL
		_update_normal(delta)
		return
	if _try_jump():
		_apply_gravity(delta)
		return
	if _squat_down:
		_enter_slide(true)
		_update_slide(delta)
		return
	var horizontal := _steer(Vector3(velocity.x, 0.0, velocity.z), delta)
	var speed := horizontal.length()
	if speed > dash_run_speed:
		speed = _decay(speed, dash_run_speed, ground_bleed, run_reduce, delta)
	else:
		speed = move_toward(speed, dash_run_speed, run_accel * delta)
	horizontal = horizontal.normalized() * speed
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_apply_gravity(delta)


## Rotates a horizontal velocity toward the move input without changing speed.
func _steer(horizontal: Vector3, delta: float) -> Vector3:
	if _move == Vector3.ZERO:
		return horizontal
	if horizontal.length_squared() < 0.0001:
		return _move.normalized() * 0.01
	var angle := horizontal.signed_angle_to(_move, Vector3.UP)
	var step := deg_to_rad(air_turn_rate) * delta
	return horizontal.rotated(Vector3.UP, clampf(angle, -step, step))


func _apply_run(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horizontal.length()
	var opposed := _move != Vector3.ZERO and horizontal.normalized().dot(_move.normalized()) < -0.5
	if speed <= max_run or opposed:
		horizontal = horizontal.move_toward(_move * max_run, run_accel * delta)
	else:
		horizontal = _steer(horizontal, delta)
		horizontal = horizontal.normalized() * _decay(speed, max_run, ground_bleed, run_reduce, delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_gravity(delta: float) -> void:
	if is_air_braking:
		_var_jump = 0.0
		velocity.y = move_toward(velocity.y, -fast_max_fall, gravity * air_brake_gravity_mult * delta)
		return
	if _var_jump > 0.0:
		_var_jump -= delta
		if _jump_down:
			velocity.y = maxf(velocity.y, _var_jump_speed)
			return
		_var_jump = 0.0
	if is_on_floor() and velocity.y <= 0.0:
		velocity.y = 0.0
		return
	var mult := 0.5 if absf(velocity.y) < half_grav_threshold and _jump_down else 1.0
	velocity.y = move_toward(velocity.y, -max_fall, gravity * mult * delta)


func _jump() -> void:
	_jump_buffer = 0.0
	_coyote = 0.0
	_var_jump = var_jump_time
	_var_jump_speed = jump_speed
	var carried := Vector3(velocity.x, 0.0, velocity.z)
	var boosted := (carried + _move * jump_h_boost).limit_length(maxf(carried.length(), max_run + jump_h_boost))
	velocity = Vector3(boosted.x, jump_speed, boosted.z)
	jumped.emit(&"jump")
