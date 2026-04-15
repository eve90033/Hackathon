extends Sprite2D


## Monster spritesheet: 4 columns (directions) × 4 rows (walk cycle)
## Same direction convention as SpriteCharacter but only IDLE/MOVING animations

enum Anim {IDLE, MOVING}
enum FrameDirection{RIGHT=3,DOWN=0,LEFT=2,UP=1}

const IMAGE_SPEED := 6
const ANIMATION_DATA := {
	Anim.IDLE:[0],
	Anim.MOVING:[0,1,2,3],
}

var anim:int = Anim.IDLE:
	set(v):
		if anim == v:
			return
		anim = v
		current_image = 0
		image_list = ANIMATION_DATA[anim]
		update_animation()

var direction := Vector2.DOWN:
	set(v):
		direction = v
		update_animation()
var image_list:PackedInt32Array = [0]:
	set(v):
		image_list = v
var current_image:= 0.0:
	set(v):
		current_image = wrap(v, 0, image_list.size())
		update_animation()


func update_animation():
	frame_coords.x = direction_to_frame(direction)
	frame_coords.y = image_list[floor(current_image)]


func _process(delta: float) -> void:
	current_image += IMAGE_SPEED * delta


func direction_to_frame(dir) -> int:
	var deg_angle := rad_to_deg(dir.angle())
	var angle_to_int:int = round(deg_angle / 90)
	var angle:int = wrap(angle_to_int, 0, 4)
	return FrameDirection.values()[angle]
