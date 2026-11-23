@tool
class_name NoiseSplitSequence
extends Node

## Group the generated extra-path copies are put in.
const EXTRA_GROUP := &"extra_path_copy"
## Meta on each top-level copy: the level number it belongs to (the first path is level 1).
const LEVEL_META := &"level_number"
## Smallest a falling piece may be, in meters. It only keeps a cut from sitting exactly on a face.
const MIN_FALLING_PIECE := 0.001
## Never copied from the first path to a new one (each path makes its own).
const NOT_COPIED: Array[StringName] = [&"cuts", &"positioning_seed", &"split_map"]

## The scene tree, fetched once when this node enters it (get_tree() is only called here).
var _tree: SceneTree

## Runtime only. Slot i is level i + 1; a freed path leaves null.
var paths: Array[BodySplitPath] = []

@export var splitter: BodySplitPath
@export var noise: Noise
@export var cut_count := 6

@export_group("Sampling")
## Where in the noise field the sequence starts. Change it (or the noise's seed) for a different sequence.
@export var sample_origin := Vector2.ZERO
## Distance between consecutive samples in the noise field. FastNoiseLite's default frequency is
## 0.01, so about 50 gives clearly different neighbours; much smaller drifts slowly instead.
@export var noise_step := 50.0
## Noise values cluster near 0, so this stretches them to use more of the board. 1 = raw noise.
@export var noise_contrast := 1.8

@export_group("Rules")
@export var allow_x_cuts := true
@export var allow_y_cuts := true
@export var allow_z_cuts := true

## Never place two cuts in a row on the same axis (needs at least two axes enabled).
@export var no_repeat_axis := false

## Minimum size (meters) of a piece that stays attached after a cut. The piece that falls can be any size.
@export var min_piece_size := 0.05

## The most a single saw may cut off, as a fraction of the original board's length along that saw's axis
## (X, Y or Z). 1 = no limit. Y cuts drop the top, X and Z cuts drop the smaller side, so below 0.5 the
## X and Z cuts have to sit close to one end of the board.
@export_range(0.01, 1.0, 0.01) var max_cut_fraction := 1.0

@export_group("Levels")
## Scene each new level is instantiated from. Its root is a BodySplitPath, or contains one.
## The first path is the reference for exported values and signal connections the scene doesn't have.
@export var path_scene: PackedScene
## Stop building new levels after this many (the first path counts). 0 = endless.
@export var max_levels := 0
## How far along the world Z axis each new path starts from the final point of the path before it.
## Negative values go the other way.
@export var extra_path_z_offset := 3000.0
## Bodies (of the first path) that get collision layer 8 turned on in the new levels.
@export var layer_8_on_copy: Array[StaticBody3D] = []

@export_group("")
@export_tool_button("Generate Cuts") var cuts_action := generate_into_splitter
@export_tool_button("Generate Cuts + Splits + Markers") var all_action := generate_everything
@export_tool_button("Generate Level (random seed)") var level_action := generate_level



@export_group("Room")
@export var floor_plane: MeshInstance3D
@export var ceiling: MeshInstance3D
@export var wall_front: MeshInstance3D
@export var wall_back: MeshInstance3D
@export var wall_left: MeshInstance3D
@export var wall_right: MeshInstance3D
@export var floor_ceiling_texture_scale := 2.0
## Extra space between the paths and each wall, in meters.
@export var room_margin := 500.0
## Fixed height of the room, in meters. The floor is always at world Y = 0.
@export var room_height := 1000.0
## Width of the opening in the wall after each path, centered where that path ends and the next begins. 0 = solid wall.
@export var divider_opening_width := 600.0
## Height of that opening, measured from the floor. 0 = all the way up.
@export var divider_opening_height := 0.0
## Fills the openings (needed to see anything in them).
@export var cover_material: Material

const DIVIDER_GROUP := &"room_divider"
const DIVIDER_GAP := 0.5
const EXIT_META := &"exit_level"
const EPS := 0.0001

