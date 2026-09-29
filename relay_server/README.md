# IskoLinic Relay Server

WebSocket relay server for CRDT sync between clinic desktop app instances. Built with [Shelf](https://pub.dev/packages/shelf) and [shelf_web_socket](https://pub.dev/packages/shelf_web_socket).

## What it does

- **Relays** `sync_push` messages between connected clinic nodes (broadcast)
- **Stores** records in-memory so reconnecting nodes can catch up via `sync_request`
- **Paginates** large sync responses in batches with `sync_ack` acknowledgement
- **Heartbeat** — responds to `ping` with `pong` (clients ping every 3 min to prevent timeout)

> **Note:** Data is stored in-memory only. On server restart, data is lost — but each clinic node holds the full dataset locally and re-pushes on reconnect.

## Endpoints

| Route | Description |
|-------|-------------|
| `GET /` | Health check — returns JSON with status, client count, record counts |
| `GET /ws` | WebSocket upgrade — connect here for CRDT sync |

## Local Development

```bash
# Install dependencies
dart pub get

# Run the server
dart run bin/server.dart

# Server starts on port 8080 (or PORT env variable)
# Health check: http://localhost:8080/
# WebSocket:   ws://localhost:8080/ws
```

## Running with Docker

```bash
docker build . -t iskolinic-relay
docker run -it -p 8080:8080 iskolinic-relay
```

---

## Deploying to Render

### Prerequisites

- A [Render](https://render.com) account (free tier works)
- This project pushed to a **GitHub** or **GitLab** repository

### Step-by-step

1. **Push to GitHub**

   ```bash
   git init
   git add .
   git commit -m "Initial relay server"
   git remote add origin https://github.com/YOUR_USERNAME/iskolinic_relay_server.git
   git push -u origin main
   ```

2. **Create a new Web Service on Render**

   - Go to [dashboard.render.com](https://dashboard.render.com) → **New** → **Web Service**
   - Connect your GitHub repo
   - Configure:

   | Setting | Value |
   |---------|-------|
   | **Name** | `iskolinic-relay` (or any name) |
   | **Region** | Choose closest to your users |
   | **Runtime** | **Docker** |
   | **Instance Type** | **Free** (or Starter for better uptime) |

   - Render auto-detects the `Dockerfile` — no build command needed

3. **Environment Variables**

   Render sets `PORT` automatically — no manual config needed. The server already reads `Platform.environment['PORT']`.

4. **Deploy**

   Click **Create Web Service**. Render will:
   - Build the Docker image
   - Start the server
   - Assign a URL like `https://iskolinic-relay.onrender.com`

5. **Get your WebSocket URL**

   Your WebSocket URL will be:
   ```
   wss://iskolinic-relay.onrender.com/ws
   ```
   Use `wss://` (not `ws://`) because Render provides HTTPS by default.

6. **Connect the clinic desktop app**

   In your clinic desktop app, set the relay URL in `sync_provider.dart`:
   ```dart
   await syncProvider.init(
     patientProvider,
     wsUrl: 'wss://iskolinic-relay.onrender.com/ws',
   );
   ```

### Health Check

Render will ping `GET /` to monitor your service. The server returns:

```json
{
  "status": "ok",
  "server": "iskolinic_relay_server",
  "clients": 2,
  "records": { "patients": 150, "visitations": 430 }
}
```

### Important Notes

> **Free tier**: Render free instances spin down after 15 minutes of inactivity. The first connection after spin-down takes ~30 seconds. The clinic app's auto-reconnect handles this gracefully.

> **Persistence**: The in-memory store is cleared on each restart/redeploy. This is fine — clinic nodes re-sync their full dataset on reconnect.

> **Scaling**: For production with many nodes, consider upgrading to a paid Render plan to avoid spin-downs. The server is stateless otherwise and works well with a single instance.
