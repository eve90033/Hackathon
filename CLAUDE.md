# Monster RPG Hackathon

## 語言
所有溝通使用繁體中文。

## 工作習慣
- 不要猜，先搜尋確認再動手
- 視覺性的東西要用截圖驗證
- 同一個方法失敗 2 次就換路線，不要盲目重試
- **Subagent 或自己寫完程式碼後，必須實際啟動遊戲抓 stdout，grep `SCRIPT ERROR` 確認零錯誤才算完成。`--editor --quit --headless` 只做 import，不能捕捉所有編譯錯誤（例如 class_name 解析失敗）。**
- 新增 class_name 的 .gd 檔案後，其他腳本不要直接用類型名引用，改用 `preload()` + `set_script()` 避免 import 順序問題
- **寫 report / 整理文件 / 回報進度前，必須先跑 `git log`、`git status`、讀相關檔案**。每個 claim 附證據（commit hash / file:line）。memory 可能過時，只能當參考不能當 primary source。無證據就明說「我不確定」，不要憑記憶猜。

## Sync / 多人同步變更規則（避免改一個壞一個）

動任何 MultiplayerSynchronizer / MultiplayerSpawner / `@rpc` 前必做：

### Rule A：先讀 .gd 再碰 .tscn
**光看 SceneReplicationConfig 不算懂**。必 grep 該實體 `.gd`：
```bash
grep -nE "_is_server|is_multiplayer_authority|target_position|<屬性名>" <script>.gd
```
確認「誰讀、誰寫」後才動 .tscn 的 sync config。**不准以為某個 Synchronizer 是死 code 就拔掉**。

### Rule B：改完更新 SYNC_INVENTORY.md
`SYNC_INVENTORY.md` 是**活文件**，每個實體的同步屬性、每條 RPC 的 mode/caller/用途都列好。改 sync/RPC 同一 commit 要更新它。

### Rule C：Sync 類改動必手測 4 件事（再宣稱完成）
1. **玩家移動雙向可見**：自己走、對方看得到；對方走、我看得到
2. **怪物 AI**：移動、攻擊、死亡重生
3. **NPC 巡邏**：client 端實際在動
4. **登入還原**：level / HP / 同伴 / 武器 在對方螢幕上正確

光 `grep SCRIPT ERROR = 0` **不夠**，必實機雙 client 走一遍。

### Rule D：跨 authority 的 RPC 注意
- `@rpc("authority")` = 只有 node 的 authority 能**發**此 RPC。NetworkCharacter 的 authority 是 client peer；server 要通知它時**必用 `any_peer`**（sender 內部檢查 `== 1`）
- `call_local` = 連 caller 自己也執行，適用於 spawn 這種「所有端都要做一次」
- `call_remote`（預設）= 跳過 caller，適用於「本地已經做了，其他人補做」

### Rule E：`@rpc` handler 裡絕對不能 `await`
RPC handler 一旦 `await`，整個 function 變成 Coroutine → **Godot 4 MultiplayerAPI 的 RPC dispatch 會卡住**，其他 peer 的 MultiplayerSpawner broadcast / MultiplayerSynchronizer 更新會有機率 race 掉，表現為：
- 晚加入的玩家看不到早就在場的玩家
- 位置 sync 卡在 spawn point 不更新
- **偶發性**（跑 10 次中 1-2 次壞）

踩過的坑：`_request_spawn` 裡 `await get_tree().create_timer(1.0).timeout` 延遲廣播同伴 catch-up，結果 desktop 看 web 位置卡住、web 看不到 desktop。

正解：要延後執行，用 `Timer.timeout.connect()` 把 continuation 丟到外面跑：
```gdscript
@rpc("any_peer", "reliable")
func _request_spawn():
    spawner.spawn(...)                        # 立刻做
    var t := get_tree().create_timer(1.0)
    t.timeout.connect(_deferred_work.bind(sender), CONNECT_ONE_SHOT)
    # handler 到此 return，不卡 dispatch

func _deferred_work(target_peer: int):
    # 1 秒後在外部 context 跑，安全
    ...
```

### Rule F：Netfox StateSync + TickInterp 規則（2026-04-18 遷移後）

