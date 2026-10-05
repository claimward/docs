---
title: "macOS-App"
linkTitle: "macOS-App"
weight: 4
description: "claimward-vpn-app-osx: eine Menüleisten-App in Go, deren Fenster eine Svelte-Single-Page-App in einer Webview ist, mit einem Helper als root-LaunchDaemon."
tags: [macos, app, helper, svelte]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.2.0** ist eine in Go geschriebene Menüleisten-App (Tray), deren **gesamte Benutzeroberfläche
eine in einer Webview dargestellte Svelte-Single-Page-App ist**. Ihre Logik (Anmeldung,
Wahl des Mandanten, Verbinden) und ihr Helper sind die gemeinsamen
[`pkg/appcore` und `pkg/helper`]({{< relref "/components/client.md" >}}).

## Aufbau {#design}

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

Der Tray-Prozess besitzt den gesamten Zustand und stellt sowohl die Oberfläche als auch eine kleine JSON-API auf
`127.0.0.1` bereit, geschützt durch ein bei jedem Start neues Token, das in konstanter Zeit verglichen wird. Die
Webview ist ein schlankes Fenster, das auf diese Loopback-URL zeigt, in einem eigenen Prozess,
weil nur eine Cocoa-Run-Loop den Hauptthread besitzen kann. Der
[Helper]({{< relref "/components/helper.md" >}}) registriert sich beim Server und
besitzt den Tunnel; die App ist nicht privilegiert.

## Build {#build}

Mit [go-task](https://taskfile.dev):

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Starten Sie das Bundle und nicht das bloße Binary: Ein bloßes Binary, das von einem
Menüleisten-Agenten gestartet wird, kann sein Fenster nicht in den Vordergrund bringen. Von Hand:

```sh
cd frontend && npm install && npm run build && cd ..   # the Svelte UI, embedded with go:embed
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Konfiguration {#configure}

`~/Library/Application Support/Claimward/config.json`, auch bearbeitbar über
**Configuration…** (GitHub ist der Standard):

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "github",
  "github_client_id": "Iv1.0123456789abcdef"
}
```

Für OIDC setzen Sie `"provider": "oidc"`, für go-authn `"provider": "go-authn"`, jeweils mit
`"oidc_issuer"` und `"oidc_client_id"`. Bei GitHub und go-authn zeigt ein Klick auf
**Connect** einen Code an, der auf der angezeigten Seite einzugeben ist; bei OIDC öffnet der Browser
die Anmeldeseite des Anbieters.

## Den Helper installieren und starten {#install-the-helper-and-run}

```sh
sudo ./scripts/install-helper.sh https://vpn.example.org   # more servers may follow
open dist/Claimward.app                                    # then click Connect
```

Das Installationsprogramm kopiert den Helper nach `/Library/PrivilegedHelperTools/`, schreibt
`/Library/Application Support/Claimward/helper.json` (gehört root, Modus `0644`)
mit den angegebenen Servern und lädt den LaunchDaemon `com.claimward.helper`.
Der Socket des Helpers ist `/var/run/claimward-helper.sock`, `0660`,
`root:admin`; er protokolliert nach `/var/log/claimward-helper.log`.
`sudo ./scripts/uninstall-helper.sh` entfernt ihn.

## Mandanten {#tenants}

Eine Person in mehreren Mandanten wählt einen im Fenster aus („Choose a tenant…“),
das sie anbietet, sobald der Server meldet, dass eine Wahl besteht, oder auf Anfrage. Die
Wahl gilt für die Sitzung; eine neue Anmeldung vergisst sie. Ein **Connect** aus der
Menüleiste, das der Server mangels Auswahl ablehnt, öffnet das Fenster.

## Release {#release}

`.github/workflows/release.yml` baut `Claimward.dmg` bei `v*`-Tags und
hängt es an das Release an. Wenn die Signatur-Secrets gesetzt sind, signiert es die App
mit einer Developer ID und lässt das DMG notarisieren und versieht es mit dem Ticket (Stapling); ohne sie weicht es
auf eine Ad-hoc-Signatur aus, die Gatekeeper bei einem heruntergeladenen DMG blockiert. Das
Repository enthält keine Signatur-Secrets, daher sind die veröffentlichten DMGs (v0.1.0 und
v0.2.0) **ad hoc signiert und nicht notarisiert**. Das DMG enthält die App (mit dem Helper-Binary darin); der
Helper wird wie oben beschrieben installiert.

{{< callout type="info" >}}
**Noch ausstehend:** das Sitzungstoken in der Keychain (heute ist es eine Datei mit `0600`),
der mit SMJobBless installierte Helper, ein mit einer
Developer ID signiertes Release und unter macOS angewendetes DNS.
{{< /callout >}}
