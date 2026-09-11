# 11 · GPT Image 2 素材生成提示词包

> 配套文档：[`10_美术素材规格与双网格瓦片契约.md`](10_美术素材规格与双网格瓦片契约.md)
> —— 尺寸/网格/格子语义的**唯一权威**在那篇；本文是**可直接粘贴给 GPT Image 2 的提示词**。
>
> **用法**：每条提示词 = `【全局前缀】` + `【本文件提示词】`。全局前缀整包通用，粘贴一次即可。
>
> **风格目标**：《元气骑士前传》(Soul Knight Prequel)。
> **输出目标**：替换 `assets/sprites/` 下现有素材，**文件名必须逐字一致**。

---

## 0. 使用流程（先读，能省掉一整轮返工）

```
① 复制 §1 全局前缀
② 复制目标文件的 §N 提示词，前缀 + 提示词一起发
③ 生成后按 §15 归一化（缩放到目标尺寸 → 吸附调色板 → 切片）
④ 按 §16 校验清单自检，不合格就只重出**那一张**
```

**一次要几张？** 建议按文件逐张生成，**不要**一次要 14 张 —— 同一次生成里的字体/比例/描边会漂移。

**如果工具一次只能出一张**：地图图集（§5）是唯一建议「分 4 次出、每次一种地表」的例外。

---

## 1. 全局前缀（每条提示词前都加这一段）

```
Pixel art sprite sheet for a 2.5D top-down action RPG, in the art style of
"Soul Knight Prequel" (元气骑士前传 / ChillyRoom): bright, chunky, readable
pixel art with a soft three-quarter-top camera.

TECHNICAL - MUST BE EXACT:
- The final image must be a hard-edged, TRUE PIXEL ART rendering. Every pixel
  is either fully opaque or fully transparent. NO anti-aliasing, NO soft edges,
  NO blur, NO semi-transparent fringe.
- Use a limited palette of 32 colors, high saturation, bright. Include this
  exact color set: #0d0b1f #221a2e #3a3040 #5a4d63 #8a7f92 #c8c5bd #ffffff
  #243d1c #3a5c2a #5c8f3a #8fc75a #c9e88a #d9c46a #4a3524 #6b4a2f #a3713f
  #d9a866 #7d7a75 #a8a49c #d6d2c8 #26303f #3d5266 #5f86a6 #9fc4d9 #7a2f3a
  #c23a3a #f2762e #ffc14d #5d2a78 #b44ac9 #f28fc9 #8fe0f2
- Do NOT use gradients, do NOT dither, do NOT use more than 3 shading steps
  per material.
- Fully TRANSPARENT background (alpha = 0). No white background, no checkerboard,
  no drop shadow on the canvas, no ground plane, no text, no labels, no numbers,
  no watermark, no signature, no border, no grid lines, no ruler marks.
- Output the artwork at a large integer scale (e.g. 16x) so that every logical
  pixel is a crisp square block. Do NOT smooth anything when scaling.

ART DIRECTION:
- 2.5D "three-quarter top-down" view: we see a bit of the top and mostly the
  front. Characters stand upright on the ground plane, feet at the bottom.
- Fixed light source from the UPPER-LEFT at 45 degrees. Dark shading on lower
  and right side, 1-2 px highlight on top-facing surfaces.
- Consistent 1 pixel hard outline in near-black #0d0b1f around every silhouette.
  (Boss may use a 2 pixel outline.)
- Silhouette-first design: each sprite must still be identifiable when scaled
  down to 16x16. Avoid thin 1px floating details.
- Chunky, friendly, slightly cartoonish proportions. Rounded shapes, no sharp
  realism, no anime faces, no visible facial detail beyond 1-2 dark pixels.

LAYOUT:
- Neat uniform grid, cells of equal size, each sprite centered in its own cell
  and NOT touching the cell edge. Leave at least 1 px of transparent gutter
  between neighbouring cells. Nothing may bleed across cell boundaries.
- Reading order is left-to-right, top-to-bottom, exactly as described below.

STRICTLY AVOID:
- NES/8-bit look, GameBoy green, monochrome, washed-out pastel, muddy colors.
- Dark dungeon / gothic / horror mood. This is a bright forest adventure.
- 3D render, painted illustration, vector art, cel-shaded anime, watercolor.
- Any text, logo, UI mockup chrome, or annotation inside the image.
```

---

## 2. 角色 · `player_ranger.png`

**文件名**：`player_ranger.png` ｜ **尺寸**：`128 × 128` ｜ **网格**：32 px，**4 列 × 4 行**（16 格）

```
Generate a 4x4 grid character sheet, 4 columns and 4 rows, every cell 32x32
pixels, total canvas 128x128 pixels. A total of 16 cells, all cells must contain
a sprite (no empty cells).

CHARACTER: a young forest ranger / archer hero.
- Short messy auburn hair, no helmet, big determined eyes (2 dark pixels).
- Layered leather armour in warm brown (#6b4a2f / #a3713f) with lighter straps.
- A cherry-blossom PINK scarf (#f28fc9) around the neck - this is the character's
  signature color, keep it identical in every cell.
- Tall dark boots (#3a3040).
- A small shortbow (#d9a866 with #c8c5bd string), held in the right hand.
- About 28 pixels tall inside the 32x32 cell, feet 2 px above the cell bottom.

GRID SEMANTICS (left-to-right, top-to-bottom):
Row 1 (facing the camera / down):
  (1,1) idle standing      (1,2) walk frame A      (1,3) walk frame B
  (1,4) roll - crouched into a ball, arms tucked, scarf trailing
Row 2 (facing away / up - we see the BACK of the head and cape):
  (2,1) idle standing      (2,2) walk frame A      (2,3) walk frame B
  (2,4) roll from behind
Row 3 (facing right in profile):
  (3,1) idle standing      (3,2) walk frame A      (3,3) walk frame B
  (3,4) roll in profile
Row 4 (special poses, facing the camera):
  (4,1) hurt - recoiling back, red flash overlay on the body
  (4,2) attack - bow drawn, arrow nocked, aiming forward
  (4,3) dead - lying on the ground, eyes closed
  (4,4) dash - leaning far forward, motion smear on the scarf

All 16 cells must show THE SAME character with identical colors and identical
outline weight. The walk frames must differ only in the legs and arm swing.
```

---

