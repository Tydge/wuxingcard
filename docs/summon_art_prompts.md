# 召唤物美术

使用内置 `imagegen` 生成。每种召唤物先生成透明背景的场上立绘，再把该立绘作为参考图，生成同一物体的 **4:3 横向**手牌插画。下表的英文描述与通用提示词组合使用；生成图已转换为 WebP 并放入项目。

| 召唤物 | 透明立绘主体 | 手牌插画背景 |
| --- | --- | --- |
| 金灵炉 `metal_furnace` | Hovering ancient bronze alchemical furnace; engraved gold patterns, sapphire water-energy core, blue vapor and tassels. | Storm-lit ancient Chinese stone terrace above clouds; water energy flowing from the furnace. |
| 青藤苗 `wood_seedling` | Enchanted seedling with twisted wood trunk, emerald vines and leaves, orange fire sparks glowing in the leaf veins. | Mossy ruined terrace in a dark mountain forest; warm sparks among the leaves. |
| 玄水泉 `water_spring` | Floating ancient stone spring basin with swirling blue water; new emerald branches grow from the water. | Misty moonlit mountain courtyard, wet stone and reflected water. |
| 赤焰灯 `fire_lantern` | Floating ornate red bronze lantern with an undying orange-red spirit flame; small earthen fragments below. | Dusk mountain temple terrace lit by the lantern. |
| 坤土碑 `earth_stele` | Upright carved earth stele, glowing gold geometric runes and metallic crystal veins. | Windswept cliffside ruin under golden twilight, with crystals around the stele. |

透明立绘提示词模板：

> Use case: stylized-concept. Asset type: transparent-background full-body game summon standee for a dark Eastern fantasy five-element card battler. Subject: **[名称与表中主体描述]**. Centered full-object front three-quarter view, clear silhouette readable at small battlefield size. Refined painterly Chinese xianxia fantasy concept art. Genuine transparent alpha background; no scenery, ground, pedestal, cast shadow, card frame, text, or watermark.

手牌插画提示词模板（附上对应透明立绘作为参考图）：

> Use case: stylized-concept. Asset type: 4:3 landscape card illustration for a dark Eastern fantasy five-element card battler. The input image is the exact summon reference; preserve its object identity, distinctive shape, materials, details and colors. Subject: **[名称与表中主体描述]**. Scene: **[表中手牌插画背景]**. Refined painterly Chinese xianxia fantasy art, cinematic but readable at small card size. Subject contained in the central 70% with surrounding environment. No card border, UI, text, number, or watermark.

## 第二组五行召唤物

继续使用内置 `imagegen`，每张卡先生成透明场上立绘，再以该立绘为参考生成 4:3 手牌插画。提示词沿用上面的两套模板，主体与场景替换如下：

| 召唤物 | 透明立绘主体 | 手牌插画背景 |
| --- | --- | --- |
| 玄金铃 `metal_chime` | A floating dark bronze ritual bell with sword and cloud engravings, gilt trim, golden protective sound waves. | Misty ancient mountain shrine, protective rings across stone steps. |
| 春藤鹿 `wood_deer` | A deer woven from twisted wood and emerald vines, leaf antlers, pale blossoms, soft healing chest glow. | Rain-fresh forest glade at dawn, green light restoring wilted grass. |
| 听雨螺 `water_conch` | A floating azure conch with water-current carvings, pearl core, rain and mist ribbons. | Moonlit ancient stone terrace in rain, abstract reflected paths. |
| 离火鸦 `fire_raven` | A three-legged black-red spirit raven with ember-lined wings and flowing fire tail. | Twilight mountain battlefield, sparks trailing toward a distant stone platform. |
| 镇山龟 `earth_tortoise` | A weathered stone tortoise carrying a miniature mountain, restrained gold earth runes. | Windswept mountain pass with cracked pillars and grasses bent by quiet earth pressure. |

所有场上立绘要求完整主体、真实透明 alpha、清晰轮廓；卡面要求主体位于中央约 70%，保留周围环境；两类图片都不得包含卡框、UI、文字、数字或水印。

立绘路径：`assets/summons/standee/{summon_id}.webp`。手牌插画路径：`assets/cards/generated/{summon_id}_card.webp`。可运行 `Godot --headless --path . --script res://tools/test_summon_art.gd` 检查透明角落和 4:3 比例。
