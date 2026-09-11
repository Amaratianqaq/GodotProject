# Soul Forest · 框架文档

> 类《元气骑士前传》的 2.5D 像素动作 RPG —— **第一阶段：宁静森林**
> 引擎：Godot 4.7.2 (mono，但全项目使用 GDScript，不需要 .NET 编译)

---

## 这个仓库是什么

一套**可运行、可验证、可继续开发**的第一阶段游戏框架，包含：

| 类别 | 内容 |
|---|---|
| 系统 | 大厅（角色选择）、森林关卡程序化生成、仓库、血/甲/蓝条、全局技能树、随机宝箱掉落、存档 |
| 角色 | 游侠（参考《元气骑士》游侠：翻滚 + 必暴） |
| 敌人 | 5 小怪 + 2 精英 + 1 BOSS（哥布林大祭司） |
| 武器 | 12 把品质武器（白/绿/蓝/橙 各 3 把，**仅有贴图**）+ 樱花霰弹枪（橙·传奇，**完整实现**） |
| 美术 | 14 张代码生成的像素图集（角色/敌人/BOSS/武器/道具/地表/UI） |
| 文档 | 本目录 —— 用来**约束后续开发**，不是事后补的说明书 |

---

## 三条命令：跑起来 / 验证 / 截图

先设置好引擎路径（本机为）：

```powershell
$GODOT = "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
```

### 1. 运行游戏

```powershell
& $GODOT --path E:\GodotProject
```

或者用编辑器打开 `E:\GodotProject\project.godot` 后按 F5。

**操作**：`WASD` 移动 · 鼠标瞄准 · `左键` 攻击（按住连发）· `空格` 翻滚 · `E` 交互 ·
`Tab` 背包 · `I` 仓库（仅大厅）· `K` 技能树 · `Q` 喝药 · `R` 换弹 · `1/2` 切换武器槽 · `Esc` 暂停

### 2. 全量自检（静态）

```powershell
& $GODOT --headless --path E:\GodotProject res://tools/Validation.tscn
```

检查：脚本编译、场景加载、美术图集内容、ConfigDB 数据完整性、背包、掉落 200 次开箱统计、
技能树效果、武器工厂、5 个随机种子的地图生成 + 同种子可复现性、存档往返。退出码 0 = 全绿。

### 3. 运行时冒烟测试

```powershell
& $GODOT --headless --path E:\GodotProject res://tools/SmokeTest.tscn
```

真的把森林关卡和大厅跑起来：生成地图 → 刷怪 → 开火 → 命中结算 → 开箱 → 杀 BOSS → 掉落 →
翻滚必暴 → 进大厅 → 仓库存取。退出码 0 = 全绿。

### 4. 截图（人工肉眼验收）

```powershell
# 需要真实渲染器，不要加 --headless
& $GODOT --path E:\GodotProject res://tools/Screenshot.tscn -- --scene=forest --out=E:\GodotProject\docs\screenshots\forest.png
& $GODOT --path E:\GodotProject res://tools/Screenshot.tscn -- --scene=lobby  --panel=skill_tree
```

已渲染的验收截图在 `docs/screenshots/`。

---

## 文档索引（按需阅读）

