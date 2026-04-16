extends Node

signal votes_recus(votes: Dictionary, pseudo: String)
signal lancer_roue_web(pseudo: String)
signal joueur_rejoint(pseudo: String)
signal joueur_quitte(pseudo: String)
signal code_salle_recu(code: String)
signal boss_vote_recu(option: int, pseudo: String)
signal majestueux_vote_recu(option: int, pseudo: String)
signal portail_qte_recu(succes: bool, pseudo: String)
var _ws := WebSocketPeer.new()
var est_connecte := false
var URL := "wss://dookey-h1if.onrender.com/?clientType=game"
var etat_courant : String = "LOBBY_ATTENTE"
var code_salle_actuel : String = ""

var equipes : Dictionary = {}

const COULEURS_EQUIPES = [
	Color(0.72, 0.0, 0.0),
	Color(0.25, 0.31, 0.56),
	Color(0.82, 0.93, 0.26),
	Color(0.07, 0.76, 0.22),
]
const NOMS_EQUIPES = ["Équipe Rouge", "Équipe Bleue", "Équipe Lime", "Équipe Verte"]

func assigner_equipes(joueurs: Array) -> void:
	equipes.clear()
	if joueurs.is_empty():
		return
	
	var liste = joueurs.duplicate()
	liste.shuffle()
	
	var nb = liste.size()
	var base = nb / 4
	var reste = nb % 4
	
	var slots : Array[int] = []
	for equipe_idx in range(4):
		for _j in range(base):
			slots.append(equipe_idx)
	
	var equipes_pour_reste = [0, 1, 2, 3]
	equipes_pour_reste.shuffle()
	for i in range(reste):
		slots.append(equipes_pour_reste[i])
	
	slots.shuffle()
	
	for i in range(liste.size()):
		equipes[liste[i]] = slots[i]

func _ready() -> void:
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var protocol = JavaScriptBridge.eval("window.location.protocol == 'https:' ? 'wss:' : 'ws:'")
		var saved_code = JavaScriptBridge.eval("window.sessionStorage.getItem('dookeyGodotCode')")
		if host and protocol:
			if saved_code and saved_code != "":
				URL = "%s//%s/?clientType=game&roomCode=%s" % [protocol, host, saved_code]
			else:
				URL = "%s//%s/?clientType=game" % [protocol, host]
			
	var tls : TLSOptions = null
	if URL.begins_with("wss://"):
		tls = TLSOptions.client_unsafe()
		
	var err := _ws.connect_to_url(URL, tls)
	if err != OK:
		push_error("[WS Client] Impossible de se connecter au Node Serveur URL:", URL)
		return
	print("[WS Client] Tentative de connexion à ", URL)

func _process(_delta: float) -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not est_connecte:
				print("[WS Client] Connecté avec succès au serveur Node !")
				est_connecte = true
				if etat_courant != "":
					_ws.send_text(etat_courant)

			while _ws.get_available_packet_count() > 0:
				var paquet := _ws.get_packet()
				var message := paquet.get_string_from_utf8().strip_edges()
				print("[WS Serveur relayé] Message reçu : ", message)
				_traiter_message(message)
				
		WebSocketPeer.STATE_CLOSED:
			var code = _ws.get_close_code()
			var reason = _ws.get_close_reason()
			if est_connecte:
				print("[WS Client] Déconnecté du serveur. Code:", code, " Raison:", reason)
				est_connecte = false
			else:
				if code != -1 or reason != "":
					print("[WS Client] Échec de la connexion. Code:", code, " Raison: ", reason)

func _traiter_message(message: String) -> void:
	if message.begins_with("ROOM_CREATED:"):
		var code = message.substr(13).strip_edges()
		code_salle_actuel = code
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.sessionStorage.setItem('dookeyGodotCode', '%s')" % code)
		code_salle_recu.emit(code)
		
	elif message.begins_with("PLAYER_JOINED:"):
		var pseudo = message.substr(14).strip_edges()
		joueur_rejoint.emit(pseudo)
		
	elif message.begins_with("PLAYER_LEFT:"):
		var pseudo = message.substr(12).strip_edges()
		joueur_quitte.emit(pseudo)

	elif message.begins_with("VOTES:"):
		var total_partie := message.substr(6)
		var last_colon = total_partie.rfind(":")
		var partie = total_partie
		var pseudo = "Anonyme"
		if last_colon != -1:
			partie = total_partie.substr(0, last_colon)
			pseudo = total_partie.substr(last_colon + 1)
			
		var votes := {}
		for entry in partie.split(","):
			var kv := entry.split("=")
			if kv.size() == 2:
				var chiffre := kv[0].strip_edges().to_int()
				var nb_votes := kv[1].strip_edges().to_int()
				if chiffre >= 1 and chiffre <= 6 and nb_votes > 0:
					votes[chiffre] = nb_votes
		if votes.size() > 0:
			votes_recus.emit(votes, pseudo)

	elif message.begins_with("CLIC:"):
		var total_partie := message.substr(5).strip_edges()
		var last_colon = total_partie.rfind(":")
		var chiffre_str = total_partie
		var pseudo = "Anonyme"
		if last_colon != -1:
			chiffre_str = total_partie.substr(0, last_colon)
			pseudo = total_partie.substr(last_colon + 1)
			
		var chiffre := chiffre_str.to_int()
		if chiffre >= 1 and chiffre <= 6:
			var votes := { chiffre: 1 }
			votes_recus.emit(votes, pseudo)
			lancer_roue_web.emit(pseudo)

	elif message == "LANCER":
		lancer_roue_web.emit("Anonyme")
	
	elif message.begins_with("BOSS_VOTE:"):
		var parts := message.split(":")
		if parts.size() >= 3:
			var option := parts[1].to_int()
			var pseudo := parts[2]
			boss_vote_recu.emit(option, pseudo)

	elif message.begins_with("MAJESTUEUX_VOTE:"):
		var parts := message.split(":")
		if parts.size() >= 3:
			var option := parts[1].to_int()
			var pseudo := parts[2]
			majestueux_vote_recu.emit(option, pseudo)

	elif message.begins_with("PORTAIL_QTE_VOTE:"):
		var parts := message.split(":")
		if parts.size() >= 3:
			var succes := parts[1] == "1"
			var pseudo := parts[2]
			portail_qte_recu.emit(succes, pseudo)

# ── Envoie d'un message vers le serveur Node (qui relayera à tous les téléphones)
func envoyer_message(msg: String) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(msg)

func verrouiller_salle() -> void:
	envoyer_message("LOCK_ROOM")

# Notifie le serveur Node de l'état actuel des équipes (ex: après une élimination)
func notifier_mises_a_jour_equipes() -> void:
	var msg = "EQUIPES:"
	var entries = []
	for pseudo in equipes:
		entries.append("%s=%d" % [pseudo, equipes[pseudo]])
	msg += ",".join(entries)
	envoyer_message(msg)
