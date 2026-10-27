@tool
class_name BodySplitPath
extends Path3D

const BOARD_GROUP := &"boards"
const META_KEY := &"generated_split"
const STAGE_KEY := &"split_stage"
const FALLS_KEY := &"falls_off"
const EPS := 0.0001

const MARKER_META := &"split_center_marker"

@export var circular_saw_scene: PackedScene  # Y and Z cuts
@export var band_saw_scene: PackedScene  # X cuts

@export var pre_curve:Curve3D;
@export_tool_button("Generate Splits") var generate_action := generate_splits
@export_tool_button("Create Split Markers") var markers_action := create_split_markers


const TURN_AREA_SIZE := 50.0

@export var floor_plane: MeshInstance3D
@export var ceiling: MeshInstance3D
@export var wall_front: MeshInstance3D
@export var wall_back: MeshInstance3D
@export var wall_left: MeshInstance3D
@export var wall_right: MeshInstance3D

@export var floor_ceiling_texture_scale := 2.0
## Extra space between the system and each wall, in meters.
const room_margin := 500


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
## Extra run-out past the saw before turning off a leg that travels along X (Y/Z cuts), in meters.
@export var turn_clearance_x := 0.25
## Extra run-out past the saw before turning off a leg that travels along Z (X cuts), in meters.
@export var turn_clearance_z := 0.25
## board path -> [negative_half path, positive_half path] in the next stage.
## All paths are relative to this Path3D node, so use get_node(path) to get the board.


## Added to the seed behind the spacing between path points. Same cuts + same value = same layout.
@export var positioning_seed := 0

## Longest a visual mesh segment may be along X, in meters. Longer boxes are cut into equal
## segments no longer than this. 0 disables splitting. Collision shapes are not affected.
@export_range(0.0, 1000.0, 0.01, "or_greater", "suffix:m") var max_mesh_x := 100.0

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
		if not reference.has(source_body.get_path_to(n)) and not _is_in_area(n, source_body):
			push_warning("BodySplitPath: '%s' is not a BoxShape3D (or has no shape) and will NOT be split." % n.name)
	for n in source_body.find_children("*", "CollisionPolygon3D", true, false):
		push_warning("BodySplitPath: CollisionPolygon3D '%s' can't be split by this tool." % n.name)

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
			var bounds := _union(piece)
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
			push_warning("BodySplitPath: cut at %s misses every remaining piece; skipped." % cut.offset)
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
		push_warning("BodySplitPath: no valid cuts, nothing generated.")
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

# --- Public helpers for the simulation to call later --------------------------
## True if the node sits anywhere under an Area3D between it and the root.
func _is_in_area(node: Node, root: Node) -> bool:
	var p := node.get_parent()
	while p != null and p != root:
		if p is Area3D:
			return true
		p = p.get_parent()
	return false

## A seed derived from the cut data itself, so identical cuts always get identical positioning.
func _cuts_seed(cut_list: Array[SplitCut]) -> int:
	var h := 1469598103934665603
	for cut in cut_list:
		for v:int in [cut.axis, roundi(cut.offset * 10000.0), cut.drop_side]:
			h = (h ^ v) * 1099511628211
	return h

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
		push_warning("BodySplitPath: material '%s' is not a StandardMaterial3D; it was left unshifted." % mat.resource_name)
		return mat.duplicate() as Material

	var copy := std.duplicate() as StandardMaterial3D
	if not copy.uv1_triplanar:
		push_warning("BodySplitPath: '%s' isn't triplanar, so its texture will stretch on resized pieces. Enable uv1_triplanar." % mat.resource_name)
		return copy
	if copy.uv1_world_triplanar:
		return copy  # world-space mapping never changes when a piece moves or resizes

	# Triplanar samples at (local_position * uv1_scale + uv1_offset). The piece's local origin
	# moved by `delta`, so add it back to land on the same texel as the original.
	copy.uv1_offset += delta * copy.uv1_scale
	copy.texture_repeat = true
	return copy

