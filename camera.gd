extends Camera3D
class_name InsectFollowCamera

@export var you_died_screen:Control;

## The node to follow (your InsectCrawler).
@export var target: Node3D

## Camera position relative to the target, in the target's local space.
@export var offset: Vector3 = Vector3(0.0, 1.5, 3.0)

## Where the camera looks, relative to the target, in the target's local space.
@export var look_at_offset: Vector3 = Vector3(0.0, 0.3, 0.0)

## Position smoothing. Higher = tighter follow, lower = floatier.
@export var position_follow_speed: float = 6.0

## Orientation smoothing. Lower values give a slower, gentler swing.
@export var rotation_follow_speed: float = 4.0

## How much the FOV widens (in degrees) when the insect dies.
@export var death_fov_increase: float = 15.0

## How quickly the FOV eases into its widened value.
@export var death_fov_speed: float = 3.0

@export_group("Shake")
## Positional shake amplitude, in meters.
@export var shake_position_amplitude: float = 0.15

## Rotational shake amplitude, in degrees.
@export var shake_rotation_amplitude: float = 4.0

## How fast the shake noise is sampled; higher = jittery, lower = rolling.
@export var shake_frequency: float = 18.0

var _smoothed_rotation: Quaternion = Quaternion.IDENTITY
var _is_following: bool = true
var _base_fov: float
var _target_fov: float

var _is_shaking: bool = false
var _shake_time: float = 0.0
var _shake_noise: FastNoiseLite


func _ready() -> void:
	top_level = true
	_base_fov = fov
	_target_fov = fov

	_shake_noise = FastNoiseLite.new()
	_shake_noise.seed = randi()
	_shake_noise.frequency = 1.0 # we drive it manually via shake_frequency * time

	if target == null:
		push_warning("InsectFollowCamera: no target assigned.")
		set_physics_process(false)
		return

	_smoothed_rotation = _get_target_rotation()
	var smoothed_basis: Basis = Basis(_smoothed_rotation)
	global_position = target.global_position + smoothed_basis * offset
	look_at(target.global_position + smoothed_basis * look_at_offset, smoothed_basis.y)


func _physics_process(delta: float) -> void:
	if _is_following and target != null:
		_follow_target(delta)

	var fov_t: float = 1.0 - exp(-death_fov_speed * delta)
	fov = lerp(fov, _target_fov, fov_t)

	if _is_shaking:
		_apply_shake(delta)


## Moves and orients the camera toward its smoothed follow position/rotation.
func _follow_target(delta: float) -> void:
	var pos_t: float = 1.0 - exp(-position_follow_speed * delta)
	var rot_t: float = 1.0 - exp(-rotation_follow_speed * delta)

	_smoothed_rotation = _smoothed_rotation.slerp(_get_target_rotation(), rot_t).normalized()
	var smoothed_basis: Basis = Basis(_smoothed_rotation)

	var desired_pos: Vector3 = target.global_position + smoothed_basis * offset
	global_position = global_position.lerp(desired_pos, pos_t)

	var look_target: Vector3 = target.global_position + smoothed_basis * look_at_offset
	if not global_position.is_equal_approx(look_target):
		look_at(look_target, smoothed_basis.y)


func _get_target_rotation() -> Quaternion:
	return target.global_transform.basis.orthonormalized().get_rotation_quaternion()


## Call this when the insect dies. Unlocks the camera from the target
## and slightly zooms the FOV out.
func _on_insect_died() -> void:
	_is_following = false
	_target_fov = _base_fov + death_fov_increase


# ---------------------------------------------------------------------------
# Shake VFX
# ---------------------------------------------------------------------------

func _on_saw_board_touched()->void:
	start_shake()
func _on_saw_board_left() -> void:
	stop_shake()
## Starts continuous camera shake. Call again with different amplitudes
## (set shake_position_amplitude / shake_rotation_amplitude first) to change
## intensity on the fly without stopping.
func start_shake() -> void:
	_is_shaking = true


## Stops the shake and immediately clears any residual offset, so the
## camera snaps back to its true follow position instead of freezing
## mid-shake.
func stop_shake() -> void:
	_is_shaking = false
	_shake_time = 0.0


## Samples noise and applies a small offset/rotation on top of wherever
## _follow_target (or the frozen post-death transform) left the camera
## this frame. Applied last, so it composites correctly in both states.
func _apply_shake(delta: float) -> void:
	_shake_time += delta * shake_frequency

	var nx: float = _shake_noise.get_noise_2d(_shake_time, 0.0)
	var ny: float = _shake_noise.get_noise_2d(_shake_time, 100.0)
	var nz: float = _shake_noise.get_noise_2d(_shake_time, 200.0)
	var nrx: float = _shake_noise.get_noise_2d(_shake_time, 300.0)
	var nry: float = _shake_noise.get_noise_2d(_shake_time, 400.0)
	var nrz: float = _shake_noise.get_noise_2d(_shake_time, 500.0)

	var shake_offset: Vector3 = Vector3(nx, ny, nz) * shake_position_amplitude
	var shake_rotation: Vector3 = Vector3(
		deg_to_rad(nrx * shake_rotation_amplitude),
		deg_to_rad(nry * shake_rotation_amplitude),
		deg_to_rad(nrz * shake_rotation_amplitude)
	)

	global_position += global_transform.basis * shake_offset

	var shake_basis: Basis = Basis.from_euler(shake_rotation)
	global_transform.basis = (global_transform.basis * shake_basis).orthonormalized()


func _on_inscet_died() -> void:
	_is_following = false
	_target_fov = _base_fov + death_fov_increase
	you_died_screen.show();
