# 普通卡牌独立插画

本轮以 **内置 imagegen** 为保留下来的 20 张普通牌分别生成插画。所有卡牌均独立生成，使用 4:3 横向完整画面，按 ID 放入 `assets/cards/generated/`。召唤牌沿用之前独立生成的 10 套美术。

## 完整提示词模板

以下模板的 `{subject}` 使用后面列表的“画面内容”，每张牌对应一次独立生成调用。

```text
Use case: stylized-concept
Asset type: standalone painted spell illustration for a Chinese xianxia card game, horizontal 4:3 canvas (1536x1152), full bleed.
Subject and scene: {subject}
Style: richly detailed painterly Chinese immortal fantasy, realistic materials, strong clear focal action, atmospheric depth, teal shadows and element-colored glow, restrained cinematic lighting. Each card must have its own unmistakable scene. Composition readable at thumbnail size; keep key subject inside central 80% and leave crop-safe edges. This is a small, practical spell rather than a world-ending spectacle.
Constraints: only the illustration, no card frame, no interface, no words, no numbers, no logo, no watermark. Ancient Chinese clothing and architecture where present. No western armor, no modern objects. Use the described specific action rather than a generic swirling element background.
```

## 每张牌的画面内容与输出

### 锋芒（`metal_strike`）

- 画面内容：一柄近景银色飞剑划出凝练锐利的金白剑气，剑尖朝画面右上方，锋刃闪光；冷月、深蓝山崖为背景，简单初级剑术的力量感
- 输出：`assets/cards/generated/metal_strike.webp`

### 玄铁护身（`metal_ward`）

- 画面内容：玄铁碎片组成半透明的环形护盾，环绕一位背向镜头的古装行者；金属棱面与淡金灵光清晰可见，深蓝石台背景
- 输出：`assets/cards/generated/metal_ward.webp`

### 伐木诀（`metal_sever`）

- 画面内容：一道细长银金剑光截断粗壮的绿色树根，断口迸出木灵光与飞散木屑；古林近景，画面体现切断木属性灵气
- 输出：`assets/cards/generated/metal_sever.webp`

### 藤刺（`wood_strike`）

- 画面内容：一条带有锐利尖刺的翠绿藤蔓从石缝中迅速探出，长刺朝画面右上方突刺，飞散绿叶；古林石阶背景
- 输出：`assets/cards/generated/wood_strike.webp`

### 生息（`wood_heal`）

- 画面内容：一双古装行者的手托起翠绿灵叶，温暖白绿光沿衣袖和指尖流动，象征生命恢复与安宁；只展示完整健康的手和疗愈灵光的近景，安静柔和，无伤口
- 输出：`assets/cards/generated/wood_heal.webp`

### 回春（`wood_regen`）

- 画面内容：古装行者张开的掌心托着一截枯枝，枯枝长出新叶与小花，绿色灵气沿枝条循环流动；湿润山林虚化背景，持续再生感
- 输出：`assets/cards/generated/wood_regen.webp`

### 水刃（`water_strike`）

- 画面内容：一枚凝练的蓝色弯月水刃掠过浅水石台，刃缘透亮锋利，留下细小水珠与一道切开的水痕；月色溪谷背景，初级水术
- 输出：`assets/cards/generated/water_strike.webp`

### 断流（`water_drain`）

- 画面内容：一股清冷湛蓝水流冲入燃烧的石制法阵，赤红火焰被水流切断并熄灭，白色水汽升起；蓝水与余火形成对比
- 输出：`assets/cards/generated/water_drain.webp`

### 潮思（`water_thought`）

- 画面内容：静谧蓝色水面倒映星空与月光，两片无文字的古玉简从水中的倒影升起，涟漪连接两枚玉简；灵感与获取知识的感觉
- 输出：`assets/cards/generated/water_thought.webp`

### 寒雾（`water_mist`）

- 画面内容：冰蓝薄雾包围一位背向镜头的古装敌人，衣袖边缘结霜，透明护身屏障出现细小裂纹；冷色山谷，表现防御被削弱
- 输出：`assets/cards/generated/water_mist.webp`

### 赤焰诀（`fire_strike`）

- 画面内容：一团拳头大小的赤橙火焰被古装施法者的手掌向前击出，形成短促有力的火焰冲击，散开几颗亮火星；暗色石台近景，初级火术
- 输出：`assets/cards/generated/fire_strike.webp`

### 余烬印（`fire_brand`）

- 画面内容：一个赤红几何烙印在暗色古代铠甲胸前缓慢燃烧，余烬沿铠甲裂隙蔓延，细烟向上升起；近景，不出现可读文字
- 输出：`assets/cards/generated/fire_brand.webp`

### 聚火（`fire_gather`）

- 画面内容：古装施法者的双手从周围吸收零散火星，将其聚成掌心一团稳定的小火焰，暖光照亮衣袖；背景暗青色古殿
- 输出：`assets/cards/generated/fire_gather.webp`

### 碎岩（`earth_strike`）

- 画面内容：一小簇棕金色碎岩从地面崩起向前飞射，石片的断面和飞扬尘土清晰，近景石台留下浅裂缝；初级土术
- 输出：`assets/cards/generated/earth_strike.webp`

### 厚土壁（`earth_bastion`）

- 画面内容：厚实弧形岩壁从地面升起保护一位古装行者，层叠岩石与淡金土灵脉构成坚固屏障；远山石台背景，防守构图
- 输出：`assets/cards/generated/earth_bastion.webp`

### 震手（`earth_quake`）

- 画面内容：棕金色震荡波从开裂石地扩散，震开一位古装行者握着玉符的手，一枚无文字玉符正在脱手下落；衣袖与手部近景，清晰冲击感
- 输出：`assets/cards/generated/earth_quake.webp`

### 炼金（`metal_forge`）

- 画面内容：金色灵矿在小型石制熔炼坩埚上方熔化凝聚成金色灵气珠，周围悬浮细碎矿粒；暖金与暗青炉室，近景炼金过程
- 输出：`assets/cards/generated/metal_forge.webp`

### 萌发（`wood_sprout`）

- 画面内容：一株小小的明亮翠绿新芽从古石板裂隙中萌发，露珠映着晨光，嫩根吸收微弱绿色灵气；超近景，柔和山林背景
- 输出：`assets/cards/generated/wood_sprout.webp`

### 木生火（`wood_to_fire`）

- 画面内容：一截悬浮的翠绿灵木从左侧绿色生机逐渐转化成右侧橙红火焰，木纹、叶脉与飞散火星相接；深色石室背景，清晰相生转化
- 输出：`assets/cards/generated/wood_to_fire.webp`

### 封火令（`metal_lock`）

- 画面内容：悬浮的金属符令与细金锁链封住一团躁动的赤红火焰，圆形几何封印收紧火脉；背景为暗色古殿，令牌无可读文字
- 输出：`assets/cards/generated/metal_lock.webp`