func _detach(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
	node.queue_free()

## The board still attached when each cut's saw is reached, as bounds in the source body's local
## space. A cut's dropped side stops counting for every cut after it.
func _remaining_bounds_per_cut(valid_cuts: Array[SplitCut], start: AABB) -> Array[AABB]:
	var result: Array[AABB] = []
	var remaining := start
	for cut in valid_cuts:
		result.append(remaining)
		var lo := remaining.position[cut.axis]
		var hi := remaining.end[cut.axis]
		if cut.offset <= lo + EPS or cut.offset >= hi - EPS:
			continue  # misses what's left: nothing is split or dropped
		var negative_falls := cut.drops(true)   # same call generate_splits() uses
		var positive_falls := cut.drops(false)
		var pos := remaining.position
		var size := remaining.size
		if negative_falls and not positive_falls:
			pos[cut.axis] = cut.offset
			size[cut.axis] = hi - cut.offset
		elif positive_falls and not negative_falls:
			size[cut.axis] = cut.offset - lo
		remaining = AABB(pos, size)
	return result

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
	body.rotation_degrees.y = 90
	body.set_process_mode.bind(Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED).call_deferred()
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
	
	var saws: Array[Node3D] = []
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
	var remaining_before := _remaining_bounds_per_cut(valid_cuts, bounds)
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
	var turn_point_indices: Array[int] = []  # curve index of each point where the board turns

	var rng := RandomNumberGenerator.new()
	rng.seed = _cuts_seed(valid_cuts) + positioning_seed
	
	const base_point_spacing = 500
	for i in valid_cuts.size():
		var travel_axis := _travel_axis(valid_cuts[i])
		var direction := Vector3.ZERO
		direction[travel_axis] = 1.0
		# The board arriving at this cut may be shorter along its travel axis than the original,
		# because earlier cuts dropped part of it. The spacing shrinks by exactly that much.
		var shortened := board_size[travel_axis] - remaining_before[i].size[travel_axis]
		var spacing := base_point_spacing + board_size[travel_axis] * rng.randf_range(1.25, 1.5) - shortened
		pos += direction * maxf(spacing, 0.001)
		new_curve.add_point(pos)
		cut_point_indices.append(new_curve.point_count - 1)

		# The next cut needs a different direction: keep going straight until the board
		# has fully cleared this saw, so the turn happens after the cut, not during it.
		if i + 1 < valid_cuts.size() and _travel_axis(valid_cuts[i + 1]) != travel_axis:
			# Where the saw sits along the board's forward (+X) axis when the cut happens.
			var saw_x := valid_cuts[i].offset if valid_cuts[i].axis == SplitCut.Axis.X else remaining_before[i].get_center().x
			var clearance := turn_clearance_z if travel_axis == 2 else turn_clearance_x
			pos += direction * (maxf(0.0, saw_x + turn_radius) + clearance)
			new_curve.add_point(pos)
			turn_point_indices.append(new_curve.point_count - 1)
	
	# One extra, empty point past the last saw: the board keeps going the same distance a
	# further cut on that axis would have taken. No marker, saw, or turn area is made for it.
	var last_axis := _travel_axis(valid_cuts[valid_cuts.size() - 1])
	var last_direction := Vector3.ZERO
	last_direction[last_axis] = 1.0
	pos += last_direction * (base_point_spacing + board_size[last_axis] * rng.randf_range(1.25, 1.5))
	new_curve.add_point(pos)
	var final_point_index := new_curve.point_count - 1
	curve = new_curve


	curve = new_curve
	
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
		var circular := cut.axis != SplitCut.Axis.X

		# X-cut markers get an extra -90° turn about their own Y axis on top of the board's
		# orientation; the band saw's offset runs along the resulting local X.
		var marker_basis := board_basis if circular else board_basis * Basis(Vector3.UP, -PI / 2.0)

		var marker := Node3D.new()
		marker.name = "SplitCenter_%02d" % (k + 1)
		marker.set_meta(MARKER_META, true)
		markers.add_child(marker)
		marker.global_transform = Transform3D(marker_basis, point_global + board_basis * local_offset)
		if scene_root:
			marker.owner = scene_root

		var saw_scene: PackedScene = circular_saw_scene if circular else band_saw_scene
		if saw_scene == null:
			push_warning("BodySplitPath: assign %s to create the saw for cut %d." % [
				"circular_saw_scene" if circular else "band_saw_scene", k + 1])
			continue

		# Where the saw sits: on the cut plane, at the center of the board that is still attached.
		var remaining_center := remaining_before[k].get_center()
		var plane_point: Vector3
		if circular:
			plane_point = remaining_center
			plane_point[cut.axis] = cut.offset
		else:
			plane_point = Vector3(cut.offset, remaining_center.y, remaining_center.z)

		var saw := saw_scene.instantiate() as Node3D
		if saw == null:
			push_warning("BodySplitPath: the saw scene's root isn't a Node3D.")
			continue

		
		var native_basis := saw.basis  # the rotation the scene was authored with
		saw.add_to_group("saws", true)
		saw.add_to_group("circular_saws" if circular else "band_saws", true)
		saw.set_meta(&"cut_number", k + 1)
		marker.add_child(saw)
		saws.append(saw)

		# Rotation (in the world): circular saws line up with their cut plane,
		# band saws keep their scene's own rotation.
		var saw_basis := (board_basis * _saw_alignment(cut.axis)) if circular else native_basis
		saw.global_transform = Transform3D(saw_basis, marker.global_position)
		# Position: local to the marker, as the offset from the split center in board axes.
		saw.position = plane_point - local_offset
		saw.name = "Saw"
		if scene_root:
			saw.owner = scene_root
				
	# One trigger area at each point where the board turns.
	for t in turn_point_indices.size():
		var area := Area3D.new()
		area.name = "TurnArea_%02d" % (t + 1)
		area.set_meta(MARKER_META, true)
		area.monitoring = false
		area.monitorable = true
		area.collision_layer = 0
		area.set_collision_layer_value(4, true)

		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * TURN_AREA_SIZE
		shape_node.shape = box
		area.add_child(shape_node)

		markers.add_child(area)
		area.global_position = to_global(curve.get_point_position(turn_point_indices[t]))
		if scene_root:
			area.owner = scene_root
			shape_node.owner = scene_root
	# Trigger area at the final, empty point of the path.
	var final_area := Area3D.new()
	final_area.name = "final_point"
	final_area.set_meta(MARKER_META, true)
	final_area.monitoring = false
	final_area.monitorable = true
	final_area.collision_layer = 0
	final_area.set_collision_layer_value(4, true)

	var final_shape_node := CollisionShape3D.new()
	var final_box := BoxShape3D.new()
	final_box.size = Vector3.ONE * TURN_AREA_SIZE
	final_shape_node.shape = final_box
	final_area.add_child(final_shape_node)

	markers.add_child(final_area)
	final_area.global_position = to_global(curve.get_point_position(final_point_index))
	if scene_root:
		final_area.owner = scene_root
		final_shape_node.owner = scene_root
	
	_fit_room(bounds, turn_radius, turn_point_indices, saws)
## Sizes and places the room planes around everything in the system.
func _fit_room(bounds: AABB, turn_radius: float, turn_point_indices: Array[int], saws: Array[Node3D]) -> void:
	var to_local_xform := global_transform.affine_inverse()
	var fit: Array[AABB] = []  # everything the room must contain, in this node's local space

	# The board along the whole path. It turns about its origin, so use its full turning
	# radius in the XZ plane and its real height range.
	for p in curve.get_baked_points():
		fit.append(AABB(
			p + Vector3(-turn_radius, bounds.position.y, -turn_radius),
			Vector3(2.0 * turn_radius, bounds.size.y, 2.0 * turn_radius)
		))

	# The saws, including all of their visible geometry.
	for saw in saws:
		fit.append(AABB(to_local_xform * saw.global_position, Vector3.ZERO))
		var visuals: Array = saw.find_children("*", "VisualInstance3D", true, false)
		if saw is VisualInstance3D:
			visuals.append(saw)
		for vi:Node in visuals:
			var global_box: AABB = vi.global_transform * vi.get_aabb()
			fit.append(to_local_xform * global_box)

	# The turn areas.
	for idx in turn_point_indices:
		var center := to_global(curve.get_point_position(idx))
		var half := Vector3.ONE * TURN_AREA_SIZE * 0.5
		fit.append(to_local_xform * AABB(center - half, Vector3.ONE * TURN_AREA_SIZE))

	if fit.is_empty():
		return
	var room := fit[0]
	for k in range(1, fit.size()):
		room = room.merge(fit[k])
	room = room.grow(room_margin)

	var lo := room.position
	var hi := room.end
	var c := room.get_center()
	var s := room.size

		# Walls: sizes are (width, height). The extra `true` makes the texture fit the wall.
	_place_plane(wall_front, Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN),
			Vector3(hi.x, c.y, c.z), Vector2(s.z, s.y), true)
	_place_plane(wall_back, Basis(Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN),
			Vector3(lo.x, c.y, c.z), Vector2(s.z, s.y), true)
	_place_plane(wall_right, Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN),
			Vector3(c.x, c.y, hi.z), Vector2(s.x, s.y), true)
	_place_plane(wall_left, Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
			Vector3(c.x, c.y, lo.z), Vector2(s.x, s.y), true)
	
	_place_plane(floor_plane, Basis.IDENTITY, Vector3(c.x, lo.y, c.z), Vector2(s.x, s.z))
	_place_plane(ceiling, Basis(Vector3.RIGHT, PI), Vector3(c.x, hi.y, c.z), Vector2(s.x, s.z))
	_tile_texture(floor_plane, Vector2(s.x, s.z), floor_ceiling_texture_scale)
	_tile_texture(ceiling, Vector2(s.x, s.z), floor_ceiling_texture_scale)

