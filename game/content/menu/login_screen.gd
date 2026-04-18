extends Control


signal login_completed


@onready var google_button: Button = $CardPanel/CardVBox/GoogleButton
@onready var status_label: Label = $CardPanel/CardVBox/StatusLabel
@onready var title_main: Label = $TitleContainer/TitleMain
@onready var title_glow: Label = $TitleContainer/TitleGlow
@onready var title_shadow: Label = $TitleContainer/TitleShadow
@onready var bg_gradient: TextureRect = $BGGradient
@onready var character_layer: Node2D = $CharacterLayer
@onready var monster_layer: Node2D = $MonsterLayer
@onready var particle_layer: Node2D = $ParticleLayer


# Random character sprite candidates for the ambient "walking" characters
const CHARACTER_CANDIDATES := [
	"Knight", "Ninja", "Samurai", "Wizard", "Pirate",
	"Archer", "Boy", "Child", "GladiatorBlue", "Eskimo",
	"IronArmor", "PriestWhite", "RobinHood", "Viking"
]

# Random monsters to float around the corners
const MONSTER_CANDIDATES := [
	"Slime", "Dragon", "Eye", "Racoon", "Ghost",
	"Fox", "Bamboo", "Frog", "Butterfly", "Bee"
]

var _t: float = 0.0


func _ready():
	google_button.pressed.connect(_on_google_login)
	NetworkManager.connection_succeeded.connect(_on_connected)
	NetworkManager.login_response.connect(_on_login_response)
	GoogleAuth.login_completed.connect(_on_google_auth_success)
	GoogleAuth.login_failed.connect(_on_google_auth_failed)

	_setup_background()
	_spawn_ambient_characters()
	_spawn_corner_monsters()
	_start_title_animation()
	_start_particles()

	if "--auto-login" in OS.get_cmdline_user_args():
		get_tree().create_timer(1.0).timeout.connect(_on_google_login)


func _process(delta: float) -> void:
	_t += delta
	# Title group floats up and down gently
	var bob = sin(_t * 1.5) * 5.0
	$TitleContainer.position.y = bob
	# Glow pulses
	var pulse = 0.45 + (sin(_t * 2.0) + 1.0) * 0.22
	title_glow.modulate.a = pulse


func _setup_background():
	# Create a deep-night gradient: dark purple top → dark blue bottom
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(0.08, 0.06, 0.14, 1.0),   # top — deep purple
		Color(0.12, 0.14, 0.28, 1.0),   # middle — night blue
		Color(0.05, 0.08, 0.16, 1.0),   # bottom — very dark blue
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])

	var gt := GradientTexture2D.new()
	gt.gradient = gradient
	gt.width = 256
	gt.height = 720
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)

	bg_gradient.texture = gt


func _spawn_ambient_characters():
	# Spawn character sprites walking across at the bottom of screen
	var viewport_size = Vector2(1280, 720)
	var lanes = [520.0, 600.0, 650.0]  # Lower third, stacked for depth
	for i in range(3):
		var char_name = CHARACTER_CANDIDATES[randi() % CHARACTER_CANDIDATES.size()]
		var sprite_path = "res://assets/Actor/Character/%s/SpriteSheet.png" % char_name
		if !ResourceLoader.exists(sprite_path):
			continue
		var tex = load(sprite_path)
		if !tex:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.hframes = 4
		sprite.vframes = 7
		# Walking-right animation row is row 2 (y=2); use row 1 for down
		sprite.frame_coords = Vector2i(0, 2)  # walking RIGHT
		sprite.scale = Vector2(4.0, 4.0)
		var y = lanes[i]
		var x = 100.0 + i * 450.0
		sprite.position = Vector2(x, y)
		sprite.modulate = Color(1, 1, 1, 0.85)
		sprite.z_index = int(y)  # Lower is behind
		character_layer.add_child(sprite)
		_animate_walking(sprite, viewport_size, i)


func _animate_walking(sprite: Sprite2D, viewport_size: Vector2, idx: int):
	# Sprite slowly drifts across screen, loops forever
	var target_x = viewport_size.x + 200.0
	var duration = 18.0 + randf() * 8.0
	var tween = create_tween().set_loops()
	tween.tween_property(sprite, "position:x", target_x, duration)
	tween.tween_callback(func():
		sprite.position.x = -200.0
	)

	# Walking cycle: alternate frames 0 and 2 of row 2 (walking right)
	var frame_tween = create_tween().set_loops()
	frame_tween.tween_callback(func(): sprite.frame_coords = Vector2i(0, 2)).set_delay(0.25)
	frame_tween.tween_callback(func(): sprite.frame_coords = Vector2i(2, 2)).set_delay(0.25)


func _spawn_corner_monsters():
	# Monsters floating around the edges
	var positions = [
		Vector2(130, 130),    # top-left
		Vector2(1150, 140),   # top-right
		Vector2(110, 480),    # middle-left
		Vector2(1170, 500),   # middle-right
	]
	for i in range(4):
		var mon_name = MONSTER_CANDIDATES[randi() % MONSTER_CANDIDATES.size()]
		var path = "res://assets/Actor/Monster/%s/SpriteSheet.png" % mon_name
		if !ResourceLoader.exists(path):
			continue
		var tex = load(path)
		if !tex:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.hframes = 4
		sprite.vframes = 4
		sprite.frame_coords = Vector2i(0, 0)
		sprite.scale = Vector2(4.0, 4.0)
		sprite.position = positions[i]
		sprite.modulate = Color(1, 1, 1, 0.9)
		monster_layer.add_child(sprite)
		# Bobbing animation
		var base_y = sprite.position.y
		var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
		tween.tween_property(sprite, "position:y", base_y - 14.0, 1.4 + randf() * 0.4)
		tween.tween_property(sprite, "position:y", base_y + 14.0, 1.4 + randf() * 0.4)
		# Slow idle animation (alternate frames)
		var anim_tween = create_tween().set_loops()
		anim_tween.tween_callback(func(): sprite.frame_coords = Vector2i(0, 0)).set_delay(0.7)
		anim_tween.tween_callback(func(): sprite.frame_coords = Vector2i(1, 0)).set_delay(0.7)


