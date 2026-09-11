# 双网格地表图集 · 生成器说明（tools/refart/）

> 本目录是**参考素材生成器**，不属于游戏运行时。
> 相关契约：[`docs/10_美术素材规格与双网格瓦片契约.md`](../../docs/10_美术素材规格与双网格瓦片契约.md) §5

---

## 1. 目录内容

| 文件 | 作用 |
|---|---|
| `ref_art.gd` | 共享绘图库：32 色调色板、像素/形状/字符画、写盘与统计 |
| `dual_grid.gd` | ★ **双网格映射的唯一定义处**（生成器侧）：象限 ↔ 索引 ↔ 图集槽位 + 自检 |
| `gen_ground.gd` | 生成 `tileset_forest_ground.png`（256×256，4 地表 × 16 角点）与 `tileset_forest_wall.png` |
| `gen_chars.gd` | 生成角色/敌人图集：`player_ranger` + 7 个敌人（4×4 网格，新调色板） |
| `gen_props.gd` | 生成 13 张独立场景道具 `prop_*.png`（树木 / 石头 / 花草 / 倒木） |
| `gen_props_atlas.gd` | 生成 `props.png`（16×8 格：宝箱 / 金币 / 拾取物 / 技能图标 / UI 图标 / 品质框 / 装饰） |
| `gen_weapons.gd` | 生成 `weapons.png`（12 把品质武器）+ `weapon_cherry_shotgun.png` |
| `gen_ui.gd` | 生成 UI 4 张（九宫格面板 / 血蓝条 / 护甲条 / 品质框） |
| `gen_vfx.gd` | 生成特效序列图 5 张（火花 / 枪口 / 花瓣 / 魔法弹 / 箭） |
| `verify_dualgrid.gd` | 用**真实引擎渲染**验证双网格（逐像素位图比对） |
| `verify_all_assets.gd` | ★ **全套 35 个素材的契约比对**（尺寸 / 空图 / 越色 / 半透明） |
| `verify_chars.gd` | 角色图集结构自检（尺寸/空格子/越色/格间粘连） |
| `verify_props.gd` | 道具自检（尺寸 / **底边贴底** / 水平居中 / 越色） |
| `check_chars_layout.gd` | 角色图集**落地检查**：每格内容在格内的垂直范围（防"浮空"） |
| `out/` | 诊断输出（PNG / 文本），不参与导出 |

---

## 2. 运行方式

```powershell
$G = "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"

# 1) 改完脚本先 import（注册 class_name + 重导 PNG）
& $G --headless --path F:\GodotProject\YQQS --import

# 2) 生成图集（自带逐瓦片自检，失败会 push_error）
& $G --headless --path F:\GodotProject\YQQS --script res://tools/refart/gen_ground.gd

# 3) import 新 PNG（必须！否则运行时读到旧图）
& $G --headless --path F:\GodotProject\YQQS --import

# 4) 验证渲染（★ 必须用真渲染器，不能加 --headless：SubViewport 在 headless 下不产图）
& $G --path F:\GodotProject\YQQS --script res://tools/refart/verify_dualgrid.gd
```

---

## 3. 双网格的几何（一句话版）

- **逻辑格**决定「这里是不是草地」（数据/碰撞/刷怪都在这一层）。
- **显示格**整体偏移 `(-8, -8)`（半个瓦片），于是每个显示格恰好压在
  4 个逻辑格的**公共角点**上 → 16 种组合 → 16 张瓦片覆盖全部角点情形。
- 角点 → 位：`NW=1 NE=2 SW=4 SE=8`，索引 = 位相加；
  图集里第 `i` 个瓦片的槽位 = `(i % 4, i / 4)`。

---

## 4. 踩坑记录（这段比正文有用，改之前请读完）

### 4.1 「象限 ↔ 索引」的最终定论

**索引就是四个角是否本地形的位掩码**（row-major）：

```
bit1(1) = NW 左上      bit2(2) = NE 右上
bit4(4) = SW 左下      bit8(8) = SE 右下
索引 → 图集槽位：col = idx % 4,  row = idx / 4
```

