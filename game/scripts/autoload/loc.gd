extends Node
## Localization singleton. Loads key/value JSON per language (data-driven, PRD §12).

signal language_changed

var lang := "zh"
var _data: Dictionary = {}

func _ready() -> void:
	_load()

func set_lang(l: String) -> void:
	lang = l
	_load()
	language_changed.emit()

func toggle() -> void:
	set_lang("en" if lang == "zh" else "zh")

func _load() -> void:
	var path := "res://data/locale/%s.json" % lang
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Missing locale file: " + path)
		_data = {}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	_data = parsed if parsed is Dictionary else {}

func t(key: String) -> String:
	if _data.has(key):
		return str(_data[key])
	return key

func keys() -> Array:
	return _data.keys()
