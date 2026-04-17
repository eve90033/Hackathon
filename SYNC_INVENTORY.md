# SYNC_INVENTORY — Monster RPG 多人同步清單

**每次動 MultiplayerSynchronizer / @rpc 前，先讀這份、改完再更新這份。**

---

## 實體 Sync Topology

| 實體 | Spawn 方式 | Authority | MultiplayerSynchronizer 同步的 property | 備註 |
|------|---------|-----------|----------------------------|------|
| **NetworkCharacter** | MultiplayerSpawner (PlayerSpawner) | 對應 client peer_id | `target_position`(ALWAYS) / `move_vector,state,character_key`(ON_CHANGE) / `player_name,peer_id`(SPAWN) | 玩家，snapshot interp |
| **MonsterCharacter** | 各 peer 本地 (`world._spawn_monsters`) | Server (1) | `target_position`(ALWAYS) / `ai_state,hp,move_vector,visible`(ON_CHANGE) | snapshot interp |
| **BossCharacter** | 各 peer 本地 | Server (1) | `target_position`(ALWAYS) / `boss_state,hp,move_vector,visible`(ON_CHANGE) | snapshot interp |
| **Animal** | 各 peer 本地 (`world._spawn_animals`) | Server (1) | `target_position`(ALWAYS) / `move_vector`(ON_CHANGE) | snapshot interp |
| **NPCCharacter** | **只 client 本地**（`world._spawn_npcs`，server 不跑 spawn） | Server (1) | `target_position`(ALWAYS) / `move_vector`(ON_CHANGE) | server 跑 AI，client lerp |
| **Companion** | RPC `NetworkManager.sync_companion` 各 peer 本地 | 無 | **無同步**（各 peer 自跑 physics） | AI 漂移可接受，視覺 OK |
| **HP Pickup** | RPC `monster._rpc_spawn_hp` (call_local) 各 peer | Server (1) | 無 | 名字 `HP_<monster>_<drop_id>` 確定性；server 獨占 collision check |

**snapshot interp 演算法**（所有用 target_position 的實體）：
- Server: `move_and_slide()` 後 `target_position = global_position`
- Client: `global_position.lerp(target_position, delta * 15.0)`；若 `|target - pos| > 閾值(128~256)` 則 snap
- Replication: `replication_interval=0.05, delta_interval=0.05` (20Hz)

---

## RPC Inventory

### network_character.gd (Player)
| RPC | Mode | 呼叫者 → 執行者 | 用途 |
|-----|------|--------------|------|
| `_rpc_player_hit` | any_peer | client → server | 通知被怪物打到，server 算傷害 |
| `_rpc_hp_update` | any_peer | server → 該 client | 更新該玩家 HP 顯示 |
| `_rpc_heal_sync` | any_peer (sender 檢查 ==1) | server → 該 client | 愛心/等等回血同步（**曾是 authority 被 Godot 擋掉，已改 any_peer**） |
| `_rpc_weapon_changed` | any_peer (sender 檢查) | client 自己 → 所有 peer | 武器切換廣播（client authority） |
| `_rpc_spawn_projectile` | any_peer (sender 檢查) | client 自己 → 所有 peer | 遠程武器投射物視覺 |
| `_rpc_death_fx` | any_peer | 該 client authority → 他人 | 死亡特效 |
| `_rpc_respawn_fx(pos)` | any_peer | 該 client authority → 他人 | 復活特效 + 位置 snap |
| `_rpc_level_sync(lvl, show_fx=true)` | any_peer | 該 client authority 或 server → 所有 peer | 升級同步（show_fx=false 用於登入還原） |
| `_rpc_chat(text)` | any_peer (rate limit) | 該 client authority → 他人 | 聊天氣泡 |
| `_apply_server_restore(save)` | （不是 RPC，本地函式）| server 獨用 | spawn 後從存檔套 level/hp/atk/xp，然後 RPC level_sync 廣播 |

