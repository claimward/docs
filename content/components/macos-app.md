---
title: "macOS app"
linkTitle: "macOS app"
weight: 4
description: "claimward-vpn-app-osx: a Go menu-bar app whose window is a Svelte single-page app in a webview, with a root LaunchDaemon helper."
tags: [macos, app, helper, svelte]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.1.0** is a menu-bar (tray) app written in Go whose **whole user interface
is a Svelte single-page app rendered in a webview**. Its logic (sign-in,
tenant choice, connect) and its helper are the shared
[`pkg/appcore` and `pkg/helper`]({{< relref "/components/client.md" >}}).

## Design

```text
 claimward-app (tray process, as you)
 ├─ systray     menu: status / Open Claimward… / Configuration… / Connect / Disconnect / Quit
 ├─ uiserver    loopback HTTP: embedded Svelte SPA + token-guarded JSON API
 └─ appcore     sign-in, tenant choice, session; drives the helper
        │ spawns "claimward-app ui <url>"     │ Unix socket (JSON), 0660 root:admin
        ▼                                     ▼
   webview (WKWebView)                   claimward-helper (root LaunchDaemon)
   renders the Svelte UI                 enrolls with the server, wireguard-go: utunN,
                                         route pushes
```

The tray process owns all state and serves both the UI and a small JSON API on
`127.0.0.1`, guarded by a per-launch token compared in constant time. The
webview is a thin window pointed at that loopback URL, in a separate process
because only one Cocoa run loop can own the main thread. The
[helper]({{< relref "/components/helper.md" >}}) enrolls with the server and
owns the tunnel; the app is unprivileged.

## Build

With [go-task](https://taskfile.dev):

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Run the bundle rather than the bare binary: a bare binary started from a
menu-bar agent cannot bring its window to the front. By hand:

```sh
cd frontend && npm install && npm run build && cd ..   # the Svelte UI, embedded with go:embed
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Configure

`~/Library/Application Support/Claimward/config.json`, also editable from
**Configuration…** (GitHub is the default):

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "github",
  "github_client_id": "Iv1.0123456789abcdef"
}
```

For OIDC set `"provider": "oidc"`, for go-authn `"provider": "go-authn"`, with
`"oidc_issuer"` and `"oidc_client_id"`. With GitHub and go-authn, clicking
**Connect** shows a code to enter at the displayed page; with OIDC the browser
opens the provider's sign-in page.

## Install the helper and run

```sh
sudo ./scripts/install-helper.sh https://vpn.example.org   # more servers may follow
open dist/Claimward.app                                    # then click Connect
```

The installer copies the helper to `/Library/PrivilegedHelperTools/`, writes
`/Library/Application Support/Claimward/helper.json` (root's, mode `0644`)
with the servers given, and loads the LaunchDaemon `com.claimward.helper`.
The helper's socket is `/var/run/claimward-helper.sock`, `0660`,
`root:admin`; it logs to `/var/log/claimward-helper.log`.
`sudo ./scripts/uninstall-helper.sh` removes it.

## Tenants

A person in several tenants chooses one in the window ("Choose a tenant…"),
which offers them once the server says there is a choice, or on request. The
choice holds for the session; a new sign-in forgets it. A **Connect** from the
menu bar that the server refuses for want of a choice opens the window.

## Release

`.github/workflows/release.yml` builds `Claimward.dmg` on `v*` tags and
attaches it to the release. When the signing secrets are set it signs the app
with a Developer ID and notarizes and staples the DMG; without them it falls
back to an ad-hoc signature, which Gatekeeper blocks on a downloaded DMG. The
v0.1.0 DMG was built without the secrets, so it is **ad-hoc signed and not
notarized**. The DMG holds the app (with the helper binary inside it); the
helper is installed as above.

{{< callout type="info" >}}
**Still to come:** the session token in the Keychain (it is a `0600` file
today), the helper installed with SMJobBless, a release signed with a
Developer ID, and DNS applied on macOS.
{{< /callout >}}
