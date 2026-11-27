extends MeshInstance3D


@export var material_surface := 0

@export var default_alpha := .3
@export var max_alpha := .9
@export var min_alpha := 0.01
@export var alpha_speed := 10.0

var current_alpha: float
var material: StandardMaterial3D


func _ready()->void:
	var mat := get_surface_override_material(material_surface)

	if mat == null:
		mat = mesh.surface_get_material(material_surface)

	if mat:
		material = mat.duplicate()
		set_surface_override_material(material_surface, material)
		current_alpha = material.albedo_color.a
	else:
		push_warning("No material found on surface %s" % material_surface)


func _process(delta:float)->void:
	if material == null:
		return

	if Input.is_action_pressed("move_forward"):
		current_alpha = move_toward(current_alpha, max_alpha, alpha_speed * delta)

	elif Input.is_action_pressed("move_back"):
		current_alpha = move_toward(current_alpha, min_alpha, alpha_speed * delta)

	else:
		current_alpha = move_toward(current_alpha, default_alpha, alpha_speed * delta)

	var color := material.albedo_color
	color.a = current_alpha
	material.albedo_color = color
