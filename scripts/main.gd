extends Control

# -----------------------------------------------------------------------------
# 1. Σταθερές και βασικά δεδομένα
# -----------------------------------------------------------------------------
#
# Σ.Τε.Θ. Ναρκαλιευτής
# Εκπαιδευτικό Minesweeper σε Godot 4.7.
#
# Το αρχείο είναι οργανωμένο ώστε να διαβάζεται σε μάθημα:
# 1. Σταθερές και δεδομένα παιχνιδιού
# 2. Φόρτωση assets και μεταφράσεων
# 3. Δημιουργία UI
# 4. Λογική Minesweeper
# 5. TOP10 και βοηθητικές συναρτήσεις

const SCORE_FILE := "user://scores.json"
const MAX_SCORES_PER_DIFFICULTY := 10
const MAX_PLAYER_NAME_LENGTH := 10
const MAX_SCORE_SECONDS := 999999

const LANGUAGES := ["el", "en"]
const LANGUAGE_FILES := {
	"el": "res://locales/el.json",
	"en": "res://locales/en.json"
}

# Κωδικοί Font Awesome. Οι γραμματοσειρές βρίσκονται στον φάκελο staff/webfonts.
# Αν αλλάξει η γραμματοσειρά, αλλάζουμε μόνο αυτά τα codepoints.
const ICON_FLAG := 0xf024
const ICON_BOMB := 0xf1e2

# Κεντρική παλέτα χρωμάτων. Όταν αλλάζει η οπτική ταυτότητα,
# προτιμούμε να αλλάζουμε αυτά τα χρώματα αντί να ψάχνουμε όλο το UI.
const COLORS := {
	"ink": Color("#f4f7e8"),
	"muted": Color("#a9bfae"),
	"dark": Color("#06120f"),
	"panel": Color("#0b211c"),
	"panel_light": Color("#12392f"),
	"green": Color("#12a86f"),
	"green_soft": Color("#1fd38a"),
	"teal": Color("#28d5c4"),
	"yellow": Color("#ffcc33"),
	"red": Color("#ff5b57"),
	"blue": Color("#67a9ff"),
	"purple": Color("#c689ff")
}

# Τα επίπεδα δυσκολίας κρατούνται ως δεδομένα. Έτσι η λογική του παιχνιδιού
# δεν χρειάζεται να ξέρει "με το χέρι" πόσες γραμμές ή νάρκες έχει κάθε επιλογή.
const DIFFICULTIES := [
	{"key": "small", "label": "difficulty.small", "rows": 8, "cols": 8, "mines": 10},
	{"key": "classic", "label": "difficulty.classic", "rows": 10, "cols": 10, "mines": 15},
	{"key": "retro", "label": "difficulty.retro", "rows": 14, "cols": 14, "mines": 32}
]

# -----------------------------------------------------------------------------
# 2. Κατάσταση παιχνιδιού και αναφορές στο UI
# -----------------------------------------------------------------------------

var rng := RandomNumberGenerator.new()

var rows := 10
var cols := 10
var mine_count := 15
var flags_left := 15
var opened_cells := 0
var elapsed_seconds := 0.0
var first_click := true
var game_finished := false
var timer_runs := false

var current_language := "el"
var texts: Dictionary = {}
var board: Array = []
var cell_buttons: Array = []
var scores: Array = []
var page_sections: Array[Control] = []

var icon_font: Font
var logo_texture: Texture2D

var main_scroll: ScrollContainer
var page_layout: VBoxContainer
var top_spacer: Control
var bottom_spacer: Control
var grid: GridContainer
var status_panel: PanelContainer
var status_label: Label
var mines_label: Label
var time_label: Label
var body_flow: HFlowContainer
var board_center: CenterContainer
var side_column: VBoxContainer
var instruments_panel: PanelContainer
var instruments_grid: GridContainer
var score_panel: PanelContainer
var score_scroll: ScrollContainer
var best_label: Label
var score_list: VBoxContainer
var player_name_input: LineEdit
var difficulty_menu: OptionButton
var language_menu: OptionButton
var flag_mode: Button
var current_cell_size := 44.0
var current_cell_gap := 3.0
var vertical_center_pending := false


func _ready() -> void:
	rng.randomize()
	_load_assets()
	_load_language(current_language)
	_load_scores()
	_build_interface()
	_start_new_game()


func _process(delta: float) -> void:
	if timer_runs:
		elapsed_seconds += delta
		_update_hud()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and grid != null:
		_resize_cells()
		_schedule_vertical_centering()
		queue_redraw()


