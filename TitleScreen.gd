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
	var score_text = ""
	
	if GameState.high_scores.is_empty():
		score_text = "No scores yet!"
	else:
		var max_score_length = 0
		for entry in GameState.high_scores:
			var score_len = str(entry["score"]).length()
			if score_len > max_score_length:
				max_score_length = score_len
		for i in range(GameState.high_scores.size()):
			var entry = GameState.high_scores[i]
			var rank = i + 1
			var tag = entry["tag"]
			var score_str = str(entry["score"])
			while score_str.length() < max_score_length:
				score_str = " " + score_str
			score_text += str(rank).pad_zeros(2) + ". " + str(tag) + " - " + str(score_str) + "\n"
	
	score_list_label.bbcode_text = score_text
	
	$HighScoresPanel.show()
