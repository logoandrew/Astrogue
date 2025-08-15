extends Node

# Sigmals to announce changes in game state
signal hp_changed(current_hp, max_hp)
signal score_changed(new_score)
signal light_changed(current_durability, max_durability)

# --- Game State Variables with Setters ---
var player_hp = 10:
	set(new_hp):
		player_hp = new_hp
		hp_changed.emit(player_hp, max_player_hp)
		
var max_player_hp = 10:
	set(new_max_hp):
		max_player_hp = new_max_hp
		hp_changed.emit(player_hp, max_player_hp)
		
var score = 0:
	set(new_score):
		score = new_score
		score_changed.emit(score)
		
var light_durability = 110:
	set(new_durability):
		light_durability = new_durability
		light_changed.emit(light_durability, max_light_durability)

# --- Other Game State Variables ---
var level = 1
var high_scores = []
var has_light_source = true
var max_light_durability = 210
var item_lore = {}

func _ready():
	load_high_scores()

func load_high_scores():
	var file = FileAccess.open("user://highscores.dat", FileAccess.READ)
	if file:
		high_scores = file.get_var()
		file.close()

func save_high_scores():
	var file = FileAccess.open("user://highscores.dat", FileAccess.WRITE)
	if file:
		file.store_var(high_scores)
		file.close()
