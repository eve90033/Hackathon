extends Node

var auto_screenshot_timer := 0.0
var auto_screenshots_taken := 0
const AUTO_SCREENSHOT_DELAY := 2.0
const AUTO_SCREENSHOT_COUNT := 3

func _ready():
	if NetworkManager.is_dedicated_server or DisplayServer.get_name() == "headless":
		set_process(false)
		set_process_input(false)
		return
	auto_screenshot_timer = AUTO_SCREENSHOT_DELAY

func _process(delta):
	if auto_screenshots_taken < AUTO_SCREENSHOT_COUNT:
		auto_screenshot_timer -= delta
		if auto_screenshot_timer <= 0:
			_take_screenshot("auto_%d" % auto_screenshots_taken)
			auto_screenshots_taken += 1
			auto_screenshot_timer = AUTO_SCREENSHOT_DELAY

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		_take_screenshot("manual")

func _take_screenshot(prefix:String):
	var image = get_viewport().get_texture().get_image()
	var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
	var path = "user://screenshot_%s_%s.png" % [prefix, timestamp]
	image.save_png(path)
	print("Screenshot saved: ", path)
