extends MeshInstance3D


func _physics_process(_delta: float) -> void:
	position.x = GLB.spider.position.x


func _on_warning_region_body_entered(body: Node3D) -> void:
	assert(body is Crawler)
	show()


func _on_warning_region_body_exited(body: Node3D) -> void:
	assert(body is Crawler)
	hide()
