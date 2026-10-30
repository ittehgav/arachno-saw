@tool
class_name BoardSplitter
extends Node
## Splits a box-shaped StaticBody3D into pieces along a list of cuts.
## BodySplitPath owns the cuts and the path; it calls generate_splits(cuts) on this node.

const BOARD_GROUP := &"boards"
const META_KEY := &"generated_split"
const STAGE_KEY := &"split_stage"
const FALLS_KEY := &"falls_off"
const EPS := 0.0001

@export var source_body: StaticBody3D
@export var output_root: Node3D
## true: generate the pieces after every cut (stages 1..N).
## false: only generate the pieces after the last cut.
@export var generate_all_stages := true
## Move each piece's origin to its own center (children are offset to compensate).
@export var recenter_pieces := true
@export_range(0.0, 0.1, 0.001, "suffix:m") var seam_overlap := 0.005
## Longest a visual mesh segment may be along X, in meters. Longer boxes are cut into equal
## segments no longer than this. 0 disables splitting. Collision shapes are not affected.
@export_range(0.0, 1000.0, 0.01, "or_greater", "suffix:m") var max_mesh_x := 100.0

## board path -> [negative_half path, positive_half path] in the next stage.
## All paths are relative to THIS node, so use get_node(path) to get the board.
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


func generate_splits(cuts: Array[SplitCut]) -> void:
	if source_body == null or output_root == null:
		push_warning("BoardSplitter: assign source_body and output_root first.")
		return

	var reference := read_boxes(source_body)
	if reference.is_empty():
		push_warning("BoardSplitter: source_body has no BoxShape3D / BoxMesh children.")
		return

	for n in source_body.find_children("*", "CollisionShape3D", true, false):
		if not reference.has(source_body.get_path_to(n)) and not _is_in_area(n, source_body):
			push_warning("BoardSplitter: '%s' is not a BoxShape3D (or has no shape) and will NOT be split." % n.name)
	for n in source_body.find_children("*", "CollisionPolygon3D", true, false):
		push_warning("BoardSplitter: CollisionPolygon3D '%s' can't be split by this tool." % n.name)

	# Compute every stage as data first, in the source body's local space.
	# A stage holds what exists right after a cut: the boards still attached, plus the boards that
	# fall off at that cut. Boards that fell off earlier are not carried into later stages.
	var stages: Array = []  # stages[s] = Array[Dictionary] of pieces after cut s+1
	var stage_lineages: Array = []
	var stage_falls: Array = []  # stage_falls[s][i] = true if piece i falls off at that cut
	var stage_remaining: Array = []  # stage_remaining[s] = indices of the pieces that stay attached
	var links: Array[Dictionary] = []  # links[s]: attached piece before the cut -> child indices in stage s
	var current: Array[Dictionary] = [reference]
	var current_lineages: Array[String] = [""]
	for cut in cuts:
		if cut == null:
			continue
		var next_pieces: Array[Dictionary] = []
		var next_lineages: Array[String] = []
		var next_falls: Array[bool] = []
		var stage_links := {}
		var any_split := false
		for p in current.size():
			var piece := current[p]
			var bounds := union_of(piece)
			var lo := bounds.position[cut.axis]
			var hi := bounds.end[cut.axis]
			var negative := {}
			var positive := {}
			if cut.offset > lo + EPS and cut.offset < hi - EPS:
				negative = _clip(piece, cut.axis, cut.offset, false)
				positive = _clip(piece, cut.axis, cut.offset, true)
			if negative.is_empty() or positive.is_empty():
				# The plane misses this piece. It isn't split, but it still falls if it lies
				# entirely on the side that drops.
				var on_negative_side := (lo + hi) * 0.5 < cut.offset
				stage_links[p] = [next_pieces.size()]
				next_pieces.append(piece)
				next_lineages.append(current_lineages[p])
				next_falls.append(cut.drops(on_negative_side))
				continue
			any_split = true
			stage_links[p] = [next_pieces.size(), next_pieces.size() + 1]
			next_pieces.append(negative)
			next_lineages.append(current_lineages[p] + "A")
			next_falls.append(cut.drops(true))
			next_pieces.append(positive)
			next_lineages.append(current_lineages[p] + "B")
			next_falls.append(cut.drops(false))
		if not any_split:
			push_warning("BoardSplitter: cut at %s misses every remaining piece; skipped." % cut.offset)
			continue

		# Only what stays attached is cut by the next cut.
		var remaining_indices: Array[int] = []
		var kept_pieces: Array[Dictionary] = []
		var kept_lineages: Array[String] = []
		for i in next_pieces.size():
			if not next_falls[i]:
				remaining_indices.append(i)
				kept_pieces.append(next_pieces[i])
				kept_lineages.append(next_lineages[i])
		stages.append(next_pieces)
		stage_lineages.append(next_lineages)
		stage_falls.append(next_falls)
		stage_remaining.append(remaining_indices)
		links.append(stage_links)
		current = kept_pieces
		current_lineages = kept_lineages

	if stages.is_empty():
		push_warning("BoardSplitter: no valid cuts, nothing generated.")
		return

	_clear_generated()

	var built := {}  # stage number -> Array of bodies, in piece order
	var first_stage := 0 if generate_all_stages else stages.size() - 1
	for s in range(first_stage, stages.size()):
		var stage_pieces: Array = stages[s]
		var bodies: Array = []
		for i in stage_pieces.size():
			var body := _build_body(s + 1, stage_lineages[s][i], stage_pieces[i], reference)
			body.set_meta(FALLS_KEY, stage_falls[s][i])
			bodies.append(body)
		built[s + 1] = bodies

	# Match each board that was still attached before a cut to what it became in the next stage:
	# two boards if it was split (one of them may be the part that falls), one if it wasn't.
	# Stage 0 is the source body itself. Stored as paths so the map survives saving.
	for s in links.size():
		var parent_list: Array = []
		if s == 0:
			parent_list.append(source_body)
		else:
			var previous_bodies: Array = built.get(s, [])
			for idx: int in stage_remaining[s - 1]:
				if idx < previous_bodies.size():
					parent_list.append(previous_bodies[idx])
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

	split_map_nodes = _resolve_split_map()


