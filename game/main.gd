extends Node


var world: Node
var overlay: Node
var overlay_layer: CanvasLayer

var login_screen_scene = preload("res://content/menu/login_screen.tscn")
var character_select_scene = preload("res://content/menu/character_select.tscn")
var world_scene = preload("res://world.tscn")


func _ready() -> void:
	add_to_group("main")

	# Always load world first — spawner must be in scene tree before peers connect
	world = world_scene.instantiate()
	add_child(world)

	# Persistent overlay layer for login/character select UI
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 10
	overlay_layer.name = "OverlayLayer"
	add_child(overlay_layer)

	if "--server" in OS.get_cmdline_user_args():
		_start_dedicated_server()
	elif "--auto-skip" in OS.get_cmdline_user_args():
		get_tree().create_timer(0.5).timeout.connect(_auto_enter_world)
	else:
		# Hide world visuals during login (including CanvasLayers)
		_set_world_visible(false)
		_show_overlay(login_screen_scene)


func _show_overlay(packed_scene: PackedScene):
	# Remove old overlay content
	if overlay:
		overlay.queue_free()
		overlay = null

	overlay = packed_scene.instantiate()
	overlay_layer.add_child(overlay)
	overlay_layer.visible = true

	if overlay.has_signal("login_completed"):
		overlay.login_completed.connect(_on_login_completed)
	if overlay.has_signal("character_created"):
		overlay.character_created.connect(_on_character_created)


func _remove_overlay():
	if overlay:
		overlay.queue_free()
		overlay = null
	overlay_layer.visible = false


func _unhandled_input(_event):
	pass


func _on_login_completed():
	# No character found → show character creation
	_show_overlay(character_select_scene)


func _on_character_created(player_name: String, character_name: String):
	NetworkManager.my_info.name = player_name
	NetworkManager.my_info.character = character_name

	# Save to server
	var user_id = NetworkManager.my_info.user_id
	var save_data = { "name": player_name, "character": character_name }
	if NetworkManager.is_host():
		NetworkManager.player_database[user_id] = save_data
		NetworkManager._save_database()
	else:
		NetworkManager.save_character.rpc_id(1, user_id, save_data)

	# Update players dict and broadcast
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
	# Auto-test mode: join existing server
	NetworkManager.my_info.name = "TestPlayer"
	NetworkManager.my_info.character = "Knight"
	var err = NetworkManager.join_game(NetworkManager.server_url)
	if err != OK:
		# No server, host ourselves
		NetworkManager.host_game()
	# Wait for connection before entering world
	if !multiplayer.is_server():
		await NetworkManager.connection_succeeded
	world.setup_multiplayer()


func _set_world_visible(v: bool):
	world.visible = v
	world.set_process(v)
	# CanvasLayers don't respect parent visibility — toggle them manually
	for child in world.get_children():
		if child is CanvasLayer:
			child.visible = v


func enter_world():
	_remove_overlay()
	_set_world_visible(true)
	# Start with black screen, fade out after player spawns
	var transition = world.get_node_or_null("ScreenFxLayer/Transition")
	if transition:
		transition.modulate.a = 1.0
	world.setup_multiplayer()
	# Fade out after player is ready (delay for spawn)
	get_tree().create_timer(2.5).timeout.connect(func():
		if transition:
			transition.play(Transition.Type.FADE_OUT)
	)
