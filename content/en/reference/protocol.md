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
token** (a `github` provider), an **OIDC ID token** (`oidc`), or a
**go-authn access token** (`go-authn`). Since server v0.14.0 the request also
names the provider that issued it, in the header **`Claimward-Provider: <id>`**
(gRPC: the metadata `claimward-provider`), an `id` from the discovery
document's `providers`. The token is judged by that provider alone. No header
is `401 missing_provider`; an id the server does not list, or several ids, is
`401 unknown_provider`. Request bodies are JSON, at most
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
(`GRPC_ENDPOINT`). `mtu` is the tunnel MTU in bytes (an integer,
1280 to 9000), left out when the server has none to advertise. Since server v0.7.0 it is always
set: `TUNNEL_MTU`, or the uplink MTU minus 80 (at most 1420). The client applies it, then lowers
it to fit its own path (the interface MTU towards the endpoint minus 60 for IPv4, 80 for IPv6,
never below 1280); it never raises it. Absent means 1420.

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

## `GET /.well-known/claimward-configuration` {#discovery}

The public discovery document (since server v0.13.0), unauthenticated, so that
a client can learn how to sign in before it does. The path follows
[RFC 8615](https://www.rfc-editor.org/rfc/rfc8615) section 3; a claim without a
value is omitted, as in [RFC 8414](https://www.rfc-editor.org/rfc/rfc8414)
section 3.2. Public values only, never a secret. Response `200`,
`application/json`, `Cache-Control: public, max-age=300`; any other method is
refused with `405`.

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

Version 2 (server v0.14.0, **breaking**) replaces the single `provider` and its
fields of version 1 by the list `providers`, one entry per provider of
`PROVIDERS_FILE`, in file order: `id` (what the client sends in
`Claimward-Provider`), `kind` (`github`, `oidc` or `go-authn`), `name` (shown
to the person), then `github_client_id` for `github`, `oidc_issuer` and
`oidc_client_id` for `oidc` and `go-authn`. A client of version 0.10.0 or later
reads it; it refuses a document of a version it does not know.
`server_name` appears only when `SERVER_NAME` is set, `logo` only when
`SERVER_LOGO_FILE` is. `exclusive` is `SERVER_EXCLUSIVE`: this server refuses
to share the machine with other Claimward tunnels, clients refuse to connect it
alongside others, and refuse others while it is connected.

## `GET /.well-known/claimward-logo.svg` {#logo}

The server's logo (since server v0.14.0), unauthenticated, present only when
`SERVER_LOGO_FILE` is set; otherwise `404`. The discovery document's `logo`
gives its `path` and the `sha256` (hex) of its bytes, so a client can cache it
and notice a change. Response `200`: `Content-Type: image/svg+xml`,
`X-Content-Type-Options: nosniff`,
`Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; sandbox`,
and `ETag` set to the same hash; a request with a matching `If-None-Match` gets
`304`. The server validates the file at start (at most 64 KiB, no script, no
external reference, no DOCTYPE) and refuses to start on an invalid one. A
client must still treat it as untrusted and render it as an image, never inline.

## Errors

Non-2xx responses carry:

```json
{ "error": "invalid_token", "message": "…" }
```

| Code | Status | Meaning |
|------|--------|---------|
| `missing_token` / `invalid_token` | 401 | no bearer, or the provider's verification failed (including an organisation or domain allowlist) |
| `missing_provider` | 401 | no `Claimward-Provider` header (since v0.14.0) |
| `unknown_provider` | 401 | the header names a provider the server does not list, or several (since v0.14.0) |
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
`authorization: Bearer <token>`, with the provider in `claimward-provider`, and
is verified as for the HTTP API (`UNAUTHENTICATED` when either is wrong). `Watch`
sends the current set at once, then a new one each time the tenant's routes
change, for the tenant **the device enrolled into**, found by `public_key`,
which must be enrolled by the caller (`NOT_FOUND` otherwise,
`PERMISSION_DENIED` once the person has left that tenant).

The server serves it over TLS with `TLS_CERT`/`TLS_KEY`. The clients
(`pkg/routeclient`) speak TLS to it, checked against the system's roots,
except to a loopback address, and refuse a plaintext one.
