extends Node3D
class_name SafeSpotFinder

@export var top:RayCast3D
@export var bottom:RayCast3D
@export var left:RayCast3D
@export var right:RayCast3D
@export var back:RayCast3D
@export var front:RayCast3D
@onready var all_casts := [top, bottom, left, right, back, front]

var safe_transforms:Array[Transform3D];

func _enter_tree() -> void:
	GLB.safe_spot_finder = self;

func _ready()->void:
	var c:Node3D = GLB.board_container
	safe_transforms = find_safe_regions([c.top_trunk, c.bottom_trunk, c.right_trunk, c.left_trunk])


func _on_board_container_boards_changed() -> void:
	var safe_boards := GLB.board_container.safe_boards;
	safe_transforms = find_safe_regions(safe_boards)


@export var scan_extent := Vector2(2.0, 2.0)   # half-size of the area each ray may slide across
@export var scan_step := 0.1                   # spacing between scan positions

## Slides each ray across its face (nearest positions first), keeping it aimed at this
## node's center, until it touches one of safe_regions or the scan finishes with no hit.
## Returns one global transform per ray that found a safe region, in the order
## top, bottom, left, right, back, front (rays with no hit are skipped).
## Each transform sits at the contact point with its up axis facing the ray.
func find_safe_regions(safe_regions: Array) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	var center: Vector3 = global_position

	var rays: Array[RayCast3D] = [top, bottom, left, right, back, front]
	var axes_a: Array[Vector3] = [Vector3.RIGHT, Vector3.RIGHT, Vector3.UP, Vector3.UP, Vector3.RIGHT, Vector3.RIGHT]
	var axes_b: Array[Vector3] = [Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.UP, Vector3.UP]

	var offsets: Array[Vector2] = _build_offsets()

	for i: int in rays.size():
		var ray: RayCast3D = rays[i]
		var start_pos: Vector3 = ray.global_position
		var hit: StaticBody3D = null

		for offset: Vector2 in offsets:
			var shift: Vector3 = global_basis * (axes_a[i] * offset.x + axes_b[i] * offset.y)
			ray.global_position = start_pos + shift
			ray.target_position = ray.to_local(center)
			ray.force_raycast_update()

			hit = _get_safe_body_hit(ray, safe_regions)
			if hit != null:
				break

		if hit != null:
			var hit_point: Vector3 = ray.get_collision_point()
			transforms.append(Transform3D(_basis_with_up(ray.global_position - hit_point), hit_point))
		else:
			# Scan completed with nothing found: restore the original position.
			ray.global_position = start_pos
			ray.target_position = ray.to_local(center)

	return transforms


## Builds an orthonormal basis whose Y axis is the given direction.
func _basis_with_up(direction: Vector3) -> Basis:
	var up: Vector3 = direction.normalized() if direction.length_squared() > 0.0001 else Vector3.UP
	var ref: Vector3 = Vector3.RIGHT
	if absf(up.dot(ref)) > 0.99:
		ref = Vector3.BACK
	var z: Vector3 = ref.cross(up).normalized()
	var x: Vector3 = up.cross(z)
	return Basis(x, up, z)


func _build_offsets() -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	var nx: int = int(scan_extent.x / scan_step)
	var ny: int = int(scan_extent.y / scan_step)
	for i: int in range(-nx, nx + 1):
		for j: int in range(-ny, ny + 1):
			offsets.append(Vector2(i, j) * scan_step)
	offsets.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
	return offsets


func _get_safe_body_hit(ray: RayCast3D, safe_regions: Array) -> StaticBody3D:
	if not ray.is_colliding():
		return null
	var collider: StaticBody3D = ray.get_collider() as StaticBody3D
	if collider != null and safe_regions.has(collider):
		return collider
	return null
