extends Node

var player_hp = 10
var max_player_hp = 10
var score = 0
var level = 1
var high_score = 0
var has_light_source = true
var light_durability = 100
var max_light_durability = 300

func _ready():
	load_high_score()

func load_high_score():
	var file = FileAccess.open("user://highscore.dat", FileAccess.READ)
	if file:
		high_score = file.get_var()
		file.close()

func save_high_score():
	var file = FileAccess.open("user://highscore.dat", FileAccess.WRITE)
	if file:
		file.store_var(high_score)
		file.close()
