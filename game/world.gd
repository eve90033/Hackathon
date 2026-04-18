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
# 怪物中文名（寶可夢風格，3~5字，根據實際圖片命名）
const MONSTER_NAMES := {
	"Axolot": "火六鰓", "AxolotBlue": "冰六鰓", "Bamboo": "竹筒蟲", "BambooYellow": "金筒蟲",
	"Bear": "暴怒熊", "Beast": "赤角獸", "Beast2": "翠角獸", "BlueBat": "冰翼蝠",
	"Butterfly": "焰粉蝶", "ButterflyBlue": "冰晶蝶", "Cyclope": "赤獨眼", "Cyclope2": "翠獨眼",
	"Dragon": "綠龍仔", "DragonYellow": "橙龍仔", "Eye": "藍浮眼", "Eye2": "赤浮眼",
	"Fish": "綠泡魚", "FishRed": "赤眼魚", "Flam": "烈焰靈", "Flam2": "寒冰靈",
	"GoldRacoon": "金浣熊", "GreenOctopus": "翠觸手", "Grey Trex": "骨暴龍",
	"HeartGreen": "綠咬咬", "HeartRed": "紅咬咬", "KappaGreen": "翠河童", "KappaRed": "赤河童",
	"LanternGreen": "翠燈怪", "LanternRed": "赤燈怪", "Larva": "花毛蟲", "Larva2": "藍甲蟲",
	"Lizard": "草蜥蜴", "Lizard2": "岩蜥蜴", "Mole": "赤地鼠", "Mole2": "藍地鼠",
	"Mollusc": "菇菇龜", "Mollusc2": "花菇龜", "Mouse": "圓耳鼠", "MouseBlack": "黑耳鼠",
	"Mushroom": "紅蘑菇", "Mushroom2": "藍蘑菇", "Octopus": "綠水母", "Octopus2": "藍水母",
	"Owl": "火焰鴞", "Owl2": "暗夜鴞", "Panda": "圓眼熊", "Racoon": "赤浣熊",
	"RedOctopus": "赤觸手", "Reptile": "藍甲龍", "Reptile2": "翠甲龍",
	"Skull": "赤骷髏", "SkullBlue": "冰骷髏", "Slime": "藍史萊", "Slime2": "綠史萊",
	"Slime3": "白史萊", "Slime4": "金史萊", "Snake": "赤圓蛇", "Snake2": "橙圓蛇",
	"Snake3": "翠圓蛇", "Snake4": "紅圓蛇", "SpiderRed": "赤蜘蛛", "SpiderYellow": "金蜘蛛",
	"Spirit": "藍水滴", "Spirit2": "赤水滴", "TRex": "黃暴龍", "YellowsBat": "金翼蝠",
}

# 動物中文名
const ANIMAL_NAMES := {"Pig": "粉豬豬"}

# NPC 中文名
const NPC_NAMES := {"Guard": "車手阿志", "ChenChimney": "陳煙囪", "WangKaiming": "王巨螺"}

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


var _multiplayer_setup_done := false

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
	# 生成武器架
	_spawn_weapon_racks()
	# 生成村莊裝飾（動物 + NPC）
	_spawn_animals()
	_spawn_npcs()
	# 怪物分區視覺提示
	if !is_server:
		_spawn_zone_indicator()

	# Note: multiplayer setup is deferred to setup_multiplayer()
	# called by main.gd after connection is established.
	# This ensures the spawner is in the scene tree before peers connect.


