extends Node
## DialogueRunner — новелла в реальном времени (autoload «Dialogue»).
## Диалог НЕ ставит игру на паузу: он идёт в углу экрана, пока бой продолжается.
## На время выбора Engine.time_scale = 0.6 (слоу-мо), иначе нечестно.
## Каждая реплика — это тег (#жестокость / #жалость / #правда / #ложь) и эффект.

signal dialogue_started(convo_id: String)
signal node_entered(node: Dictionary)
signal choices_offered(choices: Array, time_left: float)
signal choice_made(choice: Dictionary)
signal timed_out(node_id: String)
signal dialogue_ended(convo_id: String)
signal voice_set(voice_id: String)
signal fx_applied(fx: Dictionary)

const DIALOGUE_DIR := "res://content/dialogues/"
const CHOICE_TIME := 6.0
const SLOW_TIME_SCALE := 0.6
const CHARS_PER_SECOND := 42.0

var active: bool = false
var convo_id: String = ""
var convo: Dictionary = {}
var node: Dictionary = {}
var node_id: String = ""
var speaker: String = ""
var portrait: String = ""
var full_text: String = ""
var visible_chars: int = 0
var choices: Array = []
var choice_time_left: float = 0.0
var waiting_for_choice: bool = false
var finished: bool = false

## Голос, который сейчас «живёт в голове» и даёт бафф (Blood читает это).
var active_voice: String = ""

var _cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not active:
		return
	if visible_chars < full_text.length():
		visible_chars = mini(full_text.length(), visible_chars + int(CHARS_PER_SECOND * delta) + 1)
	if waiting_for_choice:
		choice_time_left -= delta
		choices_offered.emit(choices, choice_time_left)
		if choice_time_left <= 0.0:
			_resolve_timeout()


# ---------------------------------------------------------------- запуск

## Пул коротких реплик Голосов в бою: берёт случайный узел из "pool".
func start_pool(id: String) -> bool:
	var data := _load_convo(id)
	if data.is_empty():
		return false
	var pool: Array = data.get("pool", [])
	if pool.is_empty():
		return false
	return start(id, str(pool[randi() % pool.size()]))


func start(id: String, start_node: String = "") -> bool:
	if active:
		return false
	var data := _load_convo(id)
	if data.is_empty():
		push_warning("Dialogue: разговор «%s» не найден" % id)
		return false
	active = true
	finished = false
	convo_id = id
	convo = data
	for part in str(data.get("participants", "")).split(","):
		var who := part.strip_edges()
		if who != "":
			GameState.meet(who)
	var first: String = start_node if start_node != "" else str(data.get("start", ""))
	_enter_node(first)
	Engine.time_scale = SLOW_TIME_SCALE
	dialogue_started.emit(id)
	return true


