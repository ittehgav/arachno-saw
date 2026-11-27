@tool
class_name ResourceWarmup
extends Node
## Editor: scan_project() finds every non-orphan resource file (plus resources used
## inside the nodes of non-orphan scenes) and stores their UIDs in `registered_uids`.
## Runtime: warm_up() loads them on a low-priority thread, then renders/plays them
## invisibly and silently, and finally emits `all_loaded`.
##
## Requires Godot 4.4+ (@export_tool_button). Save the scene after scanning.

signal progress(done: int, total: int)
signal all_loaded

const MUTE_BUS: StringName = &"_WarmupMuted"
const PROBE_VIEWPORT_SIZE: Vector2i = Vector2i(128, 128)

enum Stage { IDLE, LOADING_MAIN_THREAD, RENDERING }

@export_group("Scan")
## Folders (with trailing slash) that are skipped by the scan.
@export var excluded_dirs: PackedStringArray = ["res://addons/"]
## Files with these extensions are never registered.
@export var excluded_extensions: PackedStringArray = [
	"gd", "cs", "uid", "import", "md", "txt", "json", "cfg", "csv", "translation"
]
## Extra files that count as "used" even if nothing references them (e.g. scenes loaded by string in code).
@export var extra_roots: PackedStringArray = []
@export_tool_button("Scan project", "Search") var scan_button: Callable = scan_project
## Result of the scan. uid://... when the file has a UID, otherwise its res:// path.
@export var registered_uids: PackedStringArray = []

@export_group("Warm-up")
@export var warm_on_ready: bool = false
## Instantiate PackedScenes in the hidden viewport (runs their _ready scripts!). Off = scenes are only loaded.
@export var render_scenes: bool = true
## Max main-thread time per frame spent on instancing/loading, in ms.
@export_range(0.5, 16.0, 0.5) var frame_budget_ms: float = 4.0
## How many frames each probe stays alive so the renderer actually draws it.
@export_range(1, 8) var render_frames_per_item: int = 2
## Keep loaded resources referenced afterwards so the resource cache stays warm.
@export var keep_cached: bool = true
## Mutes the Master bus during the render stage. Catches sounds that scene scripts
## play from code. Only use this if nothing audible is playing (e.g. a silent loading screen).
@export var mute_master_while_rendering: bool = false

var _stage: Stage = Stage.IDLE
var _thread: Thread
var _cancel: bool = false
var _warming: bool = false
var _total: int = 0
var _load_index: int = 0
var _loaded: Array[Resource] = []
var _queue: Array[Resource] = []
var _active: Array[Dictionary] = []
var _viewport: SubViewport
var _camera: Camera3D
var _saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _saved_master_mute: bool = false


func _ready() -> void:
	set_process(false)
	if warm_on_ready and not Engine.is_editor_hint():
		warm_up()


func _exit_tree() -> void:
	_cancel = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# ---------------------------------------------------------------------------
# 1) Editor scan
# ---------------------------------------------------------------------------

func scan_project() -> void:
	if not Engine.is_editor_hint():
		push_warning("ResourceWarmup: scan_project() only works in the editor.")
		return

	var files: Array[String] = _collect_files("res://")

	# Non-orphan = referenced by at least one other file (same idea as Godot's
	# Orphan Resource Explorer), plus the main scene, autoloads and extra roots.
	var referenced: Dictionary = {}
	for root: String in _get_roots():
		referenced[root] = true
	for f: String in files:
		for dep: String in ResourceLoader.get_dependencies(f):
			var dep_path: String = _dependency_to_path(dep)
			if not dep_path.is_empty() and dep_path != f:
				referenced[dep_path] = true

	var non_orphans: Array[String] = []
	for f: String in files:
		if referenced.has(f):
			non_orphans.append(f)

	var found: Dictionary = {}
	for f: String in non_orphans:
		found[f] = true

	# Look inside the nodes of every non-orphan scene.
	var scene_count: int = 0
	for f: String in non_orphans:
		if f.get_extension() in ["tscn", "scn"]:
			_scan_scene(f, found)
			scene_count += 1

	# Register UIDs.
	var uid_set: Dictionary = {}
	for p: String in found.keys():
		if excluded_extensions.has(p.get_extension()) or not ResourceLoader.exists(p):
			continue
		var id: int = ResourceLoader.get_resource_uid(p)
		if id != ResourceUID.INVALID_ID:
			uid_set[ResourceUID.id_to_text(id)] = true
		else:
			uid_set[p] = true

	var result: PackedStringArray = PackedStringArray(uid_set.keys())
	result.sort()
	registered_uids = result
	notify_property_list_changed()
	if Engine.has_singleton("EditorInterface"):
		var editor_interface: Object = Engine.get_singleton("EditorInterface")
		editor_interface.call("mark_scene_as_unsaved")

	print("ResourceWarmup: %d files scanned, %d non-orphan (%d scenes inspected), %d registered."
		% [files.size(), non_orphans.size(), scene_count, registered_uids.size()])


