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
  verwaltet nur seine Peers. Starten Sie den Server mit den Rechten, die Schnittstelle und die Firewall zu
  konfigurieren: unter Linux root oder `CAP_NET_ADMIN` (nftables); unter OpenBSD root,
  für `/dev/pf` (siehe [OpenBSD]({{< relref "/components/server.md#openbsd" >}})).
- Aktivieren Sie unter Linux `net.ipv4.ip_forward` sowie NAT- oder Firewall-Regeln, wenn Clients
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

Seit v0.14.0 liest der Server **einen oder mehrere** Anbieter aus der JSON-Datei,
die `PROVIDERS_FILE` benennt (erforderlich, höchstens 1 MiB). Die alten Variablen
`AUTH_PROVIDER`, `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_ALLOWED_DOMAINS`,
`GITHUB_CLIENT_ID`, `GITHUB_ALLOWED_ORGS` und `GOAUTHN_GATEWAY_CLIENT_ID` werden
beim Start abgelehnt. Ein Anbieter `github` braucht eine GitHub-OAuth-App mit aktiviertem **Device
Flow**, ihr Client-Secret in der Datei `provider-<id>-secret` und `allowed_orgs`,
um den Zugang zu beschränken. Ein Anbieter `oidc` braucht einen nativen/öffentlichen
PKCE-Client, und `allowed_domains` beschränkt ihn. Ein Anbieter `go-authn` nutzt den
eigenen Client des Gateways (`gateway_client_id`, Secret in
`provider-<id>-gateway-secret`): Der Anbieter entscheidet dann, welche Schlüssel sich
verbinden dürfen, und ein Gateway, das seine Liste nicht abrufen kann, lässt niemanden
Neues zu. Jede Anfrage benennt ihren Anbieter im Header `Claimward-Provider`
(`401 missing_provider`, `401 unknown_provider`). `SERVER_LOGO_FILE` veröffentlicht ein
Logo unter `/.well-known/claimward-logo.svg`. Starten Sie den Server nach einer Änderung
der Datei neu. Siehe
[Identitätsanbieter]({{< relref "/identity-providers.md" >}}).

## Admin-API und WebUI {#admin-api-and-webui}

Wenn die Credential `admin-token` vorhanden ist (eine Datei in
`CREDENTIALS_DIRECTORY`, siehe [Credentials]({{< relref "/components/server.md#credentials" >}})),
stellt der Server eine eingebettete Svelte-WebUI unter
`/admin/` und eine API unter `/admin/api/` bereit, geschützt durch
`Authorization: Bearer <Inhalt von admin-token>` (in konstanter Zeit verglichen). Ohne die Datei
antwortet `/admin/` mit `503`. Die Dateien der WebUI werden ohne Authentifizierung ausgeliefert;
sie fragt nach dem Token und sendet es bei jedem Aufruf mit.

| Methode & Pfad | |
|---|---|
| `GET /admin/api/overview` | Anzahlen `{"tenants", "peers", "watchers"}` |
| `GET /admin/api/tenants` | alle Mandanten |
| `POST /admin/api/tenants` | einen anlegen: `id` (oder ein Slug von `name`), `name`, `domains`, `groups`, `idps`, `members` (Logins; `pinned` ist schreibgeschützt, `400`, wenn ein Login nicht aufgelöst wird), `allowed_ips`, `dns` |
| `GET /admin/api/tenants/{id}` | ein Mandant |
| `PUT /admin/api/tenants/{id}` | ersetzt seinen Namen, seine Mitgliedschaftslisten und Routen; erhöht `serial` und pusht die Routen an seine Beobachter |
| `DELETE /admin/api/tenants/{id}` | löscht ihn (nicht `default`); beendet seine Beobachtungen |

Stellen Sie `/admin/` nur dort bereit, wo Administratoren es erreichen: Das Token ist ein statisches
gemeinsames Geheimnis.

## Metriken {#metrics}

`GET /metrics` liefert Prometheus-Metriken aus, ohne Authentifizierung, auf einem
eigenen Listener: `METRICS_ADDR`, die keinen Standardwert hat, es gibt also keine
Metriken, solange sie nicht gesetzt ist (nie auf dem Registrierungsport). Sie nennen
jeden Mandanten: halten Sie diesen Listener auf Loopback oder in einem privaten Netz.

| Metrik | |
|---|---|
| `claimward_enrollments_total{tenant}` | erfolgreiche Registrierungen |
| `claimward_active_peers` | registrierte Peers |
| `claimward_tenants` | konfigurierte Mandanten |
| `claimward_route_watchers` | aktive Beobachtungen des RouteService |
| `claimward_tenant_route_serial{tenant}` | die Routen-Seriennummer jedes Mandanten |