func _start_particles():
	# Warm orb particles floating up
	var particles := CPUParticles2D.new()
	particles.amount = 60
	particles.lifetime = 10.0
	particles.preprocess = 5.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(700, 10)
	particles.position = Vector2(640, 760)
	particles.direction = Vector2(0, -1)
	particles.spread = 30.0
	particles.initial_velocity_min = 20.0
	particles.initial_velocity_max = 50.0
	particles.gravity = Vector2(0, -5)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.5
	particles.color = Color(1.0, 0.85, 0.55, 1.0)
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([
		Color(1.0, 0.85, 0.55, 0.0),
		Color(1.0, 0.88, 0.60, 0.9),
		Color(1.0, 0.75, 0.40, 0.6),
		Color(1.0, 0.65, 0.30, 0.0),
	])
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
	particles.color_ramp = ramp
	particle_layer.add_child(particles)

	# Sparkles (smaller, faster)
	var sparkles := CPUParticles2D.new()
	sparkles.amount = 25
	sparkles.lifetime = 4.0
	sparkles.preprocess = 2.0
	sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	sparkles.emission_rect_extents = Vector2(640, 360)
	sparkles.position = Vector2(640, 360)
	sparkles.direction = Vector2(0, -1)
	sparkles.spread = 180.0
	sparkles.initial_velocity_min = 5.0
	sparkles.initial_velocity_max = 15.0
	sparkles.scale_amount_min = 1.0
	sparkles.scale_amount_max = 2.5
	sparkles.color = Color(1.0, 0.95, 0.8, 1.0)
	var s_ramp := Gradient.new()
	s_ramp.colors = PackedColorArray([
		Color(1, 1, 1, 0.0),
		Color(1, 0.95, 0.75, 0.9),
		Color(1, 0.9, 0.6, 0.0),
	])
	s_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	sparkles.color_ramp = s_ramp
	particle_layer.add_child(sparkles)


func _start_title_animation():
	# Placeholder for any future init
	pass


func _on_google_login():
	google_button.disabled = true
	status_label.text = "Google 登入中..."
	GoogleAuth.start_login()


func _on_google_auth_success(user_data: Dictionary):
	var user_id = user_data.get("id", "")
	var display_name = user_data.get("name", "")
	NetworkManager.my_info.user_id = user_id
	if not display_name.is_empty():
		NetworkManager.my_info.name = display_name
	NetworkManager.flog("[Login] Google user: %s (%s)" % [display_name, user_id])

	status_label.text = "連線中..."
	var server_url = NetworkManager.server_url
	NetworkManager.flog("[Login] Connecting to %s" % server_url)
	var err = NetworkManager.join_game(server_url)
	if err != OK:
		status_label.text = "連線失敗，嘗試自己建立..."
		NetworkManager.flog("[Login] join_game failed, trying auto_connect")
		NetworkManager.auto_connect()


func _on_google_auth_failed(reason: String):
	status_label.text = "登入失敗：" + reason
	google_button.disabled = false


func _on_connected():
	status_label.text = "已連線！檢查角色資料..."
	var my_id = multiplayer.get_unique_id()
	NetworkManager.flog("[Login] _on_connected: my_id=%d is_host=%s user_id=%s" % [my_id, str(NetworkManager.is_host()), NetworkManager.my_info.user_id])

	var user_id = NetworkManager.my_info.user_id
	if NetworkManager.is_host():
		NetworkManager.login_as_host(user_id)
	else:
		NetworkManager.flog("[Login] Sending request_login to server for user_id=%s" % user_id)
		NetworkManager.request_login.rpc_id(1, user_id)


func _on_login_response(user_id: String, data: Dictionary):
	NetworkManager.flog("[Login] _on_login_response: user_id=%s data=%s" % [user_id, str(data)])
	if data.is_empty():
		status_label.text = "歡迎新玩家！"
		NetworkManager.flog("[Login] New player, showing character select")
		login_completed.emit()
	else:
		NetworkManager.my_info.name = data.get("name", "Player")
		NetworkManager.my_info.character = data.get("character", "Knight")
		# Cache full saved data locally so _load_player_data can restore level/xp/companion/weapon
		NetworkManager.player_database[user_id] = data.duplicate()
		var my_id = multiplayer.get_unique_id()
		NetworkManager.players[my_id] = NetworkManager.my_info.duplicate()
		NetworkManager.flog("[Login] Returning player, cached save data locally: %s" % str(data))
		NetworkManager._register_player.rpc(NetworkManager.my_info)
		status_label.text = "歡迎回來，%s！" % NetworkManager.my_info.name
		await get_tree().create_timer(0.5).timeout
		NetworkManager.flog("[Login] Entering world now")
		get_tree().get_first_node_in_group("main").enter_world()
