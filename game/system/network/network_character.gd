extends Character
class_name NetworkCharacter


signal weapon_changed(weapon_key: String)


const CHARACTERS_PATH := "res://assets/Actor/Character/"
const WEAPON_SCENE := preload("res://system/weapon/weapon.tscn")
const CLUB_RESOURCE := preload("res://content/weapon/club/club.tres")
const PLAYER_TEAM := preload("res://content/team/player_team.tres")

# 武器路徑對照表（用於多人同步）
const WEAPON_PATHS := {
	"club": "res://content/weapon/club/club.tres",
	"axe": "res://content/weapon/axe/axe.tres",
	"big_sword": "res://content/weapon/big_sword/big_sword.tres",
	"bone": "res://content/weapon/bone/bone.tres",
	"book": "res://content/weapon/book/book.tres",
}
var current_weapon_key := "club"

var peer_id := 1
var player_name := "Player":
	set(v):
		player_name = v
		if is_inside_tree():
			var lbl = get_node_or_null("NameLabel")
			if lbl:
				lbl.text = player_name
			if _name_screen_label:
				_name_screen_label.text = player_name
var character_key := "Knight":
	set(v):
		character_key = v
		if is_inside_tree() and sprite:
			var p = CHARACTERS_PATH + character_key + "/SpriteSheet.png"
			if ResourceLoader.exists(p):
				sprite.texture = load(p)

@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var name_label: Label = $NameLabel

# CanvasLayer 名字標籤（在螢幕空間渲染，不受 viewport 縮放影響）
var _name_canvas: CanvasLayer
var _name_screen_label: Label


func _enter_tree():
	# Must set authority in _enter_tree, not _ready (MultiplayerSpawner requirement)
	if peer_id > 0:
		set_multiplayer_authority(peer_id)


func _ready():
	# Init snapshot target so remote peers don't lerp from (0,0)
	target_position = global_position

	# Apply character skin
	var sprite_path = CHARACTERS_PATH + character_key + "/SpriteSheet.png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	# Name label (hidden world-space label kept for compat)
	name_label.text = player_name
	_setup_screen_name_label()

	# Setup combat: weapon + life
	_setup_combat()

	# All player characters need to be detectable by monsters (layer 5 + group)
	add_to_group("player")
	set_collision_layer_value(5, true)
	# Don't get pushed by monsters
	set_collision_mask_value(2, false)

	if is_multiplayer_authority():
		# This is our character: add input + camera
		var human_controller = HumanController.new()
		add_child(human_controller)
	elif NetworkManager.is_dedicated_server:
		# Dedicated server: disable hitbox for remote players
		# (monster damage to player is handled client-side)
		if hitbox:
			hitbox.monitorable = false

	# Call parent _ready for hitbox wiring + SFX
	super._ready()


func _setup_screen_name_label():
	# 在獨立的 CanvasLayer 渲染名字，避免 viewport 縮放造成模糊
	_name_canvas = CanvasLayer.new()
	_name_canvas.layer = 5
	add_child(_name_canvas)

	_name_screen_label = Label.new()
	_name_screen_label.text = player_name
	var cjk_font = load("res://theme/NotoSansTC-Regular.ttf")
	if cjk_font:
		_name_screen_label.add_theme_font_override("font", cjk_font)
	_name_screen_label.add_theme_font_size_override("font_size", 14)
	_name_screen_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	_name_screen_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_name_screen_label.add_theme_constant_override("shadow_offset_x", 2)
	_name_screen_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_screen_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_screen_label.size = Vector2(200, 30)
	_name_canvas.add_child(_name_screen_label)


func _process(_delta):
	_update_screen_name_pos()


func _update_screen_name_pos():
	if !_name_screen_label or !is_inside_tree():
		return
	# 把角色世界座標轉成螢幕座標
	var cam = get_viewport().get_camera_2d()
	if !cam:
		_name_screen_label.visible = false
		return
	var viewport_size = get_viewport().get_visible_rect().size
	var canvas_transform = get_viewport().get_canvas_transform()
	var screen_pos = canvas_transform * (global_position + Vector2(0, -16))
	_name_screen_label.position = Vector2(screen_pos.x - 100, screen_pos.y - 15)
	_name_screen_label.visible = true


