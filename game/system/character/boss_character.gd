extends CharacterBody2D
class_name BossCharacter

## Boss 角色：完整狀態機 AI + 入場演出 + 多人同步

enum BossState { IDLE, CHASE, ATTACK, JUMP_ATTACK, STUNNED, PHASE2, DEAD }

signal boss_died(boss)

@export_category("physics")
@export var speed := 50.0
@export var acceleration := 600.0
@export var deceleration := 400.0

@export_category("combat")
@export var max_hp := 30
@export var contact_damage := 3
@export var detection_range := 120.0
@export var attack_range := 25.0
@export var jump_range := 80.0
@export var stun_duration := 2.0
@export var xp_value := 200

@export var team: ResourceDamageTeam

var move_vector := Vector2.ZERO:
	set(v):
		move_vector = v
		if move_vector.length():
			sprite.direction = move_vector.normalized()

var boss_state := BossState.IDLE
var hp: int
var target: Node2D
var home_position := Vector2.ZERO
var retarget_timer := 0.0
var state_timer := 0.0
var attack_count := 0  # 計算攻擊次數，每第 3 次跳躍攻擊
var is_phase2 := false
var intro_played := false

# 攻擊階段：0=蓄力, 1=衝刺, 2=後退
var attack_phase := 0

# 視覺回饋
var flash_timer := 0.0
var push_velocity := Vector2.ZERO

# Phase 2 倍率
var speed_mult := 1.0
var cooldown_mult := 1.0

@onready var sprite = $Sprite
@onready var hitbox: Hitbox = $Hitbox
@onready var damage_area: DamageArea = $DamageArea
@onready var detection_area: Area2D = $DetectionArea

# 音效
var sfx_hit: AudioStreamPlayer
var sfx_alert: AudioStreamPlayer
var sfx_die: AudioStreamPlayer
var sfx_jump: AudioStreamPlayer

# Boss 名稱標籤
var name_label: Label

# Boss 頭上血條
var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect
const HP_BAR_WIDTH := 40.0
const HP_BAR_HEIGHT := 3.0


func _is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _is_multiplayer() -> bool:
	return multiplayer.has_multiplayer_peer()


func _ready():
	if Engine.is_editor_hint():
		return

	hp = max_hp
	home_position = global_position
	add_to_group("boss")
	add_to_group("monster")

	# Server 是所有 Boss 的權威
	if _is_multiplayer():
		set_multiplayer_authority(1)

	# 碰撞設定
	set_collision_mask_value(2, false)

	# 音效初始化
	sfx_hit = AudioStreamPlayer.new()
	sfx_hit.stream = load("res://assets/Audio/Sounds/Hit & Impact/Hit3.wav")
	sfx_hit.volume_db = -5
	add_child(sfx_hit)

	sfx_alert = AudioStreamPlayer.new()
	sfx_alert.stream = load("res://assets/Audio/Sounds/Alert/Alert3.wav")
	sfx_alert.volume_db = -8
	add_child(sfx_alert)

	sfx_die = AudioStreamPlayer.new()
	sfx_die.stream = load("res://assets/Audio/Sounds/Hit & Impact/Impact3.wav")
	sfx_die.volume_db = -3
	add_child(sfx_die)

	sfx_jump = AudioStreamPlayer.new()
	sfx_jump.stream = load("res://assets/Audio/Sounds/Hit & Impact/Hit3.wav")
	sfx_jump.volume_db = -3
	add_child(sfx_jump)

	# 連接傷害訊號
	if hitbox:
		hitbox.damage_received.connect(_on_damage_received)

	# 預設關閉接觸傷害
	if damage_area:
		damage_area.monitoring = false

	# 偵測範圍 — 僅 Server 啟用
	if detection_area:
		if !_is_multiplayer() or _is_server():
			detection_area.body_entered.connect(_on_detection_entered)
			detection_area.body_exited.connect(_on_detection_exited)
		else:
			detection_area.monitoring = false

	# Boss 名稱標籤（常駐顯示）
	name_label = Label.new()
	name_label.text = "Giant Frog"
	name_label.add_theme_font_size_override("font_size", 5)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-HP_BAR_WIDTH / 2.0, -50)
	name_label.size = Vector2(HP_BAR_WIDTH, 10)
	name_label.visible = true
	add_child(name_label)

	# Boss 血條（始終顯示在頭上）
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.15, 0.08, 0.08, 0.8)
	hp_bar_bg.position = Vector2(-HP_BAR_WIDTH / 2.0, -42)
	hp_bar_bg.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	add_child(hp_bar_bg)

	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = Color(0.9, 0.15, 0.1)
	hp_bar_fill.position = Vector2(-HP_BAR_WIDTH / 2.0, -42)
	hp_bar_fill.size = Vector2(HP_BAR_WIDTH, HP_BAR_HEIGHT)
	add_child(hp_bar_fill)

	_update_hp_bar()


