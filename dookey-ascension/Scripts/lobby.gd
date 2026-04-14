extends Control

var qr_texture   : TextureRect
var http_request : HTTPRequest
var code_label   : Label
var lien_label   : Label
var joueurs_titre_label: Label
var joueurs_flow : HFlowContainer
var liste_joueurs: Array[String] = []

# Animation fond
var bg_anim      : TextureRect
var anim_frame   : int = 0
var anim_dir     : int = 1  # +1 = vers 4, -1 = vers 0
const NB_FRAMES  : int = 5  # frames 0..4

func _ready() -> void:
	# Fond animé ping-pong (pixil-frame-0.png .. pixil-frame-4.png)
	bg_anim = TextureRect.new()
	bg_anim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_anim.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_anim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_charger_frame(0)
	add_child(bg_anim)
	
	# Timer d'animation : 8 fps ≈ 0.125s par frame
	var timer = Timer.new()
	timer.wait_time = 0.125
	timer.autostart = true
	timer.timeout.connect(_avancer_frame_anim)
	add_child(timer)
	
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	bg_anim.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	var panel_global = PanelContainer.new()
	panel_global.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel_global.custom_minimum_size = Vector2(750, 0)
	var global_style = StyleBoxFlat.new()
	global_style.bg_color = Color(0.96, 0.92, 0.76, 1.0) # Sand / Light Dirt
	global_style.border_width_bottom = 6
	global_style.border_width_top = 6
	global_style.border_width_left = 6
	global_style.border_width_right = 6
	global_style.border_color = Color(0.55, 0.35, 0.15, 1.0) # Bark/Dirt Brown
	global_style.corner_radius_top_left = 12
	global_style.corner_radius_top_right = 12
	global_style.corner_radius_bottom_left = 12
	global_style.corner_radius_bottom_right = 12
	global_style.shadow_color = Color(0.2, 0.4, 0.6, 0.3)
	global_style.shadow_size = 0
	global_style.shadow_offset = Vector2(8, 8) # Hard crisp shadow
	global_style.set_content_margin_all(20)
	panel_global.add_theme_stylebox_override("panel", global_style)
	vbox.add_child(panel_global)
	
	var inner_vbox = VBoxContainer.new()
	inner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	inner_vbox.add_theme_constant_override("separation", 8)
	panel_global.add_child(inner_vbox)
	
	var titre = Label.new()
	titre.text = "SALLE D'ATTENTE"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	var titre_settings = LabelSettings.new()
	titre_settings.font_size = 46
	titre_settings.font_color = Color(1.0, 1.0, 1.0)
	titre_settings.outline_size = 8
	titre_settings.outline_color = Color(0.4, 0.2, 0.05) # Deep brown outline
	titre_settings.shadow_color = Color(0.0, 0.0, 0.0, 0.2)
	titre_settings.shadow_size = 0
	titre_settings.shadow_offset = Vector2(4, 4)
	titre.label_settings = titre_settings
	inner_vbox.add_child(titre)
	
	var qr_margin = MarginContainer.new()
	qr_margin.add_theme_constant_override("margin_top", 5)
	qr_margin.add_theme_constant_override("margin_bottom", 5)
	inner_vbox.add_child(qr_margin)
	
	var qr_bg = PanelContainer.new()
	var qr_style = StyleBoxFlat.new()
	qr_style.bg_color = Color.WHITE
	qr_style.border_width_bottom = 4
	qr_style.border_width_top = 4
	qr_style.border_width_left = 4
	qr_style.border_width_right = 4
	qr_style.border_color = Color(0.55, 0.35, 0.15)
	qr_style.corner_radius_top_left = 8
	qr_style.corner_radius_top_right = 8
	qr_style.corner_radius_bottom_left = 6
	qr_style.corner_radius_bottom_right = 6
	qr_bg.add_theme_stylebox_override("panel", qr_style)
	qr_bg.custom_minimum_size = Vector2(150, 150)
	qr_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var qr_center = CenterContainer.new()
	qr_bg.add_child(qr_center)
	qr_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	qr_texture = TextureRect.new()
	qr_texture.custom_minimum_size = Vector2(160, 160)
	qr_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr_center.add_child(qr_texture)
	qr_margin.add_child(qr_bg)
	
	code_label = Label.new()
	code_label.text = "Connexion..."
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_color_override("font_color", Color.WHITE) 
	var code_settings = LabelSettings.new()
	code_settings.font_size = 40
	code_settings.font_color = Color(1.0, 0.85, 0.2) # Vibrant yellow/gold
	code_settings.outline_size = 8
	code_settings.outline_color = Color(0.4, 0.2, 0.05)
	code_label.label_settings = code_settings
	inner_vbox.add_child(code_label)
	
	lien_label = Label.new()
	lien_label.text = ""
	lien_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lien_label.add_theme_font_size_override("font_size", 20)
	lien_label.add_theme_color_override("font_color", Color(0.4, 0.2, 0.05))
	inner_vbox.add_child(lien_label)
	
	var sous_titre = Label.new()
	sous_titre.text = "Scannez le QR Code ou entrez l'adresse et le code sur votre navigateur"
	sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous_titre.add_theme_font_size_override("font_size", 16)
	sous_titre.add_theme_color_override("font_color", Color(0.5, 0.35, 0.2))
	inner_vbox.add_child(sous_titre)
	
	joueurs_titre_label = Label.new()
	joueurs_titre_label.text = "0 joueur(s) connecté(s)\n"
	joueurs_titre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joueurs_titre_label.add_theme_font_size_override("font_size", 24)
	joueurs_titre_label.add_theme_color_override("font_color", Color(0.3, 0.6, 0.3)) # Grass green text
	inner_vbox.add_child(joueurs_titre_label)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(650, 80) # Plus compact
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	
	joueurs_flow = HFlowContainer.new()
	joueurs_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	joueurs_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	joueurs_flow.add_theme_constant_override("h_separation", 10)
	joueurs_flow.add_theme_constant_override("v_separation", 10)
	
	scroll.add_child(joueurs_flow)
	inner_vbox.add_child(scroll)
	
	var btn_start = Button.new()
	btn_start.text = "COMMENCER LA PARTIE"
	btn_start.add_theme_font_size_override("font_size", 24)
	
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.3, 0.8, 0.3) # Bright Grass Green
	btn_style.border_width_bottom = 6
	btn_style.border_width_top = 4
	btn_style.border_width_left = 4
	btn_style.border_width_right = 4
	btn_style.border_color = Color(0.15, 0.5, 0.15) # Dark green border
	btn_style.corner_radius_top_left = 12
	btn_style.corner_radius_top_right = 12
	btn_style.corner_radius_bottom_left = 12
	btn_style.corner_radius_bottom_right = 12
	btn_style.shadow_color = Color(0.2, 0.4, 0.6, 0.2)
	btn_style.shadow_size = 0
	btn_style.shadow_offset = Vector2(4, 4)
	btn_style.content_margin_top = 10
	btn_style.content_margin_bottom = 10
	btn_style.content_margin_left = 20
	btn_style.content_margin_right = 20
	
	btn_start.add_theme_stylebox_override("normal", btn_style)
	btn_start.add_theme_color_override("font_color", Color.WHITE)
	
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.4, 0.9, 0.4)
	btn_hover.border_color = Color(0.2, 0.6, 0.2)
	btn_start.add_theme_stylebox_override("hover", btn_hover)
	
	btn_start.pressed.connect(_lancer_restauration)
	btn_start.custom_minimum_size = Vector2(300, 0)
	
	var btn_container = CenterContainer.new()
	var margin_btn = MarginContainer.new()
	margin_btn.add_theme_constant_override("margin_top", 5)
	margin_btn.add_child(btn_start)
	btn_container.add_child(margin_btn)
	inner_vbox.add_child(btn_container)
	
	# Initialiser HTTPRequest pour télécharger le QR Code
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_sur_qr_telecharge)

	# Écoute des signaux du Websocket principal
	WebSocketServer.code_salle_recu.connect(_sur_code_salle_recu)
	WebSocketServer.joueur_rejoint.connect(_sur_joueur_rejoint)
	WebSocketServer.joueur_quitte.connect(_sur_joueur_quitte)
	
	# Si le Websocket s'était déjà connecté (hyper rapide), on interroge le code directement !
	if WebSocketServer.code_salle_actuel != "":
		_sur_code_salle_recu(WebSocketServer.code_salle_actuel)
		
	# HOT-START : Si on trouve une sauvegarde du plateau, on zappe le lobby !
	if OS.has_feature("web"):
		var save_str = JavaScriptBridge.eval("window.sessionStorage.getItem('dookeyGameState');")
		if save_str and save_str != "":
			print("[lobby.gd] Sauvegarde trouvée ! Reprise à chaud de la partie...")
			call_deferred("_lancer_restauration")