func _draw() -> void:
	# Φόντο σαν πλακέτα: δίνει τεχνολογική ταυτότητα χωρίς να κλέβει την προσοχή.
	draw_rect(Rect2(Vector2.ZERO, size), COLORS.dark)
	var step := 52
	for x in range(24, int(size.x), step):
		var x_index := floori(float(x) / float(step))
		var y := 24 + (x_index % 5) * 34
		draw_line(Vector2(x, 0), Vector2(x, min(size.y, y + 180)), _fade(COLORS.green, 0.16), 2.0)
		draw_circle(Vector2(x, min(size.y - 16, y + 180)), 4.0, _fade(COLORS.teal, 0.22))
	for y in range(36, int(size.y), step):
		var y_index := floori(float(y) / float(step))
		var start_x := 18 + (y_index % 4) * 38
		draw_line(Vector2(start_x, y), Vector2(min(size.x, start_x + 210), y), _fade(COLORS.teal, 0.12), 2.0)
		draw_circle(Vector2(min(size.x - 16, start_x + 210), y), 3.5, _fade(COLORS.green, 0.25))


func _load_assets() -> void:
	# Τα assets φορτώνονται με load(), ώστε το παιχνίδι να μη σταματήσει αν λείπει κάποιο αρχείο.
	icon_font = load("res://staff/webfonts/fa-solid-900.woff2")
	logo_texture = load("res://staff/images/logo.png")


func _load_language(language_code: String) -> void:
	# Κάθε γλώσσα είναι ξεχωριστό JSON αρχείο.
	# Αυτό είναι απλό για μάθημα: ο μαθητής βλέπει ότι το ίδιο κλειδί έχει άλλη τιμή ανά γλώσσα.
	current_language = language_code
	texts = {}

	var path := str(LANGUAGE_FILES.get(language_code, LANGUAGE_FILES["el"]))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		texts = parsed


func _tr(key: String) -> String:
	# Μικρή βοηθητική μετάφραση.
	# Αν λείπει κάποιο κλειδί, εμφανίζουμε το ίδιο το key για να φαίνεται αμέσως το λάθος.
	return str(texts.get(key, key))


func _build_interface() -> void:
	# Όλο το περιβάλλον δημιουργείται με κώδικα, χωρίς ξεχωριστά UI scenes.
	# Αυτό βοηθά εκπαιδευτικά: ο μαθητής βλέπει πώς χτίζονται Containers,
	# Panels, Buttons και Labels βήμα-βήμα.
	page_sections.clear()

	main_scroll = ScrollContainer.new()
	main_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(main_scroll)

	var root := MarginContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("margin_left", 20)
	root.add_theme_constant_override("margin_right", 20)
	root.add_theme_constant_override("margin_top", 0)
	root.add_theme_constant_override("margin_bottom", 0)
	main_scroll.add_child(root)

	var vertical_frame := VBoxContainer.new()
	vertical_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vertical_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(vertical_frame)

	top_spacer = Control.new()
	vertical_frame.add_child(top_spacer)

	page_layout = VBoxContainer.new()
	page_layout.add_theme_constant_override("separation", 14)
	vertical_frame.add_child(page_layout)

	bottom_spacer = Control.new()
	vertical_frame.add_child(bottom_spacer)

	_build_header(page_layout)
	_build_status(page_layout)
	_build_game_area(page_layout)


func _rebuild_interface_after_language_change() -> void:
	var previous_name := ""
	var previous_difficulty := 1
	if player_name_input != null:
		previous_name = player_name_input.text
	if difficulty_menu != null:
		previous_difficulty = difficulty_menu.selected

	for child in get_children():
		child.queue_free()

	_build_interface()
	difficulty_menu.selected = previous_difficulty
	player_name_input.text = previous_name
	_start_new_game()
	queue_redraw()


func _build_header(layout: VBoxContainer) -> void:
	var header_center := CenterContainer.new()
	header_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(header_center)

	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _box(COLORS.panel, COLORS.green, 2, 8))
	header_center.add_child(header)
	page_sections.append(header)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	header.add_child(header_row)

	var logo_box := CenterContainer.new()
	logo_box.custom_minimum_size = Vector2(76, 58)
	header_row.add_child(logo_box)

	var logo := TextureRect.new()
	logo.texture = logo_texture
	logo.custom_minimum_size = Vector2(72, 50)
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_box.add_child(logo)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title_box)

	var title := Label.new()
	title.text = _tr("game.title")
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLORS.ink)
	title_box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = _tr("game.description")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 15)
	subtitle.add_theme_color_override("font_color", COLORS.muted)
	title_box.add_child(subtitle)


