extends Control

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const RouteViewScript = preload("res://scripts/ui/route_view.gd")
const BaseSystemScript = preload("res://scripts/systems/base_system.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")
const TileSystemScript = preload("res://scripts/systems/tile_system.gd")
const FeedbackSystemScript = preload("res://scripts/systems/feedback_system.gd")
const DeveloperDiagnosticsReportScript = preload("res://scripts/ui/developer_diagnostics_report.gd")
const StatusEffectPresenterScript = preload("res://scripts/ui/status_effect_presenter.gd")
const ItemTextPresenterScript = preload("res://scripts/ui/item_text_presenter.gd")
const RunDebriefPresenterScript = preload("res://scripts/ui/run_debrief_presenter.gd")
const InventoryDragButtonScript = preload("res://scripts/ui/inventory_drag_button.gd")

# Original pixel-art abyss palette: basalt, moss, jade light, lantern amber, and rare crystal.
const C_BG := Color("#0a1821")
const C_PANEL := Color("#14292d")
const C_PANEL_ALT := Color("#203c3a")
const C_TEXT := Color("#f0ecd7")
const C_MUTED := Color("#a7b9ac")
const C_ACCENT := Color("#a0dc79")
const C_GOLD := Color("#efc36b")
const C_RED := Color("#e87966")
const ABYSS_BACKDROP: Texture2D = preload("res://assets/background/abyss_pixel_backdrop.png")
const TUTORIAL_STEPS := [
	{"title_key": "tutorial.1.title", "body_key": "tutorial.1.body", "tip_key": "tutorial.1.tip"},
	{"title_key": "tutorial.2.title", "body_key": "tutorial.2.body", "tip_key": "tutorial.2.tip"},
	{"title_key": "tutorial.3.title", "body_key": "tutorial.3.body", "tip_key": "tutorial.3.tip"},
	{"title_key": "tutorial.4.title", "body_key": "tutorial.4.body", "tip_key": "tutorial.4.tip"},
	{"title_key": "tutorial.5.title", "body_key": "tutorial.5.body", "tip_key": "tutorial.5.tip"}
]
var manager
var selected_floor_number: int = 1
var selected_modifier_id: String = "standard"
var selected_contract_id: String = "none"
var floor_option: OptionButton
var modifier_option: OptionButton
var contract_option: OptionButton
var modifier_preview_label: Label
var seed_input: LineEdit
var pending_preview_seed: int = 0
var base_system = BaseSystemScript.new()
var inventory_system = InventorySystemScript.new()
var feedback_system
var developer_diagnostics_report = DeveloperDiagnosticsReportScript.new()
var status_effect_presenter = StatusEffectPresenterScript.new()
var screen_mode := "base"
var shell: MarginContainer
var main_column: VBoxContainer
var content_root: VBoxContainer
var phase_label: Label
var scrap_label: Label
var crystal_label: Label
var run_loot_label: Label
var notice_label: Label
var settings_button: Button
var help_button: Button
var log_scroll: ScrollContainer
var route_view: Control
var route_hint_label: Label
var first_hour_guide_panel: PanelContainer
var first_hour_guide_label: Label
var _first_hour_guide_signature: String = ""
var objective_label: Label
var challenge_label: Label
var contract_label: Label
var fight_status_label: Label
var fight_health_bar: ProgressBar
var status_effects_label: Label
var pause_button: Button
var return_button: Button
var speed_label: Label
var equipment_label: Label
var expedition_gear_panel: PanelContainer
var backpack_button: Button
var armory_page_index: int = 0
var log_label: Label
var tile_hand_grid: GridContainer
var tile_exchange_button: Button
var loot_preparation_label: Label
var tile_preview_label: Label
var tile_hand_signature := ""
var selected_tile_hand_index := -1
var exp_metrics: Dictionary = {}
var overlay: Control
var modal_kind := ""
var current_summary: Dictionary = {}
var _resume_after_settings: bool = false
var _resume_after_return_confirmation: bool = false
var developer_report_label: Label
var developer_status_label: Label
var _focus_before_overlay: Control
var _base_primary_action: Control
var _brand_box: VBoxContainer
var _brand_title: Label
var _brand_subtitle: Label
var _phase_panel: PanelContainer
var _header_spacer: Control
var _scrap_panel: PanelContainer
var _crystal_panel: PanelContainer
var _resource_spacer: Control
var _run_panel: PanelContainer
var _developer_button: Button
var _compact_layout_active: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_content_scale()
	_compact_layout_active = _is_compact_layout()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_audio_buses()
	_apply_audio_settings()
	_apply_display_settings()
	_build_shell()
	manager = ExpeditionManagerScript.new()
	add_child(manager)
	feedback_system = FeedbackSystemScript.new()
	add_child(feedback_system)
	manager.feedback_requested.connect(_on_feedback_requested)
	manager.changed.connect(_on_manager_changed)
	manager.run_finished.connect(_on_run_finished)
	GameState.changed.connect(_on_game_state_changed)
	# Connect only after the shell and game-state nodes exist; the first Web
	# viewport resize can happen immediately after the initial HTML canvas boot.
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_compact_layout_active = _is_compact_layout()
	_apply_responsive_shell()
	_render_base()
	_refresh_header()
	if not GameState.tutorial_completed and not GameState.has_saved_expedition():
		call_deferred("_show_tutorial_step", GameState.tutorial_page)

func _process(_delta: float) -> void:
	if screen_mode == "expedition" and manager != null and is_instance_valid(manager):
		_sync_expedition_view(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and manager != null and is_instance_valid(manager) and manager.active:
		manager.save_run_snapshot()

func _build_shell() -> void:
	var bg := TextureRect.new()
	bg.texture = ABYSS_BACKDROP
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var bg_shade := ColorRect.new()
	bg_shade.color = Color(0.018, 0.038, 0.048, 0.34)
	bg_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_shade)
	shell = MarginContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_theme_constant_override("margin_left", 24)
	shell.add_theme_constant_override("margin_right", 24)
	shell.add_theme_constant_override("margin_top", 18)
	shell.add_theme_constant_override("margin_bottom", 18)
	add_child(shell)
	main_column = VBoxContainer.new()
	main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_column.add_theme_constant_override("separation", 10)
	shell.add_child(main_column)
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 14)
	main_column.add_child(header)
	_brand_box = VBoxContainer.new()
	_brand_box.custom_minimum_size.x = 285
	_brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brand_box.add_theme_constant_override("separation", 1)
	header.add_child(_brand_box)
	_brand_title = _label("ABYSS LOOP", 21, C_TEXT, true)
	_brand_box.add_child(_brand_title)
	_brand_subtitle = _label(_t("header.brand.subtitle"), 11, C_MUTED, true)
	_brand_box.add_child(_brand_subtitle)
	_header_spacer = Control.new()
	_header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_header_spacer)
	_phase_panel = _make_panel(header, C_PANEL_ALT, 12)
	_phase_panel.custom_minimum_size.x = 122
	phase_label = _label(_t("header.phase.shelter"), 12, C_ACCENT, true)
	phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phase_panel.add_child(phase_label)
	help_button = _button(_t("header.button.help"), Callable(self, "_open_help_menu"), false)
	help_button.custom_minimum_size.x = 88
	header.add_child(help_button)
	if OS.is_debug_build():
		_developer_button = _button(_t("header.button.diagnostics"), Callable(self, "_open_developer_tools"), false)
		_developer_button.custom_minimum_size.x = 142
		_developer_button.tooltip_text = "Отладочная панель разработчика; доступна только в debug-сборке."
		header.add_child(_developer_button)
	settings_button = _button(_t("header.button.settings"), Callable(self, "_open_settings"), false)
	settings_button.custom_minimum_size.x = 112
	header.add_child(settings_button)
	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color("#2a3c43"))
	main_column.add_child(separator)
	var resource_row := HBoxContainer.new()
	resource_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_row.add_theme_constant_override("separation", 8)
	main_column.add_child(resource_row)
	_scrap_panel = _make_panel(resource_row, C_PANEL, 9)
	_scrap_panel.custom_minimum_size.x = 190
	_scrap_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrap_label = _label("Материалы 60", 13, C_GOLD, true)
	_scrap_panel.add_child(scrap_label)
	_crystal_panel = _make_panel(resource_row, C_PANEL, 9)
	_crystal_panel.custom_minimum_size.x = 190
	_crystal_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crystal_label = _label("Редкий ресурс 14", 13, Color("#8ec7ec"), true)
	_crystal_panel.add_child(crystal_label)
	_resource_spacer = Control.new()
	_resource_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_row.add_child(_resource_spacer)
	_run_panel = _make_panel(resource_row, C_PANEL, 9)
	_run_panel.custom_minimum_size.x = 310
	_run_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	run_loot_label = _label("Добыча экспедиции: —", 12, C_MUTED)
	_run_panel.add_child(run_loot_label)
	content_root = VBoxContainer.new()
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_root.add_theme_constant_override("separation", 12)
	main_column.add_child(content_root)
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.visible = false
	add_child(overlay)
	_apply_responsive_shell()

func _update_content_scale() -> void:
	var root_window := get_window()
	if root_window == null:
		return
	var window_size: Vector2i = root_window.size
	if window_size.x <= 0 or window_size.y <= 0:
		return
	# The desktop design canvas is 1440x900. Keeping that virtual size on a
	# 390x844 browser canvas shrinks all text and controls to a fraction of a
	# CSS pixel and letterboxes the game. On compact screens use the actual
	# browser window size as the virtual size, then reflow the UI into columns.
	# Desktop retains the existing layout scale.
	var target_scale_size := window_size if window_size.x < 900 or window_size.y < 560 else Vector2i(1440, 900)
	if root_window.content_scale_size != target_scale_size:
		root_window.content_scale_size = target_scale_size
	if root_window.content_scale_aspect != Window.CONTENT_SCALE_ASPECT_EXPAND:
		root_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

func _is_compact_layout() -> bool:
	return get_viewport_rect().size.x < 900.0

func _apply_responsive_shell() -> void:
	var compact_layout := _is_compact_layout()
	if is_instance_valid(shell):
		shell.add_theme_constant_override("margin_left", 8 if compact_layout else 24)
		shell.add_theme_constant_override("margin_right", 8 if compact_layout else 24)
		shell.add_theme_constant_override("margin_top", 8 if compact_layout else 18)
		shell.add_theme_constant_override("margin_bottom", 8 if compact_layout else 18)
	if is_instance_valid(main_column):
		main_column.add_theme_constant_override("separation", 6 if compact_layout else 10)
	if is_instance_valid(_brand_box):
		_brand_box.custom_minimum_size.x = 0 if compact_layout else 285
	if is_instance_valid(_brand_title):
		_brand_title.add_theme_font_size_override("font_size", 17 if compact_layout else 21)
	if is_instance_valid(_brand_subtitle):
		_brand_subtitle.visible = not compact_layout
	if is_instance_valid(_phase_panel):
		_phase_panel.custom_minimum_size.x = 92 if compact_layout else 122
	if is_instance_valid(phase_label):
		phase_label.add_theme_font_size_override("font_size", 10 if compact_layout else 12)
	if is_instance_valid(_header_spacer):
		_header_spacer.visible = true
	if is_instance_valid(help_button):
		help_button.visible = not compact_layout
	if is_instance_valid(_developer_button):
		_developer_button.visible = not compact_layout
	if is_instance_valid(settings_button):
		settings_button.text = "Настройки" if compact_layout else _t("header.button.settings")
		settings_button.custom_minimum_size.x = 96 if compact_layout else 112
	if is_instance_valid(_scrap_panel):
		_scrap_panel.custom_minimum_size.x = 120 if compact_layout else 190
	if is_instance_valid(_crystal_panel):
		_crystal_panel.custom_minimum_size.x = 146 if compact_layout else 190
	if is_instance_valid(_resource_spacer):
		_resource_spacer.visible = not compact_layout
	if is_instance_valid(_run_panel):
		_run_panel.visible = not compact_layout
	if is_instance_valid(scrap_label):
		scrap_label.add_theme_font_size_override("font_size", 11 if compact_layout else 13)
	if is_instance_valid(crystal_label):
		crystal_label.add_theme_font_size_override("font_size", 11 if compact_layout else 13)

func _on_viewport_size_changed() -> void:
	_update_content_scale()
	_apply_responsive_shell()
	var compact_layout := _is_compact_layout()
	if compact_layout == _compact_layout_active:
		return
	_compact_layout_active = compact_layout
	# Rebuild only the content tree at a breakpoint transition. GameState and the
	# expedition manager remain alive, so resizing or rotating never resets a run.
	if screen_mode == "expedition":
		_render_expedition()
	else:
		_render_base()

func _t(key: String) -> String:
	return Localization.text(key)

func _label(text_value: String, font_size: int = 14, color: Color = C_TEXT, bold: bool = false) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if bool(GameState.settings.get("high_contrast", false)) and color == C_MUTED:
		label.add_theme_color_override("font_color", Color("#e0eee4"))
	if bold or bool(GameState.settings.get("high_contrast", false)):
		label.add_theme_color_override("font_outline_color", Color("#061014") if bool(GameState.settings.get("high_contrast", false)) else Color(0, 0, 0, 0.2))
		label.add_theme_constant_override("outline_size", 1 if bool(GameState.settings.get("high_contrast", false)) else 0)
	# Short UI labels must retain their natural width; wrapping every label made
	# HBoxContainer children collapse to a few pixels and pushed the body off-screen.
	# Long explanatory text still wraps safely inside its containing panel.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text_value.length() > 42 else TextServer.AUTOWRAP_OFF
	return label

func _make_panel(parent: Node, fill: Color = C_PANEL, padding: int = 16) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill.r, fill.g, fill.b, 0.86)
	style.border_color = Color("#d2e8d9") if bool(GameState.settings.get("high_contrast", false)) else Color("#526b52")
	style.set_border_width_all(3 if bool(GameState.settings.get("high_contrast", false)) else 2)
	style.set_corner_radius_all(5)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	panel.add_theme_stylebox_override("panel", style)
	if parent != null:
		parent.add_child(panel)
	return panel

func _apply_keyboard_focus_outline(control: Control) -> void:
	control.focus_mode = Control.FOCUS_ALL
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	focus_style.border_color = Color("#fff2a8")
	focus_style.set_border_width_all(2)
	focus_style.set_corner_radius_all(3)
	control.add_theme_stylebox_override("focus", focus_style)

