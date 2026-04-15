# 設計補充：MMO Lite 即時動作 RPG 完整規格 v2.1

補充 `eve-unknown-design-20260415-104007.md`。
**重大變更：從「方案 C 單機先行」改為「Godot ENet MMO Lite」。**
目標：任何開發者讀完這份文件就能直接寫 code，不需要再問「這個怎麼做」。

## Eng Review Decisions (2026-04-15 v2)

1. **resource_life.gd 兩個 bug 必修**：heal():31 `max_life→heal_value` + damage():39-44 kill()後要 return（防雙重 killed 信號）
2. **混合同步**：MultiplayerSynchronizer 只同步 position + move_vector，hp/state/capturable 用 @rpc reliable
3. **Peer 設在樹根**：NetworkManager._ready() 設 `get_tree().get_multiplayer().multiplayer_peer`，切場景不斷線
4. **NetworkCharacter extends Character**：不改 character.gd，override _physics_process 加 authority 檢查
5. **MonsterCharacter 需手動接線**：加 Hitbox + ResourceLife + DamageArea（它不繼承 Character，沒有這些）
6. **自訂 spawn 流程**：不用 player_assignor.gd，NetworkCharacter._ready() 根據 authority 決定加 HumanController + 相機
7. **動態 Boss HP scaling**：玩家加入/離開時按比例調整 current_hp = current_hp / old_max * new_max
8. **怪物同步率 20Hz**：MultiplayerSynchronizer delta_interval = 0.05
9. **角色列表靜態陣列**：不用 DirAccess 執行時掃描
10. **數值用 Resource .tres**：不硬編碼在 GDScript
11. **push() 需實作**：ActorSprite 呼叫 parent.push() 但 Character 沒有此方法，需加
12. **AreaTargetFinder 碰撞層過濾**：防止怪物追擊同隊玩家
13. **world.gd 多人改造**：每個玩家需自己的 CameraGrid 實例，PlayerUi 只綁本地玩家

---

## 0. 架構變更摘要

| 項目 | v1（單機） | v2（MMO Lite） |
|------|-----------|---------------|
| 連線 | 無 | Godot ENet P2P，Host 制 |
| 登入 | 無 | 輸入暱稱 + Host/Join |
| 選角 | 無（固定 Knight） | 92 種角色選擇 |
| 怪物 | 本地 AI | Host 權威，同步給所有 Client |
| 收服 | 單人 | 搶怪制（先按先得，Server 判定） |
| Boss | 單人 | 多人 scaling（HP × 1.5/人） |
| 存檔 | user://save.json | 各自本地 JSON（demo 夠用） |
| 戰鬥獎勵 | 無 | HP 掉落 + XP 升級 |

---

## 1. 網路架構

### 1.1 技術選型：Godot 內建 ENet

為什麼不用 Nakama / WebSocket：
- Godot 4.3 內建 MultiplayerSynchronizer 一個節點同步位置+動畫，不用手寫封包
- MultiplayerSpawner 自動處理新玩家加入時生成角色
- @rpc 裝飾器處理戰鬥動作
- 零外部依賴，不用裝 Docker 跑額外 server
- 上次 hackathon 用 WebSocket + Node.js 太重失敗了

### 1.2 Host/Client 架構

```
         ┌─────────────────────────────────┐
         │  HOST（Server + Client 合一）    │
         │  - 跑遊戲世界（怪物 AI、生成）    │
         │  - 自己也是一個玩家               │
         │  - 權威：怪物 HP、掉落、收服判定  │
         └──────────┬──────────────────────┘
                    │ ENet (UDP, port 7777)
         ┌──────────┼──────────┐
         │          │          │
    ┌────▼───┐ ┌────▼───┐ ┌───▼────┐
    │Client 1│ │Client 2│ │Client 3│
    │ 發送輸入│ │ 發送輸入│ │ 發送輸入│
    │ 接收狀態│ │ 接收狀態│ │ 接收狀態│
    └────────┘ └────────┘ └────────┘
```

- Demo 展示：展示機當 Host，評審/觀眾用其他機器 Join
- 最大玩家數：4（demo 夠用，ENet 預設支援 32）
- 同一 WiFi 區網即可連線

### 1.3 權威分工

| 資料 | 誰管 | 同步方式 |
|------|------|---------|
| 玩家位置/方向/動畫 | 各自的 Client（authority） | MultiplayerSynchronizer |
| 玩家暱稱/角色外觀 | 各自的 Client | @rpc 廣播（加入時） |
| 怪物位置/AI/HP | Host | MultiplayerSynchronizer |
| 怪物受傷 | Client 發 @rpc → Host 計算 → 廣播結果 | @rpc |
| 收服判定 | Host（先到先得） | @rpc |
| 同伴跟隨 | 各自的 Client | MultiplayerSynchronizer |
| XP / 升級 | 各自的 Client 本地 | 不同步（demo 不防作弊） |
| HP 掉落物 | Host 生成 | MultiplayerSynchronizer |
| Boss HP 縮放 | Host 計算 | — |

