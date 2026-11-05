@tool
class_name NoiseSplitSequence
extends Node

## Group the generated extra-path copies are put in (persistent, so they survive saving the scene).
const EXTRA_GROUP := &"extra_path_copy"

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

## Minimum distance (meters) between a cut and the board's faces, or another cut on the same axis.
@export var min_piece_size := 0.05

@export_group("Extra Paths")
## Additional paths built by generate_level(), after the first one. Each is a copy of `splitter`
## (its children, markers, roller root, board splitter and room planes) with its own seed-derived
## cuts, spacing and safe spots. 0 = only the first path.
@export var extra_path_count := 0
## Where each extra path starts, relative to the final point of the path before it (world axes).
## The first extra path is placed from the first path's final point, the next from that one's, and so on.
## The Y part has no effect: every line is kept at its line_start_height above the floor.
@export var extra_path_offset := Vector3(0.0, 0.0, -3000.0)
## Also copy the board splitter's source_body for every extra path, moved along with the path.
## If off, the extra paths' splitters keep using the original source body.
@export var copy_source_body := true

@export_group("")
@export_tool_button("Generate Cuts") var cuts_action := generate_into_splitter
@export_tool_button("Generate Cuts + Splits + Markers") var all_action := generate_everything
@export_tool_button("Generate Level (random seed, with extra paths)") var level_action := generate_level


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
	while result.size() < cut_count and sample < max_samples:
		var t := sample_origin.x + sample * noise_step
		sample += 1  # a rejected sample still moves on, so the sequence can't get stuck

		# Axes this cut may use: every enabled one, minus the previous cut's if repeats are off.
		var candidates: Array[int] = []
		for a in axes:
			if not (no_repeat_axis and a == last_axis):
				candidates.append(a)
		if candidates.is_empty():
			push_warning("NoiseSplitSequence: no_repeat_axis needs at least two enabled axes.")
			break

		var pick := _unit(noise.get_noise_2d(t, sample_origin.y))
		var axis: int = candidates[mini(int(pick * candidates.size()), candidates.size() - 1)]

		var lo := remaining.position[axis] + min_piece_size
		var hi := remaining.end[axis] - min_piece_size
		if hi <= lo:
			continue  # what's left is too thin on this axis to cut
		var offset := lerpf(lo, hi, _unit(noise.get_noise_2d(t, sample_origin.y + 1000.0)))
		var drop_negative := _unit(noise.get_noise_2d(t, sample_origin.y + 2000.0)) < 0.5
		if axis == SplitCut.Axis.Y:
			drop_negative = false  # Y cuts only ever drop the top (+Y) part
		var cut := SplitCut.new()
		cut.axis = axis as SplitCut.Axis
		cut.offset = offset
		cut.drop_side = SplitCut.DropSide.NEGATIVE_SIDE if drop_negative else SplitCut.DropSide.POSITIVE_SIDE
		last_axis = axis
		result.append(cut)

		# Keep only the side that stays attached.
		var pos := remaining.position
		var size := remaining.size
		if cut.drops(true):
			pos[axis] = offset
			size[axis] = remaining.end[axis] - offset
		else:
			size[axis] = offset - remaining.position[axis]
		remaining = AABB(pos, size)

	if result.size() < cut_count:
		push_warning("NoiseSplitSequence: only %d of %d cuts fit; lower min_piece_size or cut_count." % [result.size(), cut_count])
	return result


## Noise (-1..1) -> 0..1, with contrast, never reaching exactly 1.
func _unit(v: float) -> float:
	return clampf(v * noise_contrast * 0.5 + 0.5, 0.0, 0.9999)

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

	_build_extra_paths(level_seed)
	_apply_seed(level_seed)  # leave the noise on the level's own seed

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

func _build_extra_paths(level_seed: int) -> void:
	var previous := splitter
	for n in range(2, extra_path_count + 2):
		var path_seed := _extra_seed(level_seed, n)
		var path := _clone_path(splitter, n, previous)
		if path == null:
			return

		_apply_seed(path_seed)
		path.positioning_seed = path_seed
		if not _generate_into(path):
			push_warning("NoiseSplitSequence: couldn't generate cuts for path %d; stopping." % n)
			return
		path.generate_splits()
		path.create_split_markers()
		previous = path


## Copies `source` and everything it needs so it can be regenerated on its own, and places the
## copy so its start point is extra_path_offset away from the final point of `previous`.
## Copied: the path with all its children; and, when they sit outside the path, its markers node,
## roller root, board splitter (plus its output root and, optionally, source body) and the room
## planes. Generated nodes are left out of the copies; everything else is kept.
func _clone_path(source: BodySplitPath, n: int, previous: BodySplitPath) -> BodySplitPath:
	if source.get_parent() == null:
		push_warning("NoiseSplitSequence: the splitter must be in the scene tree to be copied.")
		return null
	var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else null
	var copies := {}  # original node -> its copy, for every node duplicated here

	var path := _clone_subtree(source, n, copies, scene_root) as BodySplitPath

	# Place the copy: its first curve point lands on (previous final point + offset). Height is
	# left alone, because create_split_markers() pins every line to line_start_height anyway.
	var target := _final_point_global(previous) + extra_path_offset
	var start_local := _start_point_local(path)
	var pos := target - path.global_transform.basis * start_local
	pos.y = source.global_position.y
	path.global_position = pos
	var delta := Vector3(pos.x - source.global_position.x, 0.0, pos.z - source.global_position.z)

	# Things that live outside the path's subtree get their own copies, moved by the same amount
	# so any non-generated children keep their place relative to the path.
	for prop: StringName in [&"board_splitter", &"split_gen", &"markers", &"roller_root",
			&"floor_plane", &"ceiling", &"wall_front", &"wall_back", &"wall_left", &"wall_right"]:
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
	return path


func _copy_outside(orig: Node, source: BodySplitPath, n: int, copies: Dictionary, scene_root: Node, delta: Vector3) -> void:
	if orig == null or not is_instance_valid(orig) or copies.has(orig) or orig.get_parent() == null:
		return
	if orig.is_ancestor_of(source):
		push_warning("NoiseSplitSequence: '%s' contains the path, so it can't be copied separately; the copy shares it." % orig.name)
		return
	var copy := _clone_subtree(orig, n, copies, scene_root)
	if copy is Node3D:
		(copy as Node3D).global_position += delta


## Duplicates a node (with its children) next to the original, records every original -> copy
## pair in `copies`, and removes the generated nodes from the copy.
func _clone_subtree(orig: Node, n: int, copies: Dictionary, scene_root: Node) -> Node:
	var copy := orig.duplicate()
	copy.name = "%s_%02d" % [orig.name, n]
	orig.get_parent().add_child(copy)
	copies[orig] = copy
	if scene_root and orig.owner == scene_root:
		copy.owner = scene_root

	for o: Node in orig.find_children("*", "", true, false):
		var c := copy.get_node_or_null(orig.get_path_to(o))
		if c == null:
			continue
		copies[o] = c
		# Same ownership as the original, so saved scenes keep the copy without flattening
		# instanced scenes into it.
		if scene_root and o.owner == scene_root:
			c.owner = scene_root

	_strip_generated(copy)
	copy.add_to_group(EXTRA_GROUP, true)
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
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(EXTRA_GROUP):
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
