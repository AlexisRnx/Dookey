extends Control

var qr_texture   : TextureRect
var http_request : HTTPRequest
var code_label   : Label
var lien_label   : Label
var joueurs_titre_label: Label
var joueurs_flow : HFlowContainer
var liste_joueurs: Array[String] = []

func _ready() -> void:
	# Création de l'interface graphique dynamique
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	bg.add_child(vbox)
	
	var titre = Label.new()
	titre.text = "SALLE D'ATTENTE"
	titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	titre.add_theme_font_size_override("font_size", 36)
	vbox.add_child(titre)
	
	qr_texture = TextureRect.new()
	qr_texture.custom_minimum_size = Vector2(220, 220)
	qr_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	qr_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(qr_texture)
	
	code_label = Label.new()
	code_label.text = "Connexion au serveur..."
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_label.add_theme_font_size_override("font_size", 48)
	code_label.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
	vbox.add_child(code_label)
	
	lien_label = Label.new()
	lien_label.text = ""
	lien_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lien_label.add_theme_font_size_override("font_size", 22)
	lien_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	vbox.add_child(lien_label)
	
	var sous_titre = Label.new()
	sous_titre.text = "Scannez le QR Code ou entrez l'adresse et le code sur votre navigateur"
	sous_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sous_titre.add_theme_font_size_override("font_size", 18)
	vbox.add_child(sous_titre)
	
	joueurs_titre_label = Label.new()
	joueurs_titre_label.text = "0 joueur(s) connecté(s)\n"
	joueurs_titre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	joueurs_titre_label.add_theme_font_size_override("font_size", 24)
	joueurs_titre_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	vbox.add_child(joueurs_titre_label)
	
	joueurs_flow = HFlowContainer.new()
	joueurs_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	joueurs_flow.custom_minimum_size = Vector2(600, 0)
	joueurs_flow.add_theme_constant_override("h_separation", 15)
	joueurs_flow.add_theme_constant_override("v_separation", 15)
	vbox.add_child(joueurs_flow)
	
	var start_label = Label.new()
	start_label.text = "\n[Appuyez sur ESPACE pour lancer le plateau]"
	start_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(start_label)
	
	# Initialiser HTTPRequest pour télécharger le QR Code
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_sur_qr_telecharge)

	# Écoute des signaux du Websocket principal
	WebSocketServer.code_salle_recu.connect(_sur_code_salle_recu)
	WebSocketServer.joueur_rejoint.connect(_sur_joueur_rejoint)
	
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
	get_tree().change_scene_to_file("res://Scenes/game.tscn")

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		# Destruction du lobby et lancement du vrai jeu
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
	var url_api = "https://api.qrserver.com/v1/create-qr-code/?size=220x220&data=" + url_cible.uri_encode()
	http_request.request(url_api)

func _sur_qr_telecharge(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var image = Image.new()
		var err = image.load_png_from_buffer(body)
		if err == OK:
			qr_texture.texture = ImageTexture.create_from_image(image)

func _sur_joueur_rejoint(pseudo: String) -> void:
	liste_joueurs.append(pseudo)
	joueurs_titre_label.text = "%d joueur(s) connecté(s)\n" % liste_joueurs.size()
	
	var pan = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.3, 0.5, 0.8)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.set_content_margin_all(10)
	pan.add_theme_stylebox_override("panel", style)
	
	var lbl = Label.new()
	lbl.text = pseudo
	lbl.add_theme_font_size_override("font_size", 20)
	pan.add_child(lbl)
	
	joueurs_flow.add_child(pan)