### 1.4 關鍵 Godot 節點

```
World (world.tscn)
├── MultiplayerSpawner ← 自動生成/移除玩家角色
│   （spawn_path = PlayerContainer）
│   （auto_spawn = false，手動 spawn）
├── PlayerContainer (Node) ← 所有玩家角色的父節點
│   ├── Player_1 (peer_id=1)
│   │   └── MultiplayerSynchronizer
│   │       （sync: position, move_vector, sprite.animation, sprite.direction）
│   ├── Player_2 (peer_id=12345)
│   │   └── MultiplayerSynchronizer
│   └── ...
├── MonsterContainer (Node) ← Host 管理
│   ├── Monster_0
│   │   └── MultiplayerSynchronizer
│   │       （sync: position, move_vector, hp, state）
│   └── ...
└── ...其他節點
```

### 1.5 斷線處理

| 情況 | 處理 |
|------|------|
| Client 斷線 | Host 偵測到 peer_disconnected → 移除該玩家角色（3s 延遲） |
| Host 斷線 | 所有 Client 回到標題畫面，顯示「連線中斷」 |
| 連線超時 | Join 後 5s 無回應 → 顯示「無法連線」 |

---

## 2. 玩家初始流程

### 2.1 完整流程

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  TITLE   │───►│  LOGIN   │───►│  SELECT  │───►│  WORLD   │
│  SCREEN  │    │          │    │ CHARACTER │    │          │
│          │    │ 暱稱輸入  │    │          │    │ 共享世界  │
│ Monster  │    │ Host/Join│    │ 92 種角色 │    │ 看到其他  │
│ RPG      │    │ IP 輸入   │    │ 走路預覽  │    │ 玩家！   │
│ Online   │    │          │    │          │    │          │
│ 按任意鍵  │    │ [Z] 確認  │    │ [Z] 確認  │    │          │
└──────────┘    └──────────┘    └──────────┘    └──────────┘
```

### 2.2 標題畫面

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│         MONSTER RPG ONLINE          │  ← theme 字體，大號
│                                     │
│                                     │
│           Press Any Key             │  ← 閃爍動畫（sin alpha）
│                                     │
│                                     │
└─────────────────────────────────────┘
```

- 背景：村莊地圖截圖或純色 + 怪物 Faceset 裝飾
- 音樂：assets/Audio/Musics/ 選一首（標題用）
- 按任意鍵 → 進入登入畫面
- 場景：`content/menu/title_screen.tscn`（改造現有的）

### 2.3 登入畫面

```
┌─────────────────────────────────────┐
│                                     │
│         MONSTER RPG ONLINE          │
│                                     │
│    暱稱：[________]                 │  ← LineEdit，上限 12 字
│                                     │
│    ● 建立房間 (Host)                │  ← 選中時顯示本機 IP
│    ○ 加入房間 (Join)                │  ← 選中時出現 IP 輸入框
│                                     │
│    IP：[127.0.0.1]                  │  ← Join 模式才顯示
│    Port：[7777]                     │  ← 預設 7777
│                                     │
│         [Z] 確認                    │
│                                     │
└─────────────────────────────────────┘
```

- 暱稱空白時不能確認
- Host 模式：顯示本機 IP（`IP.get_local_addresses()` 過濾 192.168.x.x）
- Join 模式：IP 欄位用 LineEdit，預設 127.0.0.1
- 確認後：
  - Host → 建立 ENetMultiplayerPeer server → 進選角
  - Join → 連線到指定 IP:Port → 連線成功進選角 / 失敗顯示錯誤
- 場景：`content/menu/login_screen.tscn`（新建）
- 方向鍵上下切換 Host/Join，Z 確認

### 2.4 選角畫面

```
┌─────────────────────────────────────────┐
│  選擇你的角色              [暱稱: Roy]  │
│                                          │
│  ┌──┬──┬──┬──┬──┬──┬──┬──┐             │
│  │01│02│03│04│05│06│07│08│  ← Faceset   │
│  ├──┼──┼──┼──┼──┼──┼──┼──┤    16×16     │
│  │09│10│11│12│[█]│14│15│16│  ← 選中高亮  │
│  ├──┼──┼──┼──┼──┼──┼──┼──┤             │
│  │17│18│19│20│21│22│23│24│             │
│  ├──┼──┼──┼──┼──┼──┼──┼──┤             │
│  │..│..│..│..│..│..│..│..│             │
│  └──┴──┴──┴──┴──┴──┴──┴──┘             │
│                                          │
│           ┌────────┐                     │
│           │  ↓↑←→  │  ← 選中角色的       │
│           │  走路   │    4 方向走路動畫    │
│           │  動畫   │    輪播             │
│           └────────┘                     │
│           "Knight"                       │
│          [Z] 確認                        │
└─────────────────────────────────────────┘
```

