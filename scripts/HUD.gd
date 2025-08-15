extends CanvasLayer

@onready var health_bar = $HealthBar
@onready var health_label = $HealthLabel
@onready var message_log = $MessageLog

signal quit_to_menu_requested
signal high_score_submitted(player_tag)


var message_history = []


func _ready():
	GameState.hp_changed.connect(_on_hp_changed)
	GameState.score_changed.connect(_on_score_changed)
	_on_hp_changed(GameState.player_hp, GameState.max_player_hp)


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


func log_message(message, color = Color.WHITE):
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
