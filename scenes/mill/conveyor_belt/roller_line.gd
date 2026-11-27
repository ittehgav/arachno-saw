extends MultiMeshInstance3D

@export var rotation_axis: Vector3 = Vector3.FORWARD
@export var rotation_speed: float = 180.0 # Degrees per second

func _process(delta: float) -> void:
	var mm:= self.multimesh


	var axis := rotation_axis.normalized()
	var r := Basis(axis, deg_to_rad(rotation_speed) * delta)

	for i in multimesh.instance_count:
		var t := multimesh.get_instance_transform(i)
		t.basis = r * t.basis
		multimesh.set_instance_transform(i, t)
