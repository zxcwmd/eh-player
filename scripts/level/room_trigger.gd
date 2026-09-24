class_name RoomTrigger
extends Area3D
## Триггер комнаты. Делает три вещи:
##   1. сообщает Isaac-камере границы комнаты (для snap и combat-zoom);
##   2. запускает волны врагов комнаты через FloorManager;
##   3. включает/выключает боевой слой музыки.

signal room_entered(room_name: String)
signal room_cleared(room_name: String)

@export var room_name: String = "Комната"
@export var wave_group: String = ""            # id группы волн в данных этажа
@export var lock_doors_on_combat: bool = true

var player_inside: bool = false
var active: bool = false
var enemies_alive: int = 0


func _ready() -> void:
	add_to_group("room_trigger")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 2
	var shape := get_node_or_null("CollisionShape3D")
	if shape == null:
		shape = CollisionShape3D.new()
		var size: Vector2 = get_meta("room_size", Vector2(18, 18))
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, 3.4, size.y)
		shape.shape = box
		shape.position = Vector3(0, 1.7, 0)
		add_child(shape)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or player_inside:
		return
	player_inside = true
	active = true
	room_entered.emit(room_name)
	_notify_camera()
	if wave_group != "":
		_start_combat()
	else:
		Audio.set_music_layer(0)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	player_inside = false


func _notify_camera() -> void:
	var center: Vector3 = global_position
	if get_parent() != null:
		center = (get_parent() as Node3D).global_position
	var size: Vector2 = get_meta("room_size", Vector2(18, 18))
	var cams := get_tree().get_nodes_in_group("isaac_camera")
	if cams.size() > 0:
		var cam: Node = cams[0]
		if cam.has_method("enter_room"):
			cam.enter_room(room_name, center, size)


func _start_combat() -> void:
	var fm := _floor_manager()
	if fm == null:
		return
	enemies_alive = fm.start_waves(wave_group, self)
	if enemies_alive > 0:
		Audio.set_music_layer(1)
	else:
		_finish_room()


func on_enemy_died() -> void:
	if not active:
		return
	enemies_alive = maxi(0, enemies_alive - 1)
	if enemies_alive == 0:
		_finish_room()


func _finish_room() -> void:
	active = false
	room_cleared.emit(room_name)
	Audio.set_music_layer(0)
	if Style.hallucinating():
		return
	# тихие комнаты без боя в белом слое включают «дышащую» камеру
	if wave_group == "":
		var cams := get_tree().get_nodes_in_group("isaac_camera")
		if cams.size() > 0 and (cams[0] as Node).has_method("set_detached"):
			pass


func _floor_manager() -> Node:
	var nodes := get_tree().get_nodes_in_group("floor_manager")
	return nodes[0] if nodes.size() > 0 else null