## 3. 小怪 · 6 张敌人图集

> 6 张共用同一套提示词骨架，只替换 `CREATURE` 段落。
> 每张：**文件名** / **尺寸 128×128** / **32 px，4 列 × 4 行**。

### 3.1 `enemy_slime.png`

```
Generate a 4x4 grid sprite sheet, 4 columns, 4 rows, every cell 32x32 px,
canvas 128x128 px, all 16 cells filled.

CREATURE: a forest slime.
- A rounded translucent blob, body in grass green (#8fc75a base, #5c8f3a shading,
  #c9e88a top highlight).
- Two tiny black dot eyes, a small happy mouth. Inside the body, one darker
  green blob core visible.
- A tiny leaf stuck on top of its head. No limbs. Squashes and stretches.

GRID SEMANTICS:
Row 1 (idle loop, faces camera): (1,1) tall idle  (1,2) squashed  (1,3) mid
  (1,4) slightly stretched up
Row 2 (attack, lunging forward): (2,1) wind up (leaning back)  (2,2) launch
  (2,3) airborne stretched  (2,4) landing splat
Row 3 (reactions): (3,1) hurt - eyes closed, body shrunk  (3,2) stunned - eyes
  as spinning spirals  (3,3) death frame A - melting, flattened  (3,4) death
  frame B - a puddle with the eyes floating on top
Row 4 (special): (4,1) warning pose - glowing outline  (4,2) casting - raising a
  small green energy orb  (4,3) cast release - orb flying off  (4,4) bounce mid-air
```

### 3.2 `enemy_bat.png`

```
Generate a 4x4 grid sprite sheet, 4 columns, 4 rows, every cell 32x32 px,
canvas 128x128 px, all 16 cells filled.

CREATURE: a forest bat. Purple-grey fur (#5a4d63 base, #3a3040 shade, #8a7f92
highlight), large membrane wings (#b44ac9 tinged dark magenta), two tiny fangs
(#ffffff), two big yellow eyes (#ffc14d) with black pupils.
- Slight 2.5D: we see a hint of the belly from below-front.

GRID SEMANTICS:
Row 1 (idle hovering, facing camera): (1,1) wings full up  (1,2) wings mid
  (1,3) wings full down  (1,4) wings folded
Row 2 (attack, diving): (2,1) screech with mouth open  (2,2) dive, wings swept
  back  (2,3) claw swipe  (2,4) recover after the dive
Row 3 (reactions): (3,1) hurt  (3,2) stunned - flapping erratically, tilted
  (3,3) death A - wings collapsing  (3,4) death B - falling upside down
Row 4 (special): (4,1) warning - eyes glowing  (4,2) spit charge - mouth glowing
  purple  (4,3) spit release  (4,4) hanging upside down from above
```

### 3.3 `enemy_mushroom.png`

```
Generate a 4x4 grid sprite sheet, 4 columns, 4 rows, every cell 32x32 px,
canvas 128x128 px, all 16 cells filled.

CREATURE: an angry walking mushroom.
- Wide red-brown cap (#c23a3a top, #7a2f3a shade, #ffc14d spots), thick cream
  stem (#d6d2c8 with #a8a49c shading), two small stubby legs and one arm.
- Grumpy face on the stem: two dark angry eyes and a downturned mouth.

GRID SEMANTICS:
Row 1 (idle, facing camera): (1,1) idle  (1,2) waddle A  (1,3) waddle B
  (1,4) hop - airborne
Row 2 (attack): (2,1) crouch down  (2,2) headbutt forward  (2,3) spit spore cloud
  (2,4) recover
Row 3 (reactions): (3,1) hurt  (3,2) stunned  (3,3) death A - cap falling off
  (3,4) death B - flat cap on the ground with the stem gone
Row 4 (special): (4,1) warning - cap shaking, spores rising  (4,2) cast - spore
  ring expanding  (4,3) release  (4,4) cap hardened into a stone-grey shield
```

### 3.4 `enemy_goblin.png`（同时被精英 `goblin_chief` 复用）

```
Generate a 4x4 grid sprite sheet, 4 columns, 4 rows, every cell 32x32 px,
canvas 128x128 px, all 16 cells filled.

CREATURE: a small green goblin scout.
- Green skin (#5c8f3a base, #3a5c2a shade, #8fc75a highlight), big pointed ears,
  long crooked nose, one tooth sticking out.
- Ragged brown loincloth (#6b4a2f), a crude short sword (#a8a49c blade,
  #6b4a2f handle) in the right hand.
- Hunched posture, oversized head - classic chunky goblin proportions.

GRID SEMANTICS:
Row 1 (idle, facing camera): (1,1) idle sniffing  (1,2) walk A  (1,3) walk B
  (1,4) walk C with a bigger stride
Row 2 (attack): (2,1) wind up  (2,2) slash  (2,3) second slash  (2,4) recover
Row 3 (reactions): (3,1) hurt  (3,2) stunned - dizzy stars  (3,3) death A
  crumpling  (3,4) death B on the ground
Row 4 (special): (4,1) warning - raising the sword  (4,2) taunt - chest thump
  (4,3) cast - throwing a rock  (4,4) lunge
```

### 3.5 `enemy_goblin_archer.png`

```
Generate a 4x4 grid sprite sheet, 4 columns, 4 rows, every cell 32x32 px,
canvas 128x128 px, all 16 cells filled.

CREATURE: a goblin archer - SAME species and SAME colors as the basic goblin
(green skin #5c8f3a, brown rags #6b4a2f) but wearing a leather cap and a quiver
of arrows on the back. Carries a wooden bow.

GRID SEMANTICS:
Row 1 (idle, facing camera): (1,1) idle  (1,2) walk A  (1,3) walk B  (1,4) walk C
Row 2 (attack, drawing the bow in profile): (2,1) nock arrow  (2,2) draw
  (2,3) full draw with tension  (2,4) release
Row 3 (reactions): (3,1) hurt  (3,2) stunned  (3,3) death A  (3,4) death B
Row 4 (special): (4,1) warning  (4,2) aiming upward  (4,3) multishot - three
  arrows on the string  (4,4) backstep while shooting
```

### 3.6 `enemy_goblin_guard.png`

