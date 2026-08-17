@tool
extends EditorScript
## 诊断：确认 headless 导出时编辑器设置里 java_sdk_path 实际读到了什么。

func _run() -> void:
	var es := EditorInterface.get_editor_settings()
	for key in ["export/android/java_sdk_path", "export/android/android_sdk_path",
			"export/android/debug_keystore", "export/android/debug_keystore_user"]:
		print("CHECK ", key, " has=", es.has_setting(key),
				" value=[", es.get(key) if es.has_setting(key) else "<missing>", "]")
	var java_path: String = es.get("export/android/java_sdk_path") if es.has_setting("export/android/java_sdk_path") else ""
	if not java_path.is_empty():
		print("CHECK java.exe exists: ", FileAccess.file_exists(java_path.path_join("bin/java.exe")))
