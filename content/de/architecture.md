---
title: "Architektur"
weight: 20
description: "Eine Steuerungsebene, die die Anmeldung prüft und das Gateway programmiert, eine Datenebene, die schlicht WireGuard ist, und auf jedem Gerät ein privilegierter Helper zwischen beiden."
tags: [wireguard, server, helper, grpc]
---

Claimward trennt eine **Steuerungsebene**, den Server, von der **Datenebene**,
dem WireGuard-Tunnel zwischen einem Gerät und dem Gateway. Die Authentifizierung wird
an Ihren Identitätsanbieter delegiert: Claimward sieht nie ein Passwort.

Auf einem Gerät meldet eine nicht privilegierte **App** die Person an und hält die
Sitzung; ein **privilegierter Helper** (root, unter Windows SYSTEM) registriert sich beim
Server und besitzt den Tunnel. Die App selbst spricht nie mit dem Server.

## Registrierungsablauf von Ende zu Ende {#end-to-end-enrollment-flow}

```text
 ┌──────────┐ 1. sign-in: GitHub device flow, OIDC code + PKCE,  ┌──────────┐
 │   app    │    or go-authn device flow (+ key registration)    │   IdP    │
 │ (as you) │◀─────────────────── bearer token ──────────────────│          │
 └────┬─────┘                                                    └──────────┘
      │ 2. socket: connect {server_url, bearer, private key, tenant}
      ▼
 ┌──────────┐ 3. POST /api/v1/enroll                ┌─────────────────────────┐
 │  helper  │    Authorization: Bearer <token>      │  claimward-vpn-server   │
 │ (root)   │    {public_key, device, tenant}  ───▶ │  verify the bearer      │
 │          │                                       │  choose the tenant      │
 │          │ ◀─── 4. {assigned_ip,                 │  allocate an address    │
 │          │       server_public_key, endpoint,    │  wgctrl: add the peer   │
 │          │       allowed_ips, dns,               │  (AllowedIPs = ip/32)   │
 │          │       grpc_endpoint, keepalive,       └───────────┬─────────────┘
 │          │       lease_expires_at}                           │ RouteService
 │          │ ◀═════════════ 6. gRPC Watch (TLS) ═══════════════╛ (live routes)
 │          │
 │          │ 5. wireguard-go: utunN / Wintun "Claimward", address, routes
 └────┬─────┘
      ╚═══════════════════ WireGuard tunnel ════════════════════▶ private network
```

1. Die App meldet die Person mit dem konfigurierten Anbieter an: standardmäßig **GitHub**
   (OAuth Device Flow), ein beliebiger **OpenID-Connect**-Issuer (Authorization
   Code mit PKCE, im Browser) oder ein **go-authn**-Anbieter (Device Flow).
   Das Bearer-Token, das sie erhält, ist ein GitHub-Access-Token, ein OIDC-ID-Token oder ein go-authn-Access-Token.
   Bei go-authn wird zuerst der **öffentliche** Schlüssel des Geräts beim Anbieter
   registriert, und das Bearer-Token ist das Token, das diese Registrierung
   zurückgibt.
2. Die App erzeugt das WireGuard-Schlüsselpaar des Geräts bei der ersten Anmeldung und
   bewahrt es in ihrer Sitzungsdatei auf, bis sich die Person abmeldet, sodass das Gerät
   seinen öffentlichen Schlüssel über Verbindungen hinweg behält (und seine Adresse, solange es registriert ist). Zum Verbinden übergibt sie dem Helper die Server-URL, das Bearer-Token, den
   privaten Schlüssel und den für die Sitzung gewählten Mandanten, über den Socket des Helpers.
3. Der Helper prüft, dass der Server **einer der in seiner eigenen Konfiguration genannten** ist,
   und ruft dann `POST /api/v1/enroll` mit dem öffentlichen Schlüssel des Geräts und dem
   Bearer-Token auf.
4. Der Server **prüft** das Bearer-Token (ein Aufruf der GitHub-API, ein OIDC-ID-Token oder
   ein go-authn-Access-Token, dessen Subject den Schlüssel besitzen muss), wendet eine etwaige
   Allowlist für Organisationen oder E-Mail-Domains an, wählt den **Mandanten**, **vergibt** eine
   VPN-Adresse und **programmiert das Gateway** (`wgctrl`) mit einem Peer, dessen einzige
   erlaubte IP dieses `/32` ist. Er antwortet mit den Tunnelparametern: der Adresse,
   seinem eigenen öffentlichen Schlüssel, dem Endpunkt, den Routen und DNS-Servern des Mandanten, dem
   Keepalive, dem Endpunkt des RouteService und dem Ende der Lease.
5. Der Helper baut mit `wireguard-go` einen Tunnel im Userspace auf, gibt der
   Schnittstelle ihre Adresse und installiert die Routen.
