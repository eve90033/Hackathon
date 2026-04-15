extends Node2D


@export var starting_map:PackedScene
@export var stating_weapon:ResourceWeapon

var map:Map
var network_character_scene = preload("res://system/network/network_character.tscn")
var monster_scene = preload("res://system/character/monster_character.tscn")
var animal_scene = preload("res://system/character/animal.tscn")

const ANIMAL_BASE_PATH := "res://assets/Actor/Animal/"
const ALL_ANIMALS := [
	"Cat", "CatBlack", "CatCyclop", "CatOrange", "CatWhite",
	"Chicken", "Cow", "Dog", "Dog2", "DogBlack", "DogOrange", "DogYellow",
	"Donkey", "Fish", "Frog", "Hamster", "Horse", "Hyena", "Lion",
	"LionCub", "Lioness", "Monkey", "Parrot", "Pig", "Racoon", "WildBoar",
]

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
const MONSTER_BASE_PATH := "res://assets/Actor/Monster/"
const ALL_MONSTERS := [
	"Axolot", "AxolotBlue", "Bamboo", "BambooYellow", "Bear", "Beast", "Beast2",
	"BlueBat", "Butterfly", "ButterflyBlue", "Cyclope", "Cyclope2", "Dragon",
	"DragonYellow", "Eye", "Eye2", "Fish", "FishRed", "Flam", "Flam2",
	"GoldRacoon", "GreenOctopus", "Grey Trex", "HeartGreen", "HeartRed",
	"KappaGreen", "KappaRed", "LanternGreen", "LanternRed", "Larva", "Larva2",
	"Lizard", "Lizard2", "Mole", "Mole2", "Mollusc", "Mollusc2", "Mouse",
	"MouseBlack", "Mushroom", "Mushroom2", "Octopus", "Octopus2", "Owl", "Owl2",
	"Panda", "Racoon", "RedOctopus", "Reptile", "Reptile2", "Skull", "SkullBlue",
	"Slime", "Slime2", "Slime3", "Slime4", "Snake", "Snake2", "Snake3", "Snake4",
	"SpiderRed", "SpiderYellow", "Spirit", "Spirit2", "TRex", "YellowsBat",
]


func _enter_tree():
	# Must set spawn_function before _ready, per Godot docs
	var spawner = get_node_or_null("PlayerContainer/PlayerSpawner")
	if spawner:
		spawner.spawn_function = _spawn_player_func


func _ready():
	var is_server = NetworkManager.is_dedicated_server

	generate_map(starting_map)

	if !is_server:
		camera_grid.animation_finished.connect(on_camera_animation_finished)
		_setup_hud()
	else:
		# Server: disable all rendering
		rain.emitting = false
		snow.emitting = false
		cloud.emitting = false
		leaf.emitting = false
		raylight.emitting = false
		fog.visible = false
		music.stop()
		player_ui.visible = false
		transition.visible = false
		color_correction.visible = false

	# Spawn monsters
	_spawn_monsters()

	# Multiplayer: connect signals
	if multiplayer.has_multiplayer_peer():
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)

		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()

		if multiplayer.is_server():
			# Server: spawn any already connected peers
			var spawner = player_container.get_node("PlayerSpawner")
			for pid in NetworkManager.players:
				if pid != 1:
					spawner.spawn(pid)
		else:
			# Client: wait a frame then tell server we're ready
			get_tree().create_timer(1.5).timeout.connect(func():
				print("[World] Client sending _request_spawn, my_id=%d" % multiplayer.get_unique_id())
				_request_spawn.rpc_id(1)
			)
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
	# Load saved data (level, XP, companion)
	_load_player_data(character)
	# Wire HP UI
	if character.resource_life:
		player_ui.resource_life = character.resource_life


var _pending_local_setup := false

func _spawn_player_func(data) -> Node:
	# Called on ALL peers by MultiplayerSpawner
	var peer_id = int(data)
	var info = NetworkManager.players.get(peer_id, NetworkManager.my_info)
	var character = network_character_scene.instantiate()
	character.peer_id = peer_id
	character.player_name = info.get("name", "Player")
	character.character_key = info.get("character", "Knight")
	character.name = "Player_%d" % peer_id
	character.position = Vector2(56, 53)
	print("[World] Spawned Player_%d (%s) is_me=%s" % [peer_id, character.character_key, str(peer_id == multiplayer.get_unique_id())])
	if peer_id == multiplayer.get_unique_id():
		_pending_local_setup = true
	return character