```
Generate a 4x4 grid sprite sheet, 4 columns, 4 rows, every cell 32x32 px,
canvas 128x128 px, all 16 cells filled.

CREATURE: a goblin guard - SAME green skin (#5c8f3a) as the other goblins, but
bulkier and armoured. Wears a dented iron pot helmet (#a8a49c with #7d7a75
shading) and a rusted plate chestpiece. Carries a big wooden shield with a metal
boss in the left hand and a mace in the right. Shoulders slightly hunched behind
the shield.

GRID SEMANTICS:
Row 1 (idle, facing camera): (1,1) idle behind shield  (1,2) walk A  (1,3) walk B
  (1,4) walk C
Row 2 (attack): (2,1) shield bash wind up  (2,2) shield bash  (2,3) mace overhead
  (2,4) mace smash down
Row 3 (reactions): (3,1) hurt  (3,2) stunned  (3,3) death A  (3,4) death B
Row 4 (special): (4,1) warning  (4,2) brace - crouching behind the shield
  (4,3) shield glow (magic ward)  (4,4) charge forward
```

---

## 4. BOSS · `boss_goblin_priest.png`

**文件名**：`boss_goblin_priest.png` ｜ **尺寸**：`256 × 256` ｜ **网格**：64 px，**4 列 × 4 行**

```
Generate a 4x4 grid BOSS sprite sheet, 4 columns, 4 rows, every cell 64x64
pixels, canvas 256x256 pixels, all 16 cells filled.

Creature: Goblin High Priest - the boss of the Silent Forest.
- A tall, gaunt goblin in a deep purple ritual robe (#5d2a78 robe with #b44ac9
  trim and #ffc14d gold hems). A large hood with a shadowed face where only two
  glowing magenta eyes (#f28fc9) are visible.
- Oversized bony hands with long fingers. Holds a gnarled wooden staff topped
  with a floating pink-violet crystal orb.
- Ritual ornaments: gold shoulder pauldrons, hanging bone charms, a heavy
  amulet. About 56 px tall inside the 64x64 cell.
- This is a BOSS: 2 px outline, slightly more detail allowed, but still clearly
  the same pixel-art style and the same palette as the small enemies.

GRID SEMANTICS:
Row 1 (idle loop, facing camera): (1,1) idle floating robe  (1,2) idle bob down
  (1,3) idle bob up  (1,4) ritual stance, arms raised
Row 2 (melee combo): (2,1) wind up staff  (2,2) vertical staff slam  (2,3) sweep
  with the robe  (2,4) recover
Row 3 (spell casting): (3,1) raise orb overhead  (3,2) orb fully charged, both
  arms up  (3,3) summon - three small magic circles appear  (3,4) release -
  magenta shockwave, robe flaring outward
Row 4 (special): (4,1) hurt - hood torn, recoiling  (4,2) enraged - eyes burning
  bright, robe glowing  (4,3) death A - collapsing, orb falling  (4,4) death B -
  empty robe and burning orb on the ground

Also produce, as a SEPARATE single image (no grid): "boss_goblin_priest_icon.png",
64x64 pixels, a BOSS portrait icon - just the hooded head and shoulders, same
palette, transparent background.
```

---

## 5. 双网格地表图集 · `tileset_forest_ground.png` ★最关键

> **这张图决定了整个地图的观感。** 生成前请先看完 §5.1 的原理解释。

### 5.1 要给模型讲清楚的事（已写进提示词，这里给人看）

- 图集是 **256×256 = 16 列 × 16 行，每格 16×16**。
- 每 **4 列 × 4 行 = 16 格** 是**同一种地表**的 16 个「角点变体」。
- 这 16 格不是随机美术，而是**严格按 4 个角是否属于本地形**排出来的，
  顺序是：左上角是索引 0，右下角是索引 15；索引 = 行主序。
- 4 种地表放在 2×2 的大块里：草地(左上) / 泥土(右上) / 石板(左下) / 圣坛(右下)。
- 剩下 8 个大块留空（纯透明）。

> ⚠️ 模型很可能画错排列。**这是全包里最需要人工复核的一张。**
> 复核方法：把草地块单独切出来，按 §5.2 的 4×4 表格逐格对号入座。

### 5.2 提示词（整张图集）

