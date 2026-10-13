extends CharacterBody3D
class_name Crawler;

signal fly_consumed(fly:Fly)
signal died(source:DeathType)
signal shield_lost;

enum DeathType{
	saw,
	board,
	skull
}

const HOVER_DIST := 0.5     # center-to-surface distance at rest (e.g. your sphere/capsule radius)
const SNAP_RANGE := 1.0     # how far straight "down" we look first
const SEARCH_RANGE := 2.0   # how far the wide search looks if that misses

var last_valid_transform: Transform3D

const SPEED := 50.0
const TURN_SPEED := 2.5      # radians per second
const STICK_SPEED := 15.0      # how hard it's pulled into the surface (replaces gravity)
const ALIGN_SPEED := 15.0     # how quickly the body rotates to the new surface
const PROBE_LENGTH := 5
	 # must be a bit more than center-to-surface distance
var bonus_speed:float = 0;
var speed:float:
	get():
		return SPEED + bonus_speed;
var surface_normal := Vector3.UP;

@export var pcam:PhantomCamera3D
@export var body:Spider

@export var death_sfx:AudioStreamPlayer

@export var blink_animation:AnimationPlayer;
@export var cheat_death_sfx:AudioStreamPlayer;

@export var buff_glow_mesh:MeshInstance3D
@export var buff_glow_animation:AnimationPlayer

var moving:bool=false;

var has_shield:bool=false;
func _enter_tree() -> void:
	GLB.spider = self;

func _ready()->void:
	last_valid_transform = global_transform

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
	# 5. Hard guarantee: always end the frame glued to a surface.
	if _snap_to_surface():
		last_valid_transform = global_transform
	else:
		# Lost every surface: undo this frame's move instead of flying off.
		global_transform = last_valid_transform
		velocity = Vector3.ZERO
func _snap_to_surface() -> bool:
	var origin := global_position

	# Prefer the surface directly beneath us (stable, avoids jitter at edges).
	var hit := _raycast(origin, origin - surface_normal * SNAP_RANGE)

	# Otherwise search in a cone/ring of directions for the nearest surface.
	if hit.is_empty():
		hit = _find_nearest_surface()
	if hit.is_empty():
		return false

	surface_normal = hit.normal
	global_position = hit.position + hit.normal * HOVER_DIST
	return true


func _find_nearest_surface() -> Dictionary:
	var origin := global_position
	var down := -surface_normal
	var best := {}
	var best_dist := INF

	for tilt:float in [PI / 4.0, PI / 2.0, PI * 0.75]:
		for i in 8:
			var a := TAU * i / 8.0
			var tangent := global_basis.x * cos(a) + global_basis.z * sin(a)
			var dir := (down * cos(tilt) + tangent * sin(tilt)).normalized()
			var hit := _raycast(origin, origin + dir * SEARCH_RANGE)
			if hit:
				var d := origin.distance_to(hit.position)
				if d < best_dist:
					best_dist = d
					best = hit

	# Also try straight down at the full search range.
	var straight := _raycast(origin, origin + down * SEARCH_RANGE)
	if straight and origin.distance_to(straight.position) < best_dist:
		best = straight

	return best

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
	## easier than to keep the board var around until
	## death prevention is checked
	if not has_shield: 
		reparent(board);
		set_physics_process(false)
	die(DeathType.board)

func _on_collision_scan_area_entered(area: Area3D) -> void:
	if area is Saw:
		die(DeathType.saw);
	elif area is Fly:
		fly_consumed.emit(area)
		area.apply_effect(self)

func die(source:DeathType)->void:
	if has_shield:
		has_shield = false;
		cheat_death(source)
		shield_lost.emit()
		return;
	set_physics_process (false)
	death_sfx.play()
	died.emit(source)

func cheat_death(type:DeathType)->void:
	cheat_death_sfx.play()
	blink_animation.play("blink");
	match type:
		DeathType.saw:
			tp_to_safe_board();
		DeathType.board:
			tp_to_safe_board();
		
func tp_to_safe_board()->void:
	var safe_boards:Array = GLB.board_container.safe_boards;
	var target_transform:Variant = GLB.board_container.get_free_face_transform(safe_boards, 5)
	while not target_transform:
		target_transform = GLB.board_container.get_free_face_transform(safe_boards, 5);
		
	global_transform = target_transform
	
func _on_fly_consumed(fly: Fly) -> void:
	## should never overlap animations?
	var m:StandardMaterial3D = buff_glow_mesh.mesh.material;
	var color:Color = Fly.buff_colors[fly.type];
	m.albedo_color = color
	m.emission = color;
	buff_glow_animation.play("buff_glow")