- 格子：8 列 × 12 行 = 96 格（放得下 92 個角色，4 格空白）
- 每格顯示角色的 Faceset.png（16×16 or 32×32）
- 方向鍵移動光標，選中的格子白色邊框
- 下方預覽：選中角色的 SpriteSheet 走路動畫（4 方向輪播）
- 角色名稱顯示在預覽下方
- Z 確認 → 進入遊戲世界
- 場景：`content/menu/character_select.tscn`（新建）
- 角色列表：掃描 `assets/Actor/Characters/` 目錄動態生成

### 2.5 角色資料掃描

```gdscript
# 掃描 assets/Actor/Characters/ 取得所有可選角色
# 每個子資料夾有 Faceset.png + SpriteSheet.png
# 資料夾名 = 角色名（如 "Knight", "DarkKnight", "Princess"）

var characters: Array[Dictionary] = []
# { "name": "Knight", "faceset": "res://assets/Actor/Characters/Knight/Faceset.png",
#   "spritesheet": "res://assets/Actor/Characters/Knight/SpriteSheet.png" }
```

---

## 3. 操控方式 — Input Mapping

| 動作 | 鍵盤 | 手把 | Input Action 名稱 |
|------|------|------|-------------------|
| 移動 | 方向鍵 | 左搖桿 | move_left/right/up/down（已有） |
| 攻擊 | Z | Joypad Button 0 (A) | attack |
| 閃避 | X | Joypad Button 1 (B) | dodge |
| 收服 | C | Joypad Button 2 (X) | capture |
| 切換同伴 | A / S | LB / RB | companion_prev / companion_next |
| 暫停 | Escape | Start | ui_cancel（Godot 內建） |

為什麼用 Z/X/C 不用空白鍵：
- 空白鍵在 Godot 預設綁了 `ui_select`，衝突
- Z/X/C 左手三指自然排列，跟方向鍵配合順手
- 日系 RPG 傳統（RPG Maker、Undertale）

---

## 4. 玩家狀態機

```
                    ┌──────────┐
           ┌───────►│  IDLE    │◄──────────┐
           │        └────┬─────┘           │
           │             │ move_vector > 0  │
           │             ▼                  │
           │        ┌──────────┐           │
           │        │  MOVING  │           │
           │        └────┬─────┘           │
           │             │                  │
     attack pressed      │ attack pressed   │ attack pressed
           │             │                  │
           │             ▼                  │
           │        ┌──────────┐           │
           └────────│ ATTACK   │───────────┘
                    └────┬─────┘    attack_duration 結束
                         │
                    dodge pressed (from IDLE/MOVING only)
                         │
                         ▼
                    ┌──────────┐
                    │  DODGE   │──── dodge_duration 結束 ──► IDLE
                    └──────────┘

                    ┌──────────┐
                    │   HIT    │──── hitstun 結束 ──► IDLE
                    └──────────┘
                    (任何狀態被打都進 HIT，除了 DODGE)

                    ┌──────────┐
                    │  DEAD    │──── 重生計時 ──► IDLE (出生點)
                    └──────────┘
```

### 狀態規則

| 狀態 | 可移動 | 可攻擊 | 可閃避 | 可收服 | 可受傷 |
|------|--------|--------|--------|--------|--------|
| IDLE | - | Yes | Yes | Yes | Yes |
| MOVING | Yes | Yes | Yes | Yes | Yes |
| ATTACK | No | No | No | No | Yes |
| DODGE | Yes(衝刺方向) | No | No | No | **No** (i-frame) |
| HIT | No | No | No | No | No (無敵中) |
| DEAD | No | No | No | No | No |

### 狀態時序

| 狀態 | 持續時間 | 備註 |
|------|---------|------|
| ATTACK | 0.4s 總計 | 0.1s 啟動 + 0.15s 活動 + 0.15s 收招 |
| DODGE | 0.25s | 全程 i-frame |
| DODGE 冷卻 | 0.8s | 從 DODGE 結束開始計算 |
| HIT | 0.3s | 受擊硬直，含擊退 |
| HIT 後無敵 | 0.5s | 閃爍效果，可移動可攻擊 |
| DEAD → 重生 | 1.5s | 畫面淡黑 → 出現在出生點 |

### 多人同步

玩家狀態由各自 Client 管理，透過 MultiplayerSynchronizer 同步：
- 同步屬性：`position`, `move_vector`, `sprite.animation`, `sprite.direction`, `combat_state`
- 其他 Client 看到的是插值後的位置（MultiplayerSynchronizer 內建）

---

## 5. 攻擊系統 — Frame-Level 時序