`gen_ground.gd` 生成后会把每张瓦片读回来核对「实心象限 == 索引的位」，
实测 64/64 全部吻合（见 `_assert_tile_quads`）。

**这个 16 项映射在开发中改错了五次**，所以它现在只写在 `dual_grid.gd` 一处，
并带 `self_test()`。不要再往别处抄一份：

| 错误 | 后果 | 发现方式 |
|---|---|---|
| 索引位与象限交叉填（读成 180°） | 地形整片错位 | 逐像素比对 |
| 改成"旋转 90°"的写法 | 更错 | diff 反而变大 |
| 判定"线性（异或）律不成立" | 白写一张查表 | 后来发现穷举时漏了单 bit 组合 |
| **文件里出现重名函数** | 改了代码但行为不变，白查很久 | 直接打印运行时实际返回值 |
| 内圆角裁切条件一锅端 | 1 格宽的洞被放大成十字 | 打印期望 vs 实际点阵 |

**结论（请照做）**：
- 这样一个 16 项的映射，**写一张显式表 + 一个 `self_test()`，不要现场推导**。
- 改完必须跑 `DualGrid.self_test()` 与 `verify_dualgrid.gd`，**别用眼睛看 16px 的图**。
- 怀疑"改了没生效"时，第一步是**打印运行时实际加载的值**。
  （`.godot` 的 class 缓存确实会滞后；重名函数更隐蔽。）
- 测"某逻辑格 → 某象限"时用**单格点亮法**（只放一个显示格 + 只点亮一个逻辑格），
  比任何推理都可靠。

### 4.2 图集瓦片里**不能**放"背景侧"的装饰

双网格只贴「属于本地形的象限」，背景象限会被丢弃。
所以接触落影 / 背景侧描边这类画在背景上的像素**永远显示不出来**，
还可能与邻格地形色冲突。交界处的深色感只能由**地形侧的根线**给出。

### 4.3 每种地表必须各占一个 `TileMapLayer`

`TileMapLayer.set_cell()` 是**覆盖**不是叠加。
把 4 种地表写进同一层，后写的会把先写的整格盖掉（表现为"某地表整片消失"）。

### 4.4 世界底色要显式压在图层最下面

只靠 `add_child` 顺序不保险，给底层层设 `z_index = -10`。

### 4.5 生成器里不要用大质数乘法做哈希

GDScript 的 int 溢出在不同运行中结果不一致（实测 `hash % 13` 的分布会整批漂移），
会让"同一份代码两次生成结果不同"。用 `& 0x1FFFFFFFFFFFFF` 之类掩码保证确定性。

### 4.6 噪声必须按 16 周期化才能无缝平铺

否则左右相邻两张瓦片在接缝处对不上。本生成器的 `_noise16` 用
「晶格点坐标 %16」实现，`_verify_seamless()` 会断言满格瓦片的左右列 / 上下行一致。

---

## 6. 当前状态（交接）

- ✅ `tileset_forest_ground.png`：4 种地表 × 16 角点，逐瓦片自检通过，满格可无缝平铺
- ✅ `tileset_forest_wall.png`：8×8 墙体/建筑图，已生成
- ✅ `RefDualGrid.self_test()` 通过
- ✅ **`verify_dualgrid.gd` 通过** —— 地图内部**逐像素**与手算位图一致
  （同时钉死「偏移 (−8,−8)」与「象限 ↔ 索引」两件事，这是本目录最有价值的一条证据）
- ✅ **已接进游戏**：`ForestLevel` 现在真的用双网格渲染地表，
  由 `tools/DualGridAcceptance.tscn` 验收（结构 / 层内容 / 地表覆盖 / 角点多样性）

### 两个 DualGrid 的分工（容易混淆，记一下）

| 文件 | class_name | 归属 | 用途 |
|---|---|---|---|
| `tools/refart/dual_grid.gd` | `RefDualGrid` | 生成器侧 | 生成图集、逐像素验证渲染 |
| `scripts/core/dual_grid.gd` | `DualGrid` | 游戏运行时 | `ForestLevel` / `ForestTileset` 用 |

