# Soul Forest

类《元气骑士前传》的 **2.5D 像素动作 RPG** —— 第一阶段：宁静森林。
Godot 4.7.2 · 纯 GDScript。

> 📖 **完整框架文档在 [`docs/`](docs/README.md)** —— 改代码之前请先读
> [`docs/01_框架总览.md`](docs/01_框架总览.md)。

---

## 快速开始

```powershell
$GODOT = "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"

# 运行
& $GODOT --path E:\GodotProject

# 静态自检（13 项，必须 exit 0）
& $GODOT --headless --path E:\GodotProject res://tools/Validation.tscn; "exit=$LASTEXITCODE"

# 运行时冒烟测试（34 项，必须 exit 0）
& $GODOT --headless --path E:\GodotProject res://tools/SmokeTest.tscn; "exit=$LASTEXITCODE"

# 截图验收
& $GODOT --path E:\GodotProject res://tools/Screenshot.tscn -- --scene=forest
```

**操作**：`WASD` 移动 · 鼠标瞄准 · `左键` 攻击 · `空格` 翻滚 · `E` 交互 ·
`Tab` 背包 · `I` 仓库（仅大厅）· `K` 技能树 · `Q` 喝药 · `R` 换弹 · `1/2` 换武器 · `Esc` 暂停

---

## 第一阶段内容

| 类别 | 内容 |
|---|---|
| 系统 | 大厅（角色选择）、森林程序化关卡、仓库、血/甲/蓝条、全局技能树、随机宝箱掉落、存档 |
| 角色 | 游侠（翻滚 + 必暴，参考《元气骑士》游侠） |
| 敌人 | 5 小怪 + 2 精英 + 1 BOSS（哥布林大祭司） |
| 武器 | 12 把品质武器（白/绿/蓝/橙 各 3 把，仅有贴图）+ **樱花霰弹枪**（橙·传奇，完整实现） |
| 美术 | 14 张代码生成的像素图集（`tools/gen_pixel_assets.gd`）；**替换为《元气骑士前传》风格新素材库的规格与提示词已就绪** —— 见 [docs/10](docs/10_美术素材规格与双网格瓦片契约.md) / [docs/11](docs/11_GPTImage2_素材生成提示词.md) |
| 地形 | **双网格（dual-grid）系统瓦片**：4 种地表 × 16 角点，**16 张瓦片覆盖全部衔接情形**（传统 blob 要 47 张）。地貌成片、边界自动圆角 —— 见 [docs/10](docs/10_美术素材规格与双网格瓦片契约.md) §5 |
| 文档 | `docs/` 下 12 篇框架约束文档 |

---

## 四条最重要的铁律

1. **数据不在代码里。** 所有数值写 `res://data/**/*.tres`（由 `tools/gen_data.gd` 生成或编辑器创建）。
2. **通信只走 EventBus。** UI 不轮询、系统之间不直接互调。见 [docs/01](docs/01_框架总览.md) §5。
3. **改完必须跑验证。** 下面三个都返回 0 才算改完。
4. **双网格的索引映射只有一处定义。** `scripts/core/dual_grid.gd`（运行时）与
   `tools/refart/dual_grid.gd`（生成器侧）是同一套映射的两份实现，
   改动后必须跑 `tools/DualGridAcceptance.tscn` + `tools/refart/verify_dualgrid.gd`。
   这个 16 项映射在开发中改错过五次，**别靠推理，靠验证**。

```powershell
& $GODOT --headless --path E:\GodotProject res://tools/Validation.tscn;          "exit=$LASTEXITCODE"
& $GODOT --headless --path E:\GodotProject res://tools/SmokeTest.tscn;           "exit=$LASTEXITCODE"
& $GODOT           --path E:\GodotProject res://tools/DualGridAcceptance.tscn;   "exit=$LASTEXITCODE"
```

---

## 目录速览

```
docs/       框架文档（先读这里）
data/       46 个 .tres 配置
scenes/     15 个 .tscn（实体/关卡用场景；UI 只留挂脚本的根节点）
scripts/    76 个 .gd（autoload / core / data / components / entities /
            weapons / projectiles / items / levels / world / ui / lobby / boot）
assets/     像素图集 + 着色器（音频目录已预留，目前为空）
tools/      生成器与校验器（setup_project / gen_pixel_assets / gen_data /
            Validation / SmokeTest / Screenshot）
```

---

## 截图

`docs/screenshots/` —— 由真实 GPU 渲染：

| 文件 | 内容 |
|---|---|
| `forest.png` | 森林关卡（地形/树木/敌人/宝箱/HUD） |
| `lobby.png` | 大厅（角色选择面板/传送门/设施） |
| `ui_inventory.png` | 背包 |
| `ui_warehouse.png` | 仓库 |
| `ui_skill_tree.png` | 全局技能树 |

---

## 已知空缺

- **无音频资源**（所有 `.sfx_*` 路径已配好，`AudioManager` 对缺失文件静默跳过，丢文件即生效）
- **无手柄支持、无设置界面**
- 12 把品质武器只有贴图（按需求「代码实现后续添加」）
- 相机屏幕震动只有广播、无消费者

详见 [docs/08_第一阶段验收清单.md](docs/08_第一阶段验收清单.md) §4。
