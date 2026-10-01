# Ecto Remote

A native macOS GUI client for remote support sessions. It opens a **reverse SSH
tunnel** to your relay host, starts a **listener** on the tunneled port, and
shows the inbound data stream live while logging each connection to its own file.
Styled as a neon cyberpunk console.

> Built to drive this workflow:
> 1. `ssh -N -R PORT:localhost:PORT debug@176.53.160.131`
> 2. `ncat -lvkp PORT`
> 3. read + log the incoming stream.

## Download a ready-to-run build

Grab the latest `EctoRemote-macOS-*.zip` (or `.dmg`) from the
[**Releases**](../../releases) page. Each push to the build branch produces a new
release automatically via GitHub Actions on a macOS runner.

First launch is Gatekeeper-gated because the app is ad-hoc signed (not notarized):
right-click the app → **Open**, or run
`xattr -dr com.apple.quarantine "/Applications/Ecto Remote.app"`.

## How it works

| Stage | What the app does |
|-------|-------------------|
| 1. Tunnel | Spawns `ssh -N -R PORT:localhost:PORT <user>@<host>` as a hidden background process and feeds it the saved password through an `SSH_ASKPASS` helper (no PTY, no password on disk). |
| 2. Listener | Once the tunnel is confirmed, runs `ncat -lvkp PORT` (configurable). |
| 3. Capture | Reads the listener's stream, renders it live in the console, and writes a per-connection log file under Application Support. |

### Where logs go

```
~/Library/Application Support/EctoRemote/logs/
    session_<port>_<timestamp>/
        session.log                         # full human-readable transcript
        connection_001_<peer>_<ts>.log      # raw payload, one file per connection
```

The **Open Logs Folder** button reveals this directory in Finder, and each
connection row has a button to reveal its own file.

## Configuration

Open **Settings** (⌘,) to change:
- SSH user and relay host (default `debug@176.53.160.131`)
- Extra SSH arguments
- The listener command template, where `{PORT}` is substituted
  (default `ncat -lvkp {PORT}`; `ncat` comes from `brew install nmap`)
- Whether the listener auto-starts when the tunnel comes up

The relay password is stored in the **macOS Keychain**, keyed per `user@host`.

## Requirements

- macOS 13 (Ventura) or newer, Intel or Apple Silicon (universal binary)
- `ssh` (built into macOS)
- `ncat` for the listener (`brew install nmap`) or any substitute you configure

## Building locally

```
swift build -c release
./packaging/build_app.sh 1.0.0 1
```

This produces `EctoRemote.app` plus a distributable `.zip`/`.dmg`.

## Project layout

```
Package.swift
Sources/EctoRemote/
    EctoRemoteApp.swift        # @main app + AppDelegate
    Core/                      # model, settings, keychain, process + log plumbing
    Views/                     # SwiftUI cyberpunk UI
packaging/                     # Info.plist, icon generator, build script, notes
.github/workflows/release.yml  # macOS CI build + release publishing
```