func _collect_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var exts: Dictionary = {}
	for e: String in ResourceLoader.get_recognized_extensions_for_type(""):
		exts[e] = true
	_collect_files_rec(dir_path, exts, out)
	return out


func _collect_files_rec(dir_path: String, exts: Dictionary, out: Array[String]) -> void:
	for file_name: String in DirAccess.get_files_at(dir_path):
		var ext: String = file_name.get_extension().to_lower()
		if exts.has(ext) and not excluded_extensions.has(ext):
			out.append(dir_path.path_join(file_name))
	for sub: String in DirAccess.get_directories_at(dir_path):
		var sub_path: String = dir_path.path_join(sub) + "/"
		if not excluded_dirs.has(sub_path):
			_collect_files_rec(sub_path, exts, out)


func _get_roots() -> Array[String]:
	var roots: Array[String] = []
	var main: String = _to_path(str(ProjectSettings.get_setting("application/run/main_scene", "")))
	if not main.is_empty():
		roots.append(main)
	for prop: Dictionary in ProjectSettings.get_property_list():
		var setting_name: String = prop["name"]
		if setting_name.begins_with("autoload/"):
			var autoload_path: String = _to_path(str(ProjectSettings.get_setting(setting_name)).trim_prefix("*"))
			if not autoload_path.is_empty():
				roots.append(autoload_path)
	for r: String in extra_roots:
		var root_path: String = _to_path(r)
		if not root_path.is_empty():
			roots.append(root_path)
	return roots


func _to_path(s: String) -> String:
	if s.begins_with("uid://"):
		var id: int = ResourceUID.text_to_id(s)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return s


## Dependency strings look like "uid://...::Type::res://path" (sections vary by version).
func _dependency_to_path(dep: String) -> String:
	var fallback: String = ""
	for part: String in dep.split("::"):
		if part.begins_with("res://"):
			return part
		if part.begins_with("uid://") and fallback.is_empty():
			fallback = _to_path(part)
	return fallback


func _scan_scene(path: String, found: Dictionary) -> void:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		return
	var state: SceneState = scene.get_state()
	var visited: Dictionary = {}
	for n: int in state.get_node_count():
		var inst: PackedScene = state.get_node_instance(n)
		if inst:
			found[inst.resource_path] = true
		for p: int in state.get_node_property_count(n):
			_collect_resources(state.get_node_property_value(n, p), found, visited)


## External resources are recorded by path; embedded (sub)resources are searched recursively.
func _collect_resources(value: Variant, found: Dictionary, visited: Dictionary) -> void:
	match typeof(value):
		TYPE_OBJECT:
			var res: Resource = value as Resource
			if res == null or visited.has(res.get_instance_id()):
				return
			visited[res.get_instance_id()] = true
			if res.resource_path.is_empty() or "::" in res.resource_path:
				for prop: Dictionary in res.get_property_list():
					var usage: int = prop["usage"]
					var type: int = prop["type"]
					if not (usage & PROPERTY_USAGE_STORAGE):
						continue
					if type == TYPE_OBJECT or type == TYPE_ARRAY or type == TYPE_DICTIONARY:
						_collect_resources(res.get(prop["name"]), found, visited)
			else:
				found[res.resource_path] = true
		TYPE_ARRAY:
			for v: Variant in value:
				_collect_resources(v, found, visited)
		TYPE_DICTIONARY:
			for k: Variant in value:
				_collect_resources(value[k], found, visited)


