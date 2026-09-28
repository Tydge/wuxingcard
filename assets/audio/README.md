# 音频素材与接入

## 音乐

七首 BGM 由项目作者提供，保留原始 MP3 编码，避免重复有损转码。当前战斗曲目为 `Dangerous Duel`、`Whisper of the Dragon (3)`；`Whisper of the Dragon (2)` 暂不播放。非战斗曲目为 `Whispers of Silk`、`Ethereal Veil`、`Whisper of the Dragon`、`Whisper of the Dragon (1)`。`audio/audio_director.gd` 按这两个曲目池随机轮播，池内一轮播完才重新洗牌；进入和离开战斗时交叉淡入淡出。

| 游戏资源 | 原文件 |
| --- | --- |
| `music/battle_dangerous_duel.mp3` | `Dangerous Duel.mp3` |
| `music/battle_whisper_dragon_2.mp3` | `Whisper of the Dragon (2).mp3` |
| `music/battle_whisper_dragon_3.mp3` | `Whisper of the Dragon (3).mp3` |
| `music/menu_whispers_of_silk.mp3` | `Whispers of Silk.mp3` |
| `music/menu_ethereal_veil.mp3` | `Ethereal Veil.mp3` |
| `music/menu_whisper_dragon.mp3` | `Whisper of the Dragon.mp3` |
| `music/menu_whisper_dragon_1.mp3` | `Whisper of the Dragon (1).mp3` |

## 音效

卡牌、菜单、命中等短音效选自 Kenney 的以下 CC0 音频包，并保留各包原始许可文件于 `licenses/`。只取运行时实际使用的片段，不将下载包整体打入游戏。

- [Casino Audio](https://kenney.nl/assets/casino-audio)：抽牌、查看、出牌、弃牌、获得灵气。
- [RPG Audio](https://kenney.nl/assets/rpg-audio)：翻页、施法掠过、召唤登场。
- [Interface Sounds](https://kenney.nl/assets/interface-sounds)：选择、确认、返回、状态和治疗。
- [Impact Sounds](https://kenney.nl/assets/impact-sounds)：五行命中、护盾、召唤物消散。

`element_*.wav` 是由 `tools/generate_audio_accents.py` 合成的原创五行短层，和对应实录命中声叠加。UI、战斗音效与 BGM 分属不同总线，可在游戏里分别调节音量；频繁动作有最短间隔，多段命中按伤害数字节奏播放。

新增音效时，应挂在实际动作或战斗事件上，避免挂在 `_refresh()` 等界面重建路径上。音乐授权由提供这些文件的项目作者管理；若以后公开发行，应保留能证明其发行用途的来源记录。
