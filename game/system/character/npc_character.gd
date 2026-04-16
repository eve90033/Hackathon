extends CharacterBody2D
class_name NPCCharacter

## NPC 角色：巡邏路徑 + 隨機表情泡泡

@export var speed := 40.0
@export var acceleration := 600.0
@export var deceleration := 400.0
@export var character_key := "NinjaBlue"

var move_vector := Vector2.ZERO:
	set(v):
		move_vector = v
		if move_vector.length():
			sprite.direction = move_vector.normalized()

# 巡邏相關
var patrol_points: Array[Vector2] = []
var patrol_index := 0
var patrol_wait_timer := 0.0
var patrol_waiting := false
var home_position := Vector2.ZERO

# 表情泡泡相關
var emote_timer := 0.0
var emote_interval := 8.0  # 每 8 秒隨機顯示表情
var emote_node: Sprite2D

@onready var sprite: SpriteCharacter = $Sprite


func _is_server() -> bool:
	return !multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _ready():
	if Engine.is_editor_hint():
		return
	home_position = global_position
	# 載入角色外觀
	var tex_path = "res://assets/Actor/Character/%s/SpriteSheet.png" % character_key
	if ResourceLoader.exists(tex_path):
		sprite.texture = load(tex_path)
	# 設定預設巡邏路徑（以出生點為中心的四角）
	if patrol_points.is_empty():
		patrol_points = [
			home_position + Vector2(-20, 0),
			home_position + Vector2(0, -15),
			home_position + Vector2(20, 0),
			home_position + Vector2(0, 15),
		]
	# 隨機初始表情計時，避免所有 NPC 同步
	emote_timer = randf_range(0.0, emote_interval)
	# Server 權威
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(1)


func _physics_process(delta):
	if Engine.is_editor_hint():
		return

	# 表情泡泡（所有 client 各自顯示即可）
	emote_timer += delta
	if emote_timer >= emote_interval:
		emote_timer = 0.0
		emote_interval = randf_range(6.0, 12.0)
		_show_random_emote()

	if !_is_server():
		# Client：只渲染同步的位置和動畫
		if move_vector.length():
			sprite.anim = SpriteCharacter.Anim.MOVING
			sprite.direction = move_vector.normalized()
		else:
			sprite.anim = SpriteCharacter.Anim.IDLE
		velocity = velocity.move_toward(move_vector * speed, acceleration * delta)
		move_and_slide()
		return

	# Server：跑巡邏 AI
	if patrol_waiting:
		patrol_wait_timer -= delta
		move_vector = Vector2.ZERO
		sprite.anim = SpriteCharacter.Anim.IDLE
		velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
		if patrol_wait_timer <= 0:
			patrol_waiting = false
			patrol_index = (patrol_index + 1) % patrol_points.size()
	else:
		var target_pos = patrol_points[patrol_index]
		var dist = global_position.distance_to(target_pos)
		if dist < 3.0:
			patrol_waiting = true
			patrol_wait_timer = randf_range(1.5, 4.0)
		else:
			move_vector = global_position.direction_to(target_pos)
			sprite.anim = SpriteCharacter.Anim.MOVING
			velocity = velocity.move_toward(move_vector * speed, acceleration * delta)

	move_and_slide()


func _show_random_emote():
	# 顯示隨機表情泡泡
	if emote_node and is_instance_valid(emote_node):
		emote_node.queue_free()

	# 表情圖片為 emote1.png ~ emote30.png
	var pick_num = randi_range(1, 30)
	var emote_path = "res://assets/Ui/Emote/emote%d.png" % pick_num
	if !ResourceLoader.exists(emote_path):
		return

	emote_node = Sprite2D.new()
	emote_node.texture = load(emote_path)
	emote_node.position = Vector2(0, -20)
	emote_node.scale = Vector2(0.5, 0.5)
	add_child(emote_node)

	# 2.5 秒後淡出消失
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(emote_node, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if emote_node and is_instance_valid(emote_node):
			emote_node.queue_free()
			emote_node = null
	)