func _build_status(layout: VBoxContainer) -> void:
	var toolbar_center := CenterContainer.new()
	toolbar_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(toolbar_center)

	var toolbar := PanelContainer.new()
	toolbar.add_theme_stylebox_override("panel", _box(Color("#071a16"), COLORS.green, 1, 8))
	toolbar_center.add_child(toolbar)
	page_sections.append(toolbar)

	var main_controls := HFlowContainer.new()
	main_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_controls.alignment = FlowContainer.ALIGNMENT_CENTER
	main_controls.add_theme_constant_override("h_separation", 12)
	main_controls.add_theme_constant_override("v_separation", 8)
	toolbar.add_child(main_controls)

	language_menu = OptionButton.new()
	for language_code in LANGUAGES:
		language_menu.add_item(_tr("language.%s" % language_code))
	language_menu.selected = LANGUAGES.find(current_language)
	language_menu.item_selected.connect(_on_language_changed)
	language_menu.custom_minimum_size = Vector2(120, 42)
	_style_select(language_menu)
	main_controls.add_child(language_menu)

	difficulty_menu = OptionButton.new()
	for difficulty in DIFFICULTIES:
		difficulty_menu.add_item(_tr(difficulty["label"]))
	difficulty_menu.selected = 1
	difficulty_menu.item_selected.connect(_on_difficulty_changed)
	difficulty_menu.custom_minimum_size = Vector2(160, 42)
	_style_select(difficulty_menu)
	main_controls.add_child(difficulty_menu)

	player_name_input = LineEdit.new()
	player_name_input.text = _tr("input.player.default")
	player_name_input.placeholder_text = _tr("input.player.placeholder")
	player_name_input.max_length = MAX_PLAYER_NAME_LENGTH
	player_name_input.custom_minimum_size = Vector2(138, 42)
	_style_line_edit(player_name_input)
	main_controls.add_child(player_name_input)

	var restart_button := Button.new()
	restart_button.text = _tr("button.new_game")
	restart_button.tooltip_text = _tr("button.new_game.tooltip")
	restart_button.custom_minimum_size = Vector2(142, 42)
	restart_button.pressed.connect(_start_new_game)
	_style_primary_button(restart_button)
	main_controls.add_child(restart_button)

	var status_center := CenterContainer.new()
	status_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(status_center)

	status_panel = PanelContainer.new()
	status_panel.add_theme_stylebox_override("panel", _box(Color("#101628"), COLORS.yellow, 1, 7))
	status_center.add_child(status_panel)
	page_sections.append(status_panel)

	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 8)
	status_panel.add_child(status_box)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 21)
	status_label.add_theme_color_override("font_color", COLORS.yellow)
	status_box.add_child(status_label)

	var lesson := Label.new()
	lesson.text = _tr("lesson.controls")
	lesson.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lesson.add_theme_font_size_override("font_size", 14)
	lesson.add_theme_color_override("font_color", COLORS.muted)
	status_box.add_child(lesson)
	_update_status_panel_width()


func _build_game_area(layout: VBoxContainer) -> void:
	body_flow = HFlowContainer.new()
	body_flow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	body_flow.add_theme_constant_override("h_separation", 14)
	body_flow.add_theme_constant_override("v_separation", 14)
	layout.add_child(body_flow)

	board_center = CenterContainer.new()
	board_center.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board_center.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body_flow.add_child(board_center)

	var board_panel := PanelContainer.new()
	board_panel.add_theme_stylebox_override("panel", _box(Color("#071a16"), COLORS.teal, 2, 8))
	board_center.add_child(board_panel)

	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	board_panel.add_child(grid)

	side_column = VBoxContainer.new()
	side_column.custom_minimum_size = Vector2(270, 0)
	side_column.add_theme_constant_override("separation", 14)
	body_flow.add_child(side_column)

	instruments_panel = PanelContainer.new()
	instruments_panel.add_theme_stylebox_override("panel", _box(Color("#101628"), COLORS.yellow, 1, 8))
	side_column.add_child(instruments_panel)

	instruments_grid = GridContainer.new()
	instruments_grid.columns = 1
	instruments_grid.add_theme_constant_override("h_separation", 8)
	instruments_grid.add_theme_constant_override("v_separation", 8)
	instruments_panel.add_child(instruments_grid)

	flag_mode = Button.new()
	flag_mode.text = _tr("toggle.flag")
	flag_mode.tooltip_text = _tr("toggle.flag.tooltip")
	flag_mode.toggle_mode = true
	flag_mode.custom_minimum_size = Vector2(0, 42)
	_style_toggle_button(flag_mode)
	instruments_grid.add_child(flag_mode)

	mines_label = _hud_label()
	mines_label.custom_minimum_size = Vector2(0, 42)
	instruments_grid.add_child(mines_label)

	time_label = _hud_label()
	time_label.custom_minimum_size = Vector2(0, 42)
	instruments_grid.add_child(time_label)

	score_panel = PanelContainer.new()
	score_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	score_panel.add_theme_stylebox_override("panel", _box(COLORS.panel, COLORS.green, 1, 8))
	side_column.add_child(score_panel)

	var score_box := VBoxContainer.new()
	score_box.add_theme_constant_override("separation", 8)
	score_panel.add_child(score_box)

	var score_title := Label.new()
	score_title.text = _tr("score.title")
	score_title.add_theme_font_size_override("font_size", 24)
	score_title.add_theme_color_override("font_color", COLORS.yellow)
	score_box.add_child(score_title)

	best_label = Label.new()
	best_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	best_label.add_theme_font_size_override("font_size", 14)
	best_label.add_theme_color_override("font_color", COLORS.muted)
	score_box.add_child(best_label)

	score_scroll = ScrollContainer.new()
	score_scroll.custom_minimum_size = Vector2(0, 170)
	score_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	score_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	score_box.add_child(score_scroll)

	score_list = VBoxContainer.new()
	score_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_list.add_theme_constant_override("separation", 4)
	score_scroll.add_child(score_list)


