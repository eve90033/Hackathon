extends Sprite2D


## Boss spritesheet: horizontal strip, each animation is a separate texture
## No direction system - bosses face one direction only

enum Anim {IDLE, MOVING, ATTACK, JUMP, HIT}

const IMAGE_SPEED := 6

@export var tex_idle: Texture2D
@export var tex_walk: Texture2D
@export var tex_attack: Texture2D
@export var tex_jump: Texture2D
@export var tex_hit: Texture2D
@export var frame_size: int = 40

var anim: int = Anim.IDLE:
	set(v):
		if anim == v:
			return
		anim = v
		current_image = 0
		_apply_texture()

var direction := Vector2.DOWN:
	set(v):
		direction = v
		# Flip sprite based on horizontal direction
		if v.x > 0.1:
			flip_h = false
		elif v.x < -0.1:
			flip_h = true

var current_image := 0.0
var _frame_count := 1


func _ready():
	_apply_texture()


func _apply_texture():
	var tex: Texture2D
	match anim:
		Anim.IDLE: tex = tex_idle
		Anim.MOVING: tex = tex_walk
		Anim.ATTACK: tex = tex_attack
		Anim.JUMP: tex = tex_jump
		Anim.HIT: tex = tex_hit
	if tex == null:
		tex = tex_idle
	if tex == null:
		return
	texture = tex
	_frame_count = max(1, tex.get_width() / frame_size)
	hframes = _frame_count
	vframes = 1
	frame = 0


func _process(delta: float) -> void:
	current_image += IMAGE_SPEED * delta
	var idx = int(fmod(current_image, _frame_count))
	if frame != idx:
		frame = idx
