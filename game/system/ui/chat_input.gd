extends CanvasLayer
class_name ChatInput

## 聊天輸入框：Enter 開啟，輸入後 Enter 發送

signal message_sent(text: String)

var line_edit: LineEdit
var bg: ColorRect
var is_open := false


func _ready():
	layer = 20
	visible = false

	# 半透明黑底背景（畫面底部）
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.anchor_left = 0.0
	bg.anchor_right = 1.0
	bg.anchor_top = 1.0
	bg.anchor_bottom = 1.0
	bg.offset_top = -24
	bg.offset_bottom = 0
	add_child(bg)

	# 輸入框
	line_edit = LineEdit.new()
	line_edit.placeholder_text = "輸入訊息..."
	line_edit.anchor_left = 0.0
	line_edit.anchor_right = 1.0
	line_edit.anchor_top = 1.0
	line_edit.anchor_bottom = 1.0
	line_edit.offset_top = -22
	line_edit.offset_bottom = -2
	line_edit.offset_left = 4
	line_edit.offset_right = -4
	line_edit.add_theme_font_size_override("font_size", 10)
	add_child(line_edit)
	line_edit.text_submitted.connect(_on_text_submitted)


func open_chat():
	## 開啟聊天輸入框（cinema 模式下禁止）
	var ui = get_node_or_null("/root/UIManager")
	if ui and ui.is_cinema():
		return
	is_open = true
	visible = true
	line_edit.text = ""
	line_edit.grab_focus()


func close_chat():
	## 關閉聊天輸入框
	is_open = false
	visible = false
	line_edit.release_focus()


func _on_text_submitted(text: String):
	## 送出訊息
	if text.strip_edges() != "":
		message_sent.emit(text.strip_edges())
	close_chat()
