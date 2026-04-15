extends Node2D


@export var starting_map:PackedScene
@export var stating_weapon:ResourceWeapon

var map:Map
var network_character_scene = preload("res://system/network/network_character.tscn")
var monster_scene = preload("res://system/character/monster_character.tscn")

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

var hud_label:Label
var local_player:Character

# Monster spawn definitions: [texture_path, position, hp, damage, speed, detection, xp]
const MONSTER_SPAWNS := [
	# Weak zone — east of spawn
	{"key": "Slime", "tex": "res://assets/Actor/Monster/Slime/Slime.png", "pos": Vector2(250, 80), "hp": 3, "dmg": 1, "spd": 45, "det": 70, "xp": 10},
	{"key": "Slime2", "tex": "res://assets/Actor/Monster/Slime/Slime.png", "pos": Vector2(280, 40), "hp": 3, "dmg": 1, "spd": 45, "det": 70, "xp": 10},
	{"key": "Slime3", "tex": "res://assets/Actor/Monster/Slime/Slime.png", "pos": Vector2(230, 130), "hp": 3, "dmg": 1, "spd": 45, "det": 70, "xp": 10},
	{"key": "Racoon", "tex": "res://assets/Actor/Monster/Racoon/SpriteSheet.png", "pos": Vector2(300, 100), "hp": 3, "dmg": 1, "spd": 50, "det": 80, "xp": 10},
	{"key": "Racoon2", "tex": "res://assets/Actor/Monster/Racoon/SpriteSheet.png", "pos": Vector2(320, 50), "hp": 3, "dmg": 1, "spd": 50, "det": 80, "xp": 10},
	# Medium zone — northeast
	{"key": "Dragon", "tex": "res://assets/Actor/Monster/Dragon/SpriteSheet.png", "pos": Vector2(400, -80), "hp": 5, "dmg": 2, "spd": 55, "det": 90, "xp": 25},
	{"key": "Dragon2", "tex": "res://assets/Actor/Monster/Dragon/SpriteSheet.png", "pos": Vector2(450, -40), "hp": 5, "dmg": 2, "spd": 55, "det": 90, "xp": 25},
	# Strong zone — west
	{"key": "Eye", "tex": "res://assets/Actor/Monster/Eye/Eye.png", "pos": Vector2(-200, -130), "hp": 8, "dmg": 2, "spd": 60, "det": 100, "xp": 50},
	{"key": "Eye2", "tex": "res://assets/Actor/Monster/Eye/Eye.png", "pos": Vector2(-230, -100), "hp": 8, "dmg": 2, "spd": 60, "det": 100, "xp": 50},
]


func _ready():
	generate_map(starting_map)
	camera_grid.animation_finished.connect(on_camera_animation_finished)

	# HUD
	_setup_hud()

	# Spawn monsters
	_spawn_monsters()

	# Multiplayer: connect signals and spawn local player
	if multiplayer.has_multiplayer_peer():
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)

		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()

		_spawn_player(my_id)

		if multiplayer.is_server():
			for pid in NetworkManager.players:
				if pid != 1:
					_spawn_player(pid)
	else:
		_spawn_single_player()


func _spawn_single_player():
	var character = network_character_scene.instantiate()
	character.peer_id = 1
	character.player_name = NetworkManager.my_info.get("name", "Player")
	character.character_key = NetworkManager.my_info.get("character", "Knight")
	character.name = "Player_1"
	player_container.add_child(character)
	camera_grid.target = character
	local_player = character
	# Wire HP UI
	if character.resource_life:
		player_ui.resource_life = character.resource_life


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

	# If this is our character, attach camera + UI
	if peer_id == multiplayer.get_unique_id():
		camera_grid.target = character
		local_player = character
		# Wire HP UI after character is ready
		character.ready.connect(func():
			if character.resource_life:
				player_ui.resource_life = character.resource_life
		)


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


var hud_node:Control
var face_icon:Node
var level_label:Label
var hp_bar:ColorRect
var hp_bar_bg:ColorRect
var hp_label:Label
var xp_bar:ColorRect
var xp_bar_bg:ColorRect
var xp_label:Label

