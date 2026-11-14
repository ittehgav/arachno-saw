extends Node3D
class_name CameraControl

signal started_aiming
signal stopped_aiming

@export var pcam: PhantomCamera3D
@export var player: Node3D

@export_group("Look")
@export var mouse_sensitivity := 0.003
@export_range(-89.0, 89.0, 0.5) var min_pitch_degrees := -80.0
@export_range(-89.0, 89.0, 0.5) var max_pitch_degrees := 80.0

@export_group("Follow")
## How fast the camera frame re-aligns to the player's up axis (roll/pitch).
@export var up_follow_speed := 6.0
## How much of the player's rotation around its up axis the camera picks up (0 = none, 1 = all).
@export_range(0.0, 1.0) var yaw_follow_strength := 0.25

@export_group("Aiming")
@export var aim_fov := 50.0
## How far the pivot (and so the look direction) is raised along the player's up axis.
@export var aim_height := 0.6
@export var aim_transition_speed := 6.0
@export_range(1.0, 89.0) var aim_pitch_limit_degrees := 89.0

var aiming := false:
	set(value):
		if value == aiming:
			return
		aiming = value
		if not is_node_ready():
			return
		_rot_from = _cam_quat
		_rot_t = 0.0
		if aiming:
			# Start from the current view, leveled to the global axes
			var e := Basis(_cam_quat).get_euler(EULER_ORDER_YXZ)
			_aim_pitch = e.x
			_aim_yaw = e.y
			started_aiming.emit()
		else:
			# Continue from wherever the aim ended, relative to the player frame
			var rel := _frame.transposed() * Basis(_cam_quat)
			var e := rel.get_euler(EULER_ORDER_YXZ)
			_yaw = e.y
			_pitch = clampf(e.x, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
			stopped_aiming.emit()

var _frame := Basis.IDENTITY          # camera reference frame, follows the player
var _prev_player_basis := Basis.IDENTITY
var _yaw := 0.0                       # mouse offsets, relative to _frame
var _pitch := 0.0
var _aim_yaw := 0.0                   # mouse angles while aiming, global axes
var _aim_pitch := 0.0
var _cam_quat := Quaternion.IDENTITY
var _rot_from := Quaternion.IDENTITY
var _rot_t := 1.0
var _aim_blend := 0.0
var _base_offset_local := Vector3.ZERO
var _base_fov := 75.0


func _ready() -> void:
	assert(pcam != null and player != null, "Assign pcam and player in the inspector.")


	var player_basis := player.global_basis.orthonormalized()
	_frame = player_basis
	_prev_player_basis = player_basis

	# Keep the position the camera was placed at, relative to the player
	var pivot := player.global_position + pcam.get_follow_offset()
	var to_cam := pcam.global_position - pivot
	if to_cam.length() > 0.001:
		pcam.set_spring_length(to_cam.length())
		var cam_basis := Basis.looking_at(-to_cam, player_basis.y)
		var rel := player_basis.transposed() * cam_basis
		var e := rel.get_euler(EULER_ORDER_YXZ)
		_yaw = e.y
		_pitch = clampf(e.x, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))


	_base_offset_local = player_basis.transposed() * pcam.get_follow_offset()

	var res := pcam.get_camera_3d_resource()
	if res:
		_base_fov = res.fov

	_cam_quat = _normal_quat()
	_rot_from = _cam_quat
	pcam.set_third_person_quaternion(_cam_quat)
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera_lock"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("aim_web"):
		aiming = true
	elif event.is_action_released("aim_web"):
		aiming = false
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)


func _rotate_camera(relative: Vector2) -> void:
	if aiming:
		var limit := deg_to_rad(aim_pitch_limit_degrees)
		_aim_yaw -= relative.x * mouse_sensitivity
		_aim_pitch = clampf(_aim_pitch - relative.y * mouse_sensitivity, -limit, limit)
	else:
		_yaw -= relative.x * mouse_sensitivity
		_pitch = clampf(
			_pitch - relative.y * mouse_sensitivity,
			deg_to_rad(min_pitch_degrees),
			deg_to_rad(max_pitch_degrees)
		)


func _process(delta: float) -> void:
	_update_frame(delta)

	# Orientation (blended when switching between normal and aim)
	var target := _aim_quat() if aiming else _normal_quat()
	_rot_t = minf(_rot_t + aim_transition_speed * delta, 1.0)
	_cam_quat = _rot_from.slerp(target, smoothstep(0.0, 1.0, _rot_t)).normalized()
	pcam.set_third_person_quaternion(_cam_quat)

	# Pivot offset and FOV
	_aim_blend = move_toward(_aim_blend, 1.0 if aiming else 0.0, aim_transition_speed * delta)
	var s := smoothstep(0.0, 1.0, _aim_blend)
	pcam.set_follow_offset(_frame * _base_offset_local + _frame.y * aim_height * s)

	var res := pcam.get_camera_3d_resource()
	if res:
		res.fov = lerpf(_base_fov, aim_fov, s)


func _update_frame(delta: float) -> void:
	var cur := player.global_basis.orthonormalized()
	var up := cur.y

	# How much the player turned around its up axis since last frame
	var dq := Quaternion(cur) * Quaternion(_prev_player_basis).inverse()
	if dq.w < 0.0:
		dq = -dq
	var twist := 2.0 * atan2(Vector3(dq.x, dq.y, dq.z).dot(up), dq.w)
	_prev_player_basis = cur

	# Steer the frame's up axis toward the player's (carries roll and pitch)
	var swing := Quaternion(_frame.y, up)
	var k := 1.0 - exp(-up_follow_speed * delta)
	_frame = Basis(Quaternion.IDENTITY.slerp(swing, k)) * _frame

	# Follow only a fraction of the player's yaw
	_frame = Basis(Quaternion(_frame.y, twist * yaw_follow_strength)) * _frame
	_frame = _frame.orthonormalized()


func _normal_quat() -> Quaternion:
	return Quaternion(_frame) \
		* Quaternion(Vector3.UP, _yaw) \
		* Quaternion(Vector3.RIGHT, _pitch)


func _aim_quat() -> Quaternion:
	return Quaternion(Vector3.UP, _aim_yaw) * Quaternion(Vector3.RIGHT, _aim_pitch)

## relative to the player, slightly above
@onready var origin:Vector3 = position 
func move_camera_toward(target:Vector3, speed:float)->void:
	var distance:= global_position.distance_to(target);
	var duration := distance/speed
	top_level = true;
	var t:= create_tween();
	t.tween_property(self, "global_position", target, duration)
	aiming = false
	
func reset_camera()->void:
	top_level = false
	await get_tree().process_frame
	position = origin;
	

func _on_spider_died(_source: Crawler.DeathType) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
