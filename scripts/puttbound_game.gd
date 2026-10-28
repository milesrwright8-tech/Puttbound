extends Node3D
## Puttbound: Worlds in Motion
## A self-contained offline mini-golf runtime. Course geometry and props are generated
## from compact data so adding holes later only requires catalog entries.

const SAVE_PATH := "user://puttbound_save.json"
const MAX_STROKES := 12
const WORLD_COUNT := 5
const HOLES_PER_WORLD := 6

const WORLD_DEFS := [
	{"name": "Sunny Park", "tag": "Fresh fairways & clever banks", "sky": Color("#8fd7ff"), "ground": Color("#77c96b"), "fairway": Color("#b8ed8e"), "accent": Color("#f7b64a"), "wall": Color("#8d573b"), "hazard": Color("#52b9d9")},
	{"name": "Candy Kingdom", "tag": "Bounce into a sugar rush", "sky": Color("#ffb6d9"), "ground": Color("#f3a2c8"), "fairway": Color("#ffe3a4"), "accent": Color("#ff6d91"), "wall": Color("#b56ec6"), "hazard": Color("#8ce5ee")},
	{"name": "Neon Arcade", "tag": "Timing is everything", "sky": Color("#101b4e"), "ground": Color("#151d56"), "fairway": Color("#243b8f"), "accent": Color("#52f7e5"), "wall": Color("#f548a3"), "hazard": Color("#3c8cff")},
	{"name": "Pirate Cove", "tag": "Risk the shortcut", "sky": Color("#86cef1"), "ground": Color("#315c70"), "fairway": Color("#d7a75e"), "accent": Color("#ffcf63"), "wall": Color("#75462f"), "hazard": Color("#2c91ba")},
	{"name": "Space Station", "tag": "Low gravity. Big ideas.", "sky": Color("#090d22"), "ground": Color("#151a38"), "fairway": Color("#5961a8"), "accent": Color("#84e9ff"), "wall": Color("#b8c6e8"), "hazard": Color("#c54dff")}
]

const HOLE_TYPES := ["classic", "ramp", "moving", "bumper", "maze", "trick"]
const TYPE_LABELS := {"classic":"BANK SHOT", "ramp":"JUMP LINE", "moving":"TIMING GATE", "bumper":"BOUNCE RUN", "maze":"MAZE ROUTE", "trick":"TRICK SHOT"}

var holes: Array[Dictionary] = []
var current_hole := 0
var current_world := 0
var current_type := "classic"
var strokes := 0
var par := 3
var completed := false
var shot_active := false
var aiming := false
var shot_cooldown := 0.0
var elapsed := 0.0
var course_root: Node3D
var ball: RigidBody3D
var camera: Camera3D
var cup_area: Area3D
var hazard_areas: Array[Area3D] = []
var launcher_areas: Array[Area3D] = []
var teleporter_areas: Array[Area3D] = []
var moving_props: Array[Dictionary] = []
var last_safe_position := Vector3.ZERO
var aim_start := Vector2.ZERO
var aim_current := Vector2.ZERO
var aim_direction := Vector3(0, 0, 1)
var aim_power := 0.0
var aim_mesh_instance: MeshInstance3D
var aim_immediate := ImmediateMesh.new()
var save_data: Dictionary = {}
var screen_mode := "menu"
var play_mode := "campaign"
var player_count := 1
var active_player := 0
var player_names := ["PLAYER 1", "PLAYER 2", "PLAYER 3", "PLAYER 4"]
var player_colors := [Color("#ffdb56"), Color("#57d9ff"), Color("#ff72b5"), Color("#a98cff")]
var round_scores: Array = []

var ui_layer: CanvasLayer
var menu_panel: Control
var course_select_panel: Control
var settings_panel: Control
var credits_panel: Control
var game_panel: Control
var result_panel: Control
var multiplayer_panel: Control
var toast_label: Label
var hud_strokes: Label
var hud_par: Label
var hud_hole: Label
var hud_world: Label
var hud_turn: Label
var hud_hint: Label
var power_bar: ProgressBar
var power_text: Label
var result_title: Label
var result_body: Label
var aim_hint: Label
var shot_guide_enabled := true
var sound_volume := 0.8
var music_volume := 0.35
var camera_sensitivity := 1.0
var hit_audio: AudioStreamPlayer
var cup_audio: AudioStreamPlayer
var hazard_audio: AudioStreamPlayer

func _ready() -> void:
	_build_hole_catalog()
	_load_save()
	var display_name := DisplayServer.get_name().to_lower()
	if display_name != "headless" and not OS.get_cmdline_args().has("--headless"):
		_setup_audio()
	_build_world_shell()
	_build_ui()
	_show_menu()

func _build_hole_catalog() -> void:
	holes.clear()
	for world_index in range(WORLD_COUNT):
		for hole_index in range(HOLES_PER_WORLD):
			var kind: String = HOLE_TYPES[(hole_index + world_index * 2) % HOLE_TYPES.size()]
			var difficulty := world_index + hole_index / 3
			var hole_par := 2 + int((hole_index + world_index) % 3)
			if kind == "maze" or kind == "trick":
				hole_par += 1
			holes.append({
				"world": world_index,
				"number": hole_index + 1,
				"type": kind,
				"par": hole_par,
				"distance": 11.0 + float((hole_index * 2 + world_index) % 5),
				"difficulty": difficulty,
				"name": _hole_name(world_index, hole_index, kind)
			})

func _hole_name(world_index: int, hole_index: int, kind: String) -> String:
	var names := [
		["Meadow Gate", "Sundial Bend", "Picnic Bank", "Topiary Turn", "Pebble Bridge", "Park Finale"],
		["Lollipop Lane", "Marshmallow Mile", "Gumdrop Gauntlet", "Taffy Tunnels", "Jellybean Jump", "Sugar Rush"],
		["Pixel Plaza", "Laser Lane", "Pulse Platform", "Synth Spiral", "Bumper Byte", "Final Boss"],
		["Driftwood Dash", "Cannon Cove", "Barrel Breaker", "Kraken Bend", "Island Hop", "Captain's Cut"],
		["Orbital Dock", "Moonwalk", "Gravity Well", "Solar Swing", "Airlock Alley", "Zero-G Zenith"]
	]
	return names[world_index][hole_index]

func _build_world_shell() -> void:
	camera = Camera3D.new()
	camera.name = "FollowCamera"
	camera.current = true
	camera.fov = 52.0
	camera.position = Vector3(0, 13, 13)
	add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.name = "WorldLight"
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.name = "SoftFill"
	fill.position = Vector3(0, 7, 2)
	fill.omni_range = 28.0
	fill.light_energy = 0.45
	fill.light_color = Color("#b7e6ff")
	add_child(fill)
	course_root = Node3D.new()
	course_root.name = "Course"
	add_child(course_root)
	_build_aim_visual()

