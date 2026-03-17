const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const path = require('path');

const app = express();
const port = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, 'public')));

const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws) => {
    console.log('Un client s’est connecté');

    ws.on('message', (data) => {
        // On reçoit le score du site
        const message = data.toString();
        console.log("Score reçu du site :", message);

        // On renvoie le score à TOUS les clients connectés (dont Godot)
        wss.clients.forEach((client) => {
            if (client.readyState === WebSocket.OPEN) {
                client.send(message);
            }
        });
    });
});

server.listen(port, () => {
    console.log(`Serveur prêt sur le port ${port}`);
});