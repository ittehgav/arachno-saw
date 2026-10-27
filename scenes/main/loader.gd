class_name AssetPreloader
extends Node
## Preloads whole scenes using ResourceLoader's threaded API. Everything a scene
## references (meshes, textures, audio, materials, sub-scenes) is found from the
## .tscn/.scn file itself and loaded in parallel before the scene.
## Add it to your loading scene (or make it an autoload), list your scenes in
## `scene_paths`, and connect to `progress_changed` and `finished`.

signal progress_changed(ratio: float)
signal finished

## Scenes to load. Nothing else is scanned: every mesh, texture and audio file
## comes from what these scenes (and the resources/sub-scenes they use) reference.
@export_file("*.tscn", "*.scn") var scene_paths: Array[String] = []
## Lets big resources load their own dependencies in parallel.
@export var use_sub_threads := true
## Plays every loaded sound once, silently, so first-play setup happens now.
@export var warm_up_audio := true
## Draws every unique mesh once in a hidden viewport so shaders compile now.
@export var warm_up_meshes := true
## How many meshes are drawn per warm-up step (two frames each).
@export_range(1, 64) var warm_up_batch := 8
@export var start_on_ready := true

const SKIP_EXT := ["gd", "cs"]

## path -> loaded Resource. Keeping them here also keeps them in Godot's cache,
## so later load() calls on the same path return instantly.
var resources: Dictionary = {}
var failed: Array[String] = []

var _paths: Array[String] = []
var _queued: Dictionary = {}
var _visited: Dictionary = {}
var _pending: Array[String] = []
var _total := 0
var _started := false


func _ready() -> void:
	set_process(false)
	if start_on_ready:
		start()


func start() -> void:
	if _started:
		return
	_started = true

	# Dependencies are queued before the scene that uses them.
	for scene in scene_paths:
		_queue_dependencies(scene)
		_queue(scene)

	for p in _paths:
		var err := ResourceLoader.load_threaded_request(p, "", use_sub_threads)
		if err == OK:
			_pending.append(p)
		else:
			failed.append(p)
			push_warning("AssetPreloader: could not request %s (error %d)" % [p, err])

	_total = _pending.size()
	if _total == 0:
		_finish()
		return
	set_process(true)


func _process(_delta: float) -> void:
	var still_loading: Array[String] = []
	for p in _pending:
		match ResourceLoader.load_threaded_get_status(p):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				still_loading.append(p)
			ResourceLoader.THREAD_LOAD_LOADED:
				resources[p] = ResourceLoader.load_threaded_get(p)
			_:
				failed.append(p)
				push_error("AssetPreloader: failed to load " + p)
	_pending = still_loading

	var done := _total - _pending.size()
	progress_changed.emit(float(done) / float(_total))

	if _pending.is_empty():
		set_process(false)
		_finish()


func _finish() -> void:
	if warm_up_audio:
		await _warm_up_audio()
	if warm_up_meshes:
		await _warm_up_meshes()
	progress_changed.emit(1.0)
	finished.emit()


## Returns the loaded resource, or null if it wasn't preloaded.
func get_resource(path: String) -> Resource:
	return resources.get(path)


## Convenience for the scenes listed in `scene_paths`.
func get_scene(path: String) -> PackedScene:
	return resources.get(path) as PackedScene


# ---------------------------------------------------------------- queueing

func _queue(path: String) -> void:
	if not _queued.has(path):
		_queued[path] = true
		_paths.append(path)


## Queues everything `path` depends on, deepest dependencies first.
func _queue_dependencies(path: String) -> void:
	if _visited.has(path) or not ResourceLoader.exists(path):
		return
	_visited[path] = true
	for dep in ResourceLoader.get_dependencies(path):
		var dep_path := _dependency_path(dep)
		if dep_path.is_empty() or dep_path.get_extension().to_lower() in SKIP_EXT:
			continue
		_queue_dependencies(dep_path)
		_queue(dep_path)


## Dependencies come as "path", "uid::path" or "uid::type::path".
func _dependency_path(dep: String) -> String:
	var parts := dep.split("::")
	var path := parts[parts.size() - 1]
	if path.is_empty() or path.begins_with("uid://"):
		if parts[0].begins_with("uid://"):
			var id := ResourceUID.text_to_id(parts[0])
			if ResourceUID.has_id(id):
				return ResourceUID.get_id_path(id)
		return ""
	return path


# ----------------------------------------------------------------- warm-up

func _warm_up_audio() -> void:
	for path:StringName in resources:
		var stream := resources[path] as AudioStream
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -80.0
		add_child(player)
		player.play()
		await get_tree().process_frame  # one sound per frame keeps hitches small
		player.stop()
		player.queue_free()


func _warm_up_meshes() -> void:
	# mesh -> material_override (or null), de-duplicated by resource.
	var meshes: Dictionary = {}
	var seen_scenes: Dictionary = {}
	for path:StringName in resources:
		var res:Resource = resources[path]
		if res is Mesh:
			if not meshes.has(res):
				meshes[res] = null
		elif res is PackedScene:
			_collect_scene_meshes(res, meshes, seen_scenes)
	if meshes.is_empty():
		return

	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var cam := Camera3D.new()
	cam.far = 100000.0
	vp.add_child(cam)
	cam.make_current()
	vp.add_child(DirectionalLight3D.new())

	var keys := meshes.keys()
	for from in range(0, keys.size(), warm_up_batch):
		var nodes: Array[MeshInstance3D] = []
		var bounds := AABB()
		for i in range(from, mini(from + warm_up_batch, keys.size())):
			var mesh: Mesh = keys[i]
			var node := MeshInstance3D.new()
			node.mesh = mesh
			node.material_override = meshes[mesh]
			vp.add_child(node)
			bounds = mesh.get_aabb() if nodes.is_empty() else bounds.merge(mesh.get_aabb())
			nodes.append(node)
		var radius := maxf(bounds.size.length() * 0.5, 0.5)
		cam.position = bounds.get_center() + Vector3(0.0, 0.0, radius * 2.5)
		await get_tree().process_frame
		await get_tree().process_frame
		for n in nodes:
			n.queue_free()
	vp.queue_free()


## Reads MeshInstance3D nodes straight from the scene file, including meshes
## embedded inside the .tscn, without instancing the scene (no scripts run).
func _collect_scene_meshes(scene: PackedScene, out: Dictionary, seen: Dictionary) -> void:
	if seen.has(scene):
		return
	seen[scene] = true
	var state := scene.get_state()
	for i in state.get_node_count():
		var inst := state.get_node_instance(i)
		if inst != null:
			_collect_scene_meshes(inst, out, seen)
			continue
		if state.get_node_type(i) != &"MeshInstance3D":
			continue
		var mesh: Mesh = null
		var mat: Material = null
		for p in state.get_node_property_count(i):
			var prop_name := state.get_node_property_name(i, p)
			if prop_name == &"mesh":
				mesh = state.get_node_property_value(i, p)
			elif prop_name == &"material_override":
				mat = state.get_node_property_value(i, p)
		if mesh != null and not out.has(mesh):
			out[mesh] = mat