var _room_lo := Vector3.ZERO  # the room as last fitted, in the first path's local space
var _room_hi := Vector3.ZERO
var _room_fitted := false
## level -> {"z", "x", "covered"} for the wall after that level (between it and the next one).
var _exits := {}

func _enter_tree() -> void:
	_tree = get_tree()


func _ready() -> void:
	if Engine.is_editor_hint() or splitter == null:
		return
	paths = [splitter]
	_build_first_room()
	_watch(splitter)


func _exit_tree() -> void:
	_tree = null


## Builds the cut sequence and puts it on the splitter. Returns false if nothing was generated.
func generate_into_splitter() -> bool:
	if splitter == null or noise == null:
		push_warning("NoiseSplitSequence: assign splitter and noise first.")
		return false
	return _generate_into(splitter)


## Builds the first path only (no extra paths).
func generate_everything() -> void:
	if generate_into_splitter():
		splitter.generate_splits()
		splitter.create_split_markers()
		_build_first_room()

func _generate_into(target: BodySplitPath) -> bool:
	var result := _generate_cuts_for(target)
	if result.is_empty():
		return false
	target.cuts = result
	target.notify_property_list_changed()
	return true


## The cut sequence for the current settings. Same settings always give the same sequence.
func generate_cuts() -> Array[SplitCut]:
	return _generate_cuts_for(splitter)


func _generate_cuts_for(target: BodySplitPath) -> Array[SplitCut]:
	var result: Array[SplitCut] = []
	if target == null or noise == null:
		return result

	var bounds := target.get_board_bounds()
	if bounds.size == Vector3.ZERO:
		push_warning("NoiseSplitSequence: the splitter has no board to read bounds from (assign its source_body).")
		return result

	var axes: Array[int] = []
	if allow_x_cuts:
		axes.append(SplitCut.Axis.X)
	if allow_y_cuts:
		axes.append(SplitCut.Axis.Y)
	if allow_z_cuts:
		axes.append(SplitCut.Axis.Z)
	if axes.is_empty():
		push_warning("NoiseSplitSequence: all axes are disabled.")
		return result

	# The board that is still attached after the cuts so far. Each cut drops one side, so this
	# shrinks, and every new cut is placed inside it so its saw always touches what's left.
	var remaining := bounds
	var sample := 0
	var max_samples := cut_count * 25
	var last_axis := -1
	# With X plus another axis enabled, every cut must leave the board thick enough for a final non-X cut.
	var reserve_last := axes.size() > 1 and axes.has(SplitCut.Axis.X) and _can_cut_non_x(bounds, -1)
	while result.size() < cut_count and sample < max_samples:
		var t := sample_origin.x + sample * noise_step
		sample += 1  # a rejected sample still moves on, so the sequence can't get stuck

		# Axes this cut may use: every enabled one, minus X for the last cut (unless X is the only
		# enabled axis), minus the previous cut's if repeats are off.
		var is_last := result.size() == cut_count - 1
		var candidates: Array[int] = []
		for a in axes:
			if is_last and axes.size() > 1 and a == SplitCut.Axis.X:
				continue
			if is_last and not _has_room(remaining.size[a]):
				continue  # too thin to cut: don't pick an axis the last cut can't use
			if not (no_repeat_axis and a == last_axis):
				candidates.append(a)
		if candidates.is_empty():
			push_warning("NoiseSplitSequence: no_repeat_axis needs at least two enabled axes.")
			break

		var pick := _unit(noise.get_noise_2d(t, sample_origin.y))
		var axis: int = candidates[mini(int(pick * candidates.size()), candidates.size() - 1)]

		var p0 := remaining.position[axis]
		var p1 := remaining.end[axis]
		var mid := (p0 + p1) * 0.5
		var max_drop := max_cut_fraction * bounds.size[axis]
		var u := _unit(noise.get_noise_2d(t, sample_origin.y + 1000.0))
		var lo: float
		var hi: float
		var drop_negative: bool
		if axis == SplitCut.Axis.Y:
			# The top falls. The board below keeps at least min_piece_size, the cut sits at or above
			# the middle (at most half drops), and at most max_drop may drop.
			drop_negative = false
			lo = maxf(p0 + min_piece_size, maxf(mid, p1 - max_drop))
			hi = p1 - MIN_FALLING_PIECE
		else:
			# The smaller side falls; noise picks which end. The side that stays keeps at least
			# min_piece_size, and at most max_drop (and at most half) may drop.
			drop_negative = _unit(noise.get_noise_2d(t, sample_origin.y + 2000.0)) < 0.5
			if drop_negative:
				lo = p0 + MIN_FALLING_PIECE
				hi = minf(mid, minf(p0 + max_drop, p1 - min_piece_size))
			else:
				lo = maxf(mid, maxf(p1 - max_drop, p0 + min_piece_size))
				hi = p1 - MIN_FALLING_PIECE
		if hi <= lo:
			continue  # no position fits the rules on this axis
		var offset := lerpf(lo, hi, u)
		var cut := SplitCut.new()
		cut.axis = axis as SplitCut.Axis
		cut.offset = offset
		cut.drop_side = SplitCut.DropSide.NEGATIVE_SIDE if drop_negative else SplitCut.DropSide.POSITIVE_SIDE

		# What stays attached after this cut.
		var pos := remaining.position
		var size := remaining.size
		if cut.drops(true):
			pos[axis] = offset
			size[axis] = remaining.end[axis] - offset
		else:
			size[axis] = offset - remaining.position[axis]
		var after := AABB(pos, size)

		# Reject a cut that would leave the board too thin for a final non-X cut.
		if reserve_last and not is_last:
			var skip := axis if (no_repeat_axis and result.size() == cut_count - 2) else -1
			if not _can_cut_non_x(after, skip):
				continue

		last_axis = axis
		result.append(cut)
		remaining = after

	# Safety net: never end on an X cut when other axes are enabled.
	while axes.size() > 1 and not result.is_empty() and result.back().axis == SplitCut.Axis.X:
		result.pop_back()

	if result.size() < cut_count:
		push_warning("NoiseSplitSequence: only %d of %d cuts fit; lower min_piece_size or cut_count." % [result.size(), cut_count])
	return result


