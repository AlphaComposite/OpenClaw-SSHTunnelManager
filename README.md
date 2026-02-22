# OpenClaw SSH Tunnel Manager

A lightweight macOS menu bar app for managing persistent SSH tunnel connections. Originally built to keep [OpenClaw](https://github.com/openclaw/openclaw) accessible on a remote server — if you're running OpenClaw on a VPS, its web dashboard lives at `127.0.0.1:18789` on the remote host, and you need an SSH tunnel to reach it from your local machine. This app keeps that tunnel alive so you can always access it at `localhost:18789` in your browser.

The problem it solves: running `ssh -N -L 18789:127.0.0.1:18789 root@your-server` in a terminal works, but the connection drops when your network resets, your Mac sleeps, or the server restarts. Then you have to notice it's down, switch to the terminal, and re-run the command. SSH Tunnel Manager sits in your menu bar, monitors the connection, and automatically reconnects when it drops — so your tunnels stay up without you thinking about it.

While it was designed with OpenClaw in mind, it works for any SSH tunnel use case: database access, remote dev servers, internal web tools, etc. You can configure multiple tunnels and manage them all from one place.

## Features

- **Menu bar status indicator** — colored circle with connection count (e.g., `🟢 2/3`) shows how many tunnels are connected at a glance. Green if any are connected, yellow while connecting, red if none are up.
- **Clipboard import** — copy an SSH command like `ssh -N -L 18789:127.0.0.1:18789 root@server` to your clipboard, then click **+**. The form auto-fills from the command. Supports multiple `-L` flags in one command for bulk import.
- **Auto-reconnect** — detects dropped connections and retries with exponential backoff (1s, 2s, 4s... up to 30s max)
- **Multiple tunnels** — add, edit, and remove tunnel configurations through a UI
- **Live activity log** — timestamped connection events per tunnel for debugging
- **Manual controls** — connect, disconnect, and reconnect buttons
- **SSH keepalive** — configurable `ServerAliveInterval` catches dead connections faster
- **No dock icon** — lives entirely in the menu bar, out of your way

## Building from Source

### Prerequisites

- macOS 13.0 or later
- Xcode 14 or later (install from the App Store)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (generates the Xcode project from `project.yml`)

### Step 1: Clone the repository

```bash
git clone https://github.com/AlphaComposite/SSHTunnelManager.git
cd SSHTunnelManager
```

### Step 2: Install XcodeGen

The `.xcodeproj` is not checked in — it's generated from `project.yml`. Install XcodeGen via Homebrew:

```bash
brew install xcodegen
```

### Step 3: Generate the Xcode project

```bash
xcodegen generate
```

This creates `SSHTunnelManager.xcodeproj` in the current directory.

### Step 4: Build and run

**Option A — Xcode (recommended for first run):**

```bash
open SSHTunnelManager.xcodeproj
```

Then press **⌘R** to build and run. A small colored circle will appear in your menu bar.

**Option B — Command line:**

```bash
xcodebuild -project SSHTunnelManager.xcodeproj -scheme SSHTunnelManager -configuration Release build
```

The built app will be at:

```
~/Library/Developer/Xcode/DerivedData/SSHTunnelManager-*/Build/Products/Release/SSHTunnelManager.app
```

Copy it to `/Applications` to keep it permanently, or run it directly from DerivedData.

## Setting Up Your First Tunnel

### Quick way — paste from clipboard

If you already have an SSH tunnel command, just copy it:

```bash
ssh -N -L 18789:127.0.0.1:18789 root@your.server.ip
```

Then click **+** in the app. The form will auto-fill from your clipboard. If the command has multiple `-L` flags, all tunnels are imported at once.

### Manual setup

1. Click the status indicator in the menu bar to open the dashboard
2. Click the **+** button to add a new tunnel
3. Fill in the connection details:
   - **Name**: A label for the tunnel (e.g., "OpenClaw")
   - **User**: Your SSH username (e.g., `root`)
   - **Host**: Your server's IP or hostname (e.g., `your.server.ip`)
   - **Local Port**: The port to forward on your machine (e.g., `18789`)
   - **Remote Host**: Usually `127.0.0.1` (the server's localhost)
   - **Remote Port**: The port the service is running on remotely (e.g., `18789`)
4. Click **Save**
5. Hit the **play button** to connect

Once connected, you can access the remote service at `http://localhost:<local-port>` in your browser.

## SSH Key Authentication

This app uses `BatchMode=yes`, meaning it will **not** prompt for passwords — it relies on SSH key authentication. Make sure your key is set up before connecting:

```bash
ssh-copy-id root@your-server-ip
```

Alternatively, specify a key path in the tunnel configuration (e.g., `~/.ssh/id_rsa`).

## How It Works

The app spawns `/usr/bin/ssh` as a child process with `-N -L` flags (no remote command, local port forwarding). It monitors the process and uses `ServerAliveInterval` / `ServerAliveCountMax` to detect dead connections at the SSH level. If the process exits unexpectedly and auto-reconnect is enabled, it retries with exponential backoff.

## License

MIT