func _start_new_game() -> void:
	# Κάθε νέα παρτίδα αρχίζει από καθαρή κατάσταση:
	# μηδενίζουμε χρόνο/κελιά, διαβάζουμε τη δυσκολία και ξαναχτίζουμε το ταμπλό.
	var difficulty: Dictionary = DIFFICULTIES[difficulty_menu.selected]
	rows = difficulty["rows"]
	cols = difficulty["cols"]
	mine_count = difficulty["mines"]
	flags_left = mine_count
	opened_cells = 0
	elapsed_seconds = 0.0
	first_click = true
	game_finished = false
	timer_runs = false
	flag_mode.button_pressed = false

	_create_empty_board()
	_create_buttons()
	_update_hud()
	_update_scoreboard()
	status_label.text = _tr("status.first")
	status_label.add_theme_color_override("font_color", COLORS.yellow)
	_schedule_vertical_centering()


func _create_empty_board() -> void:
	# Το board είναι δισδιάστατος πίνακας. Κάθε θέση κρατά την κατάσταση ενός κελιού.
	board.clear()
	for row in range(rows):
		var board_row := []
		for col in range(cols):
			board_row.append({
				"mine": false,
				"open": false,
				"flag": false,
				"near": 0
			})
		board.append(board_row)


func _create_buttons() -> void:
	# Αφαιρούμε άμεσα τα παλιά κουμπιά από το GridContainer.
	# Το queue_free() μόνο του θα τα διέγραφε στο τέλος του frame, αλλά μέχρι τότε
	# θα συνέχιζαν να μετράνε στο layout και θα επηρέαζαν το κεντράρισμα.
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()

	cell_buttons.clear()
	grid.columns = cols

	for row in range(rows):
		var button_row := []
		for col in range(cols):
			var button := Button.new()
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.gui_input.connect(_on_cell_input.bind(row, col))
			button.add_theme_font_size_override("font_size", 21)
			button.add_theme_constant_override("outline_size", 2)
			_style_cell(button, "closed")
			grid.add_child(button)
			button_row.append(button)
		cell_buttons.append(button_row)
	_resize_cells()
	_schedule_vertical_centering()


func _place_mines(safe_row: int, safe_col: int) -> void:
	# Δεν τοποθετούμε νάρκες στην αρχή.
	# Περιμένουμε το πρώτο κλικ, ώστε η πρώτη κίνηση να είναι δίκαιη.
	var protected_cells := _neighbors(safe_row, safe_col)
	protected_cells.append(Vector2i(safe_row, safe_col))

	var placed := 0
	while placed < mine_count:
		var row := rng.randi_range(0, rows - 1)
		var col := rng.randi_range(0, cols - 1)
		if protected_cells.has(Vector2i(row, col)):
			continue
		if board[row][col]["mine"]:
			continue
		board[row][col]["mine"] = true
		placed += 1

	_calculate_numbers()


func _calculate_numbers() -> void:
	# Για κάθε μη-νάρκη μετράμε πόσες νάρκες υπάρχουν στα 8 γειτονικά κελιά.
	for row in range(rows):
		for col in range(cols):
			if board[row][col]["mine"]:
				continue
			var total := 0
			for point in _neighbors(row, col):
				if board[point.x][point.y]["mine"]:
					total += 1
			board[row][col]["near"] = total


func _neighbors(row: int, col: int) -> Array:
	# Επιστρέφει τα έγκυρα γειτονικά κελιά γύρω από μία θέση.
	var result := []
	for row_step in range(-1, 2):
		for col_step in range(-1, 2):
			if row_step == 0 and col_step == 0:
				continue
			var next_row := row + row_step
			var next_col := col + col_step
			if next_row >= 0 and next_row < rows and next_col >= 0 and next_col < cols:
				result.append(Vector2i(next_row, next_col))
	return result


func _on_cell_input(event: InputEvent, row: int, col: int) -> void:
	if game_finished:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_toggle_flag(row, col)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if flag_mode.button_pressed:
				_toggle_flag(row, col)
			else:
				_open_cell(row, col)
			get_viewport().set_input_as_handled()

	if event is InputEventScreenTouch and event.pressed:
		if flag_mode.button_pressed:
			_toggle_flag(row, col)
		else:
			_open_cell(row, col)
		get_viewport().set_input_as_handled()


func _toggle_flag(row: int, col: int) -> void:
	var cell: Dictionary = board[row][col]
	if cell["open"]:
		return

	if cell["flag"]:
		cell["flag"] = false
		flags_left += 1
	else:
		if flags_left <= 0:
			status_label.text = _tr("status.no_flags")
			return
		cell["flag"] = true
		flags_left -= 1

	_update_button(row, col)
	_update_hud()