```
Generate a PIXEL ART TILESET SHEET, canvas exactly 256x256 pixels, divided
into a 16 columns x 16 rows grid where EVERY tile is exactly 16x16 pixels.
No gaps, no padding, no grid lines drawn.

The sheet contains FOUR terrain blocks, each block being 4 columns x 4 rows
(16 tiles). The remaining area of the canvas is fully transparent.

BLOCK POSITIONS ON THE CANVAS (columns and rows counted from 0):
  - GRASS block   : columns 0-3,   rows 0-3      (grassland / forest floor)
  - DIRT  block   : columns 4-7,   rows 0-3      (packed brown dirt path)
  - STONE block   : columns 0-3,   rows 4-7      (weathered grey flagstone)
  - SANCTUM block : columns 4-7,   rows 4-7      (cursed violet-purple ritual floor)
  - everything else (columns 8-15, and rows 8-15): leave 100% transparent.

WITHIN EACH 4x4 BLOCK, THE 16 TILES ARE AN AUTOTILE CORNER-VARIANT SET.
Read the block left-to-right, top-to-bottom. A tile is defined by which of its
FOUR CORNERS belong to the terrain (1 = terrain, 0 = background).
The corner-to-position mapping is FIXED and MUST be followed exactly:

  tile at block position (col,row) index = row*4 + col
  index 0  = NW0 NE0 SW0 SE0  -> completely empty / background only
  index 1  = NW0 NE0 SW0 SE1  -> a quarter-round shape filling the BOTTOM-RIGHT
             corner only (a 1/4 circle of terrain whose center is the tile center)
  index 2  = NW0 NE0 SW1 SE0  -> a quarter-round shape filling the BOTTOM-LEFT
  index 3  = NW0 NE0 SW1 SE1  -> the BOTTOM HALF filled, top half is background;
             the horizontal boundary sits exactly on the middle row of the tile
  index 4  = NW0 NE1 SW0 SE0  -> a quarter-round shape filling the TOP-RIGHT
  index 5  = NW0 NE1 SW0 SE1  -> two quarter-rounds: TOP-RIGHT and BOTTOM-LEFT,
             with a 4px wide diagonal background channel between them
  index 6  = NW0 NE1 SW1 SE0  -> two quarter-rounds: TOP-RIGHT and BOTTOM-LEFT,
             mirrored, with a 4px wide diagonal background channel
  index 7  = NW0 NE1 SW1 SE1  -> everything filled EXCEPT the bottom-left corner,
             which is an INNER CONCAVE notch (background colored, 4-5 px, with a
             soft inner shadow cast by the terrain onto the background)
  index 8  = NW1 NE0 SW0 SE0  -> a quarter-round shape filling the BOTTOM-RIGHT
  index 9  = NW1 NE0 SW0 SE1  -> two quarter-rounds: TOP-LEFT and BOTTOM-RIGHT
  index 10 = NW1 NE0 SW1 SE0  -> the LEFT HALF filled, right half background
  index 11 = NW1 NE0 SW1 SE1  -> everything filled EXCEPT the top-right inner
             concave notch
  index 12 = NW1 NE1 SW0 SE0  -> the TOP HALF filled, bottom half background
  index 13 = NW1 NE1 SW0 SE1  -> everything filled EXCEPT the bottom-right inner
             concave notch
  index 14 = NW1 NE1 SW1 SE0  -> everything filled EXCEPT the top-left inner
             concave notch
  index 15 = NW1 NE1 SW1 SE1  -> FULLY FILLED seamless tile, no background at all

CRITICAL GEOMETRY RULES (identical for all four blocks):
- All quarter-round corners use the SAME radius (about 5-6 px) and are centered on
  the tile center, so tiles can be stitched together pixel-perfectly.
- Where terrain meets background, add a 1-2 px darker root/edge line and a small
  contact shadow on the background side of the boundary - this is what makes the
  borders read as smooth, organic transitions instead of hard staircases.
- index 0 tiles are NOT transparent: fill them with a dark neutral background
  color (a very dark soil tone, #221a2e) so no holes appear at map edges.
- index 15 of each block MUST tile seamlessly with itself: its leftmost column of
  pixels must equal its rightmost column, and its top row must equal its bottom
  row. This is mandatory in all four blocks.
- All four blocks share the SAME corner shapes; only the materials differ.

MATERIALS:
- GRASS: bright saturated grass #5c8f3a with #8fc75a highlights and #3a5c2a
  shading, sparse 1px grass-blade details at the edges, dark #243d1c soil root
  where it meets the background.
- DIRT: packed brown earth #6b4a2f with #a3713f pebbles and #4a3524 shading,
  small 1-2 px stones, no grass.
- STONE: weathered grey flagstone #a8a49c with #7d7a75 shading and #d6d2c8
  highlights, faint 1px cracks, mossy #5c8f3a specks near the lower edge.
- SANCTUM: dark violet ritual floor #5d2a78 with #b44ac9 inlay lines and
  #f28fc9 glowing rune dots, the inner concave notches glowing faintly.

Style: bright, chunky, readable pixel art in the style of Soul Knight Prequel -
hard-edged pixels, no anti-aliasing, no blur, no gradients, no dithering, a
limited palette, transparent background outside the two terrain areas, and NO
text, NO numbers, NO labels, NO grid lines, NO watermark anywhere.
```

### 5.3 草地块的 16 格速查表（供人工复核，粘贴给模型可选）

```
GRASS block (columns 0-3, rows 0-3), index -> shape:
  0 (0,0) whole tile = dark soil background, no grass
  1 (1,0) grass only in the bottom-right quarter (rounded)
  2 (2,0) grass only in the bottom-left quarter (rounded)
  3 (3,0) bottom half grass, top half soil, straight horizontal boundary
  4 (0,1) grass only in the top-right quarter (rounded)
  5 (1,1) grass in top-right + bottom-left quarters (two dots)
  6 (2,1) grass in top-left + bottom-right quarters (two dots)
  7 (3,1) grass everywhere except a concave bite in the bottom-left
  8 (0,2) grass only in the bottom-right quarter (rounded, mirrored variant)
  9 (1,2) grass in top-left + bottom-right quarters
 10 (2,2) left half grass, right half soil, straight vertical boundary
 11 (3,2) grass everywhere except a concave bite in the top-right
 12 (0,3) top half grass, bottom half soil
 13 (1,3) grass everywhere except a concave bite in the bottom-right
 14 (2,3) grass everywhere except a concave bite in the top-left
 15 (3,3) full 16x16 seamless grass, nothing else
```

> **万一模型画出「整齐的方格感」**：说明它把 16 格画成了 16 种独立图案，
> 而不是**同一个地形被切掉不同角**。这时把提示词里这段加强重发：
> *"Every tile in a block must be made of the SAME material cut by DIFFERENT
> corner masks - not 16 different designs. Think of it as one seamless terrain
> texture seen through a 16-step stencil."*

---

## 6. 墙体 / 建筑图集 · `tileset_forest_wall.png`

**文件名**：`tileset_forest_wall.png` ｜ **尺寸**：`128 × 128` ｜ **网格**：16 px，**8 列 × 8 行**

```
Generate a pixel art TILESET sheet, canvas exactly 128x128 pixels, a grid of
8 columns x 8 rows, every tile exactly 16x16 pixels, all 64 tiles filled.
Tile index = row*8 + col. No grid lines drawn, no text, no labels.

These are CLIFF and STRUCTURE tiles for a bright forest adventure, art style of
Soul Knight Prequel: chunky hard-edged pixels, earthy browns #6b4a2f #a3713f
#d9a866, greys #7d7a75 #a8a49c #d6d2c8, moss greens #5c8f3a #3a5c2a, and the
forbidden blacks #0d0b1f for outlines.

Tile contents, in order:
Row 1 (0-7)   CLIFF TOP EDGE: hard top rim in three pieces (left end, middle A
              with a pebble, middle B with moss), right end, single-width top,
              top-left outer corner, top-right outer corner, top edge concave
              notch where the cliff juts inward.
Row 2 (8-15)  CLIFF FRONT FACE: dark shaded face, lit face, two faces with rock
              strata lines, mossy face, earthy slope face, cracked/broken face,
              a face with a shadow gradient at its bottom.
Row 3 (16-23) CLIFF BOTTOM EDGE: bottom rim left, middle A, middle B, right,
              bottom concave notch left, bottom concave notch right, bottom
              outer corner left, bottom outer corner right.
Row 4 (24-31) SIDE BOUNDARIES: left outer wall, left inner wall, right outer
              wall, right inner wall, solid dark fill, solid dark fill with moss,
              corner concave, corner convex.
Row 5 (32-39) STRUCTURES: wooden plank floor, wooden floor with cross beams,
              stone brick wall, cracked stone brick wall, a small tent, a wooden
              fence, a horizontal wooden bridge, a vertical wooden bridge.
Row 6 (40-47) RITUAL / SPECIAL GROUND: altar flagstone, magic circle center, magic
              circle ring segment, moss-covered stone, hanging vines, fallen
              leaves ground, swamp mud, a dark pit with a rim.
Row 7 (48-55) HAZARDS: upward spikes (bone-white), spikes with a skull, deep
              water, shallow water, glowing lava, a teleport pad with a swirl,
              a chest pedestal base, a carved totem.
Row 8 (56-63) MISC: solid near-black fill tile, a semi-transparent black shadow
              overlay tile, a mossy wall, a cave mouth, stone stairs, a wooden
              walkway, a small campfire, a pile of bones.

Every tile must be edge-to-edge seamless with its own kind (a run of tile 2,1
next to itself must show no seam). Keep outlines only where the material meets
a DIFFERENT material.
```

