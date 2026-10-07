@tool
class_name MeshExploder
extends Node3D

const CONTAINER_NAME: StringName = &"ExplosionParticles"

@export var skeleton: Skeleton3D

@export_group("Explosion")
@export var force: float = 8.0
@export var upward_bias: float = 0.4
@export var spin_degrees: float = 360.0
@export var debris_lifetime: float = 4.0
@export var gravity_strength: float = 9.8
@export var hide_skeleton_on_emit: bool = true

@export_range(0.0, 2.0, 0.05) var scatter: float = 0.6  ## how far each piece's direction can stray from straight-out
@export_range(0.0, 1.0, 0.05) var speed_variation: float = 0.5  ## 0 = all same speed, 1 = anywhere from 0x to 1x of the max
@export_range(0.0, 1.0, 0.05) var spin_variation: float = 0.7
@export_range(0.0, 1.0, 0.05) var lifetime_variation: float = 0.3
@export_group("Piece Color")
@export var use_piece_color: bool = true
@export var piece_color: Color = Color(0.17, 0.145, 0.121, 1.0)
@export_range(0.0, 1.0, 0.05) var color_variation: float = 0.15  ## random brightness shift per piece

@export_group("Editor Buttons")
@export var generate: bool = false:
	set(value):
		if value and is_inside_tree() and Engine.is_editor_hint():
			generate_particles()
		notify_property_list_changed()
@export var preview_emit: bool = false:
	set(value):
		if value and is_inside_tree() and Engine.is_editor_hint():
			emit_all()
		notify_property_list_changed()
@export var reset: bool = false:
	set(value):
		if value and is_inside_tree() and Engine.is_editor_hint():
			reset_particles()
		notify_property_list_changed()


func generate_particles() -> void:
	if skeleton == null:
		push_warning("MeshExploder: no Skeleton3D assigned.")
		return

	_clear_particles()

	var scene_owner: Node = _get_scene_owner()

	var container: Node3D = Node3D.new()
	container.name = CONTAINER_NAME
	add_child(container)
	container.owner = scene_owner

	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(skeleton, meshes)

	for mi: MeshInstance3D in meshes:
		var p: CPUParticles3D = CPUParticles3D.new()
		p.name = "%s_Particles" % mi.name
		p.mesh = mi.mesh
		p.amount = 1
		p.one_shot = true
		p.explosiveness = 1.0
		p.local_coords = false
		p.emitting = false
		p.spread = 0.0

		container.add_child(p)
		p.owner = scene_owner
		p.global_transform = mi.global_transform  # sits exactly where the mesh is

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for c: Node in node.get_children():
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null and mi.mesh != null:
			out.append(mi)
		_collect_meshes(c, out)

func emit_all(origin: Vector3 = global_position) -> void:
	var container: Node3D = get_node_or_null(NodePath(CONTAINER_NAME)) as Node3D
	if container == null:
		push_warning("MeshExploder: no particles found, run generate_particles() first.")
		return

	for c: Node in container.get_children():
		var p: CPUParticles3D = c as CPUParticles3D
		if p == null or p.mesh == null:
			continue

		var xf: Transform3D = p.global_transform
		var center: Vector3 = xf * p.mesh.get_aabb().get_center()

		# outward from the blast, plus upward bias, plus a random kick per piece
		var dir_world: Vector3 = (center - origin).normalized() + Vector3.UP * upward_bias
		dir_world += Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * scatter
		dir_world = dir_world.normalized()

		# direction is in the emitter's local space
		p.direction = (xf.basis.orthonormalized().inverse() * dir_world).normalized()
		p.spread = 0.0

		# each piece gets its own speed, spin, and lifetime
		var speed: float = force * randf_range(1.0 - speed_variation, 1.0)
		p.initial_velocity_min = speed
		p.initial_velocity_max = speed

		var spin: float = spin_degrees * randf_range(1.0 - spin_variation, 1.0)
		spin *= 1.0 if randf() < 0.5 else -1.0  # random spin direction
		p.angular_velocity_min = spin
		p.angular_velocity_max = spin

		p.gravity = Vector3.DOWN * gravity_strength
		p.lifetime = debris_lifetime * randf_range(1.0 - lifetime_variation, 1.0 + lifetime_variation)
		if use_piece_color:
			var col: Color = piece_color
			if color_variation > 0.0:
				col.v = clampf(col.v + randf_range(-color_variation, color_variation), 0.0, 1.0)
			var mat: StandardMaterial3D = StandardMaterial3D.new()
			mat.albedo_color = col
			p.material_override = mat
		else:
			p.material_override = null  # back to the mesh's own materials
		p.restart()

	if hide_skeleton_on_emit and skeleton != null:
		skeleton.visible = false


func reset_particles() -> void:
	var container: Node3D = get_node_or_null(NodePath(CONTAINER_NAME)) as Node3D
	if container != null:
		for c: Node in container.get_children():
			var p: CPUParticles3D = c as CPUParticles3D
			if p != null:
				p.emitting = false
	if skeleton != null:
		skeleton.visible = true


func _clear_particles() -> void:
	var old: Node = get_node_or_null(NodePath(CONTAINER_NAME))
	if old != null:
		remove_child(old)
		old.queue_free()


func _get_scene_owner() -> Node:
	if Engine.is_editor_hint():
		return get_tree().edited_scene_root
	return owner
