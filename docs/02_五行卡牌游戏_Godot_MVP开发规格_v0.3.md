# 五行卡牌游戏：Godot MVP 开发规格 v0.3

## 1. MVP 目标

MVP 的唯一目标：

验证“五行能量同时作为费用、抗性和弱点”的战斗循环是否真正有趣。

MVP 必须完整跑通：

```text
进入战斗
→ 初始抽牌
→ 生成自然能量
→ 玩家出牌
→ 敌人 AI 出牌
→ 状态结算
→ 疲劳
→ 胜负
→ 重新开始
```

MVP 暂不开发：

- 大地图
- Roguelike 路线
- 商店
- 装备
- 卡牌升级
- 剧情系统
- PVP
- 驻场单位
- 召唤物
- 复杂角色养成
- 大规模动画
- 卡牌收藏系统
- 多属性卡牌

---

## 2. 技术路线

引擎：

Godot 4.x Stable

语言：

GDScript

表现形式：

2D 为主。

推荐采用：

- Control / Container 体系构建战斗 UI
- CanvasLayer 管理 HUD
- Tween 做卡牌移动、缩放、伤害反馈
- GPUParticles2D 做元素粒子
- Shader 做发光、扭曲、闪白等效果

---

## 3. MVP 默认战斗参数

```text
最大生命：100
初始手牌：4
手牌上限：8
初始五行能量：各 1
单元素能量上限：10
每回合自然能量：1
每回合基础抽牌：1
```

直接伤害卡：

```text
基础伤害原则上从 10 点量级开始
```

---

## 4. MVP 内容规模

建议首个可玩版本：

### 玩家

1 个角色。

### 敌人

3 种。

#### 敌人 A：火 / 木爆发

测试：

- 高能量储存
- 克制与抗性
- 高费爆发

#### 敌人 B：水 / 金控制

测试：

- 减能量
- 抽牌干扰
- 节奏控制

#### 敌人 C：五行均衡

测试：

- 综合策略
- 不同构筑适应性

### 卡牌

建议：

20～30 张测试牌。

---

## 5. 推荐目录结构

```text
res://
├── autoload/
│   ├── game_data.gd
│   └── rng_service.gd
│
├── battle/
│   ├── battle_scene.tscn
│   ├── battle_manager.gd
│   ├── battle_state.gd
│   ├── combatant.gd
│   ├── damage_system.gd
│   ├── energy_system.gd
│   └── ai/
│       └── enemy_ai.gd
│
├── cards/
│   ├── card_data.gd
│   ├── card_instance.gd
│   ├── card_view.tscn
│   ├── card_view.gd
│   └── effects/
│       ├── card_effect.gd
│       ├── damage_effect.gd
│       ├── heal_effect.gd
│       ├── draw_effect.gd
│       ├── gain_energy_effect.gd
│       ├── lose_energy_effect.gd
│       ├── convert_energy_effect.gd
│       └── apply_status_effect.gd
│
├── statuses/
├── ui/
├── data/
└── assets/
```

---

## 6. 数据与表现分离

战斗逻辑独立于 UI。

至少包含：

```text
BattleState
Combatant
CardData
CardInstance
StatusData
StatusInstance
CardEffect
```

UI 只负责：

- 显示
- 输入
- 动画

---

## 7. 元素枚举

```gdscript
enum Element {
    METAL,
    WOOD,
    WATER,
    FIRE,
    EARTH
}
```

推荐两个明确函数：

```gdscript
func get_element_countered_by(attack_element: Element) -> Element:
```

含义：

> 这个攻击属性克制哪个元素？

映射：

```text
METAL -> WOOD
WOOD  -> EARTH
EARTH -> WATER
WATER -> FIRE
FIRE  -> METAL
```

以及：

```gdscript
func get_counter_of(element: Element) -> Element:
```

含义：

> 哪个属性克制这个元素？

---

## 8. Combatant 数据