同一套映射的两份实现。**改任一份都要按下面整条链跑一遍。**

### 五道验收（改完必须全绿）

```powershell
$G = "E:\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
$P = "F:\GodotProject\YQQS"

# 1) 生成图集（自带逐瓦片自检：实心象限必须等于索引的位）
& $G --headless --path $P --script res://tools/refart/gen_ground.gd

# 1b) 生成角色/敌人图集（自带落地对齐：内容底边贴到距格底 2px）
& $G --headless --path $P --script res://tools/refart/gen_chars.gd

# 1c) 生成场景道具（13 张独立 PNG + props 图集）
& $G --headless --path $P --script res://tools/refart/gen_props.gd
& $G --headless --path $P --script res://tools/refart/gen_props_atlas.gd

# 1d) 武器 / UI / 特效
& $G --headless --path $P --script res://tools/refart/gen_weapons.gd
& $G --headless --path $P --script res://tools/refart/gen_ui.gd
& $G --headless --path $P --script res://tools/refart/gen_vfx.gd

# 2) 必须 import，否则运行时读到旧 PNG（这一步骗过我）
& $G --headless --path $P --import

# 3) 渲染逐像素验证（★ 必须真渲染器，SubViewport 在 --headless 下不产图）
& $G --path $P --script res://tools/refart/verify_dualgrid.gd
& $G --headless --path $P --script res://tools/refart/verify_all_assets.gd
& $G --headless --path $P --script res://tools/refart/verify_chars.gd
& $G --headless --path $P --script res://tools/refart/verify_props.gd
& $G --headless --path $P --script res://tools/refart/check_chars_layout.gd

# 4) 游戏内实际使用验收 + 回归检查（地形换了渲染方式后，
#    碰撞/装饰落地/玩家出生这些依赖逻辑格的系统必须没被带偏）
& $G --path $P res://tools/DualGridAcceptance.tscn
& $G --headless --path $P res://tools/DualGridRegression.tscn
& $G --path $P res://tools/CharAcceptance.tscn

# 5) 工程总自检
& $G --headless --path $P res://tools/Validation.tscn
& $G --headless --path $P res://tools/SmokeTest.tscn
```

## 7. 素材进度：**35 / 35 全部落地** ✅

契约见 `docs/10_美术素材规格与双网格瓦片契约.md` §3，逐文件比对由
`verify_all_assets.gd` 完成（尺寸 / 空图 / 越色 / 半透明 四项硬检查）。

| 类别 | 文件 | 生成器 |
|---|---|---|
| 角色 | `player_ranger.png` | `gen_chars.gd` |
| 敌人 | `enemy_slime/bat/mushroom/goblin/goblin_archer/goblin_guard.png` | `gen_chars.gd` |
| BOSS | `boss_goblin_priest.png` | `gen_chars.gd` |
| 地形 | `tileset_forest_ground.png`、`tileset_forest_wall.png` | `gen_ground.gd` |
| 场景道具 | `prop_*.png` × 13 | `gen_props.gd` |
| 道具图集 | `props.png` | `gen_props_atlas.gd` |
| 武器 | `weapons.png`、`weapon_cherry_shotgun.png` | `gen_weapons.gd` |
| UI | `ui_panel.png`、`ui_bar.png`、`ui_bar_armor.png`、`ui_frame_rarity.png` | `gen_ui.gd` |
| VFX | `vfx_hit_spark/muzzle_flash/petal/orb/arrow.png` | `gen_vfx.gd` |

### 一个仍然存在的"接了但没接线"的地方

`vfx_*.png` 五张已按契约生成并登记进 `Atlas.SHEETS`，但
**`combat_fx.gd` 目前仍用 `props.png` 里的单帧火花/闪光**（靠改 scale/rotation 凑动感）。
换成序列图需要改 `combat_fx.gd` —— 那次改动属于"表现层调优"，
不在"素材替换"的范围内，所以先把图备好、在 Atlas 里注明，避免误以为已经生效。

其余素材（角色/敌人/地形/道具/武器/UI）都已经被代码实际引用。