func _button(text_value: String, callback: Callable, accent: bool = false, script_override: Script = null) -> Button:
	var button := Button.new()
	if script_override != null:
		button.set_script(script_override)
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("#10221f") if accent else C_TEXT)
	button.add_theme_color_override("font_hover_color", Color("#10221f") if accent else C_TEXT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = C_ACCENT if accent else Color("#263c3b")
	var high_contrast := bool(GameState.settings.get("high_contrast", false))
	normal.border_color = Color("#f0f6ef") if high_contrast else (Color("#d2e69b") if accent else Color("#526f58"))
	normal.set_border_width_all(3 if high_contrast else 2)
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#b4eb8b") if accent else Color("#35554a")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#7fbd5c") if accent else Color("#1c302f")
	# Disabled actions must not look like active bright-green buttons. In particular,
	# returning during combat is intentionally blocked and needs a clear visual state.
	var disabled_style := normal.duplicate() as StyleBoxFlat
	disabled_style.bg_color = Color("#34413b")
	disabled_style.border_color = Color("#59665e")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_color_override("font_disabled_color", Color("#b0bbb4"))
	var focus_style := StyleBoxFlat.new()
	focus_style.bg_color = Color("#314d43") if not accent else Color("#b4eb8b")
	focus_style.border_color = Color("#fff2a8")
	focus_style.set_border_width_all(3)
	focus_style.set_corner_radius_all(4)
	focus_style.content_margin_left = 12
	focus_style.content_margin_right = 12
	focus_style.content_margin_top = 8
	focus_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("focus", focus_style)
	var action_guard := {"busy": false}
	button.pressed.connect(func() -> void:
		if bool(action_guard.get("busy", false)) or button.disabled:
			return
		action_guard["busy"] = true
		callback.call()
		if is_instance_valid(button) and button.is_inside_tree():
			var reset_timer: SceneTreeTimer = get_tree().create_timer(0.18)
			reset_timer.timeout.connect(func() -> void:
				action_guard["busy"] = false
			)
		else:
			action_guard["busy"] = false
	)
	return button

func _clear_screen() -> void:
	for child in content_root.get_children():
		content_root.remove_child(child)
		child.queue_free()
	route_view = null
	route_hint_label = null
	fight_status_label = null
	fight_health_bar = null
	pause_button = null
	return_button = null
	speed_label = null
	equipment_label = null
	expedition_gear_panel = null
	log_label = null
	log_scroll = null
	tile_hand_grid = null
	tile_preview_label = null
	tile_exchange_button = null
	loot_preparation_label = null
	tile_hand_signature = ""
	exp_metrics.clear()
	selected_tile_hand_index = -1
	notice_label = null

func _set_phase(text_value: String) -> void:
	phase_label.text = text_value

func _refresh_header() -> void:
	if not is_instance_valid(scrap_label):
		return
	var next_scrap_text := "Материалы %d" % int(GameState.scrap)
	var next_crystal_text := "Редкий ресурс %d" % int(GameState.crystals)
	if scrap_label.text != next_scrap_text:
		scrap_label.text = next_scrap_text
	if crystal_label.text != next_crystal_text:
		crystal_label.text = next_crystal_text
	var next_loot_text: String
	if manager != null and is_instance_valid(manager) and bool(manager.active):
		next_loot_text = "Добыча экспедиции: %d мат. · %d редк." % [int(manager.run_ledger.get("scrap", 0)), int(manager.run_ledger.get("crystals", 0))]
	else:
		next_loot_text = "Экспедиции завершены: %d · лучший цикл: %d" % [GameState.runs_completed, GameState.best_loop]
	if run_loot_label.text != next_loot_text:
		run_loot_label.text = next_loot_text

func _on_game_state_changed() -> void:
	_refresh_header()

func _render_base() -> void:
	var compact_layout := _is_compact_layout()
	if is_instance_valid(overlay) and overlay.visible:
		_close_overlay(false)
	_focus_before_overlay = null
	screen_mode = "base"
	_set_phase(_t("header.phase.shelter"))
	_base_primary_action = null
	_clear_screen()
	var base_scroll := ScrollContainer.new()
	base_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	base_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	base_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_root.add_child(base_scroll)
	var base_content := VBoxContainer.new()
	base_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_content.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	base_content.add_theme_constant_override("separation", 12)
	base_scroll.add_child(base_content)
	var top_row: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top_row.add_theme_constant_override("separation", 12 if not compact_layout else 8)
	base_content.add_child(top_row)
	var launch_panel := _make_panel(top_row, Color("#182b31"), 22)
	launch_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_panel.size_flags_stretch_ratio = 1.28
	launch_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var launch_box := VBoxContainer.new()
	launch_box.add_theme_constant_override("separation", 8)
	launch_panel.add_child(launch_box)
	launch_box.add_child(_label(_t("base.section.preparation"), 12, C_ACCENT, true))
	launch_box.add_child(_label(_t("base.hero.title"), 29, C_TEXT, true))
	launch_box.add_child(_label(_t("base.hero.description"), 14, C_MUTED))
	var thin_line := HSeparator.new()
	thin_line.add_theme_color_override("separator", Color("#2c4248"))
	launch_box.add_child(thin_line)
	var feature_row := HBoxContainer.new()
	feature_row.add_theme_constant_override("separation", 8)
	launch_box.add_child(feature_row)
	for feature in [_t("base.feature.autobattle"), _t("base.feature.nodes"), _t("base.feature.tiles")]:
		var feature_panel := _make_panel(feature_row, Color("#20373c"), 8 if compact_layout else 10)
		feature_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var feature_label := _label(feature, 10 if compact_layout else 12, Color("#b7d3cd"), true)
		feature_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact_layout else TextServer.AUTOWRAP_OFF
		feature_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		feature_panel.add_child(feature_label)
	if not GameState.has_saved_expedition():
		selected_floor_number = clampi(GameState.highest_unlocked_floor, 1, ContentRegistry.FLOOR_COUNT)
		var floor_row: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()
		floor_row.add_theme_constant_override("separation", 8)
		launch_box.add_child(floor_row)
		floor_row.add_child(_label(_t("base.floor.label"), 12, C_ACCENT, true))
		floor_option = OptionButton.new()
		_apply_keyboard_focus_outline(floor_option)
		floor_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		floor_option.tooltip_text = "В подземелье восемь этажей. Открывается следующий этаж после победы над его хранителем; закрытые этажи недоступны."
		for floor_index in range(ContentRegistry.FLOOR_DEFS.size()):
			var floor_definition: Dictionary = ContentRegistry.FLOOR_DEFS[floor_index]
			var floor_number: int = int(floor_definition.get("floor", floor_index + 1))
			var is_unlocked: bool = floor_number <= int(GameState.highest_unlocked_floor)
			var floor_label: String = "Этаж %d — %s" % [floor_number, str(floor_definition.get("name", "Неизвестный этаж"))] if is_unlocked else "Этаж %d — ЗАКРЫТ" % floor_number
			floor_option.add_item(floor_label)
			var option_index: int = floor_option.item_count - 1
			floor_option.set_item_metadata(option_index, floor_number)
			floor_option.set_item_disabled(option_index, not is_unlocked)
			if floor_number == selected_floor_number:
				floor_option.select(option_index)
		floor_option.item_selected.connect(_on_floor_selected)
		floor_row.add_child(floor_option)

		var preparation_row: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()
		preparation_row.add_theme_constant_override("separation", 8)
		launch_box.add_child(preparation_row)
		modifier_option = OptionButton.new()
		_apply_keyboard_focus_outline(modifier_option)
		modifier_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modifier_option.custom_minimum_size.x = 180 if not compact_layout else 0
		for modifier_key in ContentRegistry.RUN_MODIFIERS.keys():
			var modifier_definition: Dictionary = ContentRegistry.RUN_MODIFIERS[modifier_key]
			modifier_option.add_item(str(modifier_definition.get("name", modifier_key)))
			modifier_option.set_item_metadata(modifier_option.item_count - 1, str(modifier_key))
			if str(modifier_key) == selected_modifier_id:
				modifier_option.select(modifier_option.item_count - 1)
		modifier_option.tooltip_text = "Опциональный облик маршрута. Этаж определяет биом, состав врагов и хранителя."
		modifier_option.item_selected.connect(_on_modifier_selected)
		preparation_row.add_child(modifier_option)
		seed_input = LineEdit.new()
		_apply_keyboard_focus_outline(seed_input)
		pending_preview_seed = _make_preview_seed()
		seed_input.placeholder_text = "Seed (0 = случайный)"
		seed_input.tooltip_text = "Введите целое число, чтобы повторить генерацию выбранного этажа."
		seed_input.custom_minimum_size.x = 180 if not compact_layout else 0
		seed_input.text = "0"
		seed_input.text_changed.connect(_on_seed_input_changed)
		preparation_row.add_child(seed_input)
		var contract_row: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()
		contract_row.add_theme_constant_override("separation", 8)
		launch_box.add_child(contract_row)
		contract_row.add_child(_label(_t("base.contract.label"), 12, C_ACCENT, true))
		contract_option = OptionButton.new()
		_apply_keyboard_focus_outline(contract_option)
		contract_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		contract_option.tooltip_text = "Необязательная задача с платой, целью, сроком и дополнительной наградой."
		for contract_key in ContentRegistry.EXPEDITION_CONTRACTS.keys():
			var contract_definition: Dictionary = ContentRegistry.EXPEDITION_CONTRACTS[contract_key]
			contract_option.add_item(str(contract_definition.get("name", contract_key)))
			contract_option.set_item_metadata(contract_option.item_count - 1, str(contract_key))
			if str(contract_key) == selected_contract_id:
				contract_option.select(contract_option.item_count - 1)
		contract_option.item_selected.connect(_on_contract_selected)
		contract_row.add_child(contract_option)
		modifier_preview_label = _label("", 11, C_GOLD, true)
		modifier_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		launch_box.add_child(modifier_preview_label)
		_refresh_modifier_preview()
	if GameState.has_saved_expedition():
		launch_box.add_child(_label(_t("base.saved_run.label"), 12, C_GOLD, true))
		var resume_button := _button(_t("base.button.resume"), Callable(self, "_resume_expedition"), true)
		resume_button.custom_minimum_size = Vector2(0, 56)
		_base_primary_action = resume_button
		launch_box.add_child(resume_button)
		launch_box.add_child(_button(_t("base.button.discard"), Callable(self, "_confirm_discard_saved_run"), false))
	else:
		var start_button := _button(_t("base.button.start"), Callable(self, "_start_expedition"), true)
		start_button.custom_minimum_size = Vector2(0, 56)
		_base_primary_action = start_button
		launch_box.add_child(start_button)
	var armory_button := _button(_t("base.button.armory"), Callable(self, "_open_armory"), false)
	armory_button.disabled = GameState.has_saved_expedition()
	if armory_button.disabled:
		armory_button.text = _t("base.button.armory_after_run")
	launch_box.add_child(armory_button)
	var research_button := _button(_t("base.button.research"), Callable(self, "_open_research_tree"), false)
	research_button.disabled = GameState.has_saved_expedition()
	if research_button.disabled:
		research_button.text = _t("base.button.research_after_run")
	launch_box.add_child(research_button)
	var reassurance := _make_panel(launch_box, Color("#132229"), 12)
	var reassurance_box := VBoxContainer.new()
	reassurance_box.add_theme_constant_override("separation", 4)
	reassurance.add_child(reassurance_box)
	reassurance_box.add_child(_label(_t("base.risk.title"), 12, C_GOLD, true))
	var risk_description := _label(_t("base.risk.description"), 12, C_MUTED)
	risk_description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reassurance_box.add_child(risk_description)
	if GameState.runs_completed == 0:
		var first_session_panel := _make_panel(launch_box, Color("#20362f"), 12)
		var first_session_box := VBoxContainer.new()
		first_session_box.add_theme_constant_override("separation", 5)
		first_session_panel.add_child(first_session_box)
		first_session_box.add_child(_label(_t("base.first_session.title"), 12, C_GOLD, true))
		var first_session_status := _t("base.first_session.start")
		if GameState.has_saved_expedition():
			first_session_status = _t("base.first_session.saved")
		elif GameState.runs_started > 0:
			first_session_status = _t("base.first_session.return")
		var first_session_status_label := _label(first_session_status, 12, C_TEXT)
		first_session_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		first_session_box.add_child(first_session_status_label)
		var after_return_label := _label(_t("base.first_session.after_return"), 12, C_MUTED)
		after_return_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		first_session_box.add_child(after_return_label)
		first_session_box.add_child(_button(_t("base.first_session.help_button"), Callable(self, "_open_help_menu"), false))
	if not GameState.load_notice.is_empty():
		var save_notice_panel := _make_panel(launch_box, Color("#3b2c20"), 10)
		save_notice_panel.add_child(_label(_t("base.save_notice.title") + "\n" + GameState.load_notice, 12, C_GOLD, true))
	var facility_column := VBoxContainer.new()
	facility_column.custom_minimum_size.x = 410 if not compact_layout else 0
	facility_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	facility_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	facility_column.add_theme_constant_override("separation", 8)
	top_row.add_child(facility_column)
	facility_column.add_child(_label(_t("base.infrastructure.title"), 12, C_MUTED, true))
	facility_column.add_child(_label("Пыль утраченных вещей: %d · добывается при вытеснении предметов из полного рюкзака; улучшает Переработчик минералов." % GameState.echo_dust, 11, C_GOLD, true))
	for building_id in ContentRegistry.BUILDINGS.keys():
		_build_building_card(facility_column, str(building_id))
	var bottom_panel := _make_panel(base_content, C_PANEL, 16)
	var bottom_box := VBoxContainer.new()
	bottom_box.add_theme_constant_override("separation", 8)
	bottom_panel.add_child(bottom_box)
	bottom_box.add_child(_label(_t("base.statistics.title"), 12, C_MUTED, true))
	var stats: Container = GridContainer.new() if compact_layout else HBoxContainer.new()
	if stats is GridContainer:
		var stats_grid := stats as GridContainer
		stats_grid.columns = 2
		stats_grid.add_theme_constant_override("h_separation", 8)
		stats_grid.add_theme_constant_override("v_separation", 6)
	else:
		stats.add_theme_constant_override("separation", 20)
	bottom_box.add_child(stats)
	stats.add_child(_label(_t("base.statistics.expeditions") % GameState.runs_completed, 13, C_TEXT, true))
	stats.add_child(_label(_t("base.statistics.victories") % GameState.total_victories, 13, C_TEXT, true))
	stats.add_child(_label(_t("base.statistics.elites_bosses") % [GameState.total_bosses_defeated, GameState.total_elites_defeated], 13, C_TEXT, true))
	stats.add_child(_label(_t("base.statistics.decisions") % GameState.total_events_resolved, 13, C_TEXT, true))
	stats.add_child(_label(_t("base.statistics.best_loop") % GameState.best_loop, 13, C_TEXT, true))
	stats.add_child(_label(_t("base.statistics.buildings") % _total_building_levels(), 13, C_TEXT, true))
	stats.add_child(_label(_t("base.statistics.research") % [GameState.unlocked_nodes.size(), ContentRegistry.BASE_RESEARCH.size()], 13, C_TEXT, true))
	var trophies: Dictionary = GameState.bestiary_trophies
	bottom_box.add_child(_label("Бестиарий трофеев · пыльца %d · призма %d · кости %d · эхо %d" % [int(trophies.get("spore_pollen", 0)), int(trophies.get("prism_fragment", 0)), int(trophies.get("bone_fragment", 0)), int(trophies.get("echo_residue", 0))], 11, C_MUTED))
	bottom_box.add_child(_label("Постоянный ресурс · пыль утраченных вещей: %d / %d" % [GameState.echo_dust, GameState.MAX_ECHO_DUST], 11, C_GOLD, true))
	if not GameState.last_summary.is_empty():
		var last: Dictionary = GameState.last_summary
		var outcome_text := "успешное возвращение" if str(last.get("outcome", "")) == "return" else "поражение"
		bottom_box.add_child(_label("Последняя экспедиция: %s · цикл %d · сохранено %d материалов и %d редких ресурсов." % [outcome_text, int(last.get("loops", 0)), int(last.get("kept_scrap", 0)), int(last.get("kept_crystals", 0))], 12, C_MUTED))
	var history_button := _button(_t("base.button.history") % [GameState.expedition_history.size(), GameState.MAX_EXPEDITION_HISTORY], Callable(self, "_open_expedition_history").bind("all"), false)
	history_button.custom_minimum_size.y = 38
	bottom_box.add_child(history_button)
	_refresh_header()
	var base_focus_target: Control = _base_primary_action
	if floor_option != null:
		base_focus_target = floor_option
	if base_focus_target != null:
		call_deferred("_focus_control_if_valid", base_focus_target)
	if bool(GameState.settings.get("high_contrast", false)):
		_apply_contrast_to_tree(self)

func _open_expedition_history(filter_id: String = "all") -> void:
	_prepare_overlay()
	modal_kind = "campaign_history"
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.03, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := _make_panel(center, Color("#17272e"), 18)
	panel.custom_minimum_size = Vector2(minf(900.0, get_viewport_rect().size.x - 36.0), minf(700.0, get_viewport_rect().size.y - 36.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 9)
	panel.add_child(layout)
	layout.add_child(_label("ЖУРНАЛ КАМПАНИИ", 20, C_TEXT, true))
	layout.add_child(_label("Последние экспедиции · история хранится локально, максимум %d записей. Повторная загрузка не дублирует завершённый забег." % GameState.MAX_EXPEDITION_HISTORY, 11, C_MUTED))
	var return_count := 0
	var defeat_count := 0
	var best_score := 0
	for entry_value in GameState.expedition_history:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		if str(entry.get("outcome", "defeat")) == "return":
			return_count += 1
		else:
			defeat_count += 1
		best_score = maxi(best_score, int(entry.get("challenge_score", 0)))
	layout.add_child(_label("Записей: %d · возвращений: %d · поражений: %d · лучший счёт: %d" % [GameState.expedition_history.size(), return_count, defeat_count, best_score], 12, C_GOLD, true))
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	layout.add_child(filter_row)
	filter_row.add_child(_button("Все", Callable(self, "_open_expedition_history").bind("all"), filter_id == "all"))
	filter_row.add_child(_button("Возвращения", Callable(self, "_open_expedition_history").bind("returns"), filter_id == "returns"))
	filter_row.add_child(_button("Поражения", Callable(self, "_open_expedition_history").bind("defeats"), filter_id == "defeats"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)
	var history_stack := VBoxContainer.new()
	history_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_stack.add_theme_constant_override("separation", 8)
	scroll.add_child(history_stack)
	var entries := GameState.get_expedition_history(filter_id, GameState.MAX_EXPEDITION_HISTORY)
	if entries.is_empty():
		history_stack.add_child(_label("Записей пока нет. Завершите экспедицию, чтобы она появилась здесь.", 13, C_MUTED))
	for entry_value in entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		var is_return := str(entry.get("outcome", "defeat")) == "return"
		var card := _make_panel(history_stack, Color("#1a3035") if is_return else Color("#30282a"), 10)
		var card_box := VBoxContainer.new()
		card_box.add_theme_constant_override("separation", 4)
		card.add_child(card_box)
		var title_text := "%s · этаж %d/8 · %s · цикл %d · ур. %d" % ["ВОЗВРАЩЕНИЕ" if is_return else "ПОРАЖЕНИЕ", int(entry.get("floor_number", 1)), str(entry.get("floor_name", entry.get("difficulty_name", "Этаж"))), int(entry.get("loops", 0)), int(entry.get("hero_level", 1))]
		card_box.add_child(_label(title_text, 13, C_ACCENT if is_return else C_RED, true))
		card_box.add_child(_label("%s · seed %d · v%s · счёт %d" % [str(entry.get("date", "Дата неизвестна")), int(entry.get("seed", 0)), str(entry.get("game_version", "unknown")), int(entry.get("challenge_score", 0))], 10, C_MUTED))
		var endgame_completed := bool(entry.get("endgame_completed", false))
		var history_mode_name := str(entry.get("expedition_mode_name", "Обычная экспедиция"))
		card_box.add_child(_label("Этаж: %s%s" % [str(entry.get("floor_name", history_mode_name)), " · ФИНАЛ КАМПАНИИ" if endgame_completed else (" · ХРАНИТЕЛЬ ПОВЕРЖЕН" if bool(entry.get("floor_cleared", false)) else "")], 10, C_GOLD if endgame_completed or bool(entry.get("floor_cleared", false)) else C_MUTED, endgame_completed or bool(entry.get("floor_cleared", false))))
		card_box.add_child(_label("Победы %d · боссы %d · элиты %d · события %d" % [int(entry.get("victories", 0)), int(entry.get("bosses_defeated", 0)), int(entry.get("elites_defeated", 0)), int(entry.get("events_resolved", 0))], 11, C_TEXT))
		card_box.add_child(_label("Добыча: заработано %d мат. / %d ред. · сохранено %d мат. / %d ред. · потеряно %d мат. / %d ред." % [int(entry.get("earned_scrap", 0)), int(entry.get("earned_crystals", 0)), int(entry.get("kept_scrap", 0)), int(entry.get("kept_crystals", 0)), int(entry.get("lost_scrap", 0)), int(entry.get("lost_crystals", 0))], 10, C_TEXT))
		var detail_parts: Array[String] = []
		if not str(entry.get("objective_name", "")).is_empty():
			detail_parts.append("Цель: %s (%s)" % [str(entry.get("objective_name", "")), "выполнена" if bool(entry.get("objective_completed", false)) else "не выполнена"])
		if not str(entry.get("contract_name", "")).is_empty():
			detail_parts.append("Контракт: %s — %s" % [str(entry.get("contract_name", "")), str(entry.get("contract_status", "active"))])
		var tiles_value: Variant = entry.get("tiles", [])
		if typeof(tiles_value) == TYPE_ARRAY and not tiles_value.is_empty():
			var tile_names := PackedStringArray()
			for tile_name_value in tiles_value:
				tile_names.append(str(tile_name_value))
			detail_parts.append("Тайлы: " + ", ".join(tile_names))
		if not detail_parts.is_empty():
			card_box.add_child(_label("\n".join(detail_parts), 10, C_MUTED))
	layout.add_child(_button("Закрыть журнал", Callable(self, "_close_overlay"), false))
	call_deferred("_configure_overlay_focus", true)

func _total_building_levels() -> int:
	var total := 0
	for level in GameState.buildings.values():
		total += int(level)
	return total

func _build_building_card(parent: Node, building_id: String) -> void:
	var def: Dictionary = ContentRegistry.BUILDINGS[building_id]
	var cost: Dictionary = base_system.get_upgrade_cost(building_id)
	var level := int(GameState.buildings.get(building_id, 0))
	var panel := _make_panel(parent, C_PANEL, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_constant_override("separation", 3)
	row.add_child(description)
	description.add_child(_label(str(def.name), 14, C_TEXT, true))
	description.add_child(_label("Уровень %d / %d" % [level, int(def.max_level)], 11, C_ACCENT))
	description.add_child(_label(str(def.effect), 11, C_MUTED))
	var run_checkpoint_active: bool = GameState.has_saved_expedition()
	var cost_text := "%d мат. · %d ред." % [int(cost.scrap), int(cost.crystals)]
	var echo_dust_cost := int(cost.get("echo_dust", 0))
	if echo_dust_cost > 0:
		cost_text += " · %d пыли" % echo_dust_cost
	var button_text := "ПОСЛЕ ЗАБЕГА" if run_checkpoint_active else ("МАКСИМУМ" if level >= int(def.max_level) else "Улучшить\n" + cost_text)
	var upgrade_button := _button(button_text, Callable(self, "_on_upgrade_pressed").bind(building_id), level < int(def.max_level) and not run_checkpoint_active)
	upgrade_button.custom_minimum_size = Vector2(132, 58)
	upgrade_button.disabled = level >= int(def.max_level) or run_checkpoint_active
	if run_checkpoint_active:
		upgrade_button.tooltip_text = "Сначала завершите или отмените сохранённую экспедицию."
	elif echo_dust_cost > GameState.echo_dust:
		upgrade_button.tooltip_text = "Не хватает пыли утраченных вещей: нужно %d, доступно %d. Вытесненные предметы конвертируются после завершения экспедиции." % [echo_dust_cost, GameState.echo_dust]
	row.add_child(upgrade_button)

func _resume_expedition() -> void:
	if manager.restore_saved_run():
		_render_expedition()
		_sync_expedition_view(true)
	else:
		_open_message("Не удалось восстановить экспедицию", "Сохранённый снимок неполон или несовместим. Можно отказаться от него и начать новый забег.")

func _confirm_discard_saved_run() -> void:
	_show_modal(
		"Отказаться от забега?",
		"Будут удалены только сохранённое состояние текущей экспедиции и её незакреплённая добыча. Постоянные ресурсы, экипировка и улучшения убежища останутся.",
		[
			{"text": "Продолжить сохранённый забег", "callback": Callable(self, "_close_overlay"), "accent": false},
			{"text": "Удалить сохранённый забег", "callback": Callable(self, "_discard_saved_run"), "accent": true}
		],
		"confirm"
	)

func _discard_saved_run() -> void:
	if not GameState.clear_saved_expedition():
		_show_tiny_notice("Не удалось сохранить удаление забега. Контрольная точка сохранена; повторите попытку.")
		return
	_close_overlay(false)
	_render_base()
	_show_tiny_notice("Сохранённый забег удалён. Постоянный прогресс не затронут.")

func _open_research_tree(notice_text: String = "") -> void:
	_prepare_overlay()
	modal_kind = "research"
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.03, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := _make_panel(center, Color("#17272e"), 20)
	panel.custom_minimum_size = Vector2(880, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("ДЕРЕВО ПОСТОЯННОГО РАЗВИТИЯ", 20, C_TEXT, true))
	box.add_child(_label("Исследования сохраняются между экспедициями. Новые узлы требуют выполнения всех зависимостей.", 12, C_MUTED))
	if not notice_text.is_empty():
		box.add_child(_label(notice_text, 12, C_ACCENT, true))
	var resources_label := _label("Доступно: %d материалов · %d редких ресурсов" % [GameState.scrap, GameState.crystals], 12, C_GOLD, true)
	box.add_child(resources_label)
	var reset_preview: Dictionary = base_system.get_research_reset_preview()
	var reset_button := _button("ПЕРЕРАСПРЕДЕЛИТЬ ИССЛЕДОВАНИЯ · ВЕРНУТЬ 80%", Callable(self, "_request_research_reset"), bool(reset_preview.get("ok", false)))
	reset_button.custom_minimum_size.y = 38
	reset_button.disabled = not bool(reset_preview.get("ok", false)) or GameState.has_saved_expedition()
	reset_button.tooltip_text = "Вернётся 80% фактических вложений с округлением вниз; разница удерживается как плата за перераспределение." if bool(reset_preview.get("ok", false)) else str(reset_preview.get("message", "Сброс недоступен."))
	box.add_child(reset_button)
	var research_scroll := ScrollContainer.new()
	research_scroll.custom_minimum_size = Vector2(0, 440)
	research_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	research_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	research_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(research_scroll)
	var branch_stack := VBoxContainer.new()
	branch_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branch_stack.add_theme_constant_override("separation", 12)
	research_scroll.add_child(branch_stack)
	for branch_id_value in ContentRegistry.RESEARCH_BRANCHES.keys():
		var branch_id := str(branch_id_value)
		var branch_status: Dictionary = base_system.get_research_branch_status(branch_id)
		var branch_def: Dictionary = ContentRegistry.RESEARCH_BRANCHES[branch_id_value]
		var branch_panel := _make_panel(branch_stack, Color("#182e34"), 12)
		var branch_box := VBoxContainer.new()
		branch_box.add_theme_constant_override("separation", 6)
		branch_panel.add_child(branch_box)
		var progress_text := "Завершено: %d / %d" % [int(branch_status.get("unlocked_nodes", 0)), int(branch_status.get("total_nodes", 0))]
		if bool(branch_status.get("complete", false)):
			progress_text += " · НАПРАВЛЕНИЕ ЗАВЕРШЕНО"
		branch_box.add_child(_label(str(branch_def.get("name", branch_id)), 15, C_ACCENT, true))
		branch_box.add_child(_label(str(branch_def.get("summary", "")), 11, C_MUTED))
		branch_box.add_child(_label("Стиль: %s · %s" % [str(branch_def.get("style", "")), progress_text], 10, C_GOLD, true))
		var nodes_grid := GridContainer.new()
		nodes_grid.columns = 2
		nodes_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nodes_grid.add_theme_constant_override("h_separation", 10)
		nodes_grid.add_theme_constant_override("v_separation", 10)
		branch_box.add_child(nodes_grid)
		var branch_nodes_value: Variant = branch_def.get("nodes", [])
		if typeof(branch_nodes_value) != TYPE_ARRAY:
			continue
		for research_id_value in branch_nodes_value:
			var research_id := str(research_id_value)
			if not ContentRegistry.BASE_RESEARCH.has(research_id):
				continue
			var definition: Dictionary = ContentRegistry.BASE_RESEARCH[research_id]
			var status: Dictionary = base_system.get_research_status(research_id)
			var card := _make_panel(nodes_grid, Color("#20333a") if bool(status.get("unlocked", false)) else Color("#1b2b32"), 12)
			card.custom_minimum_size = Vector2(390, 150)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var card_box := VBoxContainer.new()
			card_box.add_theme_constant_override("separation", 4)
			card.add_child(card_box)
			var title_text := str(definition.get("name", research_id))
			card_box.add_child(_label(title_text, 14, C_ACCENT if bool(status.get("unlocked", false)) else C_TEXT, true))
			card_box.add_child(_label(str(definition.get("description", "")), 11, C_MUTED))
			card_box.add_child(_label("ЭФФЕКТ: " + str(definition.get("effect_text", "—")), 11, C_GOLD, true))
			var prerequisites_value: Variant = definition.get("prerequisites", [])
			var prerequisite_names: Array[String] = []
			if typeof(prerequisites_value) == TYPE_ARRAY:
				for prerequisite_value in prerequisites_value:
					var prerequisite_id := str(prerequisite_value)
					prerequisite_names.append(str(ContentRegistry.BASE_RESEARCH.get(prerequisite_id, {}).get("name", prerequisite_id)))
			var requirement_text := "Зависимости: нет · открывается сразу" if prerequisite_names.is_empty() else "Зависимости: " + ", ".join(prerequisite_names)
			if not bool(status.get("prerequisites_met", false)):
				var missing_names: Array = status.get("missing", [])
				requirement_text = "ЗАБЛОКИРОВАНО · не изучено: " + ", ".join(missing_names)
			card_box.add_child(_label(requirement_text, 10, C_MUTED))
			var cost_text := "%d мат. · %d ред." % [int(definition.get("scrap_cost", 0)), int(definition.get("crystal_cost", 0))]
			var run_checkpoint_active: bool = GameState.has_saved_expedition()
			var action_text := "ПОСЛЕ ЗАБЕГА" if run_checkpoint_active else ("ИЗУЧЕНО" if bool(status.get("unlocked", false)) else ("ЗАБЛОКИРОВАНО" if not bool(status.get("prerequisites_met", false)) else "ИССЛЕДОВАТЬ · " + cost_text))
			var action_button := _button(action_text, Callable(self, "_on_research_pressed").bind(research_id), bool(status.get("available", false)))
			action_button.custom_minimum_size.y = 36
			action_button.disabled = run_checkpoint_active or bool(status.get("unlocked", false)) or not bool(status.get("prerequisites_met", false)) or not bool(status.get("can_afford", false))
			if not bool(status.get("unlocked", false)) and not bool(status.get("prerequisites_met", false)):
				action_button.tooltip_text = requirement_text
			elif not bool(status.get("can_afford", false)) and not bool(status.get("unlocked", false)):
				action_button.text = "НЕДОСТАТОЧНО РЕСУРСОВ · " + cost_text
			card_box.add_child(action_button)
		var next_preview: Dictionary = branch_status.get("next_preview", {})
		if not next_preview.is_empty() and not bool(branch_status.get("complete", false)):
			var preview_text := "Следующий открываемый узел: %s — %s · %d мат. / %d ред." % [str(next_preview.get("name", "")), str(next_preview.get("effect_text", "—")), int(next_preview.get("scrap_cost", 0)), int(next_preview.get("crystal_cost", 0))]
			if not bool(next_preview.get("available", false)):
				preview_text += " · пока недостаточно ресурсов"
			branch_box.add_child(_label(preview_text, 10, C_MUTED))
		var blocked_count := int(branch_status.get("blocked_count", 0))
		if blocked_count > 0:
			branch_box.add_child(_label("Будущие узлы закрыты, пока не выполнены их условия; причины указаны на карточках.", 10, C_MUTED))
	box.add_child(_button("Закрыть дерево развития", Callable(self, "_close_overlay"), false))
	call_deferred("_configure_overlay_focus", true)

func _on_research_pressed(research_id: String) -> void:
	var result: Dictionary = base_system.try_research(research_id)
	if bool(result.get("ok", false)):
		_open_research_tree(str(result.get("message", "Исследование завершено.")))
	else:
		_open_research_tree(str(result.get("message", "Исследование недоступно.")))

func _request_research_reset() -> void:
	var preview: Dictionary = base_system.get_research_reset_preview()
	if not bool(preview.get("ok", false)) or GameState.has_saved_expedition():
		_open_research_tree(str(preview.get("message", "Перераспределение сейчас недоступно.")))
		return
	var names_value: Variant = preview.get("research_names", [])
	var research_names: Array[String] = []
	if typeof(names_value) == TYPE_ARRAY:
		for name_value in names_value:
			research_names.append(str(name_value))
	var body := "Будут сброшены %d изученных узлов:\n• %s\n\nВложено: %d материалов и %d кристаллов.\nВернётся (80%%, округление вниз): %d материалов и %d кристаллов.\nУдержание за перераспределение: %d материалов и %d кристаллов.\n\nВсе перечисленные постоянные эффекты отключатся. После сброса можно заново выбрать ветку развития. Экипировка, постройки, статистика и история забегов не изменятся." % [int(preview.get("research_count", 0)), "\n• ".join(research_names), int(preview.get("spent_scrap", 0)), int(preview.get("spent_crystals", 0)), int(preview.get("refund_scrap", 0)), int(preview.get("refund_crystals", 0)), int(preview.get("lost_scrap", 0)), int(preview.get("lost_crystals", 0))]
	if bool(preview.get("legacy_price_fallback", false)):
		body += "\n\nПримечание: для исследований из старого сохранения без истории покупки вложения оценены по текущим ценам."
	var preserved_unknown_count := int(preview.get("preserved_unknown_count", 0))
	if preserved_unknown_count > 0:
		body += "\nВременно недоступные узлы (%d) и их история останутся нетронутыми." % preserved_unknown_count
	_show_modal("Перераспределить дерево исследований?", body, [
		{"text": "Отмена", "callback": Callable(self, "_cancel_research_reset"), "accent": false},
		{"text": "Сбросить и вернуть 80%", "callback": Callable(self, "_confirm_research_reset"), "accent": true}
	], "confirm")

func _cancel_research_reset() -> void:
	_open_research_tree()

func _confirm_research_reset() -> void:
	var result: Dictionary = base_system.try_reset_research_tree()
	_open_research_tree(str(result.get("message", "Перераспределение завершено.")))

func _open_armory() -> void:
	var slot_names: Dictionary = InventorySystemScript.SLOT_NAMES
	var equipped_lines: Array[String] = []
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var item_value: Variant = GameState.loadout.get(slot, {})
		var item: Dictionary = item_value if typeof(item_value) == TYPE_DICTIONARY else {}
		var item_level := int(item.get("upgrade_level", 0))
		var level_suffix := " +%d" % item_level if item_level > 0 else ""
		equipped_lines.append("%s: %s%s" % [slot_names.get(slot, slot), str(item.get("name", "пусто")) if not item.is_empty() else "пусто", level_suffix])
	var page_size := 12
	var page_count := maxi(1, ceili(float(GameState.armory.size()) / float(page_size)))
	armory_page_index = clampi(armory_page_index, 0, page_count - 1)
	var first_item := armory_page_index * page_size
	var last_item := mini(GameState.armory.size(), first_item + page_size)
	var body_text := "Материалы: %d · кристаллы: %d\n\nШесть слотов экипировки:\n%s\n\nАрсенал хранит постоянную коллекцию. Выберите предмет, чтобы надеть его, улучшить или разобрать. Страница %d/%d." % [GameState.scrap, GameState.crystals, "\n".join(equipped_lines), armory_page_index + 1, page_count]
	var buttons: Array = []
	var comparison_lines: Array[String] = []
	for i in range(first_item, last_item):
		var item_value: Variant = GameState.armory[i]
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		var comparison := _format_item_comparison(item)
		var upgrade_level := int(item.get("upgrade_level", 0))
		var level_suffix := " · +%d" % upgrade_level if upgrade_level > 0 else ""
		if i >= maxi(first_item, last_item - 3):
			comparison_lines.append("%s%s — %s; набор %s." % [str(item.get("name", "Предмет")), level_suffix, _format_item_bonus(item), str(item.get("set_name", "без набора"))])
		var text_value := "%02d · %s%s · %s" % [i + 1, str(item.get("name", "Предмет")), level_suffix, comparison]
		buttons.append({"text": text_value, "callback": Callable(self, "_open_armory_item").bind(str(item.get("id", ""))), "accent": false})
	if not comparison_lines.is_empty():
		body_text += "\n\nНесколько предметов этой страницы:\n" + "\n".join(comparison_lines)
	body_text += "\n\nНаборы: " + " · ".join(inventory_system.set_summary(GameState.loadout))
	var current_gear_stats: Dictionary = inventory_system.total_equipment_stats(GameState.loadout)
	var active_gear_synergies: Array = current_gear_stats.get("active_synergies", [])
	body_text += "\nСинергии: " + (_format_value_list(active_gear_synergies) if not active_gear_synergies.is_empty() else "пока нет — сочетайте архетипы разных слотов")
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var equipped_value: Variant = GameState.loadout.get(slot, {})
		if typeof(equipped_value) == TYPE_DICTIONARY and not equipped_value.is_empty():
			buttons.append({"text": "Снять: %s" % slot_names.get(slot, slot), "callback": Callable(self, "_unequip_armory_slot").bind(slot), "accent": false})
	if page_count > 1:
		buttons.append({"text": "← Предыдущая страница", "callback": Callable(self, "_change_armory_page").bind(-1), "accent": false, "disabled": armory_page_index <= 0})
		buttons.append({"text": "Следующая страница →", "callback": Callable(self, "_change_armory_page").bind(1), "accent": false, "disabled": armory_page_index >= page_count - 1})
	buttons.append({"text": "Закрыть", "callback": Callable(self, "_close_overlay"), "accent": true})
	if GameState.armory.is_empty():
		body_text += "\n\nАрсенал пока пуст. Предметы выпадают с противников; найденное в экспедиции сначала попадает в рюкзак и не надевается автоматически."
	_show_modal("Арсенал убежища", body_text, buttons, "armory")

func _change_armory_page(delta: int) -> void:
	var page_count := maxi(1, ceili(float(GameState.armory.size()) / 12.0))
	armory_page_index = clampi(armory_page_index + delta, 0, page_count - 1)
	_open_armory()


func _open_armory_item(item_id: String) -> void:
	var item: Dictionary = GameState.get_armory_item(item_id)
	if item.is_empty():
		_open_message("Предмет не найден", "Он мог быть уже разобран или удалён из арсенала.")
		return
	var slot_names: Dictionary = InventorySystemScript.SLOT_NAMES
	var upgrade_level := int(item.get("upgrade_level", 0))
	var equipped: bool = GameState.is_item_equipped(item_id)
	var upgrade_cost: Dictionary = inventory_system.get_upgrade_cost(item)
	var preview_item: Dictionary = inventory_system.preview_upgrade_item(item)
	var preview_text := _format_item_bonus(preview_item) if not preview_item.is_empty() else "улучшение недоступно"
	var build_preview := _format_loadout_synergy_preview(item)
	var body_text := "%s · %s\nСлот: %s · ранг добычи: %d · улучшение: +%d/%d\nСила предмета: %.1f\n\nСейчас: %s\nПосле улучшения: %s\n\nСвойство: %s\nНабор: %s\n\n%s\n\nСостояние: %s\nРесурсы: %d материалов, %d кристаллов." % [str(item.get("name", "Предмет")), str(item.get("rarity", "Обычный")), str(slot_names.get(str(item.get("slot", "")), "Неизвестный слот")), int(item.get("rank", 1)), upgrade_level, InventorySystemScript.MAX_UPGRADE_LEVEL, inventory_system.item_power(item), _format_item_bonus(item), preview_text, str(item.get("archetype_description", "Базовые характеристики")), str(item.get("set_name", "без набора")), build_preview, "Экипирован — разбор заблокирован" if equipped else "В арсенале", GameState.scrap, GameState.crystals]
	if bool(item.get("is_boss_relic", false)):
		body_text += "\n\nРеликвия босса: %s. Именная экипировка масштабируется от достигнутого цикла и относится к набору «%s»." % [str(item.get("source_enemy_name", "неизвестный босс")), str(item.get("set_name", "без набора"))]
	var affix_detail := str(item.get("affix_description", ""))
	if not affix_detail.is_empty():
		body_text += "\n\nМодификаторы предмета: " + affix_detail
	if bool(item.get("is_secret_relic", false)):
		body_text += "\n\nТайная реликвия: получена за раскрытие скрытого события. Её набор и бонусы сохраняются в арсенале между экспедициями."
	if not str(item.get("landscape_affinity", "")).is_empty():
		body_text += "\n\nСвязь с ландшафтом: %s. При проходе через этот участок активируется эффект %s." % [str(item.get("affinity_name", item.get("landscape_affinity", ""))), str(item.get("affinity_effect", {}))]
	var buttons: Array = []
	buttons.append({"text": "Надеть предмет", "callback": Callable(self, "_equip_armory_item").bind(item_id), "accent": true, "disabled": equipped})
	if bool(upgrade_cost.get("available", false)):
		var can_afford: bool = GameState.scrap >= int(upgrade_cost.get("scrap", 0)) and GameState.crystals >= int(upgrade_cost.get("crystals", 0))
		var next_bonus := preview_text
		var upgrade_text := "Улучшить до +%d · %d мат. / %d кр." % [int(upgrade_cost.get("next_level", upgrade_level + 1)), int(upgrade_cost.get("scrap", 0)), int(upgrade_cost.get("crystals", 0))]
		buttons.append({"text": upgrade_text, "callback": Callable(self, "_upgrade_armory_item").bind(item_id), "accent": false, "disabled": not can_afford or GameState.has_saved_expedition(), "tooltip": "После улучшения: " + next_bonus + ("\nНе хватает ресурсов." if not can_afford else "")})
	else:
		buttons.append({"text": "Максимальный уровень улучшения", "callback": Callable(self, "_close_overlay"), "accent": false, "disabled": true})
	var salvage_reward: Dictionary = inventory_system.get_salvage_reward(item)
	var salvage_text := "Разобрать · +%d мат. / +%d кр." % [int(salvage_reward.get("scrap", 0)), int(salvage_reward.get("crystals", 0))]
	buttons.append({"text": salvage_text, "callback": Callable(self, "_request_salvage_item").bind(item_id), "accent": false, "disabled": equipped or GameState.has_saved_expedition(), "tooltip": "Разбор необратим. Экипировку сначала нужно снять." if equipped else "Перед разбором появится дополнительное подтверждение."})
	buttons.append({"text": "← Назад в арсенал", "callback": Callable(self, "_open_armory"), "accent": false})
	_show_modal("Управление предметом", body_text, buttons, "armory_item")

func _format_value_list(values: Array) -> String:
	return ItemTextPresenterScript.format_value_list(values)

func _format_loadout_synergy_preview(candidate_item: Dictionary) -> String:
	var slot := str(candidate_item.get("slot", ""))
	if not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
		return "Синергия: неизвестный слот предмета."
	var current_stats: Dictionary = inventory_system.total_equipment_stats(GameState.loadout)
	var candidate_loadout: Dictionary = GameState.loadout.duplicate(true)
	candidate_loadout[slot] = candidate_item.duplicate(true)
	var candidate_stats: Dictionary = inventory_system.total_equipment_stats(candidate_loadout)
	return ItemTextPresenterScript.format_loadout_synergy_preview(current_stats, candidate_stats, InventorySystemScript.SYNERGY_DEFS)

func _request_salvage_item(item_id: String) -> void:
	var item: Dictionary = GameState.get_armory_item(item_id)
	if item.is_empty():
		_open_message("Предмет не найден", "Арсенал уже изменился. Обновите список предметов.")
		return
	if GameState.is_item_equipped(item_id):
		_open_message("Разбор запрещён", "Этот предмет надет. Сначала снимите его с героя, чтобы защитить экипировку от случайного уничтожения.")
		return
	var reward: Dictionary = inventory_system.get_salvage_reward(item)
	var body_text := "Вы собираетесь необратимо разобрать «%s».\n\nБудет получено: %d материалов и %d кристаллов.\nПредмет и его улучшения исчезнут из арсенала. Отменить разбор после подтверждения нельзя." % [str(item.get("name", "Предмет")), int(reward.get("scrap", 0)), int(reward.get("crystals", 0))]
	_show_modal("Подтвердить разбор предмета", body_text, [
		{"text": "Разобрать предмет", "callback": Callable(self, "_salvage_armory_item").bind(item_id), "accent": true},
		{"text": "Отмена", "callback": Callable(self, "_open_armory_item").bind(item_id), "accent": false}
	], "confirm_salvage")

func _upgrade_armory_item(item_id: String) -> void:
	var result: Dictionary = GameState.upgrade_armory_item(item_id)
	if not bool(result.get("ok", false)):
		_open_message("Улучшение не выполнено", str(result.get("message", "Неизвестная ошибка.")))
		return
	_render_base()
	_open_armory_item(item_id)
	_show_tiny_notice(str(result.get("message", "Предмет улучшен.")))

func _salvage_armory_item(item_id: String) -> void:
	var result: Dictionary = GameState.salvage_armory_item(item_id)
	if not bool(result.get("ok", false)):
		_open_message("Разбор не выполнен", str(result.get("message", "Неизвестная ошибка.")))
		return
	_render_base()
	_open_armory()
	_show_tiny_notice(str(result.get("message", "Предмет разобран.")))

func _format_item_comparison(item: Dictionary) -> String:
	var slot := str(item.get("slot", ""))
	var current_value: Variant = GameState.loadout.get(slot, {})
	var current: Dictionary = current_value if typeof(current_value) == TYPE_DICTIONARY else {}
	if current.is_empty():
		return ItemTextPresenterScript.format_item_comparison(false, 0.0)
	var delta := inventory_system.item_power(item) - inventory_system.item_power(current)
	return ItemTextPresenterScript.format_item_comparison(true, delta)

func _format_item_bonus(item: Dictionary) -> String:
	return ItemTextPresenterScript.format_item_bonus(item)

func _equip_armory_item(item_id: String) -> void:
	_close_overlay(false)
	if GameState.equip_item(item_id):
		_render_base()
		_show_tiny_notice("Предмет экипирован и сохранён.")
	else:
		_open_message("Не удалось экипировать", "Предмет не найден в арсенале.")

func _unequip_armory_slot(slot: String) -> void:
	_close_overlay(false)
	GameState.unequip_slot(slot)
	_render_base()
	_show_tiny_notice("Слот освобождён.")

func _on_upgrade_pressed(building_id: String) -> void:
	var result: Dictionary = base_system.try_upgrade(building_id)
	if bool(result.ok):
		_render_base()
		_show_tiny_notice(str(result.message))
	else:
		_open_message("Улучшение недоступно", str(result.message))

func _on_floor_selected(index: int) -> void:
	if floor_option == null or index < 0 or index >= floor_option.item_count:
		selected_floor_number = clampi(GameState.highest_unlocked_floor, 1, ContentRegistry.FLOOR_COUNT)
	else:
		selected_floor_number = clampi(int(floor_option.get_item_metadata(index)), 1, int(GameState.highest_unlocked_floor))
	_refresh_modifier_preview()

func _on_modifier_selected(index: int) -> void:
	if modifier_option == null or index < 0 or index >= modifier_option.item_count:
		selected_modifier_id = "standard"
		_refresh_modifier_preview()
		return
	selected_modifier_id = str(modifier_option.get_item_metadata(index))
	_refresh_modifier_preview()

func _on_seed_input_changed(_new_text: String) -> void:
	_refresh_modifier_preview()

func _on_contract_selected(index: int) -> void:
	if contract_option == null or index < 0 or index >= contract_option.item_count:
		selected_contract_id = "none"
	else:
		selected_contract_id = str(contract_option.get_item_metadata(index))
	_refresh_modifier_preview()

func _make_preview_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi_range(1, 2147483000)

func _get_preview_seed() -> int:
	if seed_input != null:
		var text_value := seed_input.text.strip_edges()
		if not text_value.is_empty() and text_value.is_valid_int():
			var requested := int(text_value)
			if requested > 0:
				return requested
	return pending_preview_seed if pending_preview_seed > 0 else 1

func _refresh_modifier_preview() -> void:
	if modifier_preview_label == null or not is_instance_valid(modifier_preview_label):
		return
	var modifier: Dictionary = ContentRegistry.RUN_MODIFIERS.get(selected_modifier_id, ContentRegistry.RUN_MODIFIERS["standard"])
	var safe_floor: int = clampi(selected_floor_number, 1, ContentRegistry.FLOOR_COUNT)
	var floor_definition: Dictionary = ContentRegistry.FLOOR_DEFS[safe_floor - 1]
	var boss_id: String = str(floor_definition.get("boss_id", ""))
	var boss_definition: Dictionary = ContentRegistry.BOSSES.get(boss_id, {})
	var preview := "ЭТАЖ %d/8: %s" % [safe_floor, str(floor_definition.get("name", "Этаж"))]
	preview += "\n%s" % str(floor_definition.get("description", ""))
	preview += "\nБиом: %s · хранитель: %s · цикл босса: %d." % [str(floor_definition.get("biome", "Неизвестно")), str(boss_definition.get("name", boss_id)), int(floor_definition.get("boss_loop", 3))]
	preview += "\nПосле победы над хранителем добыча сохраняется, а следующий этаж открывается. На восьмом этаже находится финальный хранитель."
	preview += "\nОблик маршрута: %s — %s" % [str(modifier.get("name", "Обычный")), str(modifier.get("description", ""))]
	var challenge_value: Variant = modifier.get("challenge", {})
	if typeof(challenge_value) == TYPE_DICTIONARY and not challenge_value.is_empty():
		preview += " Испытание: %s; награда +%d материалов и +%d редких ресурсов." % [str(challenge_value.get("name", "Испытание")), int(challenge_value.get("scrap_reward", 0)), int(challenge_value.get("crystal_reward", 0))]
	var objective_preview: Dictionary = manager.preview_objective_for_seed(_get_preview_seed(), selected_modifier_id)
	if not objective_preview.is_empty():
		preview += "\nАВТОЦЕЛЬ ЭКСПЕДИЦИИ (по seed): %s. Условие: %s. Награда: +%d материалов и +%d редких ресурсов. Seed: %d." % [str(objective_preview.get("name", "Экспедиция")), str(objective_preview.get("description", "")), int(objective_preview.get("scrap_reward", 0)), int(objective_preview.get("crystal_reward", 0)), _get_preview_seed()]
	var contract_definition: Dictionary = ContentRegistry.EXPEDITION_CONTRACTS.get(selected_contract_id, ContentRegistry.EXPEDITION_CONTRACTS["none"])
	if selected_contract_id != "none":
		var affordability: Dictionary = manager.can_accept_contract(selected_contract_id)
		var afford_text := "" if bool(affordability.get("ok", false)) else " НЕДОСТАТОЧНО РЕСУРСОВ: " + str(affordability.get("reason", ""))
		preview += "\nКОНТРАКТ: %s. %s. Плата: %d материалов / %d редких ресурсов. Срок: до цикла %d. Награда: +%d материалов / +%d редких ресурсов.%s" % [str(contract_definition.get("name", "Контракт")), str(contract_definition.get("description", "")), int(contract_definition.get("scrap_cost", 0)), int(contract_definition.get("crystal_cost", 0)), int(contract_definition.get("deadline_loops", 0)), int(contract_definition.get("scrap_reward", 0)), int(contract_definition.get("crystal_reward", 0)), afford_text]
	else:
		preview += "\nКонтракт не выбран: стоимость 0, никаких дополнительных требований."
	preview += "\nЕсли поле Seed = 0, будет использован показанный seed — цель совпадёт с фактической целью забега."
	modifier_preview_label.text = preview

func _start_expedition() -> void:
	var requested_seed := 0
	if seed_input != null and not seed_input.text.strip_edges().is_empty():
		if seed_input.text.strip_edges().is_valid_int():
			requested_seed = maxi(0, int(seed_input.text.strip_edges()))
		else:
			_open_message("Некорректный seed", "Введите целое неотрицательное число или оставьте 0 для случайной генерации.")
			return
	if requested_seed <= 0:
		requested_seed = _get_preview_seed()
	var acceptance: Dictionary = manager.can_accept_contract(selected_contract_id)
	if not bool(acceptance.get("ok", false)):
		_open_message("Контракт недоступен", str(acceptance.get("reason", "Недостаточно ресурсов.")))
		return
	if not manager.start_run("standard", requested_seed, selected_modifier_id, selected_contract_id, "standard", selected_floor_number):
		_open_message("Не удалось начать экспедицию", "Начальное состояние и плата не сохранены. Проверьте свободное место для сохранения и повторите попытку.")
		return
	_render_expedition()

func _render_expedition() -> void:
	var compact_layout := _is_compact_layout()
	_first_hour_guide_signature = ""
	if is_instance_valid(overlay) and overlay.visible:
		_close_overlay(false)
	_focus_before_overlay = null
	screen_mode = "expedition"
	_set_phase("ЭКСПЕДИЦИЯ")
	_clear_screen()
	var expedition_root: VBoxContainer = content_root
	if compact_layout:
		var expedition_scroll := ScrollContainer.new()
		expedition_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		expedition_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		expedition_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		expedition_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		content_root.add_child(expedition_scroll)
		expedition_root = VBoxContainer.new()
		expedition_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		expedition_root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		expedition_root.add_theme_constant_override("separation", 8)
		expedition_scroll.add_child(expedition_root)
	var metrics_row: Container = GridContainer.new() if compact_layout else HBoxContainer.new()
	metrics_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if metrics_row is GridContainer:
		var metrics_grid := metrics_row as GridContainer
		metrics_grid.columns = 2
		metrics_grid.add_theme_constant_override("h_separation", 6)
		metrics_grid.add_theme_constant_override("v_separation", 6)
	else:
		metrics_row.add_theme_constant_override("separation", 8)
	expedition_root.add_child(metrics_row)
	_add_metric(metrics_row, "ЗДОРОВЬЕ", "—", "hp")
	_add_metric(metrics_row, "УРОВЕНЬ / ОПЫТ", "—", "level")
	_add_metric(metrics_row, "ЦИКЛ / УЗЕЛ", "—", "loop")
	_add_metric(metrics_row, "УГРОЗА / ДОБЫЧА", "—", "risk")
	objective_label = _label("ЦЕЛЬ ЭКСПЕДИЦИИ", 12, C_GOLD, true)
	expedition_root.add_child(objective_label)
	challenge_label = _label("", 12, C_ACCENT, true)
	challenge_label.visible = false
	expedition_root.add_child(challenge_label)
	contract_label = _label("", 12, C_GOLD, true)
	contract_label.visible = false
	expedition_root.add_child(contract_label)
	var body: BoxContainer = VBoxContainer.new() if compact_layout else HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if compact_layout else Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8 if compact_layout else 12)
	expedition_root.add_child(body)
	var map_panel := _make_panel(body, Color("#132127"), 14)
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.size_flags_stretch_ratio = 1.65
	map_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if compact_layout else Control.SIZE_EXPAND_FILL
	map_panel.custom_minimum_size.y = 350 if compact_layout else 0
	var map_box := VBoxContainer.new()
	map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_box.add_theme_constant_override("separation", 8)
	map_panel.add_child(map_box)
	var map_header := HBoxContainer.new()
	map_box.add_child(map_header)
	var map_title_box := VBoxContainer.new()
	map_title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_header.add_child(map_title_box)
	map_title_box.add_child(_label(_t("expedition.map.title"), 13, C_ACCENT, true))
	map_title_box.add_child(_label("Этаж %d/8 · %s · %s · seed %d · замкнутый маршрут." % [int(manager.floor_number), manager.get_floor_name(), str(manager.get_floor_config().get("biome", "")), int(manager.run_seed)], 11, C_MUTED))
	fight_status_label = _label(_t("expedition.hero_moving"), 13, C_TEXT, true)
	fight_status_label.visible = not compact_layout
	map_header.add_child(fight_status_label)
	route_view = RouteViewScript.new()
	route_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	route_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_view.cell_clicked.connect(_on_route_cell_clicked)
	route_view.cell_hovered.connect(_on_route_cell_hovered)
	route_view.world_cell_clicked.connect(_on_world_cell_clicked)
	route_view.world_cell_hovered.connect(_on_world_cell_hovered)
	map_box.add_child(route_view)
	route_view.call("configure_compact_layout", compact_layout)
	# Keep the map canvas and its own route-footer prompt clear. The longer
	# placement instruction lives in the tile panel, away from route-node hit areas.
	route_hint_label = _label(_t("expedition.route_hint"), 10, C_MUTED)
	route_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label = _label("", 11, C_GOLD)
	map_box.add_child(notice_label)
	first_hour_guide_panel = _make_panel(map_box, Color("#20362f"), 10)
	var first_hour_guide_box := VBoxContainer.new()
	first_hour_guide_box.add_theme_constant_override("separation", 3)
	first_hour_guide_panel.add_child(first_hour_guide_box)
	first_hour_guide_box.add_child(_label(_t("onboarding.first_run.title"), 10, C_GOLD, true))
	first_hour_guide_label = _label("", 11, C_TEXT)
	first_hour_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	first_hour_guide_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	first_hour_guide_box.add_child(first_hour_guide_label)
	first_hour_guide_panel.visible = false
	var right_column := VBoxContainer.new()
	right_column.custom_minimum_size.x = 334 if not compact_layout else 0
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_column.add_theme_constant_override("separation", 8)
	if compact_layout:
		# The outer expedition scroll owns vertical movement on phone-sized displays.
		body.add_child(right_column)
	else:
		var right_scroll := ScrollContainer.new()
		right_scroll.custom_minimum_size.x = 354
		right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		right_scroll.size_flags_horizontal = Control.SIZE_SHRINK_END
		right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(right_scroll)
		right_scroll.add_child(right_column)
	var control_panel := _make_panel(right_column, C_PANEL, 14)
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	control_panel.add_child(controls)
	controls.add_child(_label(_t("expedition.controls.title"), 12, C_MUTED, true))
	controls.add_child(_label(_t("expedition.controls.target_health"), 12, C_MUTED))
	fight_health_bar = ProgressBar.new()
	fight_health_bar.custom_minimum_size.y = 10
	fight_health_bar.min_value = 0
	fight_health_bar.max_value = 100
	fight_health_bar.value = 0
	fight_health_bar.show_percentage = false
	controls.add_child(fight_health_bar)
	status_effects_label = _label(_t("expedition.controls.no_effects"), 12, C_MUTED)
	status_effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_effects_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_effects_label.tooltip_text = "Временные эффекты героя и текущей цели: длительность, стаки и влияние на бой."
	controls.add_child(status_effects_label)
	pause_button = _button(_t("expedition.controls.pause"), Callable(self, "_toggle_pause"), false)
	controls.add_child(pause_button)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	controls.add_child(speed_row)
	for speed_value in [1.0, 2.0, 3.0]:
		var speed_button := _button("%.0fx" % speed_value, Callable(self, "_set_speed").bind(speed_value), false)
		speed_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speed_row.add_child(speed_button)
	speed_label = _label(_t("expedition.speed.label"), 12, C_MUTED)
	controls.add_child(speed_label)
	return_button = _button(_t("expedition.controls.return"), Callable(self, "_request_return"), true)
	controls.add_child(return_button)
	var tile_panel := _make_panel(right_column, C_PANEL, 12)
	var tile_box := VBoxContainer.new()
	tile_box.add_theme_constant_override("separation", 6)
	tile_panel.add_child(tile_box)
	tile_box.add_child(_label(_t("expedition.tiles.title"), 12, C_MUTED, true))
	tile_box.add_child(_label(_t("expedition.tiles.description"), 12, C_MUTED))
	tile_box.add_child(route_hint_label)
	tile_hand_grid = GridContainer.new()
	tile_hand_grid.columns = 2
	tile_hand_grid.add_theme_constant_override("h_separation", 6)
	tile_hand_grid.add_theme_constant_override("v_separation", 6)
	tile_box.add_child(tile_hand_grid)
	tile_exchange_button = _button("ПЕРЕПИСАТЬ КАРТУ · 1 КРИСТАЛЛ", Callable(self, "_on_exchange_selected_tile"), false)
	tile_exchange_button.custom_minimum_size.y = 36
	tile_exchange_button.tooltip_text = "Выберите карту в руке: за 1 кристалл можно заменить её другой картой один раз за цикл. Во время боя и события недоступно."
	tile_box.add_child(tile_exchange_button)
	loot_preparation_label = _label("Подготовка добычи: нет активных бонусов.", 11, C_GOLD)
	loot_preparation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loot_preparation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loot_preparation_label.tooltip_text = "Подготовленные бонусы выпадают только после успешной обычной или элитной находки. Боссовые реликвии не расходуют эту подготовку."
	tile_box.add_child(loot_preparation_label)
	tile_preview_label = _label(_t("expedition.tiles.preview_title") + "\n" + _t("expedition.tiles.preview_description"), 12, C_MUTED)
	tile_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tile_preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile_preview_label.custom_minimum_size.x = 285 if not compact_layout else 0
	tile_box.add_child(tile_preview_label)
	expedition_gear_panel = _make_panel(right_column, C_PANEL, 12)
	expedition_gear_panel.visible = false
	var gear_box := VBoxContainer.new()
	gear_box.add_theme_constant_override("separation", 5)
	expedition_gear_panel.add_child(gear_box)
	gear_box.add_child(_label(_t("expedition.equipment.title"), 12, C_MUTED, true))
	equipment_label = _label("", 12, C_TEXT)
	equipment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	equipment_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equipment_label.tooltip_text = "Сводка текущих предметов, характеристик, наборов и активных синергий. Прокрутите правую панель, если текст не помещается по высоте."
	gear_box.add_child(equipment_label)
	backpack_button = _button("РЮКЗАК · 0/12", Callable(self, "_open_run_backpack"), true)
	backpack_button.custom_minimum_size.y = 40
	backpack_button.tooltip_text = "Открыть 12 ячеек рюкзака, 6 ячеек походного тайника и шесть слотов экипировки. Переполнение не теряется: предметы сохраняются в походном тайнике или постоянном арсенале. Открытие приостанавливает экспедицию."
	gear_box.add_child(backpack_button)
	var log_panel := _make_panel(right_column, C_PANEL, 12)
	var log_box := VBoxContainer.new()
	log_box.add_theme_constant_override("separation", 4)
	log_panel.add_child(log_box)
	log_box.add_child(_label(_t("expedition.log.title"), 12, C_MUTED, true))
	log_scroll = ScrollContainer.new()
	log_scroll.custom_minimum_size.y = 104
	log_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_box.add_child(log_scroll)
	log_label = _label("", 11, C_MUTED)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_label.custom_minimum_size.x = 285 if not compact_layout else 0
	log_scroll.add_child(log_label)
	_sync_expedition_view(true)
	if pause_button != null:
		call_deferred("_focus_control_if_valid", pause_button)
	if bool(GameState.settings.get("high_contrast", false)):
		_apply_contrast_to_tree(self)

func _add_metric(parent: Node, title_text: String, value_text: String, key: String) -> void:
	var panel := _make_panel(parent, C_PANEL, 12)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	panel.add_child(box)
	box.add_child(_label(title_text, 12, C_MUTED, true))
	var value := _label(value_text, 17, C_TEXT, true)
	box.add_child(value)
	exp_metrics[key] = value

func _on_feedback_requested(kind: String, message: String) -> void:
	if screen_mode == "expedition" and is_instance_valid(route_view) and route_view.has_method("show_feedback"):
		route_view.show_feedback(kind, message)
	if feedback_system != null and is_instance_valid(feedback_system):
		feedback_system.play_feedback(kind)

func _sync_expedition_view(rebuild_tiles: bool) -> void:
	if screen_mode != "expedition" or manager == null or not is_instance_valid(manager):
		return
	if not is_instance_valid(route_view):
		return
	if route_view.has_method("configure_accessibility"):
		route_view.configure_accessibility(bool(GameState.settings.get("reduced_motion", false)), bool(GameState.settings.get("reduce_flashes", true)), bool(GameState.settings.get("high_contrast", false)), float(GameState.settings.get("animation_speed", 1.0)))
	var selected_tile_id := ""
	if selected_tile_hand_index >= 0 and selected_tile_hand_index < manager.tile_hand.size():
		selected_tile_id = str(manager.tile_hand[selected_tile_hand_index].get("name", "тайл"))
	var current_is_boss: bool = not manager.enemy.is_empty() and bool(manager.enemy.get("is_boss", false))
	var current_is_elite: bool = not manager.enemy.is_empty() and bool(manager.enemy.get("is_elite", false))
	route_view.configure(manager.route, manager.hero_progress_for_draw(), manager.placed_tiles, int(manager.combat_cell), selected_tile_hand_index >= 0, selected_tile_id, current_is_boss, manager.get_route_shape_id(), manager.world_tiles, current_is_elite, _get_tile_placement_block_reason().is_empty(), manager.get_route_geometry_seed(), manager.discovered_world_cells)
	# Equipment and backpack controls are contextual battle tools, not permanent map clutter.
	if is_instance_valid(expedition_gear_panel):
		expedition_gear_panel.visible = not manager.enemy.is_empty()
	if objective_label != null:
		var objective: Dictionary = manager.run_objective
		if not objective.is_empty():
			var objective_state := "ВЫПОЛНЕНО" if bool(objective.get("completed", false)) else "В ПРОЦЕССЕ"
			objective_label.text = "ЦЕЛЬ: %s · %d/%d · %s · награда +%d материалов / +%d редких" % [str(objective.get("name", "Экспедиция")), int(objective.get("progress", 0)), int(objective.get("target", 1)), objective_state, int(objective.get("scrap_reward", 0)), int(objective.get("crystal_reward", 0))]
			objective_label.tooltip_text = str(objective.get("description", "")) + "\nНаграда выдаётся один раз при достижении условия."
	var challenge: Dictionary = manager.run_challenge
	if challenge_label != null:
		if challenge.is_empty():
			challenge_label.visible = false
		else:
			challenge_label.visible = true
			var challenge_state := "ВЫПОЛНЕНО" if bool(challenge.get("completed", false)) else "В ПРОЦЕССЕ"
			challenge_label.text = "ИСПЫТАНИЕ: %s · %d/%d · %s" % [str(challenge.get("name", "Испытание")), int(challenge.get("progress", 0)), int(challenge.get("target", 1)), challenge_state]
	if contract_label != null:
		var contract: Dictionary = manager.run_contract
		if contract.is_empty():
			contract_label.visible = false
		else:
			contract_label.visible = true
			var contract_state := "ПРОВАЛЕН" if bool(contract.get("failed", false)) else ("ВЫПОЛНЕН" if bool(contract.get("completed", false)) else "В ПРОЦЕССЕ")
			contract_label.text = "КОНТРАКТ: %s · %d/%d · до цикла %d · %s" % [str(contract.get("name", "Контракт")), int(contract.get("progress", 0)), int(contract.get("target", 0)), int(contract.get("deadline_loops", 0)), contract_state]
			contract_label.tooltip_text = str(contract.get("description", "")) + "\nПлата уже списана при начале забега; провал контракта не отнимает дополнительных ресурсов."
	if status_effects_label != null:
		var show_status_symbols := bool(GameState.settings.get("status_symbols", true))
		var status_lines: Array[String] = [status_effect_presenter.format_line(manager.status_effect_system, manager.hero, "ГЕРОЙ", 3, show_status_symbols)]
		if not manager.enemy.is_empty():
			status_lines.append(status_effect_presenter.format_line(manager.status_effect_system, manager.enemy, "ЦЕЛЬ", 3, show_status_symbols))
		status_effects_label.text = "\n".join(status_lines)
	if exp_metrics.has("hp"):
		var hp_text := "%d / %d" % [int(manager.hero.get("hp", 0)), int(manager.hero.get("max_hp", 0))]
		var level_text := "Ур. %d · %d/%d XP" % [int(manager.hero.get("level", 1)), int(manager.hero.get("xp", 0)), int(manager.hero.get("xp_next", 16))]
		var loop_text := "Этаж %d/8 · цикл %d · узел %d/%d" % [int(manager.floor_number), int(manager.loop_count), int(manager.current_cell()) + 1, manager.route.size()]
		var risk_text := "x%.1f · %d мат." % [float(manager.danger), int(manager.run_ledger.get("scrap", 0))]
		if exp_metrics.hp.text != hp_text: exp_metrics.hp.text = hp_text
		if exp_metrics.level.text != level_text: exp_metrics.level.text = level_text
		if exp_metrics.loop.text != loop_text: exp_metrics.loop.text = loop_text
		if exp_metrics.risk.text != risk_text: exp_metrics.risk.text = risk_text
	if not manager.enemy.is_empty():
		var current_enemy_name := str(manager.enemy.get("name", "Противник"))
		var current_enemy_role := str(manager.enemy.get("role", ""))
		var role_label := _enemy_role_label(current_enemy_role)
		var behavior_hint := str(manager.enemy.get("behavior_hint", ""))
		fight_status_label.tooltip_text = behavior_hint
		if bool(manager.enemy.get("is_boss", false)):
			fight_status_label.text = "[БОСС] · %s · %s" % [current_enemy_name, str(manager.enemy.get("phase_name", "Фаза 1"))]
			if bool(manager.enemy.get("telegraph_pending", false)):
				fight_status_label.text += " · ГОТОВИТ УДАР"
		elif bool(manager.enemy.get("is_elite", false)):
			fight_status_label.text = "[ЭЛИТА · %s] · %s · %s" % [role_label, current_enemy_name, str(manager.enemy.get("elite_ability", "особая атака"))]
			if bool(manager.enemy.get("telegraph_pending", false)):
				fight_status_label.text += " · ГОТОВИТ УДАР"
		else:
			fight_status_label.text = "[%s] · БОЙ · %s" % [role_label, current_enemy_name]
		if manager.encounter_enemies.size() > 1:
			fight_status_label.text += " · врагов: %d" % manager.encounter_enemies.size()
		if fight_health_bar != null:
			fight_health_bar.visible = true
			fight_health_bar.max_value = maxf(1.0, float(manager.enemy.get("max_hp", 1)))
			fight_health_bar.value = float(manager.enemy.get("hp", 0))
	elif not manager.pending_event.is_empty():
		fight_status_label.text = "СОБЫТИЕ · %s" % str(manager.pending_event.get("name", "Решение ожидается"))
		if fight_health_bar != null:
			fight_health_bar.visible = false
	else:
		fight_status_label.text = "ПАУЗА" if manager.paused else "ИССЛЕДОВАНИЕ МАРШРУТА"
		if fight_health_bar != null:
			fight_health_bar.visible = false
	if pause_button != null:
		pause_button.text = _t("expedition.controls.resume") if manager.paused else _t("expedition.controls.pause")
	if return_button != null:
		return_button.disabled = not manager.enemy.is_empty() or int(manager.pending_perk_count) > 0 or not manager.pending_event.is_empty()
		return_button.text = _t("expedition.controls.return_blocked_event") if not manager.pending_event.is_empty() else (_t("expedition.controls.return_blocked_combat") if return_button.disabled else _t("expedition.controls.return"))
	if speed_label != null:
		speed_label.text = _t("expedition.controls.speed") % float(manager.speed)
	if equipment_label != null:
		equipment_label.text = "\n".join(manager.get_equipment_summary())
	if loot_preparation_label != null:
		var pending_rarity: float = clampf(float(manager.run_ledger.get("pending_item_rarity_bonus", 0.0)), 0.0, 0.18)
		var pending_drop: float = clampf(float(manager.run_ledger.get("pending_item_drop_bonus", 0.0)), 0.0, 0.30)
		var worn_rarity: float = clampf(float(manager.hero.get("equipped_rare_find_bonus", 0.0)), 0.0, 0.12)
		var loot_lines: Array[String] = []
		if pending_rarity > 0.0:
			loot_lines.append("Подготовка редкости +%d п.п." % int(round(pending_rarity * 100.0)))
		if pending_drop > 0.0:
			loot_lines.append("Подготовка шанса предмета +%d п.п." % int(round(pending_drop * 100.0)))
		if worn_rarity > 0.0:
			loot_lines.append("Надетый комплект: редкость +%d п.п." % int(round(worn_rarity * 100.0)))
		var preparation_text := "ДОБЫЧА: " + (" · ".join(loot_lines) if not loot_lines.is_empty() else "нет активной подготовки")
		loot_preparation_label.text = preparation_text + "\n" + _format_live_loot_forecast()
		loot_preparation_label.tooltip_text = _format_live_loot_forecast(true) + "\n\nШанс предмета сначала проверяется отдельно; редкость бросается только после успешной находки. Именная экипировка зарегистрированного босса — отдельная гарантированная награда."
	if tile_exchange_button != null:
		var exchange_preview: Dictionary = manager.get_tile_exchange_preview(selected_tile_hand_index)
		tile_exchange_button.disabled = not bool(exchange_preview.get("ok", false))
		tile_exchange_button.tooltip_text = str(exchange_preview.get("reason", "Выберите карту в руке."))
	if backpack_button != null:
		backpack_button.text = "РЮКЗАК · %d/%d" % [manager.bag.size(), manager.BACKPACK_CAPACITY]
		backpack_button.disabled = not manager.pending_event.is_empty() or int(manager.pending_perk_count) > 0 or not manager.pending_end_outcome.is_empty()
	if log_label != null:
		var recent: Array[String] = []
		for i in range(mini(12, manager.event_log.size())):
			recent.append(str(manager.event_log[i]))
		var next_log_render := "\n".join(recent)
		if log_label.text != next_log_render:
			log_label.text = next_log_render
			if log_scroll != null:
				log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)
	var signature := str(manager.tile_hand) + "|" + str(selected_tile_hand_index)
	if rebuild_tiles or signature != tile_hand_signature:
		_build_tile_hand()
		tile_hand_signature = signature
	_refresh_header()
	_refresh_first_hour_guide()
	if not manager.pending_event.is_empty() and modal_kind != "event":
		_show_event_choices()
	elif int(manager.pending_perk_count) > 0 and modal_kind != "perk":
		_show_perk_choices()

func _format_live_loot_forecast(detailed: bool = false) -> String:
	if manager == null or not is_instance_valid(manager):
		return "Шансы добычи появятся после начала экспедиции."
	var ledger: Dictionary = manager.run_ledger
	var echo_charges := clampi(int(ledger.get("echo_item_charges", 0)), 0, 4)
	var pending_drop := clampf(float(ledger.get("pending_item_drop_bonus", 0.0)), 0.0, 0.30)
	var pending_rarity := clampf(float(ledger.get("pending_item_rarity_bonus", 0.0)), 0.0, 0.18)
	var equipped_rarity := clampf(float(manager.hero.get("equipped_rare_find_bonus", 0.0)), 0.0, 0.12)
	var reward_bonus: float = float(manager.combat_reward_bonus) if not manager.enemy.is_empty() else 0.0
	var enemy_chance: float = manager.loot_system.get_equipment_drop_chance("enemy", reward_bonus, echo_charges, pending_drop)
	var elite_chance: float = manager.loot_system.get_equipment_drop_chance("elite", reward_bonus, echo_charges, pending_drop)
	var cache_chance: float = manager.loot_system.get_equipment_drop_chance("cache", 0.0, echo_charges, pending_drop)
	var enemy_bias: float = inventory_system.get_effective_rarity_bonus(equipped_rarity, pending_rarity, manager.loot_system.get_source_rarity_bonus("enemy"))
	var elite_bias: float = inventory_system.get_effective_rarity_bonus(equipped_rarity, pending_rarity, manager.loot_system.get_source_rarity_bonus("elite"))
	var cache_bias: float = inventory_system.get_effective_rarity_bonus(equipped_rarity, pending_rarity, manager.loot_system.get_source_rarity_bonus("cache"))
	var enemy_distribution: Dictionary = inventory_system.get_rarity_distribution(enemy_bias)
	var elite_distribution: Dictionary = inventory_system.get_rarity_distribution(elite_bias)
	var cache_distribution: Dictionary = inventory_system.get_rarity_distribution(cache_bias)
	if not detailed:
		return "ШАНС ПРЕДМЕТА: враг %d%% · элита %d%% · тайник %d%% · босс 100%%\nКАЧЕСТВО (если предмет выпал): %s. Элита +4 п.п.; тайник +2 п.п. к шкале редкости." % [int(round(enemy_chance * 100.0)), int(round(elite_chance * 100.0)), int(round(cache_chance * 100.0)), manager.loot_system.format_rarity_distribution(enemy_distribution)]
	return "ШАНС ПОЛУЧИТЬ ПРЕДМЕТ\nОбычный враг: %d%%\nЭлита: %d%%\nТайник: %d%%\nБосс: 100%% — именная награда по отдельным правилам\n\nКАЧЕСТВО ПРИ УСПЕШНОМ ДРОПЕ\nВраг: %s\nЭлита (+4 п.п.): %s\nТайник (+2 п.п.): %s\n\nВлияние экипировки и подготовки ограничено общим бонусом +25 п.п.; более редкие качества остаются менее вероятными." % [int(round(enemy_chance * 100.0)), int(round(elite_chance * 100.0)), int(round(cache_chance * 100.0)), manager.loot_system.format_rarity_distribution(enemy_distribution), manager.loot_system.format_rarity_distribution(elite_distribution), manager.loot_system.format_rarity_distribution(cache_distribution)]

func _refresh_first_hour_guide() -> void:
	if first_hour_guide_panel == null or not is_instance_valid(first_hour_guide_panel):
		return
	var should_show: bool = manager != null and is_instance_valid(manager) and manager.active and GameState.runs_completed == 0
	first_hour_guide_panel.visible = should_show
	if not should_show or first_hour_guide_label == null or not is_instance_valid(first_hour_guide_label):
		_first_hour_guide_signature = ""
		return
	var enemy_id := str(manager.enemy.get("id", "")) if not manager.enemy.is_empty() else ""
	var event_id := str(manager.pending_event.get("id", "")) if not manager.pending_event.is_empty() else ""
	var signature := "%d|%d|%d|%d|%d|%s|%s|%s|%s|%s" % [manager.placed_tiles.size(), manager.world_tiles.size(), manager.tile_hand.size(), manager.loop_count, int(manager.hero.get("hp", 0)), enemy_id, str(manager.enemy.get("phase_name", "")), event_id, str(manager.enemy.get("telegraph_pending", false)), str(manager.pending_perk_count)]
	if signature == _first_hour_guide_signature:
		return
	_first_hour_guide_signature = signature
	first_hour_guide_label.text = _first_hour_guide_text()

func _first_hour_guide_text() -> String:
	# This is presentation-only guidance. It reads live run state and never changes combat, rewards, or save data.
	if not manager.pending_event.is_empty():
		return _t("onboarding.hint.event")
	if int(manager.pending_perk_count) > 0:
		return _t("onboarding.hint.perk")
	if not manager.enemy.is_empty():
		if bool(manager.enemy.get("is_boss", false)):
			return _t("onboarding.hint.boss_telegraph") if bool(manager.enemy.get("telegraph_pending", false)) else _t("onboarding.hint.boss")
		if bool(manager.enemy.get("is_elite", false)):
			return _t("onboarding.hint.elite")
		return _t("onboarding.hint.combat")
	var max_hp := maxi(1, int(manager.hero.get("max_hp", 1)))
	if int(manager.hero.get("hp", max_hp)) * 3 <= max_hp:
		return _t("onboarding.hint.low_health")
	var placed_count: int = manager.placed_tiles.size() + manager.world_tiles.size()
	if placed_count == 0:
		return _t("onboarding.hint.first_tile") if not manager.tile_hand.is_empty() else _t("onboarding.hint.wait_for_tile")
	if placed_count == 1:
		return _t("onboarding.hint.after_first_tile")
	if _first_hour_has_tile_synergy():
		return _t("onboarding.hint.synergy_active")
	return _t("onboarding.hint.after_tiles_no_synergy")

func _first_hour_has_tile_synergy() -> bool:
	if manager == null or not is_instance_valid(manager) or manager.tile_system == null:
		return false
	for route_index in range(manager.route.size()):
		var route_bonus: Dictionary = manager.tile_system.get_synergy_bonus(manager.placed_tiles, route_index, manager.route.size())
		var route_synergies: Array = route_bonus.get("synergies", [])
		if not route_synergies.is_empty():
			return true
	for cell_value in manager.world_tiles.keys():
		var world_bonus: Dictionary = manager.tile_system.get_world_synergy_bonus(manager.world_tiles, str(cell_value))
		var world_synergies: Array = world_bonus.get("synergies", [])
		if not world_synergies.is_empty():
			return true
	return false

func _build_tile_hand() -> void:
	if tile_hand_grid == null or not is_instance_valid(tile_hand_grid):
		return
	for child in tile_hand_grid.get_children():
		tile_hand_grid.remove_child(child)
		child.queue_free()
	var copies_by_tile_id: Dictionary = {}
	for tile_value in manager.tile_hand:
		if typeof(tile_value) != TYPE_DICTIONARY:
			continue
		var copy_id := str(tile_value.get("id", ""))
		copies_by_tile_id[copy_id] = int(copies_by_tile_id.get(copy_id, 0)) + 1
	var copy_index_by_tile_id: Dictionary = {}
	for i in range(manager.tile_hand.size()):
		var tile: Dictionary = manager.tile_hand[i]
		var selected := i == selected_tile_hand_index
		var tile_id := str(tile.get("id", ""))
		var tile_short := str(tile.get("short", _t("route.tile.short")))
		if int(copies_by_tile_id.get(tile_id, 0)) > 1:
			var copy_index := int(copy_index_by_tile_id.get(tile_id, 0)) + 1
			copy_index_by_tile_id[tile_id] = copy_index
			tile_short = "%s · %d/%d" % [tile_short, copy_index, int(copies_by_tile_id[tile_id])]
		var tile_definition: Dictionary = ContentRegistry.TILE_DEFS.get(tile_id, {})
		var placement_zone := str(tile.get("placement_zone", tile_definition.get("placement_zone", "any")))
		var zone_hint := " · ПОЛЕ" if placement_zone == "landscape" else (" · ПРИДОРОЖЬЕ" if placement_zone == "roadside" else (" · ДОРОГА" if placement_zone == "road" else ""))
		var tile_label := "%s%s\n%s" % [tile_short, zone_hint, str(tile.get("name", tile_definition.get("name", "Тайл")))]
		var button := _button(tile_label, Callable(self, "_on_tile_selected").bind(i), selected)
		button.custom_minimum_size = Vector2(148, 64)
		button.tooltip_text = ("Размещение: только ландшафт. " if placement_zone == "landscape" else ("Размещение: только рядом с дорогой. " if placement_zone == "roadside" else ("Размещение: только дорога. " if placement_zone == "road" else ""))) + str(tile.get("description", ""))
		button.add_theme_font_size_override("font_size", 12)
		tile_hand_grid.add_child(button)

func _on_manager_changed() -> void:
	_refresh_header()
	if screen_mode == "expedition":
		_sync_expedition_view(false)

func _on_exchange_selected_tile() -> void:
	if manager == null or not is_instance_valid(manager):
		return
	var result: Dictionary = manager.exchange_tile(selected_tile_hand_index)
	if notice_label != null:
		notice_label.text = str(result.get("reason", "Обмен карты не выполнен."))
	if bool(result.get("ok", false)):
		_sync_expedition_view(true)
		if route_view != null and is_instance_valid(route_view):
			_on_world_cell_hovered(str(route_view.get("hovered_world_cell_id")))

func _on_tile_selected(index: int) -> void:
	if index < 0 or index >= manager.tile_hand.size():
		return
	if selected_tile_hand_index == index:
		selected_tile_hand_index = -1
	else:
		selected_tile_hand_index = index
	if notice_label != null:
		notice_label.text = (_t("tile.preview.selected") % str(manager.tile_hand[index].get("name", "Тайл"))) if selected_tile_hand_index >= 0 else _t("tile.preview.selection.cancelled")
	_sync_expedition_view(true)
	if route_view != null and is_instance_valid(route_view):
		_on_world_cell_hovered(str(route_view.get("hovered_world_cell_id")))

func _get_tile_placement_block_reason() -> String:
	if manager == null or not is_instance_valid(manager):
		return _t("tile.block.no_manager")
	if not str(manager.pending_end_outcome).is_empty():
		return _t("tile.block.result_pending")
	if not bool(manager.active):
		return _t("tile.block.inactive")
	if not manager.enemy.is_empty():
		return _t("tile.block.combat")
	if not manager.pending_event.is_empty() or int(manager.pending_perk_count) > 0:
		return _t("tile.block.pending_choice")
	return ""

func _on_route_cell_hovered(cell_index: int) -> void:
	if tile_preview_label == null or not is_instance_valid(tile_preview_label) or manager == null or not is_instance_valid(manager):
		return
	if cell_index < 0:
		if route_view != null and is_instance_valid(route_view) and not str(route_view.get("hovered_world_cell_id")).is_empty():
			return
		tile_preview_label.text = _t("expedition.tiles.preview_title") + "\n" + _t("expedition.tiles.preview_description")
		tile_preview_label.add_theme_color_override("font_color", C_MUTED)
		return
	var route_cell: Dictionary = manager.route[cell_index] if cell_index >= 0 and cell_index < manager.route.size() else {}
	var route_kind := str(route_cell.get("kind", "plain"))
	var route_name := str(ContentRegistry.ROUTE_CELL_TYPES.get(route_kind, {}).get("name", route_kind))
	if selected_tile_hand_index >= 0 and selected_tile_hand_index < manager.tile_hand.size():
		var blocked_reason := _get_tile_placement_block_reason()
		if not blocked_reason.is_empty():
			tile_preview_label.text = _t("tile.preview.blocked.road") % blocked_reason
			tile_preview_label.add_theme_color_override("font_color", C_RED)
			return
		var selected_tile: Dictionary = manager.tile_hand[selected_tile_hand_index]
		var preview: Dictionary = manager.tile_system.get_placement_preview(manager.route, manager.placed_tiles, cell_index, selected_tile, manager.equipment)
		tile_preview_label.text = str(preview.get("text", preview.get("reason", "Прогноз недоступен.")))
		tile_preview_label.add_theme_color_override("font_color", C_TEXT if bool(preview.get("ok", false)) else C_RED)
		return
	var placed: Dictionary = manager.placed_tiles.get(str(cell_index), {})
	if not placed.is_empty():
		tile_preview_label.text = _t("tile.preview.placed.road") % [str(placed.get("name", "Тайл")), str(placed.get("description", ""))]
	else:
		tile_preview_label.text = _t("tile.preview.empty.road") % [cell_index + 1, route_name]
	tile_preview_label.add_theme_color_override("font_color", C_MUTED)

func _on_route_cell_clicked(cell_index: int) -> void:
	if manager == null or not is_instance_valid(manager):
		if notice_label != null:
			notice_label.text = _t("tile.notice.no_manager")
		return
	if selected_tile_hand_index >= 0 and selected_tile_hand_index < manager.tile_hand.size():
		var blocked_reason := _get_tile_placement_block_reason()
		if not blocked_reason.is_empty():
			if notice_label != null:
				notice_label.text = blocked_reason
			_on_route_cell_hovered(cell_index)
			return
		var result: Dictionary = manager.place_tile(selected_tile_hand_index, cell_index)
		if bool(result.get("ok", false)):
			selected_tile_hand_index = -1
		if notice_label != null:
			notice_label.text = str(result.get("reason", _t("tile.notice.road.placed") if bool(result.get("ok", false)) else _t("tile.notice.road.failed")))
		if bool(result.get("ok", false)) and is_instance_valid(route_view) and route_view.has_method("show_feedback"):
			route_view.show_feedback("objective", str(result.get("reason", _t("tile.notice.road.placed"))))
		_sync_expedition_view(true)
		_on_route_cell_hovered(cell_index)
		return
	var placed: Dictionary = manager.placed_tiles.get(str(cell_index), {})
	if notice_label != null:
		if not placed.is_empty():
			notice_label.text = _t("tile.notice.road.occupied") % [cell_index + 1, str(placed.get("name", "Тайл"))]
		else:
			notice_label.text = _t("tile.notice.road.empty") % (cell_index + 1)
	_on_route_cell_hovered(cell_index)

func _on_world_cell_hovered(cell_id: String) -> void:
	if tile_preview_label == null or not is_instance_valid(tile_preview_label) or manager == null or not is_instance_valid(manager):
		return
	if cell_id.is_empty():
		tile_preview_label.text = _t("expedition.tiles.preview_title") + "\n" + _t("expedition.tiles.preview_description")
		tile_preview_label.add_theme_color_override("font_color", C_MUTED)
		return
	if selected_tile_hand_index < 0 or selected_tile_hand_index >= manager.tile_hand.size():
		var placed: Dictionary = manager.world_tiles.get(cell_id, {})
		if placed.is_empty():
			if TileSystemScript.is_map_world_cell_id(cell_id) and not manager.discovered_world_cells.has(cell_id):
				tile_preview_label.text = _t("tile.preview.unknown.world")
			else:
				tile_preview_label.text = _t("tile.preview.empty.world") % cell_id
		else:
			tile_preview_label.text = _t("tile.preview.placed.world") % [str(placed.get("name", "Тайл")), str(placed.get("description", "")), int(placed.get("route_index", -1)) + 1]
		tile_preview_label.add_theme_color_override("font_color", C_MUTED)
		return
	var blocked_reason := _get_tile_placement_block_reason()
	if not blocked_reason.is_empty():
		tile_preview_label.text = _t("tile.preview.blocked.world") % blocked_reason
		tile_preview_label.add_theme_color_override("font_color", C_RED)
		return
	var selected_tile: Dictionary = manager.tile_hand[selected_tile_hand_index]
	var preview: Dictionary = manager.tile_system.get_world_placement_preview(manager.route, manager.world_tiles, cell_id, selected_tile, manager.equipment, manager.get_route_shape_id(), manager.get_route_geometry_seed())
	tile_preview_label.text = str(preview.get("text", preview.get("reason", "Прогноз недоступен.")))
	tile_preview_label.add_theme_color_override("font_color", C_TEXT if bool(preview.get("ok", false)) else C_RED)

func _on_world_cell_clicked(cell_id: String) -> void:
	if manager == null or not is_instance_valid(manager):
		if notice_label != null:
			notice_label.text = _t("tile.notice.no_manager")
		return
	if selected_tile_hand_index < 0:
		if notice_label != null:
			notice_label.text = _t("tile.notice.select_first")
		return
	var blocked_reason := _get_tile_placement_block_reason()
	if not blocked_reason.is_empty():
		if notice_label != null:
			notice_label.text = blocked_reason
		_on_world_cell_hovered(cell_id)
		return
	var result: Dictionary = manager.place_world_tile(selected_tile_hand_index, cell_id)
	if bool(result.get("ok", false)):
		selected_tile_hand_index = -1
		if notice_label != null:
			notice_label.text = str(result.get("reason", _t("tile.notice.world.placed")))
	else:
		if notice_label != null:
			notice_label.text = str(result.get("reason", _t("tile.notice.world.failed")))
	_sync_expedition_view(true)
	_on_world_cell_hovered(cell_id)

func _toggle_pause() -> void:
	manager.set_pause(not manager.paused)
	_sync_expedition_view(false)

func _set_speed(speed_value: float) -> void:
	manager.set_speed(speed_value)
	_sync_expedition_view(false)

func _request_return() -> void:
	if not manager.enemy.is_empty() or int(manager.pending_perk_count) > 0 or not manager.pending_event.is_empty():
		return
	_resume_after_return_confirmation = not manager.paused
	if not manager.paused:
		manager.set_pause(true)
	var forecast: Dictionary = manager.get_return_forecast()
	var next_step_text := "Если продолжить: следующий цикл даст примерно +%d материалов и +%d редких ресурсов; опасность вырастет до ×%.1f, расчётная вероятность обычной встречи — %d%%." % [int(forecast.get("next_scrap", 0)), int(forecast.get("next_crystals", 0)), float(forecast.get("danger_next", manager.danger)), int(round(float(forecast.get("encounter_chance", 0.0)) * 100.0))]
	if bool(forecast.get("boss_next", false)):
		next_step_text += " Следующий цикл включает плановую встречу с боссом."
	_show_modal(
		"Завершить экспедицию?",
		"Сейчас добыто: %d материалов и %d редких ресурсов. При поражении сохранилось бы примерно %d материалов и %d редких ресурсов. %s Безопасный возврат сохраняет текущую добычу полностью; после выхода этот забег нельзя продолжить." % [int(forecast.get("scrap", 0)), int(forecast.get("crystals", 0)), int(forecast.get("defeat_scrap", 0)), int(forecast.get("defeat_crystals", 0)), next_step_text],
		[
			{"text": "Продолжить путь", "callback": Callable(self, "_cancel_return_request"), "accent": false},
			{"text": "Вернуться на базу", "callback": Callable(self, "_confirm_return"), "accent": true}
		],
		"confirm"
	)

func _cancel_return_request() -> void:
	_close_overlay()
	if _resume_after_return_confirmation and manager != null and manager.active:
		manager.set_pause(false)
	_resume_after_return_confirmation = false

func _confirm_return() -> void:
	_resume_after_return_confirmation = false
	_close_overlay(false)
	manager.end_run("return")

func _on_run_finished(summary: Dictionary) -> void:
	current_summary = summary.duplicate(true)
	_close_overlay(false)
	_render_summary(summary)

func _render_summary(summary: Dictionary) -> void:
	if is_instance_valid(overlay) and overlay.visible:
		_close_overlay(false)
	_focus_before_overlay = null
	screen_mode = "summary"
	_set_phase("ОТЧЁТ ЭКСПЕДИЦИИ")
	_clear_screen()
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_root.add_child(center)
	var report := _make_panel(center, C_PANEL, 20)
	report.custom_minimum_size = Vector2(minf(720.0, maxf(520.0, get_viewport_rect().size.x - 48.0)), 0.0)
	report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 10)
	report.add_child(layout)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 5)
	layout.add_child(header_box)
	var returned := str(summary.get("outcome", "")) == "return"
	header_box.add_child(_label("ЭКСПЕДИЦИЯ ЗАВЕРШЕНА", 11, C_ACCENT if returned else C_RED, true))
	header_box.add_child(_label("Добыча возвращена в убежище." if returned else "Герой потерпел поражение.", 24, C_TEXT, true))
	header_box.add_child(_label("Маршрут seed %s · пройдено циклов: %d · уровень героя: %d" % [str(summary.get("seed", "—")), int(summary.get("loops", 0)), int(summary.get("hero_level", 1))], 12, C_MUTED))
	header_box.add_child(_label("Этаж %d/8: %s · счёт: %d" % [int(summary.get("floor_number", 1)), str(summary.get("floor_name", "Этаж")), int(summary.get("challenge_score", 0))], 12, C_GOLD, true))
	var record_value: Variant = summary.get("difficulty_record", {})
	if typeof(record_value) == TYPE_DICTIONARY:
		var record: Dictionary = record_value
		if not record.is_empty():
			header_box.add_child(_label("Рекорд этажа: %d очков · лучший цикл: %d · возвращений: %d/%d" % [int(record.get("best_score", 0)), int(record.get("best_loops", 0)), int(record.get("returns", 0)), int(record.get("runs", 0))], 11, C_MUTED))
	header_box.add_child(_label("Модификатор: %s" % str(summary.get("modifier_name", "Обычная экспедиция")), 11, C_ACCENT, true))
	header_box.add_child(_label("Модификатор маршрута: %s" % str(summary.get("modifier_name", "Обычная экспедиция")), 11, C_MUTED, true))
	if bool(summary.get("floor_cleared", false)):
		if int(summary.get("floor_number", 1)) >= ContentRegistry.FLOOR_COUNT:
			header_box.add_child(_label("КАМПАНИЯ ЗАВЕРШЕНА: все 8 этажей пройдены, финальный хранитель побеждён.", 12, C_GOLD, true))
		else:
			header_box.add_child(_label("ЭТАЖ ПРОЙДЕН: следующий этаж %d теперь открыт. Добыча сохранена." % mini(ContentRegistry.FLOOR_COUNT, int(summary.get("floor_number", 1)) + 1), 12, C_GOLD, true))
	var details_scroll := ScrollContainer.new()
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	details_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(details_scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	details_scroll.add_child(box)
	var challenge_result_value: Variant = summary.get("challenge", {})
	if typeof(challenge_result_value) == TYPE_DICTIONARY and not challenge_result_value.is_empty():
		var challenge_result: Dictionary = challenge_result_value
		box.add_child(_label("Испытание «%s»: %s (%d/%d)" % [str(challenge_result.get("name", "Испытание")), "выполнено" if bool(challenge_result.get("completed", false)) else "не выполнено", int(challenge_result.get("progress", 0)), int(challenge_result.get("target", 1))], 12, C_GOLD, true))
	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color("#2a4047"))
	box.add_child(sep)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 12)
	stats.add_theme_constant_override("v_separation", 8)
	box.add_child(stats)
	_add_summary_metric(stats, "Победы", str(summary.get("victories", 0)))
	_add_summary_metric(stats, "Побеждено боссов", str(summary.get("bosses_defeated", 0)))
	_add_summary_metric(stats, "Побеждено элит", str(summary.get("elites_defeated", 0)))
	_add_summary_metric(stats, "Решения событий", str(summary.get("events_resolved", 0)))
	_add_summary_metric(stats, "Материалы в забеге", str(summary.get("earned_scrap", 0)))
	_add_summary_metric(stats, "Материалы сохранены", str(summary.get("kept_scrap", 0)))
	_add_summary_metric(stats, "Редкий ресурс сохранён", str(summary.get("kept_crystals", 0)))
	_add_summary_metric(stats, "Пыль утраченных вещей", "+%d · всего %d" % [int(summary.get("kept_echo_dust", 0)), int(summary.get("total_echo_dust", GameState.echo_dust))])
	if int(summary.get("ejected_item_count", 0)) > 0:
		_add_summary_metric(stats, "Вытеснено предметов", "%d · начисление зависит от редкости" % int(summary.get("ejected_item_count", 0)))
	_add_summary_metric(stats, "Потеряно материалов", str(summary.get("lost_scrap", 0)))
	_add_summary_metric(stats, "Потеряно редкого ресурса", str(summary.get("lost_crystals", 0)))
	var earned_trophies_value: Variant = summary.get("earned_trophies", {})
	var earned_trophies: Dictionary = earned_trophies_value if typeof(earned_trophies_value) == TYPE_DICTIONARY else {}
	var kept_trophies_value: Variant = summary.get("kept_trophies", {})
	var kept_trophies: Dictionary = kept_trophies_value if typeof(kept_trophies_value) == TYPE_DICTIONARY else {}
	box.add_child(_label("Трофеи за экспедицию · собрано: пыльца %d, призма %d, кости %d, эхо %d · сохранено в бестиарии: %d, %d, %d, %d" % [int(earned_trophies.get("spore_pollen", 0)), int(earned_trophies.get("prism_fragment", 0)), int(earned_trophies.get("bone_fragment", 0)), int(earned_trophies.get("echo_residue", 0)), int(kept_trophies.get("spore_pollen", 0)), int(kept_trophies.get("prism_fragment", 0)), int(kept_trophies.get("bone_fragment", 0)), int(kept_trophies.get("echo_residue", 0))], 11, C_GOLD, true))
	var cache_names_value: Variant = summary.get("field_cache_item_names", [])
	var cache_names: Array = cache_names_value if typeof(cache_names_value) == TYPE_ARRAY else []
	if not cache_names.is_empty():
		box.add_child(_label("ПРЕДМЕТЫ В ПОХОДНОМ ТАЙНИКЕ (%d) · все уже сохранены в постоянном арсенале\n%s" % [cache_names.size(), "\n".join(PackedStringArray(cache_names))], 12, C_ACCENT, true))
	var debrief: Dictionary = RunDebriefPresenterScript.build(summary)
	var debrief_panel := _make_panel(box, C_PANEL_ALT, 12)
	var debrief_layout := VBoxContainer.new()
	debrief_layout.add_theme_constant_override("separation", 5)
	debrief_panel.add_child(debrief_layout)
	debrief_layout.add_child(_label("РАЗБОР ЗАБЕГА · СЛЕДУЮЩИЙ ШАГ", 12, C_ACCENT, true))
	debrief_layout.add_child(_label(str(debrief.get("finding", "Итог экспедиции сохранён.")), 12, C_TEXT, true))
	debrief_layout.add_child(_label(str(debrief.get("action", "Проверьте экипировку и постоянное развитие перед следующим спуском.")), 12, C_MUTED))
	var event_history_value: Variant = summary.get("event_history", [])
	var event_history: Array = []
	if typeof(event_history_value) == TYPE_ARRAY:
		event_history = event_history_value
	if not event_history.is_empty():
		var decision_lines: Array[String] = []
		var history_start: int = maxi(0, event_history.size() - 3)
		for history_index in range(history_start, event_history.size()):
			var history_item_value: Variant = event_history[history_index]
			if typeof(history_item_value) != TYPE_DICTIONARY:
				continue
			var history_item: Dictionary = history_item_value
			decision_lines.append("%s → %s" % [str(history_item.get("event", "Событие")), str(history_item.get("choice", "Решение"))])
		if not decision_lines.is_empty():
			box.add_child(_label("ВАШИ ПОСЛЕДНИЕ РЕШЕНИЯ\n" + "\n".join(decision_lines), 11, C_MUTED))
	var objective_value: Variant = summary.get("objective", {})
	if typeof(objective_value) == TYPE_DICTIONARY and not objective_value.is_empty():
		var objective_result: Dictionary = objective_value
		box.add_child(_label("ЦЕЛЬ ЭКСПЕДИЦИИ: %s — %s (%d/%d)" % [str(objective_result.get("name", "Цель")), "выполнена" if bool(objective_result.get("completed", false)) else "не выполнена", int(objective_result.get("progress", 0)), int(objective_result.get("target", 1))], 12, C_GOLD, true))
	var contract_value: Variant = summary.get("contract", {})
	if typeof(contract_value) == TYPE_DICTIONARY and not contract_value.is_empty():
		var contract_result: Dictionary = contract_value
		var contract_result_state := "провален: " + str(contract_result.get("failure_reason", "срок истёк")) if bool(contract_result.get("failed", false)) else ("выполнен" if bool(contract_result.get("completed", false)) else "не выполнен")
		box.add_child(_label("КОНТРАКТ: %s — %s (%d/%d); награда +%d материалов / +%d редких ресурсов" % [str(contract_result.get("name", "Контракт")), contract_result_state, int(contract_result.get("progress", 0)), int(contract_result.get("target", 0)), int(contract_result.get("scrap_reward", 0)) if bool(contract_result.get("completed", false)) else 0, int(contract_result.get("crystal_reward", 0)) if bool(contract_result.get("completed", false)) else 0], 12, C_GOLD, true))
	box.add_child(_label("Сохранение добычи: %d%%" % int(round(float(summary.get("retention", 0.0)) * 100.0)), 12, C_GOLD, true))
	var continue_button := _button("Продолжить развитие убежища  →", Callable(self, "_render_base"), true)
	continue_button.custom_minimum_size.y = 46
	layout.add_child(continue_button)
	call_deferred("_focus_control_if_valid", continue_button)


