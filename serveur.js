const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

// On sert les fichiers du dossier "public"
app.use(express.static(path.join(__dirname, 'public')));

const server = http.createServer(app);

// On attache WebSocket au serveur HTTP
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
    console.log('Nouvelle connexion établie !');

    ws.on('message', (data) => {
        // Conversion du buffer en texte
        const message = data.toString();
        console.log("Score reçu :", message);

        // Envoi à TOUS les clients (Site + Godot)
        wss.clients.forEach((client) => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(message);
            }
        });
    });

    ws.on('error', (err) => console.error("Erreur WS:", err));
});

server.listen(port, '0.0.0.0', () => {
    console.log(`Serveur actif sur le port ${port}`);
});