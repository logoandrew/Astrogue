class_name TileStats
extends Resource

@export var char: String = "."
@export var color_name: String = "COLOR_ACCENT"
@export var color: Color = DesignSystem.COLOR_TEXT_PRIMARY
@export var is_item: bool = false
@export var pickup_method: String = "" # auto or manual
@export var pickup_effect: PickupEffect
