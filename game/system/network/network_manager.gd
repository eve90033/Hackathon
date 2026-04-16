extends Node


signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal login_response(user_id: String, data: Dictionary)


const PORT := 7777
const MAX_PLAYERS := 4
const DEFAULT_HOST_IP := "127.0.0.1"

# Connected players: { peer_id: { "user_id", "name", "character" } }
var players := {}
var my_info := { "name": "", "character": "", "user_id": "" }

# Server-side player database: { "user_id": { "name", "character" } }
# Persisted to file on Host machine
var player_database := {}
const DB_PATH := "user://player_database.json"


var _log_file: FileAccess

func flog(msg: String):
	print(msg)
	if !_log_file:
		var pid = OS.get_process_id()
		var path = "user://debug_log_%d.txt" % pid
		_log_file = FileAccess.open(path, FileAccess.WRITE)
		if _log_file:
			_log_file.store_line("=== Log started PID=%d ===" % pid)
	if _log_file:
		_log_file.store_line("[%d] %s" % [Time.get_ticks_msec(), msg])
		_log_file.flush()

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_load_database()


var server_url := "ws://localhost:%d" % PORT
var is_dedicated_server := false


func auto_connect():
	# Try to host first. If port is taken, join instead.
	var peer = WebSocketMultiplayerPeer.new()
	var err = peer.create_server(PORT, "*")
	if err == OK:
		multiplayer.multiplayer_peer = peer
		players[1] = my_info.duplicate()
		print("[Net] WebSocket Server on port %d" % PORT)
		connection_succeeded.emit()
	else:
		print("[Net] Port taken, joining %s" % server_url)
		peer = WebSocketMultiplayerPeer.new()
		err = peer.create_client(server_url)
		if err != OK:
			push_error("[Net] Failed to connect")
			return
		multiplayer.multiplayer_peer = peer


