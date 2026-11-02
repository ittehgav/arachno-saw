extends Node3D

@export var pcam:PhantomCamera3D;

@export var spider:Crawler
@export var player: CharacterBody3D

@export var mouse_sensitivity: float = 0.003
@export_range(-89.0, 0.0) var min_pitch_degrees: float = -80.0
@export_range(0.0, 89.0) var max_pitch_degrees: float = 60.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Make sure the pcam is in third person follow mode and tracking the player
	pcam.follow_mode = PhantomCamera3D.FollowMode.THIRD_PERSON
	pcam.follow_target = player


func _input(event: InputEvent) -> void:
	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rot: Vector3 = pcam.get_third_person_rotation()  # radians

		rot.y -= event.relative.x * mouse_sensitivity  # horizontal orbit
		rot.x -= event.relative.y * mouse_sensitivity  # vertical orbit
		rot.x = clampf(rot.x, deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))

		pcam.set_third_person_rotation(rot)
func _on_spider_died(_source: Crawler.DeathType) -> void:
	pcam.follow_mode = PhantomCamera3D.FollowMode.NONE;
	pcam.look_at_mode = PhantomCamera3D.LookAtMode.NONE;
	var t:= create_tween();
	t.tween_property(pcam.camera_3d_resource, "fov", pcam.fov + 30, 1)
