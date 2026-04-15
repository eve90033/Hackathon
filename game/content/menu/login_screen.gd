extends Control


signal login_completed


@onready var google_button: Button = $VBox/GoogleButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var title_label: Label = $VBox/TitleLabel


func _ready():
	google_button.pressed.connect(_on_google_login)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.login_response.connect(_on_login_response)
	# Auto-login for testing
	if "--auto-login" in OS.get_cmdline_user_args():
		get_tree().create_timer(1.0).timeout.connect(_on_google_login)


func _on_google_login():
	google_button.disabled = true
	status_label.text = "登入中..."

	# Simulate Google login: generate a fake user_id from machine
	var user_id = _generate_user_id()
	NetworkManager.my_info.user_id = user_id
	NetworkManager.flog("[Login] user_id=%s, my_info=%s" % [user_id, str(NetworkManager.my_info)])

	# Connect to server
	status_label.text = "連線中..."
	var server_url = NetworkManager.server_url
	NetworkManager.flog("[Login] Connecting to %s" % server_url)
	var err = NetworkManager.join_game(server_url)
	if err != OK:
		status_label.text = "連線失敗，嘗試自己建立..."
		NetworkManager.flog("[Login] join_game failed, trying auto_connect")
		NetworkManager.auto_connect()


func _on_connected():
	status_label.text = "已連線！檢查角色資料..."
	var my_id = multiplayer.get_unique_id()
	NetworkManager.flog("[Login] _on_connected: my_id=%d is_host=%s user_id=%s" % [my_id, str(NetworkManager.is_host()), NetworkManager.my_info.user_id])

	var user_id = NetworkManager.my_info.user_id
	if NetworkManager.is_host():
		# Host checks directly
		NetworkManager.login_as_host(user_id)
	else:
		# Client asks server
		NetworkManager.flog("[Login] Sending request_login to server for user_id=%s" % user_id)
		NetworkManager.request_login.rpc_id(1, user_id)


func _on_login_response(user_id: String, data: Dictionary):
	NetworkManager.flog("[Login] _on_login_response: user_id=%s data=%s" % [user_id, str(data)])
	if data.is_empty():
		# No character found → go to character creation
		status_label.text = "歡迎新玩家！"
		NetworkManager.flog("[Login] New player, showing character select")
		login_completed.emit()
	else:
		# Has character → load it and skip creation
		NetworkManager.my_info.name = data.get("name", "Player")
		NetworkManager.my_info.character = data.get("character", "Knight")
		# Update our entry
		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()
		NetworkManager.flog("[Login] Returning player, broadcasting register: my_id=%d info=%s" % [my_id, str(NetworkManager.my_info)])
		NetworkManager._register_player.rpc(NetworkManager.my_info)
		status_label.text = "歡迎回來，%s！" % NetworkManager.my_info.name
		# Small delay then enter world
		await get_tree().create_timer(0.5).timeout
		NetworkManager.flog("[Login] Entering world now")
		get_tree().get_first_node_in_group("main").enter_world()


func _generate_user_id() -> String:
	# Use OS unique ID + process ID for same-machine multiplayer
	var raw = OS.get_unique_id()
	if raw.is_empty():
		raw = "local_%d" % randi()
	raw += "_%d" % OS.get_process_id()
	return raw.md5_text().substr(0, 12)
