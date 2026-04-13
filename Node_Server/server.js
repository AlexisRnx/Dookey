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
    for(let i=0; i<4; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return code;
}

// Map of rooms: roomCode -> { gameWs: WebSocket, controllers: Set<WebSocket> }
const rooms = new Map();

wss.on('connection', (ws, req) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const clientType = url.searchParams.get('clientType');

    if (clientType === 'game') {
        let roomCode = generateRoomCode();
        while (rooms.has(roomCode)) {
            roomCode = generateRoomCode();
        }

        console.log(`[Serveur] Le jeu Godot est connecté ! Création de la salle : ${roomCode}`);
        rooms.set(roomCode, { gameWs: ws, controllers: new Set() });
        
        // Notify Godot of its new room code
        ws.send(`ROOM_CREATED:${roomCode}`);

        ws.on('message', (message, isBinary) => {
            const msgStr = isBinary ? message.toString('utf8') : message.toString();
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
        console.log(`[Serveur] Le joueur ${pseudo} a rejoint la salle ${upperCode}`);
        const room = rooms.get(upperCode);
        
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
                rooms.get(upperCode).controllers.delete(ws);
            }
        });
    }
});

server.listen(port, () => {
    console.log(`[Serveur] Démarré sur le port ${port}`);
});
