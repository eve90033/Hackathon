@icon("../character/icon_character.png")
extends CharacterBody2D
class_name Character


enum State{IDLE, ATTACK, HIT, DODGE, DEAD}


signal teleported
signal attacked
signal hit_taken
signal died
signal leveled_up(level:int)
signal xp_gained(amount:int)

@export_category("physics")
@export var speed = 100.0
@export var acceleration = 1000.0
@export var deceleration = 800.0

@export var actor_scene:PackedScene:
	set(v):
		actor_scene = v
		if !actor_scene:
			return
		if !is_inside_tree():
			await ready
		if actor:
			actor.queue_free()
		actor = actor_scene.instantiate()

@export var team:ResourceDamageTeam:
	set(v):
		team = v

@export var resource_life:ResourceLife


var actor:ActorSprite
var move_vector := Vector2.ZERO:
	set(v):
		move_vector = v
		if move_vector.length():
			sprite.direction = move_vector.normalized()
var state:State
var just_teleport := false

# XP / Level
var level := 1
var xp := 0
var attack_damage := 2
const XP_TABLE := [0, 50, 150, 350]  # XP needed for Lv1,2,3,4
const HP_PER_LEVEL := [5, 6, 7, 8]
const ATK_PER_LEVEL := [2, 2, 3, 3]

# Combat
var combat_timer := 0.0
var dodge_cooldown := 0.0
var invincible_timer := 0.0
var is_invincible := false
var attack_direction := Vector2.DOWN
var push_velocity := Vector2.ZERO
var weapon_node:Weapon
var spawn_position := Vector2.ZERO

const ATTACK_DURATION := 0.4
const ATTACK_ACTIVE_START := 0.10
const ATTACK_ACTIVE_END := 0.25
const HIT_DURATION := 0.3
const INVINCIBLE_DURATION := 0.5
const DODGE_DURATION := 0.25
const DODGE_COOLDOWN := 0.8
const DODGE_SPEED_MULT := 2.0

@onready var sprite: SpriteCharacter = $Sprite
@onready var hitbox:Hitbox = $Hitbox

# Sound effects
var sfx_attack:AudioStreamPlayer
var sfx_hurt:AudioStreamPlayer
var sfx_levelup:AudioStreamPlayer

func _setup_sfx():
	sfx_attack = AudioStreamPlayer.new()
	sfx_attack.stream = load("res://assets/Audio/Sounds/Whoosh & Slash/Slash2.wav")
	sfx_attack.volume_db = -5
	add_child(sfx_attack)
	sfx_hurt = AudioStreamPlayer.new()
	sfx_hurt.stream = load("res://assets/Audio/Sounds/Hit & Impact/Hit7.wav")
	sfx_hurt.volume_db = -5
	add_child(sfx_hurt)
	sfx_levelup = AudioStreamPlayer.new()
	sfx_levelup.stream = load("res://assets/Audio/Sounds/Bonus/PowerUp2.wav")
	add_child(sfx_levelup)


func _ready():
	if Engine.is_editor_hint():
		return
	if hitbox:
		hitbox.damage_received.connect(_on_hitbox_damage)
	_setup_sfx()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Invincibility countdown + flash
	if is_invincible:
		invincible_timer -= delta
		sprite.modulate.a = 0.3 if fmod(invincible_timer, 0.12) < 0.06 else 1.0
		if invincible_timer <= 0:
			is_invincible = false
			sprite.modulate.a = 1.0

	if dodge_cooldown > 0:
		dodge_cooldown -= delta

	match state:
		State.IDLE:
			_process_idle(delta)
		State.ATTACK:
			_process_attack(delta)
		State.HIT:
			_process_hit(delta)
		State.DODGE:
			_process_dodge(delta)
		State.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()
	# 地圖邊界限制
	global_position.x = clamp(global_position.x, -480.0, 850.0)
	global_position.y = clamp(global_position.y, -800.0, 480.0)


func _process_idle(delta:float):
	if move_vector.length():
		sprite.anim = SpriteCharacter.Anim.MOVING
		velocity = velocity.move_toward(move_vector*speed,acceleration*delta)
	else:
		sprite.anim = SpriteCharacter.Anim.IDLE
		velocity = velocity.move_toward(Vector2.ZERO,deceleration*delta)