func _add_summary_metric(parent: Node, caption: String, value: String) -> void:
	var panel := _make_panel(parent, C_PANEL_ALT, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	box.add_child(_label(caption, 11, C_MUTED))
	box.add_child(_label(value, 19, C_TEXT, true))

func _show_event_choices() -> void:
	if manager == null or not is_instance_valid(manager) or manager.pending_event.is_empty():
		return
	var event_data: Dictionary = manager.pending_event
	var choice_values: Variant = event_data.get("choices", [])
	if typeof(choice_values) != TYPE_ARRAY:
		_open_message("Сбой события", "У этого события нет доступных вариантов. Маршрут продолжится после закрытия сообщения.")
		return
	var choices: Array = choice_values
	if choices.is_empty():
		_open_message("Сбой события", "У этого события нет доступных вариантов. Маршрут продолжится после закрытия сообщения.")
		return
	var buttons: Array = []
	for choice_value in choices:
		if typeof(choice_value) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choice_value
		var choice_id: String = str(choice.get("id", ""))
		var available: bool = manager.event_choice_is_available(choice_id)
		var button_text: String = "%s\n%s" % [str(choice.get("title", "Выбрать")), str(choice.get("description", ""))]
		if not available:
			button_text += "\nНедостаточно материалов в добыче"
		buttons.append({
			"text": button_text,
			"callback": Callable(self, "_resolve_event_choice").bind(choice_id),
			"accent": buttons.is_empty(),
			"disabled": not available,
			"tooltip": str(choice.get("description", ""))
		})
	_show_modal(
		"Событие · %s" % str(event_data.get("name", "Маршрутная ситуация")),
		str(event_data.get("narrative", "Выберите, как поступить.")),
		buttons,
		"event"
	)

func _resolve_event_choice(choice_id: String) -> void:
	_close_overlay(false)
	var result: Dictionary = manager.resolve_event_choice(choice_id)
	if not bool(result.get("ok", false)):
		_open_message("Решение не принято", str(result.get("reason", "Не удалось применить вариант.")))
		return
	if manager.active:
		_sync_expedition_view(false)
		if not overlay.visible and pause_button != null:
			call_deferred("_focus_control_if_valid", pause_button)

func _show_perk_choices() -> void:
	if manager.pending_perk_choices.is_empty():
		return
	var buttons: Array = []
	var perk_counts_value: Variant = manager.hero.get("perk_counts", {})
	var perk_counts: Dictionary = perk_counts_value if typeof(perk_counts_value) == TYPE_DICTIONARY else {}
	for perk_id_value in manager.pending_perk_choices:
		var perk_id := str(perk_id_value)
		var perk: Dictionary = ContentRegistry.PERKS[perk_id]
		var rank := int(perk_counts.get(perk_id, 0))
		var max_rank := int(perk.get("max_stacks", 1))
		var category := str(perk.get("category", "Улучшение"))
		buttons.append({"text": "%s · %s (%d/%d)\n%s" % [str(perk.name), category, rank, max_rank, str(perk.description)], "callback": Callable(self, "_choose_perk").bind(perk_id), "accent": perk_id == "power"})
	_show_modal("Новый уровень · выберите улучшение", "Это решение действует до конца текущей экспедиции.", buttons, "perk")

func _choose_perk(perk_id: String) -> void:
	_close_overlay(false)
	manager.choose_perk(perk_id)
	_sync_expedition_view(false)
	if not overlay.visible and pause_button != null:
		call_deferred("_focus_control_if_valid", pause_button)

func _show_modal(title_text: String, body_text: String, buttons: Array, kind: String = "message") -> void:
	_prepare_overlay()
	modal_kind = kind
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel := _make_panel(center, Color("#1a2a31"), 22)
	panel.custom_minimum_size = Vector2(minf(640.0, viewport_size.x - 48.0), minf(620.0, viewport_size.y - 48.0)) if kind in ["settings", "backpack"] else Vector2(minf(560.0, viewport_size.x - 48.0), 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var backpack_has_slot_grids := false
	var backpack_footer: VBoxContainer = null
	if kind == "backpack":
		for button_value in buttons:
			if typeof(button_value) == TYPE_DICTIONARY and not str(button_value.get("group", "")).is_empty():
				backpack_has_slot_grids = true
				break
	var button_parent: VBoxContainer
	if kind == "backpack":
		var backpack_layout := VBoxContainer.new()
		backpack_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		backpack_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
		backpack_layout.add_theme_constant_override("separation", 8)
		panel.add_child(backpack_layout)
		backpack_layout.add_child(_label(title_text, 20, C_TEXT, true))
		var backpack_info_scroll := ScrollContainer.new()
		backpack_info_scroll.custom_minimum_size.y = minf(118.0, viewport_size.y * 0.17) if backpack_has_slot_grids else minf(305.0, viewport_size.y * 0.42)
		backpack_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		backpack_info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		backpack_layout.add_child(backpack_info_scroll)
		var backpack_info := _label(body_text, 12, C_MUTED)
		backpack_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		backpack_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		backpack_info_scroll.add_child(backpack_info)
		button_parent = VBoxContainer.new()
		button_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button_parent.add_theme_constant_override("separation", 6)
		if backpack_has_slot_grids:
			var slots_scroll := ScrollContainer.new()
			slots_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			slots_scroll.custom_minimum_size.y = minf(260.0, viewport_size.y * 0.36)
			slots_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			slots_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
			backpack_layout.add_child(slots_scroll)
			slots_scroll.add_child(button_parent)
			backpack_footer = VBoxContainer.new()
			backpack_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			backpack_footer.add_theme_constant_override("separation", 6)
			backpack_layout.add_child(backpack_footer)
		else:
			backpack_layout.add_child(button_parent)
	elif kind == "settings":
		# Settings remain one scrollable form; this child order is used by _open_settings().
		var settings_box := VBoxContainer.new()
		settings_box.add_theme_constant_override("separation", 12)
		settings_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var settings_scroll := ScrollContainer.new()
		settings_scroll.custom_minimum_size = Vector2(minf(590.0, viewport_size.x - 96.0), minf(530.0, viewport_size.y - 96.0))
		settings_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		settings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		panel.add_child(settings_scroll)
		settings_scroll.add_child(settings_box)
		settings_box.add_child(_label(title_text, 21, C_TEXT, true))
		settings_box.add_child(_label(body_text, 14, C_MUTED))
		button_parent = settings_box
	else:
		# Long event/tutorial/help text is clipped to a bounded viewport. Choice buttons
		# stay outside that scroller so the primary action remains visible at small sizes.
		var modal_layout := VBoxContainer.new()
		modal_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modal_layout.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		modal_layout.add_theme_constant_override("separation", 12)
		panel.add_child(modal_layout)
		var title_label := _label(title_text, 21, C_TEXT, true)
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		modal_layout.add_child(title_label)
		var max_body_height := minf(280.0, maxf(120.0, viewport_size.y - 440.0))
		var desired_body_height := clampf(80.0 + float(body_text.length()) * 0.32, 110.0, max_body_height)
		var body_scroll := ScrollContainer.new()
		body_scroll.custom_minimum_size = Vector2(0.0, desired_body_height)
		body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		modal_layout.add_child(body_scroll)
		var body_label := _label(body_text, 14, C_MUTED)
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body_scroll.add_child(body_label)
		button_parent = VBoxContainer.new()
		button_parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button_parent.add_theme_constant_override("separation", 8)
		modal_layout.add_child(button_parent)
	var current_grid: GridContainer = null
	var current_group := ""
	for button_data in buttons:
		var button_group := str(button_data.get("group", "")) if kind == "backpack" else ""
		if not button_group.is_empty() and button_group != current_group:
			current_grid = GridContainer.new()
			current_grid.columns = 3
			current_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			current_grid.add_theme_constant_override("h_separation", 8)
			current_grid.add_theme_constant_override("v_separation", 8)
			button_parent.add_child(current_grid)
			current_group = button_group
		elif button_group.is_empty():
			current_grid = null
			current_group = ""
		var text_value := str(button_data.get("text", "Продолжить"))
		var callback: Callable = button_data.get("callback", Callable(self, "_close_overlay"))
		var attach_inventory_behavior := kind == "backpack" and button_group in ["equipment_grid", "backpack_grid"]
		var behavior_script: Script = InventoryDragButtonScript if attach_inventory_behavior else null
		var button := _button(text_value, callback, bool(button_data.get("accent", false)), behavior_script)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0, 76 if not button_group.is_empty() else (64 if kind == "event" else (48 if kind == "perk" else 42)))
		button.clip_text = false
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if not button_group.is_empty() else TextServer.AUTOWRAP_OFF
		button.disabled = bool(button_data.get("disabled", false))
		button.tooltip_text = str(button_data.get("tooltip", ""))
		if attach_inventory_behavior and button.has_method("configure_inventory_control"):
			button.call("configure_inventory_control", self, str(button_data.get("item_id", "")), str(button_data.get("equipment_slot", "")), int(button_data.get("inventory_cell_index", -1)), bool(button_data.get("draggable", false)))
		var item_rarity := str(button_data.get("rarity", ""))
		if not item_rarity.is_empty() and not button.disabled:
			var rarity_colors := {"Обычный": Color("#7f9c95"), "Редкий": Color("#63b8e8"), "Эпический": Color("#bb8af5"), "Реликтовый": Color("#f3c86b"), "Элитная": Color("#ed9b75"), "Боссовая": Color("#f4b856"), "Тайная": Color("#81dca4")}
			var rarity_border: Color = rarity_colors.get(item_rarity, Color("#7f9c95"))
			for style_name in ["normal", "hover", "pressed", "focus"]:
				var style_value: StyleBox = button.get_theme_stylebox(style_name).duplicate()
				if style_value is StyleBoxFlat:
					(style_value as StyleBoxFlat).border_color = rarity_border
					(style_value as StyleBoxFlat).set_border_width_all(3)
					button.add_theme_stylebox_override(style_name, style_value)
		if button.disabled:
			var disabled_style := StyleBoxFlat.new()
			disabled_style.bg_color = Color("#1b292f")
			disabled_style.border_color = Color("#2d4046")
			disabled_style.set_border_width_all(1)
			disabled_style.set_corner_radius_all(9)
			button.add_theme_stylebox_override("disabled", disabled_style)
			button.add_theme_color_override("font_disabled_color", C_MUTED)
		if not button_group.is_empty() and current_grid != null:
			current_grid.add_child(button)
		elif kind == "backpack" and backpack_has_slot_grids and backpack_footer != null:
			backpack_footer.add_child(button)
		else:
			button_parent.add_child(button)
	call_deferred("_configure_overlay_focus", true, kind)

func _prepare_overlay() -> void:
	if not is_instance_valid(overlay):
		return
	if not overlay.visible and _focus_before_overlay == null:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is Control and focus_owner.is_inside_tree() and not overlay.is_ancestor_of(focus_owner):
			_focus_before_overlay = focus_owner as Control
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = true
	modal_kind = ""

func _close_overlay(restore_focus: bool = true) -> void:
	if not is_instance_valid(overlay):
		return
	var was_visible := overlay.visible
	for child in overlay.get_children():
		overlay.remove_child(child)
		child.queue_free()
	overlay.visible = false
	modal_kind = ""
	if was_visible and restore_focus:
		var restore_target := _focus_before_overlay
		_focus_before_overlay = null
		if restore_target != null:
			call_deferred("_focus_control_if_valid", restore_target)

func _focus_control_if_valid(target: Control) -> void:
	if target == null or not is_instance_valid(target):
		return
	if is_instance_valid(overlay) and overlay.visible and not overlay.is_ancestor_of(target):
		return
	if not target.is_inside_tree() or not target.is_visible_in_tree() or target.focus_mode == Control.FOCUS_NONE:
		return
	if target is BaseButton and (target as BaseButton).disabled:
		return
	target.grab_focus()

func _collect_overlay_focus_targets(node: Node, targets: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if control != overlay and control.focus_mode != Control.FOCUS_NONE and control.is_visible_in_tree() and not control.is_queued_for_deletion():
			var enabled := true
			if control is BaseButton:
				enabled = not (control as BaseButton).disabled
			if enabled:
				targets.append(control)
	for child in node.get_children():
		_collect_overlay_focus_targets(child, targets)

func _configure_overlay_focus(focus_initial: bool = false, kind_override: String = "") -> void:
	if not is_instance_valid(overlay) or not overlay.visible:
		return
	# Newly created dialogs must honor a saved high-contrast preference as well.
	if bool(GameState.settings.get("high_contrast", false)):
		_apply_contrast_to_tree(overlay)
	var targets: Array[Control] = []
	_collect_overlay_focus_targets(overlay, targets)
	if targets.is_empty():
		return
	for index in range(targets.size()):
		var current := targets[index]
		var next_control := targets[(index + 1) % targets.size()]
		var previous_control := targets[(index - 1 + targets.size()) % targets.size()]
		current.focus_next = current.get_path_to(next_control)
		current.focus_previous = current.get_path_to(previous_control)
	if not focus_initial:
		return
	var focus_target: Control = targets[0]
	var effective_kind := kind_override if not kind_override.is_empty() else modal_kind
	if effective_kind in ["confirm", "confirm_reset", "confirm_salvage"]:
		for target in targets:
			if target is Button:
				var lower_text := (target as Button).text.to_lower()
				if lower_text.contains("отмена") or lower_text.contains("оставить как есть") or lower_text.contains("продолжить путь") or lower_text.contains("продолжить сохранённый забег"):
					focus_target = target
					break
			if target is Button and not (target as Button).disabled and not (target as Button).text.to_lower().contains("сбросить") and not (target as Button).text.to_lower().contains("разобрать") and not (target as Button).text.to_lower().contains("удалить сохранённый"):
				if not (target as Button).text.to_lower().contains("вернуться на базу"):
					focus_target = target
					break
	call_deferred("_focus_control_if_valid", focus_target)

func _open_run_backpack() -> void:
	if manager == null or not is_instance_valid(manager) or not manager.active:
		return
	if not manager.pending_event.is_empty() or int(manager.pending_perk_count) > 0 or not manager.pending_end_outcome.is_empty():
		_open_message("Рюкзак недоступен", "Сначала завершите событие, выбор улучшения или сохранение результата.")
		return
	manager.set_pause(true)
	var lines: Array[String] = ["Экспедиция приостановлена. Левый клик — сравнить предмет. Правый клик — быстро надеть. Перетащите предмет в совместимый слот или другую ячейку.", "Новые находки появляются в начале рюкзака. При заполнении 12 ячеек старейшая вещь в ячейке 12 вытесняется. Перетаскивание меняет порядок будущего вытеснения.", "Рюкзак: %d/%d · 6 слотов экипировки." % [manager.bag.size(), manager.BACKPACK_CAPACITY]]
	var active_loadout_stats: Dictionary = inventory_system.total_equipment_stats(manager.equipment)
	var active_synergies: Array = active_loadout_stats.get("active_synergies", [])
	var active_sets: Array = active_loadout_stats.get("active_sets", [])
	lines.append("Синергии: %s" % (", ".join(active_synergies) if not active_synergies.is_empty() else "пока нет — попробуйте сочетать типы экипировки"))
	lines.append("Комплекты: %s" % (", ".join(active_sets) if not active_sets.is_empty() else "не активны"))
	var buttons: Array = []
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var slot := str(slot_value)
		var item_value: Variant = manager.equipment.get(slot, {})
		var item: Dictionary = item_value if typeof(item_value) == TYPE_DICTIONARY else {}
		var slot_label := str(InventorySystemScript.SLOT_NAMES.get(slot, slot))
		var item_name := str(item.get("name", "ПУСТО")) if not item.is_empty() else "ПУСТО"
		var short_name := item_name.left(15) + ("…" if item_name.length() > 15 else "")
		buttons.append({"text": "%s\n%s" % [slot_label, short_name], "callback": Callable(self, "_open_equipped_run_item").bind(slot), "accent": false, "disabled": false, "tooltip": "%s: %s\n%s\nПеретащите подходящий предмет сюда, чтобы экипировать." % [slot_label, item_name, _format_item_bonus(item) if not item.is_empty() else "Слот пуст"], "group": "equipment_grid", "equipment_slot": slot, "item_id": str(item.get("id", "")), "rarity": str(item.get("rarity", ""))})
	for index in range(manager.BACKPACK_CAPACITY):
		if index < manager.bag.size() and typeof(manager.bag[index]) == TYPE_DICTIONARY:
			var bag_item: Dictionary = manager.bag[index]
			var bag_name := str(bag_item.get("name", "Предмет"))
			var bag_name_short := bag_name.left(14) + ("…" if bag_name.length() > 14 else "")
			var slot_label := str(InventorySystemScript.SLOT_NAMES.get(str(bag_item.get("slot", "")), "Неизвестный слот"))
			buttons.append({"text": "%02d · %s\n%s · %.0f" % [index + 1, bag_name_short, slot_label, inventory_system.item_power(bag_item)], "callback": Callable(self, "_open_run_backpack_item").bind(str(bag_item.get("id", ""))), "accent": false, "tooltip": "%s · %s\nСлот: %s\n%s\nПравый клик — быстро надеть; перетащите для сортировки." % [bag_name, str(bag_item.get("rarity", "Обычный")), slot_label, _format_item_bonus(bag_item)], "group": "backpack_grid", "item_id": str(bag_item.get("id", "")), "inventory_cell_index": index, "draggable": true, "rarity": str(bag_item.get("rarity", "Обычный"))})
		else:
			buttons.append({"text": "%02d\nПУСТО" % (index + 1), "callback": Callable(self, "_open_run_backpack"), "accent": false, "disabled": false, "tooltip": "Свободная ячейка. Перетащите предмет сюда, чтобы поменять очередь вытеснения.", "group": "backpack_grid", "inventory_cell_index": index, "draggable": false})
	buttons.append({"text": "Закрыть рюкзак", "callback": Callable(self, "_close_overlay"), "accent": false})
	buttons.append({"text": "Продолжить экспедицию", "callback": Callable(self, "_resume_after_backpack"), "accent": true})
	_show_modal("Экипировка и рюкзак", "\n".join(lines), buttons, "backpack")

func _open_equipped_run_item(slot: String) -> void:
	if manager == null:
		return
	var item_value: Variant = manager.equipment.get(slot, {})
	var item: Dictionary = item_value if typeof(item_value) == TYPE_DICTIONARY else {}
	if item.is_empty():
		_open_run_backpack()
		return
	var body := "%s\nРедкость: %s · уровень %d · улучшение +%d\nСлот: %s · сила %.1f\n\n%s" % [str(item.get("name", "Экипировка")), str(item.get("rarity", "Обычный")), int(item.get("rank", 1)), int(item.get("upgrade_level", 0)), InventorySystemScript.SLOT_NAMES.get(slot, slot), inventory_system.item_power(item), _format_item_bonus(item)]
	var buttons: Array = [
		{"text": "Снять в начало рюкзака", "callback": Callable(self, "_on_run_unequip").bind(slot), "accent": true},
		{"text": "← К рюкзаку", "callback": Callable(self, "_open_run_backpack"), "accent": false}
	]
	_show_modal("Надетая экипировка", body, buttons, "backpack")

func _open_run_backpack_item(item_id: String) -> void:
	var item: Dictionary = manager.find_run_item(item_id) if manager != null else {}
	if item.is_empty():
		_open_run_backpack()
		return
	var slot := str(item.get("slot", ""))
	var current_value: Variant = manager.equipment.get(slot, {})
	var current: Dictionary = current_value if typeof(current_value) == TYPE_DICTIONARY else {}
	var body := "%s · %s\nСлот: %s · ранг %d · улучшение +%d\nСила: %.1f\n\nСвойство: %s\nНабор: %s\n\nБонусы: %s" % [str(item.get("name", "Предмет")), str(item.get("rarity", "Обычный")), InventorySystemScript.SLOT_NAMES.get(slot, slot), int(item.get("rank", 1)), int(item.get("upgrade_level", 0)), inventory_system.item_power(item), str(item.get("archetype_description", "Базовые характеристики")), str(item.get("set_name", "без набора")), _format_item_bonus(item)]
	if not str(item.get("landscape_affinity", "")).is_empty():
		body += "\n\nЛандшафтная связь: %s. При проходе действует эффект %s. Если на том же секторе встретится соответствующее существо биома, реликвия дополнительно усиливает урон на %d%%." % [str(item.get("affinity_name", item.get("landscape_affinity", ""))), str(item.get("affinity_effect", {})), int(round(clampf(float(item.get("affinity_combat_bonus", 0.06)), 0.0, 0.12) * 100.0))]
	body += "\n\nСейчас надето: %s" % (str(current.get("name", "ничего")) if not current.is_empty() else "слот пуст")
	if not current.is_empty():
		body += " · сила %.1f · бонусы %s" % [inventory_system.item_power(current), _format_item_bonus(current)]
	var power_delta := inventory_system.item_power(item) - inventory_system.item_power(current) if not current.is_empty() else 0.0
	body += "\nСравнение силы: %s" % ItemTextPresenterScript.format_item_comparison(not current.is_empty(), power_delta)
	body += "\n\nСРАВНЕНИЕ БОНУСОВ\n" + ItemTextPresenterScript.format_stat_comparison(item, current)
	var current_stats: Dictionary = inventory_system.total_equipment_stats(manager.equipment)
	var candidate_loadout: Dictionary = manager.equipment.duplicate(true)
	candidate_loadout[slot] = item.duplicate(true)
	var candidate_stats: Dictionary = inventory_system.total_equipment_stats(candidate_loadout)
	body += "\n\n" + ItemTextPresenterScript.format_loadout_synergy_preview(current_stats, candidate_stats, InventorySystemScript.SYNERGY_DEFS)
	var buttons: Array = []
	buttons.append({"text": "Надеть в слот · %s" % InventorySystemScript.SLOT_NAMES.get(slot, slot), "callback": Callable(self, "_on_run_equip").bind(item_id), "accent": true, "disabled": not inventory_system.can_equip_item(item, slot), "tooltip": "Правый клик по ячейке выполняет то же действие."})
	buttons.append({"text": "← Назад к ячейкам", "callback": Callable(self, "_open_run_backpack"), "accent": false})
	_show_modal("Предмет рюкзака", body, buttons, "backpack")

func can_inventory_item_equip(item_id: String, slot: String) -> bool:
	if manager == null or not InventorySystemScript.EQUIPMENT_SLOTS.has(slot):
		return false
	var item: Dictionary = manager.find_run_item(item_id)
	return not item.is_empty() and inventory_system.can_equip_item(item, slot)

func can_reorder_inventory_item(item_id: String, target_index: int) -> bool:
	return manager != null and manager.can_reorder_run_bag_item(item_id, target_index)

func on_inventory_quick_equip(item_id: String) -> void:
	_on_run_equip(item_id)

func on_inventory_drag_drop(item_id: String, slot: String, target_index: int) -> void:
	if not slot.is_empty():
		if not can_inventory_item_equip(item_id, slot):
			_open_message("Несовместимый слот", "Этот предмет нельзя надеть в выбранный слот. Другие типы слотов останутся недоступны.")
			return
		_on_run_equip(item_id)
		return
	var result: Dictionary = manager.reorder_run_bag_item(item_id, target_index) if manager != null else {"ok": false, "message": "Экспедиция недоступна."}
	if not bool(result.get("ok", false)):
		_open_message("Порядок не изменён", str(result.get("message", "Не удалось переместить предмет.")))
		return
	_sync_expedition_view(false)
	_open_run_backpack()

func _on_run_equip(item_id: String) -> void:
	var result: Dictionary = manager.equip_bag_item(item_id)
	if not bool(result.get("ok", false)):
		_open_message("Экипировка не изменена", str(result.get("message", "Не удалось надеть предмет.")))
		return
	_sync_expedition_view(false)
	_open_run_backpack()

func _on_run_unequip(slot: String) -> void:
	var result: Dictionary = manager.unequip_run_slot(slot)
	if not bool(result.get("ok", false)):
		_open_message("Не удалось снять предмет", str(result.get("message", "Не удалось снять предмет.")))
		return
	_sync_expedition_view(false)
	_open_run_backpack()

func _on_run_discard(item_id: String) -> void:
	var result: Dictionary = manager.discard_run_bag_item(item_id)
	if not bool(result.get("ok", false)):
		_open_message("Рюкзак не изменён", str(result.get("message", "Не удалось убрать предмет.")))
		return
	_sync_expedition_view(false)
	_open_run_backpack()

func _resume_after_backpack() -> void:
	_close_overlay(false)
	if manager != null and manager.active:
		manager.set_pause(false)
		_sync_expedition_view(false)
		if pause_button != null:
			call_deferred("_focus_control_if_valid", pause_button)

func _open_message(title_text: String, body_text: String) -> void:
	_show_modal(title_text, body_text, [{"text": "Понятно", "callback": Callable(self, "_close_overlay"), "accent": true}], "message")

func _show_tiny_notice(message: String) -> void:
	# The base is rebuilt only after a successful upgrade; brief non-blocking feedback stays in the log area.
	if screen_mode == "base" and content_root.get_child_count() > 0:
		var target: Node = content_root.get_child(content_root.get_child_count() - 1)
		if target is PanelContainer:
			var box := target.get_child(0)
			if box is VBoxContainer:
				box.add_child(_label(message, 11, C_ACCENT))

func _open_developer_tools() -> void:
	# Diagnostics are strictly read-only and must not ship as a release UI feature.
	if not OS.is_debug_build():
		return
	_prepare_overlay()
	modal_kind = "developer_tools"
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.025, 0.03, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel := _make_panel(center, Color("#14272e"), 18)
	panel.custom_minimum_size = Vector2(minf(1120.0, get_viewport_rect().size.x - 32.0), minf(760.0, get_viewport_rect().size.y - 32.0))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var layout := VBoxContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", 8)
	panel.add_child(layout)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	layout.add_child(title_row)
	var title := _label("ИНСТРУМЕНТЫ РАЗРАБОТЧИКА", 18, C_TEXT, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_button("Обновить", Callable(self, "_refresh_developer_tools"), false))
	title_row.add_child(_button("Копировать отчёт", Callable(self, "_copy_developer_report"), false))
	title_row.add_child(_button("Закрыть", Callable(self, "_close_overlay"), false))
	developer_status_label = _label("Диагностика только читает состояние и не меняет сохранения или правила игры.", 11, C_MUTED)
	layout.add_child(developer_status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)
	var report_box := _make_panel(scroll, Color("#0f2027"), 12)
	report_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	developer_report_label = _label("", 12, C_TEXT)
	developer_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	developer_report_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	developer_report_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	report_box.add_child(developer_report_label)
	_refresh_developer_tools()
	call_deferred("_configure_overlay_focus", true)

func _refresh_developer_tools() -> void:
	if not OS.is_debug_build() or not is_instance_valid(developer_report_label):
		return
	developer_report_label.text = _build_developer_diagnostic_report()
	if is_instance_valid(developer_status_label):
		developer_status_label.text = "Отчёт обновлён · только чтение · " + Time.get_datetime_string_from_system(false, true)

func _copy_developer_report() -> void:
	if not OS.is_debug_build():
		return
	var report := _build_developer_diagnostic_report()
	DisplayServer.clipboard_set(report)
	if is_instance_valid(developer_status_label):
		developer_status_label.text = "Отчёт скопирован в буфер обмена. Сохранения не изменялись."

func _build_developer_diagnostic_report() -> String:
	return developer_diagnostics_report.build_report(manager, screen_mode)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var focused_control := get_viewport().gui_get_focus_owner()
	if focused_control is LineEdit or focused_control is TextEdit:
		if key_event.keycode == KEY_ESCAPE:
			(focused_control as Control).release_focus()
			get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_F9:
		if not OS.is_debug_build():
			return
		if overlay != null and overlay.visible:
			if modal_kind == "developer_tools":
				_close_overlay()
			else:
				return
		else:
			_open_developer_tools()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_F1:
		if overlay != null and overlay.visible and modal_kind in ["event", "perk", "confirm", "confirm_reset", "confirm_salvage"]:
			return
		_open_help_menu()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE:
		if overlay != null and overlay.visible:
			if modal_kind == "settings":
				_close_settings()
			elif modal_kind in ["event", "perk", "confirm", "confirm_reset", "confirm_salvage"]:
				return # Decisions and destructive confirmations cannot be dismissed accidentally.
			else:
				_close_overlay()
		elif screen_mode == "expedition" and manager != null and manager.active and manager.pending_event.is_empty() and manager.pending_perk_count == 0:
			manager.set_pause(not manager.paused)
			_sync_expedition_view(false)
		get_viewport().set_input_as_handled()
		return
	if overlay != null and overlay.visible:
		return
	if screen_mode != "expedition" or manager == null or not manager.active:
		return
	if not manager.pending_event.is_empty() or manager.pending_perk_count > 0:
		return
	if key_event.keycode == KEY_SPACE:
		manager.set_pause(not manager.paused)
		_sync_expedition_view(false)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_1:
		_set_speed(1.0)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_2:
		_set_speed(2.0)
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_3:
		_set_speed(3.0)
		get_viewport().set_input_as_handled()

func _open_help_menu() -> void:
	var body_text := _t("help.body")
	var buttons: Array = []
	if not GameState.tutorial_completed and GameState.tutorial_page < TUTORIAL_STEPS.size():
		buttons.append({"text": _t("modal.button.continue_tutorial_step") % (GameState.tutorial_page + 1), "callback": Callable(self, "_show_tutorial_step").bind(GameState.tutorial_page), "accent": true})
	buttons.append({"text": _t("help.button.restart_tutorial"), "callback": Callable(self, "_restart_tutorial"), "accent": false})
	buttons.append({"text": _t("help.button.close"), "callback": Callable(self, "_close_overlay"), "accent": false})
	_show_modal(_t("help.title"), body_text, buttons, "help")

func _restart_tutorial() -> void:
	GameState.tutorial_page = 0
	GameState.tutorial_completed = false
	GameState.save_now()
	_show_tutorial_step(0)

func _show_tutorial_step(step_index: int) -> void:
	var bounded_step: int = clampi(step_index, 0, TUTORIAL_STEPS.size())
	if bounded_step >= TUTORIAL_STEPS.size():
		GameState.tutorial_page = TUTORIAL_STEPS.size()
		GameState.tutorial_completed = true
		GameState.save_now()
		_close_overlay()
		_show_tiny_notice(_t("modal.tutorial.done"))
		return
	GameState.tutorial_page = bounded_step
	GameState.tutorial_completed = false
	GameState.save_now()
	var step: Dictionary = TUTORIAL_STEPS[bounded_step]
	var buttons: Array = []
	if bounded_step > 0:
		buttons.append({"text": _t("modal.button.back"), "callback": Callable(self, "_show_tutorial_step").bind(bounded_step - 1), "accent": false})
	var next_text := _t("modal.button.next") if bounded_step < TUTORIAL_STEPS.size() - 1 else _t("modal.button.finish_tutorial")
	buttons.append({"text": next_text, "callback": Callable(self, "_show_tutorial_step").bind(bounded_step + 1), "accent": true})
	buttons.append({"text": _t("modal.button.skip_tutorial"), "callback": Callable(self, "_finish_tutorial"), "accent": false})
	var title_text := _t(str(step.get("title_key", "")))
	var body_text := _t(str(step.get("body_key", ""))) + "\n\n" + _t(str(step.get("tip_key", "")))
	_show_modal(title_text, body_text, buttons, "tutorial")

func _finish_tutorial() -> void:
	GameState.tutorial_page = TUTORIAL_STEPS.size()
	GameState.tutorial_completed = true
	GameState.save_now()
	_close_overlay()
	_show_tiny_notice(_t("modal.tutorial.done"))

func _open_settings() -> void:
	var is_reset_cancel := modal_kind == "confirm_reset"
	if not is_reset_cancel:
		_resume_after_settings = screen_mode == "expedition" and manager != null and manager.active and not manager.paused
	if _resume_after_settings and screen_mode == "expedition" and manager.active and not manager.paused:
		manager.set_pause(true)
	_show_modal(_t("settings.title"), _t("settings.description"), [], "settings")
	var panel := overlay.get_child(1).get_child(0) as PanelContainer
	var settings_scroll := panel.get_child(0) as ScrollContainer
	var box := settings_scroll.get_child(0) as VBoxContainer
	for entry in [
		{"key": "master_volume", "label": "Общая громкость"},
		{"key": "music_volume", "label": "Музыка"},
		{"key": "effects_volume", "label": "Эффекты"}
	]:
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		box.add_child(row)
		row.add_child(_label(_t("settings.volume." + str(entry.key).trim_suffix("_volume")), 13, C_TEXT))
		var slider := HSlider.new()
		_apply_keyboard_focus_outline(slider)
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(GameState.settings.get(str(entry.key), 0.8))
		slider.value_changed.connect(_on_setting_changed.bind(str(entry.key)))
		row.add_child(slider)
	var scale_row := VBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 4)
	box.add_child(scale_row)
	scale_row.add_child(_label(_t("settings.scale.title"), 13, C_TEXT, true))
	var scale_option := OptionButton.new()
	_apply_keyboard_focus_outline(scale_option)
	for scale_choice in [{"label": _t("settings.scale.compact"), "value": 0.85}, {"label": _t("settings.scale.standard"), "value": 1.0}, {"label": _t("settings.scale.large"), "value": 1.1}]:
		scale_option.add_item(str(scale_choice.label))
		scale_option.set_item_metadata(scale_option.item_count - 1, float(scale_choice.value))
	var selected_scale := float(GameState.settings.get("ui_scale", 1.0))
	var selected_scale_index := 1
	for scale_index in range(scale_option.item_count):
		if is_equal_approx(float(scale_option.get_item_metadata(scale_index)), selected_scale):
			selected_scale_index = scale_index
	scale_option.select(selected_scale_index)
	scale_option.item_selected.connect(_on_ui_scale_selected)
	scale_row.add_child(scale_option)
	var window_row := VBoxContainer.new()
	window_row.add_theme_constant_override("separation", 4)
	box.add_child(window_row)
	window_row.add_child(_label(_t("settings.window_mode.title"), 13, C_TEXT, true))
	var window_option := OptionButton.new()
	_apply_keyboard_focus_outline(window_option)
	window_option.add_item(_t("settings.window_mode.windowed"))
	window_option.add_item(_t("settings.window_mode.fullscreen"))
	window_option.select(1 if str(GameState.settings.get("window_mode", "windowed")) == "fullscreen" else 0)
	window_option.item_selected.connect(_on_window_mode_selected)
	window_row.add_child(window_option)
	var animation_row := VBoxContainer.new()
	animation_row.add_theme_constant_override("separation", 4)
	box.add_child(animation_row)
	animation_row.add_child(_label(_t("settings.animation.title"), 13, C_TEXT, true))
	var animation_slider := HSlider.new()
	_apply_keyboard_focus_outline(animation_slider)
	animation_slider.min_value = 0.5
	animation_slider.max_value = 1.5
	animation_slider.step = 0.25
	animation_slider.value = float(GameState.settings.get("animation_speed", 1.0))
	animation_slider.value_changed.connect(_on_animation_speed_changed)
	animation_row.add_child(animation_slider)
	animation_row.add_child(_label(_t("settings.animation.description"), 12, C_MUTED))
	for accessibility_option in [
		{"key": "reduced_motion", "label": _t("settings.accessibility.reduced_motion")},
		{"key": "reduce_flashes", "label": _t("settings.accessibility.reduce_flashes")},
		{"key": "high_contrast", "label": _t("settings.accessibility.high_contrast")},
		{"key": "status_symbols", "label": _t("settings.accessibility.status_symbols")}
	]:
		var toggle := CheckBox.new()
		toggle.text = str(accessibility_option.get("label", "Доступность"))
		_apply_keyboard_focus_outline(toggle)
		toggle.button_pressed = bool(GameState.settings.get(str(accessibility_option.get("key", "")), false))
		toggle.toggled.connect(_on_accessibility_setting_changed.bind(str(accessibility_option.get("key", ""))))
		box.add_child(toggle)
	if screen_mode == "base":
		var export_save_button := _button(_t("settings.save.export"), Callable(self, "_open_save_export_dialog"), false)
		export_save_button.tooltip_text = "Сохраняет копию прогресса и текущей контрольной точки в выбранный JSON-файл."
		box.add_child(export_save_button)
		var import_save_button := _button(_t("settings.save.import"), Callable(self, "_confirm_import_save"), false)
		import_save_button.tooltip_text = "Заменяет текущий профиль содержимым выбранного совместимого файла; перед импортом создаётся резервная копия текущего профиля."
		box.add_child(import_save_button)
		var reset_button := _button(_t("settings.save.reset"), Callable(self, "_open_reset_confirmation"), false)
		box.add_child(reset_button)
	box.add_child(_button(_t("settings.button.close"), Callable(self, "_close_settings"), true))
	call_deferred("_configure_overlay_focus", true, "settings")

func _open_save_export_dialog() -> void:
	_close_overlay(false)
	var dialog := FileDialog.new()
	dialog.title = "Экспорт сохранения Abyss Loop"
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.current_file = "abyss_loop_save.json"
	dialog.add_filter("*.json ; Сохранение Abyss Loop (JSON)")
	dialog.file_selected.connect(_export_save_selected)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)