## Repeats the node's texture across a plane of the given size (x, z), drawing each tile
## texture_size * texel_scale world units across.
func _tile_texture(node: MeshInstance3D, size: Vector2, texel_scale: float) -> void:
	if node == null:
		return
	var mesh := node.mesh as PlaneMesh

	# Find the StandardMaterial3D the node actually renders with.
	var source: StandardMaterial3D = null
	var slot := 0  # 1 = material_override, 2 = surface override, 3 = the mesh's own material
	if node.material_override is StandardMaterial3D:
		source = node.material_override
		slot = 1
	elif node.get_surface_override_material(0) is StandardMaterial3D:
		source = node.get_surface_override_material(0) as StandardMaterial3D
		slot = 2
	elif mesh != null and mesh.material is StandardMaterial3D:
		source = mesh.material as StandardMaterial3D
		slot = 3
	if source == null or source.albedo_texture == null:
		push_warning("BodySplitPath: '%s' has no StandardMaterial3D with an albedo texture to tile." % node.name)
		return

	var tile := source.albedo_texture.get_size() * texel_scale  # one tile, in world units
	if tile.x <= 0.0 or tile.y <= 0.0:
		return

	# A per-plane copy, because the floor and ceiling each need their own scale.
	var material := source.duplicate() as StandardMaterial3D
	material.uv1_triplanar = false  # triplanar mapping would ignore the UV scale
	material.texture_repeat = true
	material.uv1_offset = Vector3.ZERO
	material.uv1_scale = Vector3(size.x / tile.x, size.y / tile.y, 1.0)

	match slot:
		1: node.material_override = material
		2: node.set_surface_override_material(0, material)
		3: mesh.material = material

