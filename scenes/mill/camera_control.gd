extends Node3D


@export var player: CharacterBody3D
@export var pcam: PhantomCamera3D
@export var crosshair:TextureRect

@export var mouse_sensitivity: float = 0.003
## Pitch limits, measured relative to the camera's reference up direction
@export_range(-89.0, 0.0) var min_pitch_degrees: float = -80.0
@export_range(-60.0, 89.0) var max_pitch_degrees: float = 60.0

@export_group("Up Follow")
## The camera only starts following the player's up direction once the angle
## between the two is larger than this
@export_range(0.0, 180.0) var up_follow_tolerance_degrees: float = 30.0

@export_group("Reset")
@export var reset_key: Key = KEY_R
@export var reset_duration: float = 0.3  # set to 0 for an instant snap

# Camera angles in the reference frame's space
var _yaw: float = 0.0
var _pitch: float = 0.0
var _initial_yaw: float = 0.0
var _initial_pitch: float = 0.0

# Reference frame whose Y axis is the camera's tracked "up".
# It trails the player's up and only moves once the tolerance is exceeded.
var _frame: Basis = Basis.IDENTITY

var _reset_tween: Tween

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	pcam.follow_mode = PhantomCamera3D.FollowMode.THIRD_PERSON
	pcam.follow_target = player

	_frame = Basis(Quaternion(Vector3.UP, player.global_basis.y.normalized()))

	# Convert the pcam's starting rotation into the frame-relative space
	var local_basis := _frame.inverse() * Basis.from_euler(pcam.get_third_person_rotation())
	var local_euler := local_basis.get_euler()
	_initial_pitch = local_euler.x
	_initial_yaw = local_euler.y
	_pitch = _initial_pitch
	_yaw = _initial_yaw

var aiming:bool=false;
var aim_tween:Tween;
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == reset_key:
		reset_camera()
		
	if event.is_action_pressed("aim_web") and not aiming:
		_start_aiming()
	elif event.is_action_released("aim_web") and aiming:
		_stop_aiming()
	
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Cancel an in-progress reset if the player grabs the camera
		if _reset_tween and _reset_tween.is_running():
			_reset_tween.kill()

		_yaw -= event.relative.x * mouse_sensitivity
		_pitch -= event.relative.y * mouse_sensitivity
		_pitch = clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
func _start_aiming()->void:
	const start_aim_time:=.1
	aiming = true;
	if aim_tween and aim_tween.is_running():
		aim_tween.kill()
	var t:= create_tween()
	aim_tween = t;
	t.tween_property(pcam, "spring_length", 20, start_aim_time);
	t.parallel().tween_property(crosshair, "modulate:a", 1, start_aim_time)
	t.parallel().tween_property(pcam, "follow_offset:y", 30, start_aim_time)

func _stop_aiming()->void:
	const stop_aim_time = .25
	aiming = false;
	if aim_tween and aim_tween.is_running():
		aim_tween.kill();
	var t:= create_tween();
	aim_tween = t;
	t.tween_property(pcam, "spring_length", 80, .25)
	t.parallel().tween_property(crosshair, "modulate:a", 0, stop_aim_time)
	t.parallel().tween_property(pcam, "follow_offset:y", 0, .25)

func _process(_delta: float) -> void:
	_update_frame()

	# Keep the pitch inside the limits even while a reset tween is running
	_pitch = clampf(_pitch, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

	# Build the camera orientation in the reference frame, then hand it to the pcam
	var local_basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var world_basis := _frame * local_basis
	pcam.set_third_person_rotation(world_basis.get_euler())


func _update_frame() -> void:
	var player_up := player.global_basis.y.normalized()
	var tracked_up := _frame.y

	var angle := tracked_up.angle_to(player_up)
	var tolerance := deg_to_rad(up_follow_tolerance_degrees)

	# Inside the tolerance: the camera's up stays where it is
	if angle <= tolerance:
		return

	# Outside the tolerance: rotate the frame just far enough to bring the
	# difference back down to the tolerance
	var axis := tracked_up.cross(player_up)
	if axis.length_squared() < 0.000001:
		# Player's up is exactly opposite; any axis perpendicular to up works
		axis = _frame.x
	axis = axis.normalized()

	var rotation := Quaternion(axis, angle - tolerance)
	_frame = (Basis(rotation) * _frame).orthonormalized()


func reset_camera() -> void:
	if _reset_tween and _reset_tween.is_running():
		_reset_tween.kill()

	if reset_duration <= 0.0:
		_yaw = _initial_yaw
		_pitch = _initial_pitch
		return

	# Take the shortest way around on the horizontal axis
	var target_yaw := _yaw + angle_difference(_yaw, _initial_yaw)

	_reset_tween = create_tween()
	_reset_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reset_tween.set_parallel(true)
	_reset_tween.tween_property(self, "_yaw", target_yaw, reset_duration)
	_reset_tween.tween_property(self, "_pitch", _initial_pitch, reset_duration)

func _on_spider_died(_source: Crawler.DeathType) -> void:
	pcam.follow_mode = PhantomCamera3D.FollowMode.NONE;
	pcam.look_at_mode = PhantomCamera3D.LookAtMode.NONE;
	var t:= create_tween();
	t.tween_property(pcam.camera_3d_resource, "fov", pcam.fov + 30, 1)


func _on_spider_fly_consumed(fly: Fly) -> void:
	if fly.type == Fly.Type.teleport:
		reset_camera()