### monster_character.gd
| RPC | Mode | 用途 |
|-----|------|------|
| `_rpc_monster_hit(at_pos)` | any_peer | client → server，client 攻擊怪物 |
| `_rpc_hit_fx` | authority | server → all | 怪物受擊白閃 + 音效 |
| `_rpc_die_fx` | authority | server → all | 死亡音效 |
| `_rpc_spawn_hp(pos,heal,id)` | authority + call_local | server → all (含 server) | HP 拾取物生成 |
| `_rpc_give_xp(amount)` | authority | server → 該 client | 給 XP |
| `_rpc_respawn_fx(pos)` | authority | server → all | 重生視覺 + 位置 snap **+ 恢復 collision/hitbox** |
| `_rpc_attempt_capture(captor_name)` | any_peer | client → server | 請求收服 |
| `_rpc_capture_success_fx` / `_rpc_capture_fail_fx` | authority | server → 該 captor client | 收服結果（UI 通知） |
| `_rpc_disable_collision` | authority + call_local | server → all | 收服成功 / 死亡時停 client 端 collision（`collision_layer/hitbox.monitorable` 不在 sync config） |

### boss_character.gd
| RPC | Mode | 用途 |
|-----|------|------|
| `_rpc_boss_hit(at_pos)` | any_peer | client → server | 攻擊 Boss |
| `_rpc_hit_fx` / `_rpc_die_fx` | authority | server → all | 視覺/音效 |
| `_rpc_give_xp` | authority | server → 該 client | 給 XP |
| `_rpc_respawn_fx(pos)` | authority | server → all | 重生 + 位置 snap |
| `_rpc_boss_kill_notice(killer, boss)` | authority + call_local | server → all | 全體廣播擊殺通知 |

### network_manager.gd (autoload, /root/NetworkManager)
| RPC | Mode | 用途 |
|-----|------|------|
| `_register_player(info)` | any_peer | client → server | 登記 name/character |
| `request_login(user_id)` | any_peer | client → server | 請求登入 |
| `_kicked_by_new_session` | authority | server → 被踢的 client | 顯示「他處登入」遮罩 |
| `_login_response(user_id, data)` | authority | server → 該 client | 回傳 save data |
| `save_character(user_id, data)` | any_peer | client → server | 存檔 |
| `check_name(name, char)` | any_peer | client → server | 暱稱驗證 |
| `_name_check_response(ok, reason)` | authority | server → 該 client | 暱稱驗證結果 |
| `sync_companion(captor_name, m_key, m_tier)` | **any_peer + call_remote** | server or client → 其他 peer | 同伴生成廣播 |

### world.gd / hp_pickup.gd / weapon_rack.gd
| RPC | Mode | 用途 |
|-----|------|------|
| `_request_spawn` | any_peer | client → server | 請求生成 Player 節點 |
| `_request_rack_sync` / `_receive_rack_sync` | any_peer / authority | 雙向 | 武器架狀態同步 |
| `_rpc_rack_updated(name, key)` | any_peer | any → all | 武器架變動 |
| `_rpc_picked_up` / `_rpc_despawn` | authority + call_local | server → all | HP 拾取/消失 |

---

## 已知設計決策 / 非 bug

1. **Companion 各 peer 獨立 AI**：attack_cooldown、attack_target 不同步。視覺會有漂移但不致命。
2. **NPC 各 peer 都 spawn + server 權威 AI**：若未來要改 client-only，必改 `_physics_process` 移除 `_is_server()` 分支
3. **Snapshot interp 閾值**：
   - Monster/Animal/NPC: 128 px 以上 snap
   - NetworkCharacter/Boss: 256 px 以上 snap
   - 原因：玩家移動快，允許較大 drift 前才 snap 避免每小步都強制跳
4. **Server 是 source of truth**：save data 存於 server 的 `/data/player_database.json`；spawn 時 server 用 `_apply_server_restore` 套回 NetworkCharacter；client `_load_player_data` 只做本地 UI 即時顯示
5. **Collision / hitbox.monitorable 不在 SceneReplicationConfig**：server 改本地值後，必透過 RPC（`_rpc_die_fx` / `_rpc_respawn_fx` / `_rpc_disable_collision`）通知 client 端同步關閉/開啟，不然 client 會有「隱形但可碰」的殭屍怪物吃子彈

---

## 修訂記錄

- 2026-04-17 初版（完整審計後）
- 2026-04-17 動完 sync 的實作請務必更新此表 ← 常態