func _load_convo(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := DIALOGUE_DIR + id + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	var out: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	_cache[id] = out
	return out


func _enter_node(id: String) -> void:
	if id == "" or id == "END":
		end()
		return
	var nodes: Dictionary = convo.get("nodes", {})
	if not nodes.has(id):
		push_warning("Dialogue: узел «%s» отсутствует в «%s»" % [id, convo_id])
		end()
		return
	node_id = id
	node = nodes[id]
	speaker = str(node.get("speaker", ""))
	portrait = str(node.get("portrait", ""))

	# «ГОЛОСА» — три советчика; выбор голоса даёт постоянный бафф и цену
	if node.has("voice"):
		set_voice(str(node["voice"]))

	full_text = _localized_text(node)
	visible_chars = 0

	var raw_choices: Variant = node.get("choices", [])
	choices = _filter_choices(raw_choices) if typeof(raw_choices) == TYPE_ARRAY else []
	waiting_for_choice = choices.size() > 0
	choice_time_left = CHOICE_TIME if waiting_for_choice else 0.0

	# автоэффекты узла (не связанные с выбором)
	_apply_fx(node.get("fx", {}))

	node_entered.emit(node)


## Два слоя реальности = два текста одной и той же реплики.
func _localized_text(n: Dictionary) -> String:
	var variants: Dictionary = n.get("variants", {})
	if variants.size() > 0:
		var key := Reality.dialogue_variant()
		if variants.has(key):
			return str(variants[key])
	return str(n.get("text", ""))


func _filter_choices(raw: Array) -> Array:
	var out: Array = []
	for c in raw:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var cond: Variant = c.get("if", {})
		if typeof(cond) == TYPE_DICTIONARY and not _check_condition(cond):
			continue
		out.append(c)
	return out


func _check_condition(c: Dictionary) -> bool:
	if c.has("flag") and not GameState.has_flag(str(c["flag"])):
		return false
	if c.has("no_flag") and GameState.has_flag(str(c["no_flag"])):
		return false
	if c.has("layer") and Reality.layer_name() != str(c["layer"]):
		return false
	if c.has("voice") and active_voice != str(c["voice"]):
		return false
	if c.has("min_rank") and Style.rank_value(Style.rank_current) < Style.rank_value(str(c["min_rank"])):
		return false
	if c.has("lida_inside") and GameState.lida_inside != bool(c["lida_inside"]):
		return false
	if c.has("mother_alive") and GameState.mother_alive != bool(c["mother_alive"]):
		return false
	return true


# ---------------------------------------------------------------- ввод

## index: 0..3. Вызывается из UI или по клавишам 1-4.
func choose(index: int) -> void:
	if not waiting_for_choice or index < 0 or index >= choices.size():
		return
	var c: Dictionary = choices[index]
	waiting_for_choice = false
	choice_made.emit(c)

	var tag: String = str(c.get("tag", ""))
	if tag != "":
		GameState.add_tag(tag, int(c.get("weight", 1)))
	_apply_fx(c.get("fx", {}))

	var next: String = str(c.get("goto", node.get("next", "END")))
	_enter_node(next)


func _resolve_timeout() -> void:
	waiting_for_choice = false
	timed_out.emit(node_id)
	# «МОЛЧАТЬ» — путь к секретной концовке
	GameState.add_tag("молчание", 1)
	var on_timeout: String = str(node.get("on_timeout", node.get("next", "END")))
	_enter_node(on_timeout)


## Пропуск печати / узла без выбора (пробел, ЛКМ).
func advance() -> void:
	if not active:
		return
	if visible_chars < full_text.length():
		visible_chars = full_text.length()
		return
	if waiting_for_choice:
		return
	_enter_node(str(node.get("next", "END")))


func end() -> void:
	if not active:
		return
	active = false
	finished = true
	waiting_for_choice = false
	Engine.time_scale = 1.0
	dialogue_ended.emit(convo_id)


# ---------------------------------------------------------------- эффекты

func _apply_fx(raw: Variant) -> void:
	if typeof(raw) != TYPE_DICTIONARY or raw.is_empty():
		return
	var fx: Dictionary = raw
	if fx.has("flag"):
		GameState.set_flag(str(fx["flag"]), bool(fx.get("flag_value", true)))
	if fx.has("tag"):
		GameState.add_tag(str(fx["tag"]), int(fx.get("weight", 1)))
	if fx.has("heal"):
		GameState.heal(float(fx["heal"]))
	if fx.has("damage"):
		GameState.damage(float(fx["damage"]))
	if fx.has("pills"):
		GameState.add_pills(int(fx["pills"]))
	if fx.has("unlock_weapon"):
		var w := int(fx["unlock_weapon"])
		if not GameState.weapons_unlocked.has(w):
			GameState.weapons_unlocked.append(w)
	if fx.has("procedure"):
		SaveSystem.record_procedure(str(fx["procedure"]))
		if not GameState.weapons_unlocked.has(4):
			GameState.weapons_unlocked.append(4)
	if fx.has("page"):
		if GameState.add_page(str(fx["page"])):
			Style.award("secret_found")
	if fx.has("style"):
		Style.award(str(fx["style"]))
	if fx.has("voice"):
		set_voice(str(fx["voice"]))
	if fx.has("end_convo") and bool(fx["end_convo"]):
		end()
	fx_applied.emit(fx)


func set_voice(voice_id: String) -> void:
	active_voice = voice_id
	voice_set.emit(voice_id)
	match voice_id:
		"ДОКТОР":
			GameState.set_flag("голос_доктор")
		"МАМА":
			GameState.set_flag("голос_мама")
		"СЕСТРА":
			GameState.set_flag("голос_сестра")
			GameState.lida_inside = true
		"":
			GameState.set_flag("голос_никто")


# ---------------------------------------------------------------- запросы из UI

func text_visible() -> String:
	return full_text.left(visible_chars)


func is_typing() -> bool:
	return visible_chars < full_text.length()


func available_conversations() -> Array:
	var ids: Array = []
	var dir := DirAccess.open(DIALOGUE_DIR)
	if dir == null:
		return ids
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".json"):
			ids.append(f.get_basename())
		f = dir.get_next()
	dir.list_dir_end()
	return ids
