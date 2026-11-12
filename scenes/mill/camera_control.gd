extends Node3D
class_name CameraControl

signal started_aiming
signal stopped_aiming

@export var player: CharacterBody3D
@export var pcam: PhantomCamera3D

@export_group("Orbit")
@export var mouse_sensitivity := 0.003
@export var distance := 4.0
@export var pivot_height := 1.6          # height above player origin the camera orbits around
@export_range(-89.0, 0.0) var min_pitch_deg := -60.0   # camera high, looking down
@export_range(0.0, 89.0) var max_pitch_deg := 30.0     # camera low, looking up

@export var yaw_follow_smoothing := 4.0   # higher = camera catches up with the player faster
var _frame_z := Vector3.BACK

@export_group("Look Target")
@export var look_height := 1.0           # normal: aim at the player's body
@export var aim_look_height := 1.8       # aiming: look target slightly above the player



@export_group("Aiming")
@export var aim_fov := 45.0
@export var smoothing := 12.0


var _aim_basis := Basis.IDENTITY   # free orientation used while aiming
var _orbit := Basis.IDENTITY       # orbit basis used on the last frame
var _frame := Basis.IDENTITY       # smoothed player-relative frame from the last frame


var _default_fov: float
var _current_fov: float
var _cam_res: Camera3DResource


var _yaw := 0.0
var _pitch := deg_to_rad(-15.0)
var aiming := false
var _current_distance: float
var _current_look_height: float
var _look_target: Node3D

var _anchor_override := false   # true while the camera is following the virtual anchor
var _anchor_pos := Vector3.ZERO
var _move_tween: Tween

func _ready() -> void:
	top_level = true                 # stop inheriting the player's rotation
	process_priority = -100          # update before the PhantomCamera reads our transform
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	


	_cam_res = pcam.get_camera_3d_resource()
	_default_fov = _cam_res.fov
	_current_fov = _default_fov
	
	_current_look_height = look_height

	_look_target = Node3D.new()
	_look_target.top_level = true
	add_child(_look_target)

	_frame_z = player.global_basis.z
	_update_rig(0.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if aiming:
			# Yaw around the global up axis, pitch around the camera's local X, no limits
			_aim_basis = Basis(Vector3.UP, -event.relative.x * mouse_sensitivity) \
					* _aim_basis \
					* Basis(Vector3.RIGHT, -event.relative.y * mouse_sensitivity)
			_aim_basis = _aim_basis.orthonormalized()
		else:
			_yaw -= event.relative.x * mouse_sensitivity
			_pitch -= event.relative.y * mouse_sensitivity
			_pitch = clampf(_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
		
	elif event.is_action_pressed("aim_web"):
		start_aiming()
	elif event.is_action_released("aim_web"):
		stop_aiming()
	elif event.is_action_pressed("toggle_camera_lock"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	_update_rig(delta)
	
func move_camera_toward(target_pos: Vector3, speed: float) -> void:
	if speed <= 0.0:
		return
	if _move_tween:
		_move_tween.kill()

	# Start from the current anchor if one is active, otherwise from the player
	var start := _anchor_pos if _anchor_override else player.global_position
	var duration := start.distance_to(target_pos) / speed
	if duration <= 0.0:
		reset_camera_move()
		return

	_anchor_override = true
	_anchor_pos = start

	_move_tween = create_tween()
	_move_tween.tween_property(self, "_anchor_pos", target_pos, duration)
	_move_tween.tween_callback(reset_camera_move)


func reset_camera_move() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null
	_anchor_override = false


func start_aiming() -> void:
	if aiming:
		return
	aiming = true
	_aim_basis = _orbit.orthonormalized()   # continue from the current view
	started_aiming.emit()

func stop_aiming() -> void:
	if not aiming:
		return
	aiming = false
	# Convert the free orientation back to yaw/pitch relative to the player frame
	var e := (_frame.inverse() * _aim_basis).orthonormalized().get_euler()
	_yaw = e.y
	_pitch = clampf(e.x, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))
	stopped_aiming.emit()
func _update_rig(delta: float) -> void:
	var target_look_height := aim_look_height if aiming else look_height
	var target_fov := aim_fov if aiming else _default_fov

	var t := 1.0 - exp(-smoothing * delta)
	_current_look_height = lerpf(_current_look_height, target_look_height, t)
	_current_fov = lerpf(_current_fov, target_fov, t)
	_cam_res.fov = _current_fov

	

	var player_basis := player.global_basis.orthonormalized()
	var player_pos := _anchor_pos if _anchor_override else player.global_position
	var up := player_basis.y
	var pivot := player_pos + up * pivot_height

	# Smoothly follow the player's yaw around their up axis
	var cur_z := _frame_z.slide(up)
	if cur_z.length_squared() < 0.0001:
		cur_z = player_basis.z
	cur_z = cur_z.normalized()
	var yaw_diff := cur_z.signed_angle_to(player_basis.z, up)
	var follow_t := 1.0 - exp(-yaw_follow_smoothing * delta)
	_frame_z = cur_z.rotated(up, yaw_diff * follow_t)
	var frame := Basis(up.cross(_frame_z), up, _frame_z)

	_frame = frame
	var orbit := _aim_basis if aiming else frame * Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_orbit = orbit
	
	global_position = pivot + orbit * Vector3(0.0, 0.0, distance)

	_look_target.global_position = player_pos + up * _current_look_height
	
	# Offset from the player along the player's up axis
	pcam.set_look_at_offset(up * _current_look_height + (player_pos - player.global_position))
