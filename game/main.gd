extends Node


var current_scene: Node

var title_screen_scene = preload("res://content/menu/title_screen.tscn")
var login_screen_scene = preload("res://content/menu/login_screen.tscn")
var character_select_scene = preload("res://content/menu/character_select.tscn")
var world_scene = preload("res://world.tscn")


func _ready() -> void:
	add_to_group("main")
	_show_scene(title_screen_scene)


func _show_scene(packed_scene: PackedScene):
	if current_scene:
		current_scene.queue_free()
	current_scene = packed_scene.instantiate()
	add_child(current_scene)

	if current_scene.has_signal("login_completed"):
		current_scene.login_completed.connect(_on_login_completed)
	if current_scene.has_signal("character_created"):
		current_scene.character_created.connect(_on_character_created)


func _unhandled_input(event):
	if current_scene and current_scene.is_in_group("title_screen"):
		return
	# Title screen: any key → login
	if current_scene and current_scene.name == "TitleScreen":
		if event is InputEventKey and event.pressed:
			_show_scene(login_screen_scene)


func _on_login_completed():
	# No character found → show character creation
	_show_scene(character_select_scene)


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


func enter_world():
	_show_scene(world_scene)
