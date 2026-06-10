# Operations

Notes for running Claimward in production.

## TLS

The server speaks plain HTTP unless `TLS_CERT`/`TLS_KEY` are set. Because ID
tokens are bearer credentials, **always** put it behind TLS — directly or via a
reverse proxy (nginx, Caddy, a load balancer).

## Gateway

- Bring up `wg0` with `wg-quick`/systemd-networkd at boot; Claimward only manages
  peers. Run the server as the same root context that can `wgctrl`-configure the
  device (typically root, or with `CAP_NET_ADMIN`).
- Enable `net.ipv4.ip_forward` (and configure NAT/firewall) if clients route
  beyond the VPN subnet.

## Leases

Set `LEASE_TTL` to balance security and chattiness. Clients heartbeat to renew;
the reaper removes expired peers every minute, so revoked or offline devices drop
off automatically. To force-revoke now, deregister the peer (or remove it with
`wg set wg0 peer <key> remove`).

## State

The MVP server keeps peer/IP state **in memory** — a restart clears it, and
clients simply re-enroll on their next heartbeat. For multiple gateways or
durable audit, back the `store` and `ipam` packages with a database.

## Identity provider

Register Claimward as a **native/public** OIDC client with PKCE and the loopback
redirect. Use `OIDC_ALLOWED_DOMAINS` to restrict access to your organization's
email domains, or add group/claim checks in `internal/auth`.
