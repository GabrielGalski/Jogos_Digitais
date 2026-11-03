extends Node
## Light tutorial floor only; the authored dark trail remains on the same map.

const MATERIAL: ShaderMaterial = preload("res://resources/visual/tutorial_soil_clouds.tres")
var soil_material: ShaderMaterial = null
var cloud_elapsed: float = 0.0


func _ready() -> void:
	soil_material = MATERIAL.duplicate() as ShaderMaterial
	var floor_layer: TileMapLayer = get_parent().get_node("Floor") as TileMapLayer
	floor_layer.material = soil_material


func _physics_process(delta: float) -> void:
	cloud_elapsed += delta
	soil_material.set_shader_parameter(&"cloud_elapsed", cloud_elapsed)
