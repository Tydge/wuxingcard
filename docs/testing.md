# 测试规范

日常开发按实际影响选择最小必要检查。完整回归用于正式导出、大范围战斗或平台交互重构，以及有明确证据需要扩大验证的情况；普通提交与推送不以全套测试作为前置条件。用户明确要求停止或暂不测试时，停止执行并如实说明尚未验证的部分。

## 选择范围

| 改动 | 推荐检查 | 不需要默认执行的内容 |
| --- | --- | --- |
| README、设计文档、注释 | 对照内容、链接和差异；通常不启动Godot | 战斗模拟、所有界面流程 |
| 卡牌费用、数值、等级、效果 | `--group cards`；涉及攻防或结算追加`--group damage` | 商店、构筑拖拽、全资源检查 |
| 法宝触发、耐久、冷却 | `--group artifacts`；显示调整追加`--group ui-artifacts` | 完整无尽或构筑流程 |
| 伤害、状态、预览、AI结算 | `--group core`；按影响追加cards、artifacts、summons | 无关界面检查 |
| 召唤规则、时序 | `--group summons`；涉及攻防追加damage | 全部卡牌界面 |
| 卡组限制、保存、迁移 | `--group decks`；交互调整追加`--group ui-decks` | 批量对战、无尽商店 |
| 无尽经济、奖励、恢复 | `--group endless`；交互调整追加`--group ui-endless` | 全部藏经阁、战斗输入流程 |
| 效果文案、关键词显示 | 对照实际效果；需要检查显示时用`--group ui-cards`或单个关键词测试 | 批量随机对战 |
| 真气、状态说明、长按操作 | `--group ui-energy`；规则变化追加core | 全部构筑流程 |
| 开局与抽牌动画 | `--group ui-opening`；时序变化追加core | 无尽商店 |
| 首次指引、高亮遮罩、教学进度 | `--group onboarding`；按实际改动追加开局或无尽相关项 | 无关卡牌结算、全部资源检查 |
| 手牌拖拽、目标选择、通用触屏输入 | `--group ui-hand`，或仅受影响的`--test` | 全部资源检查 |
| 美术替换、资源路径、图片导入 | `--suite assets`和受影响界面 | 批量对战 |
| 正式导出Windows或Android包 | `--suite full`或复用有效完整记录，另做导出包验证 | 同一份代码为两个平台重复跑全套 |

表格是选择依据，不是要求每次都执行所有相邻组。共享模块发生变化时，根据其实际调用范围扩大检查；单一位置或文字调整优先执行单个相关测试。PC与触屏共用输入代码发生变化时，应验证两种输入分支。

## 执行入口

所有测试与开发预览默认静音，包括音乐、战斗音效、界面音效。`check_project.py`默认使用Godot的`Dummy`音频驱动，并将`WUXING_TEST_AUDIO=0`传给测试进程；直接运行已命名的测试脚本也会关闭音频服务和Master总线。静音只作用于当前进程，不改写玩家保存的音量设置。

只有专门检查声音时才用`--enable-audio`，让图形测试开启真实音频。直接启动游戏做静音预览时加`--audio-driver Dummy -- --mute-audio`；专门试听时用`-- --test-audio`且不使用Dummy驱动。headless规则测试始终不播放声音。`audio_policy_test`验证静音策略，不用于试听，不应搭配`--enable-audio`。

```sh
# 默认4项规则检查，不打开图形窗口
python3 tools/check_project.py

# 先查看范围：不会导入资源或启动Godot
python3 tools/check_project.py --group cards --group damage --list

# 组合相关组，重复项只执行一次
python3 tools/check_project.py --group cards --group damage

# 仅检查当前法宝UI层级
python3 tools/check_project.py --test artifact_ui_test

# 仅检查当前关键词显示
python3 tools/check_project.py --test test_card_keywords

# 检查图形测试的默认静音，不播放声音
python3 tools/check_project.py --test audio_policy_test

# 全部规则 / 全部界面 / 美术资源
python3 tools/check_project.py --suite rules
python3 tools/check_project.py --suite ui
python3 tools/check_project.py --suite assets

# 正式完整回归；需要一次收集全部失败时显式追加 --keep-going
python3 tools/check_project.py --suite full
python3 tools/check_project.py --suite full --keep-going
```

