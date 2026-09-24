extends Node
## BloodSystem — «кровь = здоровье» (autoload «Blood»).
## Единственный способ лечиться в игре: стоять вплотную к умирающему врагу.

signal healed(amount: float, from_node: Node)
signal blood_sprayed(global_position: Vector3, intensity: float)
signal thirst_warning            # HP < 25 и рядом никто не умирает

const HEAL_RADIUS := 3.2           # метры — щедрая для 3-го лица
const MAX_HEAL_PER_SECOND := 90.0  # защита от «лечения» толпой за 0 кадров
const SPRAY_COUNT := 14

var _heal_this_second: float = 0.0
var _second_timer: float = 0.0
var _thirst_sent: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	_second_timer += delta
	if _second_timer >= 1.0:
		_second_timer = 0.0
		_heal_this_second = 0.0
	_thirst_sent = false if GameState.hp > 40.0 else _thirst_sent


## Вызывается врагом в момент смерти.
## enemy: Node3D с полями blood_value:int и (опц.) bleed_multiplier:float
func on_enemy_died(enemy: Node, killer_position: Vector3) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return 0.0

	var blood_value: float = 4.0
	if "blood_value" in enemy:
		blood_value = float(enemy.blood_value)
	if "bleed_multiplier" in enemy:
		blood_value *= float(enemy.bleed_multiplier)

	# «ЛОБОТОМ» (пила) режет на куски → +200% крови
	if GameState.has_flag("оружие_лоботом_активно"):
		blood_value *= 3.0

	# Голос МАМЫ: каждое лечение стоит очко стиля
	if Dialogue.active_voice == "МАМА":
		Style.score = maxf(0.0, Style.score - 1.0)

	blood_sprayed.emit(killer_position, blood_value)

	var player := _player()
	if player == null:
		return 0.0
	var dist: float = player.global_position.distance_to(killer_position)
	if dist > HEAL_RADIUS:
		return 0.0

	# чем ближе — тем больше крови попало на Веру
	var falloff: float = 1.0 - (dist / HEAL_RADIUS) * 0.45
	var amount: float = blood_value * falloff * Style.heal_multiplier()
	amount = minf(amount, MAX_HEAL_PER_SECOND - _heal_this_second)
	if amount <= 0.0:
		return 0.0

	_heal_this_second += amount
	GameState.heal(amount)
	healed.emit(amount, enemy)

	# стиль за «грязное» лечение в упор
	if dist <= 1.6:
		Style.award("bloodbath")
	else:
		Style.award("fresh_blood")
	return amount


## Косметика: пятна крови на модели Веры (пижама синеет → краснеет).
func blood_stain_amount() -> float:
	return clampf(1.0 - GameState.hp / GameState.hp_max, 0.0, 1.0)


func _player() -> Node3D:
	var nodes := get_tree().get_nodes_in_group("player")
	return nodes[0] if nodes.size() > 0 else null


## Проверяет «жажду»: если HP низкий и никто не умирает рядом — хоррор-подсказка.
func check_thirst() -> void:
	if _thirst_sent or GameState.hp > 25.0:
		return
	_thirst_sent = true
	thirst_warning.emit()
