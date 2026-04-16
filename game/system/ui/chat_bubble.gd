extends Node2D
class_name ChatBubble

## 聊天氣泡：用 CanvasLayer 在螢幕空間渲染，圓角底板

var _canvas: CanvasLayer
var _panel: Control
var _label: Label
var _bg: PanelContainer
var _character: Node2D


func show_message(text: String):
	_character = get_parent()

	_canvas = CanvasLayer.new()
	_canvas.layer = 6
	add_child(_canvas)

	_panel = Control.new()
	_canvas.add_child(_panel)

	# 圓角半透明底板
	_bg = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.65)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	_bg.add_theme_stylebox_override("panel", style)
	_panel.add_child(_bg)

	# 白色文字
	_label = Label.new()
	_label.text = text
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bg.add_child(_label)

	# 2.5 秒後淡出
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)


func _process(_delta):
	if !_panel or !_character or !is_inside_tree():
		return
	var vp = get_viewport()
	if !vp:
		return
	var canvas_transform = vp.get_canvas_transform()
	var screen_pos = canvas_transform * (_character.global_position + Vector2(0, -20))

	# 等 PanelContainer 計算完大小後定位
	var w = _bg.size.x if _bg.size.x > 0 else 100
	_bg.position = Vector2(screen_pos.x - w / 2.0, screen_pos.y - 36)
