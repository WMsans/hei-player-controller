class_name Player
extends CharacterBody3D
## Celeste-style 3D controller. Values start from Celeste at 12 px = 1 m.

signal jumped(kind: StringName)
signal landed(impact_speed: float)
signal dash_started(direction: Vector3)

enum State { NORMAL, DASH, DASH_RUN, SLIDE }

const COYOTE_TIME := 0.1
const JUMP_BUFFER_TIME := 0.1

@export_group("Run")
@export var max_run := 7.5
@export var run_accel := 83.0
@export var run_reduce := 33.0
@export var air_mult := 0.65
@export var max_speed := 35.0

@export_group("Gravity")
@export var gravity := 75.0
@export var max_fall := 13.3
@export var fast_max_fall := 20.0
@export var half_grav_threshold := 3.3

@export_group("Jump")
@export var jump_speed := 8.75
@export var jump_h_boost := 3.3
@export var var_jump_time := 0.2

@export_group("Dash")
@export var dash_speed := 20.0
@export var dash_run_speed := 13.3
@export var dash_time := 0.15
@export var end_dash_up_mult := 0.75

@export_group("Super")
@export var super_jump_h := 21.7
@export var hyper_h_mult := 1.25
@export var hyper_v_mult := 0.5
@export var slide_mult := 1.2
@export var duck_friction := 80.0

@export_group("Air")
@export var air_turn_rate := 270.0
@export var air_brake_decel := 90.0
@export var air_brake_gravity_mult := 1.5

var state := State.NORMAL
var facing := Vector3.FORWARD
var view_yaw := 0.0
var dash_available := true

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


func set_scripted_input(move: Vector2, jump: bool, dash: bool, squat: bool) -> void:
	_scripted = true
	_script_move = move
	_script_jump = jump
	_script_dash = dash
	_script_squat = squat


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func _physics_process(delta: float) -> void:
	_sample_input()
	_coyote = maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _jump_pressed:
		_jump_buffer = JUMP_BUFFER_TIME

	var was_on_floor := is_on_floor()
	if was_on_floor:
		_coyote = COYOTE_TIME

	_update_normal(delta)

	var fall_speed := -velocity.y
	move_and_slide()
	if is_on_ceiling():
		_var_jump = 0.0
	if is_on_floor() and not was_on_floor:
		landed.emit(fall_speed)


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
	if _jump_buffer > 0.0 and _coyote > 0.0:
		_jump()
	_apply_run(delta)
	_apply_gravity(delta)


func _apply_run(delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := _move * max_run
	var mult := 1.0 if is_on_floor() else air_mult
	var over_max := horizontal.length() > max_run and horizontal.dot(target) > 0.0
	var rate := (run_reduce if over_max else run_accel) * mult
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _apply_gravity(delta: float) -> void:
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
	velocity += _move * jump_h_boost
	velocity.y = jump_speed
	jumped.emit(&"jump")
