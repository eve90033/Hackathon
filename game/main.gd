extends Node


var world: Node
var overlay: Node
var overlay_layer: CanvasLayer
var loading_label: Label

var character_select_scene = preload("res://content/menu/character_select.tscn")
var world_scene = preload("res://world.tscn")

const USER_ID_PATH := "user://user_id.txt"


func _ready() -> void:
	add_to_group("main")

	# Always load world first — spawner must be in scene tree before peers connect
	world = world_scene.instantiate()
	add_child(world)

	# Persistent overlay layer for character select + loading UI
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 10
	overlay_layer.name = "OverlayLayer"
	add_child(overlay_layer)

	if "--server" in OS.get_cmdline_user_args():
		_start_dedicated_server()
	elif "--auto-skip" in OS.get_cmdline_user_args():
		get_tree().create_timer(0.5).timeout.connect(_auto_enter_world)
	else:
		_set_world_visible(false)
		_show_loading_screen()
		_auto_login()


func _show_loading_screen():
	var ctrl = Control.new()
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(ctrl)

	var bg = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0.06, 0.07, 0.14, 1.0)
	ctrl.add_child(bg)

	loading_label = Label.new()
	loading_label.text = "連線中..."
	loading_label.anchor_left = 0.5
	loading_label.anchor_top = 0.5
	loading_label.anchor_right = 0.5
	loading_label.anchor_bottom = 0.5
	loading_label.offset_left = -200
	loading_label.offset_top = -30
	loading_label.offset_right = 200
	loading_label.offset_bottom = 30
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var cjk_font = load("res://theme/NotoSansTC-Regular.ttf")
	if cjk_font:
		loading_label.add_theme_font_override("font", cjk_font)
	loading_label.add_theme_font_size_override("font_size", 22)
	loading_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	ctrl.add_child(loading_label)

	overlay = ctrl
	overlay_layer.visible = true


func _set_loading_text(text: String):
	if loading_label and is_instance_valid(loading_label):
		loading_label.text = text


func _remove_loading_screen():
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
		overlay = null
	loading_label = null


func _show_overlay(packed_scene: PackedScene):
	if overlay:
		overlay.queue_free()
		overlay = null
	loading_label = null

	overlay = packed_scene.instantiate()
	overlay_layer.add_child(overlay)
	overlay_layer.visible = true

	if overlay.has_signal("character_created"):
		overlay.character_created.connect(_on_character_created)


func _remove_overlay():
	if overlay:
		overlay.queue_free()
		overlay = null
	overlay_layer.visible = false


func _auto_login():
	var user_id = _get_or_create_user_id()
	NetworkManager.my_info.user_id = user_id
	NetworkManager.flog("[Main] Auto-login user_id=%s" % user_id)

	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.login_response.connect(_on_login_response)
	NetworkManager.kicked_by_new_session.connect(_on_kicked_by_new_session)

	_set_loading_text("連線中...")
	var err = NetworkManager.join_game(NetworkManager.server_url)
	if err != OK:
		_set_loading_text("連線失敗，嘗試本機模式...")
		NetworkManager.flog("[Main] join_game failed, trying auto_connect")
		NetworkManager.auto_connect()


func _get_or_create_user_id() -> String:
	# CLI override (local testing: let multiple clients coexist with distinct IDs)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--user-id="):
			return arg.substr("--user-id=".length())

	# Web: read/write localStorage via JavaScriptBridge
	if OS.has_feature("web"):
		var window = JavaScriptBridge.get_interface("window")
		if window != null:
			var storage = window.localStorage
			var existing = storage.getItem("monster_rpg_user_id")
			print("[Main] localStorage.getItem -> ", existing, " (type=", typeof(existing), ")")
			if existing != null and str(existing) != "" and str(existing) != "null":
				return str(existing)
			# Generate new UUID-ish ID
			var new_id = _generate_uuid_string()
			storage.setItem("monster_rpg_user_id", new_id)
			print("[Main] Created new user_id and stored: ", new_id)
			return new_id
		push_warning("[Main] JavaScriptBridge.get_interface failed")

	# Desktop fallback: save to user:// file
	if FileAccess.file_exists(USER_ID_PATH):
		var f = FileAccess.open(USER_ID_PATH, FileAccess.READ)
		if f:
			var id = f.get_as_text().strip_edges()
			f.close()
			if not id.is_empty():
				return id

	# Generate new UUID-like ID and persist
	var new_id = _generate_uuid_string()
	var fw = FileAccess.open(USER_ID_PATH, FileAccess.WRITE)
	if fw:
		fw.store_string(new_id)
		fw.close()
	return new_id


func _generate_uuid_string() -> String:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return "%08x-%04x-%04x-%04x-%012x" % [
		rng.randi(), rng.randi() & 0xFFFF, rng.randi() & 0xFFFF,
		rng.randi() & 0xFFFF, rng.randi()
	]


