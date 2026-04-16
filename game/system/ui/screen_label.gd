extends Node2D

## 螢幕空間文字：在 CanvasLayer 渲染，不受 viewport 縮放影響
## 用法：var sl = ScreenLabel.create(parent_node, "文字", font_size, color, offset)

var _canvas: CanvasLayer
var _label: Label
var _bg: ColorRect
var _target: Node2D
var _world_offset: Vector2
var _manual_visible := true  # 手動控制可見性
var _has_bg: bool

static func create(
	parent: Node2D,
	text: String,
	font_size: int = 18,
	color: Color = Color.WHITE,
	offset: Vector2 = Vector2(0, -24),
	bg_color: Color = Color.TRANSPARENT,
	canvas_layer: int = 6
) -> Node2D:
	var node = Node2D.new()
	var script = load("res://system/ui/screen_label.gd")
	node.set_script(script)
	parent.add_child(node)
	node._init_label(parent, text, font_size, color, offset, bg_color, canvas_layer)
	return node


func _init_label(parent: Node2D, text: String, font_size: int, color: Color, offset: Vector2, bg_color: Color, canvas_layer: int):
	_target = parent
	_world_offset = offset
	_has_bg = bg_color.a > 0.01

	_canvas = CanvasLayer.new()
	_canvas.layer = canvas_layer
	add_child(_canvas)

	var container = Control.new()
	_canvas.add_child(container)

	if _has_bg:
		_bg = ColorRect.new()
		_bg.color = bg_color
		container.add_child(_bg)

	_label = Label.new()
	_label.text = text
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", color)
	_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(_label)


func set_text(t: String):
	if _label:
		_label.text = t


func set_label_visible(v: bool):
	_manual_visible = v
	if _canvas:
		_canvas.visible = v


func get_label() -> Label:
	return _label


func _process(_delta):
	if !_label or !_target or !is_inside_tree() or !is_instance_valid(_target):
		return
	# 跟隨 target 的可見狀態 + 手動控制
	if _canvas and _target is CanvasItem:
		_canvas.visible = _target.visible and _manual_visible
	var vp = get_viewport()
	if !vp:
		return
	var ct = vp.get_canvas_transform()
	var screen_pos = ct * (_target.global_position + _world_offset)

	# 用實際渲染寬度置中（支援中英文混排）
	var text_w = max(_label.get_minimum_size().x, 60)
	_label.size = Vector2(text_w, 30)
	_label.position = Vector2(screen_pos.x - text_w / 2.0, screen_pos.y)

	if _has_bg and _bg:
		_bg.size = Vector2(text_w + 8, _label.size.y)
		_bg.position = Vector2(screen_pos.x - (text_w + 8) / 2.0, screen_pos.y)
