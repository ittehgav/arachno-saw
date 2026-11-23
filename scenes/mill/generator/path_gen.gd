@tool
class_name BodySplitPath
extends Path3D

## ONLY USED TO CLEAR INCONSITENCIES WITH _READY/OTHER 
## STARTUP RELATED STUFF ON DUPLICATES
signal stage_started;

func _ready()->void:
	if process_mode == PROCESS_MODE_INHERIT:
		GLB.current_path = self
		if not Engine.is_editor_hint():
			start_stage.call_deferred()  # deferred so the generator has connected by then


## Makes this the active path and tells the generator.
func start_stage() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	GLB.current_path = self
	stage_started.emit()

const EPS := 0.0001

const MARKER_META := &"split_center_marker"
const DIVIDER_GROUP := &"room_divider"
const DIVIDER_GAP := 0.5

const DIVIDER_META := &"divider_pair"


var _opening_width := 0.0
var _opening_height := 0.0
## pair number -> {"z", "x", "covered", "cover"} for every divider that exists.
## Pair p stands between path p - 1 and path p of the generator's `paths` list.
var _dividers := {}

@export var x_saw: PackedScene  # X cuts
@export var y_saw: PackedScene  # Y cuts
@export var z_saw: PackedScene  # Z cuts

## The board that stays attached after the last cut and never drops. It's the non-falling piece of the
## highest generated stage. Falls back to the source body if no splits have been generated yet.
var final_board: StaticBody3D:
	get:
		var best: StaticBody3D = null
		var best_stage := 0
		for body in get_pieces():
			if body.get_meta(BoardSplitter.FALLS_KEY, false):
				continue
			var stage: int = body.get_meta(BoardSplitter.STAGE_KEY, 0)
			if stage > best_stage:
				best_stage = stage
				best = body
		return best if best != null else source_body

## Mirrors saw positions across the point along the board's X and Z axes. Turn this on if the
## board faces the opposite way at each point.
@export var mirror_saws_xz := true


@export var pre_curve:Curve3D;
@export_tool_button("Generate Splits") var generate_action := generate_splits
@export_tool_button("Create Split Markers") var markers_action := create_split_markers

## Extra offset applied to every saw, in the board's own axes (X = travel direction, Y = up, Z = sideways).
@export var saw_offset := Vector3.ZERO

@export var board_splitter:BoardSplitter

const POINT_AREA_SIZE := 50.0



@export var line_start_height := 200.0


@export var cuts: Array[SplitCut] = []
@export var markers:Node3D;


## Added to the seed behind the spacing between path points. Same cuts + same value = same layout.
@export var positioning_seed := 0
## Extra distance, in meters, added between every pair of neighbouring path points, on top of the
## board-length based spacing. 0 = unchanged. The random spacing itself still follows the seed.
@export var extra_point_spacing := 0

## Node the roller line instances are added under. Falls back to `markers` if empty.
@export var roller_root: Node3D

## Scene placed on the extra point past the final point. Its origin sits on the point.
@export var chipper_scene: PackedScene
## Extra distance, in meters, between the final point and the chipper, on top of the 1.5x board length.
@export var chipper_extra_distance := 0.0

@export var roller_line: PackedScene
## Distance between roller line instances along the path, which should match the scene's length.
@export var roller_spacing := 450.0
## Offset from the path along its own Y axis (negative = below).
@export var roller_y_offset := -80.0

@export var split_gen:BoardSplitter;

# --- Board splitting lives in BoardSplitter; these keep the old API working. ---
var source_body: StaticBody3D:
	get:
		return board_splitter.source_body if board_splitter else null

var output_root: Node3D:
	get:
		return board_splitter.output_root if board_splitter else null

var split_map_nodes: Dictionary:
	get:
		return board_splitter.split_map_nodes if board_splitter else {}


func generate_splits() -> void:
	if board_splitter == null:
		push_warning("BodySplitPath: assign board_splitter first.")
		return
	board_splitter.generate_splits(cuts)


func get_pieces(stage: int = -1) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if board_splitter:
		result = board_splitter.get_pieces(stage)
	return result


func set_stage_enabled(stage: int, enabled: bool) -> void:
	if board_splitter:
		board_splitter.set_stage_enabled(stage, enabled)


func get_board_bounds() -> AABB:
	return board_splitter.get_board_bounds() if board_splitter else AABB()


func _read_boxes(body: Node3D) -> Dictionary:
	return board_splitter.read_boxes(body)


func _union(piece: Dictionary) -> AABB:
	return board_splitter.union_of(piece)