func _setup_audio() -> void:
	hit_audio = _make_audio_player("PuttHit", "res://assets/audio/putt_hit.wav")
	cup_audio = _make_audio_player("CupEntry", "res://assets/audio/cup_entry.wav")
	hazard_audio = _make_audio_player("HazardReset", "res://assets/audio/hazard_reset.wav")

func _make_audio_player(player_name: String, stream_path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = load(stream_path) as AudioStream
	player.volume_db = linear_to_db(maxf(0.001, sound_volume))
	add_child(player)
	return player

func _play_audio(player: AudioStreamPlayer) -> void:
	if is_instance_valid(player) and player.stream != null and sound_volume > 0.01:
		player.volume_db = linear_to_db(maxf(0.001, sound_volume))
		player.play()

func _build_aim_visual() -> void:
	aim_mesh_instance = MeshInstance3D.new()
	aim_mesh_instance.name = "AimGuide"
	aim_mesh_instance.mesh = aim_immediate
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ffe37a")
	mat.emission_enabled = true
	mat.emission = Color("#ffb62e")
	mat.emission_energy_multiplier = 1.5
	aim_mesh_instance.material_override = mat
	aim_mesh_instance.visible = false
	add_child(aim_mesh_instance)

func _build_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UI"
	add_child(ui_layer)
	menu_panel = _make_full_panel()
	ui_layer.add_child(menu_panel)
	_build_menu()
	course_select_panel = _make_full_panel()
	ui_layer.add_child(course_select_panel)
	_build_course_select()
	settings_panel = _make_full_panel()
	ui_layer.add_child(settings_panel)
	_build_settings()
	credits_panel = _make_full_panel()
	ui_layer.add_child(credits_panel)
	_build_credits()
	multiplayer_panel = _make_full_panel()
	ui_layer.add_child(multiplayer_panel)
	_build_multiplayer()
	game_panel = _make_full_panel()
	ui_layer.add_child(game_panel)
	_build_game_hud()
	result_panel = _make_full_panel()
	ui_layer.add_child(result_panel)
	_build_result()
	toast_label = _label("", 22, Color("#fff4c2"))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.anchor_left = 0.25
	toast_label.anchor_right = 0.75
	toast_label.anchor_top = 0.08
	toast_label.anchor_bottom = 0.14
	toast_label.visible = false
	ui_layer.add_child(toast_label)

func _make_full_panel() -> Control:
	var panel := Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	return panel

func _build_menu() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#081426")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(bg)
	var glow := ColorRect.new()
	glow.color = Color("#163665")
	glow.position = Vector2(0, 430)
	glow.size = Vector2(1280, 290)
	menu_panel.add_child(glow)
	var title := _label("PUTTBOUND", 72, Color("#f8d66d"))
	title.position = Vector2(72, 64)
	title.size = Vector2(600, 94)
	menu_panel.add_child(title)
	var subtitle := _label("WORLDS IN MOTION", 20, Color("#79e1ed"))
	subtitle.position = Vector2(78, 150)
	subtitle.size = Vector2(400, 34)
	menu_panel.add_child(subtitle)
	var tagline := _label("30 offline courses. One perfect line.", 26, Color("#d8e8ff"))
	tagline.position = Vector2(78, 208)
	tagline.size = Vector2(520, 45)
	menu_panel.add_child(tagline)
	var orb := _make_orb(Vector2(928, 155), 110.0, Color("#ffe480"))
	menu_panel.add_child(orb)
	var ball_mark := _make_orb(Vector2(958, 210), 28.0, Color("#ffffff"))
	menu_panel.add_child(ball_mark)
	var buttons := VBoxContainer.new()
	buttons.position = Vector2(760, 306)
	buttons.size = Vector2(390, 330)
	buttons.add_theme_constant_override("separation", 10)
	menu_panel.add_child(buttons)
	_add_button(buttons, "PLAY CAMPAIGN", _start_campaign, true)
	_add_button(buttons, "QUICK PLAY", _start_quick_play, false)
	_add_button(buttons, "COURSE SELECTION", _show_course_select, false)
	_add_button(buttons, "PRACTICE", _start_practice, false)
	_add_button(buttons, "LOCAL PASS & PLAY", _show_multiplayer, false)
	var lower := HBoxContainer.new()
	lower.position = Vector2(78, 585)
	lower.size = Vector2(500, 52)
	lower.add_theme_constant_override("separation", 12)
	menu_panel.add_child(lower)
	_add_button(lower, "SETTINGS", _show_settings, false, 150)
	_add_button(lower, "CREDITS", _show_credits, false, 150)
	var offline := _label("OFFLINE BY DESIGN  •  NO ACCOUNT  •  NO SERVER", 14, Color("#82a6c7"))
	offline.position = Vector2(78, 658)
	offline.size = Vector2(520, 28)
	menu_panel.add_child(offline)

func _build_course_select() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0b1730")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	course_select_panel.add_child(bg)
	var title := _label("COURSE SELECT", 46, Color("#f8d66d"))
	title.position = Vector2(64, 40)
	title.size = Vector2(500, 64)
	course_select_panel.add_child(title)
	var back := _button("BACK", _show_menu, 150)
	back.position = Vector2(1050, 42)
	course_select_panel.add_child(back)
	for world_index in range(WORLD_COUNT):
		var world: Dictionary = WORLD_DEFS[world_index]
		var card := Panel.new()
		card.position = Vector2(56 + (world_index % 3) * 398, 132 + (world_index / 3) * 240)
		card.size = Vector2(360, 202)
		var style := StyleBoxFlat.new()
		style.bg_color = world["ground"].darkened(0.45)
		style.border_color = world["accent"]
		style.set_border_width_all(2)
		style.corner_radius_top_left = 18
		style.corner_radius_top_right = 18
		style.corner_radius_bottom_left = 18
		style.corner_radius_bottom_right = 18
		card.add_theme_stylebox_override("panel", style)
		course_select_panel.add_child(card)
		var wlabel := _label(str(world_index + 1).pad_zeros(2) + "  " + world["name"], 24, world["accent"])
		wlabel.position = Vector2(18, 12)
		wlabel.size = Vector2(320, 34)
		card.add_child(wlabel)
		var wtag := _label(world["tag"], 13, Color("#d6e2f3"))
		wtag.position = Vector2(19, 48)
		wtag.size = Vector2(310, 24)
		card.add_child(wtag)
		var row := HBoxContainer.new()
		row.position = Vector2(16, 88)
		row.size = Vector2(328, 96)
		row.add_theme_constant_override("separation", 6)
		card.add_child(row)
		for hole_index in range(HOLES_PER_WORLD):
			var unlocked := _hole_unlocked(world_index * HOLES_PER_WORLD + hole_index)
			var b := _button(str(hole_index + 1), _select_hole.bind(world_index * HOLES_PER_WORLD + hole_index), unlocked, 48)
			b.tooltip_text = holes[world_index * HOLES_PER_WORLD + hole_index]["name"]
			row.add_child(b)

func _build_settings() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#10182e")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_panel.add_child(bg)
	var title := _label("SETTINGS", 48, Color("#f8d66d"))
	title.position = Vector2(70, 50)
	title.size = Vector2(440, 70)
	settings_panel.add_child(title)
	var back := _button("BACK", _show_menu, 150)
	back.position = Vector2(1050, 48)
	settings_panel.add_child(back)
	var card := Panel.new()
	card.position = Vector2(120, 155)
	card.size = Vector2(820, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#182846")
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	card.add_theme_stylebox_override("panel", style)
	settings_panel.add_child(card)
	_add_setting_slider(card, "SOUND VOLUME", 0, sound_volume, _set_sound_volume, 45)
	_add_setting_slider(card, "MUSIC VOLUME", 1, music_volume, _set_music_volume, 145)
	_add_setting_slider(card, "CAMERA SENSITIVITY", 2, camera_sensitivity / 2.0, _set_camera_sensitivity, 245)
	var guide := CheckButton.new()
	guide.text = "BEGINNER SHOT GUIDE"
	guide.button_pressed = shot_guide_enabled
	guide.position = Vector2(45, 335)
	guide.size = Vector2(360, 46)
	guide.add_theme_font_size_override("font_size", 18)
	guide.toggled.connect(func(value: bool): shot_guide_enabled = value; _save_game())
	card.add_child(guide)
	var note := _label("All settings are stored locally on this device.", 16, Color("#96b2d2"))
	note.position = Vector2(46, 378)
	note.size = Vector2(500, 30)
	card.add_child(note)

func _add_setting_slider(card: Control, title_text: String, _index: int, value: float, callback: Callable, y: float) -> void:
	var label := _label(title_text, 17, Color("#dbe9ff"))
	label.position = Vector2(45, y)
	label.size = Vector2(260, 34)
	card.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.position = Vector2(320, y + 3)
	slider.size = Vector2(365, 32)
	slider.value_changed.connect(callback)
	card.add_child(slider)

func _build_credits() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#081426")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	credits_panel.add_child(bg)
	var title := _label("CREDITS", 48, Color("#f8d66d"))
	title.position = Vector2(70, 54)
	title.size = Vector2(440, 70)
	credits_panel.add_child(title)
	var back := _button("BACK", _show_menu, 150)
	back.position = Vector2(1050, 48)
	credits_panel.add_child(back)
	var body := _label("PUTTBOUND: WORLDS IN MOTION\n\nAn original offline mini-golf adventure.\n\nDesigned for quick rounds, clever lines, and local pass-and-play.\n\nBuilt with Godot 4.7.2 and procedural low-poly course art.\nNo network connection. No account. Just one more shot.", 22, Color("#dbe9ff"))
	body.position = Vector2(120, 170)
	body.size = Vector2(760, 320)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits_panel.add_child(body)

func _build_multiplayer() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#0c1b32")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	multiplayer_panel.add_child(bg)
	var title := _label("LOCAL PASS & PLAY", 44, Color("#f8d66d"))
	title.position = Vector2(70, 48)
	title.size = Vector2(700, 62)
	multiplayer_panel.add_child(title)
	var back := _button("BACK", _show_menu, 150)
	back.position = Vector2(1050, 48)
	multiplayer_panel.add_child(back)
	var intro := _label("Choose how many putters are sharing this device.", 20, Color("#b9d2ee"))
	intro.position = Vector2(76, 135)
	intro.size = Vector2(600, 35)
	multiplayer_panel.add_child(intro)
	var row := HBoxContainer.new()
	row.position = Vector2(76, 205)
	row.size = Vector2(700, 100)
	row.add_theme_constant_override("separation", 16)
	multiplayer_panel.add_child(row)
	for count in range(2, 5):
		var b := _button(str(count) + " PLAYERS", _start_multiplayer.bind(count), false, 210)
		row.add_child(b)
	var note := _label("Each player gets a color-coded ball. Lowest total score wins.\nEvery course is playable without an internet connection.", 18, Color("#8faed0"))
	note.position = Vector2(78, 350)
	note.size = Vector2(700, 90)
	multiplayer_panel.add_child(note)

func _build_game_hud() -> void:
	game_panel.visible = false
	var top := ColorRect.new()
	top.color = Color("#081426cc")
	top.position = Vector2(0, 0)
	top.size = Vector2(1280, 104)
	game_panel.add_child(top)
	hud_world = _label("SUNNY PARK", 16, Color("#83dbe8"))
	hud_world.position = Vector2(32, 18)
	hud_world.size = Vector2(300, 24)
	game_panel.add_child(hud_world)
	hud_hole = _label("HOLE 01  •  MEADOW GATE", 26, Color("#ffffff"))
	hud_hole.position = Vector2(30, 42)
	hud_hole.size = Vector2(530, 42)
	game_panel.add_child(hud_hole)
	hud_strokes = _label("STROKES 0", 20, Color("#f8d66d"))
	hud_strokes.position = Vector2(695, 32)
	hud_strokes.size = Vector2(150, 32)
	game_panel.add_child(hud_strokes)
	hud_par = _label("PAR 3", 20, Color("#d9e6fb"))
	hud_par.position = Vector2(850, 32)
	hud_par.size = Vector2(110, 32)
	game_panel.add_child(hud_par)
	hud_turn = _label("", 16, Color("#ffdb56"))
	hud_turn.position = Vector2(695, 67)
	hud_turn.size = Vector2(280, 24)
	game_panel.add_child(hud_turn)
	var pause := _button("PAUSE", _pause_game, 128)
	pause.position = Vector2(1118, 24)
	game_panel.add_child(pause)
	var restart := _button("RESTART", _restart_hole, 128)
	restart.position = Vector2(974, 24)
	game_panel.add_child(restart)
	power_bar = ProgressBar.new()
	power_bar.position = Vector2(470, 612)
	power_bar.size = Vector2(340, 25)
	power_bar.min_value = 0
	power_bar.max_value = 1
	power_bar.show_percentage = false
	game_panel.add_child(power_bar)
	power_text = _label("POWER  0%", 15, Color("#fff3bd"))
	power_text.position = Vector2(470, 642)
	power_text.size = Vector2(340, 26)
	power_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_panel.add_child(power_text)
	hud_hint = _label("DRAG BACK FROM THE BALL  •  RELEASE TO PUTT", 17, Color("#e4f2ff"))
	hud_hint.position = Vector2(310, 675)
	hud_hint.size = Vector2(660, 28)
	hud_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_panel.add_child(hud_hint)
	var camera_hint := _label("SWIPE WITH TWO FINGERS TO PAN CAMERA", 12, Color("#89a7c7"))
	camera_hint.position = Vector2(30, 675)
	camera_hint.size = Vector2(260, 28)
	game_panel.add_child(camera_hint)
	var guide := _label("", 15, Color("#ffe48a"))
	guide.position = Vector2(34, 550)
	guide.size = Vector2(350, 70)
	guide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_panel.add_child(guide)
	aim_hint = guide

func _build_result() -> void:
	result_panel.visible = false
	var shade := ColorRect.new()
	shade.color = Color("#061024e6")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_panel.add_child(shade)
	var card := Panel.new()
	card.position = Vector2(300, 145)
	card.size = Vector2(680, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#172a4a")
	style.border_color = Color("#f8d66d")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 28
	style.corner_radius_top_right = 28
	style.corner_radius_bottom_left = 28
	style.corner_radius_bottom_right = 28
	card.add_theme_stylebox_override("panel", style)
	result_panel.add_child(card)
	result_title = _label("HOLE COMPLETE", 40, Color("#f8d66d"))
	result_title.position = Vector2(44, 42)
	result_title.size = Vector2(590, 56)
	result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(result_title)
	result_body = _label("", 22, Color("#dcecff"))
	result_body.position = Vector2(60, 126)
	result_body.size = Vector2(560, 155)
	result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(result_body)
	var next := _button("NEXT HOLE", _next_hole, 190, true)
	next.position = Vector2(118, 328)
	card.add_child(next)
	var retry := _button("RETRY", _restart_hole, 140)
	retry.position = Vector2(328, 328)
	card.add_child(retry)
	var menu := _button("MENU", _show_menu, 140)
	menu.position = Vector2(488, 328)
	card.add_child(menu)

func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _button(text_value: String, callback: Callable, width: int = 200, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(width, 46)
	button.add_theme_font_size_override("font_size", 16 if not primary else 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#25466f") if not primary else Color("#efb84d")
	normal.border_color = Color("#6f9bc7") if not primary else Color("#ffe89c")
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 11
	normal.corner_radius_top_right = 11
	normal.corner_radius_bottom_left = 11
	normal.corner_radius_bottom_right = 11
	var hover := normal.duplicate()
	hover.bg_color = Color("#35649a") if not primary else Color("#ffd56d")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("disabled", normal)
	button.pressed.connect(callback)
	return button

func _add_button(container: Container, text_value: String, callback: Callable, primary: bool = false, width: int = 0) -> Button:
	var button := _button(text_value, callback, width if width > 0 else 360, primary)
	container.add_child(button)
	return button

func _make_orb(pos: Vector2, radius: float, color: Color) -> Control:
	var orb := Panel.new()
	orb.position = pos - Vector2(radius, radius)
	orb.size = Vector2(radius * 2.0, radius * 2.0)
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	orb.add_theme_stylebox_override("panel", style)
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return orb

func _set_sound_volume(value: float) -> void:
	sound_volume = value
	_save_game()

func _set_music_volume(value: float) -> void:
	music_volume = value
	_save_game()

func _set_camera_sensitivity(value: float) -> void:
	camera_sensitivity = clamp(value * 2.0, 0.25, 2.0)
	_save_game()

func _hide_all_panels() -> void:
	menu_panel.visible = false
	course_select_panel.visible = false
	settings_panel.visible = false
	credits_panel.visible = false
	multiplayer_panel.visible = false
	game_panel.visible = false
	result_panel.visible = false
	toast_label.visible = false

func _show_menu() -> void:
	_hide_all_panels()
	screen_mode = "menu"
	menu_panel.visible = true
	if course_root:
		course_root.visible = false
	if ball:
		ball.freeze = true

func _show_course_select() -> void:
	_hide_all_panels()
	screen_mode = "course_select"
	course_select_panel.visible = true
	course_root.visible = false

func _show_settings() -> void:
	_hide_all_panels()
	screen_mode = "settings"
	settings_panel.visible = true
	course_root.visible = false

func _show_credits() -> void:
	_hide_all_panels()
	screen_mode = "credits"
	credits_panel.visible = true
	course_root.visible = false

func _show_multiplayer() -> void:
	_hide_all_panels()
	screen_mode = "multiplayer"
	multiplayer_panel.visible = true
	course_root.visible = false

func _start_campaign() -> void:
	play_mode = "campaign"
	player_count = 1
	active_player = 0
	_start_hole(_first_unlocked_hole())

func _start_quick_play() -> void:
	play_mode = "quick"
	player_count = 1
	active_player = 0
	var available: Array[int] = []
	for index in range(holes.size()):
		if _hole_unlocked(index):
			available.append(index)
	var chosen := available[randi() % available.size()] if not available.is_empty() else 0
	_start_hole(chosen)

func _start_practice() -> void:
	play_mode = "practice"
	player_count = 1
	active_player = 0
	_show_course_select()

func _start_multiplayer(count: int) -> void:
	play_mode = "multiplayer"
	player_count = count
	active_player = 0
	round_scores.clear()
	for i in range(player_count):
		round_scores.append([])
	_start_hole(_first_unlocked_hole())

func _select_hole(index: int) -> void:
	if not _hole_unlocked(index):
		_show_toast("Complete earlier holes to unlock this line.")
		return
	if play_mode == "practice":
		_start_hole(index)
	else:
		play_mode = "campaign"
		_start_hole(index)

func _first_unlocked_hole() -> int:
	return clamp(int(save_data.get("unlocked_hole", 0)), 0, holes.size() - 1)

func _hole_unlocked(index: int) -> bool:
	return index <= int(save_data.get("unlocked_hole", 0))

func _start_hole(index: int) -> void:
	_hide_all_panels()
	screen_mode = "game"
	game_panel.visible = true
	course_root.visible = true
	current_hole = clamp(index, 0, holes.size() - 1)
	current_world = int(holes[current_hole]["world"])
	current_type = str(holes[current_hole]["type"])
	par = int(holes[current_hole]["par"])
	strokes = 0
	completed = false
	shot_active = false
	shot_cooldown = 0.0
	_build_course(holes[current_hole])
	_update_hud()

func _clear_course() -> void:
	for child in course_root.get_children():
		child.queue_free()
	hazard_areas.clear()
	launcher_areas.clear()
	teleporter_areas.clear()
	moving_props.clear()
	ball = null
	cup_area = null

func _build_course(hole: Dictionary) -> void:
	_clear_course()
	var theme: Dictionary = WORLD_DEFS[current_world]
	RenderingServer.set_default_clear_color(theme["sky"])
	var base_color: Color = theme["ground"]
	var fairway_color: Color = theme["fairway"]
	var accent: Color = theme["accent"]
	var wall_color: Color = theme["wall"]
	var hazard_color: Color = theme["hazard"]
	var floor := _add_static_box("CourseDeck", Vector3(0, -0.45, 0), Vector3(22, 0.7, 15), base_color)
	floor.material_override = _material(base_color, 0.9)
	_add_static_box("PlayableGreen", Vector3(0, 0.04, 0), Vector3(19.5, 0.18, 12.5), fairway_color)
	_add_decorative_border(theme)
	var start := Vector3(-7.4, 0.58, 0)
	var cup := Vector3(7.0, 0.24, 0)
	if current_hole % 2 == 1:
		start = Vector3(-6.9, 0.58, 4.0)
		cup = Vector3(6.8, 0.24, -3.8)
	if current_hole % 3 == 2:
		start = Vector3(5.8, 0.58, 4.1)
		cup = Vector3(-6.8, 0.24, -3.5)
	last_safe_position = start
	_add_static_box("NorthWall", Vector3(0, 0.72, -6.35), Vector3(20.5, 1.3, 0.42), wall_color)
	_add_static_box("SouthWall", Vector3(0, 0.72, 6.35), Vector3(20.5, 1.3, 0.42), wall_color)
	_add_static_box("WestWall", Vector3(-9.95, 0.72, 0), Vector3(0.42, 1.3, 12.3), wall_color)
	_add_static_box("EastWall", Vector3(9.95, 0.72, 0), Vector3(0.42, 1.3, 12.3), wall_color)
	_build_layout(current_type, start, cup, fairway_color, wall_color, accent, hazard_color)
	_add_cup(cup, accent)
	_add_ball(start, player_colors[active_player] if player_count > 1 else Color("#fffdf1"))
	camera.position = start + Vector3(0, 13, 12)
	camera.look_at(start + Vector3(0, 0, 0))
	if shot_guide_enabled:
		aim_hint.text = "TIP  •  Pull straight back for a clean putt.\nBank shots can open the shortcut."
	else:
		aim_hint.text = ""

func _build_layout(kind: String, start: Vector3, cup: Vector3, fairway: Color, wall: Color, accent: Color, hazard: Color) -> void:
	match kind:
		"classic":
			_add_static_box("BankA", Vector3(-1.8, 0.65, -2.2), Vector3(5.8, 1.0, 0.35), wall, 0.0, 0.13)
			_add_static_box("BankB", Vector3(1.6, 0.65, 2.2), Vector3(5.4, 1.0, 0.35), wall, 0.0, -0.13)
			_add_ramp(Vector3(2.8, 0.28, -1.1), Vector3(4.2, 0.36, 2.2), 0.0, fairway)
		"ramp":
			_add_ramp(Vector3(-2.6, 0.2, 0), Vector3(5.0, 0.45, 3.4), -0.12, fairway)
			_add_ramp(Vector3(3.1, 0.5, 0.3), Vector3(4.2, 0.45, 3.1), 0.16, fairway)
			_add_static_box("JumpRail", Vector3(0, 0.82, -2.3), Vector3(5.5, 0.75, 0.28), wall)
			_add_static_box("LandingRail", Vector3(0.2, 0.82, 2.4), Vector3(5.5, 0.75, 0.28), wall)
		"moving":
			_add_moving_gate(Vector3(-2.0, 1.0, 0), Vector3(0, 0, 3.4), 1.7, wall)
			_add_moving_gate(Vector3(2.3, 1.0, 0), Vector3(0, 0, 2.8), 2.3, accent)
			_add_bumper(Vector3(0, 0.42, -2.4), accent, 0.72)
			_add_bumper(Vector3(0, 0.42, 2.4), accent, 0.72)
		"bumper":
			for pos in [Vector3(-3.2, 0.45, -2.1), Vector3(-0.8, 0.45, 2.0), Vector3(1.4, 0.45, -1.7), Vector3(4.0, 0.45, 2.2)]:
				_add_bumper(pos, accent, 0.58)
			_add_static_box("PinballRailA", Vector3(-1.0, 0.75, -3.6), Vector3(6.0, 0.5, 0.28), wall, 0.0, 0.22)
			_add_static_box("PinballRailB", Vector3(1.2, 0.75, 3.6), Vector3(6.0, 0.5, 0.28), wall, 0.0, -0.22)
		"maze":
			_add_static_box("MazeA", Vector3(-3.0, 0.72, -1.5), Vector3(0.35, 1.35, 7.0), wall)
			_add_static_box("MazeB", Vector3(0.0, 0.72, 1.6), Vector3(5.6, 1.35, 0.35), wall)
			_add_static_box("MazeC", Vector3(3.1, 0.72, -1.7), Vector3(0.35, 1.35, 6.1), wall)
			_add_static_box("MazeD", Vector3(-0.7, 0.72, -4.0), Vector3(4.8, 1.35, 0.35), wall)
			_add_static_box("MazeE", Vector3(2.8, 0.72, 3.8), Vector3(4.0, 1.35, 0.35), wall)
		"trick":
			_add_ramp(Vector3(-2.6, 0.2, 0), Vector3(4.6, 0.42, 2.3), -0.2, fairway)
			_add_launcher(Vector3(-0.1, 0.3, -3.0), Vector3(0, 0, 1), accent)
			_add_teleporter(Vector3(2.4, 0.28, -3.2), Vector3(4.2, 0.28, 2.8), accent)
			_add_static_box("TrickRail", Vector3(4.0, 0.8, 0.0), Vector3(0.35, 1.4, 5.8), wall)
			_add_bumper(Vector3(4.8, 0.45, -3.6), accent, 0.72)
			_add_bumper(Vector3(4.8, 0.45, 3.7), accent, 0.72)
	# World-specific signature props.
	if current_world == 0:
		_add_tree_cluster(Vector3(-5.8, 0.4, -5.3), Color("#4d9b5b"))
		_add_tree_cluster(Vector3(5.8, 0.4, 5.2), Color("#4d9b5b"))
	elif current_world == 1:
		_add_candy_canes(Vector3(-5.8, 0.5, 4.9), accent)
		_add_candy_canes(Vector3(5.8, 0.5, -4.9), Color("#7fd9ff"))
	elif current_world == 2:
		_add_neon_bars(accent)
	elif current_world == 3:
		_add_barrel(Vector3(-6.0, 0.55, -5.1), wall)
		_add_barrel(Vector3(5.6, 0.55, 5.0), wall)
	elif current_world == 4:
		_add_space_beacons(accent)
		_add_hazard(Vector3(0, 0.05, -5.15), Vector3(7.0, 0.08, 1.1), hazard)

func _add_decorative_border(theme: Dictionary) -> void:
	for i in range(9):
		var pos_left := Vector3(-10.8, 0.0, -5.2 + i * 1.3)
		var pos_right := Vector3(10.8, 0.0, -5.2 + i * 1.3)
		_add_decorative_post(pos_left, theme["accent"])
		_add_decorative_post(pos_right, theme["accent"])

func _add_decorative_post(pos: Vector3, color: Color) -> void:
	var post := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.08
	mesh.bottom_radius = 0.11
	mesh.height = 0.8
	mesh.radial_segments = 8
	post.mesh = mesh
	post.position = pos + Vector3(0, 0.4, 0)
	post.material_override = _material(color, 0.45, true)
	course_root.add_child(post)

func _add_static_box(name_value: String, pos: Vector3, size: Vector3, color: Color, rot_y: float = 0.0, rot_z: float = 0.0) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.name = name_value
	body.position = pos
	body.rotation = Vector3(0, rot_y, rot_z)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	course_root.add_child(body)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color)
	body.add_child(visual)
	return visual

func _add_ramp(pos: Vector3, size: Vector3, tilt: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = "SlopedFairway"
	body.position = pos
	body.rotation.z = tilt
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	course_root.add_child(body)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color, 0.75)
	body.add_child(visual)

func _add_bumper(pos: Vector3, color: Color, radius: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Bumper"
	body.position = pos
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	body.add_child(shape)
	course_root.add_child(body)
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	visual.mesh = mesh
	visual.material_override = _material(color, 0.3, current_world == 2)
	body.add_child(visual)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.78
	torus.outer_radius = radius * 0.9
	torus.rings = 16
	torus.ring_segments = 8
	ring.mesh = torus
	ring.material_override = _material(Color("#fff1a8"), 0.25, true)
	ring.position.y = 0.08
	body.add_child(ring)

func _add_moving_gate(pos: Vector3, travel: Vector3, speed: float, color: Color) -> void:
	var body := AnimatableBody3D.new()
	body.name = "MovingGate"
	body.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.42, 1.7, 3.2)
	shape.shape = box
	body.add_child(shape)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	visual.mesh = mesh
	visual.material_override = _material(color, 0.35, current_world == 2)
	body.add_child(visual)
	course_root.add_child(body)
	moving_props.append({"node": body, "origin": pos, "travel": travel, "speed": speed, "phase": float(moving_props.size()) * 0.8})

func _add_launcher(pos: Vector3, direction: Vector3, color: Color) -> void:
	var area := Area3D.new()
	area.name = "Launcher"
	area.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 0.25, 1.9)
	shape.shape = box
	area.add_child(shape)
	area.body_entered.connect(_on_launcher_entered.bind(direction))
	course_root.add_child(area)
	launcher_areas.append(area)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.85
	mesh.bottom_radius = 0.85
	mesh.height = 0.12
	mesh.radial_segments = 24
	visual.mesh = mesh
	visual.material_override = _material(color, 0.25, true)
	area.add_child(visual)
	var arrow := _make_arrow_mesh(color)
	arrow.position.y = 0.12
	arrow.rotation.y = atan2(direction.x, direction.z)
	area.add_child(arrow)

func _add_teleporter(from_pos: Vector3, to_pos: Vector3, color: Color) -> void:
	var first := _make_teleport_area(from_pos, color)
	var second := _make_teleport_area(to_pos, color)
	first.set_meta("target", to_pos + Vector3(0, 0.6, 0))
	second.set_meta("target", from_pos + Vector3(0, 0.6, 0))
	teleporter_areas.append(first)
	teleporter_areas.append(second)

func _make_teleport_area(pos: Vector3, color: Color) -> Area3D:
	var area := Area3D.new()
	area.name = "TeleportPad"
	area.position = pos
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.95
	cyl.height = 0.18
	shape.shape = cyl
	area.add_child(shape)
	area.body_entered.connect(_on_teleporter_entered.bind(area))
	course_root.add_child(area)
	var visual := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.95
	mesh.bottom_radius = 0.95
	mesh.height = 0.1
	mesh.radial_segments = 24
	visual.mesh = mesh
	visual.material_override = _material(color, 0.2, true)
	area.add_child(visual)
	return area

func _add_hazard(pos: Vector3, size: Vector3, color: Color) -> void:
	var area := Area3D.new()
	area.name = "WaterHazard"
	area.position = pos
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.body_entered.connect(_on_hazard_entered)
	course_root.add_child(area)
	hazard_areas.append(area)
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = _material(color, 0.1, current_world == 2)
	area.add_child(visual)

func _add_cup(pos: Vector3, color: Color) -> void:
	cup_area = Area3D.new()
	cup_area.name = "CupGoal"
	cup_area.position = pos
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.48
	cyl.height = 0.6
	shape.shape = cyl
	cup_area.add_child(shape)
	cup_area.body_entered.connect(_on_cup_entered)
	course_root.add_child(cup_area)
	var hole := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.55
	torus.rings = 24
	torus.ring_segments = 10
	hole.mesh = torus
	hole.position.y = 0.04
	hole.material_override = _material(Color("#172037"), 0.2)
	cup_area.add_child(hole)
	var flagpole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.035
	pole_mesh.bottom_radius = 0.045
	pole_mesh.height = 2.0
	pole_mesh.radial_segments = 8
	flagpole.mesh = pole_mesh
	flagpole.position = Vector3(0, 1.0, 0)
	flagpole.material_override = _material(Color("#fff6db"), 0.5)
	cup_area.add_child(flagpole)
	var flag := MeshInstance3D.new()
	var flag_mesh := BoxMesh.new()
	flag_mesh.size = Vector3(0.9, 0.45, 0.05)
	flag.mesh = flag_mesh
	flag.position = Vector3(0.42, 1.65, 0)
	flag.material_override = _material(color, 0.35, current_world == 2)
	cup_area.add_child(flag)

func _add_ball(pos: Vector3, color: Color) -> void:
	ball = RigidBody3D.new()
	ball.name = "PuttBall"
	ball.position = pos
	ball.mass = 0.16
	ball.gravity_scale = 1.0 if current_world != 4 else 0.48
	ball.linear_damp = 0.3 if current_world != 4 else 0.12
	ball.angular_damp = 0.5
	ball.continuous_cd = true
	ball.contact_monitor = true
	ball.max_contacts_reported = 8
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 0.34
	shape.shape = sphere_shape
	ball.add_child(shape)
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.34
	sphere.height = 0.68
	sphere.radial_segments = 20
	sphere.rings = 12
	visual.mesh = sphere
	visual.material_override = _material(color, 0.18)
	ball.add_child(visual)
	var shine := OmniLight3D.new()
	shine.light_color = color
	shine.light_energy = 0.18
	shine.omni_range = 2.0
	ball.add_child(shine)
	course_root.add_child(ball)

func _material(color: Color, roughness: float = 0.65, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.7
	return material

func _make_arrow_mesh(color: Color) -> MeshInstance3D:
	var arrow := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.12, 0.85)
	arrow.mesh = mesh
	arrow.material_override = _material(color, 0.2, true)
	return arrow

func _add_tree_cluster(pos: Vector3, color: Color) -> void:
	for i in range(3):
		var tree := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.7 + i * 0.13
		mesh.height = 1.4 + i * 0.2
		mesh.radial_segments = 10
		mesh.rings = 6
		tree.mesh = mesh
		tree.position = pos + Vector3((i - 1) * 0.65, 1.0 + i * 0.2, (i % 2) * 0.5)
		tree.material_override = _material(color.lightened(i * 0.08), 0.85)
		course_root.add_child(tree)

func _add_candy_canes(pos: Vector3, color: Color) -> void:
	var pole := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.13
	mesh.bottom_radius = 0.18
	mesh.height = 2.1
	mesh.radial_segments = 10
	pole.mesh = mesh
	pole.position = pos + Vector3(0, 1.05, 0)
	pole.material_override = _material(color, 0.35)
	course_root.add_child(pole)
	_add_bumper(pos + Vector3(0, 2.1, 0), Color("#fff5d2"), 0.28)

func _add_neon_bars(color: Color) -> void:
	for i in range(5):
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.12, 9.0)
		bar.mesh = mesh
		bar.position = Vector3(-8.0 + i * 4.0, 0.13, 0)
		bar.material_override = _material(color, 0.2, true)
		course_root.add_child(bar)

func _add_barrel(pos: Vector3, color: Color) -> void:
	var barrel := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.62
	mesh.height = 1.05
	mesh.radial_segments = 14
	barrel.mesh = mesh
	barrel.position = pos
	barrel.rotation.z = 0.12
	barrel.material_override = _material(color, 0.7)
	course_root.add_child(barrel)

func _add_space_beacons(color: Color) -> void:
	for pos in [Vector3(-8.5, 0.8, -5.2), Vector3(8.5, 0.8, -5.2), Vector3(-8.5, 0.8, 5.2), Vector3(8.5, 0.8, 5.2)]:
		var beacon := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.24
		mesh.bottom_radius = 0.35
		mesh.height = 1.6
		mesh.radial_segments = 8
		beacon.mesh = mesh
		beacon.position = pos
		beacon.material_override = _material(color, 0.2, true)
		course_root.add_child(beacon)

func _process(delta: float) -> void:
	elapsed += delta
	for moving in moving_props:
		var node: AnimatableBody3D = moving["node"]
		if is_instance_valid(node):
			var phase: float = moving["phase"]
			var travel: Vector3 = moving["travel"]
			node.position = moving["origin"] + travel * sin(elapsed * float(moving["speed"]) + phase)
	if screen_mode == "game" and is_instance_valid(ball):
		var target := ball.global_position + Vector3(0, 0.15, 0)
		camera.global_position = camera.global_position.lerp(target + Vector3(0, 13.0, 12.0), min(delta * 4.5, 1.0))
		camera.look_at(target)
		if shot_active:
			shot_cooldown += delta
			if shot_cooldown > 0.45 and ball.linear_velocity.length() < 0.075:
				ball.linear_velocity = Vector3.ZERO
				ball.angular_velocity = Vector3.ZERO
				shot_active = false
				last_safe_position = ball.global_position
				_update_hud()
			if ball.global_position.y < -2.0 or abs(ball.global_position.x) > 12.0 or abs(ball.global_position.z) > 10.0:
				_reset_ball("OUT OF BOUNDS  •  BALL RESET")
	if aiming:
		_update_aim_visual()

func _input(event: InputEvent) -> void:
	if screen_mode != "game" or not is_instance_valid(ball) or shot_active or completed:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_aim(event.position)
		else:
			_end_aim(event.position)
	elif event is InputEventScreenDrag:
		_update_aim(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_aim(event.position)
		else:
			_end_aim(event.position)
	elif event is InputEventMouseMotion and aiming:
		_update_aim(event.position)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_pause_game()
		elif event.keycode == KEY_R:
			_restart_hole()
		elif event.keycode == KEY_SPACE and not aiming:
			_shoot(Vector3(0, 0, 1), 0.62)

func _begin_aim(position: Vector2) -> void:
	if position.y < 115:
		return
	aiming = true
	aim_start = position
	aim_current = position
	_update_aim(position)

func _update_aim(position: Vector2) -> void:
	if not aiming:
		return
	aim_current = position
	var pull := aim_start - aim_current
	var raw_power: float = clampf(pull.length() / 210.0, 0.0, 1.0)
	if raw_power < 0.03:
		aim_direction = Vector3(0, 0, 1)
	else:
		aim_direction = Vector3(pull.x, 0, pull.y).normalized()
	aim_power = raw_power
	power_bar.value = aim_power
	power_text.text = "POWER  " + str(int(aim_power * 100.0)) + "%"
	_update_aim_visual()

func _end_aim(position: Vector2) -> void:
	if not aiming:
		return
	_update_aim(position)
	aiming = false
	aim_mesh_instance.visible = false
	if aim_power > 0.06:
		_shoot(aim_direction, aim_power)
	else:
		power_bar.value = 0
		power_text.text = "POWER  0%"

func _update_aim_visual() -> void:
	if not is_instance_valid(ball) or aim_power <= 0.01:
		aim_mesh_instance.visible = false
		return
	aim_mesh_instance.visible = true
	aim_immediate.clear_surfaces()
	var mat := aim_mesh_instance.material_override
	aim_immediate.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var start := ball.global_position + Vector3(0, 0.18, 0)
	var end := start + aim_direction * (2.0 + aim_power * 7.5)
	aim_immediate.surface_add_vertex(start)
	aim_immediate.surface_add_vertex(end)
	for i in range(1, 5):
		var p := start.lerp(end, float(i) / 5.0)
		aim_immediate.surface_add_vertex(p + Vector3(0, 0.015 * i, 0))
		aim_immediate.surface_add_vertex(p + aim_direction * 0.17 + Vector3(0, 0.015 * i, 0))
	aim_immediate.surface_end()

func _shoot(direction: Vector3, power: float) -> void:
	if shot_active or completed or not is_instance_valid(ball):
		return
	strokes += 1
	shot_active = true
	shot_cooldown = 0.0
	ball.sleeping = false
	ball.apply_central_impulse(direction.normalized() * (3.7 + power * 8.0))
	ball.apply_torque_impulse(Vector3(-direction.z, 0, direction.x) * power * 0.18)
	_play_audio(hit_audio)
	_show_toast("NICE LINE  •  STROKE " + str(strokes))
	_update_hud()
	if strokes >= MAX_STROKES:
		await get_tree().create_timer(0.75).timeout
		if not completed and is_instance_valid(ball):
			_reset_ball("STROKE LIMIT  •  TRY A FRESH LINE")

func _update_hud() -> void:
	if not is_instance_valid(hud_world):
		return
	var hole: Dictionary = holes[current_hole]
	hud_world.text = str(WORLD_DEFS[current_world]["name"]).to_upper() + "  •  " + str(TYPE_LABELS[current_type])
	hud_hole.text = "HOLE " + str(int(hole["number"])).pad_zeros(2) + "  •  " + str(hole["name"])
	hud_strokes.text = "STROKES " + str(strokes)
	hud_par.text = "PAR " + str(par)
	hud_turn.text = (player_names[active_player] + "'S TURN") if player_count > 1 else "CAMPAIGN RUN"
	if not aiming:
		power_bar.value = 0
		power_text.text = "POWER  0%"

func _pause_game() -> void:
	if screen_mode != "game" or completed:
		return
	get_tree().paused = true
	var pause_panel := _make_pause_overlay()
	ui_layer.add_child(pause_panel)

func _make_pause_overlay() -> Control:
	var panel := _make_full_panel()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color("#061024dd")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(shade)
	var title := _label("PAUSED", 50, Color("#f8d66d"))
	title.position = Vector2(455, 175)
	title.size = Vector2(370, 70)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)
	var stack := VBoxContainer.new()
	stack.position = Vector2(450, 285)
	stack.size = Vector2(380, 190)
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	_add_button(stack, "RESUME", func(): _close_pause(panel), true)
	_add_button(stack, "RESTART HOLE", func(): _close_pause(panel); _restart_hole(), false)
	_add_button(stack, "RETURN TO MENU", func(): _close_pause(panel); _show_menu(), false)
	return panel

func _close_pause(panel: Control) -> void:
	get_tree().paused = false
	panel.queue_free()

func _restart_hole() -> void:
	if screen_mode != "game" and screen_mode != "result":
		return
	get_tree().paused = false
	result_panel.visible = false
	_start_hole(current_hole)

func _next_hole() -> void:
	result_panel.visible = false
	get_tree().paused = false
	if player_count > 1:
		active_player = (active_player + 1) % player_count
		if active_player == 0:
			current_hole += 1
	else:
		current_hole += 1
	if current_hole >= holes.size():
		current_hole = 0
	_start_hole(current_hole)

func _on_cup_entered(body: Node3D) -> void:
	if body != ball or completed or not shot_active:
		return
	completed = true
	shot_active = false
	_play_audio(cup_audio)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	ball.freeze = true
	var score_delta := strokes - par
	var medal := "GOLD MEDAL"
	if score_delta > 0:
		medal = "SILVER MEDAL" if score_delta == 1 else "BRONZE MEDAL"
	if strokes == 1:
		medal = "HOLE-IN-ONE"
	if player_count > 1:
		round_scores[active_player].append(strokes)
	else:
		_save_best(current_hole, strokes)
	if play_mode == "campaign" and player_count == 1:
		save_data["unlocked_hole"] = max(int(save_data.get("unlocked_hole", 0)), min(current_hole + 1, holes.size() - 1))
		_save_game()
	result_title.text = medal
	var comparison := "EVEN PAR"
	if score_delta < 0:
		comparison = str(abs(score_delta)) + " UNDER PAR"
	elif score_delta > 0:
		comparison = "+" + str(score_delta) + " OVER PAR"
	var best_text := ""
	if player_count == 1:
		best_text = "\nBEST: " + str(_best_for(current_hole)) + " STROKES"
	result_body.text = str(holes[current_hole]["name"]) + "\n\n" + str(strokes) + " STROKES  •  PAR " + str(par) + "\n" + comparison + "\n" + best_text
	result_panel.visible = true
	game_panel.visible = false
	screen_mode = "result"
	_show_toast("CUPPED  •  " + medal)

func _on_hazard_entered(body: Node3D) -> void:
	if body == ball and not completed:
		_reset_ball("HAZARD  •  BACK TO THE LAST SAFE SPOT")

func _on_launcher_entered(body: Node3D, direction: Vector3) -> void:
	if body == ball and not completed:
		ball.apply_central_impulse(direction.normalized() * 8.0)
		_show_toast("LAUNCH BOOST")

func _on_teleporter_entered(body: Node3D, area: Area3D) -> void:
	if body == ball and not completed and area.has_meta("target"):
		ball.global_position = area.get_meta("target")
		ball.linear_velocity = Vector3.ZERO
		_show_toast("ROUTE SHIFT")

func _reset_ball(message: String) -> void:
	if not is_instance_valid(ball):
		return
	_play_audio(hazard_audio)
	ball.freeze = true
	ball.global_position = last_safe_position + Vector3(0, 0.04, 0)
	ball.linear_velocity = Vector3.ZERO
	ball.angular_velocity = Vector3.ZERO
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(ball):
		ball.freeze = false
		ball.sleeping = true
	shot_active = false
	shot_cooldown = 0.0
	_show_toast(message)
	_update_hud()

func _show_toast(message: String) -> void:
	if not is_instance_valid(toast_label):
		return
	toast_label.text = message
	toast_label.visible = true
	var tween := create_tween()
	tween.tween_interval(1.45)
	tween.tween_callback(func():
		if is_instance_valid(toast_label):
			toast_label.visible = false
	)

func _load_save() -> void:
	save_data = {"unlocked_hole": 0, "best": {}, "settings": {"sound": sound_volume, "music": music_volume, "camera": camera_sensitivity, "guide": shot_guide_enabled}}
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		for key in parsed:
			save_data[key] = parsed[key]
	var settings: Dictionary = save_data.get("settings", {})
	sound_volume = float(settings.get("sound", sound_volume))
	music_volume = float(settings.get("music", music_volume))
	camera_sensitivity = float(settings.get("camera", camera_sensitivity))
	shot_guide_enabled = bool(settings.get("guide", shot_guide_enabled))

func _save_game() -> void:
	if save_data.is_empty():
		return
	save_data["settings"] = {"sound": sound_volume, "music": music_volume, "camera": camera_sensitivity, "guide": shot_guide_enabled}
	var temp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(save_data))
	file.close()
	DirAccess.rename_absolute(temp_path, SAVE_PATH)

func _save_best(index: int, value: int) -> void:
	var best: Dictionary = save_data.get("best", {})
	var key := str(index)
	if not best.has(key) or int(best[key]) > value:
		best[key] = value
		save_data["best"] = best

func _best_for(index: int) -> int:
	var best: Dictionary = save_data.get("best", {})
	return int(best.get(str(index), 0)) if best.has(str(index)) else 0
