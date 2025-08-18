extends Node

# Sigmals to announce changes in game state
signal hp_changed(current_hp, max_hp)
signal score_changed(new_score)
signal light_changed(current_durability, max_durability)
signal inventory_changed

const DEFAULT_MAX_HP = 10
const DEFAULT_LIGHT_DURABILITY = 150
const DEFAULT_MAX_LIGHT_DURABILITY = 210
const MAX_MELEE_SLOT_USES = 7

# --- Game State Variables with Setters ---
var player_hp = DEFAULT_MAX_HP:
	set(new_hp):
		player_hp = new_hp
		hp_changed.emit(player_hp, max_player_hp)
		
var max_player_hp = DEFAULT_MAX_HP:
	set(new_max_hp):
		max_player_hp = new_max_hp
		hp_changed.emit(player_hp, max_player_hp)
		
var score = 0:
	set(new_score):
		score = new_score
		score_changed.emit(score)
		
var light_durability = DEFAULT_LIGHT_DURABILITY:
	set(new_durability):
		light_durability = new_durability
		light_changed.emit(light_durability, max_light_durability)

# --- Other Game State Variables ---
var level = 1
var high_scores = []
var is_flickering = false
var max_light_durability = DEFAULT_MAX_LIGHT_DURABILITY
var item_lore = {}
var corpse_has_crystal = {}
var looted_corpses = {}

var crystal_inventory = []
var glow_slot = true
var melee_slot = false
var melee_slot_uses = 0


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


func has_light_source():
	return glow_slot and light_durability > 0


func reset():
	score = 0
	level = 1
	max_player_hp = DEFAULT_MAX_HP
	player_hp = DEFAULT_MAX_HP
	is_flickering = false
	light_durability = DEFAULT_LIGHT_DURABILITY
	max_light_durability = DEFAULT_LIGHT_DURABILITY
	item_lore.clear()
	corpse_has_crystal.clear()
	looted_corpses.clear()
	crystal_inventory.clear()
	glow_slot = true
	melee_slot = false
	melee_slot_uses = 0