## A seed derived from the cut data itself, so identical cuts always get identical positioning.
func _cuts_seed(cut_list: Array[SplitCut]) -> int:
	var h := 1469598103934665603
	for cut in cut_list:
		for v:int in [cut.axis, roundi(cut.offset * 10000.0), cut.drop_side]:
			h = (h ^ v) * 1099511628211
	return h








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
	result.append(remaining)  # the last entry is the board left after every cut
	return result


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
	var remaining_before := _remaining_bounds_per_cut(valid_cuts, bounds)


	# Start from a copy of pre_curve (falls back to a single point at the origin).
	var new_curve: Curve3D = (pre_curve.duplicate() as Curve3D) if pre_curve != null else Curve3D.new()
	if new_curve.point_count == 0:
		new_curve.add_point(Vector3.ZERO)
	# Fix the start of the line at line_start_height above the floor (world Y = 0) by moving
	# this node, so the shape of the curve itself is left alone.
	var start_world_y := (global_transform * new_curve.get_point_position(0)).y
	global_position.y += line_start_height - start_world_y

	# One point per cut, all in a straight line along +X. The spacing depends only on how long
	# the board still is (its X size) when it reaches that saw.
	var pos := new_curve.get_point_position(new_curve.point_count - 1)
	var cut_point_indices: Array[int] = []  # curve index of each cut's point

	var rng := RandomNumberGenerator.new()
	rng.seed = _cuts_seed(valid_cuts) + positioning_seed

	const base_point_spacing = 500
	var length := board_size.x
	for i in valid_cuts.size():
		length = remaining_before[i].size.x
		pos.x += base_point_spacing + extra_point_spacing + length * rng.randf_range(1.25, 1.5)
		new_curve.add_point(pos)
		cut_point_indices.append(new_curve.point_count - 1)

	# One extra, empty point past the last saw, spaced like a further cut would be.
	pos.x += base_point_spacing + extra_point_spacing+ length * rng.randf_range(1.25, 1.5)
	new_curve.add_point(pos)
	
	var final_point_index := new_curve.point_count - 1

	# The chipper's point: 1.5x the length of the board left after the last cut, past the final point.
	var end_length: float = remaining_before.back().size.x
	pos.x += end_length * 1.5
	new_curve.add_point(pos)
	var chipper_point_index := new_curve.point_count - 1

	# The path runs on past the chipper for one more board length.
	pos.x += end_length * 1.5 + chipper_extra_distance
	new_curve.add_point(pos)
	curve = new_curve
	
	# Markers and saws: one per cut, at that cut's point (the run-out points get none).
	_clear_markers()


	var local_offset := _split_center_offset()
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else null

	# The pre_curve points get the same trigger areas.
	for p in cut_point_indices[0]:
		_create_point_area(markers, p, to_global(curve.get_point_position(p)),
			global_transform.basis.orthonormalized(), scene_root)

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
		# Every marker after the first also gets a trigger area on its curve point.
		_create_point_area(marker, i, point_global, board_basis, scene_root)
			
		var saw_scene: PackedScene
		var saw_scene_name: String
		match cut.axis:
			SplitCut.Axis.X:
				saw_scene = x_saw
				saw_scene_name = "x_saw"
			SplitCut.Axis.Y:
				saw_scene = y_saw
				saw_scene_name = "y_saw"
			_:
				saw_scene = z_saw
				saw_scene_name = "z_saw"
		if saw_scene == null:
			push_warning("BodySplitPath: assign %s to create the saw for cut %d." % [saw_scene_name, k + 1])
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

		# Every saw keeps the rotation its scene was authored with.
		saw.global_transform = Transform3D(native_basis, marker.global_position)
		
		
		var saw_target := plane_point
		if mirror_saws_xz:
			saw_target = Vector3(-plane_point.x, plane_point.y, -plane_point.z)
		var plane_shift := board_basis * (saw_target - local_offset)
		
		# If the scene has a child named "saw", only that node moves to the cut; the rest of
		# the scene stays on the marker. Otherwise the whole scene moves, as before.
		var blade := saw.find_child("saw", true, false) as Node3D
		var mover: Node3D = blade if blade != null else saw
		mover.global_position += plane_shift + board_basis * saw_offset
		saw.name = "Saw"
		if scene_root:
			saw.owner = scene_root
				

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
	final_box.size = Vector3.ONE * POINT_AREA_SIZE
	final_shape_node.shape = final_box
	final_area.add_child(final_shape_node)

	markers.add_child(final_area)
	final_area.global_position = to_global(curve.get_point_position(final_point_index))
	if scene_root:
		final_area.owner = scene_root
		final_shape_node.owner = scene_root
		
	# The chipper sits on the extra point (no trigger area there). Its scene keeps its authored rotation
	# relative to the direction the board travels.
	if chipper_scene != null:
		var chipper := chipper_scene.instantiate() as Node3D
		if chipper == null:
			push_warning("BodySplitPath: the chipper scene's root isn't a Node3D.")
		else:
			var native_basis := chipper.basis
			chipper.name = "chipper"
			chipper.set_meta(MARKER_META, true)
			chipper.add_to_group("chippers", true)
			markers.add_child(chipper)
			chipper.global_transform = Transform3D(_board_basis_at(chipper_point_index) * native_basis,
					to_global(curve.get_point_position(chipper_point_index)))
			
			if scene_root:
				chipper.owner = scene_root
	
	_create_rollers(scene_root)
	



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


