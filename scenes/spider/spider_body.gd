extends CharacterBody3D
class_name Crawler;

signal died(source:String)

const SPEED := 50.0
const TURN_SPEED := 2.5      # radians per second
const STICK_SPEED := 15.0      # how hard it's pulled into the surface (replaces gravity)
const ALIGN_SPEED := 15.0     # how quickly the body rotates to the new surface
const PROBE_LENGTH := 1
	 # must be a bit more than center-to-surface distance
var bonus_speed:float = 0;
var speed:float:
	get():
		return SPEED + bonus_speed;
var surface_normal := Vector3.UP;

@export var pcam:PhantomCamera3D
@export var walk_dust:CPUParticles3D
@export var body:Spider

func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING

var moving:bool=false:
	set(val):
		
		if moving != val:
			if val:
				walk_dust.emitting = true;
			else:
				walk_dust.emitting = false
		
		moving = val

func _physics_process(delta: float) -> void:
	# Left/right turn the body around its own up axis (works on any surface).
	var turn := Input.get_axis("move_right", "move_left")
	rotate_object_local(Vector3.UP, turn * TURN_SPEED * delta)

	# Up/down move forward/back along the body's facing direction.
	var forward_input := Input.get_axis("move_forward", "move_back")
	var direction := (global_basis * Vector3(0, 0, forward_input))
	direction = direction.slide(surface_normal).normalized()

	# 1. Find the surface we should be stuck to.
	var found := _find_surface_normal(direction)
	if found != Vector3.ZERO:
		surface_normal = found

	# 2. Rotate the body so its up axis matches the surface.
	_align_to_surface(delta)

	# 3. Move along the surface, pulled into it instead of by gravity.
	var tangent_velocity := velocity.slide(surface_normal)
	if direction:
		tangent_velocity = direction * speed
	else:
		tangent_velocity = tangent_velocity.move_toward(Vector3.ZERO, speed)

	velocity = tangent_velocity - surface_normal * STICK_SPEED
	move_and_slide()

	# 4. Concave corners: climb onto surfaces we bump into at a steep angle.
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.dot(surface_normal) < 0.7:
			surface_normal = n
			break
	moving = abs(velocity.x) > 1


func _find_surface_normal(move_dir: Vector3) -> Vector3:
	var origin := global_position

	var hit := _raycast(origin, origin - surface_normal * PROBE_LENGTH)
	if hit:
		return hit.normal

	# Convex edge: wrap around the face we're walking off of.
	if move_dir != Vector3.ZERO:
		var from := origin + move_dir * PROBE_LENGTH - surface_normal * PROBE_LENGTH
		var to := origin - move_dir * PROBE_LENGTH - surface_normal * PROBE_LENGTH
		hit = _raycast(from, to)
		if hit:
			return hit.normal

	return Vector3.ZERO


func _align_to_surface(delta: float) -> void:
	var q := Quaternion(global_basis.y, surface_normal)
	var t := 1.0 - exp(-ALIGN_SPEED * delta)
	q = Quaternion.IDENTITY.slerp(q, t)
	global_basis = (Basis(q) * global_basis).orthonormalized()



func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

const shaking_amp = 5;
func _on_board_container_saw_touched(_saw: Saw) -> void:
	pcam.noise.amplitude = shaking_amp
	pcam.noise.frequency = 50 ## editor thingy only goes to 10 

func _on_board_container_saw_left(_saw: Saw) -> void:
	pcam.noise.amplitude = 0;

func board_death(board:StaticBody3D)->void:
	reparent(board);
	set_physics_process(false)
	die("falling_board")

func _on_collision_scan_area_entered(area: Area3D) -> void:
	if area is Saw:
		die("saw");
	elif area is Fly:
		area.apply_effect(self)

func die(source:String)->void:
	died.emit(source)