func _setup_hud():
	# Hide default heart receptacle
	var receptacle = player_ui.get_node_or_null("ReceptacleBar")
	if receptacle:
		receptacle.visible = false

	hud_node = Control.new()
	hud_node.name = "HUD"
	player_ui.add_child(hud_node)

	# === Face portrait 16x16 ===
	var face_border = ColorRect.new()
	face_border.color = Color(0.4, 0.3, 0.2)
	face_border.position = Vector2(2, 2)
	face_border.size = Vector2(16, 16)
	hud_node.add_child(face_border)

	# === Bars right of face ===
	var bx := 22.0
	var by := 2.0
	var bar_w := 36.0
	var bar_h := 3.0

	# --- Level label ---
	level_label = _make_label("Lv1", Vector2(bx, by - 1), Color(1.0, 0.9, 0.5))
	hud_node.add_child(level_label)

	# --- HP Bar ---
	var hp_y := by + 7

	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.15, 0.08, 0.08)
	hp_bar_bg.position = Vector2(bx, hp_y)
	hp_bar_bg.size = Vector2(bar_w, bar_h)
	hud_node.add_child(hp_bar_bg)

	hp_bar = ColorRect.new()
	hp_bar.color = Color(0.85, 0.2, 0.15)
	hp_bar.position = Vector2(bx, hp_y)
	hp_bar.size = Vector2(bar_w, bar_h)
	hud_node.add_child(hp_bar)

	hp_label = _make_label("", Vector2(bx + bar_w + 2, hp_y - 2), Color.WHITE)
	hud_node.add_child(hp_label)

	# --- XP Bar ---
	var xp_y := hp_y + bar_h + 2

	xp_bar_bg = ColorRect.new()
	xp_bar_bg.color = Color(0.1, 0.08, 0.02)
	xp_bar_bg.position = Vector2(bx, xp_y)
	xp_bar_bg.size = Vector2(bar_w, bar_h)
	hud_node.add_child(xp_bar_bg)

	xp_bar = ColorRect.new()
	xp_bar.color = Color(0.9, 0.75, 0.15)
	xp_bar.position = Vector2(bx, xp_y)
	xp_bar.size = Vector2(0, bar_h)
	hud_node.add_child(xp_bar)

	xp_label = _make_label("", Vector2(bx + bar_w + 2, xp_y - 2), Color(1.0, 0.9, 0.5))
	hud_node.add_child(xp_label)


func _make_label(text:String, pos:Vector2, color:Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", 6)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	return lbl


var face_loaded := false

func _process(_delta):
	if !local_player:
		return

	# Load face once when player is ready
	if !face_loaded and local_player.character_key:
		var face_path = "res://assets/Actor/Character/%s/Faceset.png" % local_player.character_key
		if ResourceLoader.exists(face_path):
			if face_icon and is_instance_valid(face_icon):
				face_icon.queue_free()
			var tr = TextureRect.new()
			tr.texture = load(face_path)
			tr.position = Vector2(3, 3)
			# Scale 38px faceset down to ~14px
			tr.scale = Vector2(0.37, 0.37)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hud_node.add_child(tr)
			face_icon = tr
			face_loaded = true

	var bar_w := 36.0

	# Level
	if level_label:
		level_label.text = "Lv%d" % local_player.level

	# HP bar
	if hp_bar and local_player.resource_life:
		var ratio = local_player.resource_life.life / float(local_player.resource_life.max_life)
		hp_bar.size.x = bar_w * ratio
		hp_label.text = "%d/%d" % [local_player.resource_life.life, local_player.resource_life.max_life]

	# XP bar
	if xp_bar:
		if local_player.level < 4:
			var xp_max = local_player.XP_TABLE[local_player.level]
			var xp_ratio = local_player.xp / float(xp_max) if xp_max > 0 else 1.0
			xp_bar.size.x = bar_w * min(xp_ratio, 1.0)
			xp_label.text = "%d/%d" % [local_player.xp, xp_max]
		else:
			xp_bar.size.x = bar_w
			xp_label.text = "MAX"


func _set_face(character_key:String):
	var face_path = "res://assets/Actor/Character/%s/Faceset.png" % character_key
	if !ResourceLoader.exists(face_path):
		return
	if face_icon and is_instance_valid(face_icon):
		face_icon.queue_free()
		face_icon = null
	# TextureRect: set ALL properties including texture BEFORE add_child
	var tr = TextureRect.new()
	tr.texture = load(face_path)
	tr.custom_minimum_size = Vector2(14, 14)
	tr.size = Vector2(14, 14)
	tr.position = Vector2(3, 3)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hud_node.add_child(tr)
	face_icon = tr


func _spawn_monsters():
	for data in MONSTER_SPAWNS:
		var monster = monster_scene.instantiate()
		monster.name = data["key"]
		monster.position = data["pos"]
		monster.max_hp = data["hp"]
		monster.contact_damage = data["dmg"]
		monster.speed = data["spd"]
		monster.detection_range = data["det"]
		monster.xp_value = data["xp"]
		monster.monster_key = data["key"]
		add_child(monster)
		# Set sprite texture after adding to tree
		var tex = load(data["tex"])
		if tex:
			monster.sprite.texture = tex
		# Update detection area radius
		var detect_shape = monster.get_node("DetectionArea/DetectionShape")
		if detect_shape and detect_shape.shape:
			detect_shape.shape = detect_shape.shape.duplicate()
			detect_shape.shape.radius = data["det"]


func play_transition(type:Transition.Type):
	transition
