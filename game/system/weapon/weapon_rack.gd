extends StaticBody2D
class_name WeaponRack

## 武器架：玩家靠近後按 Z 鍵替換武器

@export var weapon_resource: ResourceWeapon
var interaction_area: Area2D
var sprite: Sprite2D
var label: Label

func _ready():
	add_to_group("weapon_rack")
	# 不阻擋玩家移動（純裝飾+互動用）
	collision_layer = 0
	collision_mask = 0

	# 互動偵測區域
	interaction_area = Area2D.new()
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 20.0
	shape.shape = circle
	interaction_area.add_child(shape)
	interaction_area.collision_layer = 0
	interaction_area.collision_mask = 2  # 偵測玩家
	add_child(interaction_area)

	# 武器圖示顯示
	sprite = Sprite2D.new()
	if weapon_resource:
		sprite.texture = weapon_resource.sprite
	sprite.position = Vector2(0, -8)
	add_child(sprite)

	# 提示文字
	label = Label.new()
	label.text = "按 Z 拿取"
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.position = Vector2(-16, -20)
	label.visible = false
	add_child(label)


func _process(_delta):
	# 檢查玩家是否在互動範圍內
	var bodies = interaction_area.get_overlapping_bodies()
	var player_nearby := false
	for body in bodies:
		if body.is_in_group("player"):
			# 只對本地玩家顯示提示
			if body is NetworkCharacter and !body.is_multiplayer_authority():
				continue
			player_nearby = true
			break
	label.visible = player_nearby


## 交換武器：將玩家當前武器與架上武器互換
func swap_weapon(character: Character):
	if !character or !character.weapon_node:
		return
	var new_key := _get_weapon_key(weapon_resource)
	var old_key := ""
	if character is NetworkCharacter:
		old_key = character.current_weapon_key
	# 交換架上武器
	var old_weapon = character.weapon_node.resource_weapon
	weapon_resource = old_weapon
	# 更新本地架上圖示
	if sprite:
		sprite.texture = weapon_resource.sprite if weapon_resource else null
	# 同步武器切換 + 武器架狀態給所有 client
	if character is NetworkCharacter:
		character.change_weapon(new_key)
		# 廣播武器架狀態更新
		_rpc_rack_updated.rpc(name, old_key)
	print("[WeaponRack] 武器交換完成: %s → %s" % [old_key, new_key])


@rpc("any_peer", "reliable")
func _rpc_rack_updated(rack_name: String, new_rack_weapon_key: String):
	# 其他 client 更新武器架顯示
	var rack = get_tree().root.find_child(rack_name, true, false)
	if rack and rack is WeaponRack:
		var path = NetworkCharacter.WEAPON_PATHS.get(new_rack_weapon_key, "")
		if path != "" and ResourceLoader.exists(path):
			rack.weapon_resource = load(path)
			if rack.sprite:
				rack.sprite.texture = rack.weapon_resource.sprite
		else:
			rack.weapon_resource = null
			if rack.sprite:
				rack.sprite.texture = null


func _get_weapon_key(res: ResourceWeapon) -> String:
	if !res:
		return "club"
	var res_path = res.resource_path
	for key in NetworkCharacter.WEAPON_PATHS:
		if NetworkCharacter.WEAPON_PATHS[key] == res_path:
			return key
	return "club"
