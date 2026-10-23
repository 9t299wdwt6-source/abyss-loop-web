extends Node
# Loads the reviewed Russian reference catalog; keys stay independent of game rules.

const DEFAULT_LOCALE := "ru"
const CATALOG_PATH := "res://localization/strings_ru.json"

var active_locale: String = DEFAULT_LOCALE
var _catalog: Dictionary = {}

func _ready() -> void:
    _load_catalog()

func text(key: String) -> String:
    if _catalog.is_empty():
        _load_catalog()
    if not _catalog.has(key):
        push_warning("Missing localization key: %s" % key)
        return key
    return str(_catalog[key])

func has_key(key: String) -> bool:
    if _catalog.is_empty():
        _load_catalog()
    return _catalog.has(key)

func catalog_size() -> int:
    if _catalog.is_empty():
        _load_catalog()
    return _catalog.size()

func _load_catalog() -> void:
    if not FileAccess.file_exists(CATALOG_PATH):
        push_error("Localization catalog is missing: %s" % CATALOG_PATH)
        _catalog = {}
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Localization catalog must be a JSON object: %s" % CATALOG_PATH)
        _catalog = {}
        return
    _catalog = parsed