## The boards of a stage that stay attached, meaning they don't fall off at that stage's cut.
## Stage 0 is the source body itself; stages 1 and up are the generated ones.
func get_remaining_boards(stage: int) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	if stage <= 0:
		if source_body != null:
			result.append(source_body)
		return result
	for body in get_pieces(stage):
		if not body.get_meta(split_gen.FALLS_KEY, false):
			result.append(body)
	return result

## Everything this path puts in the room (the board's sweep along the path, the saws), as boxes in the
## space that to_local_xform maps world space into.
func get_room_boxes(to_local_xform: Transform3D) -> Array[AABB]:
	var boxes: Array[AABB] = []
	if curve == null:
		return boxes
	var bounds := get_board_bounds()
	# Farthest the board reaches from its origin in the XZ plane: the radius it sweeps when turning.
	var turn_radius := Vector2(
		maxf(absf(bounds.position.x), absf(bounds.end.x)),
		maxf(absf(bounds.position.z), absf(bounds.end.z))
	).length()
	for p in curve.get_baked_points():
		var c := to_local_xform * to_global(p)
		boxes.append(AABB(
			c + Vector3(-turn_radius, bounds.position.y, -turn_radius),
			Vector3(2.0 * turn_radius, bounds.size.y, 2.0 * turn_radius)
		))
	if markers != null:
		for saw: Node in markers.find_children("*", "Node3D", true, false):
			if not (saw.is_in_group("saws") or saw.is_in_group("chippers")):
				continue
			boxes.append(AABB(to_local_xform * (saw as Node3D).global_position, Vector3.ZERO))
			var visuals: Array = saw.find_children("*", "VisualInstance3D", true, false)
			if saw is VisualInstance3D:
				visuals.append(saw)
			for vi: Node in visuals:
				var global_box: AABB = vi.global_transform * vi.get_aabb()
				boxes.append(to_local_xform * global_box)
	return boxes

## The board of a stage that won't be removed, or null if there isn't one.
func get_remaining_board(stage: int) -> StaticBody3D:
	var boards := get_remaining_boards(stage)
	return boards[0] if not boards.is_empty() else null

func get_split_count()->int:
	return len(split_gen.split_map)
	
## Lays roller_line instances end to end along the whole path. Each one is centered on its
## slot, with its local Z axis running along the path.
func _create_rollers(scene_root: Node) -> void:
	_clear_rollers()
	if roller_line == null:
		return
	var length := curve.get_baked_length()
	if length <= 0.0 or roller_spacing <= 0.0:
		return

	var up := global_transform.basis.y.normalized()
	var count := ceili(length / roller_spacing - EPS)
	for i in count:
		var offset := (i + 0.5) * roller_spacing
		# A slot past the end of the path continues straight on from the last point.
		var clamped := minf(offset, length)
		var dir := (curve.sample_baked(minf(clamped + 1.0, length))
				- curve.sample_baked(maxf(clamped - 1.0, 0.0))).normalized()
		var local_pos := curve.sample_baked(clamped) + dir * (offset - clamped) \
				+ Vector3(0.0, roller_y_offset, 0.0)

		# Basis whose local +Z points along the path and whose Y stays the path's up.
		var z_axis := (global_transform.basis * dir).normalized()
		var x_axis := up.cross(z_axis).normalized()
		var y_axis := z_axis.cross(x_axis)

		var roller := roller_line.instantiate() as Node3D
		if roller == null:
			push_warning("BodySplitPath: the roller_line scene's root isn't a Node3D.")
			return
		roller.name = "RollerLine_%02d" % (i + 1)
		roller.set_meta(MARKER_META, true)
		roller_root.add_child(roller)
		roller.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), to_global(local_pos))
		if scene_root:
			roller.owner = scene_root


func _clear_rollers() -> void:
	if roller_root == null:
		return
	for c in roller_root.get_children():
		if c.has_meta(MARKER_META):
			roller_root.remove_child(c)
			c.queue_free()

## A POINT_AREA_SIZE cube trigger on layer 4, centered on a point, named point_<index>.
func _create_point_area(parent: Node3D, index: int, global_pos: Vector3, area_basis: Basis, scene_root: Node) -> void:
	var area := Area3D.new()
	area.name = "point_%d" % index
	area.set_meta(MARKER_META, true)
	area.monitoring = false
	area.monitorable = true
	area.collision_layer = 0
	area.set_collision_layer_value(4, true)

	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * POINT_AREA_SIZE
	shape_node.shape = box
	area.add_child(shape_node)

	parent.add_child(area)
	area.global_transform = Transform3D(area_basis, global_pos)
	if scene_root:
		area.owner = scene_root
		shape_node.owner = scene_root
