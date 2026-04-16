extends CanvasLayer

## UI 優先級管理器：控制 UI 顯示順序，避免多個重要 UI 同時出現
##
## 5 層優先級（高→低）：
##   0 - SYSTEM:  系統訊息（斷線通知、錯誤等）
##   1 - CINEMA:  Boss 入場演出（鏡頭接管，禁止輸入）
##   2 - DEATH:   死亡儀式（倒數+重生）
##   3 - NOTIFY:  升級/收服/成就通知（排隊顯示）
##   4 - CHAT:    聊天輸入（最低優先級）

enum Priority { SYSTEM = 0, CINEMA = 1, DEATH = 2, NOTIFY = 3, CHAT = 4 }

signal notify_queue_empty
signal cinema_started
signal cinema_ended

var active_priority := Priority.CHAT  # 目前最高活躍優先級
var _active_layers: Dictionary = {}   # { Priority: bool }
var _notify_queue: Array[Dictionary] = []
var _showing_notify := false
var _notify_panel: PanelContainer
var _notify_label: Label
var _notify_icon: TextureRect


func _ready():
	layer = 50  # 在大部分 UI 之上
	_build_notify_ui()
	for p in Priority.values():
		_active_layers[p] = false


func _build_notify_ui():
	# 通知面板：畫面上方居中，半透明黑底
	_notify_panel = PanelContainer.new()
	_notify_panel.anchor_left = 0.5
	_notify_panel.anchor_right = 0.5
	_notify_panel.anchor_top = 0.0
	_notify_panel.offset_left = -120
	_notify_panel.offset_right = 120
	_notify_panel.offset_top = 8
	_notify_panel.visible = false
	_notify_panel.z_index = 10

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_notify_panel.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	_notify_panel.add_child(hbox)

	_notify_icon = TextureRect.new()
	_notify_icon.custom_minimum_size = Vector2(20, 20)
	_notify_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_notify_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_notify_icon.visible = false
	hbox.add_child(_notify_icon)

	_notify_label = Label.new()
	_notify_label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_notify_label.add_theme_font_size_override("font_size", 14)
	_notify_label.add_theme_color_override("font_color", Color.WHITE)
	_notify_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hbox.add_child(_notify_label)

	add_child(_notify_panel)


## 設定某層為活躍/停止
func set_layer_active(priority: int, active: bool):
	_active_layers[priority] = active
	_update_active_priority()
	if priority == Priority.CINEMA:
		if active:
			cinema_started.emit()
		else:
			cinema_ended.emit()


## 查詢當前是否允許某優先級的 UI 操作
func can_show(priority: int) -> bool:
	return priority <= active_priority


## 查詢是否正在演出模式（禁止玩家輸入）
func is_cinema() -> bool:
	return _active_layers.get(Priority.CINEMA, false)


## 推送通知到排隊系統
func push_notify(text: String, color: Color = Color.WHITE, duration: float = 2.0, icon_path: String = ""):
	_notify_queue.append({
		"text": text,
		"color": color,
		"duration": duration,
		"icon": icon_path,
	})
	_try_show_next_notify()


func _try_show_next_notify():
	if _showing_notify or _notify_queue.is_empty():
		if _notify_queue.is_empty() and !_showing_notify:
			notify_queue_empty.emit()
		return
	# 如果有更高優先級的 UI 正在顯示，延遲通知
	if !can_show(Priority.NOTIFY):
		return
	_showing_notify = true
	var info = _notify_queue.pop_front()
	_notify_label.text = info["text"]
	_notify_label.add_theme_color_override("font_color", info["color"])

	# 圖示
	if info["icon"] != "" and ResourceLoader.exists(info["icon"]):
		_notify_icon.texture = load(info["icon"])
		_notify_icon.visible = true
	else:
		_notify_icon.visible = false

	# 動畫：從上滑入 → 停留 → 向上滑出
	_notify_panel.visible = true
	_notify_panel.modulate.a = 0.0
	_notify_panel.offset_top = -20
	var tw = create_tween()
	tw.tween_property(_notify_panel, "offset_top", 8.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.set_parallel(true)
	tw.tween_property(_notify_panel, "modulate:a", 1.0, 0.2)
	tw.set_parallel(false)
	tw.tween_interval(info["duration"])
	tw.tween_property(_notify_panel, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		_notify_panel.visible = false
		_showing_notify = false
		_try_show_next_notify()
	)


func _update_active_priority():
	active_priority = Priority.CHAT
	for p in Priority.values():
		if _active_layers[p]:
			active_priority = p
			break


func _process(_delta):
	# 當高優先級解除後，嘗試顯示排隊的通知
	if !_showing_notify and !_notify_queue.is_empty() and can_show(Priority.NOTIFY):
		_try_show_next_notify()