```gdscript
class_name Combatant
extends RefCounted

var max_hp: int = 100
var hp: int = 100

var energy := {
    Element.METAL: 1,
    Element.WOOD: 1,
    Element.WATER: 1,
    Element.FIRE: 1,
    Element.EARTH: 1
}

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []

var statuses: Array[StatusInstance] = []
var fatigue_level: int = 0
```

---

## 9. 卡牌数据

MVP 每张卡只有一个主属性。

```gdscript
class_name CardData
extends Resource

@export var id: String
@export var card_name: String
@export_multiline var description: String

@export var element: Element
@export var cost: int

@export var artwork: Texture2D
@export var effects: Array[CardEffect]
```

---

## 10. 自然能量算法

只统计当前 draw_pile 中剩余卡牌的主属性。

```gdscript
func generate_natural_energy(combatant: Combatant) -> void:
    var weights := {
        Element.METAL: 0,
        Element.WOOD: 0,
        Element.WATER: 0,
        Element.FIRE: 0,
        Element.EARTH: 0
    }

    for card in combatant.draw_pile:
        var element = card.data.element

        if combatant.energy[element] < 10:
            weights[element] += 1

    var chosen = weighted_random(weights)

    if chosen != null:
        combatant.energy[chosen] += 1
```

必须读取实时 draw_pile。

---

## 11. 抽牌逻辑

```gdscript
func draw_card(combatant: Combatant) -> void:
    if combatant.draw_pile.is_empty():
        apply_fatigue(combatant)
        return

    var card = combatant.draw_pile.pop_front()

    if combatant.hand.size() >= 8:
        combatant.discard_pile.append(card)
        return

    combatant.hand.append(card)
```

弃牌堆不会重新洗回。

---

## 12. 疲劳

```gdscript
func apply_fatigue(combatant: Combatant) -> void:
    combatant.fatigue_level += 1
    combatant.hp -= combatant.fatigue_level
```

疲劳属于无属性伤害。

---

## 13. 伤害系统

所有伤害统一走：

```gdscript
apply_damage(source, target, base_amount, element)
```

### 元素倍率

规则：

```text
最终倍率
= 1
- 同属性能量 × 0.1
+ 被攻击属性所克制的元素能量 × 0.1
```

例如：

20 点火伤攻击目标：

```text
目标火 = 6
目标金 = 4
```

则：

```text
倍率 = 1 - 0.6 + 0.4 = 0.8
最终伤害 = 16
```

### 推荐实现

```gdscript
func get_element_multiplier(target: Combatant, attack_element: Element) -> float:
    var same_energy: int = target.energy[attack_element]
    var countered_element: Element = get_element_countered_by(attack_element)
    var countered_energy: int = target.energy[countered_element]

    var multiplier := 1.0
    multiplier -= same_energy * 0.1
    multiplier += countered_energy * 0.1

    return max(multiplier, 0.0)
```

最终伤害：

```gdscript
var final_damage = roundi(base_damage * multiplier)
```

### 设计要求

UI 应能显示预计伤害。

例如：

```text
基础：20
火抗：-60%
克金：+40%
预计：16
```

---

## 14. 卡牌效果系统

禁止通过卡牌 ID 写大量 if / match 特例。

统一使用 Effect：

```text
DamageEffect
HealEffect
DrawEffect
GainEnergyEffect
LoseEnergyEffect
ConvertEnergyEffect
ApplyStatusEffect
DiscardEffect
```

一张牌：

```text
CardData
→ effects[]
→ 顺序执行
```

---

## 15. 状态系统

MVP 第一批建议：

- 灼烧
- 护盾
- 易伤
- 再生
- 元素封锁

统一钩子：

```gdscript
on_turn_start()
on_turn_end()
on_card_played()
on_before_damage()
on_after_damage()
```

---

## 16. 战斗状态机

