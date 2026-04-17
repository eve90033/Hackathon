extends Control


signal character_created(player_name: String, character_name: String)


const CHARACTERS_PATH := "res://assets/Actor/Character/"
const GRID_COLS := 20
const CELL_SIZE := 56
const CELL_PADDING := 2

var character_list: Array[String] = []
var selected_index := 0
var preview_direction := 0
var preview_frame := 0.0

var _bgm_player: AudioStreamPlayer
var _sfx_select: AudioStreamPlayer
var _sfx_confirm: AudioStreamPlayer

@onready var grid_container: GridContainer = $VBox/GridContainer
@onready var preview_sprite: Sprite2D = $VBox/BottomRow/PreviewCenter/SubViewportContainer/SubViewport/PreviewSprite
@onready var name_label: Label = $VBox/BottomRow/InfoBox/NameLabel
@onready var name_edit: LineEdit = $VBox/BottomRow/InfoBox/NameEdit
@onready var confirm_button: Button = $VBox/BottomRow/InfoBox/ConfirmButton
@onready var hint_label: Label = $VBox/BottomRow/InfoBox/HintLabel


func _ready():
	_scan_characters()
	_build_grid()
	_update_selection()
	confirm_button.pressed.connect(_on_confirm)
	_start_bgm()
	_setup_sfx()
	tree_exiting.connect(_stop_bgm)
	# Auto-select for testing
	if "--auto-login" in OS.get_cmdline_user_args():
		get_tree().create_timer(0.5).timeout.connect(func():
			# Pick a random character and auto-confirm
			selected_index = randi() % character_list.size()
			_update_selection()
			name_edit.text = "Player_%d" % OS.get_process_id()
			_on_confirm()
		)


func _scan_characters():
	var dir = DirAccess.open(CHARACTERS_PATH)
	if !dir:
		push_error("Cannot open characters directory")
		return
	dir.list_dir_begin()
	var folder = dir.get_next()
	while folder != "":
		if dir.current_is_dir() and !folder.begins_with("."):
			var faceset_path = CHARACTERS_PATH + folder + "/Faceset.png"
			var sprite_path = CHARACTERS_PATH + folder + "/SpriteSheet.png"
			if ResourceLoader.exists(faceset_path) and ResourceLoader.exists(sprite_path):
				# Only include standard 64x112 sprites (4cols x 7rows of 16x16)
				var tex = load(sprite_path) as Texture2D
				if tex and tex.get_size() == Vector2(64, 112):
					character_list.append(folder)
		folder = dir.get_next()
	character_list.sort()


func _build_grid():
	grid_container.columns = GRID_COLS
	for i in character_list.size():
		var btn = TextureRect.new()
		btn.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		btn.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		btn.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var faceset_path = CHARACTERS_PATH + character_list[i] + "/Faceset.png"
		btn.texture = load(faceset_path)
		btn.name = "Cell_%d" % i
		btn.gui_input.connect(_on_cell_input.bind(i))
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		grid_container.add_child(btn)


func _on_cell_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if selected_index != index:
			selected_index = index
			_update_selection()
			if _sfx_select:
				_sfx_select.play()


func _update_selection():
	for i in grid_container.get_child_count():
		var cell = grid_container.get_child(i) as TextureRect
		if i == selected_index:
			cell.modulate = Color.WHITE
		else:
			cell.modulate = Color(0.6, 0.6, 0.6, 1.0)

	var char_name = character_list[selected_index]
	var sprite_path = CHARACTERS_PATH + char_name + "/SpriteSheet.png"
	preview_sprite.texture = load(sprite_path)
	preview_sprite.hframes = 4
	preview_sprite.vframes = 7
	preview_direction = 0
	preview_frame = 0.0
	_update_preview_frame()

	name_label.text = char_name


func _update_preview_frame():
	var directions = [0, 3, 2, 1]  # DOWN, RIGHT, LEFT, UP
	preview_sprite.frame_coords = Vector2i(directions[preview_direction], int(preview_frame) % 4)


func _process(delta):
	preview_frame += 6.0 * delta
	if preview_frame >= 4.0:
		preview_frame = 0.0
		preview_direction = (preview_direction + 1) % 4
	_update_preview_frame()


