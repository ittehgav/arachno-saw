extends Node3D

@export var spawner_box:CollisionShape3D;
@export var fly_scene:PackedScene
@export var splitter:BodySplitPath

var current_flies:Array[Fly];

const surface_mask = 3

func _on_board_container_ready()->void:
	refresh_flies();

func _on_board_container_saw_left(_saw: Saw) -> void:
	await get_tree().create_timer(.1).timeout
	refresh_flies();



func current_fly_types()->Array[Fly.Type]:
	var types:Array[Fly.Type]
	for f:Fly in current_flies:
		types.append(f.type);
	return types

var spawnable_boards:Array[StaticBody3D];
func refresh_flies()->void:
	refresh_spawn_region();
	
	while len(current_flies):
		if current_flies[0]:
			current_flies.pop_front().clear()
		else:
			current_flies.pop_front()

	var fly_count:int = max(1, 6 - GLB.board_container.current_stage)
	for _i:int in range(fly_count):
		current_flies.append(generate_fly())
	
func refresh_spawn_region()->void:
	var c:BoardContainer = GLB.board_container
	spawnable_boards = [];
	if c.current_stage >= 0:
		spawnable_boards = c.next_boards;
	else:
		for p:NodePath in c.next_boards:
			spawnable_boards.append(c.get_node(p));

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

func generate_fly(skip_transform:bool=false)->Fly:
	## surely will nuver generate a point with the exact same
	## position and basis as the generator (dead center of board)
	var hit:Dictionary;
	var aabb:AABB;
	if len(GLB.board_container.to_drop) == 0:
		## does this for the first few trunks that 
		## dont need the sophisticated version of the behvior
		aabb = box_aabb
	else:
		aabb = get_shapes_region(spawnable_boards, 5)
	
	var fly := fly_scene.instantiate() as Node3D;
	
	if not skip_transform:
		hit = get_random_surface_point(aabb)
		## looks tupid but works ispose
		fly.roll_type(current_fly_types());
		add_child(fly) ## tp target is added manually so type isnt rolled here
		fly.global_transform = hit.transform
		fly.global_position = hit.position

	if fly.type == Fly.Type.teleport and not skip_transform:
		var hit2:= get_random_surface_point(aabb);
		while hit2.is_empty() or hit2.transform.origin.distance_to(fly.transform.origin) < 30:
			hit2 = get_random_surface_point(aabb)
			
		var tp_fly:Fly = generate_fly(true);
		tp_fly.type = Fly.Type.teleport;
		
		add_child(tp_fly)
		tp_fly.global_transform = hit2.transform
		tp_fly.global_position = hit2.position
		
		
		tp_fly.tp_target = fly;
		fly.tp_target = tp_fly
		
		current_flies.append(tp_fly)
	return fly


func get_random_surface_point(
		region: AABB,
		step := 5.0,
		max_starts := 10,
		max_steps := 20,
		avoid_nodes: Array[Node3D] = [],
		min_distance := 0.0) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var center := region.get_center()
	var min_dist_sq := min_distance * min_distance

	for i in max_starts:
		var pos := _random_wall_point(region)

		for j in max_steps:
			var query := PhysicsRayQueryParameters3D.create(pos, center)
			query.collision_mask = surface_mask
			# query.collide_with_areas = true   # if you're using Area3Ds
			# query.collide_with_bodies = false

			var hit := space.intersect_ray(query)
			if hit and _is_far_enough(hit.position, avoid_nodes, min_dist_sq):
				hit["transform"] = _surface_transform(hit.position, hit.normal)
				return hit

			# Miss, or too close to an avoided node: step and try again
			var offset := center - pos
			var axes := [0, 1, 2]
			axes.sort_custom(func(a:int, b:int)->bool: return absf(offset[a]) > absf(offset[b]))
			for k in 2:
				var ax: int = axes[k]
				pos[ax] += signf(offset[ax]) * step

			if not region.has_point(pos):
				break
	return {}

func _is_far_enough(point: Vector3, nodes: Array[Node3D], min_dist_sq: float) -> bool:
	for n in nodes:
		if is_instance_valid(n) and point.distance_squared_to(n.global_position) < min_dist_sq:
			return false
	return true

func _surface_transform(point: Vector3, normal: Vector3, random_yaw := true) -> Transform3D:
	var up := normal.normalized()

	# Pick a reference that isn't parallel to the normal
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD

	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	var b := Basis(x, up, z)  # +Y is the object's "up", pointing away from the surface

	if random_yaw:
		b = b.rotated(up, randf() * TAU)  # spin around the normal

	return Transform3D(b, point)

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
