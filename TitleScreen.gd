extends Control


func _on_start_game_pressed() -> void:
	get_tree().change_scene_to_file("res://Main.tscn")


func _on_instructions_pressed() -> void:
	$InstructionsPanel.show()


func _on_back_pressed() -> void:
	$InstructionsPanel.hide()
	$HighScoresPanel.hide()


func _on_high_score_list_pressed() -> void:
	var score_list_label = $HighScoresPanel/VBoxContainer/ScoreListLabel
	score_list_label.text = ""
	
	if GameState.high_scores.is_empty():
		score_list_label.text = "No scores yet!"
	else:
		for i in range(GameState.high_scores.size()):
			var entry = GameState.high_scores[i]
			var rank = i + 1
			var tag = entry["tag"]
			var score = entry["score"]
			score_list_label.text += str(rank) + ". " + str(tag) + " - " + str(score) + "\n"
	
	$HighScoresPanel.show()
