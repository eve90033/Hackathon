extends Area2D

## HP 拾取物：多人同步版
## Server 權威檢查拾取，廣播消失給所有 client

@export var heal_amount := 1
var lifetime := 10.0
var pickup_delay := 0.5  # 生成後 0.5 秒才能被拾取
var sfx: AudioStreamPlayer


func _is_server() -> bool:
	return !multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func _ready():
	# 偵測玩家（layer 5）
	collision_mask = 0
	set_collision_mask_value(5, true)
	sfx = AudioStreamPlayer.new()
	sfx.stream = load("res://assets/Audio/Sounds/Bonus/Coin.wav")
	sfx.volume_db = -5
	add_child(sfx)
	# 浮動動畫
	var tween = create_tween().set_loops()
	tween.tween_property($Sprite, "position:y", -8.0, 0.4).set_trans(Tween.TRANS_SINE)
	tween.tween_property($Sprite, "position:y", -4.0, 0.4).set_trans(Tween.TRANS_SINE)
	# Server 權威
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(1)


func _physics_process(delta):
	lifetime -= delta
	if lifetime <= 0:
		# Server 通知所有 client 消失（call_local 包含 server 自己）
		if _is_server() and multiplayer.has_multiplayer_peer():
			_rpc_despawn.rpc()
		else:
			queue_free()
		return

	# 拾取延遲
	if pickup_delay > 0:
		pickup_delay -= delta
		return

	# 只有 server 檢查拾取碰撞
	if !_is_server():
		return

	for body in get_overlapping_bodies():
		if body is Character:
			# Server: 治療玩家（不管滿血與否都消失）
			if body.resource_life:
				body.resource_life.heal(heal_amount)
				# 透過玩家節點同步 HP（不透過 pickup 節點，避免節點被刪後 RPC 失敗）
				if body is NetworkCharacter and multiplayer.has_multiplayer_peer():
					body._rpc_heal_sync.rpc_id(body.peer_id, body.resource_life.life, body.resource_life.max_life)
			# 通知所有 client 此拾取物被撿走
			if multiplayer.has_multiplayer_peer():
				_rpc_picked_up.rpc()
			else:
				_do_pickup_fx()
			return


@rpc("authority", "call_local", "reliable")
func _rpc_picked_up():
	## 所有 client + server 播放拾取特效並移除
	_do_pickup_fx()


func _do_pickup_fx():
	## 播放音效、隱藏、延遲刪除
	if sfx:
		sfx.play()
	$Sprite.visible = false
	$Shape.set_deferred("disabled", true)
	set_physics_process(false)
	get_tree().create_timer(0.3).timeout.connect(queue_free)


@rpc("authority", "call_local", "reliable")
func _rpc_despawn():
	## 時間到消失（所有端）
	queue_free()
