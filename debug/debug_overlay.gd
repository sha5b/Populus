extends CanvasLayer
class_name DebugOverlay

var _visible: bool = false
var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override("font_size", 14)
	add_child(_label)
	visible = _visible


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		_visible = not _visible
		visible = _visible


func update_info(fps: int, entity_count: int, extra: String = "") -> void:
	var text := "FPS: %d | Entities: %d" % [fps, entity_count]
	if extra != "":
		text += "\n" + extra
	_label.text = text
