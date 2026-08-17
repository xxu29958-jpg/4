class_name DamageNumber
extends Label
## 飘字伤害数字：命中反馈的核心可读性（参照三国大时代式黄白数字）。

const COLOR_NORMAL := Color(1.0, 1.0, 1.0)
const COLOR_SKILL := Color(1.0, 0.85, 0.35)


static func spawn(parent: Node, pos: Vector2, amount: int, is_skill := false) -> void:
	var num := DamageNumber.new()
	num.text = str(amount)
	num.position = pos + Vector2(-10, -40)
	num.z_index = 100
	num.add_theme_font_size_override("font_size", 22 if is_skill else 17)
	num.add_theme_color_override("font_color",
			COLOR_SKILL if is_skill else COLOR_NORMAL)
	num.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
	num.add_theme_constant_override("outline_size", 5)
	parent.add_child(num)
	var tw := num.create_tween()
	tw.set_parallel()
	tw.tween_property(num, "position:y", num.position.y - 30, 0.55) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(num, "modulate:a", 0.0, 0.55).set_delay(0.1)
	tw.chain().tween_callback(num.queue_free)
