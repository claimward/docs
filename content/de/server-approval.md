---
title: "Server-Genehmigung"
linkTitle: "Server-Genehmigung"
weight: 35
description: "Wie der Root-Helper entscheidet, einem von der App genannten Server zu vertrauen: die Vorab-Genehmigung des Administrators oder die Zustimmung des Betriebssystems, gespeichert in einer Datei, die nur root schreiben kann, und jederzeit widerrufbar."
tags: [security, helper, approval, macos, linux, windows]
---

Der Helper läuft als root (SYSTEM unter Windows), und ein Server, bei dem er sich
registriert, bestimmt die Routen und den Peer des Tunnels der Maschine: Ein feindlicher
Server ist jedes Paket der Maschine, dorthin geschickt. Seit **Client v0.11.0** nimmt der
Helper einen Server von der App nur an, wenn eine dieser Bedingungen gilt:

1. die Konfiguration des Administrators nennt ihn (`servers` in `helper.json`, jetzt
   optional: die **Vorab-Genehmigung**);
2. er wurde zuvor **genehmigt** und sagt noch immer dasselbe wie damals;
3. er wird **jetzt** genehmigt, mit der Zustimmung des Betriebssystems, die der Helper
   selbst einholt.

Ein App-Flag, ein Feld der Anfrage oder eine Behauptung jeder Art ist nie eine Zustimmung.

## Was vom System verlangt wird

| Plattform | Zustimmung |
|---|---|
| macOS | Authorization-Services-Recht `com.claimward.helper.approve-server`, Regel `authenticate-admin-nonshared`: Name und Passwort eines Administrators, jedes Mal. Die App holt die Autorisierung ein (`macauth.Obtain`) und sendet ihre 32 Byte lange externe Form; der Helper lässt sie vom System prüfen und vernichtet sie, ein Token erkauft also eine Genehmigung. Ein gefälschtes Token bezeichnet nichts im System und wird abgelehnt |
| Linux | polkit-Aktion `com.claimward.helper.approve-server` (`auth_admin`), beim Systembus für den Prozess hinter dem Socket erfragt: seine pid aus `SO_PEERCRED` und seine Startzeit aus `/proc/<pid>/stat`, was die Wiederverwendung von pids verhindert. Die Policy-Datei liegt in `packaging/polkit/` und gehört nach `/usr/share/polkit-1/actions/` |
| Windows | ein zweiter Socket, `C:\ProgramData\Claimward\approve.sock`, dessen ACL nur SYSTEM und Administratoren nennt: Ein Standardbenutzer kann sich ohne UAC-Erhöhung nicht verbinden. Nur eine Anfrage, die dort eingegangen ist, zählt |

Ohne konfigurierten Authorizer lehnt der Helper jede Genehmigung ab: Er schlägt
geschlossen fehl. Eine Anfrage, die abgelehnt wird oder die das System nicht beantworten
kann, ändert nichts.

## Was gespeichert wird

Der Helper hält die genehmigten Server in einer Datei, die nur root schreiben kann:

| Plattform | Datei |
|---|---|
| macOS | `/var/db/claimward/approved-servers.json` |
| Linux | `/var/lib/claimward/approved-servers.json` |
| Windows | `C:\ProgramData\Claimward\approved-servers.json` |

Jeder Eintrag ist die kanonische URL des Servers und der SHA-256 seiner
**Discovery-Identität**: sein Name und seine Identitätsanbieter (id, Art, Issuer,
Client-IDs). Ein Server, der eines davon ändert, ist nicht der genehmigte: Der Helper
lehnt ihn ab (`server_identity_changed`), bis er erneut genehmigt wird. Ob der Server
exklusiv ist, sein Logo und die Anzeigenamen der Anbieter gehören nicht zur Identität,
ebenso wenig sein TLS-Zertifikat, das alle paar Wochen erneuert wird (die Verbindung wird
bei jeder Nutzung gegen das Web-PKI geprüft).

Die Datei wird bei jeder Nutzung neu gelesen, **Löschen oder Entfernen einer Zeile
widerruft also sofort**; die Aktion `revoke` tut dasselbe für einen Server. Die
`servers`-Liste des Administrators wird vom Helper nie bearbeitet.

## Fehler, die die App sieht

| Code | Bedeutung |
|---|---|
| `server_not_approved` | der Server ist weder vorab genehmigt noch genehmigt: die Person bitten, ihn zu genehmigen |
| `server_identity_changed` | er war genehmigt und sagt nicht mehr dasselbe: erneut genehmigen |
| `approval_denied` | die Zustimmung des Systems wurde nicht erteilt |

## Grenzen, offen gesagt

- Unter macOS wird der **Text der Abfrage von der App geliefert**, die fragt; ein
  feindlicher Prozess in der Gruppe des Sockets kann das System also bitten, einen
  Administrator den eigenen Server genehmigen zu lassen, und ein unaufmerksamer
  Administrator kann zustimmen. Die Berechtigung ist die eines Administrators, nie
  zwischengespeichert, und gilt für eine Genehmigung.
- Unter Windows kann ein erhöhter Prozess alles genehmigen, wie ein Administrator die
  Datei ohnehin bearbeiten kann.
- Auch Linux hat keinen Cache: `auth_admin` fragt jedes Mal.
