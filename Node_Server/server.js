const express = require('express');
const { WebSocketServer, WebSocket } = require('ws');
const path = require('path');
const http = require('http');

const app = express();
const port = process.env.PORT || 3000;

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
            rooms.set(roomCode, { gameWs: ws, controllers: new Set(), isLocked: false, pseudos: new Set(), connectedPseudos: new Set() });
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
            
            // Broadcast game messages to all controllers in this room
            const room = rooms.get(roomCode);
            if (room) {
                for (const controller of room.controllers) {
                    if (controller.readyState === WebSocket.OPEN) {
                        controller.send(msgStr);
                    }
                }
            }
        });

        ws.on('close', () => {
            console.log(`[Serveur] La salle ${roomCode} (Jeu Godot) s'est déconnectée.`);
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
        
        // Notify the Game that a player joined
        if (room.gameWs.readyState === WebSocket.OPEN) {
            room.gameWs.send(`PLAYER_JOINED:${pseudo}`);
        }
        
        // Tell the controller they joined successfully
        ws.send("JOIN_SUCCESS");

        ws.on('message', (message, isBinary) => {
            const msgStr = isBinary ? message.toString('utf8') : message.toString();
            // Forward controller messages only to the Godot game client in this room
            if (room.gameWs && room.gameWs.readyState === WebSocket.OPEN) {
                room.gameWs.send(msgStr);
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
                
                // Si la partie n'a pas encore commencé, on supprime de la liste globale
                // et on prévient Godot pour retirer sa case de l'écran.
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
