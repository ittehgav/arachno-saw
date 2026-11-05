extends Node3D
class_name SafeSpotFinder


func _enter_tree() -> void:
	GLB.safe_spot_finder = self

## Returns global Transforms on every free face of a box CollisionShape3D (bottom face excluded).
## Each transform's origin is the face center and its Y axis is the face's outward normal.
## Returns an empty array if no face is free.
## Must be called during _physics_process (the physics space is locked otherwise).
func get_free_surface_transforms(shape_node: CollisionShape3D, probe_margin: float = 1) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	var box_shape: BoxShape3D = shape_node.shape as BoxShape3D
	if box_shape == null:
		return result

	var shape_xform: Transform3D = shape_node.global_transform
	var half_extents: Vector3 = (box_shape.size * shape_xform.basis.get_scale()).abs() * 0.5
	var face_basis: Basis = shape_xform.basis.orthonormalized()
	var space_state: PhysicsDirectSpaceState3D = shape_node.get_world_3d().direct_space_state
	var parent_body: CollisionObject3D = shape_node.get_parent() as CollisionObject3D

	# Build the 6 faces and find the bottom one (normal most aligned with global -Y)
	var face_axes: PackedInt32Array = PackedInt32Array()
	var face_normals: Array[Vector3] = []
	var bottom_idx: int = 0
	var lowest_y: float = INF
	for axis_idx: int in 3:
		for sign_val: float in [-1.0, 1.0]:
			var local_normal: Vector3 = Vector3.ZERO
			local_normal[axis_idx] = sign_val
			var world_normal: Vector3 = face_basis * local_normal
			if world_normal.y < lowest_y:
				lowest_y = world_normal.y
				bottom_idx = face_normals.size()
			face_axes.append(axis_idx)
			face_normals.append(world_normal)

	for face_idx: int in face_normals.size():
		if face_idx == bottom_idx:
			continue
		var axis_idx: int = face_axes[face_idx]
		var face_normal: Vector3 = face_normals[face_idx]
		var face_center: Vector3 = shape_xform.origin + face_normal * half_extents[axis_idx]

		# Thin box straddling the face plane, slightly smaller than the face
		var probe_shape: BoxShape3D = BoxShape3D.new()
		var probe_size: Vector3 = half_extents * 2.0 * 0.9
		probe_size[axis_idx] = probe_margin * 2.0
		probe_shape.size = probe_size

		var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
		query.shape_rid = probe_shape.get_rid()
		query.transform = Transform3D(face_basis, face_center)
		query.collide_with_bodies = true
		query.collide_with_areas = false

		var is_touching: bool = false
		var hits: Array[Dictionary] = space_state.intersect_shape(query, 32)
		for hit: Dictionary in hits:
			var hit_collider: Object = hit["collider"]
			var hit_shape_idx: int = hit["shape"]
			# Ignore the tested shape itself, but count sibling shapes on the same body
			if parent_body != null and hit_collider == parent_body:
				var shape_owner_id: int = parent_body.shape_find_owner(hit_shape_idx)
				if parent_body.shape_owner_get_owner(shape_owner_id) == shape_node:
					continue
			is_touching = true
			break
		if is_touching:
			continue

		# Orientation: Y = outward normal, X/Z follow the box's own axes
		var tangent: Vector3 = face_basis[(axis_idx + 1) % 3]
		var axis_z: Vector3 = tangent.cross(face_normal).normalized()
		var axis_x: Vector3 = face_normal.cross(axis_z).normalized()
		result.append(Transform3D(Basis(axis_x, face_normal, axis_z), face_center))

	return result
