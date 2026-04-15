extends Node2D


@export var starting_map:PackedScene
@export var stating_weapon:ResourceWeapon

var map:Map
var network_character_scene = preload("res://system/network/network_character.tscn")

@onready var rain: GPUParticles2D = %Rain
@onready var snow: GPUParticles2D = %Snow
@onready var cloud: GPUParticles2D = %Cloud
@onready var leaf: GPUParticles2D = %Leaf
@onready var raylight: GPUParticles2D = %Raylight
@onready var fog: TextureRect = %Fog

@onready var transition: ColorRect = %Transition
@onready var music: AudioStreamPlayer = %Music
@onready var color_correction: ColorRect = %ColorCorrection
@onready var camera_grid: CameraGrid = %CameraGrid
@onready var pivot: Node2D = %Pivot
@onready var player_ui: Control = %PlayerUi
@onready var player_container: Node = %PlayerContainer


func _ready():
	generate_map(starting_map)
	camera_grid.animation_finished.connect(on_camera_animation_finished)

	# Multiplayer: connect signals and spawn local player
	if multiplayer.has_multiplayer_peer():
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)

		# Update our own entry with latest info (character selected after host_game)
		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()

		# Spawn ourselves
		_spawn_player(my_id)

		# If host, spawn existing peers (they connected before us entering world)
		if multiplayer.is_server():
			for pid in NetworkManager.players:
				if pid != 1:
					_spawn_player(pid)
	else:
		# Single player fallback: spawn Knight directly
		_spawn_single_player()


func _spawn_single_player():
	var character = network_character_scene.instantiate()
	character.peer_id = 1
	character.player_name = NetworkManager.my_info.get("name", "Player")
	character.character_key = NetworkManager.my_info.get("character", "Knight")
	character.name = "Player_1"
	player_container.add_child(character)
	camera_grid.target = character


func _spawn_player(peer_id: int):
	# Don't duplicate
	if player_container.has_node("Player_%d" % peer_id):
		return

	var info = NetworkManager.players.get(peer_id, NetworkManager.my_info)
	var character = network_character_scene.instantiate()
	character.peer_id = peer_id
	character.player_name = info.get("name", "Player")
	character.character_key = info.get("character", "Knight")
	character.name = "Player_%d" % peer_id
	character.position = Vector2(56, 53)  # Spawn point
	player_container.add_child(character)

	# If this is our character, attach camera
	if peer_id == multiplayer.get_unique_id():
		camera_grid.target = character


func _on_player_connected(peer_id: int):
	print("[World] Spawning player %d" % peer_id)
	_spawn_player(peer_id)


func _on_player_disconnected(peer_id: int):
	print("[World] Removing player %d" % peer_id)
	var node = player_container.get_node_or_null("Player_%d" % peer_id)
	if node:
		node.queue_free()


func _on_server_disconnected():
	# Go back to title
	get_tree().change_scene_to_file("res://main.tscn")


func on_camera_animation_finished():
	pivot.position = camera_grid.global_position


func generate_map(map_scene:PackedScene):
	if map:
		map.queue_free()
	map = starting_map.instantiate()
	add_child(map)
	map.environment_area.environment_changed.connect(apply_environment)


func apply_environment(resource_environment:ResourceEnvironment):
	# METEO
	if !resource_environment:
		return
	rain.emitting = ResourceEnvironment.Meteo.RAIN in resource_environment.meteo_list
	snow.emitting = ResourceEnvironment.Meteo.SNOW in resource_environment.meteo_list
	cloud.emitting = ResourceEnvironment.Meteo.CLOUD in resource_environment.meteo_list
	leaf.emitting = ResourceEnvironment.Meteo.LEAF in resource_environment.meteo_list
	fog.active = ResourceEnvironment.Meteo.FOG in resource_environment.meteo_list
	raylight.emitting = ResourceEnvironment.Meteo.RAY in resource_environment.meteo_list
	# MUSIC
	if resource_environment.music:
		music.change_music(resource_environment.music)
	else:
		music.stop_music()

	# GRADIENT
	color_correction.gradient = resource_environment.color_gradient


func play_transition(type:Transition.Type):
	transition