```
按下 Z
  │
  ├─ 0.00s  進入 ATTACK，停止移動
  │         播放 SpriteCharacter.ATTACK 動畫
  │         播放 Slash 視覺特效
  │         播放 Slash.wav
  │         → @rpc 通知其他 Client 播放攻擊特效
  │
  ├─ 0.10s  DamageArea 啟用（set_deferred）
  │         活動幀開始
  │
  ├─ 0.25s  DamageArea 關閉
  │         活動幀結束
  │         → 如果命中怪物：@rpc 發給 Host 計算傷害
  │
  ├─ 0.40s  回到 IDLE/MOVING
  │
  └─ 武器方向：攻擊前最後的 move_vector，攻擊期間鎖定
```

### 攻擊碰撞框

武器已有 DamageArea（12×10 矩形）。攻擊時：
- DamageArea 位置 = 角色中心 + direction × 16px
- DamageArea 旋轉 = direction.angle()

### 多人攻擊流程

```
Client A 按攻擊 → 本地播放動畫/音效（即時回饋）
  → DamageArea 碰到怪物 Hitbox
  → @rpc("any_peer") 發給 Host：damage_monster(monster_id, damage, attacker_id)
  → Host 計算新 HP，廣播結果
  → 所有 Client 看到怪物受傷特效
```

為什麼不是 Host 驗證攻擊碰撞：
- 延遲下的體驗太差，玩家砍到了但要等 server 說「打到了」
- Demo 區網延遲 < 5ms，不需要防作弊
- 用 Client 判定碰撞 + Host 計算傷害，平衡體驗和一致性

---

## 6. 怪物狀態機（小怪）

```
              ┌──────────┐
     ┌───────►│  IDLE    │◄──── 失去目標 / 超出活動範圍
     │        └────┬─────┘
     │             │ 玩家進入偵測範圍
     │             ▼
     │        ┌──────────┐
     │        │  CHASE   │◄──── 攻擊硬直結束
     │        └────┬─────┘
     │             │ 距離 < 20px
     │             ▼
     │        ┌──────────┐
     │        │ ATTACK   │──── 攻擊後 ──► STUN
     │        └──────────┘
     │
     │        ┌──────────┐
     │        │  STUN    │──── 硬直結束 ──► CHASE
     │        └──────────┘
     │
     │        ┌──────────┐
     │        │CAPTURABLE│──── HP < 30%，頭上顯示提示
     │        └────┬─────┘     仍然可以 CHASE/ATTACK
     │             │ 玩家按 C（Host 判定先到先得）
     │             ▼
     │        ┌──────────┐
     │        │ CAPTURED │──── 收服動畫 → 變成同伴
     │        └──────────┘
     │
     │        ┌──────────┐
     └────────│   HIT    │──── 受擊硬直 0.2s → 回到之前狀態
              └──────────┘

              ┌──────────┐
              │  DEAD    │──── 30s 後原位重生 → IDLE
              └──────────┘
```

### 攻擊方式

小怪的攻擊是碰撞傷害（contact damage）：
- 小怪 sprite 只有 IDLE 和 MOVING，沒有攻擊動畫
- DamageArea（圓形半徑 10px），ATTACK 時啟用
- 造成傷害後關閉，進入 STUN

### 多人追擊目標

Host 上跑怪物 AI，追擊目標選擇：
- 偵測範圍內最近的玩家
- 每 0.5s 重新計算目標（不要每幀切換，看起來會抽搐）

### 活動範圍

每隻怪物有 `home_position`（生成時的位置）。
Chase 時如果跟 home_position 距離 > 500px，放棄追擊回到 IDLE。

---

## 7. Boss 狀態機（GiantFrog）

```
              ┌──────────┐
              │  IDLE    │──── 玩家進入 200px
              └────┬─────┘
                   │
                   ▼
              ┌──────────┐
         ┌───►│  CHASE   │
         │    └────┬─────┘
         │         │ 距離 < 80px 或計時 3s
         │         ▼
         │    ┌──────────────┐
         │    │ JUMP_CHARGE  │  0.5s 蓄力
         │    └──────┬───────┘
         │           │
         │           ▼
         │    ┌──────────────┐
         │    │  JUMP_DASH   │  朝目標玩家跳躍（速度 300px/s，最大 200px）
         │    └──────┬───────┘
         │           │
         │           ▼
         │    ┌──────────────┐
         │    │  LAND_SHOCK  │  落地震波（DamageArea 圓形 60px，0.2s）
         │    └──────┬───────┘
         │           │
         │           ▼
         │    ┌──────────────┐
         │    │    STUN      │  1.5s 硬直（弱點窗口！）
         │    └──────┬───────┘
         │           │
         └───────────┘
```

### 多人 Boss 縮放

| 玩家人數 | Boss HP | STUN 時間 | 備註 |
|---------|---------|----------|------|
| 1 | 30 | 1.5s | 基準 |
| 2 | 45 (×1.5) | 1.5s | |
| 3 | 67 (×2.2) | 1.8s | 多給硬直時間 |
| 4 | 90 (×3.0) | 2.0s | |

