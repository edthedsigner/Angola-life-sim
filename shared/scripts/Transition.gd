extends CanvasLayer
## Fade preto global (autoload "Transition") para entrar/sair do mundo sem cortes abruptos.
var rect: ColorRect

func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.color = Color(0.03, 0.035, 0.05, 1.0)
	rect.modulate.a = 0.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)

func fade_out(t: float = 0.5) -> void:
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, t)
	await tw.finished

func fade_in(t: float = 0.6) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", 0.0, t)
	await tw.finished
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
