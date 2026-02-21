# SSH Tunnel Manager

A lightweight macOS menu bar app for managing SSH tunnel connections. Automatically reconnects dropped tunnels with exponential backoff.

## Features

- **Menu bar status indicator** — green (connected), red (disconnected), yellow (reconnecting), gray (no tunnels)
- **Auto-reconnect** — exponential backoff from 1s to 30s max
- **Multiple tunnels** — add, edit, and remove tunnel configurations
- **Live activity log** — timestamped connection events per tunnel
- **Manual controls** — connect, disconnect, and reconnect buttons
- **SSH keepalive** — configurable `ServerAliveInterval` per tunnel
- **No dock icon** — lives entirely in the menu bar

## Build & Run

```bash
# Generate Xcode project (requires xcodegen)
brew install xcodegen
xcodegen generate --spec project.yml

# Build from command line
xcodebuild -project SSHTunnelManager.xcodeproj -scheme SSHTunnelManager -configuration Release build

# Or open in Xcode
open SSHTunnelManager.xcodeproj
```

The built app will be at:
```
~/Library/Developer/Xcode/DerivedData/SSHTunnelManager-*/Build/Products/Release/SSHTunnelManager.app
```

Copy it to `/Applications` to keep it permanently.

## Adding a Tunnel

1. Click the colored circle in the menu bar
2. Click the **+** button
3. Fill in the SSH connection details:
   - **Name**: A label (e.g., "Dev DB Tunnel")
   - **User / Host**: SSH credentials (e.g., `root` / `your.server.ip`)
   - **Local Port**: The port to forward locally (e.g., `18789`)
   - **Remote Host / Port**: The remote side of the tunnel (e.g., `127.0.0.1:18789`)
4. Click **Save**, then hit the play button to connect

## SSH Key Authentication

This app uses `BatchMode=yes`, which means it won't prompt for passwords. Make sure your SSH key is already set up:

```bash
ssh-copy-id root@your-server-ip
```

Or specify the key path in the tunnel configuration.

## Requirements

- macOS 13.0+
- Xcode 14+ (to build)
- SSH key-based authentication to your servers