## Gives the node its own PlaneMesh of the right size and puts it at local_pos (in this
## node's space), rotated so the plane's visible side faces into the room.
func _place_plane(node: MeshInstance3D, rotation: Basis, local_pos: Vector3, size: Vector2, fit_texture := false) -> void:
	if node == null:
		return
	var mesh := (node.mesh.duplicate() as PlaneMesh) if node.mesh is PlaneMesh else PlaneMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Y  # the rotations assume the plane faces +Y
	mesh.flip_faces = false
	mesh.center_offset = Vector3.ZERO
	node.mesh = mesh
	node.global_transform = global_transform * Transform3D(rotation, local_pos)
	if fit_texture:
		_fit_wall_texture(node, mesh, size)


## Makes the wall's texture span its full height once and repeat across its width,
## keeping the texture's aspect ratio. size = (width, height).
func _fit_wall_texture(node: MeshInstance3D, mesh: PlaneMesh, size: Vector2) -> void:
	# Find the StandardMaterial3D the node actually renders with.
	var source: StandardMaterial3D = null
	var slot := 0  # 1 = material_override, 2 = surface override, 3 = the mesh's own material
	if node.material_override is StandardMaterial3D:
		source = node.material_override
		slot = 1
	elif node.get_surface_override_material(0) is StandardMaterial3D:
		source = node.get_surface_override_material(0) as StandardMaterial3D
		slot = 2
	elif mesh.material is StandardMaterial3D:
		source = mesh.material as StandardMaterial3D
		slot = 3
	if source == null or source.albedo_texture == null or size.y <= 0.0:
		push_warning("BodySplitPath: '%s' has no StandardMaterial3D with an albedo texture to fit." % node.name)
		return

	var tex_size := source.albedo_texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return

	# One tile is as tall as the wall and (height * texture aspect) wide.
	var tile_width := size.y * tex_size.x / tex_size.y
	var repeats := size.x / tile_width

	# A per-wall copy, because the walls usually share one material but each needs its own scale.
	var material := source.duplicate() as StandardMaterial3D
	material.uv1_triplanar = false  # triplanar mapping would ignore the UV scale
	material.texture_repeat = true
	material.uv1_offset = Vector3.ZERO
	material.uv1_scale = Vector3(repeats, 1.0, 1.0)

	match slot:
		1: node.material_override = material
		2: node.set_surface_override_material(0, material)
		3: mesh.material = material

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
			return Basis(Vector3.UP, PI)  # Y -> X
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

func _clear_markers() -> void:
	for c in markers.get_children():
		if c.has_meta(MARKER_META):
			markers.remove_child(c)
			c.queue_free()

## Bounds of the source board in the source body's local space (the space cut offsets use).
func get_board_bounds() -> AABB:
	if source_body == null:
		return AABB()
	var boxes := _read_boxes(source_body)
	return _union(boxes) if not boxes.is_empty() else AABB()

## The boards of a stage that stay attached, meaning they don't fall off at that stage's cut.
## Stage 0 is the source body itself; stages 1 and up are the generated ones.
func get_remaining_boards(stage: int) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if stage <= 0:
		if source_body != null:
			result.append(source_body)
		return result
	for body in get_pieces(stage):
		if not body.get_meta(FALLS_KEY, false):
			result.append(body)
	return result


## The board of a stage that won't be removed, or null if there isn't one.
func get_remaining_board(stage: int) -> StaticBody3D:
	var boards := get_remaining_boards(stage)
	return boards[0] if not boards.is_empty() else null

func get_split_count()->int:
	return len(split_map)
