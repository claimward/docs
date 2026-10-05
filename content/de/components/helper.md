---
title: "Privilegierter Helper"
linkTitle: "Privilegierter Helper"
weight: 3
description: "Der root- oder SYSTEM-Prozess jeder App: Er registriert sich nur bei den Servern, die seine eigene Konfiguration nennt, übernimmt keine Tunnelkonfiguration aus einer Anfrage und lauscht auf einem Socket, den nur seine Gruppe erreicht."
tags: [helper, sicherheit, macos, linux, windows]
---

Jede App hat einen **privilegierten Helper**: einen root-LaunchDaemon unter macOS, einen systemd-Dienst
unter Linux, den Dienst **ClaimwardHelper** (LocalSystem) unter Windows. Er
ist der einzige privilegierte Prozess der App. Alle drei sind derselbe Code,
`pkg/helper` aus [claimward-vpn-client](https://github.com/claimward/claimward-vpn-client);
jede App liefert nur eine `main`, die die Konfiguration lädt und lauscht.

Der Helper übernimmt die Kommunikation mit dem Server ebenso wie den Tunnel: Er registriert sich,
baut den Tunnel auf und beobachtet gepushte Routen. Unter macOS hindert der Datenschutz
„Lokales Netzwerk“ eine nicht privilegierte App daran, einen Server im LAN zu erreichen, während root
davon ausgenommen ist; die anderen Plattformen folgen demselben Weg, damit sich die drei Apps
gleich verhalten.

## Das Socket-Protokoll {#the-socket-protocol}

Eine JSON-Anfrage pro Verbindung, eine JSON-Antwort (`pkg/hproto`):

| Aktion | Was der Helper tut |
|---|---|
| `connect` | registriert sich beim in der Anfrage genannten Server, sofern seine Konfiguration es erlaubt, mit dem übergebenen Bearer-Token, privaten Schlüssel, Gerätenamen und Mandanten; baut den Tunnel auf; beobachtet den RouteService |
| `tenants` | fragt den Server, mit welchen Mandanten sich das Bearer-Token verbinden darf |
| `down` | baut den Tunnel ab |
| `status` | verbunden oder nicht, die Schnittstelle, die Adresse, der Mandant |

## Durch die eigene Konfiguration begrenzt {#bounded-by-its-own-configuration}

Jeder Prozess, der den Socket des Helpers erreichen kann, kann ihn zum Handeln bringen, daher ist das, was er
tut, durch **seine eigene** Konfiguration begrenzt, niemals durch die Anfrage:

- **Er registriert sich nur bei einem Server, den seine Konfiguration nennt.** Ein Helper, der
  den Server aus der Anfrage übernähme, ließe jeden lokalen Prozess ihn auf einen eigenen
  Server richten, der mit Routen für `0.0.0.0/0` antwortet: jedes Paket der
  Maschine, dorthin gesendet, wohin dieser Prozess es wollte.
- **Er übernimmt keine Tunnelkonfiguration aus einer Anfrage.** Der Tunnel ist das, was dieser
  Server bei der Registrierung geantwortet hat. Die früheren Aktionen `up` und `update-routes`,
  die eine übernahmen, gibt es nicht mehr.
- **Seine Konfiguration muss root gehören** (unter Windows SYSTEM oder den Administratoren) **und
  für niemanden sonst beschreibbar sein**, sonst startet der Helper nicht:
  Wer sie schreibt, wählt die vertrauenswürdigen Server.

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "claimward",
  "socket": "/var/run/claimward-helper.sock"
}
```

| Schlüssel | |
|---|---|
| `servers` | **erforderlich**: die Server, bei denen sich der Helper registrieren darf. Die `server_url` der App muss einer davon sein (verglichen ohne abschließendes `/`) |
| `group` | wer den Socket neben root verwenden darf: standardmäßig `admin` unter macOS, `claimward` unter Linux, `Claimward Users` unter Windows |
| `socket` | standardmäßig `/var/run/claimward-helper.sock`, unter Windows `C:\ProgramData\Claimward\helper.sock` |

| Plattform | `helper.json` |
|---|---|
| macOS | `/Library/Application Support/Claimward/helper.json` |
| Linux | `/etc/claimward/helper.json` |
| Windows | `C:\ProgramData\Claimward\helper.json` |

## Der Socket: macOS und Linux {#the-socket-macos-and-linux}

Der Socket hat **`0660`** und gehört root und der Gruppe des Helpers. Er wird
mit einer restriktiven umask angelegt, sodass er nie mit weiteren Rechten existiert, in einem Verzeichnis,
in das nur root schreiben kann (der Helper lehnt eines ab, in das jemand anderes schreiben könnte, denn dieser
könnte den Socket durch seinen eigenen ersetzen und das Bearer-Token der App empfangen). Der
Socket des früheren Helpers hatte `0666`.

## Der Socket: Windows {#the-socket-windows}

Unter Windows sind dieselben Regeln ACLs, die der Helper selbst setzt und zurückliest,
statt darauf zu vertrauen, dass ein Installationsprogramm es getan hat:

- das Verzeichnis des Sockets, `C:\ProgramData\Claimward`, erhält eine **geschützte** DACL
  (nichts von ProgramData geerbt, das jedem Benutzer erlaubt, dort Dateien anzulegen):
  SYSTEM und Administratoren mit Vollzugriff, die Gruppe des Sockets darf es
  auflisten und durchqueren und nichts weiter. Es wird bereits mit dieser
  DACL angelegt, und ein Verzeichnis, das eine Junction oder ein Link ist, wird abgelehnt;
- der Socket erhält seine eigene DACL: SYSTEM, Administratoren und die Gruppe, die sich
  verbinden darf (Lesen/Schreiben);
- die Gruppe ist die lokale Gruppe **`Claimward Users`**, die das Installationsprogramm
  anlegt. Existiert sie nicht, wird der Socket für **INTERACTIVE** geöffnet
  (alle an der Maschine angemeldeten Personen, Konsole oder Remotedesktop), und der
  Helper protokolliert, dass er das getan hat;
- `helper.json` muss **SYSTEM oder den Administratoren gehören und für niemanden sonst
  beschreibbar sein**: Der Helper liest den Besitzer und die DACL der Datei und lehnt jeden
  Zulassungseintrag ab, der einer anderen SID Schreiben, Anhängen, Löschen, `WRITE_DAC`, `WRITE_OWNER` oder
  generisches Schreiben/Alles gewährt, ebenso eine Null-DACL.

Die Regeln (`pkg/helper/acl.go`) sind reine Funktionen, auf jeder Plattform getestet;
der Windows-Job der CI wendet sie auf echte Dateien an und liest sie zurück.

## Beobachtung der Routen über TLS {#route-watches-over-tls}

Eine Beobachtung der Routen überträgt das Bearer-Token, daher führt `pkg/routeclient` sie über
**TLS** aus, geprüft gegen die Stammzertifikate des Systems, außer zu einer Loopback-Adresse.
Gegenüber einem Server, dessen RouteService kein TLS spricht, scheitert der Handshake, bevor das
Token gesendet wird, und der Tunnel bleibt ohne Live-Aktualisierungen der Routen bestehen.

Das Beenden des Helpers baut den Tunnel ab.