func _setup_local_player(character):
	if !is_instance_valid(character):
		return
	camera_grid.target = character
	local_player = character
	if character.resource_life:
		player_ui.resource_life = character.resource_life
	_load_player_data(character)


@rpc("any_peer", "reliable")
func _request_spawn():
	if !multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	print("[World] Server received _request_spawn from peer %d" % sender)
	if player_container.has_node("Player_%d" % sender):
		print("[World] Player_%d already exists, skipping" % sender)
		return
	var spawner = player_container.get_node("PlayerSpawner")
	print("[World] Server spawning Player_%d via spawner" % sender)
	spawner.spawn(sender)


func _on_player_connected(peer_id: int):
	var info = NetworkManager.players.get(peer_id, {})
	print("[World] Player connected: peer=%d name=%s char=%s" % [peer_id, info.get("name","?"), info.get("character","?")])
	# Don't spawn here — wait for _request_spawn from client
	# (client sends it after their world is loaded)


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
	if NetworkManager.is_dedicated_server:
		return
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
var companion_face_icon:Node
var companion_face_key := ""
var save_timer := 0.0
var last_save_xp := 0
var last_save_level := 0
var last_save_companion := ""

func _process(_delta):
	if NetworkManager.is_dedicated_server:
		return

	# Find our character if not yet found
	if !local_player and multiplayer.has_multiplayer_peer():
		var my_id = multiplayer.get_unique_id()
		var children = player_container.get_children()
		var found_chars = []
		for child in children:
			if child is NetworkCharacter:
				found_chars.append("peer=%d auth=%d name=%s" % [child.peer_id, child.get_multiplayer_authority(), child.name])
				if child.peer_id == my_id:
					_setup_local_player(child)
					print("[World] LOCAL PLAYER FOUND: peer_id=%d my_id=%d" % [child.peer_id, my_id])
					break
		if !local_player and found_chars.size() > 0:
			if Engine.get_process_frames() % 60 == 0:
				print("[World] SEARCHING my_id=%d children=%s" % [my_id, str(found_chars)])

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

	# Auto-save check + sync peers
	save_timer += _delta
	if save_timer >= 2.0:
		save_timer = 0.0
		_auto_save()

	# Companion face: check for companion following local_player
	var current_comp_key := ""
	for node in get_tree().get_nodes_in_group("companion"):
		if node.target == local_player:
			current_comp_key = node.monster_key
			break
	if current_comp_key != companion_face_key:
		companion_face_key = current_comp_key
		if companion_face_icon and is_instance_valid(companion_face_icon):
			companion_face_icon.queue_free()
			companion_face_icon = null
		if companion_face_key != "":
			# Strip trailing digits: "Slime2" -> "Slime"
			var clean_key = companion_face_key.rstrip("0123456789")
			var fp = "res://assets/Actor/Monster/%s/Faceset.png" % clean_key
			if ResourceLoader.exists(fp):
				var tr = TextureRect.new()
				tr.texture = load(fp)
				tr.position = Vector2(3, 21)
				tr.scale = Vector2(0.37, 0.37)
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				hud_node.add_child(tr)
				companion_face_icon = tr


func _auto_save():
	if !local_player:
		return
	var cur_comp := ""
	for node in get_tree().get_nodes_in_group("companion"):
		if node.target == local_player:
			cur_comp = node.monster_key
			break
	# Only save if something changed
	if local_player.xp == last_save_xp and local_player.level == last_save_level and cur_comp == last_save_companion:
		return
	last_save_xp = local_player.xp
	last_save_level = local_player.level
	last_save_companion = cur_comp
	var user_id = NetworkManager.my_info.get("user_id", "")
	if user_id == "":
		return
	var save_data = {
		"level": local_player.level,
		"xp": local_player.xp,
		"companion": cur_comp,
	}
	if NetworkManager.is_host():
		NetworkManager.save_character(user_id, save_data)
	else:
		NetworkManager.save_character.rpc_id(1, user_id, save_data)


