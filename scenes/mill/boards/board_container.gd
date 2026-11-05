class_name BoardContainer
extends Node3D

signal saw_touched(saw:Saw);
signal saw_left(saw:Saw);
signal boards_changed;

signal board_dropped(board:StaticBody3D);


@export var spider:Crawler


@export var splitter:BodySplitPath;

## Array[Array[StaticBody3D]]
## for the quarter trunks
@export var preliminar_stage_cuts:Array[Array]

## for finding safe boards in prelim stage
@export var top_trunk:StaticBody3D;
@export var bottom_trunk:StaticBody3D;
@export var left_trunk:StaticBody3D;
@export var right_trunk:StaticBody3D;

@export var full_board:StaticBody3D



## to control the boards' stage
## number below 0 = preliminar hardcoded cuts
## (right now just for the quarter trunks)
## incremented on start of cutting
var current_stage:int = -2

var next_boards:Array;


var safe_board:StaticBody3D:
	get():
		print(current_stage)
		if current_stage == -2:
			return top_trunk;
		elif current_stage == -1:
			return full_board;
		return splitter.get_remaining_board(current_stage)

func _enter_tree() -> void:
	GLB.board_container = self;

func _ready()->void:
	set_to_drop()


var touching:bool=false;
func board_area_entered(area:Area3D)->void:
	if area is Saw and not touching:
		touching = true;
		saw_touched.emit(area)
		

func board_area_exited(area:Area3D)->void:
	if area is Saw and touching:
		touching = false
		saw_left.emit(area)

var glowing:Array[MeshInstance3D]
var to_drop:Array[StaticBody3D]
func _on_saw_touched(_saw: Saw) -> void:
	for n:Node3D in to_drop:
		var to_glow:Array[MeshInstance3D] = get_board_meshes(n)
		for mesh:MeshInstance3D in to_glow:
				generate_glow_material(mesh)
				glowing.append(mesh)
				glow_loop(mesh)
	current_stage += 1;

func get_board_meshes(board:StaticBody3D)->Array[MeshInstance3D]:
	var meshes:Array[MeshInstance3D];
	for c:Node in board.get_children():
		if c is MeshInstance3D:
			meshes.append(c);
	return meshes

func glow_loop(mesh:MeshInstance3D)->void:
	if mesh not in glowing:
		return;
	var m:StandardMaterial3D = mesh.material_override
	var t:=create_tween();
	t.set_trans(Tween.TRANS_CUBIC)
	t.tween_property(m, "albedo_color:s", 1, .25);
	t.tween_property(m, "albedo_color:s", 0, .5);
	
	await t.finished;
	if mesh and mesh in glowing:
		glow_loop(mesh)



func generate_glow_material(m:MeshInstance3D)->void:
	## also duplicates them here and makes sure the reference is consistent
	if m.mesh is BoxMesh:
		m.material_override = m.mesh.material.duplicate()
		m.mesh.material = null
	else: ## m.mesh is ArrayMesh
		m.material_override = m.mesh.surface_get_material(0).duplicate()
		m.mesh.surface_set_material(0, null)






func filter_dropped_boards(b:StaticBody3D)->bool:
	return not is_dropped(b)

func set_to_drop()->void:
	to_drop = [];
	
	if current_stage < 0:
		var pre:Array = preliminar_stage_cuts[current_stage + 2];
		for p:NodePath in pre:
			to_drop.append(get_node(p));
	else:
		to_drop = splitter.get_pieces(current_stage + 1).filter(func(p:StaticBody3D)->bool:return p.get_meta(BoardSplitter.FALLS_KEY));

@onready var total_stages := splitter.get_split_count();
func _on_saw_left(_saw: Saw) -> void:
	for b:StaticBody3D in to_drop:
		b.get_node("CollisionShape3D").set_deferred("disabled", true)
		drop_board(b)

	
	## rolling board drops immediately so flies can 
	## spawn on dropping side before next saw_touched
	if current_stage == total_stages + 1 and not spider.dead:
		spider.win_run();
		return
	var stage:Array[StaticBody3D] = splitter.get_pieces(current_stage + 1);
	for p:StaticBody3D in stage:
		p.set_collision_layer_value(1, true)
		p.set_collision_layer_value(5, false)

	splitter.set_stage_enabled(current_stage, false)
	splitter.set_stage_enabled(current_stage + 1, true)
	
	set_to_drop()
	await get_tree().physics_frame;
	boards_changed.emit.call_deferred()



var dropped_boards:Array[StaticBody3D];
## boards that have fallen on the ground
## their children are all deleted but the body remains 
## as keys to track which dropped parts are no longer interactive

func is_dropped(b:StaticBody3D)->bool:
	var map:Dictionary = splitter.split_map_nodes
	for k:StaticBody3D in dropped_boards:
		if k in map and b in map[k]:
			return true;
	return false
		

