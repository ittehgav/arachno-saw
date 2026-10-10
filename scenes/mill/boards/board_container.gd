class_name BoardContainer
extends Node3D

signal saw_touched(saw:Saw);
signal saw_left(saw:Saw);

## erm actually is called from another script
@warning_ignore("unused_signal") 
signal saw_missed(saw:Saw);

@export var spider:Crawler


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
		var mesh:MeshInstance3D = n.get_node("MeshInstance3D");
		generate_glow_material(mesh)
		glowing.append(mesh)
		glow_loop(mesh)
	current_stage += 1;

func glow_loop(mesh:MeshInstance3D)->void:
	if mesh not in glowing:
		return;
	var m:ShaderMaterial = mesh.material_override
	var t:=create_tween();
	t.set_trans(Tween.TRANS_CUBIC)
	var light_r:float = m.get_shader_parameter("light_color").r;

	var dark_r:float = m.get_shader_parameter("dark_color").r;

	t.tween_property(m, "shader_parameter/light_color:r", 1, .25);
	t.parallel().tween_property(m, "shader_parameter/dark_color:r", 1, .25)
	
	t.tween_property(m, "shader_parameter/light_color:r", light_r, .5);
	t.parallel().tween_property(m, "shader_parameter/dark_color:r", dark_r, .5);
	t.tween_callback(glow_loop.bind(mesh))



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
		var pre:Array = get_next_boards()
		for p:NodePath in pre:
			to_drop.append(get_node(p));
	else:
		roll_board_drop()

func roll_board_drop()->void:
	var live_boards:Array = get_next_boards();
	for b:StaticBody3D in live_boards:
		## enabling boards from start state 
		## collsion layer 3
		b.get_node("CollisionShape3D").disabled = false;
	if len(live_boards) > 1:
		to_drop = [live_boards.pick_random()]

func get_next_boards()->Array:
	if current_stage < 0:
		return preliminar_stage_cuts.pop_front();
	elif current_stage == 0:
		return splitter.get_pieces(1);
	else:
		var pieces: = splitter.get_pieces(current_stage + 1).filter(filter_dropped_boards);
		return pieces;

func _on_saw_left(_saw: Saw) -> void:
	for b:StaticBody3D in to_drop:
		drop_board(b)
	set_to_drop()
	## rolling board drops immediately so flies can 
	## spawn on dropping side before next board_touched
	
	var stage:Array[StaticBody3D] = splitter.get_pieces(current_stage + 1);
	for p:StaticBody3D in stage:
		p.set_collision_layer_value(1, true)
		p.set_collision_layer_value(5, false)

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
		

var collected_shapes:Array[CollisionShape3D]
func drop_board(b:StaticBody3D)->void:
	dropped_boards.append(b);
	spider.body.check_board_death(b);
	b.set_collision_layer_value(5, false)## to not have them get in the way of fly position roll
	collected_shapes = []
	get_shapes(b)
	for c:CollisionShape3D in collected_shapes:
		c.queue_free();
	
	## do we just use default names?
	var mesh:MeshInstance3D = b.get_node("MeshInstance3D");
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
	var m:Material = mesh.material_override;
	if not m:
		return;
	var t:= create_tween();
	t.tween_property(m, "shader_parameter/light_color:s", 0, 1);
	t.tween_property(m, "shader_parameter/dark_color:s", 0, 1);
	glowing.erase(mesh)
	
func get_shapes(b:Node)->void:
	for c in b.get_children():
		if c is CollisionShape3D:
			collected_shapes.append(c)
		get_shapes(c);
