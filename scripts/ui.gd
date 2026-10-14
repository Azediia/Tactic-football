class_name GameUI
extends CanvasLayer
## Interface du match : score, état de la pause, carte du joueur, menu contextuel d'ordres,
## infobulle de probabilités, journal des jets de dés et bannières.

const PANEL_BG := Color(0.07, 0.09, 0.13, 0.9)
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.09)
const TEXT := Color(0.93, 0.95, 0.98)
const MUTED := Color(0.6, 0.66, 0.74)
const ACCENT := Color(0.25, 0.8, 0.75)
const GOOD := Color(0.35, 0.85, 0.5)
const WARN := Color(1.0, 0.7, 0.25)
const BAD := Color(0.95, 0.4, 0.4)
const BLUE := Color(0.2, 0.45, 0.95)
const MAX_EVENTS := 7
const EVENT_LIFETIME := 9.0

var main: Main

var _root: Control
var _score_labels: Array[Label] = []
var _clock_label: Label
var _half_label: Label
var _pause_dot: ColorRect
var _pause_label: Label
var _pause_sub: Label
var _cooldown_bar: ProgressBar
var _speed_label: Label
var _feed: VBoxContainer
var _events: Array = []  # {panel, born}

var _badge_label: Label
var _name_label: Label
var _role_label: Label
var _stat_rows := {}  # clé -> {"bar", "value"}
var _orders_label: Label

var _menu: PanelContainer
var _menu_title: Label
var _mode_buttons := {}
var _allure_buttons: Array[Button] = []
var _move_box: VBoxContainer
var _pass_box: VBoxContainer
var _shoot_box: VBoxContainer
var _tackle_box: VBoxContainer
var _aerial_buttons: Array[Button] = []
var _height_buttons: Array[Button] = []
var _pass_power_slider: HSlider
var _pass_power_label: Label
var _shot_power_slider: HSlider
var _shot_power_label: Label
var _curve_labels: Array[Label] = []
var _move_info: Label

var _tooltip: PanelContainer
var _tip_title: Label
var _tip_chance: Label
var _tip_detail: Label
var _tip_warning: Label

var _hint_label: Label
var _banner_box: CenterContainer
var _banner_title: Label
var _banner_sub: Label
var _banner_until := 0
var _end_box: CenterContainer
var _end_score: Label


func setup(p_main: Main) -> void:
	main = p_main
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_root.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	column.add_child(_build_top_row())
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	column.add_child(_build_bottom_row())

	_build_menu()
	_build_tooltip()
	_build_banner()
	_build_end_screen()


# --- Construction --------------------------------------------------------------------------

func _build_top_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Gauche : état de la pause.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(left)
	var pause_panel := _panel(Color(0.07, 0.09, 0.13, 0.9), 12, 10)
	pause_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(pause_panel)
	var pause_box := VBoxContainer.new()
	pause_box.add_theme_constant_override("separation", 6)
	pause_panel.add_child(pause_box)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	pause_box.add_child(status_row)
	_pause_dot = ColorRect.new()
	_pause_dot.custom_minimum_size = Vector2(12, 12)
	_pause_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_row.add_child(_pause_dot)
	_pause_label = _label("EN DIRECT", 17)
	status_row.add_child(_pause_label)
	_cooldown_bar = _bar(ACCENT, 6)
	_cooldown_bar.custom_minimum_size = Vector2(230, 6)
	pause_box.add_child(_cooldown_bar)
	_pause_sub = _label("", 13, MUTED)
	pause_box.add_child(_pause_sub)
	_speed_label = _label("", 13, MUTED)
	pause_box.add_child(_speed_label)

	# Centre : tableau d'affichage.
	var board := _panel(Color(0.06, 0.08, 0.12, 0.94), 14, 10)
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(board)
	var board_row := HBoxContainer.new()
	board_row.add_theme_constant_override("separation", 14)
	board.add_child(board_row)
	for team in 2:
		if team == 1:
			var middle := VBoxContainer.new()
			middle.custom_minimum_size = Vector2(96, 0)
			_clock_label = _label("00:00", 24)
			_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_half_label = _label("1re mi-temps", 12, MUTED)
			_half_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			middle.add_child(_clock_label)
			middle.add_child(_half_label)
			board_row.add_child(middle)
		var chip := ColorRect.new()
		chip.color = MatchDirector.TEAM_COLORS[team]
		chip.custom_minimum_size = Vector2(8, 34)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var name_label := _label(MatchDirector.TEAM_NAMES[team], 18)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var score_label := _label("0", 36)
		_score_labels.append(score_label)
		if team == 0:
			board_row.add_child(chip)
			board_row.add_child(name_label)
			board_row.add_child(score_label)
		else:
			board_row.add_child(score_label)
			board_row.add_child(name_label)
			board_row.add_child(chip)

	# Droite : journal des événements.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	_feed = VBoxContainer.new()
	_feed.add_theme_constant_override("separation", 4)
	_feed.size_flags_horizontal = Control.SIZE_SHRINK_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_feed)
	return row


