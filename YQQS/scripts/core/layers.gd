class_name Layers
extends RefCounted
## 物理层与掩码常量 —— 与 project.godot 的 layer_names 一一对应。
##
## 【框架约束】
## 代码里 **禁止** 出现裸整数位掩码（如 `collision_layer = 5`），
## 一律使用本文件的常量组合，例如 `Layers.ENEMY | Layers.OBSTACLE`。
##
## 当前层分配（见 tools/setup_project.gd）：
##   1 world        地形/墙（TileMap 物理层）
##   2 obstacle     静态障碍（树、石头）
##   3 player       玩家角色体
##   4 enemy        敌人角色体
##   5 player_hitbox  玩家攻击判定
##   6 enemy_hitbox   敌人攻击判定
##   7 player_hurtbox 玩家受击判定
##   8 enemy_hurtbox  敌人受击判定
##   9 pickup       掉落物拾取范围
##  10 interactable 可交互物（宝箱 / 传送门 / NPC）
##  11 projectile   投射物
##  12 trigger      区域触发器（房间入口等）

const WORLD := 1 << 0
const OBSTACLE := 1 << 1
const PLAYER := 1 << 2
const ENEMY := 1 << 3
const PLAYER_HITBOX := 1 << 4
const ENEMY_HITBOX := 1 << 5
const PLAYER_HURTBOX := 1 << 6
const ENEMY_HURTBOX := 1 << 7
const PICKUP := 1 << 8
const INTERACTABLE := 1 << 9
const PROJECTILE := 1 << 10
const TRIGGER := 1 << 11

## 玩家角色体的碰撞：撞地形与障碍
const PLAYER_BODY_LAYER := PLAYER
const PLAYER_BODY_MASK := WORLD | OBSTACLE | ENEMY

## 敌人角色体的碰撞：撞地形、障碍、玩家
const ENEMY_BODY_LAYER := ENEMY
const ENEMY_BODY_MASK := WORLD | OBSTACLE | PLAYER

## 玩家受击盒：被敌人攻击盒与投射物检测到
const PLAYER_HURTBOX_LAYER := PLAYER_HURTBOX
const PLAYER_HURTBOX_MASK := 0

## 敌人受击盒
const ENEMY_HURTBOX_LAYER := ENEMY_HURTBOX
const ENEMY_HURTBOX_MASK := 0

## 玩家攻击盒：检测敌人受击盒 + 地形（挡刀用）
const PLAYER_HITBOX_LAYER := PLAYER_HITBOX
const PLAYER_HITBOX_MASK := ENEMY_HURTBOX | WORLD

## 敌人攻击盒
const ENEMY_HITBOX_LAYER := ENEMY_HITBOX
const ENEMY_HITBOX_MASK := PLAYER_HURTBOX

## 投射物：检测目标受击盒 + 地形
const PROJECTILE_LAYER := PROJECTILE
const PROJECTILE_MASK_VS_ENEMY := ENEMY_HURTBOX | WORLD | OBSTACLE
const PROJECTILE_MASK_VS_PLAYER := PLAYER_HURTBOX | WORLD | OBSTACLE

## 掉落物拾取范围：只检测玩家角色体
const PICKUP_LAYER := PICKUP
const PICKUP_MASK := PLAYER

## 可交互物
const INTERACTABLE_LAYER := INTERACTABLE
const INTERACTABLE_MASK := PLAYER

## 区域触发器
const TRIGGER_LAYER := TRIGGER
const TRIGGER_MASK := PLAYER
