class_name TileStats
extends Resource

@export var char: String = "."
var color: Color = Color.WHITE
@export var color_name: String = "COLOR_TEXT_PRIMARY":
	set(value):
		color_name = value
		color = GameState._update_color(color_name)
@export var is_item: bool = false
@export var pickup_method: String = "" # auto or manual
@export var pickup_effect: PickupEffect


func _init():
	color = GameState._update_color(color_name)