func setup_multiplayer():
	if _multiplayer_setup_done:
		return
	_multiplayer_setup_done = true

	if multiplayer.has_multiplayer_peer():
		NetworkManager.player_connected.connect(_on_player_connected)
		NetworkManager.player_disconnected.connect(_on_player_disconnected)
		NetworkManager.server_disconnected.connect(_on_server_disconnected)

		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()
		NetworkManager.flog("[World] setup_multiplayer: my_id=%d is_server=%s players=%s" % [my_id, str(multiplayer.is_server()), str(NetworkManager.players.keys())])

		if multiplayer.is_server():
			# Server: spawn any already connected peers
			var spawner = player_container.get_node("PlayerSpawner")
			for pid in NetworkManager.players:
				if pid != 1:
					var pinfo = NetworkManager.players.get(pid, {})
					spawner.spawn({"peer_id": pid, "name": pinfo.get("name", "Player"), "character": pinfo.get("character", "Knight")})
		else:
			# Client: wait then tell server we're ready
			get_tree().create_timer(1.5).timeout.connect(func():
				NetworkManager.flog("[World] Client sending _request_spawn, my_id=%d" % multiplayer.get_unique_id())
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
	_hook_save_events(character)
	# Wire HP UI
	if character.resource_life:
		player_ui.resource_life = character.resource_life


var _pending_local_setup := false

func _spawn_player_func(data) -> Node:
	# Called on ALL peers by MultiplayerSpawner
	# data is a Dictionary: { "peer_id":int, "name":String, "character":String }
	var peer_id: int
	var pname: String
	var char_key: String
	if data is Dictionary:
		peer_id = int(data.get("peer_id", 0))
		pname = data.get("name", "Player")
		char_key = data.get("character", "Knight")
	else:
		# Fallback for old-style int data
		peer_id = int(data)
		var info = NetworkManager.players.get(peer_id, NetworkManager.my_info)
		pname = info.get("name", "Player")
		char_key = info.get("character", "Knight")

	var character = network_character_scene.instantiate()
	character.peer_id = peer_id
	character.player_name = pname
	character.character_key = char_key
	character.name = "Player_%d" % peer_id
	character.position = Vector2(659, -675)  # 出生房間（地圖內有建好的房間 tile）
	character.spawn_position = Vector2(17, -147)  # 死後重生在村莊內
	# Server is source of truth: apply saved level/HP on our copy so pickup
	# heal / damage calcs use the correct cap. We deferred-call it because
	# `_ready` (which sets default max_life=5) runs after instantiate completes.
	if multiplayer.is_server() and data is Dictionary:
		var user_id := ""
		var pinfo = NetworkManager.players.get(peer_id, {})
		if pinfo is Dictionary:
			user_id = pinfo.get("user_id", "")
		if user_id != "":
			var save = NetworkManager.player_database.get(user_id, {})
			if save.has("level") and save["level"] > 1:
				character.call_deferred("_apply_server_restore", save)
	NetworkManager.flog("[World] _spawn_player_func: peer=%d char=%s is_me=%s" % [peer_id, char_key, str(peer_id == multiplayer.get_unique_id())])
	if peer_id == multiplayer.get_unique_id():
		_pending_local_setup = true
	return character


func _setup_local_player(character):
	if !is_instance_valid(character):
		return
	NetworkManager.flog("[World] _setup_local_player: before pos=%s" % str(character.global_position))
	# 確保出生在正確位置（出生房間 → 走出後入村莊）
	character.global_position = Vector2(659, -675)
	character.spawn_position = Vector2(17, -147)  # 死後重生在村莊內
	camera_grid.target = character
	camera_grid.teleport_to(character.global_position)
	local_player = character
	NetworkManager.flog("[World] _setup_local_player: after pos=%s" % str(character.global_position))
	if character.resource_life:
		player_ui.resource_life = character.resource_life
	_load_player_data(character)
	_hook_save_events(character)
	_show_tutorial_hints()
	# 向 server 請求武器架狀態同步
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		_request_rack_sync.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_spawn():
	if !multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	NetworkManager.flog("[World] Server received _request_spawn from peer %d" % sender)
	if player_container.has_node("Player_%d" % sender):
		NetworkManager.flog("[World] Player_%d already exists, skipping" % sender)
		return
	var spawner = player_container.get_node("PlayerSpawner")
	var info = NetworkManager.players.get(sender, {})
	NetworkManager.flog("[World] Server spawning Player_%d via spawner, char=%s" % [sender, info.get("character", "?")])
	spawner.spawn({"peer_id": sender, "name": info.get("name", "Player"), "character": info.get("character", "Knight")})
	# MultiplayerSpawner replicates Player nodes but NOT companion state, so late
	# joiners don't see existing players' companions. Re-broadcast from server's
	# saved data. Defer via Timer (NOT await) so this RPC handler returns
	# immediately — awaiting inside an RPC handler turns it into a Coroutine
	# that can stall Godot 4's MultiplayerAPI dispatch for other peers.
	var t := get_tree().create_timer(1.0)
	t.timeout.connect(_send_existing_companions_to.bind(sender), CONNECT_ONE_SHOT)
	# Also send current positions of all existing players to the new joiner.
	# Background-throttled web peers may broadcast at ~1 Hz, so late joiners
	# relying on StateSync alone stay at initial (659,-675) until a throttled
	# peer sends its next tick. Server already has the cached position from
	# its own StateSync copy — push it directly to the new peer as a seed.
	var t2 := get_tree().create_timer(1.0)
	t2.timeout.connect(_send_existing_player_positions_to.bind(sender), CONNECT_ONE_SHOT)


func _send_existing_companions_to(target_peer: int) -> void:
	if !is_instance_valid(self):
		return
	for pid in NetworkManager.players.keys():
		if pid == 1 or pid == target_peer:
			continue
		var pinfo = NetworkManager.players.get(pid, {})
		var user_id: String = pinfo.get("user_id", "") if pinfo is Dictionary else ""
		if user_id == "":
			continue
		var save: Dictionary = NetworkManager.player_database.get(user_id, {})
		var comp_key: String = save.get("companion", "")
		if comp_key == "":
			continue
		var captor_name := "Player_%d" % pid
		NetworkManager.flog("[World] Sending companion %s for %s to peer %d" % [comp_key, captor_name, target_peer])
		NetworkManager.sync_companion.rpc_id(target_peer, captor_name, comp_key, 0)


func _send_existing_player_positions_to(target_peer: int) -> void:
	## Server-only: tell the new joiner where each existing player currently is.
	## Bypasses the StateSync catch-up race for background-throttled peers.
	if !is_instance_valid(self):
		return
	if !multiplayer.is_server():
		return
	for child in player_container.get_children():
		if not (child is NetworkCharacter):
			continue
		if child.peer_id == target_peer:
			continue  # skip the new joiner's own character
		var pos = child.global_position
		NetworkManager.flog("[World] Seeding pos of Player_%d (%.0f,%.0f) to peer %d" % [child.peer_id, pos.x, pos.y, target_peer])
		_rpc_seed_player_position.rpc_id(target_peer, child.peer_id, pos.x, pos.y)


@rpc("authority", "reliable", "call_remote")
func _rpc_seed_player_position(peer_id: int, x: float, y: float) -> void:
	## Received by a late-joining client: force the initial position of an
	## existing peer's character to the server's cached value. This avoids
	## waiting for a possibly-throttled StateSync broadcast to arrive.
	var char_node = player_container.get_node_or_null("Player_%d" % peer_id)
	if !char_node or !is_instance_valid(char_node):
		return
	char_node.global_position = Vector2(x, y)
	var ti = char_node.get_node_or_null("TickInterp")
	if ti and ti.has_method("teleport"):
		ti.teleport()


func _on_player_connected(peer_id: int):
	var info = NetworkManager.players.get(peer_id, {})
	print("[World] Player connected: peer=%d name=%s char=%s" % [peer_id, info.get("name","?"), info.get("character","?")])
	# Don't spawn here — wait for _request_spawn from client
	# (client sends it after their world is loaded)


func _on_player_disconnected(peer_id: int):
	print("[World] Removing player %d" % peer_id)
	var node = player_container.get_node_or_null("Player_%d" % peer_id)
	# Clean up orphan companions BEFORE freeing the target, so any
	# `companion.target == node` check still works.
	for comp in get_tree().get_nodes_in_group("companion"):
		if comp.target == node:
			comp.queue_free()
	if node:
		node.queue_free()


func _on_server_disconnected():
	# Go back to title
	get_tree().change_scene_to_file("res://main.tscn")


# --- Tab-switch recovery (web browsers throttle rAF while a tab is hidden,
# so sync packets pile up in the WebSocket queue and replay as a "history
# rewind" when the tab resumes. With Netfox we tell TickInterp.teleport() on
# every synced entity to skip the interpolation-catchup animation.)

var _tab_was_hidden := false

func _notification(what:int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_tab_was_hidden = true
			_handle_tab_hide()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _tab_was_hidden:
				_tab_was_hidden = false
				_handle_tab_resume()


func _handle_tab_hide() -> void:
	# Browser throttles backgrounded tabs to ~1 Hz. Local player's
	# _physics_process slows accordingly; any held input keeps applying with
	# huge delta → big position jumps visible to other peers. Proactively
	# disable the HumanController + zero velocity so broadcast state stays
	# still while hidden.
	if NetworkManager.is_dedicated_server:
		return
	if local_player and is_instance_valid(local_player):
		local_player.move_vector = Vector2.ZERO
		local_player.velocity = Vector2.ZERO
		for child in local_player.get_children():
			if child is HumanController:
				child.active = false


func _handle_tab_resume() -> void:
	if NetworkManager.is_dedicated_server:
		return
	# Re-enable HumanController so input works again
	if local_player and is_instance_valid(local_player):
		for child in local_player.get_children():
			if child is HumanController:
				child.active = true
	# Let StateSync drain queued packets and apply them first.
	await get_tree().process_frame
	await get_tree().process_frame
	_snap_all_to_targets()


func _snap_all_to_targets() -> void:
	# Teleport all TickInterpolators so they don't slide from stale snapshot
	# to freshly-applied StateSync values post-tab-resume.
	var candidates: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		candidates.append(p)
	for m in get_tree().get_nodes_in_group("monster"):
		candidates.append(m)
	for child in get_children():
		if child is NPCCharacter or child.name.begins_with("Animal_"):
			candidates.append(child)
	for node in candidates:
		if not is_instance_valid(node):
			continue
		var ti = node.get_node_or_null("TickInterp")
		if ti:
			ti.teleport()


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

	# === Face portrait 36x36 ===
	var face_border = ColorRect.new()
	face_border.color = Color(0.4, 0.3, 0.2)
	face_border.position = Vector2(6, 6)
	face_border.size = Vector2(36, 36)
	hud_node.add_child(face_border)

	# === Bars right of face ===
	var bx := 50.0
	var by := 6.0
	var bar_w := 84.0
	var bar_h := 7.0

	# --- Level label ---
	level_label = _make_label("Lv1", Vector2(bx, by - 2), Color(1.0, 0.9, 0.5))
	hud_node.add_child(level_label)

	# --- HP Bar ---
	var hp_y := by + 16

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

	hp_label = _make_label("", Vector2(bx + bar_w + 4, hp_y - 4), Color.WHITE)
	hud_node.add_child(hp_label)

	# --- XP Bar ---
	var xp_y := hp_y + bar_h + 4

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

	xp_label = _make_label("", Vector2(bx + bar_w + 4, xp_y - 4), Color(1.0, 0.9, 0.5))
	hud_node.add_child(xp_label)


func _make_label(text:String, pos:Vector2, color:Color) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# Explicitly apply NotoSansTC font (HUD is on CanvasLayer, doesn't inherit theme)
	var cjk_font = load("res://theme/NotoSansTC-Regular.ttf")
	if cjk_font:
		lbl.add_theme_font_override("font", cjk_font)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	return lbl


var face_loaded := false
var companion_face_icon:Node
var companion_face_label:Label
var companion_face_key := ""
var save_timer := 0.0
var last_save_xp := 0
var last_save_level := 0
var last_save_companion := ""
var last_save_weapon := "club"

# 新手引導
var _tutorial_shown_enter := false
var _tutorial_shown_attack := false
var _tutorial_shown_capture := false

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
					NetworkManager.flog("[World] LOCAL PLAYER FOUND: peer_id=%d my_id=%d pos=%s" % [child.peer_id, my_id, str(child.global_position)])
					break
		if !local_player and found_chars.size() > 0:
			if Engine.get_process_frames() % 30 == 0:
				NetworkManager.flog("[World] SEARCHING my_id=%d children=%s" % [my_id, str(found_chars)])
		elif !local_player:
			if Engine.get_process_frames() % 60 == 0:
				var child_count = player_container.get_child_count()
				NetworkManager.flog("[World] NO CHARS YET my_id=%d child_count=%d" % [my_id, child_count])

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
			tr.position = Vector2(8, 8)
			# Scale 38px faceset to fill 32px area (inside 36px border)
			tr.scale = Vector2(0.84, 0.84)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			hud_node.add_child(tr)
			face_icon = tr
			face_loaded = true

	var bar_w := 84.0

	# Level
	if level_label:
		level_label.text = "Lv%d" % local_player.level

	# HP bar
	if hp_bar and local_player.resource_life:
		var display_max = local_player.HP_PER_LEVEL[local_player.level - 1]
		var ratio = local_player.resource_life.life / float(display_max)
		hp_bar.size.x = bar_w * ratio
		hp_label.text = "%d/%d" % [local_player.resource_life.life, display_max]

	# XP bar
	if xp_bar:
		if local_player.level < 10:
			var xp_max = local_player.XP_TABLE[local_player.level]
			var xp_ratio = local_player.xp / float(xp_max) if xp_max > 0 else 1.0
			xp_bar.size.x = bar_w * min(xp_ratio, 1.0)
			xp_label.text = "%d/%d" % [local_player.xp, xp_max]
		else:
			xp_bar.size.x = bar_w
			xp_label.text = "MAX"

	# 新手引導檢查
	_check_tutorial_triggers()

	# Auto-save polling：5 秒兜底檢查（關鍵事件會用 signal 立即存）
	save_timer += _delta
	if save_timer >= 5.0:
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
		# 同伴變動立即觸發存檔
		_on_save_trigger()
		if companion_face_icon and is_instance_valid(companion_face_icon):
			companion_face_icon.queue_free()
			companion_face_icon = null
		if companion_face_label and is_instance_valid(companion_face_label):
			companion_face_label.queue_free()
			companion_face_label = null
		if companion_face_key != "":
			# Try exact key first, then fallback without trailing digits
			var fp = "res://assets/Actor/Monster/%s/Faceset.png" % companion_face_key
			if !ResourceLoader.exists(fp):
				var clean_key = companion_face_key.rstrip("0123456789")
				fp = "res://assets/Actor/Monster/%s/Faceset.png" % clean_key
			if ResourceLoader.exists(fp):
				# 同伴頭像（24x24，跟通知頭像差不多大）
				var tr = TextureRect.new()
				tr.texture = load(fp)
				tr.position = Vector2(6, 48)
				tr.custom_minimum_size = Vector2(20, 20)
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				hud_node.add_child(tr)
				companion_face_icon = tr
				# 同伴中文名
				var cn_name = MONSTER_NAMES.get(companion_face_key, companion_face_key)
				var lbl = Label.new()
				lbl.text = cn_name
				var cjk_font = load("res://theme/NotoSansTC-Regular.ttf")
				if cjk_font:
					lbl.add_theme_font_override("font", cjk_font)
				lbl.add_theme_font_size_override("font_size", 14)
				lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
				lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
				lbl.add_theme_constant_override("shadow_offset_x", 1)
				lbl.add_theme_constant_override("shadow_offset_y", 1)
				lbl.position = Vector2(50, 48)
				hud_node.add_child(lbl)
				companion_face_label = lbl


@rpc("any_peer", "reliable")
func _request_rack_sync():
	## Server 端：把所有武器架的當前狀態發給請求者
	if !multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var rack_states := {}
	for rack in get_tree().get_nodes_in_group("weapon_rack"):
		if rack is WeaponRack:
			var key = rack._get_weapon_key(rack.weapon_resource)
			rack_states[rack.name] = key
	_receive_rack_sync.rpc_id(sender, rack_states)


@rpc("authority", "reliable")
func _receive_rack_sync(states: Dictionary):
	## Client 端：收到武器架狀態，更新顯示
	for rack_name in states:
		var rack = get_tree().root.find_child(rack_name, true, false)
		if rack and rack is WeaponRack:
			var weapon_key = states[rack_name]
			var path = NetworkCharacter.WEAPON_PATHS.get(weapon_key, "")
			if path != "" and ResourceLoader.exists(path):
				rack.weapon_resource = load(path)
				if rack.sprite:
					rack.sprite.texture = rack.weapon_resource.sprite
			else:
				rack.weapon_resource = null
				if rack.sprite:
					rack.sprite.texture = null


func _show_tutorial_hints():
	# 首次進入地圖的提示
	var ui = get_node_or_null("/root/UIManager")
	if !ui:
		return
	# 延遲顯示，等轉場完成
	get_tree().create_timer(3.0).timeout.connect(func():
		if ui:
			ui.push_notify("走出村莊探索世界！", Color(0.8, 0.9, 1.0), 3.0)
	)


func _check_tutorial_triggers():
	# 在 _process 裡呼叫，檢查一次性提示
	if !local_player or NetworkManager.is_dedicated_server:
		return
	var ui = get_node_or_null("/root/UIManager")
	if !ui:
		return

	# 首次靠近怪物
	if !_tutorial_shown_attack:
		for m in get_tree().get_nodes_in_group("monster"):
			if m is MonsterCharacter and m.ai_state != MonsterCharacter.AIState.DEAD:
				if local_player.global_position.distance_to(m.global_position) < 80:
					_tutorial_shown_attack = true
					ui.push_notify("按 Z 攻擊！", Color(1.0, 0.8, 0.3), 2.5)
					break

	# 首次怪物瀕死（可收服）
	if !_tutorial_shown_capture and _tutorial_shown_attack:
		for m in get_tree().get_nodes_in_group("monster"):
			if m is MonsterCharacter and m.is_capturable:
				if local_player.global_position.distance_to(m.global_position) < 80:
					_tutorial_shown_capture = true
					ui.push_notify("按 C 收服！", Color(0.3, 1.0, 0.5), 3.0)
					break


func _hook_save_events(character):
	## 關鍵事件立即存檔，不等 polling
	if character.leveled_up.is_connected(_on_save_trigger):
		return
	character.leveled_up.connect(_on_save_trigger)
	if character is NetworkCharacter:
		if !character.weapon_changed.is_connected(_on_save_trigger):
			character.weapon_changed.connect(_on_save_trigger)


func _on_save_trigger(_unused = null):
	# 下一個 frame 觸發存檔（確保相關狀態已經更新完成，例如 HP/同伴）
	call_deferred("_auto_save")


func _auto_save():
	if !local_player:
		return
	var cur_comp := ""
	for node in get_tree().get_nodes_in_group("companion"):
		if node.target == local_player:
			cur_comp = node.monster_key
			break
	# 取得當前武器
	var cur_weapon := "club"
	if local_player is NetworkCharacter:
		cur_weapon = local_player.current_weapon_key
	# Only save if something changed
	if local_player.xp == last_save_xp and local_player.level == last_save_level and cur_comp == last_save_companion and cur_weapon == last_save_weapon:
		return
	last_save_xp = local_player.xp
	last_save_level = local_player.level
	last_save_companion = cur_comp
	last_save_weapon = cur_weapon
	var user_id = NetworkManager.my_info.get("user_id", "")
	if user_id == "":
		return
	var save_data = {
		"level": local_player.level,
		"xp": local_player.xp,
		"companion": cur_comp,
		"weapon": cur_weapon,
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
	# Server-side restore (world._spawn_player_func → _apply_server_restore)
	# takes authority for this. We only apply locally for instant UI; server's
	# RPC will override if out of sync.
	# Restore weapon
	if data.has("weapon") and data["weapon"] != "club" and character is NetworkCharacter:
		character.change_weapon(data["weapon"])
	# Restore companion
	if data.has("companion") and data["companion"] != "":
		_restore_companion(character, data["companion"])
		# Also broadcast to other peers — they didn't see our original capture.
		# Without this, the saved companion is only visible on our own screen.
		if multiplayer.has_multiplayer_peer():
			NetworkManager.sync_companion.rpc(character.name, data["companion"], 0)
	# Sync save state so auto-save doesn't overwrite with defaults
	last_save_level = character.level
	last_save_xp = character.xp
	last_save_companion = data.get("companion", "")
	last_save_weapon = data.get("weapon", "club")
	save_timer = 0.0


func _restore_companion(owner:Node2D, monster_key:String):
	var comp_scene = preload("res://system/companion/companion.tscn")
	var comp = comp_scene.instantiate()
	comp.global_position = owner.global_position + Vector2(16, 16)
	comp.target = owner
	comp.monster_key = monster_key
	add_child(comp)
	# Find sprite texture — try exact key first, then fallback without trailing digits
	var tex_path = "res://assets/Actor/Monster/%s/SpriteSheet.png" % monster_key
	if !ResourceLoader.exists(tex_path):
		tex_path = "res://assets/Actor/Monster/%s/%s.png" % [monster_key, monster_key]
	if !ResourceLoader.exists(tex_path):
		var clean_key = monster_key.rstrip("0123456789")
		tex_path = "res://assets/Actor/Monster/%s/SpriteSheet.png" % clean_key
		if !ResourceLoader.exists(tex_path):
			tex_path = "res://assets/Actor/Monster/%s/%s.png" % [clean_key, clean_key]
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
	# 村莊裝飾動物，散佈在不同區域
	var animal_data = [
		{"key": "Pig", "pos": Vector2(-34, -189), "sprite": "SpriteSheetPink.png"},
	]
	for data in animal_data:
		var animal = animal_scene.instantiate()
		animal.name = "Animal_" + data["key"]
		animal.position = data["pos"]
		add_child(animal)
		# 動物不顯示名字
		var sprite_name = data.get("sprite", "SpriteSheet.png")
		var tex_path = ANIMAL_BASE_PATH + data["key"] + "/" + sprite_name
		if ResourceLoader.exists(tex_path):
			animal.sprite.texture = load(tex_path)
		# Pig 特殊 AI：跟隨玩家 + 愛心表情
		if data["key"] == "Pig":
			var pig_ai = Node.new()
			pig_ai.set_script(preload("res://system/character/pig_ai.gd"))
			animal.add_child(pig_ai)


func _spawn_npcs():
	# 村莊 NPC，散佈在村莊不同角落（純本地裝飾，不同步多人）
	var npc_scene = preload("res://system/character/npc_character.tscn")
	var npc_configs = [
		# 車手阿志：村莊南側，左右巡邏
		{"name": "Guard", "character": "Caveman", "pos": Vector2(-31, -105),
		 "patrol": [Vector2(-70, -105), Vector2(10, -105)]},
		# 陳煙囪：村莊東南側，小範圍來回（跟王開明站一起聊天）
		{"name": "ChenChimney", "character": "Noble", "pos": Vector2(120, -95),
		 "patrol": [Vector2(115, -98), Vector2(127, -92)],
		 "shout": "那邊有低能兒"},
		# 王巨螺：村莊東南側，小範圍來回（跟陳煙囪站一起）
		{"name": "WangKaiming", "character": "Sultan", "pos": Vector2(143, -95),
		 "patrol": [Vector2(139, -98), Vector2(151, -92)],
		 "shout": "龍哥好帥帥喔"},
		# 楊總統：村莊中央廣場，來回走動，只顯示憤怒表情
		{"name": "President", "character": "Villager", "pos": Vector2(-31, -145),
		 "patrol": [Vector2(-60, -145), Vector2(0, -145)],
		 "display_name": "楊總統", "shout": "賴祥德我是不會屈服的",
		 "emotes": [3, 4, 10, 15, 21, 22], "emote_interval": 4.0},
	]
	for config in npc_configs:
		var npc = npc_scene.instantiate()
		npc.name = "NPC_" + config["name"]
		npc.position = config["pos"]
		npc.character_key = config["character"]
		npc.patrol_points.assign(config["patrol"])
		if config.has("emotes"):
			npc.emote_pool.assign(config["emotes"])
		if config.has("emote_interval"):
			npc.emote_interval = config["emote_interval"]
		add_child(npc)
		# NPC 名字
		var display = config.get("display_name", NPC_NAMES.get(config["name"], config["name"]))
		preload("res://system/ui/screen_label.gd").create(npc, display, 14, Color(0.4, 0.8, 1.0), Vector2(0, -18))
		# 持續喊話
		if config.has("shout"):
			_start_npc_shout(npc, config["shout"])


func _start_npc_shout(npc: Node2D, text: String):
	# 每 4 秒用聊天氣泡喊話
	var timer = Timer.new()
	timer.wait_time = 4.0
	timer.autostart = true
	npc.add_child(timer)
	timer.timeout.connect(func():
		if is_instance_valid(npc):
			var _ChatBubbleScript = preload("res://system/ui/chat_bubble.gd")
			var bubble = Node2D.new()
			bubble.set_script(_ChatBubbleScript)
			npc.add_child(bubble)
			bubble.show_message(text)
	)
	# 第一次立即喊
	var bubble = Node2D.new()
	bubble.set_script(preload("res://system/ui/chat_bubble.gd"))
	npc.add_child(bubble)
	bubble.show_message(text)


func _spawn_monsters():
	var spawn_center := Vector2(-31, -129)  # 村莊中心（怪物圍繞此點展開）
	# 禁止怪物出現的區域
	var safe_zones := [
		Rect2(-160, -220, 280, 180),     # 村莊建築區（含重生點緩衝）
		Rect2(-60, -790, 900, 670),      # 出生點→村莊走廊（無怪路徑）
	]
	var ring_radius := 200.0  # 起始半徑
	var count := ALL_MONSTERS.size()

	for i in count:
		var key = ALL_MONSTERS[i]
		var monster = monster_scene.instantiate()
		monster.name = key

		# Spread in expanding spiral; strong tier gets pushed further so
		# players can't bump into HP 10 enemies right at village edge.
		var ring = i / 12  # 12 monsters per ring
		var tier = mini(ring, 2)  # 0=weak, 1=medium, 2=strong
		var tier_offset = [0, 0, 120][tier]
		var angle = (i % 12) * (TAU / 12) + ring * 0.5
		var radius = ring_radius + ring * 80.0 + tier_offset
		var pos = spawn_center + Vector2(cos(angle), sin(angle)) * radius
		# 確保不在安全區域內
		for safe in safe_zones:
			if safe.has_point(pos):
				var dir = (pos - safe.get_center()).normalized()
				if dir.length() < 0.1:
					dir = Vector2.RIGHT
				pos = safe.get_center() + dir * (safe.size.length() * 0.6 + 50)
		# 確保不在障礙物上（嘗試偏移最多 5 次）
		pos = _find_clear_position(pos)
		# 限制在地圖邊界內
		pos.x = clamp(pos.x, -460.0, 830.0)
		pos.y = clamp(pos.y, -780.0, 460.0)
		monster.position = pos

		# Stats scale with distance from center
		monster.max_hp = [3, 5, 10][tier]
		monster.contact_damage = [1, 2, 3][tier]
		monster.speed = [45, 55, 60][tier]
		monster.detection_range = [70, 90, 100][tier]
		monster.xp_value = [10, 25, 50][tier]
		monster.behavior_type = tier  # 0=BASIC, 1=DASH, 2=FLANK
		monster.monster_key = key
		monster.monster_tier = tier

		add_child(monster)

		# 怪物名字標籤
		var cn_name = MONSTER_NAMES.get(key, key)
		var name_color = [Color(0.6, 1.0, 0.6), Color(1.0, 0.9, 0.4), Color(1.0, 0.5, 0.4)][tier]
		var _sl = preload("res://system/ui/screen_label.gd")
		_sl.create(monster, cn_name, 14, name_color, Vector2(0, -18))

		# Find sprite texture — try several naming patterns
		var tex_path = MONSTER_BASE_PATH + key + "/SpriteSheet.png"
		if !ResourceLoader.exists(tex_path):
			tex_path = MONSTER_BASE_PATH + key + "/" + key + ".png"
		if !ResourceLoader.exists(tex_path):
			tex_path = MONSTER_BASE_PATH + key + "/" + key.to_lower() + ".png"
		if !ResourceLoader.exists(tex_path):
			# key 含空白或特殊字元，嘗試去除空白
			var clean_key = key.replace(" ", "")
			tex_path = MONSTER_BASE_PATH + key + "/" + clean_key + ".png"
		if ResourceLoader.exists(tex_path):
			monster.sprite.texture = load(tex_path)
		else:
			push_warning("[Spawn] Monster %s has no loadable texture at %s" % [key, tex_path])

		# Update detection area radius
		var detect_shape = monster.get_node("DetectionArea/DetectionShape")
		if detect_shape and detect_shape.shape:
			detect_shape.shape = detect_shape.shape.duplicate()
			detect_shape.shape.radius = monster.detection_range

	# 生成 Boss
	var boss_scene = preload("res://system/character/boss_character.tscn")
	var boss = boss_scene.instantiate()
	boss.name = "Boss_GiantFrog"
	boss.position = Vector2(-31, -700)  # 村莊北方遠處
	add_child(boss)


func _spawn_weapon_racks():
	# 武器散布在地圖各地，越強的越遠
	var rack_configs = [
		# 弱怪區（村莊附近）— 快速武器
		{"name": "bone", "res": "res://content/weapon/bone/bone.tres",
		 "pos": Vector2(-90, -90)},    # 村莊南方出口
		# 村莊內 — 遠程武器（方便新手試用）
		{"name": "book0", "res": "res://content/weapon/book/book.tres",
		 "pos": Vector2(10, -160)},    # 村莊內東北角
		# 弱怪區（村莊東側）— 遠程武器
		{"name": "book", "res": "res://content/weapon/book/book.tres",
		 "pos": Vector2(120, -180)},   # 村莊東側草地
		# 中怪區 — 大劍
		{"name": "big_sword", "res": "res://content/weapon/big_sword/big_sword.tres",
		 "pos": Vector2(-200, -350)},  # 西北方中怪區
		# 中怪區 — 斧頭（另一側）
		{"name": "axe", "res": "res://content/weapon/axe/axe.tres",
		 "pos": Vector2(200, -350)},   # 東北方中怪區
		# 強怪區 — 額外一把斧頭（靠近 Boss）
		{"name": "axe2", "res": "res://content/weapon/axe/axe.tres",
		 "pos": Vector2(-31, -550)},   # Boss 前方
	]
	for config in rack_configs:
		var rack = StaticBody2D.new()
		rack.set_script(preload("res://system/weapon/weapon_rack.gd"))
		rack.name = "WeaponRack_" + config["name"]
		rack.position = config["pos"]
		rack.weapon_resource = load(config["res"])
		rack.add_to_group("weapon_rack")
		add_child(rack)


func _is_position_blocked(tilemap: TileMap, pos: Vector2) -> bool:
	## 檢查位置是否在 TileMap 障礙物上
	for ox in [-8, 0, 8]:
		for oy in [-8, 0, 8]:
			var local_pos = (pos + Vector2(ox, oy)) - tilemap.position
			var cell = tilemap.local_to_map(local_pos)
			for layer in tilemap.get_layers_count():
				var tile_data = tilemap.get_cell_tile_data(layer, cell)
				if tile_data:
					for pl in tilemap.tile_set.get_physics_layers_count():
						if tile_data.get_collision_polygons_count(pl) > 0:
							return true
	return false


func _find_clear_position(pos: Vector2) -> Vector2:
	## 找到附近沒有障礙物的位置
	var tilemap = map.get_node_or_null("Tilemap") as TileMap
	if !tilemap:
		return pos
	if !_is_position_blocked(tilemap, pos):
		return pos
	# 嘗試 8 個方向，逐步增加距離
	var directions = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
		Vector2(1,1).normalized(), Vector2(1,-1).normalized(),
		Vector2(-1,1).normalized(), Vector2(-1,-1).normalized(),
	]
	for dist in [24, 48, 72, 96]:
		for dir in directions:
			var test_pos = pos + dir * dist
			if !_is_position_blocked(tilemap, test_pos):
				return test_pos
	# 全部失敗，回傳原始位置
	print("[Spawn] WARNING: 無法找到空地 pos=%s" % str(pos))
	return pos


func _spawn_zone_indicator():
	var zone_script = preload("res://system/ui/zone_indicator.gd")
	var zone = Node2D.new()
	zone.set_script(zone_script)
	zone.name = "ZoneIndicator"
	add_child(zone)


func play_transition(type:Transition.Type):
	transition