## True if a board this long on an axis can take a cut: the piece that stays keeps min_piece_size.
func _has_room(axis_size: float) -> bool:
	return axis_size > min_piece_size + MIN_FALLING_PIECE


## True if a Y or Z cut could still be placed in `remaining` (the same room test the cut placement uses).
## skip_axis is left out of the check (-1 = none).
func _can_cut_non_x(remaining: AABB, skip_axis: int) -> bool:
	if allow_y_cuts and skip_axis != SplitCut.Axis.Y \
			and _has_room(remaining.size[SplitCut.Axis.Y]):
		return true
	if allow_z_cuts and skip_axis != SplitCut.Axis.Z \
			and _has_room(remaining.size[SplitCut.Axis.Z]):
		return true
	return false


## Noise (-1..1) -> 0..1, with contrast, never reaching exactly 1.
func _unit(v: float) -> float:
	return clampf(v * noise_contrast * 0.5 + 0.5, 0.0, 0.9999)

signal level_generated(level_seed: int)

## The seed the current level was built from. Pass it back to generate_level() to rebuild the same level.
var current_seed := 0


## Builds a whole level (cuts, split boards, markers, saws, room) from a seed.
## With no argument it picks a new random seed. Returns the seed used, or 0 on failure.
func generate_level(level_seed: int = 0) -> int:
	if splitter == null or noise == null:
		push_warning("NoiseSplitSequence: assign splitter and noise first.")
		return 0

	if level_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		level_seed = maxi(rng.randi(), 1)  # 0 means "pick one for me", so never use it as a seed

	# Levels from an earlier run go first.
	_clear_extra_paths()
	paths = [splitter]

	_apply_seed(level_seed)
	splitter.positioning_seed = level_seed

	if not generate_into_splitter():
		return 0
	splitter.generate_splits()
	splitter.create_split_markers()
	_build_first_room()

	current_seed = level_seed
	level_generated.emit(level_seed)
	return level_seed