func _build_bottom_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	var keys := _panel(PANEL_BG, 12, 10)
	keys.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(keys)
	var keys_label := _label("Espace  pause / reprise\nÉchap  annuler la visée\n1 2 3  marche, trot, sprint\nMolette  effet du ballon\nT  vitesse du temps\nClic droit  effacer les ordres", 13, MUTED)
	keys.add_child(keys_label)
	var spacer_left := Control.new()
	spacer_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer_left)

	# Bandeau d'aide au centre.
	var hint := _panel(PANEL_BG, 12, 10)
	hint.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(hint)
	_hint_label = _label("", 15)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_child(_hint_label)

	var spacer_right := Control.new()
	spacer_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer_right)

	# Carte du joueur sélectionné.
	var card := _panel(PANEL_BG, 14, 12)
	card.custom_minimum_size = Vector2(310, 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(card)
	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 7)
	card.add_child(card_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	card_box.add_child(header)
	var badge := _panel(BLUE, 22, 0)
	badge.custom_minimum_size = Vector2(44, 44)
	header.add_child(badge)
	_badge_label = _label("1", 22)
	_badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(_badge_label)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(names)
	_name_label = _label("", 20)
	_role_label = _label("", 13, MUTED)
	names.add_child(_name_label)
	names.add_child(_role_label)

	var stat_keys := [["vitesse", "Vitesse"], ["technique", "Technique"], ["passe", "Passe"], ["frappe", "Frappe"], ["defense", "Défense"], ["stamina", "Énergie"]]
	for entry in stat_keys:
		var stat_row := HBoxContainer.new()
		stat_row.add_theme_constant_override("separation", 8)
		card_box.add_child(stat_row)
		var name_label := _label(entry[1], 13, MUTED)
		name_label.custom_minimum_size = Vector2(76, 0)
		stat_row.add_child(name_label)
		var bar := _bar(ACCENT, 8)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stat_row.add_child(bar)
		var value_label := _label("", 13)
		value_label.custom_minimum_size = Vector2(30, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_row.add_child(value_label)
		_stat_rows[entry[0]] = {"bar": bar, "value": value_label}

	_orders_label = _label("", 13, MUTED)
	_orders_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_orders_label.custom_minimum_size = Vector2(280, 0)
	card_box.add_child(_orders_label)

	return row


func _build_menu() -> void:
	_menu = _panel(Color(0.06, 0.08, 0.12, 0.96), 14, 12)
	_menu.custom_minimum_size = Vector2(272, 0)
	_menu.visible = false
	_root.add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_menu.add_child(box)

	_menu_title = _label("", 18)
	box.add_child(_menu_title)
	box.add_child(HSeparator.new())

	var group := ButtonGroup.new()
	var modes := [[Main.Mode.MOVE, "Courir"], [Main.Mode.PASS, "Passer"], [Main.Mode.SHOOT, "Tirer"], [Main.Mode.TACKLE, "Tacler"]]
	var mode_row := GridContainer.new()
	mode_row.columns = 2
	mode_row.add_theme_constant_override("h_separation", 6)
	mode_row.add_theme_constant_override("v_separation", 6)
	box.add_child(mode_row)
	for entry in modes:
		var button := _toggle(entry[1], group)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mode_value: int = entry[0]
		button.pressed.connect(func(): main.set_mode(mode_value))
		mode_row.add_child(button)
		_mode_buttons[mode_value] = button

	# Sous-menu : courir.
	_move_box = VBoxContainer.new()
	_move_box.add_theme_constant_override("separation", 6)
	box.add_child(_move_box)
	_move_box.add_child(_label("Allure des prochains points", 13, MUTED))
	var allure_group := ButtonGroup.new()
	for allure in 3:
		var button := _toggle(Player.ALLURE_NAMES[allure], allure_group)
		var allure_value: int = allure
		button.pressed.connect(func(): main.set_allure(allure_value))
		_move_box.add_child(button)
		_allure_buttons.append(button)
	_move_info = _label("Clic sur le terrain : ajoute un point de passage.", 13, MUTED)
	_move_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_move_info.custom_minimum_size = Vector2(244, 0)
	_move_box.add_child(_move_info)

	# Sous-menu : passer.
	_pass_box = VBoxContainer.new()
	_pass_box.add_theme_constant_override("separation", 6)
	box.add_child(_pass_box)
	var aerial_group := ButtonGroup.new()
	var aerial_row := HBoxContainer.new()
	aerial_row.add_theme_constant_override("separation", 6)
	_pass_box.add_child(aerial_row)
	for i in 2:
		var button := _toggle(["Au sol", "Aérienne"][i], aerial_group)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var is_aerial := i == 1
		button.pressed.connect(func(): main.opt_aerial = is_aerial)
		aerial_row.add_child(button)
		_aerial_buttons.append(button)
	_pass_power_label = _label("", 13, MUTED)
	_pass_box.add_child(_pass_power_label)
	_pass_power_slider = HSlider.new()
	_pass_power_slider.min_value = 70
	_pass_power_slider.max_value = 130
	_pass_power_slider.step = 5
	_pass_power_slider.value_changed.connect(func(v: float): main.opt_pass_power = v / 100.0)
	_pass_box.add_child(_pass_power_slider)
	_curve_labels.append(_add_curve_label(_pass_box))
	_pass_box.add_child(_hint("Clic sur un coéquipier ou sur le terrain."))

	# Sous-menu : tirer.
	_shoot_box = VBoxContainer.new()
	_shoot_box.add_theme_constant_override("separation", 6)
	box.add_child(_shoot_box)
	var height_group := ButtonGroup.new()
	var height_row := HBoxContainer.new()
	height_row.add_theme_constant_override("separation", 6)
	_shoot_box.add_child(height_row)
	for i in 3:
		var button := _toggle(Rules.SHOT_HEIGHT_NAMES[i], height_group)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var level: int = i
		button.pressed.connect(func(): main.opt_height = level)
		height_row.add_child(button)
		_height_buttons.append(button)
	_shot_power_label = _label("", 13, MUTED)
	_shoot_box.add_child(_shot_power_label)
	_shot_power_slider = HSlider.new()
	_shot_power_slider.min_value = 30
	_shot_power_slider.max_value = 100
	_shot_power_slider.step = 5
	_shot_power_slider.value_changed.connect(func(v: float): main.opt_shot_power = v / 100.0)
	_shoot_box.add_child(_shot_power_slider)
	_curve_labels.append(_add_curve_label(_shoot_box))
	_shoot_box.add_child(_hint("Clic dans le but adverse pour viser."))

	# Sous-menu : tacler.
	_tackle_box = VBoxContainer.new()
	box.add_child(_tackle_box)
	_tackle_box.add_child(_hint("Clic sur un adversaire : le joueur le poursuit et tente de lui prendre le ballon."))

	box.add_child(HSeparator.new())
	var clear := _button("Effacer les ordres")
	clear.pressed.connect(func(): main.clear_selected_orders())
	box.add_child(clear)


func _add_curve_label(parent: Control) -> Label:
	var label := _label("", 13, MUTED)
	parent.add_child(label)
	return label


func _hint(text: String) -> Label:
	var label := _label(text, 12, MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(244, 0)
	return label


func _build_tooltip() -> void:
	_tooltip = _panel(Color(0.05, 0.07, 0.1, 0.95), 10, 10)
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tooltip)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	_tooltip.add_child(box)
	_tip_title = _label("", 14, MUTED)
	_tip_chance = _label("", 26)
	_tip_detail = _label("", 12, MUTED)
	_tip_warning = _label("", 13, WARN)
	for label in [_tip_title, _tip_chance, _tip_detail, _tip_warning]:
		box.add_child(label)


func _build_banner() -> void:
	_banner_box = CenterContainer.new()
	_banner_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.visible = false
	_root.add_child(_banner_box)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_box.add_child(box)
	_banner_title = _label("", 72)
	_banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner_title.add_theme_constant_override("outline_size", 12)
	_banner_sub = _label("", 28, ACCENT)
	_banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner_sub.add_theme_constant_override("outline_size", 8)
	box.add_child(_banner_title)
	box.add_child(_banner_sub)


func _build_end_screen() -> void:
	_end_box = CenterContainer.new()
	_end_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_box.visible = false
	_root.add_child(_end_box)
	var panel := _panel(Color(0.06, 0.08, 0.12, 0.97), 18, 28)
	_end_box.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := _label("FIN DU MATCH", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_end_score = _label("", 56, ACCENT)
	_end_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_score)
	var replay := _button("Rejouer")
	replay.pressed.connect(func(): main.restart_match())
	box.add_child(replay)


# --- Fabrique de widgets -------------------------------------------------------------------

func _style(bg: Color, radius: int, margin: int, border := PANEL_BORDER) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.set_content_margin_all(margin)
	return style


func _panel(bg: Color, radius: int, margin: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(bg, radius, margin))
	return panel


func _label(text: String, size: int, color := TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _bar(color: Color, height: int) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, height)
	bar.add_theme_stylebox_override("background", _style(Color(1, 1, 1, 0.08), 4, 0, Color(0, 0, 0, 0)))
	bar.add_theme_stylebox_override("fill", _style(color, 4, 0, Color(0, 0, 0, 0)))
	return bar


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_stylebox_override("normal", _style(Color(0.14, 0.17, 0.23), 8, 8))
	button.add_theme_stylebox_override("hover", _style(Color(0.2, 0.25, 0.33), 8, 8))
	button.add_theme_stylebox_override("pressed", _style(Color(0.16, 0.5, 0.5), 8, 8, ACCENT))
	button.add_theme_stylebox_override("hover_pressed", _style(Color(0.2, 0.58, 0.58), 8, 8, ACCENT))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 8, 8, Color(0, 0, 0, 0)))
	return button