func _export_save_selected(path: String) -> void:
	var ok: bool = SaveSystem.export_save_file(path, GameState.export_save_data())
	if ok:
		_open_message("Экспорт завершён", "Копия сохранения создана. Внутренний профиль игры не изменён.\n\nФайл: " + path)
	else:
		_open_message("Не удалось экспортировать", "Файл не записан. Проверьте путь и доступ к выбранной папке; исходное сохранение не изменялось.")

func _confirm_import_save() -> void:
	_show_modal("Импортировать сохранение?", "Содержимое выбранного файла заменит текущий профиль. Перед заменой создаётся резервная копия текущего сохранения. После успешного импорта перезапустите игру, чтобы загрузить импортированный прогресс.", [
		{"text": "Отмена", "callback": Callable(self, "_open_settings"), "accent": false},
		{"text": "Выбрать файл…", "callback": Callable(self, "_open_save_import_dialog"), "accent": true}
	], "confirm")

func _open_save_import_dialog() -> void:
	_close_overlay(false)
	var dialog := FileDialog.new()
	dialog.title = "Импорт сохранения Abyss Loop"
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json ; Сохранение Abyss Loop (JSON)")
	dialog.file_selected.connect(_import_save_selected)
	add_child(dialog)
	dialog.popup_centered_ratio(0.72)

