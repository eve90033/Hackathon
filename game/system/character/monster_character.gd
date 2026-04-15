extends CharacterBody2D
class_name MonsterCharacter


enum AIState { IDLE, CHASE, ATTACK, STUN, HIT, DEAD }

signal monster_died(monster)
signal monster_captured(monster, captor)

@export_category("physics")
@export var speed = 60.0
@export var acceleration = 800.0
@export var deceleration = 600.0

@export_category("combat")
@export var max_hp := 3
@export var contact_damage := 1
@export var detection_range := 100.0
@export var attack_range := 20.0
@export var stun_duration := 1.0
@export var xp_value := 10
@export var hp_drop_value := 1
@export var respawn_time := 30.0

const HP_PICKUP_SCENE = preload("res://system/item/hp_pickup.tscn")
const COMPANION_SCENE = preload("res://system/companion/companion.tscn")

@export var team:ResourceDamageTeam

var move_vector := Vector2.ZERO:
	set(v):
		move_vector = v
		if move_vector.length():
			sprite.direction = move_vector.normalized()

var ai_state := AIState.IDLE
var hp:int
var target:Node2D
var home_position := Vector2.ZERO
var retarget_timer := 0.0
var stun_timer := 0.0
var is_capturable := false
var monster_key := ""

# Damage feedback
var flash_timer := 0.0
var push_velocity := Vector2.ZERO

@onready var sprite = $Sprite
@onready var hitbox:Hitbox = $Hitbox
@onready var damage_area:DamageArea = $DamageArea
@onready var detection_area:Area2D = $DetectionArea

var sfx_hit:AudioStreamPlayer
var sfx_alert:AudioStreamPlayer
var sfx_die:AudioStreamPlayer
var sfx_capture_ok:AudioStreamPlayer
var sfx_capture_fail:AudioStreamPlayer
var capture_cooldown := 0.0


func _ready():
	if Engine.is_editor_hint():
		return
	hp = max_hp
	home_position = global_position
	add_to_group("monster")
	# Only collide with walls, not players
	set_collision_mask_value(2, false)
	# SFX
	sfx_hit = AudioStreamPlayer.new()
	sfx_hit.stream = load("res://assets/Audio/Sounds/Hit & Impact/Hit3.wav")
	sfx_hit.volume_db = -8
	add_child(sfx_hit)
	sfx_alert = AudioStreamPlayer.new()
	sfx_alert.stream = load("res://assets/Audio/Sounds/Alert/Alert3.wav")
	sfx_alert.volume_db = -10
	add_child(sfx_alert)
	sfx_die = AudioStreamPlayer.new()
	sfx_die.stream = load("res://assets/Audio/Sounds/Hit & Impact/Impact3.wav")
	sfx_die.volume_db = -5
	add_child(sfx_die)
	sfx_capture_ok = AudioStreamPlayer.new()
	sfx_capture_ok.stream = load("res://assets/Audio/Jingles/Success1.wav")
	sfx_capture_ok.volume_db = -5
	add_child(sfx_capture_ok)
	sfx_capture_fail = AudioStreamPlayer.new()
	sfx_capture_fail.stream = load("res://assets/Audio/Sounds/Alert/Alert.wav")
	sfx_capture_fail.volume_db = -5
	add_child(sfx_capture_fail)

	# Wire hitbox damage signal
	if hitbox:
		hitbox.damage_received.connect(_on_damage_received)

	# Disable contact damage by default
	if damage_area:
		damage_area.monitoring = false

	# Detection area setup
	if detection_area:
		detection_area.body_entered.connect(_on_detection_entered)
		detection_area.body_exited.connect(_on_detection_exited)


func _physics_process(delta:float):
	if Engine.is_editor_hint():
		return

	# Capture cooldown
	if capture_cooldown > 0:
		capture_cooldown -= delta

	# Flash fade
	if flash_timer > 0:
		flash_timer -= delta
		if flash_timer <= 0:
			sprite.modulate = Color.WHITE

	# Push decay
	if push_velocity.length() > 0:
		push_velocity = push_velocity.move_toward(Vector2.ZERO, 400*delta)

	match ai_state:
		AIState.IDLE:
			_process_idle(delta)
		AIState.CHASE:
			_process_chase(delta)
		AIState.ATTACK:
			_process_attack(delta)
		AIState.STUN:
			_process_stun(delta)
		AIState.HIT:
			_process_hit(delta)
		AIState.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()


