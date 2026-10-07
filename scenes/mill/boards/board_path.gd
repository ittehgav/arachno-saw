@tool
class_name BodySplitPath
extends Path3D

const BOARD_GROUP := &"boards"
const META_KEY := &"generated_split"
const STAGE_KEY := &"split_stage"
const EPS := 0.0001

const MARKER_META := &"split_center_marker"

@export var saw_scene:PackedScene
@export var pre_curve:Curve3D;
@export_tool_button("Generate Splits") var generate_action := generate_splits
@export_tool_button("Create Split Markers") var markers_action := create_split_markers



@export var source_body: StaticBody3D
@export var output_root: Node3D
@export var cuts: Array[SplitCut] = []
@export var markers:Node3D;
## true: generate the pieces after every cut (stages 1..N).
## false: only generate the pieces after the last cut.
@export var generate_all_stages := true
## Move each piece's origin to its own center (children are offset to compensate).
@export var recenter_pieces := true
@export_range(0.0, 0.1, 0.001, "suffix:m") var seam_overlap := 0.005
## Extra distance past the saw before the board may turn, in meters (covers the saw's own size).
@export var turn_clearance := 10
## board path -> [negative_half path, positive_half path] in the next stage.
## All paths are relative to this Path3D node, so use get_node(path) to get the board.





@export var split_map: Dictionary = {}
## Same data as split_map, but with the boards themselves:
## board -> Array[StaticBody3D] (two boards if it was split, one if it went unsplit).
## Built when the node is ready, and kept up to date by generate_splits().

@onready var split_map_nodes: Dictionary = _resolve_split_map()
func _resolve_split_map() -> Dictionary:
	var result := {}
	for key: NodePath in split_map:
		var board := get_node_or_null(key) as StaticBody3D
		if board == null:
			continue
		var paths: Array = split_map[key]
		var targets: Array[StaticBody3D] = []
		for p: NodePath in paths:
			var target := get_node_or_null(p) as StaticBody3D
			if target != null:
				targets.append(target)
		if targets.size() == paths.size():  # skip entries with missing boards
			result[board] = targets
	return result

func generate_splits() -> void:
	if source_body == null or output_root == null:
		push_warning("BodySplitPath: assign source_body and output_root first.")
		return

	var reference := _read_boxes(source_body)
	if reference.is_empty():
		push_warning("BodySplitPath: source_body has no BoxShape3D / BoxMesh children.")
		return

	for n in source_body.find_children("*", "CollisionShape3D", true, false):
		if not reference.has(source_body.get_path_to(n)):
			push_warning("BodySplitPath: '%s' is not a BoxShape3D (or has no shape) and will NOT be split." % n.name)
	for n in source_body.find_children("*", "CollisionPolygon3D", true, false):
		push_warning("BodySplitPath: CollisionPolygon3D '%s' can't be split by this tool." % n.name)

	# Compute every stage as data first, in the source body's local space.
	var stages: Array = []  # stages[s] = Array[Dictionary] of pieces after cut s+1
	var stage_lineages: Array = []  # stage_lineages[s][i] = lineage string of stages[s][i]
	var links: Array[Dictionary] = []  # links[s]: parent index in stage s -> [neg, pos] indices in stage s+1
	var current: Array[Dictionary] = [reference]
	var current_lineages: Array[String] = [""]
	for cut in cuts:
		if cut == null:
			continue
		var next_pieces: Array[Dictionary] = []
		var next_lineages: Array[String] = []
		var stage_links := {}
		var any_split := false
		for p in current.size():
			var piece := current[p]
			var bounds := _union(piece)
			var lo := bounds.position[cut.axis]
			var hi := bounds.end[cut.axis]
			var negative := {}
			var positive := {}
			if cut.offset > lo + EPS and cut.offset < hi - EPS:
				negative = _clip(piece, cut.axis, cut.offset, false)
				positive = _clip(piece, cut.axis, cut.offset, true)
			if negative.is_empty() or positive.is_empty():
				# Unsplit: carried over unchanged, linked to its copy in the next stage.
				stage_links[p] = [next_pieces.size()]
				next_pieces.append(piece)
				next_lineages.append(current_lineages[p])
				continue
			any_split = true
			stage_links[p] = [next_pieces.size(), next_pieces.size() + 1]
			next_pieces.append(negative)
			next_lineages.append(current_lineages[p] + "A")
			next_pieces.append(positive)
			next_lineages.append(current_lineages[p] + "B")
		if not any_split:
			push_warning("BodySplitPath: cut at %s misses every piece; skipped." % cut.offset)
			continue
		current = next_pieces
		current_lineages = next_lineages
		stages.append(current)
		stage_lineages.append(current_lineages)
		links.append(stage_links)

	if stages.is_empty():
		push_warning("BodySplitPath: no valid cuts, nothing generated.")
		return

	_clear_generated()

	var built := {}  # stage number -> Array of bodies, in piece order
	var first_stage := 0 if generate_all_stages else stages.size() - 1
	for s in range(first_stage, stages.size()):
		var stage_pieces: Array = stages[s]
		var bodies: Array = []
		for i in stage_pieces.size():
					bodies.append(_build_body(s + 1, stage_lineages[s][i], stage_pieces[i], reference))
		built[s + 1] = bodies

	# Match each board to what it became in the next stage: two boards if it was split,
	# one if it went unsplit. Stage 0 is the source body itself. Stored as paths so the
	# map survives saving.
	for s in links.size():
		var parent_list: Array = [source_body] if s == 0 else built.get(s, [])
		var child_list: Array = built.get(s + 1, [])
		for p: int in links[s]:
			if p >= parent_list.size():
				continue
			var indices: Array = links[s][p]
			var targets: Array = []
			for idx: int in indices:
				if idx < child_list.size():
					targets.append(get_path_to(child_list[idx]))
			if targets.size() == indices.size():
				split_map[get_path_to(parent_list[p])] = targets

