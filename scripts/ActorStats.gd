class_name ActorStats
extends Resource

@export var actor_type: GlobalEnums.ActorType
@export var char: String = "@"
var color: Color = Color.WHITE
@export var color_name: String = "COLOR_ACTOR_ALIEN":
	set(value):
		color_name = value
		color = GameState._update_color(color_name)
@export var hp: int = 10
@export var accuracy: int = 80
@export var damage: int = 1


func _init():
	color = GameState._update_color(color_name)
