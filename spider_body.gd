class_name SurfaceCrawler
extends CharacterBody3D

signal died;

@export var spider:Spider;


@export var move_speed: float = 2.0
@export var rotation_speed: float = 8.0
@export var surface_distance: float = 0.2
@export var probe_distance: float = 0.8
@export_range(0.0, 180.0)
var max_transition_angle: float = 90.0

var surface_normal: Vector3 = Vector3.UP


func _ready() -> void:
	var hit: Dictionary = _raycast(-global_transform.basis.y)

	if hit:
		surface_normal = hit.normal
		global_position = hit.position + surface_normal * surface_distance


func _physics_process(delta: float) -> void:
	_update_surface(delta)
	_move(delta)


func _move(_delta: float) -> void:
	var input: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	if input == Vector2.ZERO:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var forward: Vector3 = -global_transform.basis.z
	var right: Vector3 = global_transform.basis.x

	forward = (forward - surface_normal * forward.dot(surface_normal)).normalized()
	right = surface_normal.cross(forward).normalized()

	var direction: Vector3 = (forward * input.y + right * input.x).normalized()

	velocity = direction * move_speed

	move_and_slide()


func _update_surface(delta: float) -> void:
	var b: Basis = global_transform.basis

	var down_hit: Dictionary = _raycast(-b.y)

	var forward_dir: Vector3 = -b.z
	var front_hit: Dictionary = _raycast((forward_dir - b.y).normalized())

	var best_hit: Dictionary = {}

	if front_hit:
		best_hit = front_hit
	elif down_hit:
		best_hit = down_hit

	if best_hit.is_empty():
		return

	var new_normal: Vector3 = best_hit.normal

	var angle: float = rad_to_deg(surface_normal.angle_to(new_normal))

	if angle <= max_transition_angle:
		surface_normal = surface_normal.slerp(new_normal, rotation_speed * delta).normalized()

	var desired_forward: Vector3 = -b.z
	desired_forward = (desired_forward - surface_normal * desired_forward.dot(surface_normal)).normalized()

	if desired_forward.length_squared() < 0.001:
		desired_forward = b.x.cross(surface_normal).normalized()

	var target_basis: Basis = Basis.looking_at(desired_forward, surface_normal)

	global_transform.basis = global_transform.basis.slerp(
		target_basis,
		rotation_speed * delta
	).orthonormalized()

	global_position = best_hit.position + surface_normal * surface_distance


func _raycast(direction: Vector3) -> Dictionary:
	var state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state

	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + direction.normalized() * probe_distance
	)

	query.exclude = [self]

	return state.intersect_ray(query)

func _on_csg_combiner_3d_body_entered(body: Node3D) -> void:
	if body == self:
		spider.explode()
		died.emit()
