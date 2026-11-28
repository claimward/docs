---
title: "macOS app"
linkTitle: "macOS app"
weight: 4
description: "claimward-vpn-app-osx: a native Go app (one window and a menu-bar status item, drawn by go-widgets with the system's own text fields and pop-up buttons), with a root LaunchDaemon helper."
tags: [macos, app, helper, go-widgets]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.11.0** is a native app written in Go: one window and a menu-bar status
item, drawn by [go-widgets](https://github.com/go-widgets), with the system's
own `NSTextField` and `NSPopUpButton` for the inputs. There is no webview, no
local web server and no JavaScript (before v0.7.0 the window was a Svelte page
in a webview). Its logic (sign-in, tenant choice, connect) and its helper are
the shared [`pkg/appcore` and `pkg/helper`]({{< relref "/components/client.md" >}});
the view model is `pkg/appvm`, the same one the Linux and Windows apps use.

## Design

```text
 claimward-app (one process, as you)
 ├─ window         go-widgets, with NSTextField / NSPopUpButton embedded
 ├─ status item    NSStatusItem: status / Open Claimward… / Connect / Disconnect / Quit
 ├─ notifications  when the tunnel drops or the session expires (from the app bundle)
 └─ view model     pkg/appvm over appcore: sign-in, tenant choice, session
        │ Unix socket (JSON), 0660 root:admin
        ▼
   claimward-helper (root LaunchDaemon)
   enrolls with the server, wireguard-go: utunN, route pushes
```

The app is one unprivileged process that owns all state. The text input (the
server URL) is the system's text field, with its input method and spell
checking; the provider and tenant choices are pop-up buttons. The
[helper]({{< relref "/components/helper.md" >}}) enrolls with the server and
owns the tunnel. Closing the window hides it: the app keeps running in the
status item and quits through its **Quit** item.

The window opens at 800 x 480 points (the size of WireGuard's macOS manager).
The **Servers** sidebar on the left lists the servers, each with its logo (a
neutral mark when it has none), its name and its state; **+**, **−** and a gear
are under the list. Several servers may be connected at once, and each row shows
its own state.

The detail panel on the right is a key/value table with section titles, in the
manner of WireGuard's tunnel panel. It hides every empty field except **Status**
and refreshes every second. **Server** holds the name and logo, the URL, the
identity provider and the signed-in identity, the tenant, whether the server is
*exclusive*, and whether the helper has approved it. **Status** has an icon and
the **Connect** / **Disconnect** buttons. **Interface** holds the status, the address, the DNS servers, the MTU and the lease
expiry in relative time. **Peer** holds the endpoint, the allowed IPs, the latest
handshake as "12 s ago" and the transfer as "3.50 MiB received, 900 B sent"
(needs client v0.12.0); each section is hidden while it is empty. **Edit** is at
the bottom right. When the server lists several identity providers, sign-in
shows one button per provider.

Every button carries a Tabler icon
([go-widgets/tabler-icons](https://github.com/go-widgets), MIT), and the
servers' logos are drawn by the toolkit's SVG logo widget. Unlike WireGuard's
rows, which truncate, any text wider than its box **wraps**: URLs, identities,
routes, refusal reasons and the connection log. Rows grow to hold their lines,
and the detail panel scrolls when it is taller than the 800 x 480 window, so
nothing is clipped.

**+** opens a window of its own with only a URL field. **Next** asks the server
for its public discovery document and previews its name, logo, providers and
whether it is exclusive; the person confirms before the server is added, and a
server that does not answer as a Claimward server is told in plain words. The
gear (or **Edit**) opens the same window on the selected server, prefilled, and
can change its identity provider; it is disabled, with the reason in its
accessible label, while no server is selected.

**Connect** on a server the helper has not approved asks macOS for an
administrator's authorization, naming the server's host, then approves the
server and connects (see [server approval]({{< relref "/components/helper.md" >}})).
A refusal is shown as such. **−** offers to revoke the approval with the
removal. An *exclusive* server, or a connection that blocks the others, disables
**Connect** and says why, for instance "Alpha is connected and exclusive".

## Build

With [go-task](https://taskfile.dev):

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Run the bundle rather than the bare binary: notifications are refused to a
process that is not in an app bundle, so from a bare binary a dropped tunnel
only reaches the log. By hand (no Node toolchain any more):

```sh
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Configure

Nothing has to be written by hand: **+** adds a server by its URL. The app keeps
the list in `~/Library/Application Support/Claimward/config.json` (app v0.10.0
and later, client v0.11.0; the format is described on the client page):

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com"}
  ]
}
```

Only the server URL is configured; the providers come from the server. With
GitHub and go-authn, clicking **Connect** shows a code to enter at the displayed
page; with OIDC the browser opens the provider's sign-in page. Older builds
(client v0.9.0 and earlier) read `server_url`, `provider`, `github_client_id`,
`oidc_issuer` and `oidc_client_id` instead; a file in that format is migrated
once, on first start, and its session is adopted by the matching server.

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

A person in several tenants chooses one in the detail panel's **Tenant** pop-up,
which lists them once the server has offered them; **Refresh** asks again. The
choice holds for the session; a new sign-in forgets it. A **Connect** from the
menu bar that the server refuses for want of a choice opens the window.

## Release

`.github/workflows/release.yml` builds `Claimward.dmg` on `v*` tags and
attaches it to the release. When the signing secrets are set it signs the app
with a Developer ID and notarizes and staples the DMG; without them it falls
back to an ad-hoc signature, which Gatekeeper blocks on a downloaded DMG. The
repository holds no signing secrets, so the published DMGs (v0.1.0 and
v0.2.0) are **ad-hoc signed and not notarized**. The DMG holds the app (with the helper binary inside it); the
helper is installed as above.

{{< callout type="info" >}}
**Still to come:** the helper installed with SMJobBless, a release signed with a
Developer ID, and DNS applied on macOS.
{{< /callout >}}

## Session and servers

The session (tokens and the device's WireGuard key) lives in `session.enc`,
sealed with AES-GCM; the key is held in the login **Keychain**. It is never
written to disk in clear and there is no plaintext fallback: if the Keychain is
locked or unavailable (client v0.5.0 and later), sign-in fails with an error
saying so. A `0600` `session.json` from an older version is moved into the
store on first start, or deleted if that fails.

The tunnel MTU is the server's `mtu`, lowered to fit the path to the server
(the interface MTU towards its endpoint, minus 60 for IPv4 or 80 for IPv6) and
never below 1280 (client v0.6.0, `pkg/pathmtu`).

The server must be an **https** URL. Since v0.7.0 there is no loopback UI API
and no launch token: the window and the logic share one process.