func _update_hp_bar():
	if hp_bar_fill:
		var ratio = clampf(float(hp) / float(max_hp), 0.0, 1.0)
		hp_bar_fill.size.x = HP_BAR_WIDTH * ratio
		# 顏色隨血量變化：綠→黃→紅
		if ratio > 0.5:
			hp_bar_fill.color = Color(0.2, 0.85, 0.2)
		elif ratio > 0.25:
			hp_bar_fill.color = Color(0.95, 0.8, 0.1)
		else:
			hp_bar_fill.color = Color(0.9, 0.15, 0.1)
	if hp_bar_bg:
		hp_bar_bg.visible = boss_state != BossState.DEAD
		hp_bar_fill.visible = boss_state != BossState.DEAD
		name_label.visible = boss_state != BossState.DEAD


var _prev_boss_state := BossState.IDLE

func _physics_process(delta: float):
	if Engine.is_editor_hint():
		return

	# Client 端：僅渲染同步狀態
	if _is_multiplayer() and !_is_server():
		_process_client(delta)
		return

	# Server / 單人：完整 AI 邏輯
	# 閃爍衰減
	if flash_timer > 0:
		flash_timer -= delta
		if flash_timer <= 0:
			sprite.modulate = Color.WHITE

	# 擊退衰減
	if push_velocity.length() > 0:
		push_velocity = push_velocity.move_toward(Vector2.ZERO, 400 * delta)

	match boss_state:
		BossState.IDLE:
			_process_idle(delta)
		BossState.CHASE:
			_process_chase(delta)
		BossState.ATTACK:
			_process_attack(delta)
		BossState.JUMP_ATTACK:
			_process_jump_attack(delta)
		BossState.STUNNED:
			_process_stunned(delta)
		BossState.DEAD:
			velocity = Vector2.ZERO

	move_and_slide()
	_prev_boss_state = boss_state


# === Client 端渲染 ===
var _client_attack_timer := 0.0

func _process_client(delta: float):
	if flash_timer > 0:
		flash_timer -= delta
		if flash_timer <= 0:
			sprite.modulate = Color.WHITE

	match boss_state:
		BossState.IDLE, BossState.STUNNED:
			sprite.anim = 0  # IDLE
			if damage_area:
				damage_area.monitoring = false
		BossState.CHASE:
			sprite.anim = 1  # MOVING
			if move_vector.length():
				sprite.direction = move_vector.normalized()
		BossState.ATTACK:
			if _prev_boss_state != BossState.ATTACK:
				sprite.scale = Vector2(1.2, 1.2)
				sprite.modulate = Color(1.3, 0.4, 0.4)
				_client_attack_timer = 0.0
			_client_attack_timer += delta
			if _client_attack_timer >= 0.5 and _client_attack_timer < 0.7:
				if damage_area and !damage_area.monitoring:
					damage_area.monitoring = true
			elif _client_attack_timer >= 0.7:
				if damage_area and damage_area.monitoring:
					damage_area.monitoring = false
		BossState.JUMP_ATTACK:
			sprite.anim = 3  # JUMP
			if _prev_boss_state != BossState.JUMP_ATTACK:
				if damage_area:
					damage_area.monitoring = false
		BossState.DEAD:
			if damage_area:
				damage_area.monitoring = false

	# 離開攻擊狀態時重置視覺
	if boss_state != BossState.ATTACK and _prev_boss_state == BossState.ATTACK:
		sprite.scale = Vector2(1.0, 1.0)
		if damage_area:
			damage_area.monitoring = false
		if boss_state != BossState.DEAD:
			sprite.modulate = Color.WHITE

	_prev_boss_state = boss_state
	velocity = velocity.move_toward(move_vector * speed * speed_mult, acceleration * delta)
	move_and_slide()
	_update_hp_bar()


