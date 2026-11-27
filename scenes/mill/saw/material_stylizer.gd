@tool
extends Node
class_name MaterialStylizer;

const normals_dir = "res://assets/textures/psx normals"
@export_tool_button("Apply Material Settings")
var apply_button := apply_material_settings;


func apply_material_settings() -> void:
	if !Engine.is_editor_hint():
		return

	var root := get_tree().edited_scene_root
	if root == null:
		return

	_process_node(root)


func _process_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D

		# Material Override
		if mesh_instance.material_override is StandardMaterial3D:
			_process_material(mesh_instance.material_override)

		# Surface Override Materials
		for i in mesh_instance.get_surface_override_material_count():
			var material := mesh_instance.get_surface_override_material(i)
			if material is StandardMaterial3D:
				_process_material(material)

		if mesh_instance.mesh:
			# PrimitiveMesh.material (BoxMesh, SphereMesh, etc.)
			if mesh_instance.mesh is PrimitiveMesh:
				var primitive := mesh_instance.mesh as PrimitiveMesh
				if primitive.material is StandardMaterial3D:
					_process_material(primitive.material)

			# Imported mesh / ArrayMesh surface materials
			for i in mesh_instance.mesh.get_surface_count():
				var material := mesh_instance.mesh.surface_get_material(i)
				if material is StandardMaterial3D:
					_process_material(material)

	for child in node.get_children():
		_process_node(child)
func _process_material(material: StandardMaterial3D) -> void:
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	

	var albedo := material.albedo_texture
	if albedo == null:
		return

	var texture_path := albedo.resource_path
	if texture_path.is_empty():
		return

	#var filename := texture_path.get_file().get_basename()
	#var normal_path := normals_dir.path_join(filename + "_normal.png")
#
	#if ResourceLoader.exists(normal_path):
		#var normal := load(normal_path) as Texture2D
		#if normal:
			#material.normal_enabled = true
			#material.normal_texture = normal
	material.normal_enabled = false;
	material.normal_texture = null;
