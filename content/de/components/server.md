---
title: "Server"
linkTitle: "Server"
weight: 1
description: "claimward-vpn-server: prüft die Anmeldung, vergibt VPN-Adressen, programmiert das WireGuard-Gateway, streamt die Routen der Mandanten über gRPC und stellt eine Admin-API und Metriken bereit."
tags: [server, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.2.0** ist die Steuerungsebene. Er prüft das Bearer-Token, das ein Gerät vorlegt,
vergibt VPN-Adressen und programmiert das WireGuard-Gateway mit einem Peer pro
registriertem Gerät. Er läuft auf dem Linux-Gateway-Host, neben einem vorhandenen `wg0`.

## Was er bereitstellt {#what-it-serves}

| Listener | Pfad | Zweck |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | prüfen, den Mandanten wählen, eine Adresse vergeben, den Peer hinzufügen, die Tunnelkonfiguration zurückgeben |
| | `GET /api/v1/tenants` | die Mandanten, mit denen sich der Aufrufer verbinden darf |
| | `POST /api/v1/heartbeat` | die Lease des Geräts erneuern |
| | `POST /api/v1/deregister` | den Peer entfernen |
| | `GET /healthz` | Liveness |
| | `GET /metrics` | Prometheus-Metriken |
| | `/admin/` | Admin-API und WebUI, wenn `ADMIN_TOKEN` gesetzt ist |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | streamt die Routen des Mandanten und ihre Aktualisierungen |

Die API-Anfragen tragen `Authorization: Bearer <token>`: ein GitHub-Access-Token,
ein OIDC-ID-Token oder ein go-authn-Access-Token, je nach `AUTH_PROVIDER`.
Die Nutzdaten sind im
[Registrierungsprotokoll]({{< relref "/reference/protocol.md" >}})
beschrieben.

Mit `TLS_CERT` und `TLS_KEY` verwenden beide Listener TLS. Ohne sie ist die HTTP-API
unverschlüsselt (terminieren Sie TLS an einem Proxy), ebenso der RouteService, den die
Clients dann ablehnen, außer über Loopback: Geräte verbinden sich, erhalten aber keine Live-Aktualisierungen
der Routen.

## Konfiguration {#configuration}

Die gesamte Konfiguration erfolgt über die Umgebung.

| Variable | Erforderlich | Standard | Hinweise |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | Identitätsanbieter: `github`, `oidc` oder `go-authn` |
| `GITHUB_ALLOWED_ORGS` | | — | CSV-Allowlist der Organisationen (`github`): Ein aktives Mitglied einer davon wird zugelassen |
| `GITHUB_API_URL` | | `https://api.github.com` | für GitHub Enterprise zu setzen |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | URL des Issuers (Discovery) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | die Audience, die Tokens tragen müssen |
| `OIDC_ALLOWED_DOMAINS` | | — | CSV-Allowlist der E-Mail-Domains (`oidc`) |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | der eigene Client des Gateways beim Anbieter (`wireguard_peers`) |
| `GOAUTHN_GATEWAY_SECRET_FILE` | `go-authn` | — | sein Secret, **nur aus einer Datei** |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | wie oft die Liste der registrierten Schlüssel abgerufen wird |
| `GOAUTHN_SSF` | | `false` | zusätzlich den Shared-Signals-Stream des Anbieters abfragen, damit auf eine Deaktivierung sofort reagiert wird; der Client des Gateways muss dort SSF-Empfänger sein |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | wie oft der SSF-Stream abgefragt wird |
| `WG_ENDPOINT` | ✅ | — | öffentlicher `host:port` des Gateways, den Clients mitgeteilt |
| `WG_PRIVATE_KEY` / `WG_PRIVATE_KEY_FILE` | ✅ | — | der private Schlüssel des Gateways in Base64 (die Variable hat Vorrang vor der Datei) |
| `WG_INTERFACE` | | `wg0` | zu verwaltende Schnittstelle |
| `WG_DRYRUN` | | `false` | Peer-Operationen protokollieren statt sie anzuwenden (lokale Entwicklung) |
| `VPN_CIDR` | | `10.80.0.0/24` | IPv4-Adresspool; sein erster Host ist der des Gateways |
| `PUSH_ROUTES` | | `VPN_CIDR` | CSV-Routen des Mandanten `default` |
| `DNS` | | — | CSV-DNS-Server des Mandanten `default` |
| `KEEPALIVE` | | `25` | den Clients mitgeteiltes Persistent Keepalive (Sekunden) |
| `LEASE_TTL` | | `24h` | wie lange eine Registrierung ohne Heartbeat gilt |
| `LISTEN_ADDR` | | `:8443` | HTTP-Listen-Adresse |
| `GRPC_ADDR` | | `:8444` | Listen-Adresse des RouteService |
| `GRPC_ENDPOINT` | | — | den Clients mitgeteilter `host:port` des RouteService; ist er leer, beobachten sie nicht |
| `ADMIN_TOKEN` | | — | Bearer-Token für die Admin-API und die WebUI; leer deaktiviert sie |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS und TLS auf dem RouteService |
| `DEBUG` | | — | beliebiger Wert: Debug-Protokollierung (eine Zeile pro Anfrage) |

## Authentifizierungsanbieter {#authentication-providers}

Die Authentifizierung ist hinter der Schnittstelle `Verifier` austauschbar
(`internal/auth`):

- **`github`** (Standard): Das Bearer-Token ist ein GitHub-OAuth-Access-Token aus dem
  Device Flow. Der Server löst es über die GitHub-API auf (`/user`,
  `/user/orgs`) und verlangt mit `GITHUB_ALLOWED_ORGS` eine aktive Mitgliedschaft
  in einer dieser Organisationen. Es ist kein Client-Secret beteiligt.
- **`oidc`**: Das Bearer-Token ist ein OIDC-ID-Token, geprüft gegen den Issuer mit
  der Audience `OIDC_CLIENT_ID` und der optionalen Allowlist der E-Mail-Domains.
- **`go-authn`**: Das Bearer-Token ist ein Access-Token (`at+jwt`) eines
  [go-authn/bridge](https://github.com/go-authn/bridge)-Anbieters, und der
  Schlüssel des Geräts muss dort von derselben Person registriert sein. Der Server liest
  die signierte Liste der registrierten Schlüssel des Anbieters
  ([go-authn/wireguard](https://github.com/go-authn/wireguard)) und entfernt aus
  `wg0` einen Schlüssel, den der Anbieter zurückzieht.

Jeden Ablauf von Ende zu Ende finden Sie unter
[Identitätsanbieter]({{< relref "/identity-providers.md" >}}).

## Registrierungsregeln {#enrollment-rules}

- **Ein Schlüssel gehört demjenigen, der ihn registriert hat.** Das Registrieren eines Schlüssels, den eine andere Identität
  hält, wird abgelehnt (`409 key_taken`): Ein öffentlicher Schlüssel ist öffentlich, und ihn zu übernehmen
  gäbe die Macht, das Gerät seines Besitzers abzumelden.
- Derselbe Schlüssel, erneut von seinem Besitzer registriert, behält seine Adresse und erhält eine neue
  Lease.
- Die einzige erlaubte IP des Peers ist das `/32` des Geräts, sodass Geräte die Adressen der jeweils
  anderen nicht verwenden können.
- Der Mandant ist derjenige, den der Aufrufer angefordert hat, sofern er Mitglied ist, oder sein
  einziger. Siehe [Mandanten]({{< relref "/tenants.md" >}}).

## Wie er das Gateway programmiert {#how-it-programs-the-gateway}

Der Server verwendet [`wgctrl`](https://pkg.go.dev/golang.zx2c4.com/wireguard/wgctrl),
um Peers auf einer vorhandenen Schnittstelle hinzuzufügen und zu entfernen, und prüft beim Start, dass
die Schnittstelle existiert. Die Schnittstelle selbst (ihr privater Schlüssel und Listen-Port)
bleibt `wg-quick` oder systemd-networkd beim Booten überlassen, was die privilegierte
Einrichtung der Schnittstelle aus dem dauerhaft laufenden Dienst heraushält.

## Lokal ausführen {#run-locally}

Mit `WG_DRYRUN=true` wird kein WireGuard-Gerät angetastet:

```sh
export AUTH_PROVIDER=oidc
export OIDC_ISSUER=https://accounts.google.com
export OIDC_CLIENT_ID=xxxx.apps.googleusercontent.com
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY=$(wg genkey)
export WG_DRYRUN=true LISTEN_ADDR=:8080

go run ./cmd/claimward-server
```

`task run:dev` tut dasselbe mit GitHub-Anmeldung und einem flüchtigen Schlüssel, und
`task dex` startet ein lokales [Dex](https://dexidp.io/), bei dem man sich anmelden kann
(`deploy/dev/`).

{{< callout type="warning" >}}
**Hinter TLS betreiben.** Bearer-Tokens sind Zugangsdaten: Stellen Sie die API immer über
HTTPS bereit, entweder mit `TLS_CERT`/`TLS_KEY` oder hinter einem Proxy, der TLS terminiert, und
geben Sie dem RouteService ein Zertifikat, damit Geräte Live-Aktualisierungen der Routen erhalten.
{{< /callout >}}