func _on_connected():
	_set_loading_text("載入角色資料...")
	var my_id = multiplayer.get_unique_id()
	NetworkManager.flog("[Main] _on_connected: my_id=%d is_host=%s" % [my_id, str(NetworkManager.is_host())])
	var user_id = NetworkManager.my_info.user_id
	if NetworkManager.is_host():
		NetworkManager.login_as_host(user_id)
	else:
		NetworkManager.request_login.rpc_id(1, user_id)


func _on_connection_failed():
	_set_loading_text("連線失敗，請重新整理頁面")


func _on_kicked_by_new_session():
	# 被踢時：暫停遊戲 + 顯示全螢幕覆蓋提示
	NetworkManager.flog("[Main] Kicked by new session")
	get_tree().paused = true
	_show_kicked_overlay()


func _show_kicked_overlay():
	# 清掉既有 overlay
	if overlay and is_instance_valid(overlay):
		overlay.queue_free()
	loading_label = null

	var ctrl = Control.new()
	ctrl.anchor_right = 1.0
	ctrl.anchor_bottom = 1.0
	ctrl.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay_layer.add_child(ctrl)

	var bg = ColorRect.new()
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = Color(0, 0, 0, 0.85)
	ctrl.add_child(bg)

	var vbox = VBoxContainer.new()
	vbox.anchor_left = 0.5
	vbox.anchor_top = 0.5
	vbox.anchor_right = 0.5
	vbox.anchor_bottom = 0.5
	vbox.offset_left = -260
	vbox.offset_top = -90
	vbox.offset_right = 260
	vbox.offset_bottom = 90
	vbox.add_theme_constant_override("separation", 20)
	ctrl.add_child(vbox)

	var cjk_font = load("res://theme/NotoSansTC-Regular.ttf")

	var title = Label.new()
	title.text = "你在其他地方登入了"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cjk_font:
		title.add_theme_font_override("font", cjk_font)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.7, 0.3))
	vbox.add_child(title)

	var hint = Label.new()
	hint.text = "此視窗已被中斷連線。\n要繼續玩請重新整理頁面 (F5)。"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if cjk_font:
		hint.add_theme_font_override("font", cjk_font)
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	vbox.add_child(hint)

	overlay = ctrl
	overlay_layer.visible = true


func _on_login_response(user_id: String, data: Dictionary):
	NetworkManager.flog("[Main] _on_login_response user_id=%s has_data=%s" % [user_id, !data.is_empty()])
	if data.is_empty():
		# 新玩家 → 進創角
		_remove_loading_screen()
		_show_overlay(character_select_scene)
	else:
		# 舊玩家 → 直接進遊戲
		NetworkManager.my_info.name = data.get("name", "Player")
		NetworkManager.my_info.character = data.get("character", "Knight")
		# 快取完整存檔資料，讓 _load_player_data 能取用 level/xp/companion/weapon
		NetworkManager.player_database[user_id] = data.duplicate()
		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()
		NetworkManager._register_player.rpc(NetworkManager.my_info)
		_set_loading_text("歡迎回來，%s！" % NetworkManager.my_info.name)
		await get_tree().create_timer(0.5).timeout
		enter_world()


func _unhandled_input(_event):
	pass


func _on_character_created(player_name: String, character_name: String):
	NetworkManager.my_info.name = player_name
	NetworkManager.my_info.character = character_name

	var user_id = NetworkManager.my_info.user_id
	var save_data = { "name": player_name, "character": character_name }
	if NetworkManager.is_host():
		NetworkManager.player_database[user_id] = save_data
		NetworkManager._save_database()
	else:
		NetworkManager.save_character.rpc_id(1, user_id, save_data)

	var my_id = multiplayer.get_unique_id()
	NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()
	NetworkManager._register_player.rpc(NetworkManager.my_info)

	enter_world()


func _start_dedicated_server():
	print("[Server] Starting dedicated server...")
	NetworkManager.is_dedicated_server = true
	NetworkManager.host_game()
	world.setup_multiplayer()
	print("[Server] World loaded, waiting for players on port %d" % NetworkManager.PORT)


func _auto_enter_world():
	NetworkManager.my_info.name = "TestPlayer"
	NetworkManager.my_info.character = "Knight"
	var err = NetworkManager.join_game(NetworkManager.server_url)
	if err != OK:
		NetworkManager.host_game()
	if !multiplayer.is_server():
		await NetworkManager.connection_succeeded
	world.setup_multiplayer()


func _set_world_visible(v: bool):
	world.visible = v
	world.set_process(v)
	for child in world.get_children():
		if child is CanvasLayer:
			child.visible = v


func enter_world():
	_remove_overlay()
	_set_world_visible(true)
	var transition = world.get_node_or_null("ScreenFxLayer/Transition")
	if transition:
		transition.modulate.a = 1.0
	world.setup_multiplayer()
	get_tree().create_timer(2.5).timeout.connect(func():
		if transition:
			transition.play(Transition.Type.FADE_OUT)
	)
