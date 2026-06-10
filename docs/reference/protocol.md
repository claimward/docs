# Enrollment protocol

The wire contract between clients and the server. It is defined once in
[`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
and imported by both sides.

All authenticated requests send the OIDC ID token as
`Authorization: Bearer <id_token>` — never in the body.

## `POST /api/v1/enroll`

Request:

```json
{
  "public_key": "<wireguard base64 public key>",
  "device": { "name": "alice-mbp", "os": "darwin", "platform": "app-osx" }
}
```

Response `200`:

```json
{
  "assigned_ip": "10.80.0.5/32",
  "server_public_key": "<base64>",
  "endpoint": "vpn.example.com:51820",
  "allowed_ips": ["10.80.0.0/24"],
  "dns": ["10.80.0.1"],
  "persistent_keepalive": 25,
  "mtu": 0,
  "lease_expires_at": "2026-06-11T10:00:00Z"
}
```

## `POST /api/v1/heartbeat`

```json
{ "public_key": "<base64>" }
```

Response `200`: `{ "lease_expires_at": "..." }`. `404` if the key is not enrolled
for the caller.

## `POST /api/v1/deregister`

```json
{ "public_key": "<base64>" }
```

Response `204`. `403` if the key belongs to another user.

## Errors

Non-2xx responses use:

```json
{ "error": "invalid_token", "message": "…" }
```

| Code | Meaning |
|------|---------|
| `missing_token` / `invalid_token` | auth failed (401) |
| `bad_public_key` / `bad_request` | malformed input (400) |
| `pool_exhausted` | no free address (503) |
| `not_enrolled` | unknown peer (404) |
| `not_owner` | key owned by another user (403) |
| `gateway_error` | could not program WireGuard (500) |