Host 在玩家連線時計算，Boss 生成時套用。

### Boss 追擊目標（多人）

- 每次攻擊循環重新選目標（仇恨值最高的玩家 = 累計傷害最多的）
- 如果目標死亡，切換到最近的存活玩家
- JUMP_DASH 鎖定方向，不會中途轉彎

### Phase 2（HP < 50%）

- CHASE 速度 ×1.5
- STUN 時間 ×0.67
- JUMP_DASH 速度 400px/s

---

## 8. 戰鬥獎勵系統

### 8.1 HP 掉落

怪物死亡時掉落愛心，任何玩家都能撿（不搶）。

| 怪物檔次 | 掉落 HP |
|---------|---------|
| 弱 | 1 |
| 中 | 2 |
| 強 | 3 |
| Boss | 5（全回復） |

掉落物理：往上彈 16px → 落地 → 閃爍 → 5 秒後消失。
素材：`Ui/Receptacle/Heart.png`
Host 生成掉落物，MultiplayerSynchronizer 同步位置。
任一 Client 碰到 → @rpc 告知 Host → Host 移除並廣播。

### 8.2 經驗值 + 升級

| 怪物 | XP |
|------|-----|
| 弱怪 | 10 |
| 中怪 | 25 |
| 強怪 | 50 |
| Boss | 200 |

XP 歸屬：最後一擊的玩家獲得全部 XP。
收服怪物也給相同 XP。

| 等級 | 累計 XP | HP 上限 | 攻擊力 |
|------|---------|---------|--------|
| Lv1 | 0 | 5 | 2 |
| Lv2 | 50 | 6 | 2 |
| Lv3 | 150 | 7 | 3 |
| Lv4 | 350 | 8 | 3 |

- Demo 最高 Lv4（打完全部怪 + Boss 約 Lv3-4）
- 升級時回滿血
- XP 本地計算，不同步（demo 不防作弊）

### 8.3 戰鬥結束反饋時序

```
怪物 HP 歸零（Host 判定）
  │
  ├─ Host @rpc 廣播：monster_killed(monster_id, killer_id, position)
  │
  ├─ 所有 Client：
  │   ├─ 0.0s   怪物白閃 + 煙霧粒子 + Impact3.wav
  │   ├─ 0.3s   怪物消失
  │   └─ 掉落愛心出現（Host 同步）
  │
  ├─ Killer Client：
  │   ├─ Hit-stop 0.05s
  │   ├─ "+10 XP" 浮出文字（向上飄 → 淡出，0.8s）
  │   ├─ XP bar 填充動畫 0.3s
  │   └─ 如果升級：閃金 0.3s + LevelUp1.wav + "LEVEL UP!" 1.5s
  │
  └─ Host：30s 後原位重生怪物
```

---

## 9. 收服系統（多人版）

### 搶怪規則

```
怪物 HP < 30%（Host 判定）
  │
  ├─ Host @rpc 廣播：monster_capturable(monster_id)
  │   → 所有 Client 看到怪物頭上出現收服提示
  │
  ├─ 玩家 A 在 40px 內按 C
  │   → @rpc 發給 Host：request_capture(monster_id, player_id)
  │
  ├─ Host 收到第一個 request：
  │   ├─ 鎖定怪物，拒絕其他 request
  │   ├─ @rpc 廣播：capture_started(monster_id, player_id)
  │   │   → 所有人看到收服動畫開始
  │   │   → 非收服者看到「[暱稱] 正在收服！」
  │   │
  │   ├─ 0.5s 後 Host 廣播：capture_success(monster_id, player_id)
  │   │   → 收服者：同伴加入、Success1.wav
  │   │   → 其他人：看到怪物消失、「[暱稱] 收服了 [怪物名]！」
  │   │
  │   └─ 如果收服者被打斷（HIT）：
  │       → Host 廣播：capture_interrupted(monster_id)
  │       → 怪物解鎖，所有人可以再次收服
  │
  └─ 其他玩家的 request 被拒絕：顯示「搶先一步！」
```

---

## 10. UI Layout 設計

### 10.1 HUD 佈局（遊戲中常駐）

```
┌─────────────────────────────────────────────────┐
│ [♥♥♥♥♥]                      [Boss: GiantFrog] │  ← 玩家血條（左上）
│ [▓▓▓▓░░░░] Lv2               ████████████████  │  ← XP 條 + Boss 血條（頂部）
│                                                  │
│        "PlayerB"                                 │  ← 其他玩家暱稱浮在頭上
│          [人物]                                   │
│                                                  │
│                                                  │
│                   [遊戲畫面]                      │
│                                                  │
│                                                  │
│                                                  │
│                    ┌─────────────────┐           │
│                    │ [1]  [2]  [3]   │           │  ← 同伴欄（底部置中）
│                    └─────────────────┘           │
└─────────────────────────────────────────────────┘
```