func _load_player_data(character:Character):
	var user_id = NetworkManager.my_info.get("user_id", "")
	if user_id == "":
		return
	var data = NetworkManager.player_database.get(user_id, {})
	# Restore level + XP
	if data.has("level"):
		character.level = data["level"]
		character.attack_damage = character.ATK_PER_LEVEL[character.level - 1]
	if data.has("xp"):
		character.xp = data["xp"]
	if character.resource_life and data.has("level"):
		character.resource_life.max_life = character.HP_PER_LEVEL[character.level - 1]
		character.resource_life.life = character.resource_life.max_life
	# Restore companion
	if data.has("companion") and data["companion"] != "":
		_restore_companion(character, data["companion"])
	# Sync save state so auto-save doesn't overwrite with defaults
	last_save_level = character.level
	last_save_xp = character.xp
	last_save_companion = data.get("companion", "")
	save_timer = 0.0


func _restore_companion(owner:Node2D, monster_key:String):
	var comp_scene = preload("res://system/companion/companion.tscn")
	var comp = comp_scene.instantiate()
	comp.global_position = owner.global_position + Vector2(16, 16)
	comp.target = owner
	comp.monster_key = monster_key
	add_child(comp)
	# Find sprite texture
	var clean_key = monster_key.rstrip("0123456789")
	var tex_path = "res://assets/Actor/Monster/%s/SpriteSheet.png" % clean_key
	if !ResourceLoader.exists(tex_path):
		tex_path = "res://assets/Actor/Monster/%s/%s.png" % [clean_key, clean_key]
	if !ResourceLoader.exists(tex_path):
		tex_path = "res://assets/Actor/Monster/%s/%s.png" % [clean_key, clean_key.to_lower()]
	if ResourceLoader.exists(tex_path):
		comp.sprite.texture = load(tex_path)


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


func _spawn_animals():
	var center := Vector2(56, 53)
	var count := ALL_ANIMALS.size()
	for i in count:
		var key = ALL_ANIMALS[i]
		var animal = animal_scene.instantiate()
		animal.name = "Animal_" + key
		# Scatter around village
		var angle = (i / float(count)) * TAU
		var radius = 30.0 + randf() * 60.0
		animal.position = center + Vector2(cos(angle), sin(angle)) * radius
		add_child(animal)
		# Set texture
		var tex_path = ANIMAL_BASE_PATH + key + "/SpriteSheet.png"
		if ResourceLoader.exists(tex_path):
			animal.sprite.texture = load(tex_path)


func _spawn_monsters():
	var spawn_center := Vector2(56, 53)  # Player spawn
	var village_min := Vector2(-160, -88)  # Village grid cell bounds
	var village_max := Vector2(160, 88)
	var ring_radius := 200.0  # Start outside village
	var count := ALL_MONSTERS.size()

	for i in count:
		var key = ALL_MONSTERS[i]
		var monster = monster_scene.instantiate()
		monster.name = key

		# Spread in expanding spiral
		var ring = i / 12  # 12 monsters per ring
		var angle = (i % 12) * (TAU / 12) + ring * 0.5
		var radius = ring_radius + ring * 80.0
		var pos = spawn_center + Vector2(cos(angle), sin(angle)) * radius
		# Push out of village cell
		if pos.x > village_min.x and pos.x < village_max.x and pos.y > village_min.y and pos.y < village_max.y:
			var dir = (pos - spawn_center).normalized()
			pos = spawn_center + dir * (ring_radius + 50)
		monster.position = pos

		# Stats scale with distance from center
		var tier = mini(ring, 2)  # 0=weak, 1=medium, 2=strong
		monster.max_hp = [3, 5, 10][tier]
		monster.contact_damage = [1, 2, 3][tier]
		monster.speed = [45, 55, 60][tier]
		monster.detection_range = [70, 90, 100][tier]
		monster.xp_value = [10, 25, 50][tier]
		monster.monster_key = key

		add_child(monster)

		# Find sprite texture
		var tex_path = MONSTER_BASE_PATH + key + "/SpriteSheet.png"
		if !ResourceLoader.exists(tex_path):
			tex_path = MONSTER_BASE_PATH + key + "/" + key + ".png"
		if !ResourceLoader.exists(tex_path):
			# Try lowercase
			tex_path = MONSTER_BASE_PATH + key + "/" + key.to_lower() + ".png"
		if ResourceLoader.exists(tex_path):
			monster.sprite.texture = load(tex_path)

		# Update detection area radius
		var detect_shape = monster.get_node("DetectionArea/DetectionShape")
		if detect_shape and detect_shape.shape:
			detect_shape.shape = detect_shape.shape.duplicate()
			detect_shape.shape.radius = monster.detection_range



func play_transition(type:Transition.Type):
	transition