func _exit_tree():
	if _name_canvas and is_instance_valid(_name_canvas):
		_name_canvas.queue_free()


func _setup_combat():
	# Life system
	resource_life = ResourceLife.new()
	resource_life.max_life = 5
	resource_life.life = 5

	# Team
	team = PLAYER_TEAM
	if hitbox:
		hitbox.team = PLAYER_TEAM

	# Weapon
	var weapon = WEAPON_SCENE.instantiate()
	weapon.resource_weapon = CLUB_RESOURCE
	weapon.team = PLAYER_TEAM
	add_child(weapon)
	weapon_node = weapon

	# Hit feedback: connect weapon DamageArea hit
	weapon.damage_area.area_entered.connect(_on_weapon_hit)


var _remote_prev_state := State.IDLE

func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		# Remote player: drive animation from synced state + smoothly interpolate
		# visible position toward authority's target_position. No client physics —
		# that was fighting the position packets and causing the freeze/jitter.
		if state == State.ATTACK and _remote_prev_state != State.ATTACK:
			sprite.anim = SpriteCharacter.Anim.ATTACK
			if weapon_node:
				weapon_node.direction = sprite.direction
				weapon_node.state = Weapon.State.ATTACK
		elif state != State.ATTACK and _remote_prev_state == State.ATTACK:
			if weapon_node:
				weapon_node.state = Weapon.State.BACK
		_remote_prev_state = state

		match state:
			State.ATTACK:
				sprite.anim = SpriteCharacter.Anim.ATTACK
			State.DEAD:
				sprite.anim = SpriteCharacter.Anim.DEAD
			_:
				if move_vector.length():
					sprite.anim = SpriteCharacter.Anim.MOVING
					sprite.direction = move_vector.normalized()
				else:
					sprite.anim = SpriteCharacter.Anim.IDLE

		# Snapshot interpolation toward authority's target
		var to_target = target_position - global_position
		if to_target.length() > 256.0:
			# Teleport / respawn — snap, don't slide across the map
			global_position = target_position
		else:
			global_position = global_position.lerp(target_position, clamp(delta * 15.0, 0.0, 1.0))
		return

	# Local player: full combat physics, then publish snapshot for others
	super._physics_process(delta)
	target_position = global_position


func _on_weapon_hit(_area):
	if !is_multiplayer_authority():
		return
	# Hit-stop: pause local character physics only (not global Engine.time_scale)
	set_physics_process(false)
	get_tree().create_timer(0.05).timeout.connect(
		func(): set_physics_process(true)
	)


# --- Server-authoritative HP ---

func take_hit(damage_amount:int, from_pos:Vector2):
	if !multiplayer.has_multiplayer_peer():
		super.take_hit(damage_amount, from_pos)
		return
	if !is_multiplayer_authority():
		return
	NetworkManager.flog("[Player] take_hit called! dmg=%d from=%s" % [damage_amount, str(from_pos)])
	# Find which monster is attacking near us
	var monster_name := ""
	for m in get_tree().get_nodes_in_group("monster"):
		if !(m is MonsterCharacter):
			continue
		if m.ai_state == MonsterCharacter.AIState.ATTACK:
			if m.global_position.distance_to(global_position) < 40:
				monster_name = m.name
				break
	NetworkManager.flog("[Player] sending _rpc_player_hit monster=%s" % monster_name)
	_rpc_player_hit.rpc_id(1, monster_name, from_pos)