| 文档 | 内容 | 什么时候读 |
|---|---|---|
| [01_框架总览.md](01_框架总览.md) | 技术选型、分层架构、2.5D 约定、自动加载单例、事件总线、数据流 | **开始改代码之前必读** |
| [02_目录结构与命名规范.md](02_目录结构与命名规范.md) | 目录职责、文件/类/资源命名、代码风格 | 新建任何文件之前 |
| [03_数据与配置规范.md](03_数据与配置规范.md) | 各类 `.tres` 字段清单 + 「怎么加一个新物品/武器/敌人/宝箱」 | 加内容时 |
| [04_战斗与数值规范.md](04_战斗与数值规范.md) | 伤害管线、血/甲/蓝、暴击、命中判定、武器生命周期 | 做战斗有关的东西时 |
| [05_关卡与地图生成规范.md](05_关卡与地图生成规范.md) | 生成算法、2.5D 渲染分层、刷怪/宝箱/传送门摆放 | 做关卡时 |
| [06_UI开发规范.md](06_UI开发规范.md) | 为什么用代码建 UI、UIKit、面板互斥与暂停、中文字体 | 做界面时 |
| [07_樱花霰弹枪实现说明.md](07_樱花霰弹枪实现说明.md) | 复刻思路 + 五瓣散射/弹墙/后坐力/技能树联动的逐段解析 | 想实装新武器时当模板 |
| [08_第一阶段验收清单.md](08_第一阶段验收清单.md) | 需求 → 实现的逐条对照 + 已知差距 | 验收 / 交接时 |
| [09_后续开发路线图.md](09_后续开发路线图.md) | 第二阶段及以后该做什么、按什么顺序做 | 规划下一步时 |
| [10_美术素材规格与双网格瓦片契约.md](10_美术素材规格与双网格瓦片契约.md) | **新素材库的权威规格**：文件名/尺寸/网格/逐格语义 + 双网格瓦片契约（16 瓦片/地表、偏移 −8、角点索引表、验收校验器） | 换美术、做地图渲染时 |
| [11_GPTImage2_素材生成提示词.md](11_GPTImage2_素材生成提示词.md) | 逐文件可直接粘贴的生成提示词（含全局前缀、负面清单、后期归一化 SOP） | 出素材时 |

> **双网格相关工具**（生成器在 `tools/refart/`，验收场景在 `tools/`）：
> `gen_ground.gd` 生成图集 → `verify_dualgrid.gd` 逐像素验证渲染
> → `DualGridAcceptance.tscn` 验收游戏内实际使用情况。
> 详见 [`../tools/refart/README.md`](../tools/refart/README.md)。

---

## 30 秒了解代码结构

```
scripts/
  autoload/    10 个全局单例（EventBus / ConfigDB / GameState / SaveSystem /
               SceneRouter / AudioManager / SkillTreeService / WarehouseService /
               LootService / RunManager）
  core/        纯数据与枚举：GameEnums / Atlas / Layers / StatBlock / DamageInfo /
               Inventory / CombatFx
  data/        Resource 定义：ItemData / WeaponData / EnemyData / CharacterData /
               LootTable / SkillTreeData / ProjectileData / ForestMapConfig
  components/  VitalsComponent（血蓝）/ Hitbox / Hurtbox / HealthBar / 飘字 / 火花
  entities/    Actor（基类）/ Player（游侠）/ Enemy（数据驱动 AI）/ skills/（游侠翻滚）
  weapons/     WeaponBase / WeaponRanged / WeaponMelee / WeaponCherryShotgun / WeaponRegistry
  projectiles/ Projectile（直线/弹墙/追踪/波动通吃）
  items/       PickupBase / CoinPickup / ItemPickup / Chest
  levels/      RoomData / RoomGraph / ForestMapGenerator / ForestTileset / ForestLevel
  world/       Interactable / Portal / PanelAltar
  ui/          UIKit / StatBar / ItemSlot / Hud / 四个面板
  lobby/       Lobby
  boot/        Boot（标题界面）
data/          46 个 .tres（由 tools/gen_data.gd 生成）
scenes/        15 个 .tscn（实体/关卡用场景，UI 只留一个挂脚本的根节点）
tools/         生成器与校验器（gen_pixel_assets / gen_data / setup_project /
               Validation / SmokeTest / Screenshot）
```

---

## 三条最重要的铁律

如果只记住三件事，记这三条（细节都在 01 号文档里）：

1. **数据不在代码里。** 任何数值（物品、武器、敌人、掉率、技能效果、地图参数）
   都必须写成 `res://data/**/*.tres`，代码只负责读取与逻辑。
2. **通信只走 EventBus。** UI 不轮询、系统之间不直接互相调用（详见 01 号文档的信号表）。
3. **改完必须跑验证。** `Validation.tscn` + `SmokeTest.tscn` 都返回 0 才算改完；
   两者都是可重复运行的，不需要人工点。

---

## 截图

`docs/screenshots/` 下有 5 张由真实 GPU 渲染的验收图：

- `forest.png` —— 森林关卡（地形/树木/敌人/宝箱/HUD）
- `lobby.png` —— 大厅（角色选择面板/传送门/仓库与技能树祭坛）
- `ui_inventory.png` / `ui_warehouse.png` / `ui_skill_tree.png` —— 三个主界面
