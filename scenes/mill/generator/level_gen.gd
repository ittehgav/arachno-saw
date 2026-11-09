@tool
class_name NoiseSplitSequence
extends Node

## Group the generated extra-path copies are put in (persistent, so they survive saving the scene).
const EXTRA_GROUP := &"extra_path_copy"
## Meta on each top-level copy: the level number it belongs to (the first path is level 1).
const LEVEL_META := &"level_number"
## Smallest a falling piece may be, in meters. It only keeps a cut from sitting exactly on a face.
const MIN_FALLING_PIECE := 0.1
## The scene tree, fetched once when this node enters it (get_tree() is only called here).
var _tree: SceneTree

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
## Bodies that get collision layer 8 turned on in their copies. The originals are left alone.
@export var layer_8_on_copy: Array[StaticBody3D] = []
## Minimum distance (meters) between a cut and the board's faces, or another cut on the same axis.
@export var min_piece_size := 0.05
## The most a single saw may cut off, as a fraction of the board still attached along that cut's axis.
## 1 = no limit. Y cuts drop the top, X and Z cuts drop the smaller side, so below 0.5 the
## X and Z cuts have to sit close to one end of the board.
@export_range(0.01, 1.0, 0.01) var max_cut_fraction := 1.0

@export_group("Extra Paths")
## Additional paths built by generate_level(), after the first one. Each is a copy of `splitter`
## (its children, markers, roller root and board splitter) with its own seed-derived cuts,
## spacing and safe spots. All paths share the first path's room. 0 = only the first path.
@export var extra_path_count := 0
## How far along the world Z axis each extra path starts from the final point of the path before it.
## The first extra path is placed from the first path's final point, the next from that one's, and so on.
## Negative values go the other way.
@export var extra_path_z_offset := 3000.0
## Nodes the extra paths should NOT get a copy of (typically children of the path). A node listed
## here is left out together with everything under it, and the copies keep pointing at the original.
@export var skip_duplicating: Array[Node] = []
## Width of the opening in the wall between two neighbouring paths, centered where the first path
## ends and the next one begins. 0 = a solid wall.
@export var divider_opening_width := 600.0
## Height of that opening, measured from the floor. 0 = the opening goes all the way up.
@export var divider_opening_height := 0.0
## Also copy the board splitter's source_body for every extra path, moved along with the path.
## If off, the extra paths' splitters keep using the original source body.
@export var copy_source_body := true

@export_group("")
@export_tool_button("Generate Cuts") var cuts_action := generate_into_splitter
@export_tool_button("Generate Cuts + Splits + Markers") var all_action := generate_everything
@export_tool_button("Generate Level (random seed, with extra paths)") var level_action := generate_level


func _enter_tree() -> void:
	_tree = get_tree()


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
		var max_drop := max_cut_fraction * remaining.size[axis]
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


## Noise (-1..1) -> 0..1, with contrast, never reaching exactly 1.
func _unit(v: float) -> float:
	return clampf(v * noise_contrast * 0.5 + 0.5, 0.0, 0.9999)

## True if a Y or Z cut could still be placed in `remaining` (the same room test the cut placement uses).
## skip_axis is left out of the check (-1 = none).
func _can_cut_non_x(remaining: AABB, skip_axis: int) -> bool:
	if allow_y_cuts and skip_axis != SplitCut.Axis.Y \
			and remaining.size[SplitCut.Axis.Y] - 2.0 * min_piece_size > 0.0:
		return true
	if allow_z_cuts and skip_axis != SplitCut.Axis.Z \
			and remaining.size[SplitCut.Axis.Z] - 2.0 * min_piece_size > 0.0:
		return true
	return false

signal level_generated(level_seed: int)

## The seed the current level was built from. Pass it back to generate_level() to rebuild the same level.
var current_seed := 0


## Builds a whole level (cuts, split boards, markers, saws, room, plus any extra paths) from a seed.
## With no argument it picks a new random seed. Returns the seed used, or 0 on failure.
func generate_level(level_seed: int = 0) -> int:
	if splitter == null or noise == null:
		push_warning("NoiseSplitSequence: assign splitter and noise first.")
		return 0

	if level_seed == 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		level_seed = maxi(rng.randi(), 1)  # 0 means "pick one for me", so never use it as a seed

	# Copies from an earlier level go first (also when extra_path_count is now 0).
	_clear_extra_paths()

	# The seed drives both the cuts and the spacing between the path points.
	_apply_seed(level_seed)
	splitter.positioning_seed = level_seed

	if not generate_into_splitter():
		return 0
	splitter.generate_splits()
	splitter.create_split_markers()

	var extras := _build_extra_paths(level_seed)
	_apply_seed(level_seed)  # leave the noise on the level's own seed

	# One room for every path: refit the first path's walls, floor and ceiling around all of them,
	# with a divider wall (and an opening) between each pair of neighbouring paths.
	if not extras.is_empty():
		splitter.fit_room(extras, divider_opening_width, divider_opening_height)

	current_seed = level_seed
	level_generated.emit(level_seed)
	return level_seed


