---
title: "macOS-App"
linkTitle: "macOS-App"
weight: 4
description: "claimward-vpn-app-osx: eine native Go-App (ein Fenster und ein Menüleisten-Symbol, mit go-widgets gezeichnet, mit den Textfeldern und Popup-Menüs des Systems), mit einem Helper als root-LaunchDaemon."
tags: [macos, app, helper, go-widgets]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.10.0** ist eine native, in Go geschriebene App: ein Fenster und ein Menüleisten-Symbol,
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
Die Eingabe (die Server-URL) ist das Textfeld des Systems, mit seiner
Eingabemethode und Rechtschreibprüfung; die Wahl von Anbieter und Mandant sind
Popup-Menüs. Der [Helper]({{< relref "/components/helper.md" >}}) registriert sich beim
Server und besitzt den Tunnel. Das Schließen des Fensters blendet es aus: Die App läuft
im Statussymbol weiter und wird über dessen Eintrag **Quit** beendet.

Das Fenster öffnet sich mit 800 x 480 Punkten (der Größe des macOS-Managers von WireGuard).
Die Seitenleiste **Servers** links listet die Server, jeweils mit Logo (einem neutralen
Zeichen, wenn es keines hat), Name und Zustand; **+**, **−** und ein Zahnrad
stehen unter der Liste. Mehrere Server können gleichzeitig verbunden sein, und jede Zeile
zeigt ihren eigenen Zustand.

Der Detailbereich rechts ist eine Schlüssel/Wert-Tabelle mit Abschnittstiteln, nach Art
des Tunnel-Bereichs von WireGuard. Er blendet jedes leere Feld außer **Status** aus
und aktualisiert sich jede Sekunde. **Server** enthält Name und Logo, die URL, den
Identitätsanbieter und die angemeldete Identität, den Mandanten, ob der Server
*exklusiv* ist, und ob der Helper ihn genehmigt hat. **Status** hat ein Symbol und die
Schaltflächen **Connect** / **Disconnect**. **Interface** enthält die Adresse und
den Ablauf der Lease in relativer Zeit. **Edit** steht unten rechts. Listet der
Server mehrere Identitätsanbieter, zeigt die Anmeldung eine Schaltfläche je Anbieter.

**+** öffnet ein eigenes Fenster mit nur einem URL-Feld. **Next** fragt beim Server
sein öffentliches Discovery-Dokument ab und zeigt eine Vorschau auf Name, Logo, Anbieter
und darauf, ob er exklusiv ist; die Person bestätigt, bevor der Server hinzugefügt wird,
und einem Server, der nicht als Claimward-Server antwortet, wird das in einfachen Worten
mitgeteilt. Das Zahnrad (oder **Edit**) öffnet dasselbe Fenster für den gewählten Server,
vorausgefüllt, und kann dessen Identitätsanbieter ändern; ist kein Server gewählt, ist es
deaktiviert, und der Grund steht in seiner Bedienungshilfe-Beschriftung.

**Connect** auf einem Server, den der Helper nicht genehmigt hat, fragt macOS nach der
Autorisierung eines Administrators und nennt dabei den Host des Servers; danach genehmigt
es den Server und verbindet (siehe [Genehmigung des Servers]({{< relref "/components/helper.md" >}})).
Eine Ablehnung wird als solche angezeigt. **−** bietet an, die Genehmigung mit dem
Entfernen zu widerrufen. Ein *exklusiver* Server oder eine Verbindung, die die anderen
blockiert, deaktiviert **Connect** und nennt den Grund, etwa „Alpha is connected and exclusive“.

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

Von Hand ist nichts zu schreiben: **+** fügt einen Server über seine URL hinzu. Die App führt
die Liste in `~/Library/Application Support/Claimward/config.json` (App ab v0.10.0,
Client v0.11.0; das Format steht auf der Seite des Clients):

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com"}
  ]
}
```

Konfiguriert wird nur die URL des Servers; die Anbieter kommen vom Server. Bei GitHub
und go-authn zeigt ein Klick auf **Connect** einen Code an, der auf der angezeigten Seite
einzugeben ist; bei OIDC öffnet der Browser die Anmeldeseite des Anbieters. Ältere
Builds (Client v0.9.0 und früher) lasen stattdessen `server_url`, `provider`,
`github_client_id`, `oidc_issuer` und `oidc_client_id`; eine Datei in diesem Format wird
beim ersten Start einmalig migriert, und ihre Sitzung wird vom passenden Server übernommen.

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