6. Wenn der Server einen RouteService ankündigt (`GRPC_ENDPOINT`), beobachtet der Helper
   ihn über gRPC: Änderungen an den Routen des Mandanten erreichen das Gerät,
   ohne dass es sich erneut registriert.

## Leases {#leases}

Jede Registrierung trägt eine **Lease** von `LEASE_TTL` (standardmäßig 24 Stunden). Ein
Hintergrundprozess auf dem Server entfernt jede Minute die Peers, deren Lease
abgelaufen ist, sodass ein verlorenes oder gesperrtes Gerät von selbst vom Gateway verschwindet. Bei
go-authn überdauert eine Lease nie die Registrierung des Schlüssels beim Anbieter.

Der Server erneuert eine Lease bei `POST /api/v1/heartbeat` und entfernt einen Peer
sofort bei `POST /api/v1/deregister`.

Ab **claimward-vpn-client v0.3.1**, also ab den App-Releases, die diese Version
enthalten (die macOS-, Linux- und Windows-Apps ab v0.2.0), hält der Helper die Lease selbst aufrecht, solange
der Tunnel steht. Er erneuert sie, wenn die Hälfte der Restlaufzeit der Lease verstrichen ist, nie früher
als nach 30 Sekunden und nie später als nach 10 Minuten, und handelt nach der Antwort:

| Der Server antwortet | Der Helper |
|---|---|
| eine erneuerte Lease | erneuert wieder nach der Hälfte davon |
| `404 not_enrolled`: Er hat das Gerät vergessen (die Lease ist abgelaufen, oder der Server wurde neu gestartet) | registriert sich erneut mit demselben Schlüssel und Mandanten und baut den Tunnel anhand dieser Antwort auf; schlägt auch das fehl, baut er den Tunnel ab |
| `403` (`not_a_member`, `key_not_registered`): Zugang entzogen | baut den Tunnel ab und meldet den Grund (`last_error`) |
| `401`, ein `5xx` oder nichts | versucht es innerhalb einer Minute erneut, bevor die Lease endet |

Der Helper erneuert mit dem letzten Bearer-Token, das er erhalten hat. Das genügt für ein
GitHub-Token, nicht aber für ein go-authn-Access-Token, das nach Minuten abläuft und
das nur die App auffrischen kann. Solange die App läuft, übergibt `pkg/appcore` dem
Helper daher ein frisches Bearer-Token (die Aktion `renew` des Helpers), wenn 40 % der Restlaufzeit der Lease
verstrichen sind (höchstens 8 Minuten auseinander), bevor die eigene Erneuerung des Helpers fällig ist. Eine App, die unter einem
laufenden Tunnel neu gestartet wird, beginnt damit bei ihrer ersten Statusabfrage.

*Disconnect* (die Aktion `down` des Helpers) **meldet** den Peer **ab** und gibt seine
Adresse sofort zurück. Ein Helper, der beendet wird (sein Dienstmanager stoppt
ihn, oder die Maschine fährt herunter), baut den Tunnel ab, ohne sich abzumelden,
sodass ein neu gestarteter Helper die Lease noch vorfindet und die Lease einer gestoppten Maschine
auf dem Server abläuft.

{{< callout type="info" >}}
Die Apps in v0.1.0 bauen auf früheren Client-Versionen auf, die nichts davon tun:
Sie erneuern eine Lease nur durch erneutes Verbinden und lassen den Peer nach
*Disconnect* auf dem Gateway, bis seine Lease endet.
{{< /callout >}}

## Vertrauensgrenzen {#trust-boundaries}

- Der **Server** ist die einzige Komponente, die mit dem Identitätsanbieter spricht, um
  eine Anmeldung zu prüfen, und die einzige mit dem Recht, die Peers des Gateways zu ändern.
- Auf dem Gerät ist der **Helper** der einzige privilegierte Prozess. Alles, was
  seinen Socket erreichen kann, kann ihn zum Handeln auffordern, daher handelt er im Rahmen seiner eigenen
  Konfiguration: Er registriert sich nur bei den Servern, die diese Konfiguration nennt, und
  übernimmt keine Tunnelkonfiguration aus einer Anfrage. Siehe
  [Privilegierter Helper]({{< relref "/components/helper.md" >}}).
- Die **App** läuft unter dem Benutzer der Person. Sie hält die Sitzung (Bearer-Token und Geräteschlüssel)
  in einer Datei mit `0600` in deren Konfigurationsverzeichnis.
- Eine Beobachtung der Routen überträgt das Bearer-Token, daher läuft sie über **TLS**, außer zu einer
  Loopback-Adresse.
- Der Wire-Vertrag liegt an einer einzigen Stelle,
  [`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
  und `pkg/routespb`, importiert sowohl von den Clients als auch vom Server.