`--suite`、`--group`、`--test`是互斥的三种选择方式。group和test各自可以重复。可用完整`res://`路径或注册的测试名指定`--test`。旧的单次排查脚本未注册时，不会被顺带执行。

默认quick包含`flat_damage_test`、`settlement_regression_test`、`qi_cycle_test`、`opening_flow_test`。完整清单统一维护在`tools/test_catalog.py`，通过`--suite full --list`查看。新手指引另有一项规则检查和PC／触屏各一项交互检查，属于`onboarding`组，未加入默认quick。新手检查使用独立教学进度存档；其他命名测试默认关闭指引，避免阻挡其既有操作。

在非full范围内，批量模拟使用明确的`--quick`参数：

| 脚本 | 日常样本 | 完整回归样本 |
| --- | --- | --- |
| smoke_test | 9场预设战斗 | 90场预设战斗 |
| card_expansion_test | 24份随机牌组、2场战斗 | 800份随机牌组、30场战斗，以及完整卡池随机覆盖检查 |
| upgrade_test | 2场升级战斗，保留精/玄两个等级 | 12场升级战斗 |

规则边界断言保持原样；quick只减少上述随机样本，并不标记为完整检查。直接运行这些Godot脚本而不提供`--quick`仍执行原来的完整样本。默认quick的4项检查不包含这3个批量脚本。

## 日志、失败与重跑

报告默认分别保存在`work/checks/quick/latest.json`、`work/checks/targeted/latest.json`、`work/checks/full/latest.json`等目录，避免局部记录覆盖发布用完整记录；`--output`可以另存。报告记录实际执行项、参数、耗时、退出码、源码指纹和是否完成。

- 默认遇到第一项失败立即停止，保留报告及日志；未执行项不算通过。需要全面排查时使用`--keep-going`。
- 先判断断言失败、脚本异常、超时或渲染环境问题，再处理对应项。只有代码变化、失败或未解决疑点才需要重跑或扩大范围。
- 修复后先重跑失败项及受影响范围。用于正式导出的完整记录必须来自修复后的同一运行代码及测试版本，不能将旧结果拼接成“全套通过”。
- 不自动增加超时时间或反复重试。非full规则项默认45秒、图形项60秒；full每项120秒。可根据明确原因使用`--timeout 秒数`；耗时上限不是性能通过标准。
- GUI检查优先等待状态/动画完成，并为等待设置上限；固定截图等待、鼠标坐标和首个失败导致的后续连锁断言需要逐步改善。
- 结果应明确写为“所选N项通过”，不能把局部通过描述为“全部测试通过”。未运行的范围、已知失败按实际情况报告。

## 完整记录与导出

构建脚本只接受schema 2、full范围、当前注册清单齐全且全部通过的记录，校验测试身份、运行参数、运行代码与测试指纹及Godot版本。quick、targeted、未完成或失败的记录不能用于正式导出。

不指定`--checks-report`时，构建自动尝试复用`work/checks/full/latest.json`；有效则直接导出，失效或不存在才执行full。手动指定不合格记录时直接报错，不悄悄启动全套。

构建仍保存包含文档、授权等文件的完整`source_manifest.json`。另用`check_sha256`校验运行内容与检查工具：只修改说明文档不会使完整测试记录失效，游戏数据、代码、资源、测试、导出配置或引擎改变则会失效。旧schema报告需重新做一次完整回归后才能复用。

## 旧脚本与已知未通过项

`tools/test_card_expansion_ui.gd`按旧焚阵3费、仅敌方群攻编写，已标记LEGACY，不属于注册清单，也不作为推荐检查命令。旧演示、截图、启动排查脚本保留为参考；使用前需核对现行规则，不能因文件名包含test就全部执行。