## Points the noise at a seed. FastNoiseLite has one; other Noise types move through the field instead.
func _apply_seed(s: int) -> void:
	if noise is FastNoiseLite:
		(noise as FastNoiseLite).seed = s
	else:
		sample_origin = Vector2(s % 100000, (s / 100000) % 100000)


## The seed of extra path number n (2 and up), derived from the level seed so the same level seed
## always rebuilds the same extra paths.
func _extra_seed(level_seed: int, n: int) -> int:
	return maxi(absi(("%d_path_%d" % [level_seed, n]).hash()), 1)


# --- Extra paths ---------------------------------------------------------------

func _build_extra_paths(level_seed: int) -> Array[BodySplitPath]:
	var built: Array[BodySplitPath] = []
	var previous := splitter
	for n in range(2, extra_path_count + 2):
		var path_seed := _extra_seed(level_seed, n)
		var path := _clone_path(splitter, n, previous)
		if path == null:
			return built

		_apply_seed(path_seed)
		path.positioning_seed = path_seed
		if not _generate_into(path):
			push_warning("NoiseSplitSequence: couldn't generate cuts for path %d; stopping." % n)
			return built
		path.generate_splits()
		path.create_split_markers()
		built.append(path)
		previous = path
	return built


## Copies `source` and everything it needs so it can be regenerated on its own, and places the
## copy so its start point is extra_path_offset away from the final point of `previous`.
## Copied: the path with all its children; and, when they sit outside the path, its markers node,
## roller root and board splitter (plus its output root and, optionally, source body).
## The room planes are not copied: every path shares the first path's room.
## Generated nodes are left out of the copies; everything else is kept.
func _clone_path(source: BodySplitPath, n: int, previous: BodySplitPath) -> BodySplitPath:
	if _tree == null or source.get_parent() == null:
		push_warning("NoiseSplitSequence: this node and the splitter must be in the scene tree to copy paths.")
		return null
	var scene_root := _tree.edited_scene_root if Engine.is_editor_hint() else null
	var copies := {}  # original node -> its copy, for every node duplicated here

	var path := _clone_subtree(source, n, copies, scene_root) as BodySplitPath

	# Place the copy: its first curve point lands on (previous final point + offset). Height is
	# left alone, because create_split_markers() pins every line to line_start_height anyway.
	var target := _final_point_global(previous) + Vector3(0.0, 0.0, extra_path_z_offset)
	var start_local := _start_point_local(path)
	var pos := target - path.global_transform.basis * start_local
	pos.y = source.global_position.y
	path.global_position = pos
	var delta := Vector3(pos.x - source.global_position.x, 0.0, pos.z - source.global_position.z)

	# Things that live outside the path's subtree get their own copies, moved by the same amount
	# so any non-generated children keep their place relative to the path.
	for prop: StringName in [&"board_splitter", &"split_gen", &"markers", &"roller_root"]:
		_copy_outside(source.get(prop) as Node, source, n, copies, scene_root, delta)

	for s: BoardSplitter in [source.board_splitter, source.split_gen]:
		if s == null:
			continue
		_copy_outside(s.output_root, source, n, copies, scene_root, delta)
		if copy_source_body:
			_copy_outside(s.source_body, source, n, copies, scene_root, delta)

	# Point every reference between copied nodes at the copies, so nothing in a copy still
	# touches (and clears) the first path's nodes.
	for c: Node in copies.values():
		if is_instance_valid(c):
			_remap_references(c, copies)
			if c is BoardSplitter:
				c.split_map = {}  # never share the original's split map
	# Collision layer 8 on the copies of the listed bodies (before anything is generated from them).
	for body in layer_8_on_copy:
		if body != null and copies.has(body):
			var body_copy := copies[body] as StaticBody3D
			if is_instance_valid(body_copy):
				body_copy.set_collision_layer_value(8, true)
				body_copy.process_mode = Node.PROCESS_MODE_ALWAYS
				body_copy.add_to_group(StringName("level_%d" % n), true)
	# The copy uses the first path's room. If the planes are children of the path they were
	# duplicated along with it, so remove those; then clear the references so the copy never
	# moves the shared planes when it generates.
	for prop: StringName in [&"floor_plane", &"ceiling", &"wall_front", &"wall_back", &"wall_left", &"wall_right"]:
		var original_plane := source.get(prop) as Node
		if original_plane != null and copies.has(original_plane):
			_free_now(copies[original_plane])
		path.set(prop, null)
	return path