func _import_save_selected(path: String) -> void:
	var ok: bool = SaveSystem.import_save_file(path)
	if ok:
		_open_message("Импорт завершён", "Сохранение проверено и записано в профиль. Перезапустите игру перед продолжением; резервная копия прежнего профиля сохранена.")
	else:
		_open_message("Импорт отклонён", "Файл повреждён, несовместим или содержит недопустимые значения. Текущий профиль не заменён.")

func _close_settings() -> void:
	_close_overlay()
	if _resume_after_settings and screen_mode == "expedition" and manager != null and manager.active:
		manager.set_pause(false)
	_resume_after_settings = false

func _on_accessibility_setting_changed(value: bool, key: String) -> void:
	if not ["reduced_motion", "reduce_flashes", "high_contrast", "status_symbols"].has(key):
		return
	GameState.settings[key] = value
	GameState.save_now()
	_apply_accessibility_settings()
	if key == "high_contrast":
		_apply_contrast_to_tree(self)

func _on_ui_scale_selected(index: int) -> void:
	var scale_value: float = float([0.85, 1.0, 1.1][clampi(index, 0, 2)])
	GameState.settings["ui_scale"] = scale_value
	_apply_display_settings()
	GameState.save_now()

func _on_window_mode_selected(index: int) -> void:
	GameState.settings["window_mode"] = "fullscreen" if index == 1 else "windowed"
	_apply_display_settings()
	GameState.save_now()

