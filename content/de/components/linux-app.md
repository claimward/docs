---
title: "Linux-App"
linkTitle: "Linux-App"
weight: 5
description: "claimward-vpn-app-linux: ein Fenster und ein Symbol im Infobereich, in reinem Go mit go-widgets gezeichnet, und ein gehärteter, von systemd ausgeführter Helper."
tags: [linux, app, helper, systemd]
---

[`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux)
**v0.2.1** ist ein **Fenster und ein Symbol im Infobereich, in reinem Go gezeichnet** mit
[go-widgets](https://github.com/go-widgets): keine Webview, kein GTK, kein cgo
(`CGO_ENABLED=0`). Ein von systemd ausgeführter **privilegierter Helper** besitzt den WireGuard-Tunnel.
Die Logik ist die der macOS-App: Beide verwenden
[`pkg/appcore` und `pkg/helper`]({{< relref "/components/client.md" >}}).

## Aufbau {#design}

```text
 claimward-app (your session)
 ├─ internal/view        go-widgets/toolkit widgets, bound with go-widgets/mvvmtk
 ├─ internal/trayview    tray icon + menu (StatusNotifierItem over D-Bus)
 ├─ internal/viewmodel   all state as go-widgets/mvvm observables and commands
 └─ appcore              sign-in, tenant, session; drives the helper
        │ X11 / Wayland                  │ unix socket, JSON, 0660 root:claimward
        ▼                                ▼
   the window, the tray            claimward-helper (root, systemd)
                                   enrolls with a configured server,
                                   wireguard-go TUN + ip(8), route pushes
```

Die App läuft unter Ihrem Benutzer und greift nie selbst in die Netzwerkkonfiguration oder auf den
Server zu: Alles läuft über den [Helper]({{< relref "/components/helper.md" >}}).
Das ViewModel hält den gesamten Zustand und importiert kein Widget; die CI erzwingt
MVVM mit [mvvmlint](https://github.com/go-widgets/mvvmlint) und „keine
von Hand gezeichnete Oberfläche“ mit [bricolint](https://github.com/go-widgets/bricolint).

## Funktionen {#what-it-does}

- **Status**: wer angemeldet ist, verbunden oder nicht, die Adresse und die Schnittstelle,
  der Mandant der Sitzung, ob der Helper antwortet, der Server. Er wird
  alle 2 Sekunden abgefragt.
- **Anmeldung**: Bei einem Device Flow zeigt das Fenster den Code und eine Schaltfläche *Open sign-in
  page* (`xdg-open`); die Anmeldung kann abgebrochen werden.
- **Mandant**: Wenn der Server eine Verbindung ablehnt, weil die Person mehreren Mandanten angehört,
  meldet das Fenster dies und bietet eine Auswahlliste an; *Choose tenant* fragt
  die Liste im Voraus ab. Der Mandant kann nicht gewechselt werden, solange eine Verbindung besteht.
- **Connect / Disconnect / Sign out**, **Settings** (Server-URL, Anbieter,
  GitHub-Client-ID, OIDC-Issuer und Client-ID) und das **Verbindungsprotokoll**.
- **Infobereich**: eine Statuszeile, *Connect*, *Disconnect*, *Open window*, *Quit*; das
  Symbol ist farbig, solange eine Verbindung besteht. Das Schließen des Fensters lässt die App im
  Infobereich; *Quit* lässt den Tunnel, wie er ist.

Der Infobereich benötigt einen StatusNotifierItem-Host (KDE Plasma, GNOME mit der Erweiterung
*AppIndicator and KStatusNotifierItem Support*, waybar…). Ohne
einen solchen, oder wenn das Element des Infobereichs nicht auf den Sitzungsbus gelegt werden kann, meldet die App dies beim
Start, und das Schließen des Fensters beendet sie.

## Installation {#install}

Bauen Sie als Sie selbst (Go 1.27.1 oder neuer) und installieren Sie dann als root:

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

`install.sh`:

1. legt die Gruppe `claimward` an und fügt Sie ihr hinzu (`$SUDO_USER` oder
   `--user`): **Melden Sie sich ab und wieder an**, damit es wirksam wird;
2. installiert `claimward-app` nach `/usr/local/bin` und `claimward-helper` nach
   `/usr/local/sbin` (änderbar mit `--prefix`);
3. schreibt `/etc/claimward/helper.json`, `root:root`, Modus `0644`, mit dem
   angegebenen Server (eine vorhandene Datei bleibt erhalten);
4. installiert und startet `claimward-helper.service` und wartet auf dessen Socket;
5. installiert den Desktop-Eintrag und das Symbol.

Starten Sie **Claimward VPN** aus dem Menü der Desktopumgebung; `claimward-app -hidden`
startet im Infobereich (für einen Autostart-Eintrag). `sudo ./scripts/uninstall.sh`
entfernt alles und stoppt den Helper, was den Tunnel abbaut; `--purge`
entfernt außerdem `/etc/claimward` und die Gruppe.

## Konfiguration {#configure}

Die App: `~/.config/Claimward/config.json`, vom Einstellungsformular geschrieben,
Modus `0600`, überschrieben durch die Variablen `CLAIMWARD_*` (siehe die
[Client-Bibliothek]({{< relref "/components/client.md#files-on-the-device" >}})).
Die Sitzung ist `~/.config/claimward/session.json`, Modus `0600`.

Der Helper: `/etc/claimward/helper.json` (siehe
[Privilegierter Helper]({{< relref "/components/helper.md" >}})); führen Sie nach dem Bearbeiten
`sudo systemctl restart claimward-helper` aus.

## Die gehärtete Unit {#the-hardened-unit}

`claimward-helper.service` behält nur `CAP_NET_ADMIN`, `CAP_NET_RAW` und
`CAP_CHOWN`, mit `NoNewPrivileges`, `ProtectSystem=strict` und nur `/run`
beschreibbar, `ProtectHome`, aus `/dev` allein `/dev/net/tun`, Adressfamilien
beschränkt auf unix, inet, inet6 und netlink, und die Systemaufrufe von `@system-service`.
`systemd-analyze security claimward-helper` bewertet sie mit 2.5 (OK). Mitglied
der Gruppe `claimward` zu sein bedeutet, das VPN auf- und abbauen zu dürfen.

{{< callout type="info" >}}
**Geprüft** in einer virtuellen Maschine mit Ubuntu 24.04 (arm64) gegen einen
Ersatzserver. **Noch nicht geprüft**, laut README: ein echter GNOME- oder KDE-Desktop,
Wayland, HiDPI, eine Anmeldung bei einem echten Identitätsanbieter und ein
echter claimward-vpn-server. Die Sitzungsdatei liegt noch nicht in einem Schlüsselbund.
{{< /callout >}}