# === AI 狀態處理 ===

func _process_idle(delta: float):
	move_vector = Vector2.ZERO
	sprite.anim = 0
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)

	# 檢查附近是否有玩家
	if target and target.is_inside_tree():
		var dist = global_position.distance_to(target.global_position)
		if dist <= detection_range:
			# 首次偵測到玩家 → 入場演出
			if !intro_played:
				_play_intro()
			boss_state = BossState.CHASE


func _process_chase(delta: float):
	if !_valid_target():
		boss_state = BossState.IDLE
		return

	# 漫遊限制
	if global_position.distance_to(home_position) > 600:
		boss_state = BossState.IDLE
		target = null
		return

	# 定期重新搜索
	retarget_timer -= delta
	if retarget_timer <= 0:
		retarget_timer = 0.5
		_find_nearest_player()

	if !_valid_target():
		boss_state = BossState.IDLE
		return

	var dist = global_position.distance_to(target.global_position)

	# 每第 3 次攻擊使用跳躍攻擊
	if dist <= jump_range and attack_count > 0 and attack_count % 3 == 0:
		boss_state = BossState.JUMP_ATTACK
		state_timer = 0.0
		attack_phase = 0
		return

	if dist <= attack_range:
		boss_state = BossState.ATTACK
		state_timer = 0.0
		attack_phase = 0
		return

	# 向目標移動
	move_vector = global_position.direction_to(target.global_position)
	sprite.anim = 1  # MOVING
	velocity = velocity.move_toward(move_vector * speed * speed_mult, acceleration * delta)


func _process_attack(delta: float):
	state_timer += delta
	var charge_dur := 0.5 * cooldown_mult
	var lunge_dur := charge_dur + 0.2
	var retreat_dur := lunge_dur + 0.3

	if attack_phase == 0:
		# 蓄力階段：停下，放大+紅色提示
		velocity = Vector2.ZERO
		sprite.scale = Vector2(1.2, 1.2)
		sprite.modulate = Color(1.3, 0.4, 0.4)
		sprite.anim = 2  # ATTACK
		if state_timer <= delta and sfx_alert:
			sfx_alert.play()
		if state_timer >= charge_dur:
			attack_phase = 1
			if damage_area:
				damage_area.monitoring = true
			if _valid_target():
				var lunge_dir = global_position.direction_to(target.global_position)
				velocity = lunge_dir * speed * 5.0 * speed_mult
	elif attack_phase == 1:
		# 衝刺階段
		if state_timer >= lunge_dur:
			if damage_area:
				damage_area.monitoring = false
			sprite.scale = Vector2(1.0, 1.0)
			sprite.modulate = Color.WHITE
			attack_phase = 2
			var retreat_dir = global_position.direction_to(home_position)
			if retreat_dir.length() < 0.1:
				retreat_dir = -sprite.direction
			velocity = retreat_dir * speed * 2.5
	elif attack_phase == 2:
		# 後退階段
		if state_timer >= retreat_dur:
			velocity = Vector2.ZERO
			attack_count += 1
			boss_state = BossState.STUNNED
			state_timer = 0.0
			attack_phase = 0


