# macOS app — `claimward-vpn-app-osx`

A menu-bar (tray) app written in Go whose **entire user interface is a Svelte
single-page app rendered in a webview**.

## Design

```text
 claimward-app (tray process)
 ├─ systray            menu: status / Connect / Disconnect / Open / Quit
 ├─ uiserver           loopback HTTP: embedded Svelte SPA + token-guarded JSON API
 └─ appcore            OIDC login, enroll, drive the helper
        │ spawns "ui" subprocess          │ Unix socket (JSON)
        ▼                                 ▼
   webview (WKWebView)              claimward-helper (root LaunchDaemon)
   renders the Svelte UI            wireguard-go: utun up/down
```

The tray process owns all state and serves both the UI and a small JSON API on
`127.0.0.1`. The webview is a thin window pointed at that loopback URL. Tunnel
setup needs root, so it lives in a separate **privileged helper**; the UI app is
unprivileged.

## Build

```sh
cd frontend && npm install && npm run build && cd ..   # build the Svelte UI
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=1 go build -o bin/claimward-helper  ./cmd/claimward-helper
```

## Configure

`~/Library/Application Support/Claimward/config.json`:

```json
{
  "server_url": "https://vpn.example.com",
  "oidc_issuer": "https://your-issuer.example.com",
  "oidc_client_id": "claimward"
}
```

## Install the helper and run

```sh
sudo ./scripts/install-helper.sh   # installs the root LaunchDaemon
./bin/claimward-app                # tray app → click Connect
```

!!! note "Hardening before shipping"
    The MVP helper socket is `0666`; tighten to a dedicated group + `0660` with
    peer-credential checks, move session tokens to the Keychain, and ship a
    signed, notarized `.app`.
