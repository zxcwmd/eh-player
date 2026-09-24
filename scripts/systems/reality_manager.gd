extends Node
## RealityManager — два слоя реальности (autoload «Reality»).
## БЕЛЫЙ: стерильная больница, «как есть», официальные реплики.
## РЖАВЫЙ: мясо и ржавчина, «как Вера чувствует», честные реплики.
## Один и тот же уровень имеет две геометрии; некоторые двери существуют
## только в одном слое.

signal layer_changing(to_layer: String)      # начало 4-секундного морфа
signal layer_changed(to_layer: String)       # морф завершён
signal vision_stability_changed(value: float)

enum Layer { WHITE, RUST }

const LAYER_NAMES := {Layer.WHITE: "white", Layer.RUST: "rust"}
const GROUP_WHITE := "white_layer"
const GROUP_RUST := "rust_layer"
const MORPH_TIME := 4.0                      # во время морфа игрок неуязвим

var current: int = Layer.WHITE
var morph_progress: float = 1.0              # 0 → 1, 1 = слой полностью проявился
var morphing: bool = false
var pills_cost: int = 1

## Палитры (используются постпроцессом и WorldEnvironment).
const PALETTE := {
	Layer.WHITE: {
		"wall": Color(0.910, 0.929, 0.918),
		"floor": Color(0.725, 0.776, 0.749),
		"accent": Color(0.839, 0.157, 0.157),
		"light": Color(0.94, 0.97, 0.95),
		"blood": Color(0.32, 0.03, 0.05),
		"fog": Color(0.86, 0.89, 0.87),
	},
	Layer.RUST: {
		"wall": Color(0.169, 0.106, 0.090),
		"floor": Color(0.431, 0.231, 0.165),
		"accent": Color(0.949, 0.757, 0.306),
		"light": Color(1.00, 0.72, 0.35),
		"blood": Color(0.95, 0.78, 0.28),
		"fog": Color(0.12, 0.07, 0.05),
	},
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not morphing:
		return
	morph_progress = minf(1.0, morph_progress + delta / MORPH_TIME)
	vision_stability_changed.emit(morph_progress)
	if morph_progress >= 1.0:
		morphing = false
		layer_changed.emit(layer_name())


func layer_name() -> String:
	return LAYER_NAMES[current]


func is_white() -> bool:
	return current == Layer.WHITE


## Таблетка под язык (F/T). Не ставит игру на паузу: 4 секунды Вера «перестраивается».
func take_pill() -> bool:
	if morphing:
		return false
	if not GameState.use_pill():
		return false
	_toggle()
	return true


func _toggle() -> void:
	current = Layer.RUST if current == Layer.WHITE else Layer.WHITE
	morphing = true
	morph_progress = 0.0
	layer_changing.emit(layer_name())
	_apply_visibility()
	Style.award("layer_swap")
	Dialogue.on_reality_flip(layer_name())
	GameState.set_flag("слой_" + layer_name())


## Переключает видимость/коллизии групп white_layer и rust_layer.
func _apply_visibility() -> void:
	var show_rust := current == Layer.RUST
	for n in get_tree().get_nodes_in_group(GROUP_RUST):
		_set_node_active(n, show_rust)
	for n in get_tree().get_nodes_in_group(GROUP_WHITE):
		_set_node_active(n, not show_rust)


func _set_node_active(n: Node, active: bool) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).visible = active
	if n is CollisionObject3D:
		(n as CollisionObject3D).process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
		for c in (n as CollisionObject3D).get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).disabled = not active
	if "layer_active" in n:
		n.layer_active = active


func register(n: Node) -> void:
	_set_node_active(n, _matches_current(n))


func _matches_current(n: Node) -> bool:
	if n.is_in_group(GROUP_RUST):
		return current == Layer.RUST
	return current == Layer.WHITE


func color(key: String) -> Color:
	return PALETTE[current][key]


## Интерполяция палитры во время морфа — используется постпроцессом.
func blended_color(key: String) -> Color:
	var a: Color = PALETTE[Layer.WHITE][key]
	var b: Color = PALETTE[Layer.RUST][key]
	if not morphing:
		return a if current == Layer.WHITE else b
	return a.lerp(b, morph_progress) if current == Layer.RUST else b.lerp(a, morph_progress)


## Ржавый слой открывает «честные» версии реплик.
func dialogue_variant() -> String:
	return "rust" if current == Layer.RUST else "white"


## Двери, существующие только в одном слое.
func door_open(door_layer: String) -> bool:
	return door_layer == layer_name() or door_layer == "both"
