@tool
extends EditorPlugin

const Guard := preload("res://addons/gd-guard/guard.gd")
const _SCAN_ITEM := "gd-guard: Scan Project"

var _menu_added := false


func _enter_tree() -> void:
	if not resource_saved.is_connected(_on_resource_saved):
		resource_saved.connect(_on_resource_saved)
	if not _menu_added:
		add_tool_menu_item(_SCAN_ITEM, _scan_project)
		_menu_added = true


func _exit_tree() -> void:
	if resource_saved.is_connected(_on_resource_saved):
		resource_saved.disconnect(_on_resource_saved)
	if _menu_added:
		remove_tool_menu_item(_SCAN_ITEM)
		_menu_added = false


func _on_resource_saved(resource: Resource) -> void:
	if not resource is GDScript:
		return
	var script := resource as GDScript
	var path := script.resource_path
	if path.is_empty() or _ignored_path(path):
		return
	var source := script.source_code
	if path.ends_with(".gd") and FileAccess.file_exists(path):
		source = FileAccess.get_file_as_string(path)
	_report(path, source)


func _scan_project() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem == null:
		push_error("gd-guard: editor filesystem is not available")
		return
	var root := filesystem.get_filesystem()
	if root == null:
		push_error("gd-guard: editor filesystem is not available")
		return
	_scan_directory(root)


func _scan_directory(directory: EditorFileSystemDirectory) -> void:
	if directory.get_path().begins_with("res://addons/"):
		return
	for index in directory.get_file_count():
		_scan_file(directory.get_file_path(index))
	for index in directory.get_subdir_count():
		_scan_directory(directory.get_subdir(index))


func _scan_file(path: String) -> void:
	if not path.ends_with(".gd") or _ignored_path(path):
		return
	if not FileAccess.file_exists(path):
		return
	_report(path, FileAccess.get_file_as_string(path))


func _report(path: String, source: String) -> void:
	for finding in Guard.scan(source):
		push_warning(Guard.format_warning(path, finding))


func _ignored_path(path: String) -> bool:
	return path.begins_with("res://addons/")