---

## 7. 道具与图标图集 · `props.png`

**文件名**：`props.png` ｜ **尺寸**：`256 × 128` ｜ **网格**：16 px，**16 列 × 8 行**

```
Generate a pixel art PROP AND ICON ATLAS, canvas exactly 256x128 pixels, a grid
of 16 columns x 8 rows, every cell exactly 16x16 pixels. All cells in rows 1-8
that are listed below must be filled; the unlisted cells must stay fully
transparent. No grid lines, no labels, no numbers inside the image.

Style: Soul Knight Prequel - chunky readable 16x16 pixel icons, 1 px dark
outline #0d0b1f, bright saturated palette, 2 shading steps plus one highlight.
Each icon must be centered with at least 1 px transparent margin.

Row 1 (y=0), treasure chests, six cells then ten empty:
  (0,0) normal chest CLOSED - plain wood #a3713f with iron bands
  (1,0) normal chest OPEN - lid up, empty inside
  (2,0) fine chest CLOSED - wood with a green #8fc75a gem clasp
  (3,0) fine chest OPEN
  (4,0) rare chest CLOSED - dark wood #6b4a2f with a BLUE #5f86a6 gem and gold
        #ffc14d trim
  (5,0) rare chest OPEN, glowing
  (6,0)-(15,0) fully transparent, empty

Row 2 (y=1), spinning gold coin, 4-frame loop:
  (0,1) coin face-on showing a full circle with a star mark #ffc14d / #d9a866
  (1,1) coin turned 45 degrees (narrower ellipse)
  (2,1) coin nearly edge-on (a thin vertical bar)
  (3,1) coin turned 45 degrees the other way
  (4,1)-(15,1) fully transparent

Row 3 (y=2):
  (0,2) red heart pickup #c23a3a with white highlight
  (1,2) blue mana crystal #5f86a6 with #9fc4d9 highlight
  (2,2) golden key #ffc14d
  (3,2) a blue-violet swirling portal disc, top-down, with a stone rim
  (4,2) an exit / stairway DOWN arrow sign made of stone
  (5,2) a small coin pouch #a3713f tied with a string
  (6,2)-(15,2) fully transparent

Row 4 (y=3):
  (0,3) a soft black ellipse drop shadow (pure black, feathered 1 px at the edge,
        no outline color)
  (1,3) a white/yellow 4-point HIT SPARK burst
  (2,3) a yellow-orange MUZZLE FLASH star shape
  (3,3) a red health potion bottle with a cork
  (4,3) a blue mana potion bottle with a cork
  (5,3) a rolled parchment scroll tied with a red ribbon
  (6,3)-(15,3) fully transparent

Row 5 (y=4), 8 SKILL ICONS, each inside a subtle dark round emblem frame:
  (0,4) roll / dodge - a curled boot with motion arcs
  (1,4) precision - a crosshair with an arrow
  (2,4) multishot - three arrows fanned out
  (3,4) crit - a burst star with a red center
  (4,4) vitality - a heart with a plus
  (5,4) energy - a lightning bolt in a blue circle
  (6,4) magnet - a horseshoe magnet with coin sparks
  (7,4) swift - a wing with speed lines
  (8,4)-(15,4) fully transparent

Row 6 (y=5), 8 UI ICONS, flat and clean, single accent color each:
  (0,5) a gold coin stack
  (1,5) an inventory bag / backpack
  (2,5) a warehouse crate on shelves
  (3,5) a branching skill tree (three connected nodes)
  (4,5) a gear / cogwheel
  (5,5) a bold X close button
  (6,5) a right-pointing arrow
  (7,5) a closed padlock
  (8,5)-(15,5) fully transparent

Row 7 (y=6), 4 RARITY FRAMES - 16x16 square item border frames, drawn as a
  2 px thick ornamental border with a hollow transparent center:
  (0,6) common - plain grey #c8c5bd border
  (1,6) uncommon - green #8fc75a border
  (2,6) rare - blue #5f86a6 border
  (3,6) legendary - orange #ffc14d border with a small star ornament at the
        top center
  (4,6)-(15,6) fully transparent

Row 8 (y=7), 6 DECORATION PROPS, 2.5D three-quarter view, sitting on the ground
  with the base at the bottom of the cell:
  (0,7) a closed wooden dungeon door with iron hinges
  (1,7) a burning torch on a bracket
  (2,7) a wooden barrel with iron hoops
  (3,7) a wooden crate
  (4,7) a small pile of bones
  (5,7) a spider web in a corner
  (6,7)-(15,7) fully transparent
```

---

## 8. 场景装饰（独立 PNG，共 13 张）

> 这些从旧 `props.png` / `tileset_forest.png` 里拆出来，做成独立文件是因为
> 它们要 y-sort（树会挡住角色）且尺寸各不相同。

### 8.1 `prop_tree_pine.png`

```
A single pixel art sprite, canvas exactly 32x48 pixels, transparent background.
A tall dark-green pine tree in 2.5D three-quarter top-down view, as seen in Soul
Knight Prequel: layered conical foliage in #3a5c2a / #5c8f3a with #8fc75a rim
light on the upper-left of each layer, a short brown trunk #6b4a2f visible at the
bottom, 1 px near-black #0d0b1f outline. The trunk base must sit exactly on the
bottom edge of the canvas (it is the ground anchor point). No drop shadow on the
canvas. Hard-edged pixels, no anti-aliasing, no gradients.
```

