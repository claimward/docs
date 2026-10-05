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
(`AUTH_PROVIDER=github`), ein **OIDC-ID-Token** (`oidc`) oder ein
**go-authn-Access-Token** (`go-authn`). Anfrage-Bodys sind JSON, höchstens
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
(`GRPC_ENDPOINT`). Das Protokoll kennt außerdem ein optionales `mtu`, das der Server
(v0.2.0) nie setzt.

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

## Fehler {#errors}

Antworten außerhalb von 2xx tragen:

```json
{ "error": "invalid_token", "message": "…" }
```

| Code | Status | Bedeutung |
|------|--------|---------|
| `missing_token` / `invalid_token` | 401 | kein Bearer-Token, oder die Prüfung durch den Anbieter ist fehlgeschlagen (einschließlich einer Allowlist für Organisationen oder Domains) |
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
`authorization: Bearer <token>`, und wie bei der HTTP-API geprüft. `Watch`
sendet sofort die aktuelle Menge, dann jedes Mal eine neue, wenn sich die Routen des Mandanten
ändern, für den Mandanten, **in den sich das Gerät registriert hat**, ermittelt über `public_key`,
der vom Aufrufer registriert sein muss (andernfalls `NOT_FOUND`,
`PERMISSION_DENIED`, sobald die Person diesen Mandanten verlassen hat).

Der Server stellt ihn mit `TLS_CERT`/`TLS_KEY` über TLS bereit. Die Clients
(`pkg/routeclient`) sprechen TLS mit ihm, geprüft gegen die Stammzertifikate des Systems,
außer zu einer Loopback-Adresse, und lehnen einen unverschlüsselten ab.
