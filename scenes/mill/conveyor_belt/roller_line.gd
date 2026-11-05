extends MultiMeshInstance3D
class_name RollerLine

const spacing: float = 50.0
const rotation_speed: float = 5.0

var angle: float = 0.0
var base_basis: Basis = Basis(Vector3.FORWARD, deg_to_rad(90.0))
var origins: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	setup_positions()
	multimesh.visible_instance_count = -1


func setup_positions() -> void:
	var mm: MultiMesh = multimesh
	
	if mm == null:
		push_error("No MultiMesh assigned.")
		return
	
	var count: int = mm.instance_count
	var center: float = (count - 1) * 0.5
	
	origins.resize(count)
	for i: int in count:
		origins[i] = Vector3(0.0, 0.0, (float(i) - center) * spacing)
	
	_apply_transforms()


func _process(delta: float) -> void:
	if multimesh == null:
		return
	
	angle = fposmod(angle + rotation_speed * delta, TAU)
	_apply_transforms()


func _apply_transforms() -> void:
	var mm: MultiMesh = multimesh
	
	# Rebuilt fresh every frame, so no error can accumulate.
	# Spin around the roller's local Y axis (the cylinder's own axis),
	# applied before the base orientation.
	var spin: Basis = Basis(Vector3.UP, angle)
	var b: Basis = base_basis * spin
	
	for i: int in mm.instance_count:
		mm.set_instance_transform(i, Transform3D(b, origins[i]))
