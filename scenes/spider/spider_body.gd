extends CharacterBody3D
class_name Crawler;

signal fly_consumed(fly:Fly)
signal died(source:DeathType)
signal shield_lost;

signal run_won;

enum DeathType{
	saw,
	board,
	skull
}
@export var pcam:PhantomCamera3D
@export var body:Spider

@export var death_sfx:AudioStreamPlayer

@export var blink_animation:AnimationPlayer;
@export var cheat_death_sfx:AudioStreamPlayer;

@export var buff_glow_mesh:MeshInstance3D
@export var buff_glow_animation:AnimationPlayer

var moving:bool=false;
## bc board deaths can be async and on drop board i need to know
## its alive in order to win the run
var dead:bool=false;

var has_shield:bool=false;
func _enter_tree() -> void:
	GLB.spider = self;

const HOVER_DIST := 0.5     # center-to-surface distance at rest (e.g. your sphere/capsule radius)
const SNAP_RANGE := 5.0     # how far straight "down" we look first
const SEARCH_RANGE := 5.0   # how far the wide search looks if that misses

var last_valid_transform: Transform3D

var SPEED: = 70.0;
const TURN_SPEED := 5     # radians per second
const STICK_SPEED := 15.0      # how hard it's pulled into the surface (replaces gravity)
const ALIGN_SPEED := 15.0     # how quickly the body rotates to the new surface
const PROBE_LENGTH := 5
	 # must be a bit more than center-to-surface distance

const TELEPORT_SEARCH_RANGE := 10000.0   # how far to look for a surface; set this to roughly your level size
const TELEPORT_SEARCH_RAYS := 96       # more rays = more accurate nearest point

var bonus_speed:float = 0;
var speed_up_tween:Tween;
var speed:float:
	get():
		return SPEED + bonus_speed;
var surface_normal := Vector3.UP;

@export var home_point := Vector3.ZERO   # in the parent's local space
@export var recovery_speed := 4.0        # keep recovery_speed * delta well under SEARCH_RANGE

func _ready()->void:
	last_valid_transform = global_transform

func _physics_process(delta: float) -> void:
	# Left/right turn the body around its own up axis (works on any surface).
	if not global_transform.is_finite():
		global_transform = last_valid_transform
		velocity = Vector3.ZERO
	if not velocity.is_finite():
		velocity = Vector3.ZERO
	if not surface_normal.is_finite() or not surface_normal.is_normalized():
		surface_normal = _up()
	if _has_pending_teleport:
		_has_pending_teleport = false
		_apply_teleport(_pending_teleport)
		return

	var turn := Input.get_axis("move_right", "move_left")
	rotate_object_local(Vector3.UP, turn * TURN_SPEED * delta)

	# Up/down move forward/back along the body's facing direction.
	var forward_input := Input.get_axis("move_forward", "move_back")
	var direction := (global_basis * Vector3(0, 0, forward_input))
	direction = direction.normalized().slide(surface_normal)

	# 1. Find the surface we should be stuck to.
	var found := _find_surface_normal(direction)
	if found != Vector3.ZERO:
		_set_surface_normal(found)

	# 2. Rotate the body so its up axis matches the surface.
	_align_to_surface(delta)

	# 3. Move along the surface, pulled into it instead of by gravity.
	var tangent_velocity := velocity.normalized().slide(surface_normal)
	if direction:
		tangent_velocity = direction * speed
	else:
		tangent_velocity = tangent_velocity.move_toward(Vector3.ZERO, speed)

	velocity = tangent_velocity - surface_normal * STICK_SPEED
	if turn:
		velocity *= .7
	move_and_slide()

	# 4. Concave corners: climb onto surfaces we bump into at a steep angle.
	for i in get_slide_collision_count():
		var n := get_slide_collision(i).get_normal()
		if n.dot(surface_normal) < 0.7:
			_set_surface_normal(n)
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

	if not _set_surface_normal(hit.normal):
		return false
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
	var t := 1.0 - exp(-ALIGN_SPEED * delta)
	var q := Quaternion.IDENTITY.slerp(_rotation_to_surface(), t)
	global_basis = (Basis(q) * global_basis.orthonormalized()).orthonormalized()

var _pending_teleport := Transform3D.IDENTITY
var _has_pending_teleport := false

func teleport_to(target: Transform3D) -> void:

	_pending_teleport = target
	_has_pending_teleport = true