### 8.2 `prop_tree_broad.png`

```
A single pixel art sprite, canvas exactly 48x64 pixels, transparent background.
A large broadleaf forest tree in 2.5D three-quarter top-down view, Soul Knight
Prequel style: a rounded cloud-like canopy of #5c8f3a with #8fc75a highlights on
the upper-left and #243d1c shade at the lower-right, a thick trunk #6b4a2f with
visible roots flaring at the bottom, 1 px near-black outline. Trunk base exactly
on the bottom edge of the canvas (ground anchor). Hard-edged pixels, no blur,
no drop shadow on the canvas.
```

### 8.3 `prop_tree_dead.png`

```
A single pixel art sprite, canvas exactly 32x48 pixels, transparent background.
A bare dead tree, Soul Knight Prequel style: a twisted grey-brown trunk #6b4a2f
with #4a3524 shading, three or four crooked leafless branches, a small hollow
in the trunk, 1 px near-black #0d0b1f outline. Trunk base exactly on the bottom
edge of the canvas (ground anchor). Hard-edged pixels, no anti-aliasing.
```

### 8.4 其余 10 张小道具（共用一条提示词，逐个替换 `SUBJECT` 与尺寸）

```
A single pixel art sprite for a 2.5D top-down forest action RPG, Soul Knight
Prequel style. Canvas exactly {W}x{H} pixels, transparent background.
Hard-edged pixels, 1 px near-black #0d0b1f outline, bright saturated palette,
2 shading steps plus one highlight, light from the upper-left.
The object's base must sit on the bottom edge of the canvas (ground anchor).
No drop shadow on the canvas, no anti-aliasing, no gradients, no text.

SUBJECT: {SUBJECT}
```

| 文件名 | W×H | `SUBJECT` |
|---|---|---|
| `prop_rock_small.png` | 16×16 | a small grey boulder, #a8a49c with #7d7a75 shading and a mossy #5c8f3a patch |
| `prop_rock_big.png` | 32×32 | a large weathered boulder with cracks, moss patches and a chipped top |
| `prop_stump.png` | 16×16 | a cut tree stump with visible growth rings on top, #a3713f with #4a3524 shading |
| `prop_bush.png` | 16×16 | a low round leafy bush, #5c8f3a with #8fc75a top highlights and a few dark berries |
| `prop_flower_a.png` | 16×16 | a single pink #f28fc9 five-petal flower with a gold #ffc14d center on a short stem |
| `prop_flower_b.png` | 16×16 | a single red #c23a3a five-petal flower with a gold #ffc14d center on a short stem |
| `prop_mushroom.png` | 16×16 | a small decorative red-capped mushroom with white spots and a cream stem |
| `prop_tall_grass.png` | 16×16 | a tuft of tall wavy grass blades, #3a5c2a and #8fc75a, bending to the right as if in a breeze |
| `prop_pebble.png` | 16×16 | a small cluster of three flat grey pebbles on the ground |
| `prop_fallen_log.png` | 32×16 | a fallen mossy log lying horizontally, brown bark #6b4a2f with green moss #5c8f3a on top |

---

## 9. 武器图标 · `weapons.png`

**文件名**：`weapons.png` ｜ **尺寸**：`72 × 96` ｜ **网格**：24 px，**3 列 × 4 行**

```
Generate a pixel art WEAPON ICON sheet, canvas exactly 72x96 pixels, a grid of
3 columns x 4 rows, every cell exactly 24x24 pixels, all 12 cells filled.
No grid lines, no labels, no text, transparent background.

Style: Soul Knight Prequel equipment icons - each weapon laid out on a clean
diagonal from the lower-left to the upper-right, chunky readable shapes, 1 px
near-black #0d0b1f outline, bright saturation, 2 shading steps plus a highlight,
light from the upper-left. Each icon centered in its cell with a 1 px margin.

Row 1 - COMMON quality (plain iron and wood, no glow):
  (0,0) iron sword: straight grey #c8c5bd blade, brown #6b4a2f grip, small crossguard
  (1,0) wooden club: a thick knobbly branch #a3713f with darker knots
  (2,0) hunting bow: a simple brown #a3713f shortbow with a plain string

Row 2 - UNCOMMON quality (green accent, polished):
  (0,1) fine blade: a slender polished steel sword with a GREEN #8fc75a gem in
        the pommel and green leather grip
  (1,1) battle axe: a wide single-bit axe, steel head #d6d2c8, green-wrapped haft
  (2,1) short bow: a recurve bow of dark wood with green #8fc75a limb tips

Row 3 - RARE quality (blue accent, magic metal):
  (0,2) knight greatsword: a massive two-handed sword, broad blue-steel #5f86a6
        blade, gold #ffc14d crossguard, blue gem
  (1,2) silver spear: a long spear with a leaf-shaped #d6d2c8 silver head, blue
        #5f86a6 tassel, ash-wood shaft
  (2,2) mithril bow: an ornate silver-blue bow with #9fc4d9 filigree and a blue gem

Row 4 - LEGENDARY quality (orange glow, ornate, magical):
  (0,3) flame brand: a sword with a dark blade and glowing ORANGE #f2762e flame
        running along the edge, ember particles
  (1,3) storm crossbow: a crossbow with brass #ffc14d fittings and small
        lightning arcs #8fe0f2 crackling around the limbs
  (2,3) arcane staff: a gnarled staff topped with a floating violet #b44ac9
        crystal orb and a small ring of gold runes

Consistency is critical: all 12 icons use the same outline weight, the same
shading logic and the same 45-degree presentation angle.
```

---

## 10. 樱花霰弹枪 · `weapon_cherry_shotgun.png`

**文件名**：`weapon_cherry_shotgun.png` ｜ **尺寸**：`96 × 96`（由 48×48 升到 2× 精度）

