class_name BoardContainer
extends Node3D

signal saw_touched(saw:Saw);
signal saw_left(saw:Saw);

signal saw_missed(saw:Saw);

@export var spider:Crawler
@export var glow_overlay_material:StandardMaterial3D

@export var splitter:BodySplitPath;

## Array[Array[StaticBody3D]]
## for the quarter trunks
@export var preliminar_stage_cuts:Array[Array]

## to control the boards' stage
## number below 0 = preliminar hardcoded cuts
## (right now just for the quarter trunks)
## incremented on start of cutting
var current_stage:int = -2


func _enter_tree() -> void:
	GLB.board_container = self;



var touching:bool=false;
func board_area_entered(area:Area3D)->void:
	if area is Saw and not touching:
		touching = true;
		saw_touched.emit(area)

func board_area_exited(area:Area3D)->void:
	if area is Saw and touching:
		saw_left.emit(area)
		touching = false



var to_drop:Array[StaticBody3D]
func _on_saw_touched(_saw: Saw) -> void:
	to_drop = [];
	if current_stage < 0:
		var pre:Array = get_next_boards()
		for p:NodePath in pre:
			to_drop.append(get_node(p));

	else:
		roll_board_drop()
		
	for n:Node3D in to_drop:
		var mesh:MeshInstance3D = n.get_node("MeshInstance3D");
		mesh.material_overlay = glow_overlay_material.duplicate();
		glow_loop.bind(mesh).call_deferred()
	current_stage += 1;

func roll_board_drop()->void:
	var live_boards:Array = get_next_boards();
	if len(live_boards) > 1:
		#to_drop = [live_boards.pick_random()]
		to_drop = [live_boards[1]]

func get_next_boards()->Array:
	if current_stage < 0:
		return preliminar_stage_cuts.pop_front();
	elif current_stage == 0:
		return splitter.get_pieces(1);
	else:
		var pieces: = splitter.get_pieces(current_stage + 1).filter(filter_dropped_boards);
		return pieces;


func filter_dropped_boards(b:StaticBody3D)->bool:
	return not is_dropped(b)
func glow_loop(target:MeshInstance3D)->void:
	var m:StandardMaterial3D = target.material_overlay
	if not m:
		return;
	var t:=create_tween();
	t.set_trans(Tween.TRANS_CUBIC)
	t.tween_property(m, "albedo_color:a", .75, .25);
	t.tween_property(m, "albedo_color:a", 0, .5);
	t.tween_callback(glow_loop.bind(target))


func _on_saw_left(_saw: Saw) -> void:
	for b:StaticBody3D in to_drop:
		drop_board(b)
	splitter.set_stage_enabled(current_stage, false)
	splitter.set_stage_enabled(current_stage + 1, true)

func _on_saw_missed(saw: Saw) -> void:
	saw_touched.emit(saw);
	saw_left.emit(saw)

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
		

var finished_loops:Array[Material]
var collected_shapes:Array[CollisionShape3D]
func drop_board(b:StaticBody3D)->void:
	dropped_boards.append(b);
	spider.body.check_board_death(b);
	collected_shapes = []
	get_shapes(b)
	for c:CollisionShape3D in collected_shapes:
		c.queue_free();
	
	## do we just use default names?
	var mesh:MeshInstance3D = b.get_node("MeshInstance3D");
	finished_loops.append(mesh.material_overlay)
	glow_down(mesh)
	
	var rs:int=0;# rotation signal
	if mesh.global_position.x > global_position.x:
		rs=1;
	else:
		rs=-1;

	const td = 2;##tween duration
	var t := create_tween();
	if b.name == "top":
		t.tween_property(mesh, "global_position:x", mesh.global_position.z + 300, td)
	
	t.tween_property(mesh, "global_position:y", 0, td);
	if rs:
		var r:float = mesh.rotation_degrees.z + rs * 30
		t.parallel().tween_property(mesh, "rotation_degrees:z", r, td)

	if b in splitter.split_map_nodes:
		var boards:Array = splitter.split_map_nodes[b];
		for board:StaticBody3D in boards:
			drop_board(board)

func glow_down(mesh:MeshInstance3D)->void:
	var m:StandardMaterial3D = mesh.material_overlay
	var t:= create_tween();
	t.tween_property(m, "albedo_color:a", 0, 1);
	await t.finished;
	mesh.material_overlay = null
	
func get_shapes(b:Node)->void:
	for c in b.get_children():
		if c is CollisionShape3D:
			collected_shapes.append(c)
		get_shapes(c);
