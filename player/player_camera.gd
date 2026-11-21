extends Node3D
## Third-person orbit camera. Mouse writes the player's view yaw; FOV widens with speed.

@export var mouse_sensitivity := 0.0025
@export var min_pitch := deg_to_rad(-70.0)
@export var max_pitch := deg_to_rad(35.0)
@export var height := 1.4
@export var base_fov := 75.0
@export var fast_fov := 95.0
@export var fov_response := 8.0

var _pitch := deg_to_rad(-15.0)

@onready var _player: Player = get_parent()
@onready var _arm: SpringArm3D = $SpringArm3D
@onready var _camera: Camera3D = $SpringArm3D/Camera3D


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm.add_excluded_object(_player.get_rid())
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_player.view_yaw = wrapf(_player.view_yaw - event.relative.x * mouse_sensitivity, -PI, PI)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, min_pitch, max_pitch)


func _process(delta: float) -> void:
	global_position = _player.get_global_transform_interpolated().origin + Vector3.UP * height
	rotation = Vector3(_pitch, _player.view_yaw, 0.0)
	var speed_ratio := clampf(_player.horizontal_speed() / _player.max_speed, 0.0, 1.0)
	var target_fov := lerpf(base_fov, fast_fov, speed_ratio)
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-fov_response * delta))