func _open_cell(row: int, col: int) -> void:
	var cell: Dictionary = board[row][col]
	if cell["open"] or cell["flag"]:
		return

	if first_click:
		_place_mines(row, col)
		first_click = false
		timer_runs = true
		status_label.text = _tr("status.play")
		status_label.add_theme_color_override("font_color", COLORS.yellow)

	if cell["mine"]:
		_finish_with_loss(row, col)
		return

	# Flood fill με στοίβα:
	# Αν ένα κελί έχει 0 γειτονικές νάρκες, ανοίγουμε και τα γειτονικά του.
	var stack := [Vector2i(row, col)]
	while not stack.is_empty():
		var point: Vector2i = stack.pop_back()
		var current: Dictionary = board[point.x][point.y]
		if current["open"] or current["flag"]:
			continue

		current["open"] = true
		opened_cells += 1
		_update_button(point.x, point.y)

		if current["near"] == 0:
			for next in _neighbors(point.x, point.y):
				var next_cell: Dictionary = board[next.x][next.y]
				if not next_cell["open"] and not next_cell["mine"]:
					stack.append(next)

	_check_win()


func _check_win() -> void:
	var safe_cells := rows * cols - mine_count
	if opened_cells < safe_cells:
		return

	game_finished = true
	timer_runs = false
	status_label.text = _tr("status.win")
	status_label.add_theme_color_override("font_color", COLORS.yellow)

	for row in range(rows):
		for col in range(cols):
			if board[row][col]["mine"]:
				board[row][col]["flag"] = true
			_update_button(row, col)

	_save_score_after_win()


func _finish_with_loss(hit_row: int, hit_col: int) -> void:
	game_finished = true
	timer_runs = false
	status_label.text = _tr("status.loss") % [hit_row + 1, hit_col + 1]
	status_label.add_theme_color_override("font_color", COLORS.red)

	for row in range(rows):
		for col in range(cols):
			if board[row][col]["mine"]:
				board[row][col]["open"] = true
			_update_button(row, col)


func _update_button(row: int, col: int) -> void:
	var button: Button = cell_buttons[row][col]
	var cell: Dictionary = board[row][col]

	button.disabled = cell["open"] or game_finished
	button.text = ""

	if cell["open"]:
		if cell["mine"]:
			button.text = _icon_or_text(ICON_BOMB, "*")
			_style_cell(button, "mine")
		elif cell["near"] > 0:
			button.text = str(cell["near"])
			_style_cell(button, "open")
			button.add_theme_color_override("font_color", _number_color(cell["near"]))
			button.add_theme_color_override("font_disabled_color", _number_color(cell["near"]))
		else:
			_style_cell(button, "open")
	elif cell["flag"]:
		button.text = _icon_or_text(ICON_FLAG, "!")
		_style_cell(button, "flag")
	else:
		_style_cell(button, "closed")


func _update_hud() -> void:
	mines_label.text = _tr("hud.mines") % flags_left
	time_label.text = _tr("hud.time") % int(elapsed_seconds)


func _resize_cells() -> void:
	# Responsive υπολογισμός μεγέθους κελιού.
	# Δεν κλιμακώνουμε απλώς όλο το παράθυρο: υπολογίζουμε διαθέσιμο χώρο,
	# κενά ανάμεσα στα κελιά, περιθώρια και τη δεξιά στήλη πληροφοριών.
	current_cell_gap = 3.0
	if size.x < 420.0:
		current_cell_gap = 2.0
	if size.x < 340.0:
		current_cell_gap = 1.0

	grid.add_theme_constant_override("h_separation", int(current_cell_gap))
	grid.add_theme_constant_override("v_separation", int(current_cell_gap))

	var mobile_layout := _use_mobile_layout()
	var outer_margins := 40.0
	if mobile_layout:
		outer_margins = 24.0
	var board_padding := 20.0
	var side_width := 270.0
	var flow_gap := 14.0
	var board_gaps: float = max(0, cols - 1) * current_cell_gap
	var available_width: float = max(220.0, size.x - outer_margins - side_width - flow_gap)
	if mobile_layout or size.x < 760.0:
		available_width = max(220.0, size.x - outer_margins)

	var available_height: float = max(260.0, size.y - 250.0)
	var cell_width: float = (available_width - board_padding - board_gaps) / cols
	var max_cell_size := 44.0
	if mobile_layout:
		if cols <= 8:
			max_cell_size = 64.0
		elif cols <= 10:
			max_cell_size = 58.0
		else:
			max_cell_size = 48.0
	var cell_size: float = floor(min(max_cell_size, min(cell_width, available_height / rows)))
	cell_size = max(18.0, cell_size)
	current_cell_size = cell_size

	for row in cell_buttons:
		for button in row:
			button.custom_minimum_size = Vector2(cell_size, cell_size)
	_apply_responsive_layout(mobile_layout)
	_update_status_panel_width()
	_update_page_section_widths()
	_update_side_column_height()


func _load_scores() -> void:
	# Τα scores αποθηκεύονται τοπικά.
	# Στο desktop είναι αρχείο στο user://, ενώ στο web κρατιούνται στον χώρο δεδομένων του browser.
	if not FileAccess.file_exists(SCORE_FILE):
		scores = []
		return

	var file := FileAccess.open(SCORE_FILE, FileAccess.READ)
	if file == null:
		scores = []
		return

	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Array:
		scores = _sanitize_loaded_scores(parsed)
	else:
		scores = []

	_trim_scores()