func _lancer_restauration() -> void:
	WebSocketServer.assigner_equipes(liste_joueurs)
	# Envoyer les équipes au serveur pour le filtrage côté serveur
	var parts = []
	for pseudo in WebSocketServer.equipes:
		parts.append("%s=%d" % [pseudo.uri_encode(), WebSocketServer.equipes[pseudo]])
	if parts.size() > 0:
		WebSocketServer.envoyer_message("EQUIPES:" + ",".join(parts))
	get_tree().change_scene_to_file("res://Scenes/game.tscn")

func _sur_code_salle_recu(code: String) -> void:
	code_label.text = code
	
	var base_url = "https://dookey-h1if.onrender.com"
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var protocol = JavaScriptBridge.eval("window.location.protocol")
		if host and protocol:
			base_url = protocol + "//" + host
			
	lien_label.text = "Adresse : " + base_url + "/controller"
			
	var url_cible = base_url + "/controller?code=" + code
	var url_api = "https://api.qrserver.com/v1/create-qr-code/?size=160x160&data=" + url_cible.uri_encode()
	http_request.request(url_api)

func _sur_qr_telecharge(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		if err == OK:
			qr_texture.texture = ImageTexture.create_from_image(image)

func _sur_joueur_rejoint(pseudo: String) -> void:
	if pseudo in liste_joueurs:
		return
		
	liste_joueurs.append(pseudo)
	joueurs_titre_label.text = "%d joueur(s) connecté(s)\n" % liste_joueurs.size()
	
	var pan = PanelContainer.new()
	pan.name = "Joueur_" + pseudo.validate_node_name()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.96, 0.92, 0.76) # Sand color
	style.border_width_bottom = 4
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.55, 0.35, 0.15) # Brown dirt border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.set_content_margin_all(12)
	pan.add_theme_stylebox_override("panel", style)
	
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	pan.add_child(vb)
	
	var lbl = Label.new()
	lbl.text = pseudo
	lbl.add_theme_color_override("font_color", Color.WHITE)
	var lbl_set = LabelSettings.new()
	lbl_set.font_size = 22
	lbl_set.outline_size = 6
	lbl_set.outline_color = Color(0.4, 0.2, 0.05)
	lbl.label_settings = lbl_set
	vb.add_child(lbl)
	
	# Badge équipe (affiché si équipes déjà assignées)
	var badge = Label.new()
	badge.name = "Badge"
	badge.text = "En attente..."
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var badge_set = LabelSettings.new()
	badge_set.font_size = 14
	badge_set.font_color = Color(0.5, 0.35, 0.2)
	badge.label_settings = badge_set
	vb.add_child(badge)
	
	joueurs_flow.add_child(pan)

