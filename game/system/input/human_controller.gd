extends Node
class_name HumanController


@export var active := true:
	set(v):
		active = v
		update_process()

@export var action_left := "move_left"
@export var action_right := "move_right"
@export var action_up := "move_up"
@export var action_down := "move_down"

var parent:Node2D
var _z_just_pressed := false
const ChatInputScript = preload("res://system/ui/chat_input.gd")
var chat_input: Node


func _ready() -> void:
	parent = get_parent()
	update_process()
	# 建立聊天輸入框
	var ci = CanvasLayer.new()
	ci.set_script(ChatInputScript)
	chat_input = ci
	add_child(chat_input)
	chat_input.message_sent.connect(_on_chat_message)


func update_process():
	if active:
		process_mode = Node.PROCESS_MODE_INHERIT
	else:
		process_mode = Node.PROCESS_MODE_DISABLED


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and !event.echo and event.keycode == KEY_Z:
		_z_just_pressed = true
	if event is InputEventKey and event.pressed and !event.echo and event.keycode == KEY_F11:
		print("[DEBUG] Player position: %s" % str(parent.global_position))
	# Enter 鍵開啟聊天
	if event is InputEventKey and event.pressed and !event.echo and event.keycode == KEY_ENTER:
		if chat_input and !chat_input.is_open:
			chat_input.open_chat()
			parent.move_vector = Vector2.ZERO
			get_viewport().set_input_as_handled()


## 尋找最近的武器架並交換武器
func _try_weapon_rack_interact():
	if !parent or !parent is Character:
		return
	var racks = parent.get_tree().get_nodes_in_group("weapon_rack")
	var nearest: Node2D = null
	var nearest_dist := 24.0  # 最大互動距離
	for rack in racks:
		if !rack.has_method("swap_weapon"):
			continue
		var d = parent.global_position.distance_to(rack.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = rack
	if nearest:
		nearest.swap_weapon(parent)


func _process(delta: float) -> void:
	# 聊天中不處理移動和攻擊
	if chat_input and chat_input.is_open:
		parent.move_vector = Vector2.ZERO
		return
	parent.move_vector = Input.get_vector(action_left,action_right,action_up,action_down)
	if Input.is_action_just_pressed("attack"):
		parent.start_attack()
	if Input.is_action_just_pressed("capture"):
		parent.try_capture()
	# 按 Z 鍵與最近的武器架互動
	if _z_just_pressed:
		_z_just_pressed = false
		_try_weapon_rack_interact()


func _on_chat_message(text: String):
	## 處理聊天訊息：顯示本地氣泡 + 廣播給其他 client
	_show_bubble(parent, text)
	if parent is NetworkCharacter and multiplayer.has_multiplayer_peer():
		parent._rpc_chat.rpc(text)


const ChatBubbleScript = preload("res://system/ui/chat_bubble.gd")

func _show_bubble(character: Node2D, text: String):
	## 在角色頭上顯示聊天氣泡（移除舊氣泡）
	for child in character.get_children():
		if child.has_method("show_message"):
			child.queue_free()
	var bubble = Node2D.new()
	bubble.set_script(ChatBubbleScript)
	character.add_child(bubble)
	bubble.show_message(text)