func _on_animation_speed_changed(value: float) -> void:
	GameState.settings["animation_speed"] = clampf(value, 0.5, 1.5)
	_apply_accessibility_settings()
	GameState.save_now()

func _enemy_role_label(role_id: String) -> String:
	# Role labels are redundant visual cues; behavior and combat rules remain data-driven.
	match role_id:
		"fast":
			return _t("enemy.role.fast")
		"tank":
			return _t("enemy.role.tank")
		"caster":
			return _t("enemy.role.caster")
		"support":
			return _t("enemy.role.support")
		"hunter":
			return _t("enemy.role.hunter")
		"boss":
			return _t("enemy.role.boss")
		_:
			return _t("enemy.role.unknown")

func _apply_display_settings() -> void:
	var window := get_window()
	if window == null:
		return
	window.content_scale_factor = clampf(float(GameState.settings.get("ui_scale", 1.0)), 0.85, 1.1)
	var requested_mode := str(GameState.settings.get("window_mode", "windowed"))
	if requested_mode == "fullscreen":
		window.mode = Window.MODE_FULLSCREEN
	else:
		if window.mode == Window.MODE_FULLSCREEN:
			window.mode = Window.MODE_WINDOWED
			window.size = Vector2i(1440, 900)

func _apply_accessibility_settings() -> void:
	if is_instance_valid(route_view) and route_view.has_method("configure_accessibility"):
		route_view.configure_accessibility(
			bool(GameState.settings.get("reduced_motion", false)),
			bool(GameState.settings.get("reduce_flashes", true)),
			bool(GameState.settings.get("high_contrast", false)),
			float(GameState.settings.get("animation_speed", 1.0))
		)
		route_view.queue_redraw()

