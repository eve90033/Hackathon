extends CharacterBody2D
class_name MonsterCharacter


@export_category("physics")
@export var speed = 60.0
@export var acceleration = 800.0
@export var deceleration = 600.0

@export var team:ResourceDamageTeam

var move_vector := Vector2.ZERO:
	set(v):
		move_vector = v
		if move_vector.length():
			sprite.direction = move_vector.normalized()

@onready var sprite = $Sprite


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if move_vector.length():
		sprite.anim = 1  # MOVING
		velocity = velocity.move_toward(move_vector * speed, acceleration * delta)
	else:
		sprite.anim = 0  # IDLE
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	move_and_slide()