func _process_attack(delta:float):
	combat_timer += delta
	velocity = velocity.move_toward(Vector2.ZERO,deceleration*delta)

	# 根據武器類型決定攻擊時間參數
	var atk_dur = ATTACK_DURATION
	var atk_start = ATTACK_ACTIVE_START
	var atk_end = ATTACK_ACTIVE_END
	if weapon_node and weapon_node.resource_weapon:
		atk_dur = weapon_node.resource_weapon.attack_duration
		atk_start = weapon_node.resource_weapon.attack_active_start
		atk_end = weapon_node.resource_weapon.attack_active_end

	# 近戰 DamageArea 啟用窗口（遠程武器不啟用，由投射物處理傷害）
	if weapon_node:
		var is_range = weapon_node.resource_weapon and weapon_node.resource_weapon.anim_type == ResourceWeapon.AnimationType.RANGE
		if !is_range:
			if combat_timer >= atk_start and combat_timer - delta < atk_start:
				weapon_node.set_damage_active(true)
			if combat_timer >= atk_end and combat_timer - delta < atk_end:
				weapon_node.set_damage_active(false)

	if combat_timer >= atk_dur:
		state = State.IDLE
		if weapon_node:
			weapon_node.set_damage_active(false)
			weapon_node.state = Weapon.State.BACK


func _process_hit(delta:float):
	combat_timer -= delta
	velocity = push_velocity
	push_velocity = push_velocity.move_toward(Vector2.ZERO, 400*delta)
	if combat_timer <= 0:
		state = State.IDLE
		_start_invincibility()


func _process_dodge(delta:float):
	combat_timer -= delta
	velocity = attack_direction * speed * DODGE_SPEED_MULT
	if combat_timer <= 0:
		state = State.IDLE
		dodge_cooldown = DODGE_COOLDOWN


# --- Combat actions ---

func start_attack():
	if state != State.IDLE:
		print("[Combat] Can't attack, state=", state)
		return
	state = State.ATTACK
	combat_timer = 0.0
	attack_direction = sprite.direction
	sprite.anim = SpriteCharacter.Anim.ATTACK
	if sfx_attack:
		sfx_attack.play()
	if weapon_node:
		weapon_node.direction = attack_direction
		if weapon_node.damage_area and weapon_node.damage_area.damage:
			weapon_node.damage_area.damage.amount = attack_damage
		weapon_node.use_weapon()  # 處理近戰/遠程武器切換
	attacked.emit()


func start_dodge():
	if state != State.IDLE:
		return
	if dodge_cooldown > 0:
		return
	state = State.DODGE
	combat_timer = DODGE_DURATION
	attack_direction = move_vector.normalized() if move_vector.length() else sprite.direction


func take_hit(damage_amount:int, from_pos:Vector2):
	if is_invincible or state == State.DEAD or state == State.DODGE:
		return
	if resource_life:
		resource_life.damage(damage_amount)
		if !resource_life.is_alive():
			_die()
			return
	# Enter HIT state with knockback
	state = State.HIT
	combat_timer = HIT_DURATION
	push_velocity = (global_position - from_pos).normalized() * 200.0
	if weapon_node:
		weapon_node.set_damage_active(false)
		weapon_node.state = Weapon.State.BACK
	sprite.modulate = Color(5, 5, 5)
	get_tree().create_timer(0.1).timeout.connect(func(): sprite.modulate = Color.WHITE)
	if sfx_hurt:
		sfx_hurt.play()
	hit_taken.emit()


var death_countdown_label: Label

func _die():
	state = State.DEAD
	sprite.anim = SpriteCharacter.Anim.DEAD
	if weapon_node:
		weapon_node.set_damage_active(false)
		weapon_node.state = Weapon.State.BACK
	died.emit()
	# 死亡遺失同伴
	for comp in get_tree().get_nodes_in_group("companion"):
		if comp.target == self:
			comp.queue_free()
	# 死亡儀式：紅閃 → 灰階 → 倒數 → 煙霧重生
	sprite.modulate = Color(2, 0.3, 0.3)
	var death_tween = create_tween()
	death_tween.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5), 0.3)
	death_tween.tween_callback(_show_death_countdown)
	death_tween.tween_interval(3.0)
	death_tween.tween_callback(_respawn_with_smoke)


func _show_death_countdown():
	# 顯示 3...2...1 倒數文字（用 tween 代替 timer，節點被刪時自動取消）
	death_countdown_label = Label.new()
	death_countdown_label.add_theme_font_size_override("font_size", 8)
	death_countdown_label.add_theme_color_override("font_color", Color.WHITE)
	death_countdown_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	death_countdown_label.add_theme_constant_override("shadow_offset_x", 1)
	death_countdown_label.add_theme_constant_override("shadow_offset_y", 1)
	death_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_countdown_label.position = Vector2(-8, -24)
	death_countdown_label.text = "3"
	add_child(death_countdown_label)
	var countdown_tween = create_tween()
	countdown_tween.tween_interval(1.0)
	countdown_tween.tween_callback(func():
		if death_countdown_label: death_countdown_label.text = "2")
	countdown_tween.tween_interval(1.0)
	countdown_tween.tween_callback(func():
		if death_countdown_label: death_countdown_label.text = "1")


