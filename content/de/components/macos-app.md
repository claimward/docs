---
title: "macOS-App"
linkTitle: "macOS-App"
weight: 4
description: "claimward-vpn-app-osx: eine native Go-App (ein Fenster und ein Menüleisten-Symbol, mit go-widgets gezeichnet, mit den Textfeldern und Popup-Menüs des Systems), mit einem Helper als root-LaunchDaemon."
tags: [macos, app, helper, go-widgets]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.7.0** ist eine native, in Go geschriebene App: ein Fenster und ein Menüleisten-Symbol,
mit [go-widgets](https://github.com/go-widgets) gezeichnet, mit den `NSTextField` und
`NSPopUpButton` des Systems für die Eingaben. Es gibt keine Webview, keinen lokalen
Webserver und kein JavaScript (vor v0.7.0 war das Fenster eine Svelte-Seite in einer
Webview). Ihre Logik (Anmeldung, Wahl des Mandanten, Verbinden) und ihr Helper sind die
gemeinsamen [`pkg/appcore` und `pkg/helper`]({{< relref "/components/client.md" >}}); das
View-Modell ist `pkg/appvm`, dasselbe wie in der Linux- und der Windows-App.

## Aufbau {#design}

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

Die App ist ein einziger, nicht privilegierter Prozess, der den gesamten Zustand besitzt.
Die Eingaben (Server-URL, Client-IDs) sind die Textfelder des Systems, mit seiner
Eingabemethode und Rechtschreibprüfung; die Wahl von Anbieter und Mandant sind
Popup-Menüs. Der [Helper]({{< relref "/components/helper.md" >}}) registriert sich beim
Server und besitzt den Tunnel. Das Schließen des Fensters beendet die App, wie unter Linux
und Windows.

Das Fenster hat eine Kopfzeile (das Claimward-Zeichen, den Titel und **Settings**), links
eine Seitenleiste **Servers** mit **+** und **−** unter der Liste und rechts den
Detailbereich des gewählten Servers: Name, das Popup-Menü **Tenant** mit **Refresh**, den
Sitzungsstatus, Anmeldung, Connect und Disconnect sowie das Verbindungsprotokoll. Das
Einstellungsformular öffnet sich in einem eigenen Fenster, damit der Status sichtbar bleibt;
wo kein zweites Fenster geöffnet werden kann, erscheint es im Hauptfenster.

## Build {#build}

Mit [go-task](https://taskfile.dev):

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Starten Sie das Bundle und nicht das bloße Binary: Benachrichtigungen werden einem
Prozess verweigert, der nicht in einem App-Bundle läuft; mit einem bloßen Binary landet
ein abgerissener Tunnel nur im Log. Von Hand (keine Node-Toolchain mehr):

```sh
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Konfiguration {#configure}

`~/Library/Application Support/Claimward/config.json`, auch bearbeitbar über die
Fenster **Settings** (GitHub ist der Standard):

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

Eine Person in mehreren Mandanten wählt einen im Popup-Menü **Tenant** des Detailbereichs aus,
das sie auflistet, sobald der Server sie angeboten hat; **Refresh** fragt erneut. Die
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
**Noch ausstehend:** der mit SMJobBless installierte Helper, ein mit einer
Developer ID signiertes Release und unter macOS angewendetes DNS.
{{< /callout >}}

## Sitzung und Server

Die Sitzung (Tokens und der WireGuard-Schlüssel des Geräts) liegt in `session.enc`,
versiegelt mit AES-GCM; der Schlüssel liegt in der Login-**Keychain**. Sie wird nie im
Klartext auf die Platte geschrieben, und es gibt keinen Klartext-Fallback: Ist die Keychain
gesperrt oder nicht verfügbar (Client v0.5.0 und neuer), schlägt die Anmeldung mit einem
entsprechenden Fehler fehl. Eine `session.json` mit `0600` aus einer älteren Version wird
beim ersten Start in den Speicher verschoben oder gelöscht, wenn das fehlschlägt.

Die MTU des Tunnels ist die `mtu` des Servers, so weit gesenkt, dass sie in den
Pfad zum Server passt (die Schnittstellen-MTU zum Endpunkt, minus 60 bei IPv4
oder 80 bei IPv6), und nie kleiner als 1280 (Client v0.6.0, `pkg/pathmtu`).

Der Server muss eine **https**-URL sein. Seit v0.7.0 gibt es keine Loopback-UI-API und
kein Start-Token mehr: Fenster und Logik teilen sich einen einzigen Prozess.