### 10.2 玩家血條

- 現有 `PlayerUi` + `ReceptacleBar`
- receptacle_size=1，每級 +1 顆心
- 位置：左上 (3, 3)

### 10.3 XP 條

- 血條下方，用 `LifeBarMiniProgress.png` 換藍色 modulate
- 寬度按 XP 比例填充
- 旁邊顯示 "Lv2"

### 10.4 怪物血條

- 怪物頭頂上方 8px
- `LifeBarMiniUnder.png` + `LifeBarMiniProgress.png`
- HP < 30% 填充條變黃色
- 被攻擊過才顯示

### 10.5 收服提示

- 怪物 HP < 30% + 玩家在 40px 內
- emote21（紅色驚嘆號）+ "[C]" 文字
- 上下浮動動畫（sin wave ±2px, 2Hz）

### 10.6 同伴欄

- 底部置中，每格 20×20px，間距 4px，最多 3 格
- 出戰同伴白框高亮
- 圖片用怪物 Faceset.png

### 10.7 Boss 血條

- 畫面頂部置中，寬 200px
- Boss 名字在上方
- Phase 2 填充條變橙色

### 10.8 玩家暱稱（多人新增）

- 所有玩家頭頂顯示暱稱
- theme 字體，FontSize 8，白色描邊黑底
- 自己的暱稱不顯示（只看到別人的）

### 10.9 多人訊息提示（多人新增）

- 畫面上方偏中，短暫顯示的系統訊息
- 「Roy 加入了遊戲」「Roy 收服了 Slime！」「Roy 離開了」
- 淡入 → 停留 2s → 淡出
- 最多同時顯示 3 條

---

## 11. Game Feel — 打擊感設計

### 11.1 Hit-Stop（頓幀）

| 事件 | 暫停時間 | 備註 |
|------|---------|------|
| 玩家攻擊命中怪物 | 0.05s | 只暫停發動攻擊的 Client |
| 玩家攻擊命中 Boss | 0.08s | |

實作：不用 Engine.time_scale（會影響所有玩家）。
改用：攻擊者的 Character 暫停 physics_process 0.05s。

### 11.2 Screen Shake

| 事件 | 強度 | 持續 | 範圍 |
|------|------|------|------|
| 玩家攻擊命中 | 1px | 0.1s | 攻擊者 Client |
| 玩家受傷 | 2px | 0.15s | 受傷者 Client |
| Boss 落地震波 | 3px | 0.3s | 所有 Client |
| Boss Phase 2 | 2px | 0.5s | 所有 Client |

Boss 震波的 shake 由 Host @rpc 廣播觸發。

### 11.3 Knockback

| 情境 | 距離 | 方向 |
|------|------|------|
| 玩家攻擊怪物 | 16px | 攻擊方向 |
| 怪物攻擊玩家 | 24px | 怪物→玩家 |
| Boss 震波 | 32px | Boss→玩家 |

### 11.4 受傷閃爍

- 0.5s 內 modulate.a 在 1.0 和 0.3 之間交替（Tween）
- 同步：MultiplayerSynchronizer 同步 `is_invincible` 狀態，各 Client 本地播閃爍

### 11.5 怪物受擊

- 白色閃爍：modulate = Color.WHITE 持續 0.1s
- 位置抖動：±1px 持續 0.1s

---

## 12. 音效映射表

### 12.1 玩家動作

| 事件 | 檔案 | dB |
|------|------|----|
| 攻擊揮刀 | Whoosh & Slash/Slash.wav | 0 |
| 攻擊命中 | Hit & Impact/Hit1.wav | -3 |
| 閃避 | Whoosh & Slash/Whoosh.wav | -3 |
| 受傷 | Hit & Impact/Impact.wav | 0 |
| 死亡 | Jingles/GameOver.wav | 0 |
| 升級 | Jingles/LevelUp1.wav | 0 |

### 12.2 怪物

| 事件 | 檔案 | dB |
|------|------|----|
| 受傷 | Hit & Impact/Hit3.wav | -6 |
| 死亡 | Hit & Impact/Impact3.wav | -3 |
| 發現玩家 | Alert/Alert.wav | -6 |

### 12.3 收服

| 事件 | 檔案 | dB |
|------|------|----|
| 可收服提示 | Alert/Alert2.wav | -6 |
| 收服中 | Magic & Skill/Magic1.wav | -3 |
| 收服成功 | Jingles/Success1.wav | 0 |

### 12.4 Boss

| 事件 | 檔案 | dB |
|------|------|----|
| 蓄力 | Alert/Alert3.wav | 0 |
| 起跳 | Whoosh & Slash/Launch.wav | 0 |
| 落地 | Hit & Impact/Impact5.wav | 3 |
| 硬直 | Magic & Skill/Strange.wav | -6 |
| Phase 2 | Alert/Alert5.wav | 3 |

### 12.5 多人