# --- Public helpers for the simulation to call later --------------------------

## stage < 0 returns every generated piece. Stage numbers start at 1 (after the first cut).
func get_pieces(stage: int = -1) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if stage == 0: return [source_body]
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


func _build_body(stage: int, lineage: String, piece: Dictionary, reference: Dictionary) -> StaticBody3D:
	var body := source_body.duplicate() as StaticBody3D

	body.name = "%s_s%02d_%s" % [source_body.name, stage, lineage]
	body.set_meta(META_KEY, true)
	body.set_meta(STAGE_KEY, stage)
	body.add_to_group(BOARD_GROUP, true)

	var center := _union(piece).get_center() if recenter_pieces else Vector3.ZERO

	for path: NodePath in reference.keys():
		var child := body.get_node(path)
		if not piece.has(path):
			# This box lies entirely on the other side of a cut.
			_detach(child)
			continue

		var box: AABB = piece[path]
		if child is CollisionShape3D:
			box = _expand_cut_faces(box, reference[path], seam_overlap)
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
			mesh.material = source_mesh.material
			child.mesh = mesh

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

func _detach(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()

## Grows a clipped box outward on the faces created by cuts (not the board's original
## outer faces), so neighboring pieces overlap by `amount`.
func _expand_cut_faces(box: AABB, original: AABB, amount: float) -> AABB:
	var pos := box.position
	var size := box.size
	for a in 3:
		if box.position[a] > original.position[a] + EPS:  # min face was created by a cut
			pos[a] -= amount
			size[a] += amount
		if box.end[a] < original.end[a] - EPS:  # max face was created by a cut
			size[a] += amount
	return AABB(pos, size)

func _set_body_enabled(body: StaticBody3D, enabled: bool) -> void:
	body.visible = enabled

	body.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
	for shape_node in body.find_children("*", "CollisionShape3D", true, false):
		shape_node.set_deferred("disabled", not enabled)


func _clear_generated() -> void:
	split_map.clear()
	for c in output_root.get_children():
		if c.has_meta(META_KEY):
			output_root.remove_child(c)
			c.queue_free()

func create_split_markers() -> void:
	if source_body == null or markers == null:
		push_warning("BodySplitPath: assign source_body and markers first.")
		return

	var valid_cuts: Array[SplitCut] = []
	for cut in cuts:
		if cut != null:
			valid_cuts.append(cut)
	if valid_cuts.is_empty():
		push_warning("BodySplitPath: no cuts to build a curve from.")
		return

	var boxes := _read_boxes(source_body)
	if boxes.is_empty():
		push_warning("BodySplitPath: source_body has no BoxShape3D / BoxMesh children.")
		return
	var bounds := _union(boxes)
	var board_size := bounds.size
	var board_center := bounds.get_center()
	# Farthest the board reaches from its origin in the XZ plane: the radius it sweeps when turning.
	var turn_radius := Vector2(
		maxf(absf(bounds.position.x), absf(bounds.end.x)),
		maxf(absf(bounds.position.z), absf(bounds.end.z))
	).length()

	# Start from a copy of pre_curve (falls back to a single point at the origin).
	var new_curve: Curve3D = (pre_curve.duplicate() as Curve3D) if pre_curve != null else Curve3D.new()
	if new_curve.point_count == 0:
		new_curve.add_point(Vector3.ZERO)

	# One point per cut, reached by moving along +X (Y/Z cuts) or +Z (X cuts).
	var pos := new_curve.get_point_position(new_curve.point_count - 1)
	var cut_point_indices: Array[int] = []  # curve index of each cut's point
	const base_point_spacing = 500
	for i in valid_cuts.size():
		var travel_axis := _travel_axis(valid_cuts[i])
		var direction := Vector3.ZERO
		direction[travel_axis] = 1.0
		pos += direction * (base_point_spacing + board_size[travel_axis] * randf_range(1.25, 1.5))
		new_curve.add_point(pos)
		cut_point_indices.append(new_curve.point_count - 1)

		# The next cut needs a different direction: keep going straight until the board
		# has fully cleared this saw, so the turn happens after the cut, not during it.
		if i + 1 < valid_cuts.size() and _travel_axis(valid_cuts[i + 1]) != travel_axis:
			# Where the saw sits along the board's forward (+X) axis when the cut happens.
			var saw_x := valid_cuts[i].offset if valid_cuts[i].axis == SplitCut.Axis.X else board_center.x
			pos += direction * (maxf(0.0, saw_x + turn_radius) + turn_clearance)
			new_curve.add_point(pos)
	curve = new_curve

	# Markers and saws: one per cut, at that cut's point (the run-out points get none).
	_clear_markers()

	var local_offset := _split_center_offset()
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else null

	for k in valid_cuts.size():
		var cut := valid_cuts[k]
		var i := cut_point_indices[k]
		var point_global := to_global(curve.get_point_position(i))
		# Orientation of the board as it arrives at this point: its +X faces the travel direction.
		var board_basis := _board_basis_at(i)

		var marker := Node3D.new()
		marker.name = "SplitCenter_%02d" % (k + 1)
		marker.set_meta(MARKER_META, true)
		markers.add_child(marker)
		marker.global_position = point_global + board_basis * local_offset
		if scene_root:
			marker.owner = scene_root

		if saw_scene != null:
			# Point on this cut's plane: the board's center, with the cut's axis set to the offset.
			var plane_point := board_center
			plane_point[cut.axis] = cut.offset

			var saw := saw_scene.instantiate() as Node3D
			if saw == null:
				push_warning("BodySplitPath: saw_scene's root isn't a Node3D.")
				continue
			saw.name = "Saw"
			saw.add_to_group("saws", true)
			marker.add_child(saw)
			saw.global_transform = Transform3D(
				board_basis * _saw_alignment(cut.axis),
				point_global + board_basis * plane_point
			)
			if scene_root:
				saw.owner = scene_root

## Curve-space axis the board moves along to reach a cut: +X for Y/Z cuts, +Z for X cuts.
func _travel_axis(cut: SplitCut) -> int:
	return 2 if cut.axis == SplitCut.Axis.X else 0
## Board orientation at curve point i: local +X along the segment arriving at the point,
## with the path's own up direction kept as the board's up.
func _board_basis_at(i: int) -> Basis:
	var forward := (global_transform.basis * (curve.get_point_position(i) - curve.get_point_position(i - 1))).normalized()
	var up := global_transform.basis.y.normalized()
	var z_axis := forward.cross(up).normalized()
	var y_axis := z_axis.cross(forward)
	return Basis(forward, y_axis, z_axis)

## Rotation that takes the saw's default blade plane (perpendicular to Y) onto a cut's plane.
func _saw_alignment(axis: int) -> Basis:
	match axis:
		SplitCut.Axis.X:
			return Basis(Vector3.BACK, -PI / 2.0)  # Y -> X
		SplitCut.Axis.Y:
			return Basis(Vector3.RIGHT, PI / 2.0)  # Y -> Z
	return Basis.IDENTITY  # Y cuts need no rotation

## Center of the cuts in the source body's local space, ignoring X cuts.
func _split_center_offset() -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for cut in cuts:
		if cut == null or cut.axis == SplitCut.Axis.X:
			continue
		lo[cut.axis] = minf(lo[cut.axis], cut.offset)
		hi[cut.axis] = maxf(hi[cut.axis], cut.offset)

	var center := Vector3.ZERO
	for axis:int in [1, 2]:  # Y and Z only
		if lo[axis] <= hi[axis]:  # at least one cut on this axis
			center[axis] = (lo[axis] + hi[axis]) * 0.5
	return center


func _clear_markers() -> void:
	for c in markers.get_children():
		if c.has_meta(MARKER_META):
			markers.remove_child(c)
			c.queue_free()
