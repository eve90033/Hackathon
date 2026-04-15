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

const ATTACK_DURATION := 0.15
const ATTACK_ACTIVE_START := 0.03
const ATTACK_ACTIVE_END := 0.10
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

	# DamageArea activation window
	if weapon_node:
		if combat_timer >= ATTACK_ACTIVE_START and combat_timer - delta < ATTACK_ACTIVE_START:
			weapon_node.set_damage_active(true)
		if combat_timer >= ATTACK_ACTIVE_END and combat_timer - delta < ATTACK_ACTIVE_END:
			weapon_node.set_damage_active(false)

	if combat_timer >= ATTACK_DURATION:
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
		weapon_node.state = Weapon.State.ATTACK
		if weapon_node.damage_area and weapon_node.damage_area.damage:
			weapon_node.damage_area.damage.amount = attack_damage
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
	# Flash only, no stun/knockback
	_start_invincibility(0.5)
	sprite.modulate = Color(5,5,5)
	get_tree().create_timer(0.1).timeout.connect(func(): sprite.modulate = Color.WHITE)
	if sfx_hurt:
		sfx_hurt.play()
	hit_taken.emit()


func _die():
	state = State.DEAD
	sprite.anim = SpriteCharacter.Anim.DEAD
	if weapon_node:
		weapon_node.set_damage_active(false)
		weapon_node.state = Weapon.State.BACK
	died.emit()
	# Auto respawn after 1.5s
	get_tree().create_timer(1.5).timeout.connect(_respawn)


func _respawn():
	if resource_life:
		resource_life.life = resource_life.max_life
	state = State.IDLE
	sprite.anim = SpriteCharacter.Anim.IDLE
	sprite.modulate = Color.WHITE
	sprite.modulate.a = 1.0
	_start_invincibility(2.0)  # 2s invincibility after respawn


func _start_invincibility(duration:=INVINCIBLE_DURATION):
	is_invincible = true
	invincible_timer = duration


func _on_hitbox_damage(damage:ResourceDamage, at_pos:Vector2):
	take_hit(damage.amount, at_pos)


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