# ---------------------------------------------------------------------------
# 2) Runtime warm-up
# ---------------------------------------------------------------------------

func warm_up() -> void:
	if Engine.is_editor_hint():
		push_warning("ResourceWarmup: warm_up() is meant to run in the game, not the editor.")
		return
	if _warming:
		return
	if registered_uids.is_empty():
		all_loaded.emit()
		return

	_warming = true
	_cancel = false
	_loaded.clear()
	_total = registered_uids.size()
	_load_index = 0
	_ensure_mute_bus()
	_saved_mouse_mode = Input.mouse_mode

	if not OS.has_feature("web") or OS.has_feature("threads"):
		_stage = Stage.IDLE
		_thread = Thread.new()
		_thread.start(_load_worker.bind(registered_uids.duplicate()), Thread.PRIORITY_LOW)
	else:
		# Single-threaded web export: load a few per frame instead.
		_stage = Stage.LOADING_MAIN_THREAD
		set_process(true)


func cancel() -> void:
	_cancel = true


## Drop the references kept by `keep_cached`.
func release() -> void:
	_loaded.clear()


func _load_worker(ids: PackedStringArray) -> void:
	var done: int = 0
	for id: String in ids:
		if _cancel:
			break
		var res: Resource = ResourceLoader.load(id)
		if res:
			_loaded.append(res)
		done += 1
		_emit_progress.call_deferred(done)
	_on_worker_done.call_deferred()


func _emit_progress(done: int) -> void:
	progress.emit(done, _total)


func _on_worker_done() -> void:
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	_begin_render()


func _begin_render() -> void:
	if _cancel:
		_finish()
		return
	if mute_master_while_rendering:
		_saved_master_mute = AudioServer.is_bus_mute(0)
		AudioServer.set_bus_mute(0, true)
	_queue.assign(_loaded)
	_create_stage()
	_stage = Stage.RENDERING
	set_process(true)


func _process(_delta: float) -> void:
	var start: int = Time.get_ticks_usec()
	var budget: int = int(frame_budget_ms * 1000.0)
	match _stage:
		Stage.LOADING_MAIN_THREAD:
			while _load_index < _total and Time.get_ticks_usec() - start < budget:
				var res: Resource = ResourceLoader.load(registered_uids[_load_index])
				if res:
					_loaded.append(res)
				_load_index += 1
				progress.emit(_load_index, _total)
			if _load_index >= _total:
				_begin_render()
		Stage.RENDERING:
			_render_step(start, budget)


func _render_step(start: int, budget: int) -> void:
	# Retire probes that have lived long enough.
	for i: int in range(_active.size() - 1, -1, -1):
		var entry: Dictionary = _active[i]
		var frames_left: int = int(entry["frames"]) - 1
		entry["frames"] = frames_left
		if frames_left <= 0:
			var old_node: Node = entry["node"]
			_free_probe(old_node)
			_active.remove_at(i)

	# Spawn new probes while there is time left this frame.
	while not _queue.is_empty() and Time.get_ticks_usec() - start < budget:
		var res: Resource = _queue.pop_back()
		var probe: Node = _make_probe(res)
		if probe == null:
			continue
		_viewport.add_child(probe)
		_add_stored_resources(probe)
		_show_all(probe)
		_play_audio(probe)
		_active.append({
			"node": probe,
			"frames": render_frames_per_item,
			"aabb": _gather_aabb(probe),
		})

	# Scene scripts may have captured the mouse in _ready().
	Input.mouse_mode = _saved_mouse_mode
	_frame_camera()

	if _queue.is_empty() and _active.is_empty():
		_finish()


func _finish() -> void:
	set_process(false)
	_stage = Stage.IDLE
	if is_instance_valid(_viewport):
		_viewport.queue_free()
	_viewport = null
	Input.mouse_mode = _saved_mouse_mode
	if mute_master_while_rendering:
		AudioServer.set_bus_mute(0, _saved_master_mute)
	_queue.clear()
	_active.clear()
	if not keep_cached:
		_loaded.clear()
	_warming = false
	all_loaded.emit()


# --- hidden render stage ----------------------------------------------------

