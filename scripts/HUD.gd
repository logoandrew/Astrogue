extends CanvasLayer

@onready var health_bar = $HealthBar
@onready var health_label = $HealthLabel
@onready var message_log = $MessageLog
@onready var crystal_count_label = $InventoryPanel/VBoxContainer/CrystalCountLabel
@onready var glow_equip_btn = $InventoryPanel/VBoxContainer/GlowEquipButton
@onready var melee_equip_btn = $InventoryPanel/VBoxContainer/MeleeEquipButton

signal quit_to_menu_requested
signal high_score_submitted(player_tag)
signal inventory_updated


var message_history = []

var equipped_stylebox = StyleBoxFlat.new()
var default_stylebox
var equipped_stylebox_hover = StyleBoxFlat.new()
var default_stylebox_hover

const BTN_ADD_TEXT = "Add"
const BTN_EQUIPPED_TEXT = "Equipped"
const BTN_REMOVE_TEXT = "Remove"



func _ready():
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.score_changed.connect(_on_score_changed)
	_on_hp_changed(GameState.player_hp, GameState.max_player_hp)
	
	var healthbar_fill_style = StyleBoxFlat.new()
	healthbar_fill_style.bg_color = DesignSystem.COLOR_SUCCESS
	health_bar.add_theme_stylebox_override("fill", healthbar_fill_style)
	
	equipped_stylebox.bg_color = DesignSystem.COLOR_SUCCESS
	equipped_stylebox.set_corner_radius_all(DesignSystem.SIZE_2XS)
	default_stylebox = glow_equip_btn.get_theme_stylebox("normal")
	equipped_stylebox_hover.bg_color = DesignSystem.COLOR_DANGER
	equipped_stylebox_hover.set_corner_radius_all(DesignSystem.SIZE_2XS)
	default_stylebox_hover = glow_equip_btn.get_theme_stylebox("hover")
	
	GameState.connect("inventory_changed", _on_inventory_changed)
	glow_equip_btn.connect("pressed", _on_glow_equip_pressed)
	melee_equip_btn.connect("pressed", _on_melee_equip_pressed)
	_on_inventory_changed()
	
	glow_equip_btn.mouse_entered.connect(_on_glow_equip_mouse_entered)
	glow_equip_btn.mouse_exited.connect(_on_glow_equip_mouse_exited)
	melee_equip_btn.mouse_entered.connect(_on_melee_equip_mouse_entered)
	melee_equip_btn.mouse_exited.connect(_on_melee_equip_mouse_exited)
	

func _process(delta):
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().paused = not get_tree().paused
		$QuitDialogue.visible = get_tree().paused


func _on_hp_changed(current_hp, max_hp):
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	_update_health_label()


func _on_score_changed(new_score):
	_update_health_label()


func _update_health_label():
	var top_score = 0
	if not GameState.high_scores.is_empty():
		top_score = GameState.high_scores[0]["score"]
	health_label.text = "HP: " + str(GameState.player_hp) + " / " + str(GameState.max_player_hp) + "  |  Score: " + str(GameState.score) + "  |  High Score: " + str(top_score) + "  |  Level: " + str(GameState.level)


func log_message(message, color = DesignSystem.COLOR_TEXT_PRIMARY):
	message_history.append({ "text": message, "color": color })
	if message_history.size() > 10:
		message_history.pop_front()
	message_log.clear()
	for i in range(message_history.size()):
		var msg_data = message_history[i]
		var text = msg_data["text"]
		var text_color = msg_data["color"]
		if i < message_history.size() - 1:
			text_color.a = 0.5
		message_log.bbcode_enabled = true
		message_log.scroll_following = true
		message_log.append_text("[color=" + text_color.to_html(true) + "]" + text + "[/color]\n")


func _on_submit_hs_pressed() -> void:
	var line_edit = $EnterHighScorePanel/VBoxContainer/LineEdit
	var player_tag = line_edit.text.to_upper()
	high_score_submitted.emit(player_tag)
	$EnterHighScorePanel.hide()


func _on_yes_quit_pressed() -> void:
	quit_to_menu_requested.emit()


func _on_no_quit_pressed() -> void:
	get_tree().paused = false
	$QuitDialogue.hide()


func _on_ok_pressed() -> void:
	$ExaminePanel.hide()


func _on_inventory_changed():
	crystal_count_label.text = "Available\nCrystals:\n" + str(GameState.crystal_inventory.size())
	
	if GameState.glow_slot:
		glow_equip_btn.text = str(BTN_EQUIPPED_TEXT)
		glow_equip_btn.add_theme_stylebox_override("normal", equipped_stylebox)
		glow_equip_btn.add_theme_stylebox_override("hover", equipped_stylebox_hover)
	else:
		glow_equip_btn.text = str(BTN_ADD_TEXT)
		glow_equip_btn.add_theme_stylebox_override("normal", default_stylebox)
		glow_equip_btn.add_theme_stylebox_override("hover", default_stylebox_hover)
	
	if GameState.melee_slot:
		melee_equip_btn.text = str(BTN_EQUIPPED_TEXT)
		melee_equip_btn.add_theme_stylebox_override("normal", equipped_stylebox)
		#melee_equip_btn.add_theme_stylebox_override("hover", equipped_stylebox_hover)
	else:
		melee_equip_btn.text = str(BTN_ADD_TEXT)
		melee_equip_btn.add_theme_stylebox_override("normal", default_stylebox)
		melee_equip_btn.add_theme_stylebox_override("hover", default_stylebox_hover)


func _on_glow_equip_pressed():
	if GameState.glow_slot: # Remove
		GameState.glow_slot = false
		GameState.crystal_inventory.push_front(GameState.light_durability)
		GameState.light_durability = 0
	elif not GameState.crystal_inventory.is_empty(): # Add
		GameState.glow_slot = true
		GameState.light_durability = GameState.crystal_inventory.pop_front()
		log_message("You add a crystal to your GLOW unit.")
	elif not GameState.glow_slot and GameState.crystal_inventory.is_empty():
		log_message("No crystal to add.")
	GameState.emit_signal("inventory_changed")


func _on_melee_equip_pressed():
	if GameState.melee_slot: # Remove
		log_message("Crystal cannot be removed from melee unit.")
	if not GameState.crystal_inventory.is_empty(): # Add
		GameState.melee_slot = true
		GameState.crystal_inventory.pop_front()
		GameState.melee_slot_uses = GameState.MAX_MELEE_SLOT_USES
		log_message("You jam a crystal into your melee unit.")
	elif not GameState.melee_slot and GameState.crystal_inventory.is_empty():
		log_message("No crystal to add.")
	GameState.emit_signal("inventory_changed")


func _on_glow_equip_mouse_entered():
	if GameState.glow_slot:
		glow_equip_btn.text = str(BTN_REMOVE_TEXT)


func _on_glow_equip_mouse_exited():
	if GameState.glow_slot:
		glow_equip_btn.text = str(BTN_EQUIPPED_TEXT)


func _on_melee_equip_mouse_entered():
	pass
#	if GameState.melee_slot:
#		melee_equip_btn.text = str(BTN_REMOVE_TEXT)


func _on_melee_equip_mouse_exited():
	pass
#	if GameState.melee_slot:
#		melee_equip_btn.text = str(BTN_EQUIPPED_TEXT)
