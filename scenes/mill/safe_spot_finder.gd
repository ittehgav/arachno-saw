extends Node3D
class_name SafeSpotFinder

# How far the probe reaches in/out of the face plane, and how much it's shrunk
# at the edges so shapes that only touch an edge don't count as touching the face.
const FACE_PROBE_DEPTH := 2
const EDGE_SHRINK := 1

func _enter_tree() -> void:
	GLB.safe_spot_finder = self

## Returns the center of the largest face of a BoxShape3D as a Transform3D
## relative to this node, with Y pointing away from the box. A ray is cast
## outward from that face. If it hits a collider, the opposite face is
## returned instead.
func get_free_biggest_face_transform(
		collision_shape: CollisionShape3D,
		ray_length := 1.0,
		collision_mask := 0xFFFFFFFF) -> Transform3D:
	var face := _get_biggest_face_transform(collision_shape, false)

	# Ray in world space, starting just outside the face so it can't start inside the shape
	var world_face: Transform3D = global_transform * face
	var normal: Vector3 = world_face.basis.y.normalized()
	var from: Vector3 = world_face.origin + normal * 0.01
	var to: Vector3 = from + normal * ray_length

	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask)

	# Ignore the body this shape belongs to (and this node, if it's a body)
	var exclude: Array[RID] = []
	var owner_body := collision_shape.get_parent() as CollisionObject3D
	if owner_body:
		exclude.append(owner_body.get_rid())

	query.exclude = exclude

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return _get_biggest_face_transform(collision_shape, true)

	return face


func _get_biggest_face_transform(collision_shape: CollisionShape3D, flip_side := false) -> Transform3D:
	var box := collision_shape.shape as BoxShape3D
	assert(box != null, "CollisionShape3D must have a BoxShape3D")

	# Shape transform relative to this node (includes any scale)
	var rel: Transform3D = global_transform.affine_inverse() * collision_shape.global_transform

	# Largest face is perpendicular to the smallest scaled dimension
	var scaled_size: Vector3 = box.size * rel.basis.get_scale().abs()
	var axis := 0
	if scaled_size.y < scaled_size[axis]:
		axis = 1
	if scaled_size.z < scaled_size[axis]:
		axis = 2

	var side := -1.0 if flip_side else 1.0

	var local_center := Vector3.ZERO
	local_center[axis] = side * box.size[axis] * 0.5

	var b := rel.basis.orthonormalized()
	var ex := b.x
	var ey := b.y
	var ez := b.z

	# Right-handed basis whose Y is the outward normal
	var basis_out: Basis
	match axis:
		0: basis_out = Basis(ez * side, ex * side, ey)
		1: basis_out = Basis(ex, ey * side, ez * side)
		_: basis_out = Basis(ey * side, ez * side, ex)

	return Transform3D(basis_out, rel * local_center)
