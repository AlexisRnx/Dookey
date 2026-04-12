extends Node

## WebSocket server qui écoute les messages du site Web Controller
## Port : 8080
## Messages attendus :
##   "VOTES:1=3,2=5,4=2"  → remplace les votes dans la roue
##   "CLIC:5"             → remplace les votes par ce seul chiffre puis lance la roue
##   "LANCER"             → lance la roue

signal votes_recus(votes: Dictionary)
signal lancer_roue_web()

var _tcp_server := TCPServer.new()
var _peers : Array[WebSocketPeer] = []
var etat_courant : String = ""

func _ready() -> void:
	var err := _tcp_server.listen(8080)
	if err != OK:
		push_error("[WS Server] Impossible de démarrer sur le port 8080 : erreur %d" % err)
		return
	print("[WS Server] En écoute sur ws://localhost:8080")

func _process(_delta: float) -> void:
	if _tcp_server.is_connection_available():
		var tcp_conn := _tcp_server.take_connection()
		var ws_peer := WebSocketPeer.new()
		var err := ws_peer.accept_stream(tcp_conn)
		if err == OK:
			_peers.append(ws_peer)
			print("[WS Server] Nouvelle connexion acceptée")
			if etat_courant != "":
				ws_peer.send_text(etat_courant)

	for i in range(_peers.size() - 1, -1, -1):
		var ws := _peers[i]
		ws.poll()
		var state := ws.get_ready_state()
		
		match state:
			WebSocketPeer.STATE_OPEN:
				while ws.get_available_packet_count() > 0:
					var paquet := ws.get_packet()
					var message := paquet.get_string_from_utf8().strip_edges()
					print("[WS Server] Message reçu : ", message)
					_traiter_message(message)
			WebSocketPeer.STATE_CLOSED:
				print("[WS Server] Connexion fermée")
				_peers.remove_at(i)

func _traiter_message(message: String) -> void:
	# ── Format VOTES:1=3,2=5,6=1 ──────────────────────────────────────────
	if message.begins_with("VOTES:"):
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

# ── Envoie d'un message vers tous les clients Web connectés ───────────
func envoyer_message(msg: String) -> void:
	for i in range(_peers.size() - 1, -1, -1):
		var ws := _peers[i]
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.send_text(msg)

