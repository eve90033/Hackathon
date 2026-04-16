extends Node2D
class_name ChatBubble

## 聊天氣泡：顯示在角色頭上，3 秒後淡出

var label: Label
var bg: ColorRect


func show_message(text: String):
	# 半透明黑底背景
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.position = Vector2(-30, -32)
	bg.size = Vector2(60, 14)
	add_child(bg)

	# 白色文字
	label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 6)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-30, -33)
	label.size = Vector2(60, 14)
	add_child(label)

	# 根據文字長度調整背景寬度
	var text_width = max(text.length() * 5, 30)
	bg.position.x = -text_width / 2
	bg.size.x = text_width
	label.position.x = -text_width / 2
	label.size.x = text_width

	# 2.5 秒後淡出 0.5 秒，然後移除
	var tween = create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(queue_free)
