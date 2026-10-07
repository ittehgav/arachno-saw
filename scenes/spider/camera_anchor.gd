extends Node3D
class_name CrawlerFollower

@export var crawler:Crawler;
@export var pcam:PhantomCamera3D;

func _physics_process(delta: float) -> void:
	## just a different script for camera control
	## that  doesnt override the addon class
	damped_look_at(pcam, crawler.global_position, crawler.global_basis.y, 5, delta)
	
## Tracks the last quaternion per node, so the double-cover guard works
## correctly even when this function is called for multiple different nodes.
var _damped_look_last_quat: Dictionary = {}


## Smoothly rotates `node` to face `look_target`, instead of snapping like
## look_at() does. Call this every physics frame with the same node/delta.
##   node          - the Node3D to rotate
##   look_target   - world-space position to look at
##   up            - up vector to use for the look-at orientation
##   damping_speed - higher = snappier, lower = slower/floatier turn
##   delta         - physics delta (pass from _physics_process)
func damped_look_at(node: Node3D, look_target: Vector3, up: Vector3, damping_speed: float, delta: float) -> void:
	var to_target: Vector3 = look_target - node.global_position
	if to_target.length_squared() < 0.0001:
		return

	var target_basis: Basis = Basis.looking_at(to_target.normalized(), up)
	var target_quat: Quaternion = target_basis.get_rotation_quaternion()
	var current_quat: Quaternion = node.global_transform.basis.get_rotation_quaternion()

	# Guard against quaternion double-cover flips (same rotation, opposite sign),
	# which otherwise show up as a sudden ~180-degree internal snap.
	if target_quat.dot(current_quat) < 0.0:
		target_quat = -target_quat

	var t: float = 1.0 - exp(-damping_speed * delta)
	var smoothed_quat: Quaternion = current_quat.slerp(target_quat, t)

	var trans: Transform3D = node.global_transform
	trans.basis = Basis(smoothed_quat)
	node.global_transform = trans


@export var you_died_screen:Control;
@export var you_died_message:Label
func _on_spider_died(source:String) -> void:
	pcam.follow_mode = PhantomCamera3D.FollowMode.NONE;
	pcam.look_at_mode = PhantomCamera3D.LookAtMode.NONE;
	
	match source:
		"saw":
			you_died_message.text = "Touching active circular saws might be a bad idea."
		"falling_board":
			you_died_message.text = "Boards always fall spider-side-down."
	
	you_died_screen.modulate.a = 0;
	you_died_screen.show()
	var t:= create_tween();
	t.tween_property(you_died_screen, "modulate:a", 1, 1);
	t.parallel().tween_property(pcam, "fov", pcam.fov + 30, 1)
	