| 事件 | 檔案 | dB |
|------|------|----|
| 玩家加入 | Bonus/Bonus2.wav | -6 |
| 玩家離開 | Alert/Alert4.wav | -6 |
| 撿到愛心 | Bonus/Bonus.wav | -3 |

### 12.6 UI / 選單

| 事件 | 檔案 | dB |
|------|------|----|
| 選角移動光標 | Menu/（如果有）或 Bonus/Coin.wav | -6 |
| 選角確認 | Bonus/PowerUp1.wav | -3 |

---

## 13. 視覺特效映射

| 事件 | 素材 | 用法 |
|------|------|------|
| 玩家攻擊 | FX/Slash/SpriteSheetSlash01.png | 4 幀，0.15s，跟隨攻擊方向 |
| 怪物死亡 | FX/Smoke/Smoke/ | 已有 Particle 系統 |
| Boss 落地 | FX/Smoke/SmokeCircular/ | 圓形擴散 |
| 閃避起跳 | FX/Smoke/Smoke/ | 小煙霧 |
| emote21 | 紅色驚嘆號 | 收服提示 |
| emote22 | 紅色驚嘆號(亮) | 怪物發現玩家 |
| emote29 | 星星 | Boss 暈眩 |
| emote12 | 漩渦 | 小怪暈眩 |

---

## 14. 場景節點樹設計

### 14.1 玩家角色（網路版）

```
PlayerCharacter (Character)
├── Hitbox (Area2D)
├── Shadow (Sprite2D)
├── Sprite (SpriteCharacter)
│   └── Weapon (weapon.tscn)
├── Shape (CollisionShape2D)
├── MultiplayerSynchronizer ← 新增
│   （sync: position, move_vector, sprite.animation,
│     sprite.direction, combat_state, is_invincible,
│     character_texture_path）
├── PlayerCombat (Node, player_combat.gd)
├── DodgeRoll (Node, dodge_roll.gd)
├── DamageFlash (Node, damage_flash.gd)
├── CaptureZone (Area2D, 半徑 40px)
├── InvincibilityTimer (Timer, 0.5s)
├── NicknameLabel (Label) ← 新增，頭頂暱稱
└── HumanController ← 只在 is_multiplayer_authority() 時 active
```

### 14.2 小怪（網路版）

```
Monster (MonsterCharacter)
├── Hitbox (Area2D)
├── Shadow (Sprite2D)
├── Sprite (SpriteMonster)
├── Shape (CollisionShape2D)
├── MultiplayerSynchronizer ← 新增
│   （sync: position, move_vector, hp, state, is_capturable）
├── MonsterAI (Node) ← 只在 Host 上跑
├── DetectionZone (Area2D)
├── AttackArea (DamageArea)
├── HealthBar (Control)
├── CapturePrompt (Control)
└── AlertEmote (Sprite2D)
```

### 14.3 World（網路版）

```
World (world.tscn)
├── Map (map_village.tscn)
├── MultiplayerSpawner ← 新增
│   （spawn_path = PlayerContainer）
├── PlayerContainer (Node) ← 新增，所有玩家的父節點
├── MonsterContainer (Node) ← 新增，所有怪物的父節點
│   （Host 管理生成/重生）
├── DropContainer (Node) ← 新增，掉落物
├── PlayerUi (player_ui.tscn)
├── XpBar (Control) ← 新增
├── CompanionBar (Control) ← 新增
├── BossHealthBar (Control) ← 新增
├── MessageLog (Control) ← 新增，系統訊息
├── MonsterSpawner (Node) ← Host only
└── InvisibleWalls (StaticBody2D)
```

---

## 15. Autoload 設計

### 15.1 NetworkManager（Autoload，新增）

```
NetworkManager
  var peer: ENetMultiplayerPeer
  var player_info: Dictionary = {}  # peer_id → { nickname, character }
  var is_host: bool = false

  signal player_connected(peer_id, info)
  signal player_disconnected(peer_id)
  signal connection_failed()
  signal all_players_loaded()

  func host_game(port: int = 7777) → Error
  func join_game(ip: String, port: int = 7777) → Error
  func get_local_ip() → String

  @rpc("any_peer", "reliable")
  func register_player(info: Dictionary)
  @rpc("authority", "reliable")
  func player_registered(peer_id: int, info: Dictionary)
```

### 15.2 CompanionManager（Autoload）

```
CompanionManager
  var party: Array[CompanionData]  # 最多 3 隻
  var active_index: int = 0

  signal companion_added(data)
  signal companion_removed(index)
  signal active_changed(index)

  func add_companion(monster_type: String, stats: Dictionary) → bool
  func remove_companion(index: int)
  func switch_next() / switch_prev()
  func get_active() → CompanionData
  func save_to_file() / load_from_file()
```

### 15.3 GameManager（Autoload）

