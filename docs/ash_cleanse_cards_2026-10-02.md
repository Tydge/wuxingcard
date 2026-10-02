# 2026-10-02 新增五张法术

本地源码0.7.0追加，75种卡牌（49种普通牌、26种召唤牌）共225个版本；30件法宝及78个召唤物模板不变。本轮不导出试玩包。

| 原牌 | 费用：原→精→玄 | 原版 | 一级 ·精 | 二级 ·玄 |
| --- | --- | --- | --- | --- |
| 裂脉诀 | 2→2→2 | 对对手造成12点金伤害，对手获得3层出血。 | 对对手造成14点金伤害，对手获得4层出血。 | 对对手造成16点金伤害，对手获得5层出血。 |
| 清露诀 | 1→1→1 | 降低自身5层中毒、2层灼伤。 | 降低自身6层中毒、3层灼伤。 | 降低自身7层中毒、4层灼伤。 |
| 瘴生诀 | 5→5→4 | 对手获得10层中毒，自身获得5层再生。 | 对手获得12层中毒，自身获得6层再生。 | 对手获得12层中毒，自身获得6层再生。 |
| 焚烬 | 2→2→2 | 造成15点火伤害；若消灭目标，获得2点土能量。 | 造成18点火伤害；若消灭目标，获得2点土能量。 | 造成20点火伤害；若消灭目标，获得3点土能量。 |
| 震岳诀 | 5→5→5 | 对所有召唤物造成30点土伤害。 | 对所有召唤物造成35点土伤害。 | 对所有召唤物造成40点土伤害。 |

各级为完整效果，不相加。卡牌费用消耗所属五行灵气；流血沿用现有“出血”状态名。

## 结算与交互

- 裂脉诀直接命中对手角色，不选择召唤物。
- 清露诀按顺序降低自身中毒与灼伤；不足时清零，不影响出血，不提供治疗。支付费用后的致命出血会中止清理。
- 瘴生诀中毒仅给予对手角色，再生仅给予自身；玄级费用降至4。
- 焚烬可选敌方角色或召唤物，只有此伤害消灭目标才回能。先结算击杀回能，再判定胜负；回能遵守10点上限、封锁，中毒按实际获得的一次事件结算。
- 震岳诀伤及双方全部存活召唤物，不伤角色。拖至任一存活召唤物；无召唤物时不能使用。各目标独立计算相性，同一段攻击状态只消耗一次。PC与触屏使用相同目标规则和预览。
- 新牌自动接入藏经阁、测试构筑、随机牌组、生牌候选和无尽开局／集市；升级逐副本保留。
- 无尽规则版本升为6，旧战斗先备份再从同一对手开局继续；资产与连胜保留。

## 美术

全部精确提示词、生成原图位置与最终游戏资源路径见[美术清单](ash_cleanse_art_2026-10-02.json)。

使用内置imagegen工具，每张独立生成，三级共用原版卡图。焚烬根据用户反馈改为狼形妖兽在烈焰中化成灰烬，原始石傀儡版本未接入游戏。

### 裂脉诀

- 游戏资源：`assets/cards/generated/metal_rupture.webp`
- 场景提示词：一柄锋锐银金飞剑的单次剑气划破古装敌人袖甲，细微暗红灵光从裂口散出，突出裂脉剑术，无血腥细节；金白剑光、深蓝山崖背景。

### 清露诀

- 游戏资源：`assets/cards/generated/water_clear_dew.webp`
- 场景提示词：晶莹清露悬浮在古老石碗上方，蓝色水光净化紫绿色毒雾和橙红余火，清冷山间泉池。

### 瘴生诀

- 游戏资源：`assets/cards/generated/wood_miasma_bloom.webp`
- 场景提示词：苍翠灵藤开出浓紫瘴花，毒雾向远方弥散，翠绿生机沿藤茎回流，古林湿润石阶，生死循环。

### 焚烬

- 游戏资源：`assets/cards/generated/fire_burn_to_earth.webp`
- 场景提示词：单个有生命感的狼形妖兽被炽烈橙红火焰吞没，轮廓从毛发与兽形逐渐崩解为大量细灰，灰烬随风飘散；少量陶土色灵光从余烬回流，画面突出把生物烧成灰，无血腥细节、无石质傀儡。

### 震岳诀

- 游戏资源：`assets/cards/generated/earth_quake_summons.webp`
- 场景提示词：山巅石台震动，一道厚重陶土色震荡波横扫数个兽形灵物，岩石裂开、碎石悬浮，无人类角色。

通用提示词：`Use case: stylized-concept. Landscape 4:3 pure card illustration. High quality dark eastern fantasy digital painting, painterly detailed textures, strong readable focal subject, restrained cinematic lighting, circular stone arena suspended among mountains. Landscape 4:3, focal details inside central 80%, clean crop edges. No text, letters, numerals, logos, card border, UI or watermark. One complete illustration only.`

焚烬修改提示词：`Replace the rigid stone humanoid golem with a clearly living wolf-like spirit beast, recognizable organic fur, mane, paws and fierce silhouette. It is being completely incinerated by a single concentrated orange-red flame. Show its silhouette progressively disintegrating into fine pale and charcoal ash, abundant gray ash blowing away in the wind and a small blackened ash pile below. Flames and flying ash dominate, no gore, blood, bones or exposed tissue. Keep the dark eastern fantasy digital painting style, suspended mountain stone arena atmosphere, readable composition and 4:3 landscape ratio. A faint earthy amber current rises from the ashes. No text, numerals, logos, card border or UI.`

## 验证

新增规则及PC／触屏交互检查已注册到cards、ui-cards组，日常quick不增加；按测试规范运行相关项。本轮所选17项最终通过：新增规则、PC／触屏拖牌与三级卡面、五尺寸全卡面布局、已有卡牌与伤害结算、召唤、升级界面、无尽交易与规则版本5迁移、全部75张卡图。新增规则57项断言，新增PC／触屏各42项断言；另10项Python测试工作流检查通过。全部Godot检查静音，未执行full，也未导出新APK。

验证记录保存在`work/ash_cleanse_20261002/`：`rules_initial.json`、`ui_final.json`、`related_checks.json`、`remaining_checks.json`。相关检查在升级界面截图等待超时后停止，日志保留；修复主动绘制后，只继续失败项和尚未执行的三项，不重复已通过的十项。