func _toggle(text: String, group: ButtonGroup) -> Button:
	var button := _button(text)
	button.toggle_mode = true
	button.button_group = group
	return button


# --- Événements ----------------------------------------------------------------------------

func add_event(text: String, kind: String) -> void:
	var color := TEXT
	if kind == "goal":
		color = Color(1.0, 0.85, 0.3)
	elif kind == "info":
		color = MUTED
	else:
		var verdict := text.get_slice(": ", text.count(": ")) if text.contains(": ") else text
		if verdict.contains("échec critique"):
			color = BAD
		elif verdict.contains("réussite critique"):
			color = Color(0.5, 1.0, 0.7)
		elif verdict.contains("réussie"):
			color = GOOD
		elif verdict.contains("ratée"):
			color = WARN
	var panel := _panel(Color(0.06, 0.08, 0.12, 0.82), 8, 7)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(text, 14, color)
	panel.add_child(label)
	_feed.add_child(panel)
	_events.append({"panel": panel, "born": Time.get_ticks_msec()})
	while _events.size() > MAX_EVENTS:
		var old: Dictionary = _events.pop_front()
		old["panel"].queue_free()


func show_banner(title: String, subtitle: String) -> void:
	_banner_title.text = title
	_banner_sub.text = subtitle
	_banner_box.visible = true
	_banner_box.modulate.a = 1.0
	_banner_until = Time.get_ticks_msec() + 2600