func _save_scores() -> void:
	var file := FileAccess.open(SCORE_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(scores, "\t"))


func _save_score_after_win() -> void:
	var player_name := player_name_input.text.strip_edges()
	if player_name.is_empty():
		player_name = _tr("score.anonymous")

	var entry := {
		"name": player_name.substr(0, MAX_PLAYER_NAME_LENGTH),
		"difficulty_key": _current_difficulty_key(),
		"seconds": int(elapsed_seconds),
		"date": Time.get_date_string_from_system()
	}

	scores.append(entry)
	scores.sort_custom(_sort_score_entries)
	_trim_scores()
	_save_scores()
	_update_scoreboard()


func _sanitize_loaded_scores(raw_scores: Array) -> Array:
	# Δεν θεωρούμε ότι το τοπικό αρχείο είναι πάντα σωστό.
	# Αν ο χρήστης το πειράξει ή αν χαλάσει η αποθήκευση, κρατάμε μόνο εγγραφές
	# που έχουν γνωστή δυσκολία, λογικό χρόνο και καθαρό όνομα.
	var clean_scores := []
	for raw_entry in raw_scores:
		if not raw_entry is Dictionary:
			continue

		var entry: Dictionary = raw_entry
		var difficulty_key := str(entry.get("difficulty_key", entry.get("difficulty", "")))
		if not _is_known_difficulty_key(difficulty_key):
			continue

		var seconds_value = entry.get("seconds", -1)
		if not (seconds_value is int or seconds_value is float):
			continue

		var seconds := int(seconds_value)
		if seconds < 0 or seconds > MAX_SCORE_SECONDS:
			continue

		var player_name := str(entry.get("name", _tr("score.player_fallback"))).strip_edges()
		if player_name.is_empty():
			player_name = _tr("score.anonymous")

		clean_scores.append({
			"name": player_name.substr(0, MAX_PLAYER_NAME_LENGTH),
			"difficulty_key": difficulty_key,
			"seconds": seconds,
			"date": str(entry.get("date", ""))
		})

	clean_scores.sort_custom(_sort_score_entries)
	return clean_scores


func _is_known_difficulty_key(difficulty_key: String) -> bool:
	for difficulty in DIFFICULTIES:
		if str(difficulty["key"]) == difficulty_key:
			return true
	return false


func _sort_score_entries(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("difficulty_key", a.get("difficulty", ""))) == str(b.get("difficulty_key", b.get("difficulty", ""))):
		return int(a.get("seconds", 999999)) < int(b.get("seconds", 999999))
	return str(a.get("difficulty_key", a.get("difficulty", ""))) < str(b.get("difficulty_key", b.get("difficulty", "")))


func _trim_scores() -> void:
	var kept := []
	var counts := {}
	for entry in scores:
		var key := str(entry.get("difficulty_key", entry.get("difficulty", "")))
		var count := int(counts.get(key, 0))
		if count < MAX_SCORES_PER_DIFFICULTY:
			kept.append(entry)
			counts[key] = count + 1
	scores = kept


func _scores_for_current_difficulty() -> Array:
	var result := []
	var difficulty_key := _current_difficulty_key()
	for entry in scores:
		if str(entry.get("difficulty_key", "")) == difficulty_key:
			result.append(entry)
	return result


func _update_scoreboard() -> void:
	if score_list == null:
		return

	for child in score_list.get_children():
		child.queue_free()

	var current_scores := _scores_for_current_difficulty()
	best_label.text = _tr("score.best_for") % _current_difficulty_name()

	if current_scores.is_empty():
		var empty := _score_label(_tr("score.empty"), COLORS.muted)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		score_list.add_child(empty)
		return

	for index in range(min(MAX_SCORES_PER_DIFFICULTY, current_scores.size())):
		var entry: Dictionary = current_scores[index]
		var player_name := str(entry.get("name", _tr("score.player_fallback")))
		var line := "%02d. %s  %03ds" % [index + 1, player_name, int(entry.get("seconds", 0))]
		score_list.add_child(_score_label(line, COLORS.ink if index > 2 else COLORS.yellow))


func _current_difficulty_key() -> String:
	return str(DIFFICULTIES[difficulty_menu.selected]["key"])


func _current_difficulty_name() -> String:
	return _tr(str(DIFFICULTIES[difficulty_menu.selected]["label"]))


func _on_difficulty_changed(_index: int) -> void:
	_start_new_game()


func _on_language_changed(index: int) -> void:
	var language_code: String = LANGUAGES[index]
	if language_code == current_language:
		return
	_load_language(language_code)
	_rebuild_interface_after_language_change()


func _hud_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", COLORS.yellow)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_stylebox_override("normal", _box(Color("#071a2e"), _fade(COLORS.yellow, 0.7), 1, 6))
	return label


