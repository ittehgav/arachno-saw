extends CharacterBody3D

@export var raycast:RayCast3D

@export var body:Node3D;

func _ready() -> void:
	up_direction = get_floor_normal()

const speed = 5;
const turn_speed =2.5

func _physics_process(delta: float) -> void:
	# Gravity
	
	# WASD input
	rotate_y(Input.get_axis("move_left", "move_right") * turn_speed * delta)

	var move := Input.get_axis("move_down", "move_up")
	var forward := -transform.basis.z

	velocity.x = forward.x * move * speed
	velocity.z = forward.z * move * speed
	velocity.y = get_gravity().y
	move_and_slide()

func movement_input()->Vector3:
	var input: = Vector3(
		0,
		0,
		Input.get_axis("move_up", "move_down")
	)
	return input;