func show_end() -> void:
	_end_score.text = "%d - %d" % [main.director.score[0], main.director.score[1]]
	_end_box.visible = true


# --- Mise à jour à chaque image --------------------------------------------------------------

func refresh() -> void:
	var director := main.director
	_score_labels[0].text = str(director.score[0])
	_score_labels[1].text = str(director.score[1])
	_clock_label.text = director.match_clock_text()
	_half_label.text = "1re mi-temps" if director.half == 1 else "2e mi-temps"
	_refresh_pause_panel()
	_refresh_card()
	_refresh_menu()
	_refresh_tooltip()
	_refresh_hint()
	_refresh_feed()
	_refresh_banner()


func _refresh_pause_panel() -> void:
	var cooldown_ready := main.pause_cooldown_left <= 0.0
	if main.paused:
		if main.pause_kind == "dead_ball":
			_pause_dot.color = BLUE
			_pause_label.text = "PAUSE OFFERTE"
			_pause_sub.text = "Balle arrêtée : planifie sans compter"
		else:
			_pause_dot.color = WARN
			_pause_label.text = "PAUSE TACTIQUE"
			_pause_sub.text = "Durée illimitée"
		_cooldown_bar.value = 0
	else:
		_pause_dot.color = GOOD
		_pause_label.text = "EN DIRECT"
		_cooldown_bar.value = 100.0 * (1.0 - main.pause_cooldown_left / Main.PAUSE_COOLDOWN)
		_pause_sub.text = "Pause disponible" if cooldown_ready else "Prochaine pause dans %d s" % int(ceil(main.pause_cooldown_left))
	_speed_label.text = "Vitesse du temps : x%d  (T)" % int(Main.TIME_SCALES[main.time_scale_index])