## Points the noise at a seed. FastNoiseLite has one; other Noise types move through the field instead.
func _apply_seed(s: int) -> void:
	if noise is FastNoiseLite:
		(noise as FastNoiseLite).seed = s
	else:
		sample_origin = Vector2(s % 100000, (s / 100000) % 100000)


## The seed of level n (2 and up), derived from the level seed so the same level seed
## always rebuilds the same levels.
func _extra_seed(level_seed: int, n: int) -> int:
	return maxi(absi(("%d_path_%d" % [level_seed, n]).hash()), 1)


# --- Levels --------------------------------------------------------------------

## Connects the generator's handler to a path's stage_started and makes it the FIRST callback:
## the connections already on the signal are taken off and put back after it, flags and order kept.
func _watch(path: BodySplitPath) -> void:
	var existing := path.stage_started.get_connections()
	for conn:Dictionary in existing:
		path.stage_started.disconnect(conn.callable)
	path.stage_started.connect(_on_stage_started.bind(path))
	for conn:Dictionary in existing:
		path.stage_started.connect(conn.callable, conn.flags)


## A path started: free the one before it, then build the next one.
func _on_stage_started(path: BodySplitPath) -> void:
	var idx := paths.find(path)
	if idx < 0:
		return
	if idx > 0 and paths[idx - 1] != null:
		_free_path(idx - 1)
	_cover_only_exit(idx)  # the wall after level `idx` is the one between this path and the one before it
	if max_levels > 0 and paths.size() >= max_levels:
		return
	if idx + 1 >= paths.size():
		_build_next_path(path)


## Turns on level `level` (2 and up) and starts it. Call this when the player reaches the end of the path before it.
func start_level(level: int) -> void:
	if level < 2 or level > paths.size() or paths[level - 1] == null:
		return
	set_level_enabled(level, true)
	paths[level - 1].start_stage()


func _build_next_path(from: BodySplitPath) -> BodySplitPath:
	var n := paths.size() + 1  # level number, also the new scene's name suffix
	var path := _instantiate_path(from, n)
	if path == null:
		return null

	var base_seed := splitter.positioning_seed
	var path_seed := _extra_seed(base_seed, n)
	_apply_seed(path_seed)
	path.positioning_seed = path_seed
	var ok := _generate_into(path)
	if base_seed != 0:
		_apply_seed(base_seed)  # leave the noise on the level's own seed
	if not ok:
		push_warning("NoiseSplitSequence: couldn't generate cuts for path %d." % n)
		_free_level_nodes(n)
		return null
	path.generate_splits()
	path.create_split_markers()
	
	paths.append(path)
	_watch(path)
	if _has_next(n):
		_register_exit(n, path)
	_fit_room(true)  # grows the room around the new path and rebuilds every wall
	return path


## Frees the path in slot `index` with all its nodes. The first path's nodes belong to the
## scene, so only what was generated for them is cleared.
func _free_path(index: int) -> void:
	var path := paths[index]
	if path != null and is_instance_valid(path):
		if path == splitter:
			if splitter.markers != null:
				splitter._clear_markers()
			splitter._clear_rollers()
			if splitter.board_splitter != null and splitter.output_root != null:
				splitter.board_splitter._clear_generated()
		else:
			_free_level_nodes(index + 1)
	paths[index] = null
	if index >= 1:
		_free_exit(index)  # the wall between the path before it and this one


## Turns a level on or off by its number. Level 1 is the first path and is left alone.
func set_level_enabled(level: int, enabled: bool) -> void:
	if level < 2 or _tree == null:
		return
	for n in _tree.get_nodes_in_group(EXTRA_GROUP):
		if is_instance_valid(n) and n.get_meta(LEVEL_META, 0) == level:
			n.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