```
A single pixel art equipment icon, canvas exactly 96x96 pixels, transparent
background. Soul Knight Prequel style, legendary-tier presentation.

SUBJECT: the Cherry Shotgun - a legendary cherry-blossom themed shotgun.
- A chunky double-barrel shotgun angled from the lower-left to the upper-right.
- Metal body in warm charcoal and steel #7d7a75 with gold #ffc14d engravings and
  ornamental filigree along the barrels.
- The wooden stock is carved into a cherry-branch shape in #6b4a2f with pink
  #f28fc9 cherry blossom appliques, and a few loose pink petals drifting around
  the weapon.
- The muzzle glows with a soft warm #ffc14d / #ffe9a8 halo, and a small pink
  petal cluster forms the front sight.
- 1-2 px near-black #0d0b1f outline, 3 shading steps, light from the upper-left.

Hard-edged true pixel art: every pixel fully opaque or fully transparent, no
anti-aliasing, no blur, no gradients, no dithering, no text, no background.
```

---

## 11. UI · 4 张

### 11.1 `ui_panel.png`

```
A pixel art 9-SLICE UI PANEL, canvas exactly 64x64 pixels. This is a stretchable
panel texture: the middle 56x56 region will be tiled, and the outer 4 px border
on each side is the non-stretching frame, so keep the border art inside the
outer 4 px and keep the center simple.

Style: Soul Knight Prequel inventory panel - dark readable interior with a warm
carved-wood outer frame.
- Outer 4 px: carved wood #a3713f with a #d9a866 top highlight and #6b4a2f
  bottom shade, plus a 1 px near-black #0d0b1f outline on the very outside.
- A 1 px stone-grey #a8a49c inner line inset 4 px, then a 1 px #3a3040 line.
- Four round iron rivets #c8c5bd with a #8a7f92 shade, one in each corner of the
  frame, centered 7 px from each edge.
- The center must be a flat, dark, low-contrast fill #221a2e (this is where text
  and item slots are drawn, so it must stay readable and uniform).
- No text, no icons, no gradients, no anti-aliasing.
```

### 11.2 `ui_bar.png`

```
A pixel art STATUS BAR texture, canvas exactly 64x32 pixels, transparent
background. Horizontal fill bars that will be stretched along their length; keep
them perfectly uniform horizontally so stretching never shows a seam.

Top half (y 0-15): HEALTH bar - horizontal 3-step gradient from #c23a3a at the
  top to #7a2f3a at the bottom, a 1 px #ffe9a8 highlight row at the very top, and
  a 1 px near-black #0d0b1f bottom edge.
Bottom half (y 16-31): MANA bar - same structure but in blues #5f86a6 to #26303f
  with a #9fc4d9 highlight row.
Between them, a 1 px near-black separator line.

No text, no numbers, no icons, no end caps, no rounding on the left and right
edges - the bars must run edge to edge so they tile seamlessly on repeat.
```

### 11.3 `ui_bar_armor.png`

```
A pixel art ARMOR bar texture, canvas exactly 64x16 pixels, transparent
background. Identical structure to the top half of ui_bar.png but in steel
colors: horizontal 3-step gradient #d6d2c8 at the top, #a8a49c in the middle,
#7d7a75 at the bottom, a 1 px #ffffff highlight row at the very top and a 1 px
near-black #0d0b1f bottom edge. Perfectly uniform horizontally so it can be
stretched without seams. No text, no icons, no end caps, no anti-aliasing.
```

### 11.4 `ui_frame_rarity.png`

```
Generate a pixel art RARITY FRAME strip, canvas exactly 64x16 pixels, a grid of
4 columns x 1 row, every cell exactly 16x16 pixels, transparent background.
Each cell is an ornamental 16x16 item-slot border with a fully transparent hollow
center, drawn as a 2 px thick frame:
  (0,0) COMMON    - plain grey #c8c5bd frame with #8a7f92 shading
  (1,0) UNCOMMON  - green #8fc75a frame with a #c9e88a highlight and small leaf
        ornaments at the corners
  (2,0) RARE      - blue #5f86a6 frame with a #9fc4d9 highlight and a small gem
        ornament at the top center
  (3,0) LEGENDARY - orange #ffc14d frame with a #ffe9a8 hot highlight, a star
        ornament at the top center, and two tiny upward flourishes at the lower
        corners
All four frames must be exactly the same thickness and the same inner opening
size. No anti-aliasing, no glow outside the frame, no text.
```

---

## 12. VFX · 5 张（帧动画）

### 12.1 `vfx_hit_spark.png`

```
A pixel art hit-effect animation sheet, canvas exactly 96x16 pixels, a grid of
6 columns x 1 row, every frame exactly 16x16 pixels, transparent background.
A 6-frame impact spark animation in Soul Knight Prequel style: frame 1 a bright
white-yellow #ffffff / #ffe9a8 star burst, frame 2 the star expanding with orange
#ffc14d edges, frame 3 the widest spread with #f2762e tips and a few flying
sparks, frame 4 collapsing with #f2762e and #c23a3a, frame 5 small fading
embers, frame 6 only two or three tiny dim #7a2f3a specks. Hard-edged pixels,
no blur, no anti-aliasing, no background.
```

### 12.2 `vfx_muzzle_flash.png`

```
A pixel art muzzle-flash animation sheet, canvas exactly 96x16 pixels, 6 columns
x 1 row, each frame exactly 16x16 pixels, transparent background. A gun muzzle
flash firing to the RIGHT: frame 1 a small tight white #ffffff core, frame 2 a
4-point star flash with #ffe9a8, frame 3 the widest 6-point burst in #ffc14d,
frame 4 breaking apart into #f2762e petals of flame, frame 5 scattered embers,
frame 6 nearly empty. The flash must originate from the left-center of each frame
so it lines up with the gun barrel. Hard-edged pixels, no blur, no anti-aliasing.
```

### 12.3 `vfx_petal.png`

```
A pixel art cherry-petal burst animation sheet, canvas exactly 64x16 pixels,
8 columns x 1 row, each frame exactly 8x8 pixels, transparent background. Eight
frames of pink cherry petals (#f28fc9 with #ffe3f2 highlights) bursting outward
from the center and drifting down, the cluster spreading wider and getting
sparser until only two petals remain. Cute, chunky, readable at 8x8. Hard-edged
pixels, no blur, no anti-aliasing, transparent background.
```

### 12.4 `vfx_orb.png`

```
A pixel art magic orb animation sheet, canvas exactly 64x16 pixels, 4 columns x
1 row, each frame exactly 16x16 pixels, transparent background. Four frames of a
spinning violet magic orb: a dark violet #5d2a78 core, a #b44ac9 mid ring with
rotating brighter arcs, #f28fc9 rim light on the upper-left, and small sparkles
orbiting it. Frame to frame only the internal swirl rotates - the silhouette
stays identical. No anti-aliasing, no blur.
```