func _process_idle(delta:float):
	move_vector = Vector2.ZERO
	sprite.anim = 0  # IDLE
	velocity = velocity.move_toward(Vector2.ZERO, deceleration*delta)

	# Check for nearby players
	if target and target.is_inside_tree():
		var dist = global_position.distance_to(target.global_position)
		if dist <= detection_range:
			ai_state = AIState.CHASE


func _process_chase(delta:float):
	if !_valid_target():
		ai_state = AIState.IDLE
		return

	# Roaming limit: don't go too far from home
	if global_position.distance_to(home_position) > 500:
		ai_state = AIState.IDLE
		target = null
		return

	# Retarget periodically
	retarget_timer -= delta
	if retarget_timer <= 0:
		retarget_timer = 0.5
		_find_nearest_player()

	if !_valid_target():
		ai_state = AIState.IDLE
		return

	var dist = global_position.distance_to(target.global_position)

	if dist <= attack_range:
		ai_state = AIState.ATTACK
		return

	# Move toward target
	move_vector = global_position.direction_to(target.global_position)
	sprite.anim = 1  # MOVING
	velocity = velocity.move_toward(move_vector * speed, acceleration * delta)


var attack_phase := 0  # 0=charge, 1=lunge

func _process_attack(delta:float):
	stun_timer += delta

	if attack_phase == 0:
		# Charge phase: stop and telegraph (0.3s)
		velocity = Vector2.ZERO
		sprite.scale = Vector2(1.1, 1.1)
		sprite.modulate = Color(1.3, 0.6, 0.6)
		if stun_timer <= delta and sfx_alert:
			sfx_alert.play()
		if stun_timer >= 0.3:
			# Lunge phase
			attack_phase = 1
			if damage_area:
				damage_area.monitoring = true
			if _valid_target():
				var lunge_dir = global_position.direction_to(target.global_position)
				velocity = lunge_dir * speed * 3.0
	elif attack_phase == 1:
		# Lunge active (0.15s)
		if stun_timer >= 0.45:
			# Done, retreat back
			if damage_area:
				damage_area.monitoring = false
			sprite.scale = Vector2(1.0, 1.0)
			sprite.modulate = Color.WHITE
			attack_phase = 2
			# Dash back toward home
			var retreat_dir = global_position.direction_to(home_position)
			if retreat_dir.length() < 0.1:
				retreat_dir = -sprite.direction
			velocity = retreat_dir * speed * 2.5
	elif attack_phase == 2:
		# Retreat phase (0.3s)
		if stun_timer >= 0.75:
			velocity = Vector2.ZERO
			ai_state = AIState.STUN
			stun_timer = 0.0
			attack_phase = 0


func _process_stun(delta:float):
	move_vector = Vector2.ZERO
	sprite.anim = 0  # IDLE
	velocity = velocity.move_toward(Vector2.ZERO, deceleration*delta)
	stun_timer += delta
	if stun_timer >= stun_duration:
		stun_timer = 0.0
		ai_state = AIState.CHASE


var hit_timer := 0.0

func _process_hit(delta:float):
	hit_timer -= delta
	velocity = push_velocity
	push_velocity = push_velocity.move_toward(Vector2.ZERO, 400*delta)
	sprite.anim = 0  # IDLE
	if hit_timer <= 0:
		ai_state = AIState.CHASE


func _on_damage_received(damage:ResourceDamage, at_pos:Vector2):
	if ai_state == AIState.DEAD:
		return

	hp -= damage.amount

	# Hitstun + knockback
	ai_state = AIState.HIT
	hit_timer = 0.2
	push_velocity = (global_position - at_pos).normalized() * 100.0
	velocity = push_velocity
	if sfx_hit:
		sfx_hit.play()

	# Disable contact damage during hit
	if damage_area:
		damage_area.monitoring = false

	# White flash
	sprite.modulate = Color(5,5,5)
	flash_timer = 0.1

	# Check capturable
	if hp > 0 and hp <= max_hp * 0.3:
		is_capturable = true

	# Check death
	if hp <= 0:
		_die()


func _die():
	ai_state = AIState.DEAD
	if damage_area:
		damage_area.monitoring = false
	sprite.modulate = Color(5,5,5)
	if sfx_die:
		sfx_die.play()
	monster_died.emit(self)
	# Give XP + drop HP
	_give_xp()
	_drop_hp()
	# Respawn timer
	var tween = create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_hide_and_respawn)


