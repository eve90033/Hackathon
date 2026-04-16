extends Node2D

## 怪物分區視覺提示：在地面畫半透明圓環標示弱/中/強怪區域
## 圓環跟隨玩家相機格子更新，只在玩家附近顯示

const SPAWN_CENTER := Vector2(-31.0, -129.0)
const RING_RADIUS_START := 200.0
const RING_STEP := 80.0

# Tier boundaries (matching world.gd spawn logic: ring/12, tier=min(ring,2))
# Tier 0: ring 0-1 → radius 200-360
# Tier 1: ring 2-3 → radius 360-520
# Tier 2: ring 4+  → radius 520+
const TIER_BOUNDARIES := [360.0, 520.0]

const TIER_COLORS := [
	Color(0.3, 0.85, 0.3, 0.12),   # 弱怪區 — 綠
	Color(0.95, 0.8, 0.2, 0.12),   # 中怪區 — 黃
	Color(0.9, 0.25, 0.2, 0.12),   # 強怪區 — 紅
]

const TIER_BORDER_COLORS := [
	Color(0.3, 0.85, 0.3, 0.35),
	Color(0.95, 0.8, 0.2, 0.35),
	Color(0.9, 0.25, 0.2, 0.35),
]

const TIER_NAMES := ["安全地帶", "警戒區域", "危險地帶"]

var _screen_labels: Array[Node2D] = []
const _SL = preload("res://system/ui/screen_label.gd")


func _ready():
	# 放置在 spawn center
	position = SPAWN_CENTER
	z_index = -10  # 在地面下方

	# 建立區域名稱標籤（用 ScreenLabel 螢幕空間渲染）
	for i in TIER_NAMES.size():
		var color = TIER_BORDER_COLORS[i] * Color(1,1,1,2)
		var radius = TIER_BOUNDARIES[i] if i < TIER_BOUNDARIES.size() else TIER_BOUNDARIES[-1] + 160.0
		# 用一個 Marker 節點固定世界座標，ScreenLabel 追蹤它
		var marker = Node2D.new()
		marker.position = Vector2(0, -radius - 10)
		add_child(marker)
		var sl = _SL.create(marker, TIER_NAMES[i], 14, color, Vector2.ZERO)
		_screen_labels.append(sl)


func _draw():
	# 從外到內畫：強→中→弱（讓內圈覆蓋外圈）
	var outer_radius := TIER_BOUNDARIES[-1] + 200.0  # 強怪區外邊界

	# Tier 2: 強怪區（外環）
	draw_circle(Vector2.ZERO, outer_radius, TIER_COLORS[2])
	_draw_ring_border(outer_radius, TIER_BORDER_COLORS[2])
	_draw_ring_border(TIER_BOUNDARIES[1], TIER_BORDER_COLORS[2])

	# Tier 1: 中怪區（中環 - 覆蓋內部）
	draw_circle(Vector2.ZERO, TIER_BOUNDARIES[1], TIER_COLORS[1])
	_draw_ring_border(TIER_BOUNDARIES[0], TIER_BORDER_COLORS[1])

	# Tier 0: 弱怪區（內環）
	draw_circle(Vector2.ZERO, TIER_BOUNDARIES[0], TIER_COLORS[0])

	# 村莊安全區（最內圈，半透明白色）
	draw_circle(Vector2.ZERO, RING_RADIUS_START - 20.0, Color(1, 1, 1, 0.06))
	_draw_ring_border(RING_RADIUS_START - 20.0, Color(1, 1, 1, 0.2))


func _draw_ring_border(radius: float, color: Color):
	# 用虛線圓環畫邊界（每 4 段畫 2 段、跳 2 段）
	var segments := 64
	for i in segments:
		if (i % 4) >= 2:  # 跳過每組的後 2 段
			continue
		var angle_start = (float(i) / segments) * TAU
		var angle_end = (float(i + 1) / segments) * TAU
		var p1 = Vector2(cos(angle_start), sin(angle_start)) * radius
		var p2 = Vector2(cos(angle_end), sin(angle_end)) * radius
		draw_line(p1, p2, color, 1.0, true)
