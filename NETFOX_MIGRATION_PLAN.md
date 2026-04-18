# Netfox 遷移計畫（Path B, 扣 RollbackSync）

**目的**：解決遠端實體（Player / Monster / Boss / Animal / NPC）瞬移 / 橡皮筋問題。

**範圍**：Netfox 全套（NetworkTime + StateSynchronizer + TickInterpolator），扣除 RollbackSynchronizer 跟 LagCompensator。

**不做的事**（對比「完整全套」）：
- ❌ RollbackSynchronizer（保 client authority，不做防作弊 / server 端 player 模擬）
- ❌ LagCompensator（戰鬥 hit detection client-side consistent，TickInterp 延遲不影響打擊）
- ❌ Companion 同步（design 決策，保持各 peer 獨立 AI）

---

## 架構改動總覽

| 實體 | 改前 | 改後 | Authority 變化 |
|------|------|------|----------------|
| NetworkCharacter (Player) | MP-Sync 20Hz + 手寫 lerp | StateSync + TickInterp | 不變（client peer）|
| MonsterCharacter | 同上 | 同上 | 不變（server）|
| BossCharacter | 同上 | 同上 | 不變（server）|
| Animal | 同上 | 同上 | 不變（server）|
| NPCCharacter | 同上 | 同上 | 不變（server）|
| Companion | 各 peer 獨立 | **不動** | — |

**替換的 Godot 內建 node**：`MultiplayerSynchronizer` → `StateSynchronizer` + `TickInterpolator`

**保留不動的 Godot 內建**：
- `MultiplayerSpawner`（Netfox 不取代這個，玩家/怪物 spawn 照舊）
- 所有 `@rpc` 函式（Netfox 不取代，戰鬥/事件照舊）
- `set_multiplayer_authority()` 邏輯（authority 分派照舊）

---

## Rule C 四件事的驗證點（每 phase 結束前必跑）

來自 CLAUDE.md：
1. **玩家移動雙向可見**：自己走 / 對方看得到；對方走 / 我看得到（平滑無瞬移）
2. **怪物 AI**：移動 / 攻擊 / 死亡 / 重生
3. **NPC 巡邏**：client 端實際在動（平滑）
4. **登入還原**：level / HP / 同伴 / 武器 在對方螢幕上正確

本地測試環境：
```
Server:        Godot_v4.3-stable_win64_console.exe --path game --headless -- --server
Desktop:       Godot_v4.3-stable_win64_console.exe --path game -- --server-url=ws://localhost:7777 --user-id=<id>
Web (python):  python -m http.server 8060（在 game/build/web/）
Web 瀏覽器:    localhost:8060/index.html?server=ws://localhost:7777
```

---

## Phase 0：裝 Netfox addon（~15 min）

1. Git clone netfox 最新穩定版到 `game/addons/netfox/`（以及 `netfox.extras/`, `netfox.noray/` 看要不要）
2. `project.godot` 啟用 plugin（Netfox 是 plugin 型 autoload）
3. `--editor --quit` 一次讓 Godot import
4. 跑 `--headless -- --server` 確認 autoload 不炸

**風險**：Netfox 可能要 Godot 4.3 對應版本。裝錯版 autoload 會死人。
**驗收**：server 能啟，沒 SCRIPT ERROR。

## Phase 1：Netfox basics pilot-level 理解（~30 min）

讀 `addons/netfox/README.md` + `StateSynchronizer.gd` + `TickInterpolator.gd` 的 class 註解。

重點確認：
- StateSync 是否跟 MP-Sync 同場可用（會不會打架）
- TickInterp 寫屬性的時機（`_process` 還是 `NetworkTime.on_tick`）
- Authority 語意是否跟 MP-Sync 一樣（`is_multiplayer_authority()` 仍然可靠嗎）
- `NetworkTime.tickrate` 建議值（預設 30Hz 可能要調）

**輸出**：給使用者一份簡短筆記，對齊認知後再進 phase 2。

## Phase 2：試點 Animal（~1h + 測試 30 min）

Animal 最簡單：128 行、server authority、沒戰鬥、只有左右走。

1. 讀 `animal.gd`，grep `target_position` / `is_multiplayer_authority` / `_is_server` 確認讀寫邊界（Rule A）
2. 改 `animal.tscn`：
   - 刪 `MultiplayerSynchronizer` node
   - 加 `StateSynchronizer`：properties = position, move_vector
   - 加 `TickInterpolator`：properties = position
3. 改 `animal.gd`：remote 分支拔 lerp + snap
4. `--editor --quit` import
5. `grep SCRIPT ERROR` 跑 server + client 30 秒
6. **驗收**：web client 看到動物左右走平滑，沒瞬移

**失敗兩次就換路線**：如果 Netfox 跟我們的 authority 模型衝突，回頭只裝 TickInterp 不換 StateSync。

## Phase 3：Monster（~2h + 測試 30 min）

Monster 820 行，有 AI state machine + 戰鬥 + 收服 + XP 掉落。

1. Rule A：grep `target_position` / `move_vector` / `ai_state` / `hp` / `visible` 所有讀寫點
2. 改 `monster_character.tscn`：
   - StateSync properties = position, move_vector, ai_state, hp, visible
   - TickInterp properties = position
3. 改 `monster_character.gd`：
   - 拔 `_physics_process` remote 分支的 lerp（~15 行）
   - 保留所有 `@rpc`（hit / die / hit_fx / capture / respawn_fx）
4. 跑整合測：
   - 怪物走路平滑（不瞬移）
   - 打怪傷害進得了（hit detection 沒壞）
   - 怪物死亡 / 重生（`_rpc_respawn_fx` + collision 恢復）
   - 收服流程（`_rpc_attempt_capture` → `_rpc_capture_success_fx`）