## Instantiates path_scene as level n, places its start extra_path_z_offset along world Z from the
## final point of `previous`, and fills in everything the first path has that the scene doesn't.
## The new level starts disabled.
func _instantiate_path(previous: BodySplitPath, n: int) -> BodySplitPath:
	if path_scene == null:
		push_warning("NoiseSplitSequence: assign path_scene to build more levels.")
		return null
	if _tree == null or splitter.get_parent() == null:
		push_warning("NoiseSplitSequence: this node and the splitter must be in the scene tree to build paths.")
		return null

	var root := path_scene.instantiate()  # not in the tree yet
	var path := root as BodySplitPath
	if path == null:
		for c: Node in root.find_children("*", "Path3D", true, false):
			if c is BodySplitPath:
				path = c
				break
	if path == null:
		push_warning("NoiseSplitSequence: path_scene has no BodySplitPath.")
		root.free()
		return null
	_strip_generated(root)

	# The first path's scene root: walk up from the splitter as far as the new path sits below its root.
	var rel := root.get_path_to(path)
	var ref_root: Node = splitter
	if rel != ^".":
		for i in rel.get_name_count():
			if ref_root.get_parent() != null:
				ref_root = ref_root.get_parent()

	# Reference node -> the matching node in the new scene (matched by relative path).
	var map := {}
	for o: Node in [ref_root] + ref_root.find_children("*", "", true, false):
		var c := root.get_node_or_null(ref_root.get_path_to(o))
		if c != null:
			map[o] = c
	for o: Node in map:
		_copy_exports(o, map[o], map)
	_remap_connections(map)

	# Every path shares the first path's room, so the new one gets no planes of its own.
	for prop: StringName in [&"floor_plane", &"ceiling", &"wall_front", &"wall_back", &"wall_left", &"wall_right"]:
		var plane := path.get(prop) as Node
		if plane != null and root.is_ancestor_of(plane):
			_free_now(plane)
		path.set(prop, null)

	for body in layer_8_on_copy:
		var body_copy := map.get(body) as StaticBody3D
		if body_copy != null:
			body_copy.set_collision_layer_value(8, true)
			body_copy.process_mode = Node.PROCESS_MODE_ALWAYS
			body_copy.add_to_group(StringName("level_%d" % n), true)

	root.name = "%s_%02d" % [ref_root.name, n]
	root.add_to_group(EXTRA_GROUP)
	root.set_meta(LEVEL_META, n)
	root.process_mode = Node.PROCESS_MODE_DISABLED  # start_level() turns it on
	ref_root.get_parent().add_child(root)

	# Same orientation as the first path, then slide the new path's start onto the target point.
	var mover := (root as Node3D) if root is Node3D else path
	if ref_root is Node3D:
		mover.global_basis = (ref_root as Node3D).global_basis
	var wanted := _final_point_global(previous) + Vector3(0.0, 0.0, extra_path_z_offset) \
			- path.global_transform.basis * _start_point_local(path)
	mover.global_position += Vector3(wanted.x - path.global_position.x, 0.0, wanted.z - path.global_position.z)
	return path


