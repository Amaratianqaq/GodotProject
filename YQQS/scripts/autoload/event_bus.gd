extends Node
## EventBus —— 全局信号总线（自动加载单例）。
##
## 【框架约束 · 必读】
## 1. 跨系统通信 **只能** 通过本文件里的信号，禁止 Autoload 之间互相直接调用
##    （ConfigDB / SaveSystem 这类纯数据单例的同步查询除外）。
## 2. UI **绝不** 主动轮询游戏状态；一律订阅信号刷新。
## 3. 新增信号必须写在本文件里并补注释说明「谁发、谁收」，不允许在别处
##    用 connect("xxx") 连接未声明的字符串信号。
## 4. 信号命名规范：`<主语>_<过去式动词>`，例如 player_died / item_picked_up。

# ---------------------------------------------------------------------------
# 玩家
# ---------------------------------------------------------------------------

## 玩家角色实例被创建（谁发：Player._ready / 谁收：HUD、相机、RunManager）
signal player_spawned(player: Node)
## 玩家死亡（谁发：Player / 谁收：RunManager、结算界面）
signal player_died()
## 玩家复活/重置
signal player_revived()
## 生命值变化（cur/max）
signal player_hp_changed(current: float, maximum: float)
## 护甲变化
signal player_armor_changed(current: float, maximum: float)
## 能量（蓝条）变化
signal player_mp_changed(current: float, maximum: float)
## 等级/经验变化
signal player_level_changed(level: int, xp: int, xp_next: int)
## 金币变化
signal gold_changed(amount: int)
## 经验获得（飘字用）
signal xp_gained(amount: int)

# ---------------------------------------------------------------------------
# 战斗
# ---------------------------------------------------------------------------

## 造成伤害（谁发：HurtboxComponent / 谁收：HUD 飘字、命中特效、屏幕震动）
signal damage_dealt(target: Node, info: DamageInfo)
## 目标死亡（谁发：EnemyBase / 谁收：LootService、RunManager 计数）
signal enemy_died(enemy: Node, tier: int, position: Vector2)
## 任何 Actor 死亡
signal actor_died(actor: Node)
## 命中顿帧请求（duration 秒，scale 时间缩放）
signal hitstop_requested(duration: float)
## 屏幕震动请求
signal screen_shake_requested(strength: float, duration: float)

# ---------------------------------------------------------------------------
# 物品 / 背包 / 仓库
# ---------------------------------------------------------------------------

## 背包内容变化
signal inventory_changed()
## 仓库内容变化
signal warehouse_changed()
## 物品被拾取
signal item_picked_up(item: ItemStack, position: Vector2)
## 物品被丢弃
signal item_dropped(item: ItemStack, position: Vector2)
## 装备武器
signal weapon_equipped(data: WeaponData, slot: int)
## 武器开火（供 HUD 冷却条 / 音效使用）
signal weapon_fired(weapon: Node, data: WeaponData)
## 武器换弹开始/结束
signal weapon_reload_started(weapon: Node, duration: float)
signal weapon_reload_finished(weapon: Node)
## 金币拾取
signal coin_picked_up(amount: int, position: Vector2)

# ---------------------------------------------------------------------------
# 宝箱 / 掉落
# ---------------------------------------------------------------------------

## 宝箱生成
signal chest_spawned(chest: Node, tier: int)
## 宝箱开启（rewards 为 ItemStack 数组）
signal chest_opened(chest: Node, tier: int, rewards: Array)
## 掉落物生成
signal loot_dropped(stack: ItemStack, position: Vector2)

# ---------------------------------------------------------------------------
# 技能树
# ---------------------------------------------------------------------------

## 技能点变化
signal skill_points_changed(points: int)
## 技能树结构或已点技能变化（UI 需要整树重绘）
signal skill_tree_changed()
## 单个技能被点亮
signal skill_unlocked(skill_id: StringName, level: int)

# ---------------------------------------------------------------------------
# 关卡 / 流程
# ---------------------------------------------------------------------------

## 一局游戏开始（seed 用于复现地图）
signal run_started(run_seed: int, floor_index: int)
## 一局游戏结束
signal run_ended(victory: bool)
## 一层通关
signal floor_cleared(floor_index: int)
## 地图生成完成
signal map_generated(level: Node, room_graph: RoomGraph)
## 进入某个房间
signal room_entered(room: RoomData, kind: int)
## 房间清空
signal room_cleared(room: RoomData)
## BOSS 出现 / 被击败
signal boss_spawned(boss: Node)
signal boss_defeated()

# ---------------------------------------------------------------------------
# UI / 场景
# ---------------------------------------------------------------------------

## 通用提示条
signal toast(text: String, color: Color)
## 场景切换开始/结束
signal scene_change_started(scene_id: String)
signal scene_changed(scene_id: String)
## 打开/关闭某个 UI 面板（UI 之间互斥用）
signal ui_panel_opened(panel_id: StringName)
signal ui_panel_closed(panel_id: StringName)
## 打开面板请求（例如按 K 打开技能树，由 UIManager 统一处理）
signal ui_open_requested(panel_id: StringName)
## 游戏暂停状态变化
signal pause_changed(paused: bool)
## 队伍/角色选择变化（大厅）
signal character_selected(character_id: StringName)

# ---------------------------------------------------------------------------
# 存档
# ---------------------------------------------------------------------------

signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)