func _apply_responsive_layout(mobile_layout: bool) -> void:
	if body_flow == null or board_center == null or side_column == null or score_panel == null:
		return

	if mobile_layout:
		# Σε κινητό βάζουμε πρώτα τα εργαλεία, μετά το πλέγμα και στο τέλος το TOP10.
		# Έτσι ο παίκτης δεν χρειάζεται να κάνει scroll για να αλλάξει τη λειτουργία σημαίας.
		if score_panel.get_parent() != body_flow:
			score_panel.reparent(body_flow)
		body_flow.move_child(side_column, 0)
		body_flow.move_child(board_center, 1)
		body_flow.move_child(score_panel, 2)
		instruments_grid.columns = 3
		flag_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mines_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		score_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		return

	# Σε υπολογιστή κρατάμε την κλασική διάταξη: ταμπλό αριστερά, εργαλεία και TOP10 δεξιά.
	if score_panel.get_parent() != side_column:
		score_panel.reparent(side_column)
	body_flow.move_child(board_center, 0)
	body_flow.move_child(side_column, 1)
	side_column.move_child(score_panel, 1)
	instruments_grid.columns = 1
	flag_mode.size_flags_horizontal = Control.SIZE_FILL
	mines_label.size_flags_horizontal = Control.SIZE_FILL
	time_label.size_flags_horizontal = Control.SIZE_FILL
	score_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _update_status_panel_width() -> void:
	if status_panel == null:
		return

	status_panel.custom_minimum_size = Vector2(_content_width(), 0)


func _update_page_section_widths() -> void:
	var target_width := _content_width()
	for section in page_sections:
		if section != null:
			section.custom_minimum_size = Vector2(target_width, 0)


func _content_width() -> float:
	var board_width: float = cols * current_cell_size + max(0, cols - 1) * current_cell_gap + 20.0
	var score_width: float = 270.0
	var outer_margins := 40.0
	if _use_mobile_layout():
		outer_margins = 24.0
		var mobile_width: float = max(220.0, size.x - outer_margins)
		return min(mobile_width, max(board_width, 320.0))

	var content_width: float = board_width + 14.0 + score_width

	# Σε στενές οθόνες το TOP10 πέφτει κάτω από το ταμπλό, άρα το status ακολουθεί το πλάτος του ταμπλό.
	if size.x > 0.0 and content_width > size.x - outer_margins:
		content_width = max(board_width, score_width)

	return content_width


func _schedule_vertical_centering() -> void:
	# Τα Containers του Godot ενημερώνουν τα minimum sizes στο τέλος του frame.
	# Γι' αυτό δεν κεντράρουμε αμέσως μετά την αλλαγή δυσκολίας, αλλά προγραμματίζουμε
	# έναν υπολογισμό λίγο αργότερα, όταν το νέο πλέγμα έχει σταθερό μέγεθος.
	if vertical_center_pending:
		return

	vertical_center_pending = true
	_apply_deferred_vertical_centering()


func _apply_deferred_vertical_centering() -> void:
	# Περιμένουμε δύο frames για να ολοκληρωθούν:
	# 1. η αφαίρεση/δημιουργία των κουμπιών του πλέγματος
	# 2. ο επανυπολογισμός των Containers που τα περιέχουν
	await get_tree().process_frame
	await get_tree().process_frame

	_update_status_panel_width()
	_update_page_section_widths()
	_update_side_column_height()
	_update_vertical_centering()

	if main_scroll != null:
		main_scroll.set_deferred("scroll_vertical", 0)

	vertical_center_pending = false


func _update_vertical_centering() -> void:
	if page_layout == null or top_spacer == null or bottom_spacer == null:
		return

	if _use_mobile_layout():
		top_spacer.custom_minimum_size = Vector2(0.0, 12.0)
		bottom_spacer.custom_minimum_size = Vector2(0.0, 12.0)
		return

	var content_height: float = page_layout.get_combined_minimum_size().y
	var extra_space: float = max(0.0, size.y - content_height)
	var spacer_height: float = floor(extra_space / 2.0)

	top_spacer.custom_minimum_size = Vector2(0.0, spacer_height)
	bottom_spacer.custom_minimum_size = Vector2(0.0, spacer_height)


func _use_mobile_layout() -> bool:
	# Σε πολλά κινητά το web export βλέπει physical/high-DPI pixels.
	# Έτσι ένα portrait κινητό μπορεί να φαίνεται στον κώδικα "φαρδύ",
	# ενώ ο χρήστης βλέπει μικροσκοπική desktop διάταξη. Με αυτόν τον έλεγχο
	# δίνουμε προτεραιότητα στην αναλογία portrait και όχι μόνο στο απόλυτο πλάτος.
	return size.x < 760.0 or (size.y > size.x * 1.25 and size.x < 1300.0)


