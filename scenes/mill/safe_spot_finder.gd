extends Node3D
class_name SafeSpotFinder

# How far the probe reaches in/out of the face plane, and how much it's shrunk
# at the edges so shapes that only touch an edge don't count as touching the face.
const FACE_PROBE_DEPTH := 5
const EDGE_SHRINK := 1

func _enter_tree() -> void:
	GLB.safe_spot_finder = self

## Takes bodies (StaticBody3D, RigidBody3D, CharacterBody3D, ...) that each have a
## child named "CollisionShape3D". Returns one Transform3D per body, placed at the
## exact center of a random face of that child's BoxShape3D that isn't touching any
## other body in `bodies`. The transform's Z axis points out of the face.
## Bodies with no free face are skipped.
##
## Transforms are local to `relative_to`. If it's null, each one is local to its
## body's parent, i.e. the same space as `body.transform`.
func get_free_face_transforms(bodies: Array, relative_to: Node3D = null) -> Array[Transform3D]:
	var result: Array[Transform3D] = []

	# Resolve each body to its CollisionShape3D child.
	var entries: Array = []  # [body, shape_node] pairs
	var group := {}          # shape nodes that count as blockers
	for body:Node3D in bodies:
		if not is_instance_valid(body) or not body is PhysicsBody3D:
			push_warning("Entry is not a valid PhysicsBody3D, skipping.")
			continue
		var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape_node == null:
			push_warning("%s has no child named CollisionShape3D, skipping." % body.name)
			continue
		entries.append([body, shape_node])
		group[shape_node] = true

	for entry:Array in entries:
		var body: PhysicsBody3D = entry[0]
		var shape_node: CollisionShape3D = entry[1]

		if not shape_node.is_inside_tree():
			continue

		var box := shape_node.shape as BoxShape3D
		if box == null:
			push_warning("%s's shape is not a BoxShape3D, skipping." % body.name)
			continue

		var gt := shape_node.global_transform
		var rot := gt.basis.orthonormalized()
		var half := box.size * gt.basis.get_scale().abs() * 0.5

		var faces: Array[Vector2i] = []
		for axis in 3:
			faces.append(Vector2i(axis, 1))
			faces.append(Vector2i(axis, -1))
		faces.shuffle()

		for face in faces:
			var axis := face.x
			var normal: Vector3 = rot[axis] * face.y
			var center := gt.origin + normal * half[axis]

			if _is_face_free(shape_node, group, rot, center, axis, half):
				var x_axis: Vector3 = rot[(axis + 1) % 3]
				var y_axis := normal.cross(x_axis)
				var global_t := Transform3D(Basis(x_axis, y_axis, normal), center)

				var space_node: Node3D = relative_to if relative_to != null \
						else body.get_parent_node_3d()
				if space_node != null:
					var local_t := space_node.global_transform.affine_inverse() * global_t
					local_t.basis = local_t.basis.orthonormalized()
					result.append(local_t)
				else:
					result.append(global_t)
				break

	return result


func _is_face_free(shape_node: CollisionShape3D, group: Dictionary, rot: Basis,
		center: Vector3, axis: int, half: Vector3) -> bool:
	# Thin slab covering the face, straddling the face plane.
	var size := half * 2.0
	for k in 3:
		size[k] = max(size[k] - EDGE_SHRINK, 0.001)
	size[axis] = FACE_PROBE_DEPTH * 2.0

	var probe := BoxShape3D.new()
	probe.size = size
	probe.margin = 0.0

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = probe
	params.transform = Transform3D(rot, center)
	params.collide_with_bodies = true
	params.collide_with_areas = true

	var space := shape_node.get_world_3d().direct_space_state
	for hit in space.intersect_shape(params, 256):
		var collider := hit.collider as CollisionObject3D
		if collider == null:
			continue
		# Map the hit back to the CollisionShape3D node that produced it.
		var owner_id := collider.shape_find_owner(hit.shape)
		var hit_node := collider.shape_owner_get_owner(owner_id)
		if hit_node != shape_node and group.has(hit_node):
			return false  # touching another shape from the array

	return true
