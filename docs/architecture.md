# Architecture

Claimward separates a **control plane** (the server) from the **data plane** (the
WireGuard tunnel between a device and the gateway). Authentication is delegated to
your OIDC identity provider; Claimward never sees the user's password.

## End-to-end enrollment flow

```text
 ┌──────────┐  1. OIDC Authorization Code + PKCE (browser)   ┌──────────┐
 │  client  │ ─────────────────────────────────────────────▶│   IdP    │
 │ (app/CLI)│◀──────────────── id_token ─────────────────────│  (OIDC)  │
 └────┬─────┘                                                 └──────────┘
      │ 2. POST /api/v1/enroll
      │    Authorization: Bearer <id_token>
      │    { public_key, device }
      ▼
 ┌─────────────────────────┐  3. verify token (issuer discovery)
 │  claimward-vpn-server   │     allocate IP from pool
 │  (on the gateway host)  │     wgctrl: add peer (AllowedIPs = clientIP/32)
 └────┬────────────────────┘
      │ 4. { assigned_ip, server_public_key, endpoint, allowed_ips, dns }
      ▼
 ┌──────────┐  5. wireguard-go creates utunN, configures peer
 │  client  │ ════════════════ WireGuard tunnel ════════════════▶ private network
 └──────────┘
```

1. The client signs in with the configured provider — **GitHub** by default
   (OAuth device flow) or any **OIDC** issuer (PKCE) — and receives a bearer
   credential (a GitHub access token or an OIDC ID token).
2. It generates (once) a WireGuard key pair and calls `POST /api/v1/enroll`,
   sending its **public key** with that bearer.
3. The server **verifies** the bearer (GitHub API call or OIDC verification),
   applies any org/email allowlist, **allocates** a VPN address, and **programs
   the gateway** (`wgctrl`) with a peer whose only allowed IP is that `/32`.
4. The server returns the tunnel parameters (assigned IP, its own public key,
   the public endpoint, routes, DNS, keepalive).
5. The client brings up a userspace tunnel with `wireguard-go`.

## Leases & heartbeats

Each enrollment carries a **lease** (`LEASE_TTL`, default 24h). Clients
`POST /api/v1/heartbeat` to renew. A background reaper on the server removes
peers whose lease expired, so lost or revoked devices fall off the gateway
automatically. `POST /api/v1/deregister` removes a peer immediately.

## Trust boundaries

- The **server** is the only component that talks to the IdP for verification and
  the only one with rights to change the gateway's peer set.
- On the desktop, tunnel setup needs root, so it is isolated in a small
  **privileged helper**; the UI app itself is unprivileged.
- The wire contract lives in one place —
  [`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
  — and is imported by both client and server so they cannot drift.