func _create_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.size = PROBE_VIEWPORT_SIZE
	_viewport.own_world_3d = true # separate 3D world + physics space
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport) # never shown: not inside any container / texture

	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_camera.make_current()

	var light: DirectionalLight3D = DirectionalLight3D.new()
	_viewport.add_child(light)


func _make_probe(res: Resource) -> Node:
	if res is PackedScene:
		if not render_scenes:
			return null
		var inst: Node = (res as PackedScene).instantiate()
		_silence(inst)
		var inst_3d: Node3D = inst as Node3D
		if inst_3d:
			inst_3d.transform = Transform3D.IDENTITY
		return inst

	if res is AudioStream:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.bus = MUTE_BUS
		player.volume_db = -80.0
		player.stream = res as AudioStream
		return player

	if res is Texture2D:
		var tex: Texture2D = res as Texture2D
		var sprite: Sprite2D = Sprite2D.new()
		sprite.texture = tex
		var tex_size: Vector2 = tex.get_size()
		sprite.scale = Vector2.ONE * minf(1.0, 64.0 / maxf(maxf(tex_size.x, tex_size.y), 1.0))
		sprite.position = Vector2(PROBE_VIEWPORT_SIZE) * 0.5
		return sprite

	if res is Mesh:
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = res as Mesh
		return mesh_instance

	if res is BaseMaterial3D:
		return _material_probe_3d(res as Material)

	var shader_material: ShaderMaterial = res as ShaderMaterial
	if shader_material and shader_material.shader:
		match shader_material.shader.get_mode():
			Shader.MODE_SPATIAL:
				return _material_probe_3d(shader_material)
			Shader.MODE_CANVAS_ITEM:
				var rect: ColorRect = ColorRect.new()
				rect.size = Vector2(64, 64)
				rect.material = shader_material
				return rect

	return null # still loaded and cached, just nothing to draw/play


func _material_probe_3d(material: Material) -> Node:
	var sphere: MeshInstance3D = MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.material_override = material
	return sphere


func _is_audio_player(n: Node) -> bool:
	return n is AudioStreamPlayer or n is AudioStreamPlayer2D or n is AudioStreamPlayer3D


## Make an instanced scene harmless: muted audio, no autoplay, no cameras stealing the view, no processing.
func _silence(root: Node) -> void:
	root.process_mode = Node.PROCESS_MODE_DISABLED
	for n: Node in _all_nodes(root):
		if _is_audio_player(n):
			n.set("bus", MUTE_BUS)
			n.set("volume_db", -80.0)
			n.set("autoplay", false)
		elif n is Camera3D:
			(n as Camera3D).current = false
		elif n is Camera2D:
			(n as Camera2D).enabled = false


## Meshes and audio streams kept in variables (exports, script vars, arrays, dictionaries,
## custom resources) that nothing displays/plays yet get their own MeshInstance3D /
## AudioStreamPlayer, parented to the probe, so they are drawn and played (muted) too.
func _add_stored_resources(root: Node) -> void:
	var nodes: Array[Node] = _all_nodes(root)
	var used: Dictionary = {}
	for n: Node in nodes:
		var mesh_instance: MeshInstance3D = n as MeshInstance3D
		if mesh_instance and mesh_instance.mesh:
			used[mesh_instance.mesh.get_instance_id()] = true
		var multi: MultiMeshInstance3D = n as MultiMeshInstance3D
		if multi and multi.multimesh and multi.multimesh.mesh:
			used[multi.multimesh.mesh.get_instance_id()] = true
		if _is_audio_player(n):
			var existing: AudioStream = n.get("stream") as AudioStream
			if existing:
				used[existing.get_instance_id()] = true

	var meshes: Array[Mesh] = []
	var streams: Array[AudioStream] = []
	var visited: Dictionary = {}
	for n: Node in nodes:
		for prop: Dictionary in n.get_property_list():
			var usage: int = prop["usage"]
			if not (usage & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE)):
				continue
			var type: int = prop["type"]
			if type == TYPE_OBJECT or type == TYPE_ARRAY or type == TYPE_DICTIONARY:
				_find_stored(n.get(prop["name"]), meshes, streams, visited, used, 0)

	for mesh: Mesh in meshes:
		var extra_mesh: MeshInstance3D = MeshInstance3D.new()
		extra_mesh.name = &"_WarmupMesh"
		extra_mesh.mesh = mesh
		root.add_child(extra_mesh)

	for stream: AudioStream in streams:
		var extra_player: AudioStreamPlayer = AudioStreamPlayer.new()
		extra_player.name = &"_WarmupAudio"
		extra_player.bus = MUTE_BUS
		extra_player.volume_db = -80.0
		extra_player.stream = stream
		root.add_child(extra_player) # played by _play_audio() afterwards


