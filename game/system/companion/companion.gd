extends CharacterBody2D


## A captured monster that follows the player as a companion.

var speed := 80.0
var acceleration := 600.0
var deceleration := 400.0
var move_vector := Vector2.ZERO
var target:Node2D
var monster_key := ""
var min_dist := 12.0
var max_dist := 28.0

# Combat
var attack_target:Node2D
var attack_cooldown := 0.0
var attack_range := 30.0
var attack_damage := 1
var is_attacking := false
var attack_timer := 0.0
var pre_attack_pos := Vector2.ZERO

@onready var sprite:Sprite2D = $Sprite


func _ready():
	add_to_group("companion")
	collision_layer = 0
	collision_mask = 0


func _physics_process(delta):
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Attack logic
	if is_attacking:
		_process_attack(delta)
		move_and_slide()
		return

	# Find enemy to attack
	if attack_cooldown <= 0:
		_find_attack_target()
		if attack_target:
			_start_attack()
			return

	# Follow player
	if !target or !target.is_inside_tree():
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		_update_anim()
		move_and_slide()
		return

	var dist = global_position.distance_to(target.global_position)

	if dist > 150:
		global_position = target.global_position + Vector2(randf_range(-16, 16), randf_range(-16, 16))
		return

	if dist > max_dist:
		move_vector = global_position.direction_to(target.global_position)
		velocity = velocity.move_toward(move_vector * speed, acceleration * delta)
	elif dist < min_dist:
		move_vector = -global_position.direction_to(target.global_position)
		velocity = velocity.move_toward(move_vector * speed * 0.5, acceleration * delta)
	else:
		move_vector = Vector2.ZERO
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)

	_update_anim()
	move_and_slide()


func _find_attack_target():
	attack_target = null
	var monsters = get_tree().get_nodes_in_group("monster")
	var nearest_dist := attack_range
	for m in monsters:
		if !m.is_inside_tree() or m.ai_state == m.AIState.DEAD:
			continue
		var d = global_position.distance_to(m.global_position)
		if d < nearest_dist:
			nearest_dist = d
			attack_target = m


func _start_attack():
	is_attacking = true
	attack_timer = 0.0
	pre_attack_pos = global_position
	# Scale up + tint
	sprite.scale = Vector2(1.0, 1.0)
	sprite.modulate = Color(1.2, 0.8, 0.8)


func _process_attack(delta):
	attack_timer += delta

	if attack_timer < 0.2:
		# Charge: stop and telegraph
		velocity = Vector2.ZERO
		sprite.scale = Vector2(1.0, 1.0)
		sprite.modulate = Color(1.2, 0.8, 0.8)
	elif attack_timer < 0.3:
		# Short lunge toward target direction (don't go all the way)
		if attack_target and is_instance_valid(attack_target) and attack_target.is_inside_tree():
			var dir = pre_attack_pos.direction_to(attack_target.global_position)
			velocity = dir * speed * 0.75
			_update_dir(dir)
			# Deal damage at mid-point of lunge
			if attack_timer > 0.25:
				if attack_target.has_method("_on_damage_received"):
					var dmg = ResourceDamage.new()
					dmg.amount = attack_damage
					attack_target._on_damage_received(dmg, global_position)
		else:
			attack_target = null
	elif attack_timer < 0.45:
		# Return to pre-attack position
		var dir = global_position.direction_to(pre_attack_pos)
		velocity = dir * speed * 2.0
		if global_position.distance_to(pre_attack_pos) < 4:
			global_position = pre_attack_pos
			velocity = Vector2.ZERO
	else:
		# Done
		sprite.scale = Vector2(0.8, 0.8)
		sprite.modulate = Color.WHITE
		is_attacking = false
		attack_cooldown = 1.5
		attack_target = null
		velocity = Vector2.ZERO
		global_position = pre_attack_pos

	_update_anim()
	move_and_slide()


func _update_anim():
	if !sprite:
		return
	if velocity.length() > 5:
		sprite.frame_coords.y = int(fmod(Time.get_ticks_msec() / 150.0, 4))
		_update_dir(velocity.normalized())
	else:
		sprite.frame_coords.y = 0


func _update_dir(dir:Vector2):
	var deg = rad_to_deg(dir.angle())
	var angle_int = wrapi(roundi(deg / 90.0), 0, 4)
	var dir_map = [0, 3, 2, 1]
	sprite.frame_coords.x = dir_map[angle_int]
