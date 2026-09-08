class_name GMPlayerShellActor2D
extends GMCharacterRuntime2D

## The Player Shell's single canonical 2D control projection.  GAS/P15 owns
## movement; this node only renders the resulting entity projection.

func _ready() -> void:
	super._ready()
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var active := activation_state == "active"
	var body_color := Color("#65c7ff") if active else Color("#8996a8")
	draw_circle(Vector2.ZERO, 16.0, Color(0.05, 0.09, 0.16, 0.8))
	draw_circle(Vector2.ZERO, 12.0, body_color)
	draw_arc(Vector2.ZERO, 18.0, 0.0, TAU, 32, Color("#c5eeff"), 2.0)
	var facing := movement_facing.normalized() if movement_facing.length_squared() > 0.001 else Vector2.DOWN
	draw_line(facing * 7.0, facing * 17.0, Color("#ffffff"), 3.0)
