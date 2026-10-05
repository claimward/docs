---
title: "Betrieb"
weight: 70
description: "Claimward in Produktion betreiben: TLS, das Gateway, Leases, was ein Neustart vergisst, der Identitätsanbieter, die Admin-API und Metriken."
tags: [server, betrieb, wireguard, grpc]
---

## TLS

Der Server spricht unverschlüsseltes HTTP, sofern `TLS_CERT`/`TLS_KEY` nicht gesetzt sind. Bearer-Tokens
sind Zugangsdaten, stellen Sie die API also **immer** hinter TLS, direkt oder über einen
Reverse Proxy (nginx, Caddy, einen Load Balancer).

Dasselbe Zertifikat bedient den gRPC-RouteService. Eine Beobachtung der Routen überträgt das
Bearer-Token, und die Clients lehnen eine unverschlüsselte Beobachtung ab, außer über Loopback: Ein
Server ohne `TLS_CERT`/`TLS_KEY` (etwa hinter einem Proxy, der nur
HTTPS terminiert) registriert Geräte, diese erhalten aber keine Live-Aktualisierungen der Routen, und er
protokolliert beim Start eine Warnung. Setzen Sie `GRPC_ENDPOINT` auf den `host:port`, unter dem die Geräte
den RouteService erreichen, mit einem Namen, den das Zertifikat abdeckt.

## Gateway {#gateway}

- Bringen Sie `wg0` beim Booten mit `wg-quick` oder systemd-networkd hoch; Claimward
  verwaltet nur seine Peers. Starten Sie den Server mit den Rechten, die Schnittstelle zu konfigurieren
  (root oder `CAP_NET_ADMIN`).
- Aktivieren Sie `net.ipv4.ip_forward` sowie NAT- oder Firewall-Regeln, wenn Clients
  über das VPN-Subnetz hinaus routen.
- `GET /healthz` ist die Liveness-Probe.

## Leases {#leases}

`LEASE_TTL` (standardmäßig 24 Stunden) wägt Sicherheit gegen Fluktuation ab. Der Hintergrundprozess
entfernt jede Minute abgelaufene Peers, sodass gesperrte oder offline befindliche Geräte von selbst
verschwinden. Um eines sofort zu sperren, melden Sie seinen Peer ab oder entfernen Sie ihn mit
`wg set wg0 peer <key> remove`.

Ab claimward-vpn-client v0.3.1 (die Apps ab v0.2.0) erneuert der Helper
die Lease, solange der Tunnel steht, nach der Hälfte der Restlaufzeit (zwischen 30 Sekunden
und 10 Minuten), und meldet sich bei *Disconnect* ab. Eine kürzere `LEASE_TTL` kostet daher
mehr Heartbeats, nicht abgebrochene Tunnel: Eine Entfernung aus einem Mandanten oder ein Schlüssel,
den der go-authn-Anbieter zurückzieht, beendet den Tunnel bei der nächsten Erneuerung (der
Server antwortet `403`). Ein Server, der ein Gerät vergessen hat (`404`), lässt es
sich erneut registrieren. Siehe [Leases]({{< relref "/architecture.md#leases" >}}).

Die Apps in v0.1.0 erneuern nur durch erneutes Verbinden und lassen den Peer nach *Disconnect* bestehen, bis seine
Lease endet: Bei ihnen verliert ein Gerät, das länger als `LEASE_TTL` verbunden bleibt,
seinen Tunnel, wenn sein Peer entfernt wird.

## Zustand {#state}

Der Server hält die registrierten Peers, den Adresspool und die Mandanten
**im Arbeitsspeicher**. Ein Neustart vergisst sie:

- die Mandanten sind wieder allein `default`, aus `PUSH_ROUTES` und `DNS`;
- ab Server **v0.2.0** werden die Peers, die ein vorheriger Lauf auf `wg0` hinterlassen hat,
  **beim Start entfernt**: jeder Peer, dessen einzige erlaubte IP ein `/32` innerhalb von
  `VPN_CIDR` ist, die Form, die der Server jedem Peer gibt. Jeder andere Peer
  (von Hand konfiguriert, eine Site-to-Site-Verbindung) bleibt unberührt. Behalten, würden diese Peers
  niemandem gehören: nie entfernt, nie gegen die Liste des Anbieters geprüft,
  sodass eine vor dem Neustart deaktivierte Person einen funktionierenden Tunnel behielte. Geräte
  stellen bei ihrer nächsten Erneuerung der Lease fest, dass sie unbekannt sind, und registrieren sich erneut (Apps,
  die auf claimward-vpn-client v0.3.1 aufbauen); bis dahin überträgt ihr Tunnel
  nichts. Der Helper erneuert höchstens im Abstand von 10 Minuten, daher kann nach einem Neustart ein
  Gerät bis zu 10 Minuten abgeschnitten sein. Ein erneutes Verbinden stellt es sofort
  wieder her.
- der Server in **v0.1.0** lässt diese Peers auf `wg0`: Er entfernt sie nie, und
  er kann ihre Adressen an neue Geräte vergeben (WireGuard leitet die
  Adresse dann an den neuen Peer). Leeren Sie nach seinem Neustart die Peers
  (`wg-quick down wg0 && wg-quick up wg0` oder `wg set … remove`) und lassen Sie die
  Geräte sich erneut verbinden.

Für mehrere Gateways oder einen dauerhaften Audit-Trail benötigen die Pakete `store`, `ipam` und
`tenant` eine Datenbank dahinter.

## Identitätsanbieter {#identity-provider}

Standardmäßig meldet Claimward Personen mit **GitHub** an (Device Flow): Legen Sie eine
GitHub-OAuth-App mit aktiviertem **Device Flow** an und beschränken Sie den Zugang mit
`GITHUB_ALLOWED_ORGS`. Für **OIDC** setzen Sie `AUTH_PROVIDER=oidc` mit einem
nativen/öffentlichen PKCE-Client und beschränken mit `OIDC_ALLOWED_DOMAINS`. Für
**go-authn** setzen Sie `AUTH_PROVIDER=go-authn` mit dem eigenen Client des Gateways: Der
Anbieter entscheidet dann, welche Schlüssel sich verbinden dürfen, und ein Gateway, das
seine Liste nicht abrufen kann, lässt niemanden Neues zu. Siehe
[Identitätsanbieter]({{< relref "/identity-providers.md" >}}).

## Admin-API und WebUI {#admin-api-and-webui}

Wenn `ADMIN_TOKEN` gesetzt ist, stellt der Server eine eingebettete Svelte-WebUI unter
`/admin/` und eine API unter `/admin/api/` bereit, geschützt durch
`Authorization: Bearer <ADMIN_TOKEN>` (in konstanter Zeit verglichen). Ohne es
antwortet `/admin/` mit `503`. Die Dateien der WebUI werden ohne Authentifizierung ausgeliefert;
sie fragt nach dem Token und sendet es bei jedem Aufruf mit.

| Methode & Pfad | |
|---|---|
| `GET /admin/api/overview` | Anzahlen `{"tenants", "peers", "watchers"}` |
| `GET /admin/api/tenants` | alle Mandanten |
| `POST /admin/api/tenants` | einen anlegen: `id` (oder ein Slug von `name`), `name`, `domains`, `groups`, `idps`, `allowed_ips`, `dns` |
| `GET /admin/api/tenants/{id}` | ein Mandant |
| `PUT /admin/api/tenants/{id}` | ersetzt seinen Namen, seine Mitgliedschaftslisten und Routen; erhöht `serial` und pusht die Routen an seine Beobachter |
| `DELETE /admin/api/tenants/{id}` | löscht ihn (nicht `default`); beendet seine Beobachtungen |

Stellen Sie `/admin/` nur dort bereit, wo Administratoren es erreichen: Das Token ist ein statisches
gemeinsames Geheimnis.

## Metriken {#metrics}

`GET /metrics` liefert Prometheus-Metriken aus, ohne Authentifizierung:

| Metrik | |
|---|---|
| `claimward_enrollments_total{tenant}` | erfolgreiche Registrierungen |
| `claimward_active_peers` | registrierte Peers |
| `claimward_tenants` | konfigurierte Mandanten |
| `claimward_route_watchers` | aktive Beobachtungen des RouteService |
| `claimward_tenant_route_serial{tenant}` | die Routen-Seriennummer jedes Mandanten |
