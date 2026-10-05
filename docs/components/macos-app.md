# macOS app — `claimward-vpn-app-osx`

A menu-bar (tray) app written in Go whose **entire user interface is a Svelte
single-page app rendered in a webview**.

## Design

```text
 claimward-app (tray process)
 ├─ systray            menu: status / Connect / Disconnect / Open / Quit
 ├─ uiserver           loopback HTTP: embedded Svelte SPA + token-guarded JSON API
 └─ appcore            sign-in, tenant choice, drive the helper (claimward-vpn-client)
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
CGO_ENABLED=0 go build -o bin/claimward-helper  ./cmd/claimward-helper
```

## Configure

`~/Library/Application Support/Claimward/config.json` (GitHub is the default):

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "github",
  "github_client_id": "Iv1.0123456789abcdef"
}
```

The app uses the GitHub **device flow**: clicking **Connect** shows a code to
enter at the displayed URL. For OIDC, set `"provider": "oidc"` with
`"oidc_issuer"` / `"oidc_client_id"`; for go-authn, `"provider": "go-authn"`
with the same two fields.

## Install the helper and run

```sh
sudo ./scripts/install-helper.sh https://vpn.example.com   # installs the root LaunchDaemon
./bin/claimward-app                                        # tray app → click Connect
```

The installer writes `/Library/Application Support/Claimward/helper.json`
(root's, writable by root alone) with the servers the helper may connect to.
The helper runs as root, so anything that can reach its socket could otherwise
point it at a server of its own, answering with routes for every packet of the
machine. It takes no tunnel configuration from a request, and its socket is
`0660`, `root:admin`.

## Tenants

A person may belong to several tenants: the server matches them on email
domain, groups and institution. The window offers the tenants when the server
says there is a choice, or on request, and the choice holds for the session.
A **Connect** from the menu bar that needs a choice opens the window.

!!! note "Still to come"
    The session token in the Keychain, and a signed, notarized `.app`.