專案已從 `MultiplayerSynchronizer` 改用 Netfox。動同步前必讀：

1. **不要在兩個地方同時寫同一個 property**。StateSync 捕捉屬性寫進 history，TickInterp 在 `_process` 插值寫回 property。若 `_physics_process` 或其他 handler 也改同屬性，會跟 TickInterp 打架
2. **Authority peer 必須 queue_free TickInterp**（只有 `_server_tick` 純 tick-based 的實體例外，如 Animal）。Pattern：
   ```gdscript
   if is_multiplayer_authority():  # 或 _is_server()
       if has_node("TickInterp"):
           $TickInterp.queue_free()
   ```
3. **CharacterBody2D + move_and_slide**：AI 決策放 `NetworkTime.on_tick` (30Hz)，`move_and_slide` + 邊界 clamp 留 `_physics_process` (60Hz)。不要把 move_and_slide 放進 on_tick（它用 physics delta，不配合會變半速）
4. **Respawn / teleport** 必呼叫 `$TickInterp.teleport()`（如果 node 存在），避免遠端從舊位置滑行
5. **不要寫 `target_position` 這種 proxy 變數**。直接同步 `position`；TickInterp 和 StateSync 分工處理平滑 + 廣播
6. **NetworkTime.tickrate 預設 30Hz**，比舊 MP-Sync 20Hz 高 50%。流量 + CPU 多一點，jitter 容忍度也高
7. **WebSocket on TCP，Netfox `unreliable_ordered` hint 在這裡沒意義**。Netfox 修 rubber-band 靠 history buffer 按 tick 排序，不是靠 unreliable

## 截圖驗證標準
- 截圖後必須認真確認畫面內容是否正確，不能只看「有東西在渲染」就說正常
- UI 元素太小（<20px）時，不能從全畫面截圖判斷是否正確，必須放大或加 debug 輸出確認
- 頭像/圖示類的驗證：確認是正確的圖片內容，不是只有框或底色
- 如果無法從截圖確認，誠實說「我無法從截圖確認」而不是假裝看到了
- 同一個 bug 用不同方法嘗試超過 2 次仍失敗，停下來重新分析根本原因

## 項目概述
MMO Lite 即時動作 RPG + 怪獸收集，基於 NinjaAdventure 開源 Godot 項目改造。
共享世界多人體驗：登入 → 選角（92 種）→ 多人同場打怪 → 收服怪獸做同伴。
核心架構：Godot 內建 ENet P2P，Host 制（一台當 server+client，其他 Join）。

## 技術棧
- 引擎：Godot 4.3，GDScript
- 多人：**Netfox 1.35.3** StateSync + TickInterpolator（取代內建 MP-Sync）+ MultiplayerSpawner + @rpc，WebSocket 傳輸
- 素材：Ninja Adventure Asset Pack (CC0 授權)
- 設計文件：DESIGN_SUPPLEMENT.md（完整規格）、NETFOX_NOTES.md（Netfox API 筆記）、SYNC_INVENTORY.md（sync 清單）

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

- ✗ 多人連線（Godot ENet，架構已設計，見 DESIGN_SUPPLEMENT.md）
- ✗ 登入 + 選角畫面（暱稱 + Host/Join + 92 種角色選擇）
- ✗ 戰鬥系統（即時動作，狀態機已設計）
- ✗ 怪獸 AI（BehaviorChase + 狀態機）
- ✗ 收服 + 同伴系統（多人搶怪制）
- ✗ XP / 升級（Lv1-4，每級 +1HP）
- ✗ HP 掉落物
- ✗ Boss 戰（GiantFrog，多人 HP scaling）
- ✗ 存檔（本地 JSON）
- ✗ 對話/任務（不做）
- ✗ 物品欄/背包（不做）
- ✗ 新地圖（不做）

## Godot Autoloads

- ScreenShot (screenshot.gd)：F12 截圖 + 自動截圖（測試用）
- NetworkManager（待建）：ENet 連線管理、玩家資訊同步
- CompanionManager（待建）：同伴背包、切換、存檔
- GameManager（待建）：全域狀態、screen shake、系統訊息

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