# --- Public helpers ------------------------------------------------------------

## stage < 0 returns every generated piece. Stage numbers start at 1 (after the first cut).
func get_pieces(stage: int = -1) -> Array[StaticBody3D]:
	if stage == 0:
		return [source_body]
	var result: Array[StaticBody3D] = []
	if output_root:
		for c in output_root.get_children():
			if c.has_meta(META_KEY) and (stage < 0 or c.get_meta(STAGE_KEY) == stage):
				result.append(c)
	return result


func set_stage_enabled(stage: int, enabled: bool) -> void:
	for body in get_pieces(stage):
		_set_body_enabled(body, enabled)


## Bounds of the source board in the source body's local space (the space cut offsets use).
func get_board_bounds() -> AABB:
	if source_body == null:
		return AABB()
	var boxes := read_boxes(source_body)
	return union_of(boxes) if not boxes.is_empty() else AABB()


## Reads every BoxShape3D / BoxMesh child as an AABB in the body's local space.
## Assumes those children have no rotation or scale.
func read_boxes(body: Node3D) -> Dictionary:
	var boxes := {}
	_collect_boxes(body, body, Vector3.ZERO, boxes)
	return boxes


func union_of(piece: Dictionary) -> AABB:
	var result := AABB()
	var first := true
	for box: AABB in piece.values():
		result = box if first else result.merge(box)
		first = false
	return result


# --- Internals -----------------------------------------------------------------

## True if the node sits anywhere under an Area3D between it and the root.
func _is_in_area(node: Node, root: Node) -> bool:
	var p := node.get_parent()
	while p != null and p != root:
		if p is Area3D:
			return true
		p = p.get_parent()
	return false


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