## 8. 踩坑总表（改这个目录之前，建议先扫一眼）

---

## 8. 踩坑总表（改这个目录之前，建议先扫一眼）

| 症状 | 根因 | 教训 |
|---|---|---|
| 地形整片错位 | 索引位与象限的对应写反（连环错了 5 次） | 16 项映射写显式表 + `self_test()`，别现场推导 |
| "改了代码但行为不变" | 文件里出现**重名函数**，前面那份遮蔽了后面那份 | 怀疑没生效时，第一步是打印运行时实际值 |
| "线性律不成立" | 穷举时漏了单 bit 组合 | 穷举要穷干净，否则会得出反向结论 |
| 1 格宽的洞被放大成十字 | 内圆角裁切只判了 `c==1`，没要求两个轴向邻居都为 0 | 裁切条件必须局部化，否则会"隔空啃" |
| 采样点全错、报一堆假失败 | 忘了显示层有 (−8,−8) 偏移 | 采样基址要按实测几何算，别按直觉 |
| 一片"洞未被挖空"的假警报 | 半径 7px 时相邻地形圆角**合法地**弯进隔壁格 | 别用固定采样点做断言，用逐像素位图比对 |
| 满格瓦片接缝可见 | 噪声不是 16 周期 | 可平铺性必须用周期性噪声，并用 `_verify_seamless()` 断言 |
| `hash % 13` 分布整批漂移 | GDScript int 溢出行为不稳定 | 生成器里用掩码归一化，别依赖大质数乘法 |
| 某地表整片消失 | 4 种地表写进同一个 `TileMapLayer`（`set_cell` 是覆盖） | 一种地表一个图层 |
| 中文件被 `Set-Content` 写坏 | PowerShell 往返丢 UTF-8 | **别用 PowerShell 重写含中文的源文件**，用编辑工具 |
| 角色"浮在空中" | 字符画是按"从上往下数"写的，格底留了 6~8 行空白 | 用 `_baseline()` 按参考帧统一下移；别逐格对齐（会把跳跃姿势压平） |
| BOSS 只占格子右下角一角 | 给字符画套了 `scale=2`，而它本来就是按 64 格手写的 | 先看字符画的实际列宽，再决定要不要 scale |
| BOSS 某格全空 | 死亡帧的位移把内容推出了画布 | 位移量要按"内容实际行范围"算，不是拍脑袋 |
| "本脚本全绿、Validation 却报错" | 两处空素材阈值不一致（2.5% vs 4%） | 两个校验器的判据必须同源同值 |
| `Vector4i` 分量用错 | `bb.w` 看着像 y，其实是 x | 包围盒改成具名 Dictionary，不点分量 |
| `Cannot pass a value of type Image as Image` | 混用 `RefArt.new_img()` 与 `Image.create()` | 同一条链上统一用同一种构造方式 |
| 道具整体浮空 / 摆一排看着歪 | 内容底边没贴画布底、或水平没居中 | 生成器统一做"贴底 + 居中"（`gen_props.gd` 的 `_ground()`），并用 `verify_props.gd` 断言 |
| 装饰改了但还是旧画风 | 同一个 `_deco_*` 函数在文件里被定义了**两次**，后面的旧实现覆盖了新的 | 改完 grep 一下函数名；重名函数是这个项目里反复出现的坑 |
| 道具用 scale 放大后像素比场景粗 | 拿 16×16 小图标 scale 1.45 当大树 | 素材本身就该有真实尺寸，别靠缩放凑 |
| 特效序列图的"淡出帧"被判成空素材 | Validation 要求每格 ≥4% 实心，而仅剩 2~3 个像素的余烬帧不达标 | 末帧要画成"暗淡但还在"（≈10 像素），不能凭空消失 |
| 图集出现调色板外的颜色 | 用了 `shade_v()` 线性渐变，插值出没人选过的中间色 | 像素画的渐变要做成**硬分段**（`band_v()`），别用连续插值 |
| 帧序列表高度不对（64×8 而非 64×16） | `_sheet()` 只收一个 cell 参数，帧宽=画布高 | 帧宽与画布高是两回事，分开传参 |