func _process_jump_attack(delta: float):
	state_timer += delta

	if attack_phase == 0:
		# 起跳準備：縮小
		velocity = Vector2.ZERO
		sprite.anim = 3  # JUMP
		sprite.scale = Vector2(0.8, 1.3)
		if sfx_jump:
			sfx_jump.play()
		if _valid_target():
			# Tween 跳躍到目標位置
			var target_pos = target.global_position
			var tw = create_tween()
			tw.tween_property(self, "global_position", target_pos, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.tween_callback(func():
				if !is_instance_valid(self) or !is_inside_tree():
					return
				# 落地 AoE 傷害
				sprite.scale = Vector2(1.3, 0.8)
				if damage_area:
					damage_area.monitoring = true
				var cameras = get_tree().get_nodes_in_group("camera")
				for cam in cameras:
					if cam.has_method("shake"):
						cam.shake(4.0, 0.3)
				# 用 tween 代替 create_timer，節點被刪時自動取消
				var tw2 = create_tween()
				tw2.tween_interval(0.3)
				tw2.tween_callback(func():
					if !is_instance_valid(self) or !is_inside_tree():
						return
					if damage_area:
						damage_area.monitoring = false
					sprite.scale = Vector2(1.0, 1.0)
					attack_count += 1
					boss_state = BossState.STUNNED
					state_timer = 0.0
					attack_phase = 0
				)
			)
		attack_phase = 1  # 防止重複觸發
	elif attack_phase == 1:
		# 等待 tween 完成（由回調處理狀態轉換）
		pass


func _process_stunned(delta: float):
	move_vector = Vector2.ZERO
	sprite.anim = 0  # IDLE
	velocity = velocity.move_toward(Vector2.ZERO, deceleration * delta)
	state_timer += delta
	if state_timer >= stun_duration * cooldown_mult:
		state_timer = 0.0
		boss_state = BossState.CHASE
		# TPK 檢查
		_check_tpk()


# === Phase 2 觸發 ===
func _enter_phase2():
	if is_phase2:
		return
	is_phase2 = true
	speed_mult = 1.3
	cooldown_mult = 0.7

	# 紅色閃爍動畫
	var tw = create_tween()
	tw.set_loops(5)
	tw.tween_property(sprite, "modulate", Color(2.0, 0.3, 0.3), 0.1)
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.1)

	# 廣播給所有客戶端
	if _is_multiplayer():
		_rpc_phase2_fx.rpc()


@rpc("authority", "reliable")
func _rpc_phase2_fx():
	is_phase2 = true
	speed_mult = 1.3
	cooldown_mult = 0.7
	var tw = create_tween()
	tw.set_loops(5)
	tw.tween_property(sprite, "modulate", Color(2.0, 0.3, 0.3), 0.1)
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.1)


# === 入場 ===
func _play_intro():
	intro_played = true


# === 傷害處理 ===
func _on_damage_received(damage: ResourceDamage, at_pos: Vector2):
	if boss_state == BossState.DEAD:
		return

	if _is_multiplayer() and !_is_server():
		_rpc_boss_hit.rpc_id(1, at_pos)
		return

	_apply_damage(damage.amount, at_pos)


@rpc("any_peer", "reliable")
func _rpc_boss_hit(at_pos: Vector2):
	if !multiplayer.is_server():
		return
	if boss_state == BossState.DEAD:
		return
	var sender_id = multiplayer.get_remote_sender_id()
	var world_node = get_parent()
	var attacker = world_node.get_node_or_null("PlayerContainer/Player_%d" % sender_id)
	if !attacker or !(attacker is NetworkCharacter):
		return
	# 防作弊：檢查距離和攻擊狀態
	if attacker.state != Character.State.ATTACK:
		return
	if attacker.global_position.distance_to(global_position) > 60:
		return
	var dmg = attacker.attack_damage
	_apply_damage(dmg, at_pos)
	_rpc_hit_fx.rpc()


@rpc("authority", "reliable")
func _rpc_hit_fx():
	if sfx_hit:
		sfx_hit.play()
	sprite.modulate = Color(5, 5, 5)
	flash_timer = 0.1


func _apply_damage(amount: int, at_pos: Vector2):
	hp -= amount
	_update_hp_bar()

	# 受擊回饋
	if sfx_hit:
		sfx_hit.play()
	sprite.modulate = Color(5, 5, 5)
	flash_timer = 0.1

	# 輕微擊退（Boss 較重）
	push_velocity = (global_position - at_pos).normalized() * 40.0

	# Phase 2 檢查：HP <= 50%
	if hp > 0 and hp <= max_hp * 0.5 and !is_phase2:
		_enter_phase2()

	# 死亡檢查
	if hp <= 0:
		_die()