@rpc("any_peer", "reliable")
func _rpc_player_hit(monster_name: String, from_pos: Vector2):
	NetworkManager.flog("[Server] _rpc_player_hit received! monster=%s peer=%d node=%s" % [monster_name, multiplayer.get_remote_sender_id(), name])
	if !multiplayer.is_server():
		return
	# Server: look up monster's contact_damage
	var dmg = 1  # default
	if monster_name != "":
		var world = get_parent().get_parent()  # PlayerContainer -> World
		if world:
			var monster = world.get_node_or_null(monster_name)
			if monster and monster is MonsterCharacter:
				dmg = monster.contact_damage
	# Apply damage to this player's HP on server
	if resource_life:
		resource_life.damage(dmg)
		var new_hp = resource_life.life
		var new_max = resource_life.max_life
		var is_dead = !resource_life.is_alive()
		_rpc_hp_update.rpc_id(peer_id, new_hp, new_max, is_dead, from_pos)


@rpc("any_peer", "reliable")
func _rpc_hp_update(new_hp: int, new_max: int, is_dead: bool, from_pos: Vector2):
	NetworkManager.flog("[Client] _rpc_hp_update received! hp=%d/%d dead=%s" % [new_hp, new_max, str(is_dead)])
	# Client: update local HP display
	if resource_life:
		resource_life.max_life = new_max
		resource_life.life = new_hp
	if is_dead:
		_die()
	else:
		_start_invincibility(0.5)
		sprite.modulate = Color(5, 5, 5)
		get_tree().create_timer(0.1).timeout.connect(func(): sprite.modulate = Color.WHITE)
		if sfx_hurt:
			sfx_hurt.play()
		hit_taken.emit()


# --- 回血同步（不觸發受傷閃爍）---

# "any_peer" because server (peer=1) is NOT this node's authority (client is).
# Authority-mode RPC would be rejected by Godot. We still only trust the server at runtime.
@rpc("any_peer", "reliable")
func _rpc_heal_sync(new_hp: int, new_max: int):
	var sender = multiplayer.get_remote_sender_id()
	if sender != 1:
		return  # only trust the server
	if resource_life:
		resource_life.max_life = new_max
		resource_life.life = new_hp


# --- 武器同步 ---

func change_weapon(weapon_key: String):
	## 切換武器並同步給所有 client
	current_weapon_key = weapon_key
	_apply_weapon(weapon_key)
	weapon_changed.emit(weapon_key)
	if multiplayer.has_multiplayer_peer():
		_rpc_weapon_changed.rpc(weapon_key)


@rpc("any_peer", "reliable")
func _rpc_weapon_changed(weapon_key: String):
	# 只接受來自該角色擁有者的武器切換
	var sender = multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	current_weapon_key = weapon_key
	_apply_weapon(weapon_key)


# Snapshot interpolation: authority writes target_position, remote peers lerp to it.
# Replaces direct position sync so remote rendering doesn't fight client physics.
var target_position := Vector2.ZERO


func _apply_weapon(weapon_key: String):
	var path = WEAPON_PATHS.get(weapon_key, "")
	if path == "" or !ResourceLoader.exists(path):
		return
	var res = load(path) as ResourceWeapon
	if res and weapon_node:
		weapon_node.resource_weapon = res


# --- 投射物同步 ---

func start_attack():
	super.start_attack()
	# 遠程武器：廣播投射物給其他 client
	if weapon_node and weapon_node.resource_weapon and weapon_node.resource_weapon.anim_type == ResourceWeapon.AnimationType.RANGE:
		if multiplayer.has_multiplayer_peer() and is_multiplayer_authority():
			_rpc_spawn_projectile.rpc(global_position + attack_direction * 16.0, attack_direction)


var _last_projectile_time := 0

