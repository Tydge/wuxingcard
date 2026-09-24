# 五行 · 命盘 — 可玩原型

Godot 4.6 的单机 PVE 五行卡牌战斗原型。三份 v0.3 原始设计文档保存在 `docs/`。

## 开始游戏

双击 `运行游戏.command`，或在 Godot 中导入本目录的 `project.godot` 并运行项目。首次运行会导入 WebP 图片，可能需要几秒钟。使用 1600×900 的设计视口，窗口可调整大小。

在主菜单选择一个敌人和一套牌组，点击“进入战斗”。鼠标悬停手牌可放大查看效果；按住并往上拖到战场任意位置（手牌上方）松开即可打出。松开在手牌区域会取消出牌。点击“结束回合”让敌人行动。胜负后可重开或返回选择。

战斗采用横版对峙格局：我方立绘在左、敌方立绘在右，两者面对面。我方血条、状态和五行能量在左下角，敌方对应的 HUD 中心对称地放在右上角；两侧数值面板共用同一套排版，只有内部顺序左右镜像。能量是五个圆形灵石，敌我双方都按「金木水火土」从左到右排列。

## 已实现

- 五行能量同时作为费用、同系抗性和被克制属性的弱点，0–10 上限并跨回合保留。
- 每回合先按实时抽牌堆属性比例生成自然能量，再抽 1 张；能量已满或封锁的属性从随机池排除。
- 初始 4 张手牌、上限 8 张，弃牌不洗回，递增无属性疲劳。
- 敌我共用能量、抽牌、出牌、伤害和状态逻辑；敌方手牌显示牌背，不公开内容。
- 30 种数据定义卡牌、3 种敌人、3 套玩家牌组。效果通过 `effects` 顺序结算，包括伤害、治疗、抽牌、获得/削减/转换能量、随机弃牌及状态。
- 状态：灼烧、护盾、易伤、再生、元素封锁。敌人根据伤害、恢复、资源和状态评估手牌并连续出牌。
- 横版对战界面：左我方 / 右敌方立绘面对面，我方 HUD 在左下、敌方 HUD 在右上，圆形五行能量、扇形手牌、悬停放大、拖拽出牌、从牌堆飞入手牌的抽牌动画、敌方卡牌从牌背飞入场中的展示，以及胜负和重开。战斗日志保存在逻辑层，当前战斗画面不显示。
- 布局以画面中心点对称：我方手牌（底部偏右）对应敌方卡背（顶部偏左），我方抽牌堆（右下角）对应敌方抽牌堆（左上角）。
- 五行共用的参数化战斗特效：出牌轨迹、命中法阵、护盾、治疗、能量增减、状态与伤害数字。出牌轨迹按卡牌的实际目标决定落点——打向对手的牌从我方立绘飞向敌方立绘，只增益自己的牌落回自己立绘上。抽牌与弃牌不画额外符号，只由卡牌预制体本身的飞牌与手牌变化表现。动态形状由 Godot 绘制，命中法阵复用一张 AI 生成的透明纹理。

## 原型状态数值

原始文档没有给出具体状态数值，首版暂定：灼烧每层在持有者回合结束失去 2 生命；再生每层在回合开始恢复 3 生命；易伤每层令元素伤害增加 25%；护盾先吸收元素伤害；封锁阻止该元素的自然/卡牌能量获取和出牌。疲劳与灼烧直接扣生命。状态在持有者回合结束减少 1 回合持续时间。这些值可在 `data/cards.json` 和 `battle/battle_manager.gd` 调整。

## 数据与美术

卡牌、牌组和敌人在 `data/cards.json`、`data/battles.json`。卡牌插画使用 `assets/cards/generated/{card_id}.webp`；未生成时自动使用 `assets/cards/elements/{element}.webp`。角色和背景也按 ID 从 `assets/` 自动读取。界面、卡框、文字与数值由 Godot 绘制。

卡牌定义与外观分开：`data/cards.json` 定义费用、属性、效果等规则，玩家和敌人的手牌保存卡牌 ID；`ui/card_view.tscn` 是共用的卡牌预制场景，手牌、悬停放大、拖拽、出牌展示、牌背和牌堆都实例化它。所有正面卡牌始终显示相同的费用、属性、插画、名称与完整效果文字，只做等比例缩放。卡牌外框固定为 **5:7**；插画窗口固定为 **4:3 横向**，建议生成 **1024×768** 图片。早期 2:3 竖版五行占位图会在插画窗口内居中裁切；后续生成的独立卡图按新的 4:3 规格制作。

本版使用 AI 生成的 1 张背景、4 张角色立绘、5 张五行通用插画和 1 张透明法阵纹理。每张卡的独立插画尚未生成；数据里已有 `art_prompt`。运行 `python3 tools/art_pipeline.py manifest` 可从游戏数据生成全部 36 个资源任务；生成图片后用 `python3 tools/art_pipeline.py ingest card fire_edge 图片路径` 进行尺寸、构图比例检查、WebP 转换和按 ID 入库。角色、背景、特效纹理可将 `card` 分别换成 `character`、`background`、`fx`。图片内容仍需视觉审查；当前脚本不包含自动调用图像模型或视觉模型的步骤。

横版对峙需要每个角色都有一张战场立绘。立绘由 1024×1536 的透明角色原图按 alpha 边界裁切后缩放到 **320×480**（2:3）生成，存为 `assets/characters/{id}_standee.webp`；对战里以 300×450 显示。执行 `Godot --headless --path . --script res://tools/make_standees.gd` 可为 `data/characters.json` 里所有缺少立绘的角色补齐（加 `-- --force` 可全部重建），之后用 `Godot --headless --path . --import` 让 Godot 导入新图片。

动态特效集中在 `ui/battle_fx.gd`。新增卡牌会按主属性和第一个效果自动选择特效；也可在卡牌 JSON 中填写可选字段 `fx_id`、`fx_scale`、`fx_speed`、`fx_intensity` 调整表现，无须为每张牌单独写脚本。特效的起止点由 `battle_ui.gd` 里的 `PLAYER_ANCHOR` / `ENEMY_ANCHOR` 给出，`cast()` 根据卡牌 `effects` 的 `target` 判断该飞向对方立绘还是落回自己立绘。使用本机 Godot 执行 `--path . --script res://tools/capture_fx.gd` 可自动截取五行轨迹、命中和状态反馈到 `work/fx_previews/`，执行 `--path . --script res://tools/capture_layout.gd` 可把横版布局、双方 HUD、圆形能量和双向特效截到 `work/layout_previews/`，供视觉检查。

## 测试

```sh
/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/smoke_test.gd
```

测试覆盖伤害公式、护盾预览、递增疲劳，并以固定种子完整运行 90 场战斗。游戏 UI 也通过本机 Godot 实际启动、选牌、拖拽出牌和结束回合检查：

```sh
/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot --path . --script res://tools/test_drag.gd
/Users/wangtaizhi/Desktop/Godot.app/Contents/MacOS/Godot --path . --script res://tools/capture_interaction.gd
```

## 美术提示词

通过内置 imagegen 生成资源，统一提示词主题为“暗色东方幻想、悬浮群山中的五行石台、无 UI/文字”。具体卡牌、角色和场景提示词在 `data/cards.json`、`data/characters.json`、`data/areas.json`，`tools/art_pipeline.py manifest` 会拼接同一风格要求。角色请求透明背景，卡牌插画只包含纯画面。
