class_name BattleInfoPanel
extends Control

signal closed
signal export_requested
const RULES := "真气与五行灵气\n双方初始3点真气，五系灵气均为0；每个己方回合开始再获得1点真气，不再随机获得自然能量。轻点己方五行圆圈，将1点真气转成1点对应灵气。真气跨回合积攒，不提供抗性。灵气已满或被封锁时不能转化。\n每点灵气使同系伤害抗性增加10%，使克制它的属性伤害抗性降低10%。金克木、木克土、土克水、水克火、火克金。各项增减相加，最终伤害不会小于0。打出卡牌会消耗对应灵气，改变抗性。灵气跨回合保留，每系上限10。悬停圆圈查看贡献；手机按住查看，松开收起。\n\n回合与抽牌\n游戏开始随机决定先后手，双方各抽3张，后手再抽1张；按先手、后手结算开局效果与观想，再进入先手首回合，正常获得1点真气并抽1张。每个己方回合开始先结算护盾和召唤物，再获得真气、抽1张。手牌上限8，超出的牌进入弃牌堆。\n抽牌堆耗尽且需要抽牌时，洗回弃牌堆，并失去一次循环疲劳生命：5、10、20、40……每次翻倍。手牌不洗回；没有弃牌时无法抽牌，不额外触发循环。悬停抽牌堆，或手机按住抽牌堆，查看下次循环的疲劳。测试构筑15～30张，无尽初始恰好15张原版牌、80生命、无法宝。\n\n出牌与法宝\n伤害牌拖到敌方角色或召唤物，召唤牌拖到我方空槽，其余牌拖到手牌上方释放。手机按住查看卡牌，沿手牌滑动换牌，向上拖出施法。灵气不足仍可查看。法器在己方行动时发动，护身和灵佩自动触发；冷却N：使用后的第N个己方回合恢复。\n\n状态与结算\n悬停状态图标或卡牌查看关键词，手机按住状态图标查看，松开收起。积攒真气不触发中毒，成功转化灵气或卡牌获得灵气会触发中毒。出血随每次出牌触发。失去生命包括循环疲劳，致命失血不能被事后回血救回。召唤物同系抵抗50%，被克制时额外受伤50%。\n\n战斗记录\n点击记录查看本局事件和种子，可导出战报。"
var caption := ""
var description := ""
var can_export := false
var body: RichTextLabel
var message: Label

func configure(title: String, text: String, exportable: bool = false) -> void:
	caption = title
	description = text
	can_export = exportable

func _ready() -> void:
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.size = size
	shade.color = Color("#03101bdc")
	add_child(shade)
	var panel := Panel.new()
	panel.position = Vector2(350, 120)
	panel.size = Vector2(900, 660)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#09121ff5")
	style.border_color = Color("#dec596")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var heading := Label.new()
	heading.text = caption
	heading.position = Vector2(30, 20)
	heading.size = Vector2(740, 50)
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", Color("#dec596"))
	panel.add_child(heading)
	body = RichTextLabel.new()
	body.position = Vector2(30, 90)
	body.size = Vector2(840, 465)
	body.text = description
	body.add_theme_font_size_override("normal_font_size", 23 if PlatformUI.is_touch() else 21)
	body.add_theme_color_override("default_color", Color("#f5f1e9"))
	panel.add_child(body)
	var close := Button.new()
	close.text = "关闭"
	close.position = Vector2(690, 580)
	close.size = Vector2(180, 58)
	close.pressed.connect(dismiss)
	panel.add_child(close)
	if can_export:
		var export_button := Button.new()
		export_button.text = "导出战报"
		export_button.position = Vector2(30, 580)
		export_button.size = Vector2(180, 58)
		export_button.pressed.connect(func(): export_requested.emit())
		panel.add_child(export_button)
	message = Label.new()
	message.position = Vector2(230, 580)
	message.size = Vector2(445, 58)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.add_theme_font_size_override("font_size", 17)
	panel.add_child(message)

func dismiss() -> void:
	hide()
	closed.emit()
	queue_free()
