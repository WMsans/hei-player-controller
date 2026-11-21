extends Node3D
## Visual-only feedback: squash and stretch, dash trail, and state tint.

@export var ready_color := Color(0.95, 0.35, 0.3)
@export var spent_color := Color(0.3, 0.55, 0.95)
@export var brake_color := Color(0.95, 0.95, 0.9)
@export var jump_stretch := Vector3(0.6, 1.4, 0.6)
@export var land_squash := Vector3(1.35, 0.6, 1.35)
@export var recover_rate := 12.0
@export var trail_interval := 0.025
@export var trail_fade := 0.25

var _trail_timer := 0.0
var _material := StandardMaterial3D.new()

@onready var _player: Player = get_parent()
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	_material.albedo_color = ready_color
	_mesh.set_surface_override_material(0, _material)
	_player.jumped.connect(func(_kind: StringName): scale = jump_stretch)
	_player.landed.connect(_on_landed)
	_player.dash_started.connect(func(_direction: Vector3): _trail_timer = 0.0)


func _physics_process(delta: float) -> void:
	scale = scale.lerp(Vector3.ONE, 1.0 - exp(-recover_rate * delta))

	if _player.is_air_braking:
		_material.albedo_color = brake_color
	else:
		_material.albedo_color = ready_color if _player.dash_available else spent_color

	if _player.state == Player.State.DASH or _player.state == Player.State.SLIDE:
		_trail_timer -= delta
		if _trail_timer <= 0.0 and _player.horizontal_speed() > _player.max_run:
			_trail_timer = trail_interval
			_spawn_ghost()


func _on_landed(impact_speed: float) -> void:
	var amount := clampf(impact_speed / _player.fast_max_fall, 0.0, 1.0)
	scale = Vector3.ONE.lerp(land_squash, maxf(amount, 0.35))


func _spawn_ghost() -> void:
	var ghost := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(_material.albedo_color, 0.45)
	ghost.mesh = _mesh.mesh
	ghost.material_override = material
	ghost.top_level = true
	ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(ghost)
	ghost.global_transform = _mesh.global_transform
	var tween := ghost.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, trail_fade)
	tween.tween_callback(ghost.queue_free)