## Copies the exported variables of `from` onto `to` (same script). References to nodes of the first
## path's scene become the matching nodes of the new scene; references to anything else stay as they are.
func _copy_exports(from: Node, to: Node, map: Dictionary) -> void:
	if from.get_script() == null or from.get_script() != to.get_script():
		return
	for info in from.get_property_list():
		if not (info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (info.usage & PROPERTY_USAGE_STORAGE):
			continue
		if info.name in NOT_COPIED:
			continue
		var value: Variant = from.get(info.name)
		if value is Node:
			value = map.get(value, value)
		elif value is Array:
			var arr: Array = value.duplicate()
			for i in arr.size():
				if arr[i] is Node:
					arr[i] = map.get(arr[i], arr[i])
			value = arr
		to.set(info.name, value)


## Gives each new node the signal connections its reference node has and it doesn't. Targets inside the
## first path's scene become the new scene's nodes; other targets in the scene stay as they are.
## Connections to engine objects, lambdas and bound callables are left alone.
func _remap_connections(map: Dictionary) -> void:
	var scene: Node = _tree.edited_scene_root if Engine.is_editor_hint() else _tree.current_scene
	if scene != null and scene != self and not scene.is_ancestor_of(self):
		scene = null
	for o: Node in map:
		var c: Node = map[o]
		for sig in o.get_signal_list():
			var sig_name: StringName = sig.name
			for conn in o.get_signal_connection_list(sig_name):
				var callable: Callable = conn.callable
				if callable.is_custom():
					continue
				var target := callable.get_object() as Node
				if target == null or not (map.has(target) or _in_level_tree(target, scene)):
					continue
				var new_target: Node = map.get(target, target)
				var new_callable := Callable(new_target, callable.get_method())
				if is_instance_valid(new_target) and not c.is_connected(sig_name, new_callable):
					var err := c.connect(sig_name, new_callable, conn.flags)
					if err != OK:
						push_warning("NoiseSplitSequence: couldn't connect %s.%s to %s.%s (error %d)." % [
								c.name, sig_name, new_target.name, callable.get_method(), err])


func _in_level_tree(node: Node, scene: Node) -> bool:
	if not node.is_inside_tree():
		return false
	return scene == null or node == scene or scene.is_ancestor_of(node)


## Removes anything the generators made or your code tagged as spawned, so it never reaches a new level.
func _strip_generated(root: Node) -> void:
	for n: Node in root.find_children("*", "", true, false):
		if not is_instance_valid(n) or n.get_parent() == null:
			continue
		if n.has_meta(BodySplitPath.MARKER_META) or n.has_meta(BoardSplitter.META_KEY):
			_free_now(n)


func _free_level_nodes(level: int) -> void:
	for n in _tree.get_nodes_in_group(EXTRA_GROUP):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n.get_meta(LEVEL_META, 0) == level:
			_free_now(n)


func _clear_extra_paths() -> void:
	if _tree == null:
		return
	for n in _tree.get_nodes_in_group(EXTRA_GROUP):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			_free_now(n)


## Removed from the tree right away (so names are free again), then freed.
func _free_now(n: Node) -> void:
	var p := n.get_parent()
	if p != null:
		p.remove_child(n)
	n.queue_free()


## The path's final point (where its last trigger area sits). The chipper's point and the run-out past it don't count.
func _final_point_global(path: BodySplitPath) -> Vector3:
	return path.to_global(path.curve.get_point_position(maxi(path.curve.point_count - 3, 0)))

## Local position of the first curve point a path generates from (pre_curve's first point, or the origin).
func _start_point_local(path: BodySplitPath) -> Vector3:
	if path.pre_curve != null and path.pre_curve.point_count > 0:
		return path.pre_curve.get_point_position(0)
	return Vector3.ZERO


# --- Room ----------------------------------------------------------------------

## True if a level after `level` will be built, so the wall after it needs an opening.
func _has_next(level: int) -> bool:
	return path_scene != null and (max_levels <= 0 or level < max_levels)


## Fits the room around the first path and builds the wall after it.
func _build_first_room() -> void:
	_clear_exits()
	paths = [splitter]
	if _has_next(1):
		_register_exit(1, splitter)
	_fit_room()


## Covers or uncovers the opening in the wall after `level` by hand. Stage starts overwrite this:
## only the opening behind the stage that just started stays covered.
func set_exit_covered(level: int, covered: bool) -> void:
	if not _exits.has(level):
		return
	_exits[level]["covered"] = covered
	_rebuild_exit(level)

## Covers the opening in the wall after `level` and uncovers every other one.
func _cover_only_exit(level: int) -> void:
	for l: int in _exits.keys():
		var covered := l == level
		if _exits[l]["covered"] != covered:
			_exits[l]["covered"] = covered
			_rebuild_exit(l)

## Sizes and places the room planes around every path that exists. grow_only keeps the room from
## shrinking when a path has been freed.
func _fit_room(grow_only := false) -> void:
	if splitter == null:
		return
	var to_local := splitter.global_transform.affine_inverse()
	var fit: Array[AABB] = []  # everything the room must contain, in the first path's local space
	var last: BodySplitPath = null
	for p in paths:
		if p != null and is_instance_valid(p):
			fit.append_array(p.get_room_boxes(to_local))
			last = p
	if last == null or fit.is_empty():
		return
	# The room reaches the start of the path after the last one, so the opening between them lies inside it.
	if _exits.has(paths.find(last) + 1):
		fit.append(AABB(to_local * (_final_point_global(last) + Vector3(0.0, 0.0, extra_path_z_offset)), Vector3.ZERO))
	var room := fit[0]
	for k in range(1, fit.size()):
		room = room.merge(fit[k])

	var content := room  # everything that has to fit, before the margin
	room = room.grow(room_margin)

	# Fixed height: the floor sits at world Y = 0 and the ceiling room_height above it.
	var floor_y := (to_local * Vector3.ZERO).y
	var lo := room.position
	var hi := room.end
	lo.y = floor_y
	hi.y = floor_y + room_height
	if content.position.y < lo.y or content.end.y > hi.y:
		push_warning("NoiseSplitSequence: part of the system sticks out of the room vertically. Raise room_height or move the path up.")
	if grow_only and _room_fitted:
		lo = Vector3(minf(lo.x, _room_lo.x), lo.y, minf(lo.z, _room_lo.z))
		hi = Vector3(maxf(hi.x, _room_hi.x), hi.y, maxf(hi.z, _room_hi.z))
	_room_lo = lo
	_room_hi = hi
	_room_fitted = true

	var c := (lo + hi) * 0.5
	var s := hi - lo

	# Walls: sizes are (width, height). The extra `true` makes the texture fit the wall.
	_place_plane(wall_front, Basis(Vector3.BACK, Vector3.LEFT, Vector3.DOWN),
			Vector3(hi.x, c.y, c.z), Vector2(s.z, s.y), true)
	_place_plane(wall_back, Basis(Vector3.FORWARD, Vector3.RIGHT, Vector3.DOWN),
			Vector3(lo.x, c.y, c.z), Vector2(s.z, s.y), true)
	_place_plane(wall_right, Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN),
			Vector3(c.x, c.y, hi.z), Vector2(s.x, s.y), true)
	_place_plane(wall_left, Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
			Vector3(c.x, c.y, lo.z), Vector2(s.x, s.y), true)

	_place_plane(floor_plane, Basis.IDENTITY, Vector3(c.x, lo.y + 300, c.z), Vector2(s.x, s.z))
	_place_plane(ceiling, Basis(Vector3.RIGHT, PI), Vector3(c.x, hi.y, c.z), Vector2(s.x, s.z))
	_tile_texture(floor_plane, Vector2(s.x, s.z), floor_ceiling_texture_scale)
	_tile_texture(ceiling, Vector2(s.x, s.z), floor_ceiling_texture_scale)

	for level: int in _exits.keys():
		_rebuild_exit(level)


