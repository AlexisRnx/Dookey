const express = require('express');
const { WebSocketServer, WebSocket } = require('ws');
const path = require('path');
const http = require('http');

const app = express();
const port = process.env.PORT || 3000;

// Servir tous les fichiers statiques du dossier public/ (images, etc.)
app.use(express.static(path.join(__dirname, 'public')));

// Serve the controller under the URL "/controller"
app.use('/controller', express.static(path.join(__dirname, 'public/controller')));
app.get('/controller', (req, res) => {
    res.sendFile(path.join(__dirname, 'public/controller/index.html'));
});

// Serve the Godot exported game under the URL "/display"
app.use('/display', express.static(path.join(__dirname, 'godot')));
app.get('/display', (req, res) => {
    res.sendFile(path.join(__dirname, 'godot', 'Dookey Ascension.html'));
});

// Explicit redirect rule for QR codes to guarantee query param survival across all mobile OS 
app.get('/play', (req, res) => {
    const code = req.query.code || '';
    res.redirect(`/controller/?code=${code}`);
});

// Add a default route helping the user redirect to the right place
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Create HTTP server to attach WebSocket server
const server = http.createServer(app);

// Initialize WebSocket server
const wss = new WebSocketServer({ server });

function generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for(let i=0; i<8; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
}

// Map of rooms: roomCode -> { gameWs: WebSocket, controllers: Set<WebSocket> }
const rooms = new Map();

