## Ecto Remote — macOS

Cyberpunk-styled client for opening a reverse SSH tunnel to a relay, listening
on the tunneled port, and capturing the inbound data stream to per-connection
log files.

### Download
- **EctoRemote-macOS-*.zip** — unzip and drag `Ecto Remote.app` to `/Applications`.
- **EctoRemote-macOS-*.dmg** — open and drag to `Applications`.

### First launch (important)
The app is ad-hoc signed, not notarized, so Gatekeeper will warn on first run.
Do one of the following:

1. **Right-click** `Ecto Remote.app` → **Open** → **Open** in the dialog, or
2. Remove the quarantine flag in Terminal:
   ```
   xattr -dr com.apple.quarantine "/Applications/Ecto Remote.app"
   ```

### Requirements
- macOS 13 (Ventura) or newer, Intel or Apple Silicon.
- `ncat` for the listener step: `brew install nmap`
  (or change the listener command in Settings, e.g. `nc -lk {PORT}`).

### Usage
1. Enter the **port** and the **relay password** (tick *Remember password* to
   store it in the macOS Keychain for next time).
2. Press **Connect**. The app runs, in a hidden background session:
   `ssh -N -R PORT:localhost:PORT debug@<relay>` and supplies the saved password.
3. Once the tunnel is up it starts the listener `ncat -lvkp PORT` automatically.
4. Incoming data is shown live on screen and written to a log file per
   connection. Use **Open Logs Folder** to browse them in Finder.

Relay host/user and the listener command are configurable in **Settings**.
