extends Character
class_name NetworkCharacter


const CHARACTERS_PATH := "res://assets/Actor/Character/"

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

	if is_multiplayer_authority():
		# This is our character: add input + camera
		var human_controller = HumanController.new()
		add_child(human_controller)
		add_to_group("player")
		set_collision_layer_value(5, true)
		# Camera will be assigned by world.gd
	else:
		# Remote character: just display
		pass


func _physics_process(delta: float) -> void:
	if !is_multiplayer_authority():
		# Remote player: apply synced values
		if move_vector.length():
			sprite.anim = SpriteCharacter.Anim.MOVING
			sprite.direction = move_vector.normalized()
		else:
			sprite.anim = SpriteCharacter.Anim.IDLE
		# Smooth interpolation toward synced position
		velocity = velocity.move_toward(move_vector * speed, acceleration * delta)
		move_and_slide()
		return

	# Local player: normal physics
	super._physics_process(delta)
