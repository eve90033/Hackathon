extends CharacterBody2D


## A captured monster that follows the player as a companion.

var speed := 80.0
var acceleration := 600.0
var deceleration := 400.0
var move_vector := Vector2.ZERO
var target:Node2D
var monster_key := ""
var monster_tier := 0  # 0=弱 1=中 2=強
var min_dist := 12.0
var max_dist := 28.0

# Combat（根據 tier 調整）
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
	# 根據怪物強度設定同伴數值
	_apply_tier_stats()
	# Don't attack immediately after spawn
	attack_cooldown = 2.0


func _apply_tier_stats():
	# 弱(T0): 1傷害, 30範圍, 1.5秒CD, 80速度
	# 中(T1): 2傷害, 35範圍, 1.2秒CD, 90速度
	# 強(T2): 3傷害, 40範圍, 1.0秒CD, 100速度
	attack_damage = [1, 2, 3][mini(monster_tier, 2)]
	attack_range = [30.0, 35.0, 40.0][mini(monster_tier, 2)]
	speed = [80.0, 90.0, 100.0][mini(monster_tier, 2)]


func _is_my_companion() -> bool:
	# Only the owning player runs attack AI
	if !multiplayer.has_multiplayer_peer():
		return true  # single-player
	if !target or !target is NetworkCharacter:
		return true
	return target.peer_id == multiplayer.get_unique_id()


func _physics_process(delta):
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Attack logic — only on owning client
	if _is_my_companion():
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
		if !m.is_inside_tree() or !(m is MonsterCharacter):
			continue
		if m.ai_state == MonsterCharacter.AIState.DEAD:
			continue
		var d = global_position.distance_to(m.global_position)
		if d < nearest_dist:
			nearest_dist = d
			attack_target = m


func _start_attack():
	is_attacking = true
	attack_timer = 0.0
	pre_attack_pos = global_position
	# Scale up for charge telegraph (no red tint)
	sprite.scale = Vector2(1.0, 1.0)
	sprite.modulate = Color.WHITE


func _process_attack(delta):
	attack_timer += delta

	if attack_timer < 0.2:
		# Charge: stop and telegraph (scale pulse, no red tint)
		velocity = Vector2.ZERO
		var t = attack_timer / 0.2
		sprite.scale = Vector2(1.0 + t * 0.15, 1.0 + t * 0.15)
		sprite.modulate = Color.WHITE
	elif attack_timer < 0.3:
		# Short lunge toward target direction (don't go all the way)
		if attack_target and is_instance_valid(attack_target) and attack_target.is_inside_tree():
			var dir = pre_attack_pos.direction_to(attack_target.global_position)
			velocity = dir * speed * 0.75
			if sprite:
					sprite.direction = dir
			# Deal damage at mid-point of lunge
			if attack_timer > 0.25:
				if attack_target.has_method("_on_damage_received"):
					var dmg = ResourceDamage.new()
					dmg.amount = attack_damage
					attack_target._on_damage_received(dmg, global_position)
		else:
			attack_target = null
			_end_attack()
	elif attack_timer < 0.45:
		# Return to pre-attack position
		var dir = global_position.direction_to(pre_attack_pos)
		velocity = dir * speed * 2.0
		if global_position.distance_to(pre_attack_pos) < 4:
			global_position = pre_attack_pos
			velocity = Vector2.ZERO
	else:
		# Done
		_end_attack()

	_update_anim()
	move_and_slide()


func _end_attack():
	sprite.scale = Vector2(0.8, 0.8)
	sprite.modulate = Color.WHITE
	is_attacking = false
	attack_cooldown = [1.5, 1.2, 1.0][mini(monster_tier, 2)]
	attack_target = null
	velocity = Vector2.ZERO
	global_position = pre_attack_pos


func _update_anim():
	if !sprite:
		return
	if velocity.length() > 5:
		sprite.direction = velocity.normalized()
		sprite.anim = 1  # MOVING
	else:
		sprite.anim = 0  # IDLE
