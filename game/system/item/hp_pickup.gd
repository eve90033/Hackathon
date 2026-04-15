extends Area2D


@export var heal_amount := 1
var lifetime := 10.0


var sfx:AudioStreamPlayer

func _ready():
	sfx = AudioStreamPlayer.new()
	sfx.stream = load("res://assets/Audio/Sounds/Bonus/Bonus.wav")
	sfx.volume_db = -5
	add_child(sfx)
	# Float animation
	var tween = create_tween().set_loops()
	tween.tween_property($Sprite, "position:y", -8.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property($Sprite, "position:y", -4.0, 0.4).set_trans(Tween.TRANS_SINE)


func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	# Check overlapping bodies every frame
	for body in get_overlapping_bodies():
		if body is Character and body.resource_life:
			body.resource_life.heal(heal_amount)
			if sfx:
				sfx.play()
			# Hide and free after sound
			$Sprite.visible = false
			$Shape.set_deferred("disabled", true)
			get_tree().create_timer(0.3).timeout.connect(queue_free)
			set_physics_process(false)
			return
