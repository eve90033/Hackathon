@icon("../character/icon_character.png")
@tool
extends Node2D


signal teleported

enum Anim {IDLE,MOVING}

const IMAGE_SPEED := 6
const ANIMATION_DATA := {
	Anim.IDLE:[0],
	Anim.MOVING:[0,1],
}

@export var speed := 30
@export var acceleration := 5

var anim:Anim = Anim.IDLE:
	set(v):
		if anim == v:
			return
		anim = v
		current_image = 0
		image_list = ANIMATION_DATA[anim]
		update_animation()
var direction := Vector2.DOWN:
	set(v):
		direction = v
		update_animation()
var image_list:PackedInt32Array = [0]:
	set(v):
		image_list = v
var current_image:= 0.0:
	set(v):
		current_image =  wrap(v,0,image_list.size())
		update_animation()
var move_vector:Vector2
var velocity := Vector2.ZERO

# 自動漫步相關
var wander_timer := 0.0
var wander_duration := 0.0
var home_position := Vector2.ZERO
var wander_range := 30.0
var wander_disabled := false  # 外部 AI 接管時停止漫步


@onready var sprite: Sprite2D = $Sprite


func _is_server() -> bool:
	return !multiplayer.has_multiplayer_peer() or multiplayer.is_server()

func _ready():
	if Engine.is_editor_hint():
		return
	home_position = global_position
	if multiplayer.has_multiplayer_peer():
		set_multiplayer_authority(1)
	# Netfox: explicitly set root to self (at runtime NodePath-to-Node
	# auto-resolution for @export var root: Node doesn't fire, so we
	# set it programmatically and re-run process_settings).
	if has_node("StateSync"):
		$StateSync.root = self
		$StateSync.process_settings()
	if has_node("TickInterp"):
		$TickInterp.root = self
		$TickInterp.process_settings()
	if _is_server():
		_pick_new_wander()
		NetworkTime.on_tick.connect(_server_tick)


func _pick_new_wander():
	# 隨機選擇：移動或停下休息
	if randf() < 0.4:
		# 停下休息
		move_vector = Vector2.ZERO
		wander_duration = randf_range(2.0, 5.0)
	else:
		# 朝隨機方向移動
		var angle = randf() * TAU
		move_vector = Vector2(cos(angle), sin(angle))
		wander_duration = randf_range(1.0, 3.0)


func update_animation():
	sprite.frame_coords.x = current_image


# Server-only: tick-based AI + movement. Must be tick-based (not _process)
# because TickInterpolator rewrites position in _process for visual interpolation
# and would fight per-frame position writes.
func _server_tick(delta: float, _tick: int) -> void:
	# 漫步 AI（可被外部停用）
	if !wander_disabled:
		wander_timer += delta
		if wander_timer >= wander_duration:
			wander_timer = 0.0
			_pick_new_wander()
		if global_position.distance_to(home_position) > wander_range:
			move_vector = (home_position - global_position).normalized()

	# 移動執行（始終運行）
	if move_vector.length():
		velocity = velocity.move_toward(move_vector*(speed*delta),acceleration*delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO,acceleration*delta)
	global_position += velocity


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# flip_h + animation 由 synced move_vector 驅動（server + client 都跑）
	if move_vector.length() and move_vector.x != 0:
		sprite.flip_h = move_vector.x < 0

	current_image += IMAGE_SPEED*delta
	if move_vector.length():
		anim = Anim.MOVING
	else:
		anim = Anim.IDLE
