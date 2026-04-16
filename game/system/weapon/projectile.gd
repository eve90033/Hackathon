extends Area2D
class_name Projectile

## 投射物：用於遠程武器（如 Book）

var direction := Vector2.RIGHT
var speed := 150.0
var damage_amount := 2
var lifetime := 2.0
var team: ResourceDamageTeam

func _ready():
	# 碰撞設定：只偵測 hitbox (layer 3)，不偵測 body
	collision_layer = 0
	collision_mask = 4  # Layer 3 (hitboxes)
	monitoring = true
	monitorable = false
	area_entered.connect(_on_area_entered)
	# 存活時間
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta):
	position += direction * speed * delta

func _on_area_entered(area):
	if !(area is Hitbox):
		return
	# 同陣營或友軍不打
	if team and area.team and area.team.team == team.team:
		return
	if team and area.team and area.team.team in team.ally_team:
		return
	# 沒有 team 或投射物沒有 team 都跳過
	if !area.team or !team:
		return
	var dmg = ResourceDamage.new()
	dmg.amount = damage_amount
	dmg.push_force = 5
	area.damage_received.emit(dmg, global_position)
	queue_free()