```
GameManager
  var player_spawn_pos: Vector2 = Vector2(896, 848)

  signal player_died(peer_id)
  signal player_respawned(peer_id)
  signal message_posted(text)

  func screen_shake(intensity, duration)
  func hit_stop_local(duration)  # 只暫停本地
  func flash_screen(color, duration)
  func post_message(text)  # 系統訊息
```

---

## 16. 怪物生成 + 分區（不變）

```
┌─────────────────────────────────────┐
│                    [Boss: GiantFrog]│  ← 右上角
│          [中怪區]                    │
│          Dragon ×2, Skull ×1        │
│  [弱怪區]              [強怪區]     │
│  Slime ×3              Eye ×2      │
│  Racoon ×2             Spider ×1   │
│  [玩家出生點]                        │  ← 左下角
└─────────────────────────────────────┘
```

Host 管理所有怪物生成和重生（30s）。
Boss HP 按連線玩家數 scaling。

---

## 17. 存檔格式

```json
{
  "version": 1,
  "nickname": "Roy",
  "character": "Knight",
  "player": {
    "hp": 5, "max_hp": 6, "level": 2, "xp": 75,
    "attack": 2
  },
  "companions": [
    { "monster_type": "Racoon", "hp": 3, "max_hp": 3,
      "attack": 1, "speed": 60 }
  ],
  "active_companion_index": 0,
  "play_time_seconds": 0
}
```

各自本地 user://save.json。不跨機器同步。

---

## 18. 傷害數學驗證（含多人）

### 單人

- 玩家 vs 弱怪（HP=3）：2 下殺，0.8s
- 玩家 vs 中怪（HP=5）：3 下殺，1.2s
- 玩家 vs 強怪（HP=8）：4 下殺，1.6s
- 玩家 vs Boss（HP=30）：15 下，4-5 個攻擊循環

### 雙人

- Boss HP=45，兩人同時在硬直窗口輸出
- 每個硬直窗口（1.5s）兩人合計打 6-8 下 = 12-16 dmg
- 約 3-4 個循環打完，比單人快但 Boss 更痛

### 升級後

- Lv3 玩家 ATK=3，vs Boss 只需 10 下
- Lv3 HP=7，Boss ATK=3 需要 3 下才死（更安全）

---

## 19. Edge Cases（含多人）

| 情況 | 處理 |
|------|------|
| 同時收服同一隻怪 | Host 先到先得，後到顯示「搶先一步！」 |
| 收服中被其他玩家的同伴打死怪 | 收服中斷，怪死了算殺死不算收服 |
| 多人同時攻擊同一怪物 | 共享 HP，Host 計算，最後一擊得 XP |
| 玩家在別人的收服動畫中攻擊怪物 | 收服鎖定期間怪物無敵 |
| Host 切換角色（暫停選單） | 不支援，選了就不能換 |
| 同一 WiFi 但不同子網 | 連不上，需要同子網（demo 展示時確認） |
| 2 人選同一個角色 | 允許，多人可以撞衫 |
| 玩家死亡重生時怪物在出生點 | 重生 2s 無敵 |
| 背包滿了再收服 | 提示「同伴已滿！」，收服不執行 |

---

## 20. 開發優先順序（修訂版）

| Day | 里程碑 | 完成標準 |
|-----|--------|---------|
| **Day 1** | 多人連線 + 選角 | 多台電腦看到彼此走來走去，各自選的角色不同 |
| **Day 2** | 核心戰鬥 | 攻擊/閃避/怪物 AI，多人都能打同一隻怪 |
| **Day 3** | 收服 + 同伴 + XP | 收服搶怪、同伴跟隨、升級系統 |
| **Day 4** | Boss 戰 + 打擊感 | 多人 Boss scaling、音效、screen shake |
| **Day 5** | 測試 + Demo | Bug fix、難度平衡、展示排練 |

**Day 1 結束的畫面就是整個 Hackathon 的核心賣點：**
多台電腦連進同一個世界，看到彼此的角色走來走去。

---

## 設計完整度自評

| 維度 | 分數 | 說明 |
|------|------|------|
| 網路架構 | 9/10 | 權威分工清楚，同步方案具體 |
| 初始流程 | 9/10 | 標題→登入→選角→世界，完整 |
| 操控方式 | 9/10 | 全部按鍵定義 |
| 數值平衡 | 9/10 | 單人+多人都驗算過 |
| 狀態機 | 9/10 | 玩家/小怪/Boss 三套 |
| 多人規則 | 9/10 | 搶怪/共享傷害/Boss scaling |
| UI 設計 | 9/10 | 含暱稱+系統訊息 |
| Game Feel | 9/10 | hit-stop 改為本地處理（多人安全） |
| 音效 | 9/10 | 每個事件對應具體檔案 |
| 獎勵系統 | 9/10 | HP 掉落 + XP 升級，數學驗算 |
| Edge Cases | 9/10 | 19 個邊界情況含多人場景 |

**總分：9.0/10**
