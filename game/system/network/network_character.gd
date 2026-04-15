extends Character
class_name NetworkCharacter


const CHARACTERS_PATH := "res://assets/Actor/Character/"
const WEAPON_SCENE := preload("res://system/weapon/weapon.tscn")
const CLUB_RESOURCE := preload("res://content/weapon/club/club.tres")
const PLAYER_TEAM := preload("res://content/team/player_team.tres")

var peer_id := 1
var player_name := "Player"
var character_key := "Knight"

@onready var sync: MultiplayerSynchronizer = $MultiplayerSynchronizer
@onready var name_label: Label = $NameLabel


func _ready():
	# Set multiplayer authority
	set_multiplayer_authority(peer_id)

	# Apply character skin
	var sprite_path = CHARACTERS_PATH + character_key + "/SpriteSheet.png"
	if ResourceLoader.exists(sprite_path):
		sprite.texture = load(sprite_path)

	# Name label
	name_label.text = player_name

	# Setup combat: weapon + life
	_setup_combat()

	if is_multiplayer_authority():
		# This is our character: add input + camera
		var human_controller = HumanController.new()
		add_child(human_controller)
		add_to_group("player")
		set_collision_layer_value(5, true)
		# Don't get pushed by monsters (remove Character layer from mask)
		set_collision_mask_value(2, false)
	else:
		pass

	# Call parent _ready for hitbox wiring
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


func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		# Remote player: apply synced animation from state
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