func _refresh_card() -> void:
	var player := main.selected
	if player == null:
		return
	_badge_label.text = str(player.number)
	_name_label.text = player.display_name
	var roles := {"DEF": "Défenseur", "ATT": "Attaquant", "GK": "Gardien"}
	var holder_text := "  ·  a le ballon" if main.ball.holder == player else ""
	_role_label.text = "%s%s" % [roles[player.role], holder_text]
	for key in ["vitesse", "technique", "passe", "frappe", "defense"]:
		var value := player.effective_stat(key)
		_stat_rows[key]["bar"].value = value
		_stat_rows[key]["value"].text = str(int(value))
	var stamina := player.stamina
	var bar: ProgressBar = _stat_rows["stamina"]["bar"]
	bar.value = stamina
	bar.add_theme_stylebox_override("fill", _style(GOOD if stamina > 50.0 else (WARN if stamina > 25.0 else BAD), 4, 0, Color(0, 0, 0, 0)))
	_stat_rows["stamina"]["value"].text = str(int(stamina))
	_orders_label.text = _orders_text(player)


func _orders_text(player: Player) -> String:
	if player.orders.is_empty():
		return "Aucun ordre : le joueur agit en autonomie."
	var lines: PackedStringArray = []
	var index := 1
	for order in player.orders:
		var text := ""
		match order["type"]:
			"move":
				text = "Courir (%s)" % String(Player.ALLURE_NAMES[order["allure"]]).to_lower()
			"pass":
				var target = order.get("target")
				text = "Passer à N°%d" % target.number if (target != null and is_instance_valid(target)) else "Passer vers un point"
				text += " (attend le ballon)" if main.ball.holder != player and index == 1 else ""
			"shoot":
				text = "Tirer : %s" % String(Rules.SHOT_HEIGHT_NAMES[order["height"]]).to_lower()
				text += " (attend le ballon)" if main.ball.holder != player and index == 1 else ""
			"tackle":
				var target = order["target"]
				text = "Tacler N°%d" % target.number if is_instance_valid(target) else "Tacler"
		lines.append("%d. %s" % [index, text])
		index += 1
	return "\n".join(lines)