func _find_stored(value: Variant, meshes: Array[Mesh], streams: Array[AudioStream], visited: Dictionary, used: Dictionary, depth: int) -> void:
	match typeof(value):
		TYPE_OBJECT:
			var res: Resource = value as Resource
			if res == null or visited.has(res.get_instance_id()):
				return
			visited[res.get_instance_id()] = true
			var mesh: Mesh = res as Mesh
			if mesh:
				if not used.has(mesh.get_instance_id()):
					used[mesh.get_instance_id()] = true
					meshes.append(mesh)
				return
			var stream: AudioStream = res as AudioStream
			if stream:
				if not used.has(stream.get_instance_id()):
					used[stream.get_instance_id()] = true
					streams.append(stream)
				return
			# Only look inside custom (scripted) resources, up to two levels deep.
			if depth < 2 and res.get_script() != null:
				for prop: Dictionary in res.get_property_list():
					var usage: int = prop["usage"]
					var type: int = prop["type"]
					if (usage & PROPERTY_USAGE_STORAGE) and (type == TYPE_OBJECT or type == TYPE_ARRAY or type == TYPE_DICTIONARY):
						_find_stored(res.get(prop["name"]), meshes, streams, visited, used, depth + 1)
		TYPE_ARRAY:
			for v: Variant in value:
				_find_stored(v, meshes, streams, visited, used, depth)
		TYPE_DICTIONARY:
			for k: Variant in value:
				_find_stored(value[k], meshes, streams, visited, used, depth)


## Force every node that has a `visible` property to be visible so hidden meshes/UI still get drawn.
## Runs after add_child(), so it also overrides anything a scene's _ready() hid.
func _show_all(root: Node) -> void:
	for n: Node in _all_nodes(root):
		if n is Window:
			continue # a visible Window would try to open a real popup
		if "visible" in n:
			n.set("visible", true)


func _play_audio(root: Node) -> void:
	for n: Node in _all_nodes(root):
		if _is_audio_player(n) and n.get("stream") != null:
			n.call("play")


func _free_probe(node: Node) -> void:
	if not is_instance_valid(node):
		return
	for n: Node in _all_nodes(node):
		if _is_audio_player(n):
			n.call("stop")
	node.queue_free()


func _all_nodes(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "", true, false))
	return nodes


func _gather_aabb(root: Node) -> AABB:
	var box: AABB = AABB()
	var any: bool = false
	for n: Node in _all_nodes(root):
		var visual: VisualInstance3D = n as VisualInstance3D
		if visual:
			var b: AABB = visual.global_transform * visual.get_aabb()
			box = b if not any else box.merge(b)
			any = true
	return box


## Point the camera at everything currently being probed so frustum culling doesn't skip it.
func _frame_camera() -> void:
	var box: AABB = AABB()
	var any: bool = false
	for entry: Dictionary in _active:
		var b: AABB = entry["aabb"]
		if b.size == Vector3.ZERO:
			continue
		box = b if not any else box.merge(b)
		any = true
	if not any:
		return
	var radius: float = maxf(box.size.length() * 0.5, 0.1)
	var center: Vector3 = box.get_center()
	_camera.near = maxf(radius * 0.01, 0.05)
	_camera.far = radius * 8.0
	_camera.global_position = center + Vector3(0.0, 0.0, radius * 2.5)
	_camera.look_at(center)
	_camera.make_current()


func _ensure_mute_bus() -> void:
	if AudioServer.get_bus_index(MUTE_BUS) != -1:
		return
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, MUTE_BUS)
	AudioServer.set_bus_mute(idx, true)
