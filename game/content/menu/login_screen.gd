extends Control


signal login_completed


@onready var google_button: Button = $VBox/GoogleButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var title_label: Label = $VBox/TitleLabel


func _ready():
	google_button.pressed.connect(_on_google_login)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.login_response.connect(_on_login_response)


func _on_google_login():
	google_button.disabled = true
	status_label.text = "登入中..."

	# Simulate Google login: generate a fake user_id from machine
	var user_id = _generate_user_id()
	NetworkManager.my_info.user_id = user_id

	# Auto-connect to server
	status_label.text = "連線中..."
	NetworkManager.auto_connect()


func _on_connected():
	status_label.text = "已連線！檢查角色資料..."

	var user_id = NetworkManager.my_info.user_id
	if NetworkManager.is_host():
		# Host checks directly
		NetworkManager.login_as_host(user_id)
	else:
		# Client asks server
		NetworkManager.request_login.rpc_id(1, user_id)


func _on_login_response(user_id: String, data: Dictionary):
	if data.is_empty():
		# No character found → go to character creation
		status_label.text = "歡迎新玩家！"
		login_completed.emit()
	else:
		# Has character → load it and skip creation
		NetworkManager.my_info.name = data.get("name", "Player")
		NetworkManager.my_info.character = data.get("character", "Knight")
		# Update our entry
		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()
		NetworkManager._register_player.rpc(NetworkManager.my_info)
		status_label.text = "歡迎回來，%s！" % NetworkManager.my_info.name
		# Small delay then enter world
		await get_tree().create_timer(0.5).timeout
		get_tree().get_first_node_in_group("main").enter_world()


func _generate_user_id() -> String:
	# Use OS unique ID + process ID for same-machine multiplayer
	var raw = OS.get_unique_id()
	if raw.is_empty():
		raw = "local_%d" % randi()
	raw += "_%d" % OS.get_process_id()
	return raw.md5_text().substr(0, 12)