func _apply_contrast_to_tree(node: Node) -> void:
	if node is Label:
		var label := node as Label
		if label.get_theme_color("font_color") == C_MUTED or label.get_theme_color("font_color") == Color("#e0eee4"):
			label.add_theme_color_override("font_color", Color("#e0eee4") if bool(GameState.settings.get("high_contrast", false)) else C_MUTED)
		label.add_theme_color_override("font_outline_color", Color("#061014") if bool(GameState.settings.get("high_contrast", false)) else Color(0, 0, 0, 0.2))
		label.add_theme_constant_override("outline_size", 1 if bool(GameState.settings.get("high_contrast", false)) else 0)
	if node is PanelContainer:
		var panel := node as PanelContainer
		var style_value := panel.get_theme_stylebox("panel")
		if style_value is StyleBoxFlat:
			var panel_style := (style_value as StyleBoxFlat).duplicate() as StyleBoxFlat
			panel_style.border_color = Color("#d2e8d9") if bool(GameState.settings.get("high_contrast", false)) else Color("#526b52")
			panel_style.set_border_width_all(3 if bool(GameState.settings.get("high_contrast", false)) else 2)
			panel.add_theme_stylebox_override("panel", panel_style)
	if node is Button:
		var button := node as Button
		for style_name in ["normal", "hover", "pressed", "disabled"]:
			var style_value := button.get_theme_stylebox(style_name)
			if style_value is StyleBoxFlat:
				var button_style := (style_value as StyleBoxFlat).duplicate() as StyleBoxFlat
				button_style.border_color = Color("#f0f6ef") if bool(GameState.settings.get("high_contrast", false)) else (Color("#59665e") if style_name == "disabled" else Color("#526f58"))
				button_style.set_border_width_all(3 if bool(GameState.settings.get("high_contrast", false)) else 2)
				button.add_theme_stylebox_override(style_name, button_style)
	for child in node.get_children():
		_apply_contrast_to_tree(child)