func _update_side_column_height() -> void:
	if side_column == null or score_panel == null or score_scroll == null:
		return

	var board_height: float = rows * current_cell_size + max(0, rows - 1) * current_cell_gap + 20.0

	if _use_mobile_layout():
		var target_width: float = _content_width()
		var item_width: float = max(90.0, floor((target_width - 16.0) / 3.0))
		side_column.custom_minimum_size = Vector2(target_width, 0.0)
		instruments_panel.custom_minimum_size = Vector2(target_width, 0.0)
		flag_mode.custom_minimum_size = Vector2(item_width, 40.0)
		mines_label.custom_minimum_size = Vector2(item_width, 40.0)
		time_label.custom_minimum_size = Vector2(item_width, 40.0)
		score_panel.custom_minimum_size = Vector2(target_width, 130.0)
		score_scroll.custom_minimum_size = Vector2(0.0, 42.0)
		return

	side_column.custom_minimum_size = Vector2(270.0, board_height)

	if _current_difficulty_key() == "small":
		flag_mode.custom_minimum_size = Vector2(0.0, 34.0)
		mines_label.custom_minimum_size = Vector2(0.0, 34.0)
		time_label.custom_minimum_size = Vector2(0.0, 34.0)
		score_panel.custom_minimum_size = Vector2(270.0, 130.0)
		score_scroll.custom_minimum_size = Vector2(0.0, 36.0)
	else:
		flag_mode.custom_minimum_size = Vector2(0.0, 42.0)
		mines_label.custom_minimum_size = Vector2(0.0, 42.0)
		time_label.custom_minimum_size = Vector2(0.0, 42.0)
		score_panel.custom_minimum_size = Vector2(270.0, 0.0)
		score_scroll.custom_minimum_size = Vector2(0.0, 170.0)


func _score_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label


func _style_select(select: OptionButton) -> void:
	select.add_theme_stylebox_override("normal", _box(COLORS.panel, COLORS.green, 1, 6))
	select.add_theme_stylebox_override("hover", _box(Color("#184d3f"), COLORS.teal, 2, 6))
	select.add_theme_color_override("font_color", COLORS.ink)


func _style_line_edit(input: LineEdit) -> void:
	input.add_theme_stylebox_override("normal", _box(Color("#071a16"), COLORS.green, 1, 6))
	input.add_theme_stylebox_override("focus", _box(Color("#0e2f28"), COLORS.teal, 2, 6))
	input.add_theme_color_override("font_color", COLORS.ink)
	input.add_theme_color_override("font_placeholder_color", COLORS.muted)
	input.add_theme_color_override("caret_color", COLORS.yellow)


func _style_primary_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(COLORS.yellow, COLORS.ink, 1, 6))
	button.add_theme_stylebox_override("hover", _box(Color("#ffe06b"), COLORS.ink, 2, 6))
	button.add_theme_stylebox_override("pressed", _box(COLORS.green_soft, COLORS.ink, 1, 6))
	button.add_theme_color_override("font_color", COLORS.dark)
	button.add_theme_color_override("font_hover_color", COLORS.dark)
	button.add_theme_color_override("font_pressed_color", COLORS.dark)


func _style_toggle_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _box(Color("#071a2e"), COLORS.blue, 1, 6))
	button.add_theme_stylebox_override("hover", _box(Color("#10294a"), COLORS.teal, 2, 6))
	button.add_theme_stylebox_override("pressed", _box(COLORS.yellow, COLORS.ink, 2, 6))
	button.add_theme_color_override("font_color", COLORS.ink)
	button.add_theme_color_override("font_hover_color", COLORS.ink)
	button.add_theme_color_override("font_pressed_color", COLORS.dark)


func _style_cell(button: Button, state: String) -> void:
	var normal := _cell_box(COLORS.panel_light, COLORS.green)
	var hover := _cell_box(Color("#1b5c4c"), COLORS.teal)
	var pressed := _cell_box(COLORS.green, COLORS.ink)
	var disabled := normal
	var font_color := COLORS.ink

	button.remove_theme_font_override("font")
	button.clip_text = true

	if state == "open":
		normal = _cell_box(Color("#10241f"), Color("#285448"))
		disabled = normal
		font_color = COLORS.ink
	elif state == "flag":
		normal = _cell_box(Color("#423714"), COLORS.yellow)
		hover = _cell_box(Color("#5a4816"), COLORS.yellow)
		font_color = COLORS.yellow
		_apply_icon_font(button)
	elif state == "mine":
		normal = _cell_box(Color("#421513"), COLORS.red)
		disabled = normal
		font_color = COLORS.red
		_apply_icon_font(button)

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", font_color)
	button.add_theme_color_override("font_hover_color", font_color)
	button.add_theme_color_override("font_pressed_color", COLORS.dark)
	button.add_theme_color_override("font_disabled_color", font_color)


func _apply_icon_font(button: Button) -> void:
	if icon_font != null:
		button.add_theme_font_override("font", icon_font)
		button.add_theme_font_size_override("font_size", 18)


func _number_color(number: int) -> Color:
	match number:
		1:
			return COLORS.teal
		2:
			return COLORS.green_soft
		3:
			return COLORS.yellow
		4:
			return COLORS.blue
		5:
			return COLORS.purple
		_:
			return COLORS.red


func _icon_or_text(codepoint: int, fallback: String) -> String:
	if icon_font == null:
		return fallback
	return String.chr(codepoint)


func _box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _cell_box(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	return style


func _fade(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)