var collected_shapes:Array[CollisionShape3D]
func drop_board(b:StaticBody3D)->void:
	dropped_boards.append(b);
	b.set_collision_layer_value(5, false)## to not have them get in the way of fly position roll
	collected_shapes = []
	get_shapes(b)
	for c:CollisionShape3D in collected_shapes:
		c.queue_free();
	
	## do we just use default names?
	
	var to_glow_down:Array[MeshInstance3D] = get_board_meshes(b)
	for mesh:MeshInstance3D in to_glow_down:
		const td = 2;##tween duration
		var t := create_tween();
		var m:Material = mesh.material_override;
		if not m:
			m = mesh.mesh.material;
		t.tween_property(m, "albedo_color:a", 0, td);
		t.tween_callback(mesh.queue_free)


	if b in splitter.split_map_nodes:
		var boards:Array = splitter.split_map_nodes[b];
		for board:StaticBody3D in boards:
			drop_board(board)
			
	board_dropped.emit(b);


	
func get_shapes(b:Node)->void:
	for c in b.get_children():
		if c is CollisionShape3D:
			collected_shapes.append(c)
		get_shapes(c);
		
		
class FaceData:
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var n: Vector3

	func _init(p_a: Vector3, p_b: Vector3, p_c: Vector3, p_n: Vector3) -> void:
		a = p_a
		b = p_b
		c = p_c
		n = p_n


## Returns a random Transform3D lying on a free face of one of the given bodies,
## with its Y axis (up) pointing away from the face, or null if no free face exists.
## Non-StaticBody3D elements in the array are ignored.
## Call while the bodies are in the tree, ideally from _physics_process.
## Supports BoxShape3D and ConcavePolygonShape3D.
func get_free_face_transform(bodies: Array, probe_offset: float = 0.02) -> Variant:
	var faces: Array[FaceData] = []
	var world: World3D = null

	for obj: Variant in bodies:
		var body: StaticBody3D = obj as StaticBody3D
		if body == null or not body.is_inside_tree():
			continue
		if world == null:
			world = body.get_world_3d()
		for child: Node in body.get_children():
			var cs: CollisionShape3D = child as CollisionShape3D
			if cs == null or cs.disabled or cs.shape == null:
				continue
			_collect_faces(cs, faces)

	if world == null or faces.is_empty():
		return null

	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	faces.shuffle()

	for f: FaceData in faces:
		if not _is_face_free(space, f, probe_offset):
			continue
		var p: Vector3 = (f.a + f.b + f.c) / 3.0
		var up: Vector3 = f.n
		var x: Vector3 = (f.b - f.a).normalized()
		x = (x - up * x.dot(up)).normalized()  # keep x perpendicular to up
		var z: Vector3 = x.cross(up)
		return Transform3D(Basis(x, up, z), p)

	return null


func _collect_faces(cs: CollisionShape3D, out: Array[FaceData]) -> void:
	var xf: Transform3D = cs.global_transform
	var nbasis: Basis = xf.basis.inverse().transposed()
	var shape: Shape3D = cs.shape

	if shape is BoxShape3D:
		var h: Vector3 = (shape as BoxShape3D).size * 0.5
		for axis: int in 3:
			for dir: float in [-1.0, 1.0]:
				var n: Vector3 = Vector3.ZERO
				n[axis] = dir
				var u: Vector3 = Vector3.ZERO
				u[(axis + 1) % 3] = h[(axis + 1) % 3]
				var v: Vector3 = Vector3.ZERO
				v[(axis + 2) % 3] = h[(axis + 2) % 3]
				var c: Vector3 = n * h[axis]
				var p0: Vector3 = xf * (c - u - v)
				var p1: Vector3 = xf * (c + u - v)
				var p2: Vector3 = xf * (c + u + v)
				var p3: Vector3 = xf * (c - u + v)
				var gn: Vector3 = (nbasis * n).normalized()
				out.append(FaceData.new(p0, p1, p2, gn))
				out.append(FaceData.new(p0, p2, p3, gn))

	elif shape is ConcavePolygonShape3D:
		var tris: PackedVector3Array = (shape as ConcavePolygonShape3D).get_faces()
		for i: int in range(0, tris.size(), 3):
			var a: Vector3 = xf * tris[i]
			var b: Vector3 = xf * tris[i + 1]
			var c: Vector3 = xf * tris[i + 2]
			if (b - a).cross(c - a).length_squared() < 1e-10:
				continue  # degenerate triangle
			var n: Vector3 = Plane(a, b, c).normal
			out.append(FaceData.new(a, b, c, n))


func _sample_points(f: FaceData) -> PackedVector3Array:
	var centroid: Vector3 = (f.a + f.b + f.c) / 3.0
	var pts: PackedVector3Array = PackedVector3Array([centroid])
	pts.append(centroid.lerp(f.a, 0.8))
	pts.append(centroid.lerp(f.b, 0.8))
	pts.append(centroid.lerp(f.c, 0.8))
	return pts


func _is_face_free(space: PhysicsDirectSpaceState3D, f: FaceData, offset: float) -> bool:
	var query: PhysicsPointQueryParameters3D = PhysicsPointQueryParameters3D.new()
	query.collide_with_bodies = true
	query.collide_with_areas = false
	for p: Vector3 in _sample_points(f):
		query.position = p + f.n * offset
		if not space.intersect_point(query, 1).is_empty():
			return false
	return true