func _on_confirm():
	var player_name = name_edit.text.strip_edges()
	# 空名檢查
	if player_name.is_empty():
		hint_label.text = "請輸入暱稱！"
		return
	# 長度限制（2~12字）
	if player_name.length() < 2:
		hint_label.text = "暱稱至少 2 個字！"
		return
	if player_name.length() > 12:
		hint_label.text = "暱稱最多 12 個字！"
		return
	# 安全性：禁止危險字元
	var bad_chars = "<>'\"/\\&;{}[]()=`~|!@#$%^*+"
	for c in player_name:
		if c in bad_chars:
			hint_label.text = "暱稱包含不允許的字元"
			return
	# 向 server 檢查暱稱唯一性
	if multiplayer.has_multiplayer_peer() and !multiplayer.is_server():
		hint_label.text = "檢查暱稱中..."
		confirm_button.disabled = true
		NetworkManager.check_name.rpc_id(1, player_name, character_list[selected_index])
		# 3 秒超時恢復
		get_tree().create_timer(3.0).timeout.connect(func():
			if confirm_button.disabled:
				confirm_button.disabled = false
				hint_label.text = "連線逾時，請重試"
		)
	else:
		# 單人或 host：本地檢查
		if _is_name_taken(player_name):
			hint_label.text = "此暱稱已被使用！"
			return
		if _sfx_confirm:
			_sfx_confirm.play()
		character_created.emit(player_name, character_list[selected_index])


func _is_name_taken(pname: String) -> bool:
	for uid in NetworkManager.player_database:
		var data = NetworkManager.player_database[uid]
		if data.get("name", "") == pname:
			# 如果是自己的存檔名字，允許
			if uid == NetworkManager.my_info.get("user_id", ""):
				continue
			return true
	return false


func _on_name_check_result(ok: bool, reason: String):
	confirm_button.disabled = false
	if ok:
		if _sfx_confirm:
			_sfx_confirm.play()
		character_created.emit(name_edit.text.strip_edges(), character_list[selected_index])
	else:
		hint_label.text = reason


func _unhandled_input(event):
	# Only handle if name_edit doesn't have focus
	if name_edit.has_focus():
		return
	if event.is_action_pressed("move_left"):
		selected_index = max(0, selected_index - 1)
		_update_selection()
	elif event.is_action_pressed("move_right"):
		selected_index = min(character_list.size() - 1, selected_index + 1)
		_update_selection()
	elif event.is_action_pressed("move_up"):
		selected_index = max(0, selected_index - GRID_COLS)
		_update_selection()
	elif event.is_action_pressed("move_down"):
		selected_index = min(character_list.size() - 1, selected_index + GRID_COLS)
		_update_selection()


func _start_bgm():
	_bgm_player = AudioStreamPlayer.new()
	var stream = load("res://audio/music/adventure_begin.ogg")
	if stream:
		stream.loop = true
		_bgm_player.stream = stream
		_bgm_player.volume_db = -8.0
		add_child(_bgm_player)
		# 漸入
		_bgm_player.volume_db = -30.0
		_bgm_player.play()
		var tween = create_tween()
		tween.tween_property(_bgm_player, "volume_db", -8.0, 1.2)


func _stop_bgm():
	if _bgm_player and is_instance_valid(_bgm_player):
		_bgm_player.stop()


func _setup_sfx():
	# 選角 click 音
	_sfx_select = AudioStreamPlayer.new()
	var click_stream = load("res://assets/Audio/Sounds/Bonus/Coin.wav")
	if click_stream:
		_sfx_select.stream = click_stream
		_sfx_select.volume_db = -10.0
		add_child(_sfx_select)

	# 確認「開始冒險」音
	_sfx_confirm = AudioStreamPlayer.new()
	var confirm_stream = load("res://assets/Audio/Sounds/Bonus/PowerUp2.wav")
	if confirm_stream:
		_sfx_confirm.stream = confirm_stream
		_sfx_confirm.volume_db = -6.0
		add_child(_sfx_confirm)
