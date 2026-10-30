extends MultiMeshInstance3D
class_name RollerLine

const spacing = 50;
const rotation_speed = 5

func _ready() -> void:
	setup_positions()
	multimesh.visible_instance_count = -1;

func setup_positions() -> void:
	var mm: MultiMesh = multimesh
	
	if mm == null:
		push_error("No MultiMesh assigned.")
		return
	
	var count: int = mm.instance_count
	var center: float = (count - 1) * 0.5
	
	for i: int in count:
		var t: Transform3D = Transform3D.IDENTITY
		
		# Place rollers evenly around the origin
		t.origin.z = (float(i) - center) * spacing
		t.basis = Basis(Vector3.FORWARD, deg_to_rad(90.0))
		mm.set_instance_transform(i, t)


func _process(delta: float) -> void:
	var mm: MultiMesh = multimesh
	
	if mm == null:
		return
	
	for i: int in mm.instance_count:
		var t: Transform3D = mm.get_instance_transform(i)
		
		# CylinderMesh default axis is Y.
		# Rotate around local X like a conveyor roller.
		t.basis = t.basis.rotated(
			Vector3.RIGHT,
			rotation_speed * delta
		)
		
		mm.set_instance_transform(i, t)