func _apply_teleport(target: Transform3D) -> void:
	var previous := global_transform

	global_transform = Transform3D(target.basis.orthonormalized(), target.origin)
	velocity = Vector3.ZERO
	surface_normal = global_basis.y

	# Normal case: the destination is already near a surface.
	if not _snap_to_surface():
		# Invalid position: find the nearest surface in any direction and go there.
		var hit := _find_nearest_surface_anywhere()
		if hit.is_empty():
			global_transform = previous
			push_warning("Teleport failed: no surface within %s units of %s" % [TELEPORT_SEARCH_RANGE, target.origin])
			return

		surface_normal = hit.normal
		global_position = hit.position + hit.normal * HOVER_DIST
		_snap_to_surface()   # refine to the true perpendicular distance

	# Orient instantly instead of easing, so the first frame isn't sideways.

	global_basis = (Basis(_rotation_to_surface()) * global_basis.orthonormalized()).orthonormalized()
	last_valid_transform = global_transform

func _find_nearest_surface_anywhere() -> Dictionary:
	# Stage 1: overlap queries with growing spheres. Handles a point that is
	# on, inside, or beside a collider, which rays can't see.
	var r := 0.25
	while r <= TELEPORT_SEARCH_RANGE:
		var overlap := _rest_info_at(global_position, r)
		if not overlap.is_empty():
			return overlap
		r *= 2.0

	# Stage 2: ray fan for anything farther out.
	var origin := global_position
	var best := {}
	var best_dist := INF
	var golden_angle := PI * (3.0 - sqrt(5.0))

	for i in TELEPORT_SEARCH_RAYS:
		var y := 1.0 - 2.0 * (i + 0.5) / TELEPORT_SEARCH_RAYS
		var ring := sqrt(1.0 - y * y)
		var theta := golden_angle * i
		var dir := Vector3(cos(theta) * ring, y, sin(theta) * ring)

		var hit := _raycast(origin, origin + dir * TELEPORT_SEARCH_RANGE)
		if hit:
			var d := origin.distance_squared_to(hit.position)
			if d < best_dist:
				best_dist = d
				best = hit

	return best

func _rest_info_at(point: Vector3, radius: float) -> Dictionary:
	var sphere := SphereShape3D.new()
	sphere.radius = radius

	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = sphere
	params.transform = Transform3D(Basis.IDENTITY, point)
	params.exclude = [get_rid()]

	var info := get_world_3d().direct_space_state.get_rest_info(params)
	if info.is_empty() or info.normal == Vector3.ZERO:
		return {}

	# Same keys the ray results use, so _apply_teleport needs no changes.
	return {"position": info.point, "normal": info.normal.normalized()}

func _raycast(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

func _up() -> Vector3:
	return global_basis.orthonormalized().y

# Only accepts a usable normal; returns false (and changes nothing) otherwise.
func _set_surface_normal(n: Vector3) -> bool:
	if not n.is_finite() or n.length_squared() < 0.0001:
		return false
	surface_normal = n.normalized()
	return true

func _rotation_to_surface() -> Quaternion:
	var up := _up()
	var d := up.dot(surface_normal)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		# Exactly upside down: the shortest arc is ambiguous, so flip around our own x axis.
		return Quaternion(global_basis.orthonormalized().x, PI)
	return Quaternion(up, surface_normal)   # both are unit length here

## not claude
## some stuff goes here so the signals become less scattered
const shaking_amp = 5;
func _on_board_container_saw_touched(_saw: Saw) -> void:
	pcam.noise.amplitude = shaking_amp
	pcam.noise.frequency = 50 ## editor thingy only goes to 10 

func _on_board_container_saw_left(_saw: Saw) -> void:
	pcam.noise.amplitude = 0;

#func _input(e:InputEvent)->void:
	#if e.is_action_pressed("autowin"):
		#win_run()

func win_run()->void:
	run_won.emit();

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

var invulnerable:bool=false;
func die(source:DeathType)->void:
	if has_shield:
		has_shield = false;
		cheat_death(source)
		shield_lost.emit()
		return;
	set_physics_process(false)
	death_sfx.play()
	dead = true;
	died.emit(source)

func cheat_death(type:DeathType)->void:
	cheat_death_sfx.play()
	blink_animation.play("blink");
	match type:
		DeathType.saw, DeathType.board:
			tp_to_safety()

func tp_to_safety()->void:
	await get_tree().physics_frame ## when boards drop, takes a frame 
	## for safe region detectors to refgresy
	var ssf:SafeSpotFinder = GLB.safe_spot_finder;
	var safe_board:StaticBody3D = GLB.board_container.safe_board;
	var t:Transform3D = ssf.get_free_biggest_face_transform(safe_board.get_node("CollisionShape3D"))
	t.origin = GLB.board_container.to_global(t.origin)
	teleport_to(t)

@onready var body_scale: = body.scale
func _on_fly_consumed(fly: Fly) -> void:
	if fly.type == Fly.Type.death:return;
	## should never overlap animations?
	body.scale *= 1.25;
	var t:= create_tween();
	t.tween_property(body, "scale", body_scale, .5)

	var m:StandardMaterial3D = buff_glow_mesh.mesh.material;
	var color:Color = Fly.buff_colors[fly.type];
	m.albedo_color = color
	m.emission = color;
	buff_glow_animation.play("buff_glow")
