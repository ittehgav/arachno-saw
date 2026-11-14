@tool
class_name NoiseSplitSequence
extends Node


## Smallest a falling piece may be, in meters. It only keeps a cut from sitting exactly on a face.
const MIN_FALLING_PIECE := 0.001

const EXTRA_GROUP := &"extra_path_copy"
const LEVEL_META := &"level_number"
const LAYER8_META := &"layer8_copy"

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

## The most a single saw may cut off, as a fraction of the board still attached along that cut's axis.
## 1 = no limit. Y cuts drop the top, X and Z cuts drop the smaller side, so below 0.5 the
## X and Z cuts have to sit close to one end of the board.
@export_range(0.01, 1.0, 0.01) var max_cut_fraction := 1.0

@export_group("Levels")
## Stop building new levels after this many (the first path counts). 0 = endless.
@export var max_levels := 0
## How far along world Z each new path starts from the final point of the path it was copied from.
@export var extra_path_z_offset := 3000.0
## Nodes the copies should NOT get a copy of (with everything under them). Copies keep pointing at the originals.
@export var skip_duplicating: Array[Node] = []
## Bodies that get collision layer 8 turned on in their copies.
@export var layer_8_on_copy: Array[StaticBody3D] = []
## Also copy the board splitter's source_body, moved along with the path.
@export var copy_source_body := true

@export_group("buttons")
@export_tool_button("Generate Cuts") var cuts_action := generate_into_splitter
@export_tool_button("Generate Cuts + Splits + Markers") var all_action := generate_everything
@export_tool_button("Generate Level (random seed, with extra paths)") var level_action := generate_level



func _enter_tree() -> void:
	_tree = get_tree()


func _ready() -> void:
	if Engine.is_editor_hint() or splitter == null:
		return
	paths = [splitter]


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
	
	_apply_seed(level_seed)
	splitter.positioning_seed = level_seed

	_clear_extra_paths()
	paths = [splitter]

	if not generate_into_splitter():
		return 0
	splitter.generate_splits()
	splitter.create_split_markers()

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


# --- Levels --------------------------------------------------------------------

func _watch(path: BodySplitPath) -> void:
	path.stage_started.connect(_on_stage_started.bind(path))


## A path started: free the one before it, then build the next one as a copy of this one.
func _on_stage_started(path: BodySplitPath=splitter) -> void:
	var idx := paths.find(path)
	if idx < 0:
		return
	if idx > 0 and paths[idx - 1] != null:
		_free_path(idx - 1)
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
	var n := paths.size() + 1  # level number, also the copy's name suffix
	var path := _clone_path(from, n)
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

	# Grow the first path's room around every path that still exists.
	var live: Array[BodySplitPath] = []
	for p in paths:
		if p != null and is_instance_valid(p) and p != splitter:
			live.append(p)
	splitter.fit_room(live, true)
	return path


## Frees the path in slot `index` with all its copied nodes. The first path's nodes belong to the
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


## Turns a level on or off by its number. Level 1 is the first path and is left alone.
func set_level_enabled(level: int, enabled: bool) -> void:
	if level < 2 or _tree == null:
		return
	for n in _tree.get_nodes_in_group(EXTRA_GROUP):
		if is_instance_valid(n) and n.get_meta(LEVEL_META, 0) == level:
			n.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED


## Copies `source` (the path that just started) and what it needs to be regenerated on its own, and
## places the copy extra_path_z_offset along world Z from source's final point. The copy starts disabled.
func _clone_path(source: BodySplitPath, n: int) -> BodySplitPath:
	if _tree == null or source.get_parent() == null:
		push_warning("NoiseSplitSequence: this node and the splitter must be in the scene tree to copy paths.")
		return null
	var copies := {}  # original node -> its copy
	var path := _clone_subtree(source, n, copies) as BodySplitPath

	var target := _final_point_global(source) + Vector3(0.0, 0.0, extra_path_z_offset)
	var start_local := _start_point_local(path)
	var pos := target - path.global_transform.basis * start_local
	var base := source.global_position
	pos.y = base.y
	path.global_position = pos
	var delta := Vector3(pos.x - base.x, 0.0, pos.z - base.z)

	for prop: StringName in [&"board_splitter", &"split_gen", &"markers", &"roller_root"]:
		_copy_outside(source.get(prop) as Node, source, n, copies, delta)
	for s: BoardSplitter in [source.board_splitter, source.split_gen]:
		if s == null:
			continue
		_copy_outside(s.output_root, source, n, copies, delta)
		if copy_source_body:
			_copy_outside(s.source_body, source, n, copies, delta)

	for c: Node in copies.values():
		if is_instance_valid(c):
			_remap_references(c, copies)
			if c is BoardSplitter:
				c.split_map = {}
	_remap_connections(copies)

	for body in layer_8_on_copy:
		if body != null and copies.has(body):
			var body_copy := copies[body] as StaticBody3D
			if is_instance_valid(body_copy):
				body_copy.set_collision_layer_value(8, true)
				body_copy.process_mode = Node.PROCESS_MODE_ALWAYS
				body_copy.set_meta(LAYER8_META, true)
	# A copy of a copy carries the meta and the old level group over: move it to this level's group.
	for c: Node in copies.values():
		if is_instance_valid(c) and c.has_meta(LAYER8_META):
			for g in c.get_groups():
				if String(g).begins_with("level_"):
					c.remove_from_group(g)
			c.add_to_group(StringName("level_%d" % n))

	# The copy uses the first path's room, so it gets no planes of its own.
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