func _on_setting_changed(value: float, key: String) -> void:
	if not ["master_volume", "music_volume", "effects_volume"].has(key):
		return
	GameState.settings[key] = clampf(value, 0.0, 1.0)
	var buses := {"master_volume": "Master", "music_volume": "Music", "effects_volume": "SFX"}
	var bus_index := AudioServer.get_bus_index(str(buses.get(key, "Master")))
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, value <= 0.001)
		AudioServer.set_bus_volume_linear(bus_index, maxf(0.0001, value))
	GameState.save_now()

func _ensure_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(str(bus_name)) < 0:
			AudioServer.add_bus()
			var bus_index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus_index, str(bus_name))
			AudioServer.set_bus_send(bus_index, "Master")

func _apply_audio_settings() -> void:
	var buses := {"master_volume": "Master", "music_volume": "Music", "effects_volume": "SFX"}
	for setting_key in buses.keys():
		var bus_index := AudioServer.get_bus_index(str(buses[setting_key]))
		if bus_index >= 0:
			var value := clampf(float(GameState.settings.get(setting_key, 0.8)), 0.0, 1.0)
			AudioServer.set_bus_mute(bus_index, value <= 0.001)
			AudioServer.set_bus_volume_linear(bus_index, maxf(0.0001, value))

func _open_reset_confirmation() -> void:
	_show_modal("Сбросить весь прогресс?", "Будут удалены ресурсы, улучшения и статистика убежища. Действие нельзя отменить.", [
		{"text": "Оставить как есть", "callback": Callable(self, "_open_settings"), "accent": false},
		{"text": "Сбросить прогресс", "callback": Callable(self, "_reset_progress"), "accent": true}
	], "confirm_reset")

func _reset_progress() -> void:
	_close_overlay(false)
	GameState.reset_progress()
	_render_base()