func _become_host():
	var peer = WebSocketMultiplayerPeer.new()
	var err = peer.create_server(PORT, "*")
	if err != OK:
		push_error("[Net] Failed to create server: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	players[1] = my_info.duplicate()
	print("[Net] WebSocket Server on port %d" % PORT)
	connection_succeeded.emit()


func host_game():
	_become_host()
	return OK


func join_game(address: String):
	var url = address
	if !url.begins_with("ws://") and !url.begins_with("wss://"):
		url = "ws://%s:%d" % [address, PORT]
	print("[Net] Joining server at %s" % url)
	var peer = WebSocketMultiplayerPeer.new()
	var err = peer.create_client(url)
	print("[Net] create_client result: %d" % err)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func _on_peer_connected(id: int):
	flog("[Net] Peer connected: %d, my_info=%s" % [id, str(my_info)])
	_register_player.rpc_id(id, my_info)


func _on_peer_disconnected(id: int):
	print("[Net] Peer disconnected: %d" % id)
	players.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server():
	var my_id = multiplayer.get_unique_id()
	flog("[Net] Connected to server! my_id=%d my_info=%s" % [my_id, str(my_info)])
	players[my_id] = my_info.duplicate()
	connection_succeeded.emit()


func _on_connection_failed():
	print("[Net] Connection failed!")
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected():
	print("[Net] Server disconnected!")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _register_player(info: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = info
	flog("[Net] _register_player sender=%d info=%s | all_players=%s" % [sender_id, str(info), str(players.keys())])
	player_connected.emit(sender_id)


# --- Server-side login/save ---

@rpc("any_peer", "reliable")
func request_login(user_id: String):
	# Only server handles this
	if !multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	flog("[Net] Login request from peer %d, user_id=%s" % [sender_id, user_id])
	var data = player_database.get(user_id, {})
	_login_response.rpc_id(sender_id, user_id, data)


@rpc("authority", "reliable")
func _login_response(user_id: String, data: Dictionary):
	flog("[Net] Login response: user_id=%s has_data=%s data=%s" % [user_id, !data.is_empty(), str(data)])
	login_response.emit(user_id, data)


@rpc("any_peer", "reliable")
func save_character(user_id: String, data: Dictionary):
	# Only server handles this
	if !multiplayer.is_server():
		return
	# Merge into existing data (don't overwrite everything)
	if !player_database.has(user_id):
		player_database[user_id] = {}
	for key in data:
		player_database[user_id][key] = data[key]
	_save_database()
	print("[Net] Saved for user_id=%s: %s" % [user_id, data])


func login_as_host(user_id: String):
	# Host checks its own database directly
	var data = player_database.get(user_id, {})
	login_response.emit(user_id, data)


func get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			return addr
	return "127.0.0.1"


func is_host() -> bool:
	return multiplayer.is_server()


@rpc("any_peer", "reliable")
func check_name(pname: String, char_key: String):
	## Server 端檢查暱稱唯一性（資料庫 + 在線玩家）
	if !multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	# 找出發送者的 user_id
	var sender_uid = players.get(sender, {}).get("user_id", "")
	var taken := false
	# 1. 檢查資料庫（所有註冊過的玩家）
	for uid in player_database:
		var data = player_database[uid]
		if data.get("name", "") == pname and uid != sender_uid:
			taken = true
			break
	# 2. 也檢查目前在線玩家（可能尚未存檔）
	if !taken:
		for pid in players:
			if pid != sender and players[pid].get("name", "") == pname:
				taken = true
				break
	if taken:
		_name_check_response.rpc_id(sender, false, "此暱稱已被使用！")
	else:
		_name_check_response.rpc_id(sender, true, "")


@rpc("authority", "reliable")
func _name_check_response(ok: bool, reason: String):
	## Client 端收到暱稱檢查結果
	var main = get_tree().current_scene
	if !main:
		return
	var overlay_layer = main.get_node_or_null("OverlayLayer")
	if !overlay_layer:
		return
	for child in overlay_layer.get_children():
		if child.has_method("_on_name_check_result"):
			child._on_name_check_result(ok, reason)
			break


func disconnect_from_game():
	multiplayer.multiplayer_peer = null
	players.clear()


@rpc("any_peer", "call_remote", "reliable")
func sync_companion(captor_name:String, m_key:String, m_tier:int = 0):
	flog("[Companion] sync_companion received! captor=%s monster=%s my_id=%d" % [captor_name, m_key, multiplayer.get_unique_id()])
	# Find World node (child of Main)
	var main = get_tree().current_scene
	if !main:
		flog("[Companion] ERROR: no current_scene!")
		return
	var world = main.get_node_or_null("World")
	if !world:
		world = main  # fallback for single-player
	var captor = world.get_node_or_null("PlayerContainer/" + captor_name)
	if !captor:
		flog("[Companion] ERROR: captor not found at PlayerContainer/%s" % captor_name)
		# Try direct search
		for p in world.get_node("PlayerContainer").get_children():
			flog("[Companion]   child: %s" % p.name)
		return
	# Remove old companion (notify escape on local client)
	for old in get_tree().get_nodes_in_group("companion"):
		if old.target == captor:
			# 只在擁有者的 client 顯示逃走通知
			if captor is NetworkCharacter and captor.peer_id == multiplayer.get_unique_id():
				var old_cn = old.monster_key
				var world_ref = get_tree().root.find_child("World", true, false)
				if world_ref and world_ref.get("MONSTER_NAMES"):
					old_cn = world_ref.MONSTER_NAMES.get(old.monster_key, old.monster_key)
				var ui = get_node_or_null("/root/UIManager")
				if ui:
					var old_face = "res://assets/Actor/Monster/%s/Faceset.png" % old.monster_key
					ui.push_notify("%s 逃走了！" % old_cn, Color(1.0, 0.5, 0.3), 3.0, old_face)
			old.queue_free()
	# Spawn new
	var comp_scene = preload("res://system/companion/companion.tscn")
	var comp = comp_scene.instantiate()
	comp.global_position = captor.global_position + Vector2(16, 16)
	comp.target = captor
	comp.monster_key = m_key
	comp.monster_tier = m_tier
	world.add_child(comp)
	# Load texture — try exact key first, then fallback without trailing digits
	var tex_path = "res://assets/Actor/Monster/%s/SpriteSheet.png" % m_key
	if !ResourceLoader.exists(tex_path):
		tex_path = "res://assets/Actor/Monster/%s/%s.png" % [m_key, m_key]
	if !ResourceLoader.exists(tex_path):
		var clean_key = m_key.rstrip("0123456789")
		tex_path = "res://assets/Actor/Monster/%s/SpriteSheet.png" % clean_key
		if !ResourceLoader.exists(tex_path):
			tex_path = "res://assets/Actor/Monster/%s/%s.png" % [clean_key, clean_key]
	if ResourceLoader.exists(tex_path):
		comp.sprite.texture = load(tex_path)


func _load_database():
	if !FileAccess.file_exists(DB_PATH):
		return
	var file = FileAccess.open(DB_PATH, FileAccess.READ)
	var json = JSON.new()
	var err = json.parse(file.get_as_text())
	if err == OK and json.data is Dictionary:
		player_database = json.data
		print("[Net] Loaded %d players from database" % player_database.size())


func _save_database():
	var file = FileAccess.open(DB_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(player_database, "\t"))
	print("[Net] Database saved (%d players)" % player_database.size())
