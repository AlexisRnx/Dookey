const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, 'public')));

const server = http.createServer(app);

// Configuration robuste pour Render et Godot
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
    const ip = req.socket.remoteAddress;
    console.log(`[SERVEUR] Connexion établie avec : ${ip}`);

    ws.on('message', (data) => {
        const message = data.toString();
        console.log(`[DATA] Message reçu : ${message}`);

        // On renvoie à TOUT LE MONDE (Site + Godot)
        let count = 0;
        wss.clients.forEach((client) => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(message);
                count++;
            }
        });
        console.log(`[DIFFUSION] Envoyé à ${count} clients.`);
    });

    ws.on('close', () => console.log('[SERVEUR] Un client s\'est déconnecté.'));
    ws.on('error', (err) => console.error("[ERREUR WS]:", err));
});

server.listen(port, '0.0.0.0', () => {
    console.log(`Serveur actif sur le port ${port}`);
});