```text
BATTLE_START
PLAYER_TURN_START
PLAYER_ACTION
PLAYER_TURN_END
ENEMY_TURN_START
ENEMY_ACTION
ENEMY_TURN_END
VICTORY
DEFEAT
```

BattleManager 是唯一回合控制者。

---

## 17. 敌人 AI

MVP 不需要行为树。

流程：

1. 找出所有能支付的卡牌
2. 计算基础权重
3. 根据局势调整权重
4. 带少量随机选择
5. 出牌
6. 重新评估
7. 无合适行动后结束回合

AI 可以读取：

- 双方 HP
- 双方五行能量
- 双方状态
- 自己手牌
- 自己牌库数量

AI 不需要向玩家公开下一行动。

---

## 18. 第一批伤害卡基准

### 1 费白板攻击

五系各一张：

```text
费用：1
基础伤害：10
```

### 2 费攻击

```text
费用：2
基础伤害：20
```

### 3 费重击

```text
费用：3
基础伤害：30～34
```

### 4～5 费

可以略超线性：

```text
4 费：40～46
5 费：50～60
```

原因：

高费卡会一次性消耗大量能量，同时改变使用者防御结构。

---

## 19. 第一批功能卡

### 获得能量

```text
聚火
费用：0
获得 1 火
```

或：

```text
费用：1
获得 2 指定元素
```

### 削减能量

```text
断流
费用：1 水
敌人失去 2 火
```

### 相生转换

```text
木生火
费用：1 木
额外失去 1 木
获得 3 火
```

### 抽牌

```text
潮思
费用：1 水
抽 2 张
```

### 治疗

```text
生息
费用：2 木
恢复 15～20 HP
```

---

## 20. 战斗 UI

### 顶部

敌人：

- 头像
- HP
- 五元素
- 手牌数量
- 抽牌堆数量
- 弃牌数量
- 状态

### 中间

只负责：

- 敌人战斗立绘
- 战斗背景
- 目标高亮
- 出牌动画
- 伤害数字
- 元素特效
- 状态反馈

不放规则说明。

### 底部

玩家：

- HP
- 五元素
- 手牌
- 抽牌堆数量
- 弃牌数量
- 状态

### 右下

- 结束回合按钮

---

## 21. MVP 动画反馈

### 出牌

```text
卡牌抬起
→ 放大
→ 飞向中心
→ 触发特效
→ 进入弃牌堆
```

### 支付能量

```text
对应能量球闪光
→ 数字降低
```

### 获得能量

```text
能量球放大
→ +1
```

### 伤害

```text
角色震动
→ 浮动伤害数字
```

### 克制 / 抗性

预计伤害或实际伤害附近可以简短显示：

```text
克制
抵抗
免疫
```

---

## 22. 开发顺序

### Milestone A：纯逻辑

完成：

- 能量
- 自然能量
- 抽牌
- 手牌
- 费用支付
- 元素伤害
- 疲劳
- 回合
- 胜负

### Milestone B：基础 UI

完成：

- HP
- 五行能量
- 手牌
- 卡牌选择
- 预计伤害
- 结束回合
- 敌人 AI

### Milestone C：完整 MVP 机制

完成：

- 状态
- 能量削减
- 能量转换
- 抽牌效果
- 治疗
- 手牌破坏

### Milestone D：视觉

加入：

- 卡牌插画
- 角色立绘
- 背景
- FX
- 音效
- Tween

### Milestone E：玩法测试

加入：

- 3 个敌人
- 20～30 张卡
- 数套预设构筑
- 对战日志
- 数值统计

---

## 23. MVP 成功标准

第一版只回答四个问题：

1. 储存能量获得抗性是否有趣？
2. 花费能量改变防御结构是否产生真实决策？
3. 攻击敌人能量是否值得，而不是永远打 HP？
4. 抽牌堆属性分布决定自然能量概率，是否真的让构筑和战斗产生差异？

如果四点成立，再扩大游戏。
