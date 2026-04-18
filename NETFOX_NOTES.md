# Netfox API 筆記（給使用者快速對齊）

讀過 `addons/netfox/tick-interpolator.gd` + `state-synchronizer.gd` 原始碼。

## 核心概念

### NetworkTime（autoload）
全網共享 tick 時鐘，預設 `tickrate = 30`（30Hz）。
- `NetworkTime.tick` — 目前 tick 編號
- `NetworkTime.tick_factor` — 0→1，表示 tick 間的進度（給插值用）
- Signals: `before_tick_loop`, `after_tick(dt, tick)`, `after_tick_loop`

**要啟動 tick loop**：需要有人呼叫 `NetworkTime.start_on_multiplayer_spawn()` 或類似 — 要查 README 確認。

### StateSynchronizer（取代 MultiplayerSynchronizer）

```gdscript
[node name="StateSync" type="StateSynchronizer" parent="."]
root = NodePath("..")
properties = Array[String]([  "../:position", "../:ai_state"  ])
```

- **Authority 語意跟 MP-Sync 一樣**：`is_multiplayer_authority()` 判斷是否為 authority
- Authority 在 `after_tick` 發 RPC 廣播 state（`@rpc unreliable_ordered`）
- Remote 在 `after_tick` 拿 history 裡對應 tick 的 snapshot apply 到 property
- Packet 帶 tick 標籤，存 history buffer。晚到 / 失序也有對應位置可以放
- **Config**：`full_state_interval = 24`（每 24 tick 一次 full state，中間 diff 可省流量）

### TickInterpolator（平滑視覺）

```gdscript
[node name="TickInterp" type="TickInterpolator" parent="."]
root = NodePath("..")
properties = Array[String]([  "../:position"  ])
```

- 每 tick 取兩個連續 snapshot（`_state_from`, `_state_to`），在 `_process` 用 `tick_factor` 插值
- **視覺永遠晚 1 個 tick**（~33ms at 30Hz），平滑度靠這層 buffer
- `record_first_state = true` 預設：spawn 瞬間先拍一張，不用等第一個 tick
- **`teleport()` method**：跳過插值瞬間 apply（給 respawn / tab-hide snap 用）

## StateSync + TickInterp 合作流程（remote 端每 tick）

```
tick 開始:
  1. before_tick_loop: TickInterp apply _state_to（snap 到上 tick 末的 target）
  2. after_tick:
     - StateSync 從 history 拿 tick N 的 snapshot apply 到 properties
  3. after_tick_loop:
     - TickInterp push_state: _state_from = 舊 _state_to; _state_to = 當前 properties（新 tick N 的值）
  4. _process（render rate，可能多次）:
     - 根據 tick_factor 在 _state_from 和 _state_to 之間 lerp
```

**結果**：視覺平滑地從上 tick → 這 tick 移動，packet 晚到在 buffer 裡有位置，不會瞬移。

## 遷移 pattern（每個實體都做）

### .tscn 改動
1. 刪 `MultiplayerSynchronizer` node（含 replication_config）
2. 加 `StateSynchronizer`：
   - `root = NodePath("..")`
   - `properties = ["../:position", "../:其他 sync 屬性"]`
3. 加 `TickInterpolator`：
   - `root = NodePath("..")`
   - `properties = ["../:position"]`（只需視覺平滑的屬性）

### .gd 改動
1. 刪 `var target_position` 變數（直接同步 `position` 或 `global_position`）
2. 刪 `_physics_process` 裡 remote 分支的 `global_position.lerp(target_position, ...)` 和 snap
3. Authority 分支的 `target_position = global_position` 刪掉
4. Respawn / tab-hide snap → 呼叫 `$TickInterp.teleport()`

### 保留的東西
- `set_multiplayer_authority()` 照舊
- 所有 `@rpc` 函式照舊
- `MultiplayerSpawner` 照舊
- `is_multiplayer_authority()` / `_is_server()` 判斷邏輯照舊

## 重要注意點

1. **WebSocket 是 TCP，Netfox `unreliable_ordered` hint 沒用**。Netfox 的 rubber-band 修復主要來自 **history buffer 按 tick 排序**，不是來自 transport 的 unreliable
2. **TickInterp 寫 property 是在 `_process`**，physics_process 不要再手動改 position
3. **`NetworkTime.tickrate` 預設 30Hz**，比 MP-Sync 的 20Hz 高 50%，流量 + CPU 多一點但 jitter 容忍度也高
4. **Spawn 時 `record_first_state = true` 會搶先拍一張**，避免 remote 從 (0,0) 開始插值
5. **同步屬性格式**：`"../:property_name"`（相對於 StateSync node 的路徑 + 冒號 + 屬性名）
6. **⚠️ 關鍵 pattern 變更**：server AI 必須從 `_process` / `_physics_process` 改到 `NetworkTime.on_tick` signal handler。
   - 原因：TickInterp 的 `_after_tick_loop` 會把舊 state 寫回屬性，之後 `_process` 每 frame 插值 → 若 server AI 也在 `_process` 改 position，兩邊打架
   - 正確 pattern：server AI 每 tick 改一次 position（30Hz），TickInterp 負責 tick 間的視覺插值
   - `NetworkTime.on_tick` signal 的 `delta` 是 tick 間隔（1/30 ≈ 33ms），不是 frame delta
7. **CharacterBody2D + move_and_slide 的 hybrid pattern**：
   - `move_and_slide()` 用物理 delta（60Hz），從 signal handler 跑會變半速
   - 解法：AI 決策（更新 velocity、狀態切換）放 `on_tick`；`move_and_slide()` + 邊界 clamp 留 `_physics_process`
   - **Authority peer 的 `TickInterp` 在 `_ready` 裡 queue_free** — 避免 60Hz 物理被 TickInterp clobber
   - Remote peer 保留 TickInterp 做視覺平滑
   - 這是 Animal（沒 move_and_slide）vs Monster/Boss/NPC（有）的分野
8. **TickInterp.teleport()** — snap 時呼叫，跳過插值瞬間 apply（用於 respawn、tab-hide snap、巨大位移）

## 不確定 / 要實測確認的

- [x] **NetworkTime tick loop 自動啟動** — `NetworkEvents` autoload 監 `on_server_start` / `on_client_start` 會自動 call `NetworkTime.start()`。我們不用手動管
- [ ] `target_position` → 直接同步 `position` 取代（實測決定）
- [ ] `global_position` vs `position` 差異 — parent 沒 transform 時一樣，container 會有差
- [ ] Client authority on Player 能不能同步到 Server（應該可以，StateSync 用 `is_multiplayer_authority()` 判斷）
- [ ] `visible` 屬性能不能直接進 StateSync properties
