extends Node2D

@export var skin_texture: Texture2D

func _ready():
	$Sprite2D.texture = skin_texture