@rpc("any_peer", "reliable")
func _rpc_spawn_projectile(pos: Vector2, dir: Vector2):
	# 驗證發送者是該角色的擁有者
	var sender = multiplayer.get_remote_sender_id()
	if sender != get_multiplayer_authority():
		return
	# 頻率限制：最少間隔 200ms
	var now = Time.get_ticks_msec()
	if now - _last_projectile_time < 200:
		return
	_last_projectile_time = now
	# 生成純視覺投射物
	var proj_scene = preload("res://system/weapon/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.direction = dir
	proj.damage_amount = 0
	proj.team = PLAYER_TEAM
	proj.monitoring = false
	proj.global_position = pos
	if weapon_node and weapon_node.resource_weapon:
		var sprite_node = proj.get_node_or_null("Sprite2D")
		if sprite_node:
			sprite_node.texture = weapon_node.resource_weapon.sprite
	get_tree().current_scene.add_child(proj)


# --- 死亡/重生多人同步 ---

func _die():
	super._die()
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_rpc_death_fx.rpc()


func _respawn():
	super._respawn()
	if is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_rpc_respawn_fx.rpc(global_position)


@rpc("any_peer", "reliable")
func _rpc_death_fx():
	# 其他 client 看到死亡效果：紅閃 → 灰階 + 骷髏標記
	sprite.modulate = Color(2, 0.3, 0.3)
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5), 0.3)
	var skull_sl = preload("res://system/ui/screen_label.gd").create(
		self, "x_x", 14, Color.WHITE, Vector2(0, -24))
	tw.tween_interval(3.0)
	tw.tween_callback(func():
		if is_instance_valid(skull_sl):
			skull_sl.queue_free()
	)


@rpc("any_peer", "reliable")
func _rpc_respawn_fx(pos: Vector2):
	# 其他 client 看到重生效果：移動到重生點 + 放大出現
	global_position = pos
	sprite.modulate = Color.WHITE
	sprite.modulate.a = 0.5
	sprite.scale = Vector2(0.1, 0.1)
	var tw = create_tween()
	tw.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(sprite, "modulate:a", 1.0, 0.2)


# --- 升級多人同步 ---

var _prev_level := 1

func add_xp(amount: int):
	_prev_level = level
	super.add_xp(amount)
	# 如果升級了，通知其他 client 播放升級特效
	if level > _prev_level and is_multiplayer_authority() and multiplayer.has_multiplayer_peer():
		_rpc_level_sync.rpc(level)


## Server-only. Apply saved state to this character AFTER _ready defaults have run,
## then broadcast to all clients so they match. Called via call_deferred from
## world._spawn_player_func when a peer has save data.
func _apply_server_restore(save: Dictionary) -> void:
	if !multiplayer.is_server():
		return
	if save.has("level") and save["level"] > 1:
		var lvl = int(save["level"])
		level = lvl
		attack_damage = ATK_PER_LEVEL[lvl - 1]
		if resource_life:
			resource_life.max_life = HP_PER_LEVEL[lvl - 1]
			resource_life.life = resource_life.max_life
		# Tell every peer (including this player's own client) — overrides the
		# client's local _load_player_data if it ran, or primes it if it didn't.
		if multiplayer.has_multiplayer_peer():
			_rpc_level_sync.rpc(lvl, false)  # no FX
	if save.has("xp"):
		xp = int(save["xp"])
	# Weapon restore is handled client-side (owning peer is weapon authority).


@rpc("any_peer", "reliable")
func _rpc_level_sync(new_level: int, show_fx: bool = true):
	# 同步等級 + HP上限 + ATK（包含自己的 client）
	if new_level > level:
		level = new_level
		attack_damage = ATK_PER_LEVEL[level - 1]
		if resource_life:
			resource_life.max_life = HP_PER_LEVEL[level - 1]
			resource_life.life = resource_life.max_life  # 滿血
		if show_fx:
			_show_levelup_fx()


# --- 聊天同步 ---

const _ChatBubbleScript = preload("res://system/ui/chat_bubble.gd")

var _last_chat_time := 0

@rpc("any_peer", "reliable")
func _rpc_chat(text: String):
	## 其他 client 收到聊天訊息，顯示氣泡
	# 頻率限制 + 長度限制
	var now = Time.get_ticks_msec()
	if now - _last_chat_time < 1000:
		return
	_last_chat_time = now
	text = text.substr(0, 100)
	for child in get_children():
		if child.has_method("show_message"):
			child.queue_free()
	var bubble = Node2D.new()
	bubble.set_script(_ChatBubbleScript)
	add_child(bubble)
	bubble.show_message(text)
