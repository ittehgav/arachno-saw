@tool
class_name BodySplitPath
extends Path3D

const BOARD_GROUP := &"boards"
const META_KEY := &"generated_split"
const STAGE_KEY := &"split_stage"
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

			var mesh := _make_piece_mesh(source_mesh, reference[path], box)
			mesh.surface_set_material(0, source_mesh.material)  # the BoxMesh's own material
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

const UV_EPS := 0.00001
const FACE_DIRS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]


func _axis_of(dir: Vector3) -> int:
	if absf(dir.x) > 0.5:
		return 0
	return 1 if absf(dir.y) > 0.5 else 2


## For one face of a box mesh: how its UVs change with position across that face.
## Works for any UV layout or orientation, because it reads the mapping from the mesh itself.
func _face_uv_map(arrays: Array, dir: Vector3) -> Dictionary:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var a := (_axis_of(dir) + 1) % 3
	var b := (_axis_of(dir) + 2) % 3

	var first := -1
	for i in verts.size():
		if normals[i].dot(dir) > 0.99:
			first = i
			break
	if first < 0:
		return {}

	var p0 := verts[first]
	var uv0 := uvs[first]
	var grad_a := Vector2.ZERO
	var grad_b := Vector2.ZERO
	var found_a := false
	var found_b := false
	for i in verts.size():
		if normals[i].dot(dir) <= 0.99:
			continue
		var d := verts[i] - p0
		if not found_a and absf(d[a]) > UV_EPS and absf(d[b]) < UV_EPS:
			grad_a = (uvs[i] - uv0) / d[a]
			found_a = true
		elif not found_b and absf(d[b]) > UV_EPS and absf(d[a]) < UV_EPS:
			grad_b = (uvs[i] - uv0) / d[b]
			found_b = true
	if not (found_a and found_b):
		return {}
	return {"p0": p0, "uv0": uv0, "a": a, "b": b, "grad_a": grad_a, "grad_b": grad_b}


## Builds the piece's mesh: a regular box of the piece's size, except that faces lying on the
## full board's outside surface get the full board's UVs for that part of the face.
func _make_piece_mesh(source_mesh: BoxMesh, original_box: AABB, box: AABB) -> ArrayMesh:
	var full_arrays := source_mesh.get_mesh_arrays()  # the full board's UV mapping
	var regular := source_mesh.duplicate() as BoxMesh  # what the cut faces keep
	regular.size = box.size
	var arrays := regular.get_mesh_arrays()

	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	# Piece-mesh space -> full-board-mesh space (each mesh is centered on its own box).
	var delta := box.get_center() - original_box.get_center()

	for dir: Vector3 in FACE_DIRS:
		var n := _axis_of(dir)
		var outside: bool
		if dir[n] > 0.0:
			outside = absf(box.end[n] - original_box.end[n]) < EPS
		else:
			outside = absf(box.position[n] - original_box.position[n]) < EPS
		var map := _face_uv_map(full_arrays, dir) if outside else {}
		if map.is_empty():
			continue  # a face created by a cut, or a map that couldn't be read
		for i in verts.size():
			if normals[i].dot(dir) > 0.99:
				var p := verts[i] + delta
				uvs[i] = map.uv0 \
						+ map.grad_a * (p[map.a] - map.p0[map.a]) \
						+ map.grad_b * (p[map.b] - map.p0[map.b])

	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	var turn_point_indices: Array[int] = []  # curve index of each point where the board turns


	
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
			var clearance := turn_clearance_z if travel_axis == 2 else turn_clearance_x
			pos += direction * (maxf(0.0, saw_x + turn_radius) + clearance)
			new_curve.add_point(pos)
			turn_point_indices.append(new_curve.point_count - 1)
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

		# Where the saw sits, in board space (relative to the board's origin on the path point).
		var plane_point: Vector3
		if circular:
			# Y/Z cuts: the board's center, with the cut's axis set to the offset.
			plane_point = board_center
			plane_point[cut.axis] = cut.offset
		else:
			# X cuts: along the board's length by the cut's offset, at the same height and depth
			# where the Y/Z cuts are made (the marker's split center).
			plane_point = Vector3(cut.offset, local_offset.y, local_offset.z)

		var saw := saw_scene.instantiate() as Node3D
		if saw == null:
			push_warning("BodySplitPath: the saw scene's root isn't a Node3D.")
			continue

		saw.name = "Saw"
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


func _clear_markers() -> void:
	for c in markers.get_children():
		if c.has_meta(MARKER_META):
			markers.remove_child(c)
			c.queue_free()
