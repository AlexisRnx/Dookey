const express = require('express');
const { WebSocketServer, WebSocket } = require('ws');
const path = require('path');
const http = require('http');

const app = express();
const port = process.env.PORT || 3000;

// Serve static files (the controllers and the game)
app.use(express.static(path.join(__dirname, 'public')));

// Create HTTP server to attach WebSocket server
const server = http.createServer(app);

// Initialize WebSocket server
const wss = new WebSocketServer({ server });

let gameClient = null;
const controllers = new Set();

wss.on('connection', (ws, req) => {
    // Parse URL query to identify client type
    const url = new URL(req.url, `http://${req.headers.host}`);
    const clientType = url.searchParams.get('clientType');

    if (clientType === 'game') {
        console.log('[Serveur] Le jeu Godot est connecté !');
        gameClient = ws;

        ws.on('message', (message, isBinary) => {
            // Convert binary buffer to string if needed (ws gives Buffer by default)
            const msgStr = isBinary ? message.toString('utf8') : message.toString();
            // Broadcast game messages to all controllers
            for (const controller of controllers) {
                if (controller.readyState === WebSocket.OPEN) {
                    controller.send(msgStr);
                }
            }
        });

        ws.on('close', () => {
            console.log('[Serveur] Le jeu Godot sest déconnecté.');
            gameClient = null;
        });

    } else {
        console.log('[Serveur] Nouveau téléphone (contrôleur) connecté !');
        controllers.add(ws);

        ws.on('message', (message, isBinary) => {
            const msgStr = isBinary ? message.toString('utf8') : message.toString();
            // Forward controller messages only to the Godot game client
            if (gameClient && gameClient.readyState === WebSocket.OPEN) {
                gameClient.send(msgStr);
            } else {
                console.log('[Serveur] Message reçu mais le jeu nest pas connecté.');
            }
        });

        ws.on('close', () => {
            console.log('[Serveur] Un téléphone (contrôleur) sest déconnecté.');
            controllers.delete(ws);
        });
    }
});

server.listen(port, () => {
    console.log(`[Serveur] Démarré sur le port ${port}`);
});
