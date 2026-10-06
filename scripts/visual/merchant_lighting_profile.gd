extends Resource
## Safe-room art direction, independent from combat lighting.
@export var ambient: Color = Color("ad98b8")
@export var facade_color: Color = Color("ff559f")
@export var door_color: Color = Color("cf6389")
@export var water_color: Color = Color("69d6ca")
@export var tin_color: Color = Color("ffe4cf")
@export_range(0.0, 1.0) var facade_energy: float = 0.34
@export_range(0.0, 1.0) var door_energy: float = 0.30
@export_range(0.0, 1.0) var water_energy: float = 0.12
@export_range(0.0, 1.0) var tin_energy: float = 0.46