### 12.5 `vfx_arrow.png`

```
A pixel art arrow projectile animation sheet, canvas exactly 48x16 pixels, 3
columns x 1 row, each frame exactly 16x16 pixels, transparent background. Three
frames of a wooden arrow flying to the RIGHT: a brown #a3713f shaft, a grey
#c8c5bd triangular head, cream fletching, plus 1-2 px of motion streak behind
the tail in #ffffff at 50% visual weight. Frame 1 no streak, frame 2 a short
streak, frame 3 a long streak. Hard-edged pixels, no blur, no anti-aliasing.
```

---

## 13. 负面提示词（Negative prompt，独立字段时粘贴这段）

```
anti-aliasing, soft edges, blurry, semi-transparent pixels, gradients, dithering,
noise texture, photo texture, 3D render, CGI, painted illustration, oil painting,
watercolor, vector art, cel shading, anime, manga, chibi, realistic anatomy,
photorealistic, 8-bit, NES, GameBoy palette, monochrome, sepia, low contrast,
washed out, pastel, muddy colors, dark dungeon, gothic, horror, blood, gore,
gloom, vignette, lens flare, bloom, drop shadow, cast shadow on background,
white background, checkerboard background, colored background, 
text, letters, numbers, labels, captions, annotations, arrows drawn on the image,
watermark, signature, logo, copyright mark, UI chrome, mockup frame,
grid lines, cell borders, magenta guide lines, cyan guide lines, ruler marks,
cropped sprite, sprite cut off by cell edge, overlapping sprites, misaligned grid,
inconsistent character design between cells, inconsistent outline weight,
different art style per cell, extra limbs, missing limbs, floating parts
```

---

## 14. 一致性锁定句（改画风时只改这一句）

如果生成结果**风格不统一**（比如太暗、太写实、太可爱），不要逐张改提示词，
只改全局前缀里的这句，然后**把已通过的图挑 1-2 张作为风格参考图一起发**：

```
SAME ART STYLE AS THE ATTACHED REFERENCE IMAGE. Match its outline weight,
its shading step count, its palette saturation and its proportions exactly.
```

---

## 15. 后期归一化 SOP（必做，否则素材不可用）

| 步骤 | 操作 | 工具 |
|---|---|---|
| 1 | 缩放到 §3 表格的目标尺寸，**必须用最近邻（nearest neighbour）** | ImageMagick `-filter point -resize` / Aseprite Sprite > Sprite Size |
| 2 | 吸附调色板到 §1.1 的 32 色（Aseprite 的 Replace Color 或 `-remap`） | Aseprite / ImageMagick |
| 3 | 清除抗锯齿：alpha 阈值化（<128 → 0，≥128 → 255） | Aseprite / 脚本 |
| 4 | 切网格：按目标 cell 尺寸切片，**确认每格内容居中且不触边** | Aseprite Grid + Slice |
| 5 | 导出为 PNG，文件名与 §3 表格逐字一致，覆盖到 `assets/sprites/` | — |
| 6 | 跑 §16 校验清单 | Godot headless（见契约文档 §8） |

**ImageMagick 参考命令**（把 1024×1024 的 4×4 生成图缩到 128×128）：

```powershell
magick input.png -filter point -resize 128x128! output.png
```

> 注意 `!` 是强制精确尺寸（忽略宽高比）。**必须加**，否则会得到 128×127 之类的尺寸。

---

## 16. 提交前自检清单

对每张素材：

- [ ] 文件名与 `docs/10_美术素材规格与双网格瓦片契约.md` §3 表格**逐字一致**
- [ ] 画布尺寸**逐像素**一致（用 `identify` 或属性面板确认）
- [ ] 背景**完全透明**，没有白底/棋盘底
- [ ] 没有半透明像素（放大到 800% 检查边缘没有灰边）
- [ ] 每格内容**不跨格、不触边**
- [ ] 角色/敌人的**方向顺序**与 §4.1 / §4.2 一致（第 1 列 = 面向下）
- [ ] 配色收敛在 32 色内
- [ ] 图上**没有**任何文字、编号、辅助线、水印
- [ ] 双网格图集额外确认：**idx 15 可无缝自接**（左右列、上下行像素相等）

地图图集（`tileset_forest_ground.png`）另加：

- [ ] 4 个块在正确位置（草 0-3/0-3、泥 4-7/0-3、石 0-3/4-7、坛 4-7/4-7）
- [ ] 每块 16 格的「缺角方向」与契约 §5.2 的 4×4 表逐格对得上
- [ ] 4 个块的圆角半径**一致**（把 4 块的 idx1 并排看，半径必须相同）
- [ ] 8-15 列 / 8-15 行**全透明**

---

## 17. 快速索引（复制提示词用）

| 顺序 | 文件名 | 本文位置 |
|---|---|---|
| 1 | `player_ranger.png` | §2 |
| 2 | `enemy_slime.png` | §3.1 |
| 3 | `enemy_bat.png` | §3.2 |
| 4 | `enemy_mushroom.png` | §3.3 |
| 5 | `enemy_goblin.png` | §3.4 |
| 6 | `enemy_goblin_archer.png` | §3.5 |
| 7 | `enemy_goblin_guard.png` | §3.6 |
| 8 | `boss_goblin_priest.png` | §4 |
| 9 | **`tileset_forest_ground.png`** ★ | §5 |
| 10 | `tileset_forest_wall.png` | §6 |
| 11 | `props.png` | §7 |
| 12–24 | `prop_*.png`（13 张） | §8 |
| 25 | `weapons.png` | §9 |
| 26 | `weapon_cherry_shotgun.png` | §10 |
| 27 | `ui_panel.png` | §11.1 |
| 28 | `ui_bar.png` | §11.2 |
| 29 | `ui_bar_armor.png` | §11.3 |
| 30 | `ui_frame_rarity.png` | §11.4 |
| 31–35 | `vfx_*.png`（5 张） | §12 |

**建议生成顺序**：先出 `tileset_forest_ground.png`（§5）和 `player_ranger.png`（§2）——
这两张定了调，剩下的都用它们当风格参考图，一致性最好。