## Registers the wall after `level`: halfway between where `path` ends and where the next path will start.
func _register_exit(level: int, path: BodySplitPath) -> void:
	if path == null or path.curve == null or path.curve.point_count == 0:
		return
	var to_local := splitter.global_transform.affine_inverse()
	var end_global := _final_point_global(path)
	var end_a := to_local * end_global
	var start_b := to_local * (end_global + Vector3(0.0, 0.0, extra_path_z_offset))
	_exits[level] = {
		"z": (end_a.z + start_b.z) * 0.5,
		"x": (end_a.x + start_b.x) * 0.5,
		"covered": false,
	}


func _free_exit(level: int) -> void:
	_free_exit_planes(level)
	_exits.erase(level)


func _clear_exits() -> void:
	_exits.clear()
	if _tree == null:
		return
	for n in _tree.get_nodes_in_group(DIVIDER_GROUP):
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			_free_now(n)


func _free_exit_planes(level: int) -> void:
	if _tree == null:
		return
	for n in _tree.get_nodes_in_group(DIVIDER_GROUP):
		if is_instance_valid(n) and not n.is_queued_for_deletion() and n.get_meta(EXIT_META, -1) == level:
			_free_now(n)


## Builds the wall after `level` with its opening, and the cover that fills the opening.
func _rebuild_exit(level: int) -> void:
	_free_exit_planes(level)
	if wall_left == null or wall_right == null or not _room_fitted or not _exits.has(level):
		return
	var d: Dictionary = _exits[level]
	var lo := _room_lo
	var hi := _room_hi
	var scene_root := _tree.edited_scene_root if Engine.is_editor_hint() else null
	var half := maxf(divider_opening_width, 0.0) * 0.5
	var height := hi.y - lo.y
	var door := height if (divider_opening_height <= 0.0 or divider_opening_height >= height) else divider_opening_height
	var z: float = d["z"]
	var x0 := clampf(float(d["x"]) - half, lo.x, hi.x)
	var x1 := clampf(float(d["x"]) + half, lo.x, hi.x)
	var facing_pos := Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
	var facing_neg := Basis(Vector3.LEFT, Vector3.FORWARD, Vector3.DOWN)

	# Wall pieces as rectangles in (x, y): left of the opening, right of it, and above it.
	var pieces: Array[Rect2] = [
		Rect2(lo.x, lo.y, x0 - lo.x, height),
		Rect2(x1, lo.y, hi.x - x1, height),
	]
	if door < height:
		pieces.append(Rect2(x0, lo.y + door, x1 - x0, height - door))
	var k := 0
	for r in pieces:
		if r.size.x <= EPS or r.size.y <= EPS:
			continue
		k += 1
		var center := Vector3(r.position.x + r.size.x * 0.5, r.position.y + r.size.y * 0.5, z)
		_add_exit_plane(wall_left, facing_pos, center + Vector3(0.0, 0.0, DIVIDER_GAP), r.size,
				"Divider_%02d_%d_A" % [level, k], scene_root, level)
		_add_exit_plane(wall_right, facing_neg, center - Vector3(0.0, 0.0, DIVIDER_GAP), r.size,
				"Divider_%02d_%d_B" % [level, k], scene_root, level)

	# The cover fills the opening itself, from the floor up to the top of the opening.
	if d["covered"] and cover_material != null and x1 - x0 > EPS:
		var cover_center := Vector3((x0 + x1) * 0.5, lo.y + door * 0.5, z)
		var cover_size := Vector2(x1 - x0, door)
		_add_exit_plane(wall_left, facing_pos, cover_center + Vector3(0.0, 0.0, DIVIDER_GAP), cover_size,
				"DividerCover_%02d_A" % level, scene_root, level, cover_material)
		_add_exit_plane(wall_right, facing_neg, cover_center - Vector3(0.0, 0.0, DIVIDER_GAP), cover_size,
				"DividerCover_%02d_B" % level, scene_root, level, cover_material)