wss.on('connection', (ws, req) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    let clientType = url.searchParams.get('clientType');
    
    // Support URL pathways as fallback for tight game engines
    if (url.pathname === '/game') clientType = 'game';
    if (url.pathname === '/controller') clientType = 'controller';

    if (clientType === 'game') {
        const requestedCode = url.searchParams.get('roomCode');
        const upperReq = requestedCode ? requestedCode.toUpperCase() : null;
        
        let roomCode;
        if (upperReq && rooms.has(upperReq)) {
            // Reconnexion du Godot (Suite à un F5)
            roomCode = upperReq;
            const room = rooms.get(roomCode);
            room.gameWs = ws;
            room.isLocked = false; // On deverrouille car Godot retourne au Menu
            console.log(`[Serveur] Le Godot s'est reconnecté à sa salle : ${roomCode}`);
            ws.send(`ROOM_CREATED:${roomCode}`);
            
            // Renvoie la liste des joueurs existants
            for (const pseudo of room.pseudos) {
                ws.send(`PLAYER_JOINED:${pseudo}`);
            }
            
        } else {
            // Nouvelle Partie
            roomCode = generateRoomCode();
            while (rooms.has(roomCode)) {
                roomCode = generateRoomCode();
            }
            console.log(`[Serveur] Le jeu Godot est connecté ! Création de la salle : ${roomCode}`);
            rooms.set(roomCode, { 
                gameWs: ws, 
                controllers: new Set(), 
                isLocked: false, 
                pseudos: new Set(), 
                connectedPseudos: new Set(),
                equipes: new Map(),    // pseudo -> teamIdx (0-3)
                currentTeam: -1       // index de l'équipe dont c'est le tour (-1 = lobby)
            });
            ws.send(`ROOM_CREATED:${roomCode}`);
        }

        ws.on('message', (message, isBinary) => {
            const msgStr = isBinary ? message.toString('utf8') : message.toString();
            
            if (msgStr.trim() === "LOCK_ROOM") {
                const room = rooms.get(roomCode);
                if (room) {
                    room.isLocked = true;
                    console.log(`[Serveur] Salle ${roomCode} verrouillée. Nouveaux joueurs rejetés.`);
                }
                return;
            }
            
            // Messages du jeu Godot vers les controllers
            const room = rooms.get(roomCode);
            if (room) {
                // Stocker les équipes si Godot nous les envoie
                if (msgStr.startsWith('EQUIPES:')) {
                    const payload = msgStr.substring(8);
                    room.equipes.clear();
                    payload.split(',').forEach(entry => {
                        const [pseudo, idx] = entry.split('=');
                        if (pseudo && idx !== undefined) {
                            room.equipes.set(decodeURIComponent(pseudo.trim()), parseInt(idx.trim()));
                        }
                    });
                    console.log(`[Serveur] Équipes enregistrées pour ${roomCode}:`, Object.fromEntries(room.equipes));
                    
                    // Envoyer à chaque controller son équipe personnelle
                    for (const [ctrlWs, ctrlPseudo] of room.controllerMap || new Map()) {
                        const teamIdx = room.equipes.get(ctrlPseudo);
                        if (ctrlWs.readyState === WebSocket.OPEN && teamIdx !== undefined) {
                            ctrlWs.send(`VOTRE_EQUIPE:${teamIdx}`);
                        }
                    }
                    return; // Ne pas broadcaster aux controllers
                }

                // Détecter le tour actuel depuis NOUVEAU_TOUR:teamIdx:nomEquipe
                if (msgStr.startsWith('NOUVEAU_TOUR:')) {
                    const parts = msgStr.split(':');
                    room.currentTeam = parseInt(parts[1]);
                    console.log(`[Serveur] ${roomCode} - Nouveau tour, équipe index: ${room.currentTeam}`);
                }

                // Broadcaster aux controllers (NOUVEAU_TOUR, TEMPS_ECOULE, etc.)
                for (const [ctrlWs, ctrlPseudo] of room.controllerMap || new Map()) {
                    if (ctrlWs.readyState === WebSocket.OPEN) {
                        ctrlWs.send(msgStr);
                        // Envoyer un indicateur si c'est le tour du joueur
                        if (msgStr.startsWith('NOUVEAU_TOUR:') && room.equipes.size > 0) {
                            const myTeam = room.equipes.get(ctrlPseudo);
                            const isMyTurn = (myTeam !== undefined && myTeam === room.currentTeam);
                            ctrlWs.send(isMyTurn ? 'MON_TOUR' : 'PAS_MON_TOUR');
                        }
                    }
                }
            }
        });

        ws.on('close', () => {
            console.log(`[Serveur] La salle ${roomCode} (Jeu Godot) s'est déconnectée.`);
            if (rooms.has(roomCode)) {
                const room = rooms.get(roomCode);
                // Fermer toutes les connexions controllers pour éviter les zombies
                for (const ctrlWs of room.controllers) {
                    if (ctrlWs.readyState === WebSocket.OPEN) {
                        ctrlWs.send('JEU_DECONNECTE');
                        ctrlWs.close();
                    }
                }
            }
            rooms.delete(roomCode);
        });

    } else if (clientType === 'controller') {
        const roomCode = url.searchParams.get('roomCode');
        const pseudo = url.searchParams.get('pseudo') || "Joueur Inconnu";

        if (!roomCode || !rooms.has(roomCode.toUpperCase())) {
            console.log(`[Serveur] Rejet : Un contrôleur a tenté de rejoindre la salle inexistante : ${roomCode}`);
            if(ws.readyState === WebSocket.OPEN) {
                ws.send("ERROR:ROOM_NOT_FOUND");
                ws.close();
            }
            return;
        }

        const upperCode = roomCode.toUpperCase();
        const room = rooms.get(upperCode);
        
        // Empêcher d'avoir 2 fois le même pseudo EN MÊME TEMPS
        if (room.connectedPseudos.has(pseudo)) {
            console.log(`[Serveur] Rejet : Le pseudo ${pseudo} est déjà connecté dans ${upperCode}`);
            if (ws.readyState === WebSocket.OPEN) {
                ws.send("ERROR:PSEUDO_TAKEN");
                ws.close();
            }
            return;
        }
        
        if (room.isLocked && !room.pseudos.has(pseudo)) {
            console.log(`[Serveur] Rejet : Tentative de rejoindre la salle verrouillée ${upperCode}`);
            if (ws.readyState === WebSocket.OPEN) {
                ws.send("ERROR:ROOM_LOCKED");
                ws.close();
            }
            return;
        }

        room.pseudos.add(pseudo);
        room.connectedPseudos.add(pseudo);
        console.log(`[Serveur] Le joueur ${pseudo} a rejoint la salle ${upperCode}`);
        room.controllers.add(ws);
        
        // Stocker le pseudo associé à ce WebSocket pour le filtrage par équipe
        if (!room.controllerMap) room.controllerMap = new Map();
        room.controllerMap.set(ws, pseudo);
        
        // Notify the Game that a player joined
        if (room.gameWs.readyState === WebSocket.OPEN) {
            room.gameWs.send(`PLAYER_JOINED:${pseudo}`);
        }
        
        // Tell the controller they joined successfully
        ws.send("JOIN_SUCCESS");

        ws.on('message', (message, isBinary) => {
            const msgStr = isBinary ? message.toString('utf8') : message.toString();
            
            // Filtrage par équipe : seuls les joueurs de l'équipe active peuvent voter
            const isVote = msgStr.startsWith('CLIC:') || msgStr.startsWith('VOTES:') || msgStr === 'LANCER' || msgStr.startsWith('BOSS_VOTE:');
            if (isVote && room.equipes.size > 0 && room.currentTeam >= 0) {
                const myTeam = room.equipes.get(pseudo);
                if (myTeam === undefined || myTeam !== room.currentTeam) {
                    console.log(`[Serveur] Vote BLOQUÉ de ${pseudo} (équipe ${myTeam}) - Tour de l'équipe ${room.currentTeam}`);
                    ws.send('PAS_MON_TOUR');
                    return;
                }
            }
            
            // Forward controller messages only to the Godot game client in this room
            if (room.gameWs && room.gameWs.readyState === WebSocket.OPEN) {
                let finalMsg = msgStr;
                if (msgStr.startsWith('BOSS_VOTE:')) {
                    finalMsg += ":" + pseudo;
                }
                room.gameWs.send(finalMsg);
            } else {
                console.log(`[Serveur] Message reçu dans ${upperCode} mais le jeu n'est plus connecté.`);
            }
        });

        ws.on('close', () => {
            console.log(`[Serveur] Le joueur ${pseudo} s'est déconnecté de la salle ${upperCode}.`);
            if (rooms.has(upperCode)) {
                const r = rooms.get(upperCode);
                r.controllers.delete(ws);
                r.connectedPseudos.delete(pseudo);
                if (r.controllerMap) r.controllerMap.delete(ws);
                
                if (!r.isLocked) {
                    r.pseudos.delete(pseudo);
                    if (r.gameWs && r.gameWs.readyState === WebSocket.OPEN) {
                        r.gameWs.send(`PLAYER_LEFT:${pseudo}`);
                    }
                }
            }
        });
    }
});

server.listen(port, () => {
    console.log(`[Serveur] Démarré sur le port ${port}`);
});
