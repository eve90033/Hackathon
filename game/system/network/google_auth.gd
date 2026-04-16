extends Node
## Google Authentication via JavaScriptBridge (Web only)
## Non-web platforms use a generated local user_id as fallback.

signal login_completed(user_data: Dictionary)
signal login_failed(reason: String)

var _js_callback: JavaScriptObject
var is_web: bool = false


func _ready():
	is_web = OS.has_feature("web")
	if is_web:
		_js_callback = JavaScriptBridge.create_callback(_on_google_login_js)
		JavaScriptBridge.eval("window.godotLoginCallback = null;", true)
		var window = JavaScriptBridge.get_interface("window")
		window.godotLoginCallback = _js_callback


func start_login():
	if is_web:
		JavaScriptBridge.eval("triggerGoogleLogin();", true)
	else:
		# Fallback for non-web: generate local user
		var user_data = {
			"id": _generate_local_id(),
			"name": "Player_%d" % (randi() % 9999),
			"email": "",
			"picture": ""
		}
		login_completed.emit(user_data)


func _on_google_login_js(args: Array):
	var json_str = str(args[0])
	var parsed = JSON.parse_string(json_str)
	if parsed and parsed.has("id"):
		var user_data = {
			"id": parsed.get("id", ""),
			"name": parsed.get("name", ""),
			"email": parsed.get("email", ""),
			"picture": parsed.get("picture", "")
		}
		print("[GoogleAuth] Login success: ", user_data.name)
		login_completed.emit(user_data)
	else:
		print("[GoogleAuth] Login failed: invalid response")
		login_failed.emit("Invalid Google response")


func _generate_local_id() -> String:
	var raw = OS.get_unique_id()
	if raw.is_empty():
		raw = "local_%d" % randi()
	raw += "_%d" % OS.get_process_id()
	return raw.md5_text().substr(0, 12)
