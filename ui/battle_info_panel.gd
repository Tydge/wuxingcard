class_name BattleInfoPanel
extends Control

signal closed
signal export_requested
const RULES := "五行能量\n每点能量使同系伤害抗性增加10%，使克制它的属性伤害抗性降低10%。金克木、木克土、土克水、水克火、火克金。各项增减相加，最终伤害不会小于0。\n打出卡牌会消耗对应能量，也会改变你的抗性。能量跨回合保留，每系上限10。悬停能量圆形查看贡献；手机可轻点查看。\n\n回合与抽牌\n每回合按开局完整卡组的五行比例随机获得1点自然能量，再抽1张牌；已满或封锁的属性不参加本次随机。初始4张手牌，先手首回合还会抽1张；法宝可能增加开局抽牌。手牌上限8，超出的牌直接弃掉。弃牌不洗回，牌堆耗尽后每次抽牌的疲劳失血递增。\n\n出牌与法宝\n伤害牌拖到敌方角色或召唤物，召唤牌拖到我方空槽，其余牌拖到手牌上方释放。手机按住查看，沿手牌滑动换牌，向上拖出施法。灵气不足仍可查看。法器在己方行动时发动，护身和灵佩自动触发；法器冷却N：使用后的第N个己方回合恢复；例如冷却3，随后两个己方回合不能用，第三个可用。\n\n状态与结算\n悬停状态图标或卡牌查看关键词，手机轻点状态查看。中毒随每次成功获得能量触发；出血随每次出牌触发，先消耗一层再处理法宝连锁。失去生命包括疲劳，致命失血不能被事后回血救回。召唤物同系抵抗50%，被克制时额外受伤50%。\n\n战斗记录\n点击记录查看本局事件和战斗种子。可导出战报，保留卡组、法宝及结算经过，方便反馈问题。"
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
