@icon("../weapon/icon_weapon.png")
@tool
extends Node2D
class_name Weapon


enum State {BACK,ATTACK,PROJECTED,ON_FLOOR}


@export var resource_weapon:ResourceWeapon:
	set(v):
		resource_weapon = v
		if !is_inside_tree():
			await ready
		if !resource_weapon:
			sprite.texture = null
			damage_area.damage = null
			return
		sprite.texture = resource_weapon.sprite_in_hand
		damage_area.damage = resource_weapon.damage
		update_weapon()
@export var team:ResourceDamageTeam:
	set(v):
		team = v
		if !is_inside_tree():
			await ready
		damage_area.team = team

var direction:= Vector2.ZERO:
	set(v):
		direction = v
		update_weapon()

var state:State = State.BACK:
	set(v):
		state = v
		update_weapon()

@onready var sprite: Sprite2D = $Sprite
@onready var damage_area: DamageArea = $Sprite/DamageArea


func update_weapon():
	if !resource_weapon:
		return
	match state:
		State.BACK:
			visible = false
		State.ATTACK:
			visible = true
			sprite.texture = resource_weapon.sprite
			sprite.rotation = direction.angle()
			sprite.position = direction * 16.0
			show_behind_parent = direction.y >= 0
		_:
			visible = true
			sprite.rotation = 0
			sprite.texture = resource_weapon.sprite
			sprite.offset = Vector2(-7,-5)*direction
			show_behind_parent = direction.y >= 0


func _ready():
	if !Engine.is_editor_hint():
		set_damage_active(false)
		visible = false


func use_weapon():
	# 遠程武器：生成投射物而非近戰揮砍
	if resource_weapon and resource_weapon.anim_type == ResourceWeapon.AnimationType.RANGE:
		spawn_projectile()
	state = State.ATTACK


func spawn_projectile():
	if !resource_weapon or resource_weapon.anim_type != ResourceWeapon.AnimationType.RANGE:
		return
	var proj_scene = preload("res://system/weapon/projectile.tscn")
	var proj = proj_scene.instantiate()
	proj.direction = direction
	proj.damage_amount = damage_area.damage.amount if damage_area.damage else 2
	proj.team = team
	# 使用武器的 sprite 作為投射物外觀
	proj.get_node("Sprite2D").texture = resource_weapon.sprite
	proj.global_position = global_position + direction * 16.0
	get_tree().current_scene.add_child(proj)


func set_damage_active(active:bool):
	if damage_area:
		damage_area.monitoring = active