# === 死亡處理 ===
func _die():
	boss_state = BossState.DEAD
	if damage_area:
		damage_area.monitoring = false
	sprite.modulate = Color(5, 5, 5)
	if sfx_die:
		sfx_die.play()
	boss_died.emit(self)

	# 給所有附近玩家 XP
	_give_xp_to_all()

	# 廣播死亡效果
	if _is_multiplayer():
		_rpc_die_fx.rpc()

	# 死亡動畫：白閃→灰階停留 5 秒→淡出
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5), 0.3)
	tw.tween_interval(5.0)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_hide_and_reset)


@rpc("authority", "reliable")
func _rpc_die_fx():
	if sfx_die:
		sfx_die.play()
	sprite.modulate = Color(5, 5, 5)
	var tw = create_tween()
	tw.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5), 0.3)
	tw.tween_interval(5.0)
	tw.tween_property(sprite, "modulate:a", 0.0, 0.5)


func _give_xp_to_all():
	## 給所有附近玩家分配 XP
	var players = get_tree().get_nodes_in_group("player")
	for p in players:
		if p is NetworkCharacter:
			var dist = global_position.distance_to(p.global_position)
			if dist < 300.0:  # 附近 300px 內的玩家獲得 XP
				if _is_multiplayer():
					if p.peer_id == 1:
						# Host 玩家直接加 XP（rpc_id 不會本地呼叫）
						p.add_xp(xp_value)
					else:
						_rpc_give_xp.rpc_id(p.peer_id, xp_value)
				else:
					p.add_xp(xp_value)


@rpc("authority", "reliable")
func _rpc_give_xp(amount: int):
	var my_id = multiplayer.get_unique_id()
	var world = get_parent()
	if !world:
		return
	var player = world.get_node_or_null("PlayerContainer/Player_%d" % my_id)
	if player and player.has_method("add_xp"):
		player.add_xp(amount)


func _hide_and_reset():
	visible = false
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if hitbox:
		hitbox.monitorable = false
	# 60 秒後重生
	get_tree().create_timer(60.0).timeout.connect(_respawn)


func _respawn():
	hp = max_hp
	boss_state = BossState.IDLE
	is_phase2 = false
	speed_mult = 1.0
	cooldown_mult = 1.0
	attack_count = 0
	intro_played = false
	global_position = home_position
	visible = true
	set_deferred("collision_layer", 2)
	set_deferred("collision_mask", 1)
	sprite.modulate = Color.WHITE
	sprite.modulate.a = 1.0
	sprite.scale = Vector2(1.0, 1.0)
	if hitbox:
		hitbox.monitorable = true
	target = null
	_update_hp_bar()


# === TPK 處理：所有玩家死亡 ===
var _tpk_scheduled := false

func _check_tpk():
	if _tpk_scheduled:
		return
	var players = get_tree().get_nodes_in_group("player")
	if players.size() == 0:
		return
	var all_dead := true
	for p in players:
		if p is Character and p.state != Character.State.DEAD:
			all_dead = false
			break
	if all_dead:
		_tpk_scheduled = true
		var tw = create_tween()
		tw.tween_interval(5.0)
		tw.tween_callback(_tpk_reset)


func _tpk_reset():
	_tpk_scheduled = false
	boss_state = BossState.IDLE
	hp = max_hp
	is_phase2 = false
	speed_mult = 1.0
	cooldown_mult = 1.0
	attack_count = 0
	global_position = home_position
	velocity = Vector2.ZERO
	sprite.modulate = Color.WHITE
	sprite.scale = Vector2(1.0, 1.0)
	if damage_area:
		damage_area.monitoring = false
	target = null


# === 目標搜索 ===
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
	var nearest: Node2D = null
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


func _on_detection_entered(body: Node2D):
	if body.is_in_group("player"):
		if !_valid_target():
			target = body
			if boss_state == BossState.IDLE:
				# 首次偵測 → 入場演出
				if !intro_played:
					_play_intro()
				boss_state = BossState.CHASE


func _on_detection_exited(body: Node2D):
	if body == target:
		pass  # 持續追蹤直到漫遊限制