func _refresh_menu() -> void:
	var player := main.selected
	var visible_menu := main.can_give_orders() and player != null
	_menu.visible = visible_menu
	if not visible_menu:
		return
	_menu_title.text = "N°%d  %s" % [player.number, player.display_name]
	for mode_value in _mode_buttons:
		(_mode_buttons[mode_value] as Button).set_pressed_no_signal(main.mode == mode_value)
	_move_box.visible = main.mode == Main.Mode.MOVE
	_pass_box.visible = main.mode == Main.Mode.PASS
	_shoot_box.visible = main.mode == Main.Mode.SHOOT
	_tackle_box.visible = main.mode == Main.Mode.TACKLE

	var is_holder := main.ball.holder == player
	for allure in 3:
		var speed_ms: float = Player.ALLURE_SPEED[allure] * player.speed_factor()
		var text := "%s  ·  %d km/h" % [Player.ALLURE_NAMES[allure], int(round(speed_ms * 3.6))]
		if is_holder:
			var touch := clampf(Rules.touch_chance(player, speed_ms), 1.0, 99.0)
			text += "  ·  ballon %d %%" % int(touch)
		_allure_buttons[allure].text = text
		_allure_buttons[allure].set_pressed_no_signal(main.current_allure == allure)
	_move_info.text = "Clic sur le terrain : ajoute un point de passage. Le pourcentage indique la sûreté de la conduite du ballon." if is_holder else "Clic sur le terrain : ajoute un point de passage."

	_aerial_buttons[0].set_pressed_no_signal(not main.opt_aerial)
	_aerial_buttons[1].set_pressed_no_signal(main.opt_aerial)
	for level in 3:
		_height_buttons[level].set_pressed_no_signal(main.opt_height == level)
	_pass_power_label.text = "Force de la passe : %d %%" % int(round(main.opt_pass_power * 100.0))
	_pass_power_slider.set_value_no_signal(main.opt_pass_power * 100.0)
	_shot_power_label.text = "Puissance de la frappe : %d %%" % int(round(main.opt_shot_power * 100.0))
	_shot_power_slider.set_value_no_signal(main.opt_shot_power * 100.0)
	var max_curve := int(round(Rules.max_curve(player) * 100.0))
	var curve_text := "Effet (molette) : aucun  ·  max %d %%" % max_curve
	if main.opt_curve != 0:
		var side := "à droite" if main.opt_curve > 0 else "à gauche"
		curve_text = "Effet (molette) : %s %d %%  ·  max %d %%" % [side, int(round(absf(main.effective_curve()) * 100.0)), max_curve]
	for label in _curve_labels:
		label.text = curve_text

	_menu.reset_size()
	_menu.position = Vector2(14.0, 128.0)


func _refresh_tooltip() -> void:
	var preview := main.compute_preview()
	var mouse := get_viewport().get_mouse_position()
	if preview.is_empty() or (_menu.visible and _menu.get_global_rect().has_point(mouse)):
		_tooltip.visible = false
		return
	var chance: float = preview["chance"]
	_tip_title.text = preview["title"]
	_tip_chance.text = "%d %%" % int(chance)
	_tip_chance.add_theme_color_override("font_color", GOOD if chance >= 65.0 else (WARN if chance >= 40.0 else BAD))
	_tip_detail.text = "Critique %d %%   ·   Échec critique %d %%" % [int(preview["crit_success"]), int(preview["crit_fail"])]
	_tip_warning.text = preview["warning"]
	_tip_warning.visible = preview["warning"] != ""
	_tooltip.visible = true
	_tooltip.reset_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var size := _tooltip.get_combined_minimum_size()
	_tooltip.position = Vector2(minf(mouse.x + 22.0, viewport_size.x - size.x - 10.0), minf(mouse.y + 22.0, viewport_size.y - size.y - 10.0))


func _refresh_hint() -> void:
	var text := ""
	if main.director.phase != MatchDirector.Phase.LIVE:
		text = ""
	elif main.can_give_orders():
		match main.mode:
			Main.Mode.MOVE:
				text = "Clique sur un joueur bleu pour le choisir, ou sur le terrain pour tracer sa course.  Espace : reprendre"
			Main.Mode.PASS:
				text = "Passe : clique sur un coéquipier (passe dans les pieds) ou sur le terrain (passe en profondeur)"
			Main.Mode.SHOOT:
				text = "Tir : clique dans le but adverse pour choisir l'endroit visé"
			Main.Mode.TACKLE:
				text = "Tacle : clique sur l'adversaire qui a le ballon"
	elif main.pause_cooldown_left > 0.0:
		text = "Match en cours  ·  prochaine pause dans %d s" % int(ceil(main.pause_cooldown_left))
	else:
		text = "Match en cours  ·  Espace : pause tactique"
	_hint_label.get_parent().visible = text != ""
	_hint_label.text = text


func _refresh_feed() -> void:
	var now := Time.get_ticks_msec()
	for entry in _events.duplicate():
		var age := float(now - int(entry["born"])) / 1000.0
		var panel: Control = entry["panel"]
		panel.modulate.a = clampf((EVENT_LIFETIME - age) / 2.0, 0.0, 1.0)
		if age > EVENT_LIFETIME:
			panel.queue_free()
			_events.erase(entry)


func _refresh_banner() -> void:
	if not _banner_box.visible:
		return
	var remaining := float(_banner_until - Time.get_ticks_msec()) / 1000.0
	if remaining <= 0.0:
		_banner_box.visible = false
	else:
		_banner_box.modulate.a = clampf(remaining / 0.6, 0.0, 1.0)