func _is_skipped(node: Node) -> bool:
	for s in skip_duplicating:
		if s != null and is_instance_valid(s) and (s == node or s.is_ancestor_of(node)):
			return true
	return false


## Turns a level on or off by its number: level 1 is the first path, 2 and up are the extra paths.
## Only extra levels are managed here (they start disabled); the first path is left alone.
func set_level_enabled(level: int, enabled: bool) -> void:
	if level < 2 or _tree == null:
		return
	for n in _tree.get_nodes_in_group(EXTRA_GROUP):
		if is_instance_valid(n) and n.get_meta(LEVEL_META, 0) == level:
			n.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


func _copy_outside(orig: Node, source: BodySplitPath, n: int, copies: Dictionary, scene_root: Node, delta: Vector3) -> void:
	if orig == null or not is_instance_valid(orig) or copies.has(orig) or orig.get_parent() == null:
		return
	if _is_skipped(orig):
		return
	if orig.is_ancestor_of(source):
		push_warning("NoiseSplitSequence: '%s' contains the path, so it can't be copied separately; the copy shares it." % orig.name)
		return
	var copy := _clone_subtree(orig, n, copies, scene_root)
	if copy is Node3D:
		(copy as Node3D).global_position += delta


## Duplicates a node (with its children) next to the original, records every original -> copy
## pair in `copies`, and leaves out the nodes in skip_duplicating and the generated nodes.
## Everything is removed from the copy BEFORE it is added to the tree, so the skipped and
## generated nodes never enter the tree and their _ready() never runs.
func _clone_subtree(orig: Node, n: int, copies: Dictionary, scene_root: Node) -> Node:
	var copy := orig.duplicate()  # not in the tree yet
	copy.name = "%s_%02d" % [orig.name, n]

	# Pair every original node with its copy (relative paths work while the copy is off-tree).
	var pairs := {}
	pairs[orig] = copy
	for o: Node in orig.find_children("*", "", true, false):
		var c := copy.get_node_or_null(orig.get_path_to(o))
		if c != null:
			pairs[o] = c

	# Leave out the skipped nodes (and everything under them): the copies keep pointing at the originals.
	for o: Node in pairs.keys():
		if o != orig and _is_skipped(o):
			var skipped_copy: Node = pairs[o]
			if is_instance_valid(skipped_copy) and skipped_copy.get_parent() != null:
				_free_now(skipped_copy)
			pairs.erase(o)

	_strip_generated(copy)

	copy.add_to_group(EXTRA_GROUP, true)
	# Levels after the first start disabled. Everything under the copy (saws, split boards,
	# markers) inherits this. set_level_enabled() turns a level back on.
	copy.set_meta(LEVEL_META, n)
	copy.process_mode = Node.PROCESS_MODE_DISABLED

	# Only now does the copy enter the tree.
	orig.get_parent().add_child(copy)

	for o: Node in pairs:
		var c: Node = pairs[o]
		if not is_instance_valid(c) or not (c == copy or copy.is_ancestor_of(c)):
			continue  # removed above
		copies[o] = c
		# Same ownership as the original, so saved scenes keep the copy without flattening
		# instanced scenes into it.
		if scene_root and o.owner == scene_root:
			c.owner = scene_root
	return copy


## Removes everything the generators made (split markers, saws, areas, rollers, split boards).
func _strip_generated(root: Node) -> void:
	for n: Node in root.find_children("*", "", true, false):
		if not is_instance_valid(n) or n.get_parent() == null:
			continue
		if n.has_meta(BodySplitPath.MARKER_META) or n.has_meta(BoardSplitter.META_KEY):
			_free_now(n)


## Sets exported node references that point at an original (now copied) node to its copy.
func _remap_references(node: Node, copies: Dictionary) -> void:
	if node.get_script() == null:
		return
	for info in node.get_property_list():
		# Stored script variables only: this skips getter-only properties such as source_body.
		if info.type != TYPE_OBJECT:
			continue
		if not (info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (info.usage & PROPERTY_USAGE_STORAGE):
			continue
		var value:Variant = node.get(info.name)
		if value is Node and copies.has(value):
			node.set(info.name, copies[value])


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


func _final_point_global(path: Path3D) -> Vector3:
	return path.to_global(path.curve.get_point_position(path.curve.point_count - 1))


## Local position of the first curve point a path generates from (pre_curve's first point, or the origin).
func _start_point_local(path: BodySplitPath) -> Vector3:
	if path.pre_curve != null and path.pre_curve.point_count > 0:
		return path.pre_curve.get_point_position(0)
	return Vector3.ZERO
