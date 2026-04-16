extends Node

## 粉豬特殊 AI：隨機跟隨附近玩家，超出範圍返回原地，顯示愛心表情

enum PigState { IDLE, FOLLOW, RETURN, WAIT }

var animal: Node2D
var state := PigState.IDLE
var follow_target: Node2D
var home_position := Vector2.ZERO
var follow_range := 80.0
var max_range := 150.0
var wait_timer := 0.0
var wait_duration := 10.0
var emote_node: Node2D
var emote_cooldown := 0.0


func _ready():
	animal = get_parent()
	home_position = animal.home_position


func _process(delta):
	# Server 端：控制移動和狀態
	if animal._is_server():
		match state:
			PigState.IDLE:
				_state_idle(delta)
			PigState.FOLLOW:
				_state_follow(delta)
			PigState.RETURN:
				_state_return(delta)
			PigState.WAIT:
				_state_wait(delta)

	# Client 端：偵測豬是否在跟隨玩家，顯示愛心
	if !animal._is_server():
		emote_cooldown -= delta
		if emote_cooldown <= 0:
			# 如果豬在移動且附近有玩家，顯示愛心
			if animal.move_vector.length() > 0.1:
				var nearby_player = _find_nearby_player()
				if nearby_player:
					_show_heart()
					emote_cooldown = 4.0
				else:
					emote_cooldown = 1.0
			else:
				emote_cooldown = 1.0


func _state_idle(_delta):
	var target = _find_nearby_player()
	if target:
		follow_target = target
		state = PigState.FOLLOW
		animal.wander_disabled = true


func _state_follow(delta):
	if !follow_target or !is_instance_valid(follow_target) or !follow_target.is_inside_tree():
		_start_return()
		return
	if animal.global_position.distance_to(home_position) > max_range:
		_start_return()
		return
	var dist = animal.global_position.distance_to(follow_target.global_position)
	if dist > 12.0:
		animal.move_vector = animal.global_position.direction_to(follow_target.global_position)
		animal.speed = 120
	else:
		animal.move_vector = Vector2.ZERO
	if dist > follow_range * 1.5:
		_start_return()


func _state_return(_delta):
	var dist = animal.global_position.distance_to(home_position)
	if dist < 5.0:
		animal.move_vector = Vector2.ZERO
		animal.speed = 30
		state = PigState.WAIT
		wait_timer = 0.0
	else:
		animal.move_vector = animal.global_position.direction_to(home_position)
		animal.speed = 35


func _state_wait(delta):
	animal.move_vector = Vector2.ZERO
	wait_timer += delta
	if wait_timer >= wait_duration:
		state = PigState.IDLE
		animal.wander_disabled = false


func _start_return():
	follow_target = null
	state = PigState.RETURN


func _find_nearby_player() -> Node2D:
	var candidates: Array[Node2D] = []
	for p in animal.get_tree().get_nodes_in_group("player"):
		if !p.is_inside_tree():
			continue
		if !(p is NetworkCharacter):
			continue
		if animal.global_position.distance_to(p.global_position) <= follow_range:
			candidates.append(p)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]


func _show_heart():
	if emote_node and is_instance_valid(emote_node):
		emote_node.queue_free()
		emote_node = null
	# 跟 NPC 一樣用圖片 emote（emote27 = 愛心）
	var emote_path = "res://assets/Ui/Emote/emote27.png"
	if !ResourceLoader.exists(emote_path):
		return
	emote_node = Sprite2D.new()
	emote_node.texture = load(emote_path)
	emote_node.position = Vector2(0, -12)
	emote_node.scale = Vector2(0.5, 0.5)
	animal.add_child(emote_node)
	var tween = animal.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(emote_node, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if emote_node and is_instance_valid(emote_node):
			emote_node.queue_free()
			emote_node = null
	)