func _respawn_with_smoke():
	# 煙霧效果：縮小 → 消失 → 移動到重生點 → 放大出現
	if death_countdown_label:
		death_countdown_label.queue_free()
		death_countdown_label = null
	var smoke_tween = create_tween()
	smoke_tween.tween_property(sprite, "scale", Vector2(0.1, 0.1), 0.2)
	smoke_tween.tween_callback(func():
		_respawn()
		sprite.scale = Vector2(0.1, 0.1)
		sprite.modulate.a = 0.5
	)
	smoke_tween.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	smoke_tween.tween_property(sprite, "modulate:a", 1.0, 0.2)


func _respawn():
	if resource_life:
		resource_life.life = resource_life.max_life
	state = State.IDLE
	sprite.anim = SpriteCharacter.Anim.IDLE
	sprite.modulate = Color.WHITE
	sprite.modulate.a = 1.0
	# Move back to spawn point
	if spawn_position != Vector2.ZERO:
		global_position = spawn_position
	_start_invincibility(2.0)  # 2s invincibility after respawn


func _start_invincibility(duration:=INVINCIBLE_DURATION):
	is_invincible = true
	invincible_timer = duration


func _on_hitbox_damage(damage:ResourceDamage, at_pos:Vector2):
	take_hit(damage.amount, at_pos)


func try_capture():
	if state == State.DEAD:
		return
	# Find nearest monster within 40px
	var monsters = get_tree().get_nodes_in_group("monster")
	var nearest:Node2D = null
	var nearest_dist := 40.0
	for m in monsters:
		if !m.is_inside_tree() or !m.has_method("attempt_capture"):
			continue
		if m is MonsterCharacter and m.ai_state == MonsterCharacter.AIState.DEAD:
			continue
		var d = global_position.distance_to(m.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = m
	if nearest and nearest.has_method("attempt_capture"):
		nearest.attempt_capture(self)


func push(from_pos:Vector2, force:float):
	push_velocity = (global_position - from_pos).normalized() * force


func add_xp(amount:int):
	xp += amount
	xp_gained.emit(amount)
	# Check level up
	while level < 4 and xp >= XP_TABLE[level]:
		level += 1
		attack_damage = ATK_PER_LEVEL[level - 1]
		if resource_life:
			resource_life.max_life = HP_PER_LEVEL[level - 1]
			resource_life.heal()  # Full heal on level up
		if sfx_levelup:
			sfx_levelup.play()
		print("[Level Up] Lv%d! HP=%d ATK=%d" % [level, HP_PER_LEVEL[level-1], attack_damage])
		leveled_up.emit(level)
		_show_levelup_fx()


func _show_levelup_fx():
	# 白閃 → 金色漸變 → 恢復正常
	sprite.modulate = Color(3, 3, 3)
	var flash_tween = create_tween()
	flash_tween.tween_property(sprite, "modulate", Color(1.2, 1.1, 0.8), 0.3)
	flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	# LEVEL UP 文字上飄漸隱
	var lvl_label = Label.new()
	lvl_label.text = "LEVEL UP!"
	lvl_label.add_theme_font_size_override("font_size", 8)
	lvl_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	lvl_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	lvl_label.add_theme_constant_override("shadow_offset_x", 1)
	lvl_label.add_theme_constant_override("shadow_offset_y", 1)
	lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_label.position = Vector2(-20, -28)
	add_child(lvl_label)
	var label_tween = create_tween()
	label_tween.set_parallel(true)
	label_tween.tween_property(lvl_label, "position:y", -48.0, 1.0)
	label_tween.tween_property(lvl_label, "modulate:a", 0.0, 1.0)
	label_tween.set_parallel(false)
	label_tween.tween_callback(lvl_label.queue_free)


func teleport(target_teleporter:Teleporter,offset_position:Vector2):
	if just_teleport:
		return
	global_position = target_teleporter.global_position+offset_position+(target_teleporter.direction*Vector2(25,25))
	just_teleport = true
	for camera in get_tree().get_nodes_in_group("camera"):
		camera.teleport_to(global_position)
	await get_tree().create_timer(0.1,false).timeout
	just_teleport = false
	teleported.emit()

