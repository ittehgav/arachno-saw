extends CharacterBody3D


signal movement_enabled;
signal movement_disabled;


@export var speed: float = 6.0
@export var base_speed: float = 1.0
@export var bonus_speed: float = 1.0
@export var gravity: float = 20.0
@export var align_speed: float = 10.0   # how fast the body rotates to the new surface
@export var turn_speed: float = 2.5     # radians per second
@export var strafe: bool = false        # true keeps A/D sideways movement while turning
@export var probe_length: float = 1.5   # how far to look for a surface under/around the body
@export var stick_force: float = 12.0   # pull toward the surface while rotating around an edge
@export var sharp_angle: float = 30.0   # degrees; movement slows to a stop past this
@export var radius_snap_min: float = 8.0
@export var normal_smoothing: float = 30.0   # higher = reacts faster, lower = ignores seam glitches better
var _smooth_up: Vector3 = Vector3.UP

var _last_dir: Vector3 = Vector3.FORWARD
var _probe_len: float = 0.0


var speed_up_tween:Tween;

func _ready() -> void:
	_smooth_up = global_basis.y
	safe_margin = 0.1   # default 0.001 is too tight for a 4m body and catches on internal edges
	floor_max_angle = deg_to_rad(80.0)
	floor_snap_length = 0.5
	floor_constant_speed = true
	
func disable_movement() -> void:
	if not is_physics_processing():
		return
	set_physics_process(false)
	velocity = Vector3.ZERO
	movement_disabled.emit()


func enable_movement() -> void:
	if is_physics_processing():
		return
	set_physics_process(true)
	movement_enabled.emit()


func _physics_process(delta: float) -> void:
	var up: Vector3 = global_basis.y
	up_direction = up

	var speed_mult: float = base_speed * bonus_speed
	var step_travel: float = speed * speed_mult * delta   # distance moved this frame
	_probe_len = probe_length + step_travel * 2.0
	floor_snap_length = maxf(radius_snap_min, step_travel * 3.0)

	# A/D turn the body around its local up axis
	var turn: float = float(Input.is_physical_key_pressed(KEY_A)) - float(Input.is_physical_key_pressed(KEY_D))
	if turn != 0.0:
		global_basis = global_basis.rotated(up, turn * turn_speed * delta).orthonormalized()

	# W/S move forward/back (and A/D sideways too, if strafe is on)
	var x: float = 0.0
	if strafe:
		x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var z: float = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var direction: Vector3 = (global_basis * Vector3(x, 0.0, z)).normalized()

	if direction != Vector3.ZERO:
		_last_dir = direction

	# Find the surface we should be hugging
	var hit: Dictionary = _probe_surface(_last_dir)
	var target_up: Vector3 = up
	var has_surface: bool = false
	if is_on_floor():
		var contact: Vector3 = _contact_normal(up)
		target_up = contact if contact != Vector3.ZERO else get_floor_normal()
		has_surface = true
	elif not hit.is_empty():
		target_up = hit.normal
		has_surface = true

	# Low-pass filter the target so a one-frame bad normal at a seam can't stop the body
	if has_surface:
		var blended: Vector3 = _smooth_up.lerp(target_up, clampf(normal_smoothing * delta, 0.0, 1.0))
		_smooth_up = blended.normalized() if blended.length_squared() > 0.0001 else target_up
		target_up = _smooth_up
	else:
		_smooth_up = up

	# Slow to a stop while the surface is turning sharply, until we've caught up
	var misalign: float = up.angle_to(target_up)
	var sharp: float = deg_to_rad(sharp_angle) / sqrt(speed_mult)
	var speed_scale: float = 1.0 - smoothstep(sharp * 0.5, sharp, misalign)

	# Hug the surface while rotating, otherwise normal gravity along local up
	var vertical: Vector3
	if has_surface and not is_on_floor():
		vertical = -target_up * stick_force * speed_mult
	else:
		vertical = up * velocity.dot(up) - up * gravity * delta

	var final_speed: float = speed * speed_mult * speed_scale
	velocity = direction * final_speed + vertical
	move_and_slide()

	if has_surface:
		var pivot: Vector3 = global_position
		if not hit.is_empty():
			pivot = hit.position
		_align_to_normal(target_up, pivot, delta, speed_mult)

func _contact_normal(up: Vector3) -> Vector3:
	# Average every floor-ish contact, so at a seam both surfaces contribute
	# instead of the solver picking one of them arbitrarily
	var sum: Vector3 = Vector3.ZERO
	for i: int in get_slide_collision_count():
		var n: Vector3 = get_slide_collision(i).get_normal()
		if n.dot(up) > 0.2:
			sum += n
	return sum.normalized() if sum.length_squared() > 0.0001 else Vector3.ZERO

func _align_to_normal(target_up: Vector3, pivot: Vector3, delta: float, speed_mult: float) -> void:
	var current_up: Vector3 = global_basis.y
	var angle: float = current_up.angle_to(target_up)
	if angle < 0.0001:
		return
	var axis: Vector3 = current_up.cross(target_up)
	if axis.length_squared() < 0.000001:
		return
	# Minimum rate so big turns always finish quickly instead of easing out forever
	var step: float = minf(angle, maxf(align_speed * angle, 5.0) * speed_mult * delta)
	var rot: Basis = Basis(axis.normalized(), step)
	global_basis = (rot * global_basis).orthonormalized()
	# Pivot around the contact point so the feet stay on the surface
	global_position = pivot + rot * (global_position - pivot)


func _probe_surface(dir: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var up: Vector3 = global_basis.y
	# Straight down, then diagonally down-and-forward to catch surfaces that
	# wrap under an edge (e.g. a 90° drop where a straight-down ray would miss)
	var dirs: Array[Vector3] = [
		-up,                          # straight down
		(-up + dir).normalized(),     # down-forward (drops ahead)
		(-up - dir).normalized(),     # down-backward (wall under a convex edge)
		dir,                          # forward (concave corners, wall ahead)
	]
	
	for d: Vector3 in dirs:
		var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			global_position, global_position + d * _probe_len, collision_mask, [get_rid()])
		var r: Dictionary = space.intersect_ray(q)
		if not r.is_empty():
			return r
	return {}
