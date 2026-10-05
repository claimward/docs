---
title: "Windows-App"
linkTitle: "Windows-App"
weight: 6
description: "claimward-vpn-app-windows: ein Fenster und ein Symbol im Infobereich in reinem Go, der Dienst ClaimwardHelper und wireguard-go auf einem Wintun-Adapter."
tags: [windows, app, helper, wintun]
---

[`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows)
**v0.3.0** ist eine Desktop-App mit einem Symbol im Infobereich (Tray). Alles ist
Go mit `CGO_ENABLED=0`: Das Fenster und der Infobereich werden von
[go-widgets](https://github.com/go-widgets) gezeichnet (keine Webview, kein HTTP-Server in der
App), und der Tunnel ist [wireguard-go](https://git.zx2c4.com/wireguard-go) auf einem
[Wintun](https://www.wintun.net)-Adapter, konfiguriert über die IP Helper API.
Ihre Logik und ihr Helper sind die gemeinsamen
[`pkg/appcore` und `pkg/helper`]({{< relref "/components/client.md" >}}).

## Aufbau {#design}

```text
 claimward-app.exe (the person, unprivileged)
 ├─ internal/ui/view.go        widgets, bound by go-widgets/mvvmtk to …
 ├─ internal/ui/viewmodel.go   … the ViewModel: all state, observables and commands
 ├─ internal/ui/tray_binding   the tray menu, bound to the same ViewModel
 └─ appcore                    sign-in, session, tenant, helper client
        │ AF_UNIX socket, one JSON request each: C:\ProgramData\Claimward\helper.sock
        ▼
 claimward-helper.exe — the ClaimwardHelper service (LocalSystem)
   pkg/helper   enrolls with a server helper.json names, owns the tunnel
   pkg/wgtun    wireguard-go on the Wintun adapter "Claimward"; address, routes, DNS, MTU
```

Das Fenster zeigt die Verbindung, die Adresse und die Schnittstelle, wer angemeldet ist,
den Mandanten und ob der Helper antwortet; die Aufforderung des Device Flow mit einer
Schaltfläche, die die Seite im Standardbrowser öffnet (an die Shell wird immer nur eine `https`-Seite
übergeben); **Connect / Disconnect / Sign out**; **Choose
tenant**; die Einstellungen, gespeichert in `%AppData%\Claimward\config.json`; und das
Verbindungsprotokoll. Der Status wird alle 2 Sekunden abgefragt. Das Menü im Infobereich bietet
den Status, Connect, Disconnect, Open und Quit. Das Schließen des Fensters beendet die
App; der Tunnel gehört dem Dienst und bleibt bis Disconnect bestehen.

Das Symbol im Infobereich erscheint ab **v0.3.0**. Davor hatte die Tray-Bibliothek keine
Windows-Implementierung des Aufrufs, den die App macht, und die App ignorierte den
Fehler, sodass v0.1.0 und v0.2.0 **kein Symbol im Infobereich** zeigten. v0.3.0 wird mit der
Tray-Bibliothek gebaut, die ihn implementiert (go-widgets/tray v0.14.0). Das ist durch die
Kompilierung und die eigenen Tests der Bibliothek geprüft, noch nicht auf einem Windows-Desktop. Zwei
bekannte Lücken: Ein Symbol, das nicht hinzugefügt werden kann, wird auf stderr gemeldet, was ein
Build mit Fenster nicht anzeigt
([#6](https://github.com/claimward/claimward-vpn-app-windows/issues/6)), und
beim Beenden kann ein Geistersymbol zurückbleiben, bis der Mauszeiger darüberfährt
([go-widgets/tray#37](https://github.com/go-widgets/tray/issues/37)).

## Installation {#install}

Aus einem Release-Ordner (`scripts/package.sh` erstellt sie, mit Wintun), in einer
PowerShell **mit erhöhten Rechten**:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.org
# optionally, the app's settings for the current user as well:
.\install.ps1 -Server https://vpn.example.org -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Es kopiert die Programme und `wintun.dll` nach `C:\Program Files\Claimward`,
legt die lokale Gruppe **Claimward Users** an und fügt Sie ihr hinzu, schreibt
`C:\ProgramData\Claimward\helper.json`, registriert und startet den Dienst
**ClaimwardHelper** und fügt eine Startmenü-Verknüpfung **Claimward VPN** hinzu.
Die Mitgliedschaft wird bei Ihrer **nächsten Anmeldung an Windows** wirksam; bis dahin
weist der Socket Sie ab. Fügen Sie weitere Personen hinzu mit
`Add-LocalGroupMember -Group 'Claimward Users' -Member <name>`.

`.\uninstall.ps1` entfernt den Dienst, die Verknüpfung und die Programme;
`-RemoveData` entfernt außerdem `C:\ProgramData\Claimward` und die Gruppe. Ein
MSI gibt es noch nicht.

`package.sh` lädt `wintun-0.14.1.zip` von wintun.net herunter und weist es zurück,
sofern sein SHA-256 nicht mit dem im Skript festgelegten übereinstimmt; die DLL ist von
WireGuard LLC signiert und liegt nicht im Repository.

## Konfiguration {#configure}

Die App liest `%AppData%\Claimward\config.json`, dann die Variablen `CLAIMWARD_*`
(siehe die [Client-Bibliothek]({{< relref "/components/client.md#files-on-the-device" >}})).
Die Sitzung ist `%AppData%\claimward\session.json`.

Der Helper liest `C:\ProgramData\Claimward\helper.json`:

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "Claimward Users",
  "socket": "C:\\ProgramData\\Claimward\\helper.sock"
}
```

Der Dienst protokolliert nach `C:\ProgramData\Claimward\helper.log`; aus einer Konsole
mit erhöhten Rechten führt `claimward-helper run` ihn im Vordergrund aus. Die ACLs, die der Helper
setzt und prüft, sind unter
[Privilegierter Helper]({{< relref "/components/helper.md#the-socket-windows" >}}) beschrieben.

{{< callout type="info" >}}
**Noch ausstehend:** ein MSI-Installationsprogramm und die Sitzung in der Windows-Anmeldeinformationsverwaltung
(DPAPI) statt in einer Datei pro Benutzer.
{{< /callout >}}