func _sur_joueur_quitte(pseudo: String) -> void:
	if pseudo in liste_joueurs:
		liste_joueurs.erase(pseudo)
		joueurs_titre_label.text = "%d joueur(s) connecté(s)\n" % liste_joueurs.size()
		
	var safe_name = "Joueur_" + pseudo.validate_node_name()
	var node = joueurs_flow.get_node_or_null(safe_name)
	if node:
		node.queue_free()
		joueurs_flow.remove_child(node)

# ─── Animation fond ping-pong ───────────────────────────────────────────────
func _charger_frame(idx: int) -> void:
	var path = "res://Assets/pixil-frame-%d.png" % idx
	var tex = load(path)
	if tex:
		bg_anim.texture = tex
	else:
		# Frame manquante : fond de secours bleu ciel
		var fallback = ColorRect.new()
		fallback.color = Color(0.55, 0.82, 0.95)
		print("[lobby.gd] Frame manquante : ", path)

func _avancer_frame_anim() -> void:
	anim_frame += anim_dir
	# Rebond : on inverse la direction aux extrémités
	if anim_frame >= NB_FRAMES - 1:
		anim_frame = NB_FRAMES - 1
		anim_dir = -1
	elif anim_frame <= 0:
		anim_frame = 0
		anim_dir = 1
	_charger_frame(anim_frame)
