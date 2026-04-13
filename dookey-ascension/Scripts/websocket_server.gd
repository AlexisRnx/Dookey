extends Node

## WebSocket server qui écoute les messages du site Web Controller
## Port : 8080
## Messages attendus :
##   "VOTES:1=3,2=5,4=2"  → remplace les votes dans la roue
##   "CLIC:5"             → remplace les votes par ce seul chiffre puis lance la roue
##   "LANCER"             → lance la roue

signal votes_recus(votes: Dictionary)
signal lancer_roue_web()
signal joueur_rejoint(pseudo: String)
signal code_salle_recu(code: String)

var _ws := WebSocketPeer.new()
var est_connecte := false
# On pointe par défaut sur le serveur Render pour faciliter les tests depuis l'éditeur
var URL := "wss://dookey-h1if.onrender.com/game"
var etat_courant : String = "LOBBY_ATTENTE"
var code_salle_actuel : String = ""

func _ready() -> void:
	if OS.has_feature("web"):
		var host = JavaScriptBridge.eval("window.location.host")
		var protocol = JavaScriptBridge.eval("window.location.protocol == 'https:' ? 'wss:' : 'ws:'")
		if host and protocol:
			URL = "%s//%s/game" % [protocol, host]
			
	var err := _ws.connect_to_url(URL)
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
			if est_connecte:
				print("[WS Client] Connexion perdue.")
				est_connecte = false

func _traiter_message(message: String) -> void:
	if message.begins_with("ROOM_CREATED:"):
		var code = message.substr(13).strip_edges()
		code_salle_actuel = code
		code_salle_recu.emit(code)
		
	elif message.begins_with("PLAYER_JOINED:"):
		var pseudo = message.substr(14).strip_edges()
		joueur_rejoint.emit(pseudo)

	# ── Format VOTES:1=3,2=5,6=1 ──────────────────────────────────────────
	elif message.begins_with("VOTES:"):
		var partie := message.substr(6)  # Tout après "VOTES:"
		var votes  := {}
		for entry in partie.split(","):
			var kv := entry.split("=")
			if kv.size() == 2:
				var chiffre := kv[0].strip_edges().to_int()
				var nb_votes := kv[1].strip_edges().to_int()
				if chiffre >= 1 and chiffre <= 6 and nb_votes > 0:
					votes[chiffre] = nb_votes
		if votes.size() > 0:
			votes_recus.emit(votes)

	# ── Format CLIC:3 (le joueur a cliqué sur son chiffre obtenu) ──────────
	elif message.begins_with("CLIC:"):
		var chiffre := message.substr(5).strip_edges().to_int()
		if chiffre >= 1 and chiffre <= 6:
			# On crée un vote unique pour ce chiffre qui remplacera tout (100% de la roue)
			var votes := { chiffre: 1 }
			votes_recus.emit(votes)
			lancer_roue_web.emit()

	# ── Format LANCER (déclenche juste la roue) ───────────────────────────
	elif message == "LANCER":
		lancer_roue_web.emit()

# ── Envoie d'un message vers le serveur Node (qui relayera à tous les téléphones)
func envoyer_message(msg: String) -> void:
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(msg)
