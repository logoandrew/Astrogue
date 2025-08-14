extends Node

var lore_data: Dictionary


func _ready():
	load_lore_data()


func load_lore_data():
	var file = FileAccess.open("res://lore.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json = JSON.parse_string(json_string)
		if json:
			lore_data = json
		file.close()


func generate_scout_lore():
	if not lore_data.has("scouts"):
		return "No lore data found."
		
	var s = lore_data.scouts
	var template = s.templates.pick_random()
	var lore_text = template.format({
		"first_name": s.first_names.pick_random(),
		"last_name": s.last_names.pick_random(),
		"nickname": s.nicknames.pick_random(),
		"origin": s.origins.pick_random(),
		"motivation": s.motivations.pick_random(),
		"death": s.deaths.pick_random(),
		"death_quote": s.death_quotes.pick_random(),
		"personal_item": s.personal_items.pick_random(),
		"regret": s.regrets.pick_random(),
		"hometown_detail": s.hometown_details.pick_random()
	})
	
	return lore_text
