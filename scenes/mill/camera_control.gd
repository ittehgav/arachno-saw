extends Node3D

@export var phantom_camera: PhantomCamera3D

@export var aim_height := 0.8
@export var normal_fov := 75.0
@export var aim_fov := 45.0
@export var aim_duration := 0.2

var aiming := false

@export var player: CharacterBody3D
@export var sensitivity := 0.003

@export var min_pitch := deg_to_rad(-80.0)
@export var max_pitch := deg_to_rad(80.0)

var yaw := 0.0
var pitch := 0.0

var initial_offset: Vector3
var initial_basis: Basis

var camera_locked := true

func _ready() -> void:
	camera_locked = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	normal_fov = phantom_camera.camera_3d_resource.fov

	initial_offset = global_position - player.global_position
	initial_basis = global_basis

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera_lock"):
		camera_locked = !camera_locked
		Input.mouse_mode = (
			Input.MOUSE_MODE_CAPTURED
			if camera_locked
			else Input.MOUSE_MODE_VISIBLE
		)
		return

	if not camera_locked:
		return

	if event is InputEventMouseMotion:
		yaw -= event.relative.x * sensitivity
		pitch -= event.relative.y * sensitivity
		pitch = clamp(pitch, min_pitch, max_pitch)


	if event.is_action_pressed("aim_web"):
		_set_aim(true)

	elif event.is_action_released("aim_web"):
		_set_aim(false)

func _set_aim(enable: bool) -> void:
	if aiming == enable:
		return

	aiming = enable

	var target_fov := aim_fov if enable else normal_fov

	var tween := create_tween()

	if phantom_camera and phantom_camera.camera_3d_resource:
		tween.tween_property(
			phantom_camera.camera_3d_resource,
			"fov",
			target_fov,
			aim_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func _process(_delta: float) -> void:
	if player == null:
		return

	var yaw_basis := Basis(player.global_basis.y, yaw)

	var right := yaw_basis * initial_basis.x
	var pitch_basis := Basis(right, pitch)

	var rotation := pitch_basis * yaw_basis

	var aim_offset := (
		player.global_transform.basis.y * aim_height
		if aiming
		else Vector3.ZERO
	)

	global_position = player.global_position + rotation * initial_offset + aim_offset
	global_basis = rotation * initial_basis
