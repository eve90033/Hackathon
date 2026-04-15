extends Character
class_name NetworkCharacter


const CHARACTERS_PATH := "res://assets/Actor/Character/"
const WEAPON_SCENE := preload("res://system/weapon/weapon.tscn")
const CLUB_RESOURCE := preload("res://content/weapon/club/club.tres")
const PLAYER_TEAM := preload("res://content/team/player_team.tres")

var peer_id := 1
var player_name := "Player":
	set(v):
		player_name = v
		if is_inside_tree():
			var lbl = get_node_or_null("NameLabel")
			if lbl:
				lbl.text = player_name
var character_key := "Knight":
	set(v):
		character_key = v
		if is_inside_tree() and sprite:
			var p = CHARACTERS_PATH + character_key + "/SpriteSheet.png"
			if ResourceLoader.exists(p):
				sprite.texture = load(p)

@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var name_label: Label = $NameLabel


func _enter_tree():
	# Must set authority in _enter_tree, not _ready (MultiplayerSpawner requirement)
	if peer_id > 0:
		set_multiplayer_authority(peer_id)


func _ready():

	# Apply character skin
	var sprite_path = CHARACTERS_PATH + character_key + "/SpriteSheet.png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	# Name label
	name_label.text = player_name

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
		# Remote player: apply synced animation from state
		# Detect attack start for weapon visual
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
		velocity = velocity.move_toward(move_vector * speed, acceleration * delta)
		move_and_slide()
		return

	# Local player: full combat physics
	super._physics_process(delta)


func _on_weapon_hit(_area):
	if !is_multiplayer_authority():
		return
	# Hit-stop only: brief engine freeze (0.04s)
	Engine.time_scale = 0.05
	get_tree().create_timer(0.04, true, false, true).timeout.connect(
		func(): Engine.time_scale = 1.0
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