func _drop_hp():
	var pickup = HP_PICKUP_SCENE.instantiate()
	pickup.heal_amount = hp_drop_value
	pickup.global_position = global_position
	get_tree().current_scene.add_child(pickup)


func _give_xp():
	# Give XP to nearest player
	var players = get_tree().get_nodes_in_group("player")
	var nearest:Node2D = null
	var nearest_dist := INF
	for p in players:
		var d = global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	if nearest and nearest.has_method("add_xp"):
		nearest.add_xp(xp_value)


func _hide_and_respawn():
	visible = false
	# Disable all collision
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if hitbox:
		hitbox.monitorable = false
	# Wait for respawn
	get_tree().create_timer(respawn_time).timeout.connect(_respawn)


func _respawn():
	hp = max_hp
	is_capturable = false
	ai_state = AIState.IDLE
	global_position = home_position
	visible = true
	# Restore collision (layer 2, mask walls only)
	set_deferred("collision_layer", 2)
	set_deferred("collision_mask", 1)
	sprite.modulate = Color.WHITE
	sprite.modulate.a = 1.0
	if hitbox:
		hitbox.monitorable = true
	target = null


func _valid_target() -> bool:
	if !target:
		return false
	if !target.is_inside_tree():
		return false
	if target is Character and target.state == Character.State.DEAD:
		return false
	return true


func _find_nearest_player():
	var players = get_tree().get_nodes_in_group("player")
	var nearest:Node2D = null
	var nearest_dist := INF
	for p in players:
		if p is Character and p.state == Character.State.DEAD:
			continue
		var d = global_position.distance_to(p.global_position)
		if d < nearest_dist and d <= detection_range:
			nearest_dist = d
			nearest = p
	if nearest:
		target = nearest


func attempt_capture(captor:Node2D):
	if ai_state == AIState.DEAD:
		return
	if capture_cooldown > 0:
		return
	capture_cooldown = 1.0  # 1s cooldown between attempts

	# Fail rate = current HP / max HP (lower HP = easier to capture)
	var fail_rate = float(hp) / float(max_hp)
	if randf() >= fail_rate:
		# Success
		_capture_success(captor)
	else:
		# Fail
		_capture_fail()


func _capture_success(captor:Node2D):
	ai_state = AIState.DEAD
	if damage_area:
		damage_area.monitoring = false
	if sfx_capture_ok:
		sfx_capture_ok.play()

	# Floating text
	_show_floating_text("收服成功！", Color(0.2, 1.0, 0.3))

	# Shrink + fade animation
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.4)
	tween.set_parallel(false)
	tween.tween_callback(func():
		# Give XP
		_give_xp()
		# Spawn companion
		_spawn_companion(captor)
		# Disable collision
		set_deferred("collision_layer", 0)
		set_deferred("collision_mask", 0)
		if hitbox:
			hitbox.monitorable = false
		visible = false
		monster_captured.emit(self, captor)
	)


func _capture_fail():
	if sfx_capture_fail:
		sfx_capture_fail.play()
	# Flash white
	sprite.modulate = Color(5, 5, 5)
	flash_timer = 0.15
	# Floating text
	_show_floating_text("收服失敗...", Color(1.0, 0.4, 0.3))


func _spawn_companion(captor:Node2D):
	# Remove existing companion
	for old in get_tree().get_nodes_in_group("companion"):
		if old.target == captor:
			old.queue_free()
	var comp = COMPANION_SCENE.instantiate()
	comp.global_position = global_position
	comp.target = captor
	comp.monster_key = monster_key
	get_tree().current_scene.add_child(comp)
	if sprite and sprite.texture:
		comp.sprite.texture = sprite.texture


func _show_floating_text(text:String, color:Color):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-20, -20)
	add_child(label)
	# Float up and fade
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", -40.0, 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.set_parallel(false)
	tween.tween_callback(label.queue_free)


func _on_detection_entered(body:Node2D):
	if body.is_in_group("player"):
		if !_valid_target():
			target = body
			ai_state = AIState.CHASE


func _on_detection_exited(body:Node2D):
	if body == target:
		# Keep chasing until roaming limit, don't drop target immediately
		pass
