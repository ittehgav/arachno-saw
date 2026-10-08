extends Node3D

@export var spawner_box:CollisionShape3D;
@export var fly_scene:PackedScene



func _ready()->void:
	current_fly = generate_fly();

var box_aabb:AABB:
	get():
		var box:=spawner_box.shape as BoxShape3D;
		var local_aabb := AABB(-box.size/2.0, box.size);
		return spawner_box.global_transform * local_aabb


func get_shapes_region(bodies: Array[StaticBody3D], margin := 0.0) -> AABB:
	var result := AABB()
	var found := false
	var shapes:Array[CollisionShape3D];
	for b:StaticBody3D in bodies:
		shapes.append(b.get_node("CollisionShape3D"));

	for node in shapes:
		if node == null or node.shape == null:
			continue

		var local_aabb: AABB
		if node.shape is BoxShape3D:
			var size: Vector3 = node.shape.size
			local_aabb = AABB(-size / 2.0, size)
		else:
			local_aabb = node.shape.get_debug_mesh().get_aabb()

		var global_aabb := node.global_transform * local_aabb

		if found:
			result = result.merge(global_aabb)
		else:
			result = global_aabb
			found = true

	return result.grow(margin) if found else result

func generate_fly()->Fly:
	var aabb:AABB;
	if len(GLB.board_container.to_drop) == 0:
		## does this for the first few trunks that 
		## dont need the sophisticated version of the behvior
		aabb = box_aabb
	else:
		aabb = get_shapes_region(GLB.board_container.to_drop, 5)
	var hit := get_random_surface_point(aabb)
	var stop:int = 0;
	while len(GLB.board_container.to_drop) > 0 and hit.collider not in GLB.board_container.to_drop:
		print(GLB.board_container.to_drop, hit.collider)
		hit = get_random_surface_point(aabb)
		stop += 1;
		if stop == 10:
			breakpoint
	if not hit.is_empty():
		var fly := fly_scene.instantiate() as Node3D
		add_child(fly)
		fly.global_transform = hit.transform
		return fly
	return null

func get_random_surface_point(region: AABB, step := 5.0, max_starts := 50, max_steps := 50) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var center := region.get_center()

	for i in max_starts:
		var pos := _random_wall_point(region)

		for j in max_steps:
			var query := PhysicsRayQueryParameters3D.create(pos, center);
			query.collision_mask = 5;
			# query.collision_mask = ...  # your StaticBody3D layer
			var hit := space.intersect_ray(query)
			if hit:
				hit["transform"] = _surface_transform(hit.position, hit.normal)
				return hit

			var offset := center - pos
			var axes := [0, 1, 2]
			axes.sort_custom(func(a:int, b:int)->bool: return absf(offset[a]) > absf(offset[b]))
			for k in 2:
				var ax: int = axes[k]
				pos[ax] += signf(offset[ax]) * step

			if not region.has_point(pos):
				break
	return {}

func _surface_transform(point: Vector3, normal: Vector3, random_yaw := true) -> Transform3D:
	var up := normal.normalized()

	# Pick a reference that isn't parallel to the normal
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD

	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var basis := Basis(x, up, z)  # +Y is the object's "up", pointing away from the surface

	if random_yaw:
		basis = basis.rotated(up, randf() * TAU)  # spin around the normal

	return Transform3D(basis, point)

func _random_wall_point(region: AABB) -> Vector3:
	var s := region.size
	# Two faces per axis, picked by area so the walls are covered evenly
	var areas := [s.y * s.z, s.y * s.z, s.x * s.z, s.x * s.z, s.x * s.y, s.x * s.y]
	var r :float= randf() * (areas[0] * 2.0 + areas[2] * 2.0 + areas[4] * 2.0)
	var face := 0
	for f in 6:
		r -= areas[f]
		if r <= 0.0:
			face = f
			break

	var p := region.position + Vector3(randf() * s.x, randf() * s.y, randf() * s.z)
	match face:
		0: p.x = region.position.x
		1: p.x = region.end.x
		2: p.y = region.position.y
		3: p.y = region.end.y
		4: p.z = region.position.z
		5: p.z = region.end.z
	return p


var current_fly:Fly
func _on_board_container_saw_left(_saw: Saw) -> void:

	await get_tree().create_timer(.1).timeout
	if current_fly:
		current_fly.queue_free();
		current_fly = generate_fly()