**高風險點**：`_rpc_respawn_fx` 會 snap position，StateSync 下 snap 會不會被 interp 吃掉要驗證。

## Phase 4：Boss（~1-2h + 測試）

Boss 777 行，類似 Monster 但：
- 多部件 sprite（Body / Head / Wing 拼接）
- 有 `boss_state` instead of `ai_state`
- 擊殺通知廣播

步驟同 Monster。加一項驗證：Boss 多部件 sprite 是否跟著 TickInterp 一起平移（應該會，因為 TickInterp 改的是 root node position，子 node 跟著走）。

## Phase 5：NPC（~1h + 測試）

NPC 142 行，特殊點：**只 client 本地 spawn**（world.gd `_spawn_npcs` server 不跑）。但 authority 還是 server（1），所以 client 端 NPC node 的 authority 是 server peer。

這很詭異但 SYNC_INVENTORY 有記。照樣改 StateSync + TickInterp，authority 不動。

**驗收**：NPC 在 client 端巡邏可見 + 沒瞬移（Rule C 第三項）。

## Phase 6：Player (NetworkCharacter)（~2-3h + 測試）

最複雜也最後做（前面 pilot 過才有信心）。

特殊點：
- authority = client peer，不是 server
- 自己的 character：永遠 `is_multiplayer_authority() == true`，走本地 physics
- 別人的 character：`false`，走 StateSync + TickInterp
- 有 `super._physics_process(delta)` 呼叫 NinjaAdventure 內建 Character 的物理

步驟：
1. Rule A 大 grep（include network_character.gd + network_character.tscn + 任何引用 `target_position` 的地方）
2. 改 .tscn：同模式
3. 改 .gd：
   - remote 分支拔 lerp + 移除 `target_position` 手動寫入
   - authority 分支維持不變
4. 驗證 `_apply_server_restore` 還能從存檔套 level/hp 並正確同步到 client
5. 驗證 tab-hide snap（tab 切走回來）

**驗收**：Rule C 第一 + 第四項。

## Phase 7：文件更新（~15 min）

1. SYNC_INVENTORY.md：
   - 「MultiplayerSynchronizer 同步的 property」欄改為「Netfox StateSync + TickInterp property」
   - 加一欄「replication_interval」→ Netfox 改用 NetworkTime.tickrate
2. CLAUDE.md 可能加 **Rule F**：Netfox TickInterp 的注意事項
   - 不要跟 MP-Sync 對同一 property 寫衝
   - TickInterp 改 position 不 target_position，remote 不要再塞 lerp 進去

## Phase 8：本地 3-way + deploy（~1-2h）

1. 本地跑完 Rule C 四件事 2 輪（偶發性 bug 跑 2 遍抓 race condition）
2. PowerShell flyctl deploy 新 server（CLAUDE.md 記載 PowerShell 比 bash 快）
3. `game/build/web/` 重新 export + push gh-pages
4. 線上 3-way 複測 Rule C

---

## 風險清單

| 風險 | 機率 | 影響 | 緩解 |
|------|------|------|------|
| Netfox 版本 / Godot 4.3 不相容 | 中 | 高 | Phase 0 炸就 fallback 只加 TickInterp 共存方案 |
| StateSync + 現有 @rpc authority 有衝突 | 中 | 中 | Phase 2 pilot 抓出來 |
| TickInterp 對 snap（respawn、tab-hide）行為奇怪 | 中 | 中 | 保留舊 snap code，必要時手動 disable interp 幾秒 |
| `_physics_process` authority 分支跟 Netfox tick 打架 | 低 | 中 | Phase 6 仔細 handle |
| Client authority on Player 跟 StateSync 不合 | 低 | 高 | StateSync 支援任意 authority，應該 OK |
| Web client WebSocket + Netfox 沒人測過 | 中 | 中 | Phase 2 就用 web client 測，早抓 |

---

## 驗收標準

遷移完成的定義：

1. ✅ 本地 3-way test Rule C 四件事連跑 3 輪無瞬移、無橡皮筋、無 SCRIPT ERROR
2. ✅ 線上 3-way test 同樣通過
3. ✅ SYNC_INVENTORY.md 更新
4. ✅ PR 開好，含完整 commit message 說明改動

---

## 回退計畫

如果某個 phase 炸超過 2 次（CLAUDE.md「同一個方法失敗 2 次就換路線」）：

- Phase 0 炸 → 改方案 A（只加 TickInterp 共存 MP-Sync）
- Phase 2 炸 → 同上
- Phase 3+ 個別實體炸 → 那隻回退到 MP-Sync，其他照舊
- 整體不順 → git reset 回 master branch，改走方案 A

---

## Checkpoint 時機

每個 phase 完成後 commit + checkpoint：

- Phase 0 done → `chore: install netfox addon`
- Phase 2 done → `feat(sync): migrate animal to netfox StateSync + TickInterp (pilot)`
- Phase 3 done → `feat(sync): migrate monster to netfox`
- Phase 4 done → `feat(sync): migrate boss to netfox`
- Phase 5 done → `feat(sync): migrate npc to netfox`
- Phase 6 done → `feat(sync): migrate player to netfox`
- Phase 7 done → `docs: update SYNC_INVENTORY for netfox migration`
- Phase 8 done → deploy + PR

每個 commit 都獨立可 revert。

---

## 給使用者的承諾

- 每個 phase 完成**我會告訴你**，並等你測過再下一 phase
- 跑遊戲抓 SCRIPT ERROR 是每 phase 必做（CLAUDE.md 規定）
- 看到任何非預期的行為 **停下來問你**，不自己硬幹
- 預估 9-12h 工時內做完（你給的 8-16h 預算內）

Ready for you to approve. 你看完這 plan OK 就說「開動」我進 Phase 0。