func _add_exit_plane(template: MeshInstance3D, plane_basis: Basis, local_pos: Vector3, size: Vector2,
		plane_name: String, scene_root: Node, level: int, material: Material = null) -> void:
	var plane := template.duplicate() as MeshInstance3D
	plane.name = plane_name
	template.get_parent().add_child(plane)
	plane.add_to_group(DIVIDER_GROUP, true)
	plane.set_meta(EXIT_META, level)
	if scene_root and template.owner == scene_root:
		plane.owner = scene_root
	_place_plane(plane, plane_basis, local_pos, size, material == null)
	if material != null:
		plane.material_override = material


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
		push_warning("NoiseSplitSequence: '%s' has no StandardMaterial3D with an albedo texture to tile." % node.name)
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


## Gives the node its own PlaneMesh of the right size and puts it at local_pos (in the first path's
## space), rotated so the plane's visible side faces into the room.
func _place_plane(node: MeshInstance3D, r: Basis, local_pos: Vector3, size: Vector2, fit_texture := false) -> void:
	if node == null:
		return
	var mesh := (node.mesh.duplicate() as PlaneMesh) if node.mesh is PlaneMesh else PlaneMesh.new()
	mesh.size = size
	mesh.orientation = PlaneMesh.FACE_Y  # the rotations assume the plane faces +Y
	mesh.flip_faces = false
	mesh.center_offset = Vector3.ZERO
	node.mesh = mesh
	node.global_transform = splitter.global_transform * Transform3D(r, local_pos)
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
		push_warning("NoiseSplitSequence: '%s' has no StandardMaterial3D with an albedo texture to fit." % node.name)
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
