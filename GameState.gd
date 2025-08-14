extends Node

var player_hp = 10
var max_player_hp = 10
var score = 0
var level = 1
var high_scores = []
var has_light_source = true
var light_durability = 110
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