func _copy_outside(orig: Node, source: BodySplitPath, n: int, copies: Dictionary, delta: Vector3) -> void:
	if orig == null or not is_instance_valid(orig) or copies.has(orig) or orig.get_parent() == null:
		return
	if _is_skipped(orig):
		return
	if orig.is_ancestor_of(source):
		push_warning("NoiseSplitSequence: '%s' contains the path, so it can't be copied separately; the copy shares it." % orig.name)
		return
	var copy := _clone_subtree(orig, n, copies)
	if copy is Node3D:
		(copy as Node3D).global_position += delta


## "Path_02" -> "Path", so a copy of a copy is named Path_03 and not Path_02_03.
func _base_name(node: Node) -> String:
	var s := String(node.name)
	if node.has_meta(LEVEL_META):
		return s.rsplit("_", true, 1)[0]
	return s


## Duplicates a node (with children) next to the original and records every original -> copy pair.
## Skipped and generated nodes are removed BEFORE the copy enters the tree, so their _ready() never runs.
func _clone_subtree(orig: Node, n: int, copies: Dictionary) -> Node:
	var copy := orig.duplicate()  # not in the tree yet
	copy.name = "%s_%02d" % [_base_name(orig), n]

	var pairs := {orig: copy}
	for o: Node in orig.find_children("*", "", true, false):
		var c := copy.get_node_or_null(orig.get_path_to(o))
		if c != null:
			pairs[o] = c

	for o: Node in pairs.keys():
		if o != orig and _is_skipped(o):
			var skipped_copy: Node = pairs[o]
			if is_instance_valid(skipped_copy) and skipped_copy.get_parent() != null:
				_free_now(skipped_copy)
			pairs.erase(o)

	_strip_generated(copy)

	copy.add_to_group(EXTRA_GROUP)
	copy.set_meta(LEVEL_META, n)
	copy.process_mode = Node.PROCESS_MODE_DISABLED  # set_level_enabled() / start_level() turn it on
	if copy is Node3D:
		(copy as Node3D).visible = true
	orig.get_parent().add_child(copy)

	for o: Node in pairs:
		var c: Node = pairs[o]
		if is_instance_valid(c) and (c == copy or copy.is_ancestor_of(c)):
			copies[o] = c
	return copy


## Removes everything the generators made (split markers, saws, areas, rollers, split boards).
func _strip_generated(root: Node) -> void:
	for n: Node in root.find_children("*", "", true, false):
		if not is_instance_valid(n) or n.get_parent() == null:
			continue
		if n.has_meta(BodySplitPath.MARKER_META) or n.has_meta(BoardSplitter.META_KEY) or \
			n.is_in_group(BodySplitPath.SPAWNED_GROUP):
			_free_now(n)


## Sets exported node references that point at an original (now copied) node to its copy.
func _remap_references(node: Node, copies: Dictionary) -> void:
	if node.get_script() == null:
		return
	for info in node.get_property_list():
		if info.type != TYPE_OBJECT:
			continue
		if not (info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (info.usage & PROPERTY_USAGE_STORAGE):
			continue
		var value: Variant = node.get(info.name)
		if value is Node and copies.has(value):
			node.set(info.name, copies[value])


## Gives every copied node the signal connections of its original, aimed at the copy of the target
## when the target was copied too, and at the original target when it wasn't.
func _remap_connections(copies: Dictionary) -> void:
	var scene: Node = _tree.edited_scene_root if Engine.is_editor_hint() else _tree.current_scene
	if scene != null and scene != self and not scene.is_ancestor_of(self):
		scene = null
	for o: Node in copies:
		var c: Node = copies[o]
		if not is_instance_valid(o) or not is_instance_valid(c):
			continue
		for sig in o.get_signal_list():
			var sig_name: StringName = sig.name
			for conn in o.get_signal_connection_list(sig_name):
				var callable: Callable = conn.callable
				if callable.is_custom():
					continue  # lambdas and bound callables (including the stage_started watch) are left alone
				var target := callable.get_object() as Node
				if target == null:
					continue
				if not (copies.has(target) or _is_skipped(target) or _in_level_tree(target, scene)):
					continue
				var method := callable.get_method()
				var new_target: Node = copies.get(target, target)
				if new_target != target and c.is_connected(sig_name, Callable(target, method)):
					c.disconnect(sig_name, Callable(target, method))
				var new_callable := Callable(new_target, method)
				if is_instance_valid(new_target) and not c.is_connected(sig_name, new_callable):
					var err := c.connect(sig_name, new_callable, conn.flags)
					if err != OK:
						push_warning("NoiseSplitSequence: couldn't connect %s.%s to %s.%s (error %d)." % [
								c.name, sig_name, new_target.name, method, err])


func _in_level_tree(node: Node, scene: Node) -> bool:
	if not node.is_inside_tree():
		return false
	return scene == null or node == scene or scene.is_ancestor_of(node)


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


func _final_point_global(path: Path3D) -> Vector3:
	return path.to_global(path.curve.get_point_position(path.curve.point_count - 1))


## Local position of the first curve point a path generates from (pre_curve's first point, or the origin).
func _start_point_local(path: BodySplitPath) -> Vector3:
	if path.pre_curve != null and path.pre_curve.point_count > 0:
		return path.pre_curve.get_point_position(0)
	return Vector3.ZERO
