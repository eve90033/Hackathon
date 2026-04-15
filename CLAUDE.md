# Monster RPG Hackathon

## 語言
所有溝通使用繁體中文。

## 工作習慣
- 不要猜，先搜尋確認再動手
- 視覺性的東西要用截圖驗證
- 同一個方法失敗 2 次就換路線，不要盲目重試

## 項目概述
Cassette Beasts 風格怪獸收集 RPG，基於 NinjaAdventure 開源 Godot 項目改造。
目前只有 NinjaAdventure 的基底系統，怪獸/戰鬥系統尚未建立。
目標平台和多人方案尚未定案。

## 技術棧
- 引擎：Godot 4.3，GDScript
- 素材：Ninja Adventure Asset Pack (CC0 授權)

## 目錄結構

```
D:\Hackathon\
├── game/                    # Godot 項目根目錄（project.godot 在這）
│   ├── system/              # NinjaAdventure 15 個核心系統（不要動）
│   ├── content/             # NinjaAdventure 原始內容（可擴充）
│   │   ├── character/       # 4 個角色預設（ninja_blue, samurai_blue, samurai_green, pig）
│   │   ├── weapon/          # 5 種武器（club, axe, big_sword, bone, book）
│   │   ├── destroyable/     # 3 種可破壞物（crate, grass, pot）
│   │   ├── environment/     # 2 個環境（autumn, swamp）
│   │   ├── map/             # map_village.tscn 主地圖
│   │   ├── menu/            # title_screen.tscn
│   │   ├── team/            # 4 個陣營資源
│   │   └── behavior/        # behavior_enemy.tscn
│   ├── audio/music/         # 原始 4 首音樂
│   ├── theme/               # UI 主題 + nine-patch + 字體
│   ├── assets/              # 素材包（保持原始目錄結構）
│   │   ├── Actor/Monster/   # 66 怪獸（Faceset.png + SpriteSheet.png 或 Named.png）
│   │   ├── Actor/Boss/      # 20 Boss（多部件：Body, Head, Wing）
│   │   ├── Actor/Character/ # 92 可玩角色（Faceset + SpriteSheet）
│   │   ├── Actor/Animal/    # 26 動物
│   │   ├── Audio/Musics/    # 41 首 .ogg
│   │   ├── Audio/Sounds/    # 132 音效（11 類子目錄）
│   │   ├── Audio/Jingles/   # 15 jingles (.wav)
│   │   ├── Backgrounds/     # Tilesets(19張) + Animated + Vehicles
│   │   ├── FX/              # 75 特效（Attack/Elemental/Magic/Projectile/Slash/Smoke）
│   │   ├── Items/           # 140 物品圖示（11 類）
│   │   └── Ui/              # Dialog/Emote/Font/Input/Receptacle/Skill Icon/Theme
│   ├── main.gd / main.tscn  # 啟動場景（標題 → 遊戲）
│   └── world.gd / world.tscn # 主世界管理器
├── tools/                   # Godot 4.3 執行檔（win64）
└── CLAUDE.md
```

## NinjaAdventure 核心系統（system/）

15 個模組，全部互相依賴，不要改路徑：

| 系統 | 核心類別 | 用途 |
|------|---------|------|
| character/ | Character, SpriteCharacter, ActorSprite, Animal | 角色移動+動畫（8 狀態 × 4 方向） |
| damage/ | DamageArea, Hitbox, ResourceDamageTeam | 傷害碰撞 + 陣營判定 |
| weapon/ | Weapon, ResourceWeapon | 武器系統（SLASH/PIERCING/RANGE） |
| stat/ | ResourceLife, ResourceStat | 生命系統（5 個 signal） |
| behavior/ | BehaviorFollow, BehaviorFollowPath, AreaTargetFinder | AI 行為 |
| camera/ | CameraGrid | 格子相機（320×176/格，0.8s SINE 過渡） |
| map/ | Map | 地圖基底（4 層 TileMap） |
| environment/ | ResourceEnvironment, EnvironmentArea, EnvironmentShape | 天氣+音樂+色調切換 |
| teleporter/ | Teleporter | 傳送門（雙向+轉場動畫） |
| transition/ | Transition | 場景轉場（INSTANT/FADE） |
| destroyable/ | Destroyable | 可破壞物（HP+擊退+粒子） |
| particle/ | Particle, ResourceParticle | GPU 粒子系統 |
| input/ | HumanController | 玩家輸入 → move_vector |
| ui/ | PlayerUi, ReceptacleBar | 愛心血條 |
| color_correction/ | ColorCorrection | Shader 色彩校正 |

