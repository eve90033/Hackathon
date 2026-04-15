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


func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_load_database()


func auto_connect():
	# Try to host first. If port is taken, join instead.
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PLAYERS)
	if err == OK:
		multiplayer.multiplayer_peer = peer
		players[1] = my_info.duplicate()
		print("[Net] Hosting on port %d" % PORT)
		connection_succeeded.emit()
	else:
		# Port taken = server already exists, join it
		print("[Net] Port taken, joining existing server...")
		peer = ENetMultiplayerPeer.new()
		err = peer.create_client(DEFAULT_HOST_IP, PORT)
		if err != OK:
			push_error("[Net] Failed to connect")
			return
		multiplayer.multiplayer_peer = peer


func _become_host():
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		push_error("[Net] Failed to create server: %s" % err)
		return
	multiplayer.multiplayer_peer = peer
	players[1] = my_info.duplicate()
	print("[Net] Hosting on port %d" % PORT)
	connection_succeeded.emit()


func host_game():
	_become_host()
	return OK


func join_game(address: String):
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client(address, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func _on_peer_connected(id: int):
	print("[Net] Peer connected: %d" % id)
	_register_player.rpc_id(id, my_info)


func _on_peer_disconnected(id: int):
	print("[Net] Peer disconnected: %d" % id)
	players.erase(id)
	player_disconnected.emit(id)


func _on_connected_to_server():
	print("[Net] Connected to server!")
	var my_id = multiplayer.get_unique_id()
	players[my_id] = my_info.duplicate()
	connection_succeeded.emit()


func _on_connection_failed():
	print("[Net] Join failed, becoming host...")
	multiplayer.multiplayer_peer = null
	_become_host()


func _on_server_disconnected():
	print("[Net] Server disconnected!")
	multiplayer.multiplayer_peer = null
	players.clear()
	server_disconnected.emit()


@rpc("any_peer", "reliable")
func _register_player(info: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	players[sender_id] = info
	print("[Net] Registered player %d: %s" % [sender_id, info.get("name", "?")])
	player_connected.emit(sender_id)


# --- Server-side login/save ---

@rpc("any_peer", "reliable")
func request_login(user_id: String):
	# Only server handles this
	if !multiplayer.is_server():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	print("[Net] Login request from peer %d, user_id=%s" % [sender_id, user_id])
	var data = player_database.get(user_id, {})
	_login_response.rpc_id(sender_id, user_id, data)


@rpc("authority", "reliable")
func _login_response(user_id: String, data: Dictionary):
	print("[Net] Login response: user_id=%s has_data=%s" % [user_id, !data.is_empty()])
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


func disconnect_from_game():
	multiplayer.multiplayer_peer = null
	players.clear()


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
