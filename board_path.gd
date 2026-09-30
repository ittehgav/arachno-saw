@tool
class_name BodySplitPath
extends Path3D

const META_KEY := &"generated_split"
const STAGE_KEY := &"split_stage"
const EPS := 0.0001

@export var source_body: StaticBody3D
@export var output_root: Node3D
@export var cuts: Array[SplitCut] = []
## true: generate the pieces after every cut (stages 1..N).
## false: only generate the pieces after the last cut.
@export var generate_all_stages := true
## Move each piece's origin to its own center (children are offset to compensate).
@export var recenter_pieces := true
@export_tool_button("Generate Splits") var generate_action := generate_splits


func generate_splits() -> void:
	if source_body == null or output_root == null:
		push_warning("BodySplitPath: assign source_body and output_root first.")
		return

	var reference := _read_boxes(source_body)
	if reference.is_empty():
		push_warning("BodySplitPath: source_body has no BoxShape3D / BoxMesh children.")
		return

	# Compute every stage as data first, in the source body's local space.
	var stages: Array = []  # stages[k] = Array[Dictionary] of pieces after cut k+1
	var current: Array[Dictionary] = [reference]
	for cut in cuts:
		if cut == null:
			continue
		var next_pieces: Array[Dictionary] = []
		var any_split := false
		for piece in current:
			var bounds := _union(piece)
			var lo := bounds.position[cut.axis]
			var hi := bounds.end[cut.axis]
			if cut.offset <= lo + EPS or cut.offset >= hi - EPS:
				next_pieces.append(piece)  # plane misses this piece
				continue
			var negative := _clip(piece, cut.axis, cut.offset, false)
			var positive := _clip(piece, cut.axis, cut.offset, true)
			if negative.is_empty() or positive.is_empty():
				next_pieces.append(piece)
				continue
			any_split = true
			next_pieces.append(negative)
			next_pieces.append(positive)
		if not any_split:
			push_warning("BodySplitPath: cut at %s misses every piece; skipped." % cut.offset)
			continue
		current = next_pieces
		stages.append(current)

	if stages.is_empty():
		push_warning("BodySplitPath: no valid cuts, nothing generated.")
		return

	_clear_generated()

	var first_stage := 0 if generate_all_stages else stages.size() - 1
	for s in range(first_stage, stages.size()):
		var stage_pieces: Array = stages[s]
		for i in stage_pieces.size():
			_build_body(s + 1, i, stage_pieces[i], reference.keys())


# --- Public helpers for the simulation to call later --------------------------

## stage < 0 returns every generated piece. Stage numbers start at 1 (after the first cut).
func get_pieces(stage: int = -1) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if output_root:
		for c in output_root.get_children():
			if c.has_meta(META_KEY) and (stage < 0 or c.get_meta(STAGE_KEY) == stage):
				result.append(c)
	return result


func set_stage_enabled(stage: int, enabled: bool) -> void:
	for body in get_pieces(stage):
		_set_body_enabled(body, enabled)


# --- Internals -----------------------------------------------------------------

## Reads every direct BoxShape3D / BoxMesh child as an AABB in the body's local space.
## Assumes those children have no rotation or scale.
func _read_boxes(body: Node3D) -> Dictionary:
	var boxes := {}
	_collect_boxes(body, body, Vector3.ZERO, boxes)
	return boxes
	
func _collect_boxes(body: Node3D, node: Node, offset: Vector3, boxes: Dictionary) -> void:
	for child in node.get_children():
		if not (child is Node3D):
			continue
		var pos: Vector3 = offset + child.position
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var size: Vector3 = child.shape.size
			boxes[body.get_path_to(child)] = AABB(pos - size * 0.5, size)
		elif child is MeshInstance3D and child.mesh is BoxMesh:
			var size: Vector3 = child.mesh.size
			boxes[body.get_path_to(child)] = AABB(pos - size * 0.5, size)
		_collect_boxes(body, child, pos, boxes)
## Body-space position of a node's parent (zero when the parent is the body itself).
func _offset_in_body(body: Node3D, node: Node) -> Vector3:
	var offset := Vector3.ZERO
	var p := node.get_parent()
	while p != body and p is Node3D:
		offset += p.position
		p = p.get_parent()
	return offset

func _union(piece: Dictionary) -> AABB:
	var result := AABB()
	var first := true
	for box: AABB in piece.values():
		result = box if first else result.merge(box)
		first = false
	return result


## Returns a new piece with every box clipped to one side of the plane.
## Boxes that end up with no thickness are dropped.
func _clip(piece: Dictionary, axis: int, offset: float, keep_positive: bool) -> Dictionary:
	var out := {}
	for path:NodePath in piece:
		var box: AABB = piece[path]
		var lo := box.position[axis]
		var hi := box.end[axis]
		if keep_positive:
			lo = maxf(lo, offset)
		else:
			hi = minf(hi, offset)
		if hi - lo <= EPS:
			continue
		var pos := box.position
		var size := box.size
		pos[axis] = lo
		size[axis] = hi - lo
		out[path] = AABB(pos, size)
	return out


func _build_body(stage: int, index: int, piece: Dictionary, all_paths: Array) -> StaticBody3D:
	var body := source_body.duplicate() as StaticBody3D
	body.name = "%s_stage%02d_%02d" % [source_body.name, stage, index]
	body.set_meta(META_KEY, true)
	body.set_meta(STAGE_KEY, stage)

	var center := _union(piece).get_center() if recenter_pieces else Vector3.ZERO

	for path: NodePath in all_paths:
		var child := body.get_node(path)
		if not piece.has(path):
			# This box lies entirely on the other side of a cut.
			child.get_parent().remove_child(child)
			child.queue_free()
			continue

		var box: AABB = piece[path]
		child.position = box.get_center() - center - _offset_in_body(body, child)

		if child is CollisionShape3D:
			# Fresh, independent BoxShape3D; settings like margin carry over.
			var shape := child.shape.duplicate() as BoxShape3D
			shape.size = box.size
			child.shape = shape
		elif child is MeshInstance3D:
			var original := source_body.get_node(path) as MeshInstance3D
			var source_mesh := original.mesh as BoxMesh

			var mesh := source_mesh.duplicate() as BoxMesh
			mesh.size = box.size
			mesh.material = source_mesh.material  # the BoxMesh's own material
			child.mesh = mesh

			# Same material resources as the original node, applied after the new mesh
			# is assigned so nothing gets reset by the mesh change.
			child.material_override = original.material_override
			child.material_overlay = original.material_overlay
			for s in original.get_surface_override_material_count():
				child.set_surface_override_material(s, original.get_surface_override_material(s))

	output_root.add_child(body)
	body.global_transform = source_body.global_transform * Transform3D(Basis.IDENTITY, center)

	# Needed so generated nodes show up in the scene tree and get saved.
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	if scene_root:
		body.owner = scene_root
		for n in body.find_children("*", "", true, false):
			n.owner = scene_root

	_set_body_enabled(body, false)
	return body

func _set_body_enabled(body: StaticBody3D, enabled: bool) -> void:
	body.visible = enabled
	body.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	for shape_node in body.find_children("*", "CollisionShape3D", true, false):
		shape_node.set_deferred("disabled", not enabled)


func _clear_generated() -> void:
	for c in output_root.get_children():
		if c.has_meta(META_KEY):
			output_root.remove_child(c)
			c.queue_free()

@export var follow:PathFollow3D
## speed = % of path moved per second
@export var speed:int = 5 
var moving:bool=false;


func _physics_process(delta: float) -> void:
	if moving:
		follow.progress_ratio += delta * .01 * speed;