## Returns a new piece with every box clipped to one side of the plane.
## Boxes that end up with no thickness are dropped.
func _clip(piece: Dictionary, axis: int, offset: float, keep_positive: bool) -> Dictionary:
	var out := {}
	for path: NodePath in piece:
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

	var center := union_of(piece).get_center() if recenter_pieces else Vector3.ZERO

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

			var segments := _split_x(box, max_mesh_x)
			var base_offset := _offset_in_body(body, child)

			# The first segment reuses this node; every extra one is a copy of it.
			var nodes: Array[MeshInstance3D] = [child]
			for n in range(1, segments.size()):
				var extra := child.duplicate() as MeshInstance3D
				for g in extra.get_children():
					extra.remove_child(g)
					g.queue_free()
				extra.name = "%s_Part%02d" % [child.name, n + 1]
				child.get_parent().add_child(extra)
				nodes.append(extra)

			for h in segments.size():
				# Where this segment's center sits relative to the original mesh's center.
				# Shifting the triplanar offset by this makes the texture line up with the original.
				var delta: Vector3 = segments[h].get_center() - reference[path].get_center()

				var mesh := source_mesh.duplicate() as BoxMesh
				mesh.size = segments[h].size
				mesh.material = _shifted_material(source_mesh.material, delta)
				nodes[h].mesh = mesh
				nodes[h].position = segments[h].get_center() - center - base_offset

				nodes[h].material_override = _shifted_material(original.material_override, delta)
				for s in original.get_surface_override_material_count():
					nodes[h].set_surface_override_material(
							s, _shifted_material(original.get_surface_override_material(s), delta))

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


## Returns a unique StandardMaterial3D (null stays null). A piece centered `delta` away from
## the original mesh center gets its triplanar mapping shifted, so every face, including the
## ones exposed by earlier cuts, samples the texture exactly where the original board did.
func _shifted_material(mat: Material, delta: Vector3) -> Material:
	if mat == null:
		return null

	var std := mat as StandardMaterial3D
	if std == null:
		push_warning("BoardSplitter: material '%s' is not a StandardMaterial3D; it was left unshifted." % mat.resource_name)
		return mat.duplicate() as Material

	var copy := std.duplicate() as StandardMaterial3D
	if not copy.uv1_triplanar:
		push_warning("BoardSplitter: '%s' isn't triplanar, so its texture will stretch on resized pieces. Enable uv1_triplanar." % mat.resource_name)
		return copy
	if copy.uv1_world_triplanar:
		return copy  # world-space mapping never changes when a piece moves or resizes

	# Triplanar samples at (local_position * uv1_scale + uv1_offset). The piece's local origin
	# moved by `delta`, so add it back to land on the same texel as the original.
	copy.uv1_offset += delta * copy.uv1_scale
	copy.texture_repeat = true
	return copy


## Divides a box along X into equal segments, each at most max_x long.
## Returns the box unchanged if it already fits (or max_x <= 0).
func _split_x(box: AABB, max_x: float) -> Array[AABB]:
	var out: Array[AABB] = []
	if max_x <= 0.0 or box.size.x <= max_x + EPS:
		out.append(box)
		return out
	var count := ceili(box.size.x / max_x - EPS)
	var seg_size := box.size
	seg_size.x = box.size.x / count
	for i in count:
		var pos := box.position
		pos.x += seg_size.x * i
		out.append(AABB(pos, seg_size))
	return out


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

	body.set_process_mode.bind(Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED).call_deferred()
	for shape_node in body.find_children("*", "CollisionShape3D", true, false):
		shape_node.set_deferred("disabled", not enabled)


func _clear_generated() -> void:
	split_map.clear()
	for c in output_root.get_children():
		if c.has_meta(META_KEY):
			output_root.remove_child(c)
			c.queue_free()
