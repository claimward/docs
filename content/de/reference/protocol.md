---
title: "Registrierungsprotokoll"
linkTitle: "Registrierungsprotokoll"
weight: 1
description: "Die HTTP-API zwischen dem Helper eines Geräts und claimward-vpn-server, ihre Fehler und der gRPC-RouteService."
tags: [protokoll, server, grpc]
---

Der Wire-Vertrag zwischen den Clients und dem Server. Er ist einmal definiert, in
[`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
(HTTP) und `proto/routes/v1/routes.proto` (gRPC), und wird von beiden Seiten importiert.

Jede authentifizierte Anfrage sendet das Bearer-Token der Person als
`Authorization: Bearer <token>`, niemals im Body: ein **GitHub-OAuth-Access-Token**
(ein `github`-Anbieter), ein **OIDC-ID-Token** (`oidc`) oder ein
**go-authn-Access-Token** (`go-authn`). Seit Server v0.14.0 nennt die Anfrage auch
den Anbieter, der es ausgestellt hat, im Header **`Claimward-Provider: <id>`**
(gRPC: die Metadaten `claimward-provider`), eine `id` aus den `providers` des
Discovery-Dokuments. Das Token wird von diesem Anbieter allein beurteilt. Kein
Header ist `401 missing_provider`; eine Id, die der Server nicht listet, oder
mehrere Ids sind `401 unknown_provider`. Anfrage-Bodys sind JSON, höchstens
64 KiB, und unbekannte Felder werden abgelehnt.

## `POST /api/v1/enroll`

Anfrage:

```json
{
  "public_key": "<wireguard base64 public key>",
  "device": { "name": "alice-mbp", "os": "darwin", "platform": "app-osx" },
  "tenant": "hpc"
}
```

`tenant` ist optional: Ohne ihn verwendet der Server den einzigen Mandanten der Person.
Die Helper senden als `os` `darwin`, `linux` oder `windows` und als `platform`
`app-osx`, `app-linux` oder `app-windows`.

Antwort `200`:

```json
{
  "assigned_ip": "10.80.0.5/32",
  "server_public_key": "<base64>",
  "endpoint": "vpn.example.com:51820",
  "allowed_ips": ["10.80.0.0/24"],
  "dns": ["10.80.0.1"],
  "grpc_endpoint": "vpn.example.com:8444",
  "persistent_keepalive": 25,
  "lease_expires_at": "2026-10-06T10:00:00Z"
}
```

`allowed_ips` und `dns` sind die des Mandanten. `dns` entfällt, wenn der Mandant
keine hat, `grpc_endpoint`, wenn der Server keinen RouteService ankündigt
(`GRPC_ENDPOINT`). `mtu` ist die Tunnel-MTU in Bytes (eine ganze Zahl,
1280 bis 9000) und entfällt, wenn der Server keine anzukündigen hat. Seit Server v0.7.0 ist sie immer
gesetzt: `TUNNEL_MTU` oder die Uplink-MTU minus 80 (höchstens 1420). Der Client wendet sie an und senkt
sie dann auf seinen eigenen Pfad (Schnittstellen-MTU zum Endpunkt minus 60 für IPv4, 80 für IPv6,
nie unter 1280); er erhöht sie nie. Fehlt sie, gilt 1420.

## `GET /api/v1/tenants`

Antwort `200`: die Mandanten, mit denen sich der Aufrufer verbinden darf.

```json
[ { "id": "default", "name": "Default" } ]
```

## `POST /api/v1/heartbeat`

```json
{ "public_key": "<base64>" }
```

Antwort `200`: `{ "lease_expires_at": "..." }`. `404 not_enrolled`, wenn der Schlüssel
nicht vom Aufrufer registriert ist, `403 not_a_member`, sobald die Person den
Mandanten der Sitzung verlassen hat, `403 key_not_registered` (go-authn), sobald der Anbieter
den Schlüssel nicht mehr führt.

## `POST /api/v1/deregister`

```json
{ "public_key": "<base64>" }
```

Antwort `204`, auch für einen Schlüssel, der nicht registriert ist. `403 not_owner`, wenn der Schlüssel
einer anderen Person gehört.

## `GET /healthz`

Antwort `200`: `{ "status": "ok" }`, ohne Authentifizierung.

## `GET /.well-known/claimward-configuration` {#discovery}

Das öffentliche Discovery-Dokument (seit Server v0.13.0), ohne
Authentifizierung, damit ein Client vor der Anmeldung erfährt, wie er sich
anmelden kann. Der Pfad folgt Abschnitt 3 von
[RFC 8615](https://www.rfc-editor.org/rfc/rfc8615); ein Feld ohne Wert wird
weggelassen, wie in Abschnitt 3.2 von
[RFC 8414](https://www.rfc-editor.org/rfc/rfc8414). Nur öffentliche Werte,
niemals ein Geheimnis. Antwort `200`, `application/json`,
`Cache-Control: public, max-age=300`; jede andere Methode wird mit `405`
abgelehnt.

```json
{
  "version": 2,
  "server_name": "Lab",
  "providers": [
    { "id": "hub", "kind": "github", "name": "GitHub", "github_client_id": "Iv1.0123456789abcdef" },
    { "id": "campus", "kind": "oidc", "name": "Campus", "oidc_issuer": "https://idp.example.org", "oidc_client_id": "claimward" }
  ],
  "exclusive": false,
  "logo": { "path": "/.well-known/claimward-logo.svg", "sha256": "<hex>" }
}
```

Version 2 (Server v0.14.0, **inkompatibel**) ersetzt den einzelnen `provider` und
seine Felder aus Version 1 durch die Liste `providers`, ein Eintrag pro Anbieter
aus `PROVIDERS_FILE`, in Dateireihenfolge: `id` (was der Client in
`Claimward-Provider` sendet), `kind` (`github`, `oidc` oder `go-authn`), `name`
(der Person angezeigt), dann `github_client_id` für `github`, `oidc_issuer` und
`oidc_client_id` für `oidc` und `go-authn`. Ein Client ab Version 0.10.0
liest es; ein Dokument einer ihm unbekannten Version lehnt er ab.
`server_name` erscheint nur, wenn `SERVER_NAME` gesetzt ist, `logo` nur, wenn
`SERVER_LOGO_FILE` es ist. `exclusive` ist `SERVER_EXCLUSIVE`: Dieser Server
weigert sich, die Maschine mit anderen Claimward-Tunneln zu teilen; Clients
verbinden ihn nicht neben anderen und lehnen andere ab, solange er verbunden
ist.

## `GET /.well-known/claimward-logo.svg` {#logo}

Das Logo des Servers (seit Server v0.14.0), ohne Authentifizierung, nur vorhanden,
wenn `SERVER_LOGO_FILE` gesetzt ist; andernfalls `404`. Das `logo` des
Discovery-Dokuments nennt seinen `path` und den `sha256` (hex) seiner Bytes, sodass
ein Client es zwischenspeichern und eine Änderung bemerken kann. Antwort `200`:
`Content-Type: image/svg+xml`, `X-Content-Type-Options: nosniff`,
`Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox`,
und `ETag` auf denselben Hash gesetzt; eine Anfrage mit passendem `If-None-Match`
erhält `304`. Der Server prüft die Datei beim Start (höchstens 64 KiB, kein Skript,
keine externe Referenz, kein DOCTYPE) und startet bei einer ungültigen nicht. Ein
Client muss es dennoch als nicht vertrauenswürdig behandeln und als Bild darstellen,
nie inline.

## Fehler {#errors}

Antworten außerhalb von 2xx tragen:

```json
{ "error": "invalid_token", "message": "…" }
```

| Code | Status | Bedeutung |
|------|--------|---------|
| `missing_token` / `invalid_token` | 401 | kein Bearer-Token, oder die Prüfung durch den Anbieter ist fehlgeschlagen (einschließlich einer Allowlist für Organisationen oder Domains) |
| `missing_provider` | 401 | kein Header `Claimward-Provider` (seit v0.14.0) |
| `unknown_provider` | 401 | der Header nennt einen Anbieter, den der Server nicht listet, oder mehrere (seit v0.14.0) |
| `bad_public_key` / `bad_request` | 400 | fehlerhafte Eingabe |
| `key_not_registered` | 403 | go-authn: Der Schlüssel ist beim Anbieter nicht von dieser Person registriert |
| `not_a_member` | 403 | der angeforderte Mandant gehört nicht (oder nicht mehr) zu denen des Aufrufers |
| `not_owner` | 403 | deregister: Der Schlüssel gehört einer anderen Person |
| `not_enrolled` | 404 | heartbeat: keine Registrierung dieses Schlüssels durch den Aufrufer |
| `key_taken` | 409 | enroll: Der Schlüssel ist von einer anderen Person registriert |
| `tenant_required` | 409 | enroll: Der Aufrufer gehört mehreren Mandanten an und hat keinen genannt; die Meldung listet sie auf |
| `pool_exhausted` | 503 | keine freie Adresse in `VPN_CIDR` |
| `gateway_error` | 500 | der Peer konnte nicht zu WireGuard hinzugefügt werden |

## RouteService (gRPC)

```protobuf
package claimward.routes.v1;

service RouteService {
  rpc Watch(WatchRequest) returns (stream RouteUpdate);
}
message WatchRequest { string public_key = 1; }
message RouteUpdate {
  repeated string allowed_ips = 1;
  repeated string dns = 2;
  uint64 serial = 3;   // increases on each change
}
```

Der Server lauscht auf `GRPC_ADDR` und kündigt `GRPC_ENDPOINT` in der
Registrierungsantwort an. Das Bearer-Token wird in den Metadaten übertragen,
`authorization: Bearer <token>`, mit dem Anbieter in `claimward-provider`, und
wie bei der HTTP-API geprüft (`UNAUTHENTICATED`, wenn eines von beiden falsch ist). `Watch`
sendet sofort die aktuelle Menge, dann jedes Mal eine neue, wenn sich die Routen des Mandanten
ändern, für den Mandanten, **in den sich das Gerät registriert hat**, ermittelt über `public_key`,
der vom Aufrufer registriert sein muss (andernfalls `NOT_FOUND`,
`PERMISSION_DENIED`, sobald die Person diesen Mandanten verlassen hat).

Der Server stellt ihn mit `TLS_CERT`/`TLS_KEY` über TLS bereit. Die Clients
(`pkg/routeclient`) sprechen TLS mit ihm, geprüft gegen die Stammzertifikate des Systems,
außer zu einer Loopback-Adresse, und lehnen einen unverschlüsselten ab.
