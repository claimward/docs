---
title: "Enrollment protocol"
linkTitle: "Enrollment protocol"
weight: 1
description: "The HTTP API between a device's helper and claimward-vpn-server, its errors, and the gRPC RouteService."
tags: [protocol, server, grpc]
---

The wire contract between the clients and the server. It is defined once in
[`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
(HTTP) and `proto/routes/v1/routes.proto` (gRPC), and imported by both sides.

Every authenticated request sends the person's bearer as
`Authorization: Bearer <token>`, never in the body: a **GitHub OAuth access
token** (`AUTH_PROVIDER=github`), an **OIDC ID token** (`oidc`), or a
**go-authn access token** (`go-authn`). Request bodies are JSON, at most
64 KiB, and unknown fields are refused.

## `POST /api/v1/enroll`

Request:

```json
{
  "public_key": "<wireguard base64 public key>",
  "device": { "name": "alice-mbp", "os": "darwin", "platform": "app-osx" },
  "tenant": "hpc"
}
```

`tenant` is optional: without it the server uses the person's only tenant.
The helpers send `os` `darwin`, `linux` or `windows` and `platform`
`app-osx`, `app-linux` or `app-windows`.

Response `200`:

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

`allowed_ips` and `dns` are the tenant's. `dns` is left out when the tenant has
none, `grpc_endpoint` when the server advertises no RouteService
(`GRPC_ENDPOINT`). The protocol also has an optional `mtu`, which the v0.1.0
server never sets.

## `GET /api/v1/tenants`

Response `200`: the tenants the caller may connect to.

```json
[ { "id": "default", "name": "Default" } ]
```

## `POST /api/v1/heartbeat`

```json
{ "public_key": "<base64>" }
```

Response `200`: `{ "lease_expires_at": "..." }`. `404 not_enrolled` if the key
is not enrolled by the caller, `403 not_a_member` once the person has left the
session's tenant, `403 key_not_registered` (go-authn) once the provider no
longer lists the key.

## `POST /api/v1/deregister`

```json
{ "public_key": "<base64>" }
```

Response `204`, also for a key that is not enrolled. `403 not_owner` if the key
belongs to another person.

## `GET /healthz`

Response `200`: `{ "status": "ok" }`, unauthenticated.

## Errors

Non-2xx responses carry:

```json
{ "error": "invalid_token", "message": "…" }
```

| Code | Status | Meaning |
|------|--------|---------|
| `missing_token` / `invalid_token` | 401 | no bearer, or the provider's verification failed (including an organisation or domain allowlist) |
| `bad_public_key` / `bad_request` | 400 | malformed input |
| `key_not_registered` | 403 | go-authn: the key is not registered at the provider by this person |
| `not_a_member` | 403 | the tenant asked for is not one of the caller's, or no longer is |
| `not_owner` | 403 | deregister: the key belongs to another person |
| `not_enrolled` | 404 | heartbeat: no enrollment of this key by the caller |
| `key_taken` | 409 | enroll: the key is enrolled by another person |
| `tenant_required` | 409 | enroll: the caller belongs to several tenants and named none; the message lists them |
| `pool_exhausted` | 503 | no free address in `VPN_CIDR` |
| `gateway_error` | 500 | the peer could not be added to WireGuard |

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

The server listens on `GRPC_ADDR` and advertises `GRPC_ENDPOINT` in the
enrollment response. The bearer travels in the metadata,
`authorization: Bearer <token>`, and is verified as for the HTTP API. `Watch`
sends the current set at once, then a new one each time the tenant's routes
change, for the tenant **the device enrolled into**, found by `public_key`,
which must be enrolled by the caller (`NOT_FOUND` otherwise,
`PERMISSION_DENIED` once the person has left that tenant).

The server serves it over TLS with `TLS_CERT`/`TLS_KEY`. The clients
(`pkg/routeclient`) speak TLS to it, checked against the system's roots,
except to a loopback address, and refuse a plaintext one.
