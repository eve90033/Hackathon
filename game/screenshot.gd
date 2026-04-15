extends Node

# Screenshot utility - press F12 to take a screenshot
func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		var image = get_viewport().get_texture().get_image()
		var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
		var path = "user://screenshot_%s.png" % timestamp
		image.save_png(path)
		print("Screenshot saved: ", path)