## 遊戲流程（目前）

main.gd → world.tscn → 載入 map_village.tscn
- HumanController 讀 Input → Character.move_vector → physics 移動
- CameraGrid 跟隨玩家，跨格平滑過渡
- EnvironmentArea 偵測位置 → 切換天氣/音樂/色調
- 可破壞物件（箱子/草/罐子）
- NPC 沿路徑巡邏
- 傳送門場景切換

## 目前可用功能

- ✓ 角色移動 + 4 方向動畫
- ✓ 武器系統框架（5 種武器）
- ✓ 傷害碰撞 + 陣營判定
- ✓ 環境天氣（雨/雪/霧/雲/樹葉/光線）
- ✓ NPC + AI 行為（BehaviorFollow 跟隨 / BehaviorFollowPath 路徑巡邏）
- ✓ 可破壞物件（箱子/草/罐子）
- ✓ 傳送門 + 場景轉場
- ✓ 格子相機平滑跟隨
- ✓ 愛心血條 UI
- ✓ 怪物上場系統（小怪 + Boss 均已驗證可用）

## 已建立的素材系統

### 小怪（66 種，全部 64×64, 4列×4行）
- sprite_monster.gd — 4方向, IDLE+MOVING
- monster_character.gd/.tscn — 小怪角色基底
- 已測試：Racoon, Slime, Dragon, Eye

### Boss（20 種，水平幀列，多檔案）
- sprite_boss.gd — 多 texture 動畫切換（Idle/Walk/Attack/Hit/Jump），flip_h 朝向
- boss_character.gd/.tscn — Boss 角色基底，含定時攻擊展示
- 已測試：GiantFrog, DemonCyclop

### 玩家角色（92 種，全部 64×112, 4列×7行）
- 直接用 character.tscn + SpriteCharacter，換 texture 即可
- 已測試：Knight 替換 NinjaBlue

### 動物（26 種，32×16, 2列×1行）
- animal.tscn — 左右翻轉，2 幀走路
- 適合背景裝飾，不適合戰鬥單位

### 地圖
- 23 張 tileset（村莊/沙漠/地牢/田野/水域等），目前只用 1 張村莊地圖

## 尚未建立

- ✗ 戰鬥系統（即時動作方向已確認可行）
- ✗ 怪獸 AI（追逐/攻擊玩家）
- ✗ 存檔/升級/經驗值
- ✗ 對話/任務
- ✗ 多人連線
- ✗ 物品欄/背包
- ✗ 新地圖（素材充足但未製作）

## Godot Autoloads

- ScreenShot (screenshot.gd)：F12 截圖 + 自動截圖（測試用）

## 素材包注意事項

- SpriteCharacter 動畫：hframes=4(方向) × vframes=7(動作), frame_coords 控制
- 小怪統一 64×64：SpriteSheet.png 和具名 PNG 格式相同
- Boss 各自尺寸不同（40~82px），TenguBlue 的 Walk/Attack 高度與 Idle 不一致
- Dragon 系列 Boss 為模組化拼接（Head+Body+Wing），尚未測試
- AtlasTexture 在 Godot 4 有 bug，用 hframes/vframes + frame_coords 代替
- Godot 內建截圖：get_viewport().get_texture().get_image().save_png()
- 新增腳本後需跑一次 --editor --quit 讓 Godot 匯入

## 跑遊戲

```bash
"D:/Hackathon/tools/Godot_v4.3-stable_win64_console.exe" --path "D:/Hackathon/game"
```
