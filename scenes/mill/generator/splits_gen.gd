@tool
class_name NoiseSplitSequence
extends Node

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

@export_group("")
@export_tool_button("Generate Cuts") var cuts_action := generate_into_splitter
@export_tool_button("Generate Cuts + Splits + Markers") var all_action := generate_everything


## Builds the cut sequence and puts it on the splitter. Returns false if nothing was generated.
func generate_into_splitter() -> bool:
	if splitter == null or noise == null:
		push_warning("NoiseSplitSequence: assign splitter and noise first.")
		return false
	var result := generate_cuts()
	if result.is_empty():
		return false
	splitter.cuts = result
	splitter.notify_property_list_changed()
	return true


func generate_everything() -> void:
	if generate_into_splitter():
		splitter.generate_splits()
		splitter.create_split_markers()


## The cut sequence for the current settings. Same settings always give the same sequence.
func generate_cuts() -> Array[SplitCut]:
	var result: Array[SplitCut] = []
	if splitter == null or noise == null:
		return result

	var bounds := splitter.get_board_bounds()
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

	# The seed drives both the cuts and the spacing between the path points.
	if noise is FastNoiseLite:
		(noise as FastNoiseLite).seed = level_seed
	else:
		# Other Noise types have no seed property, so move through the field instead.
		sample_origin = Vector2(level_seed % 100000, (level_seed / 100000) % 100000)
	splitter.positioning_seed = level_seed

	if not generate_into_splitter():
		return 0
	splitter.generate_splits()
	splitter.create_split_markers()

	current_seed = level_seed
	level_generated.emit(level_seed)
	return level_seed