2026-10-01既有重试记录保存在`work/balance_20261001/`。2026-10-02导出检查已核对现行行为：`test_deck_workshop`更新木系原版牌池数量断言，`test_summon_drag`改为检查当前RichTextLabel描述；两项与`endless_ui_test`截图改为主动绘制，避免macOS窗口遮挡时等待渲染信号停滞。无尽升级预览及构筑移牌保留原有有效断言，相关PC／触屏检查已通过，未删除检查项。

Android原生触屏发现取消召唤目标时隐藏控件会重入取消函数。释放控件前先解除共享引用；`high_cost_ui_test`及继承的触屏检查通过隐藏信号重入复现并验证此边界。原生模拟器回归与正式APK安装验证另存发布交付目录，不替代full记录。

## 新增测试

新增检查应覆盖明确的规则边界、存档风险或已发生的交互问题。先归入对应组，决定是否需要图形渲染与触屏；不要默认加入quick。低风险文案、间距与静态数值调整不为每条实现新增同构测试。发现重复检查时合并共同断言，但保留不同的结算边界与真实输入分支。

2026-10-02新增五张法术：`ash_cleanse_cards_test`覆盖按层数清理、击杀回能、双方召唤物群伤及AI副本；`ash_cleanse_ui_test`／`ash_cleanse_touch_test`覆盖真实拖牌、取消、目标预览及三级卡面。分别归入cards、ui-cards，不增加默认quick。`upgrade_ui_test`截图改为主动绘制，避免窗口被遮挡时无限等待`frame_post_draw`，保留原有升级与构筑断言。

2026-10-03新增`hand_scaling_cards_test`及PC／触屏`hand_scaling_ui_test`、`hand_scaling_touch_test`，覆盖打出后手牌计数、中毒转灼伤取整及仓库升级卡图。`endless_ui_test`增加实际付费升级后细条卡图断言。其余三处历史截图等待改为主动绘制，保留原有断言，避免相同的macOS遮挡停滞。

2026-10-03新增`discovery_cards_test`与PC／触屏`discovery_ui_test`、`discovery_touch_test`，分别归入cards及ui-cards，不增加默认quick。规则检查覆盖候选范围组合筛选、无重复抽样、牌堆与疲劳独立、满手牌、效果继续、固定种子重放、AI隔离、真气抑制光环和能量倍率伤害；界面覆盖真实2／3／4选一与确认、原生触摸释放、观想兼容、三级卡面、伤害预览及召唤落点。本轮仅运行上述3项以及qi_cycle_test、upgrade_test --quick、endless_recovery_test，六项分别通过；不构成完整回归，不导出APK或Windows包。

### 用户明确指定较小导出范围

2026-10-04本轮用户明确要求：导出也只测新增内容与可能冲突，不跑不相关的完整回归。Android构建新增可重复的`--required-test`，必须同时传入`--checks-report`。报告仍须schema 2、targeted范围、所列测试身份与参数完全一致、全部通过、运行代码与测试指纹一致、Godot版本一致及测试期间源码未改变；不会自动回退full或将局部记录标成full。未显式选择该例外时继续执行既有full发布门槛。资源包探针保留资源、字体、授权检查，把重复随机对战样本缩为2场。

本轮所选7项已通过：wuxing_spirits_cards_test（120项断言）、PC／触屏wuxing_spirits_ui_test（各88项）、discovery_cards_test（109项）、settlement_regression_test、upgrade_test --quick及endless_recovery_test。Python发布工作流11项通过。未运行full，报告位于`work/checks/wuxing_spirits_release/latest.json`。

2026-10-04后续立绘／发现等级／关键词修正只运行4项：discovery_cards_test（115项断言）、wuxing_spirits_cards_test（120项）、endless_recovery_test、test_card_keywords，分别通过。规则与侧栏报告分别保存在`work/checks/identity_rules/latest.json`和`work/checks/identity_keywords/latest.json`。六张透明立绘逐张与原图人工对照，转换后RGBA逐像素一致；游戏内卡图／立绘组合预览另存`work/identity_fix/runtime_comparison.png`。未跑full，未导出安装包；朝向配置的最终静态修改由组合预览核对，不重复未受影响的规则检查。
