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
		selected_index = index
		_update_selection()


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
	if player_name.is_empty():
		hint_label.text = "請輸入暱稱！"
		return
	character_created.emit(player_name, character_list[selected_index])


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
