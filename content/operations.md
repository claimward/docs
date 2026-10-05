---
title: "Operations"
weight: 70
description: "Running Claimward in production: TLS, the gateway, leases, what a restart forgets, the identity provider, the admin API and metrics."
tags: [server, operations, wireguard, grpc]
---

## TLS

The server speaks plain HTTP unless `TLS_CERT`/`TLS_KEY` are set. Bearer tokens
are credentials, so **always** put the API behind TLS, directly or through a
reverse proxy (nginx, Caddy, a load balancer).

The same certificate serves the gRPC RouteService. A route watch carries the
bearer token, and the clients refuse a plaintext watch except on loopback: a
server without `TLS_CERT`/`TLS_KEY` (for instance behind a proxy that only
terminates HTTPS) enrolls devices, but they get no live route updates, and it
logs a warning at start-up. Set `GRPC_ENDPOINT` to the `host:port` the devices
reach the RouteService at, with a name the certificate covers.

## Gateway

- Bring up `wg0` with `wg-quick` or systemd-networkd at boot; Claimward only
  manages its peers. Run the server with the rights to configure the interface
  (root, or `CAP_NET_ADMIN`).
- Enable `net.ipv4.ip_forward`, and NAT or firewall rules, if clients route
  beyond the VPN subnet.
- `GET /healthz` is the liveness probe.

## Leases

`LEASE_TTL` (24 hours by default) balances security and churn. The reaper
removes expired peers every minute, so revoked or offline devices drop off on
their own. To revoke one now, deregister its peer, or remove it with
`wg set wg0 peer <key> remove`.

From claimward-vpn-client v0.3.1 (the apps from v0.2.0), the helper renews
the lease while the tunnel is up, at half of what is left (between 30 seconds
and 10 minutes), and deregisters on *Disconnect*. A shorter `LEASE_TTL` therefore
costs more heartbeats, not dropped tunnels: a removal from a tenant, or a key
the go-authn provider takes back, ends the tunnel at the next renewal (the
server answers `403`). A server that has forgotten a device (`404`) gets it
enrolled again. See [Leases]({{< relref "/architecture.md#leases" >}}).

The v0.1.0 apps renew only by connecting again, and leave the peer until its
lease ends after *Disconnect*: with them, a device that stays connected longer
than `LEASE_TTL` loses its tunnel when its peer is reaped.

## State

The server keeps the enrolled peers, the address pool and the tenants
**in memory**. A restart forgets them:

- the tenants are back to `default` alone, from `PUSH_ROUTES` and `DNS`;
- from server **v0.2.0**, the peers a previous run left on `wg0` are
  **removed at startup**: every peer whose only allowed IP is a `/32` inside
  `VPN_CIDR`, the shape the server gives every peer. Any other peer
  (configured by hand, a site-to-site link) is left alone. Kept, those peers
  would be nobody's: never reaped, never checked against the provider's list,
  so a person disabled before the restart would keep a working tunnel. Devices
  find themselves unknown at their next lease renewal and enroll again (apps
  built on claimward-vpn-client v0.3.1); until then their tunnel carries
  nothing. The helper renews at most 10 minutes apart, so after a restart a
  device can be cut off for up to 10 minutes. Reconnecting brings it back at
  once.
- the **v0.1.0** server leaves those peers on `wg0`: it never reaps them, and
  it may hand their addresses to new devices (WireGuard then routes the
  address to the new peer). After restarting it, flush the peers
  (`wg-quick down wg0 && wg-quick up wg0`, or `wg set … remove`) and have
  devices connect again.

For several gateways or a durable audit trail, the `store`, `ipam` and
`tenant` packages need a database behind them.

## Identity provider

By default Claimward signs people in with **GitHub** (device flow): create a
GitHub OAuth App with **Device Flow** enabled and restrict access with
`GITHUB_ALLOWED_ORGS`. For **OIDC**, set `AUTH_PROVIDER=oidc` with a
native/public PKCE client, and restrict with `OIDC_ALLOWED_DOMAINS`. For
**go-authn**, set `AUTH_PROVIDER=go-authn` with the gateway's own client: the
provider then decides which keys may connect, and a gateway that cannot fetch
its list admits nobody new. See
[Identity providers]({{< relref "/identity-providers.md" >}}).

## Admin API and WebUI

With `ADMIN_TOKEN` set, the server serves an embedded Svelte WebUI at
`/admin/` and an API under `/admin/api/`, guarded by
`Authorization: Bearer <ADMIN_TOKEN>` (compared in constant time). Without it,
`/admin/` answers `503`. The WebUI's files are served without authentication;
it asks for the token and sends it with each call.

| Method & path | |
|---|---|
| `GET /admin/api/overview` | `{"tenants", "peers", "watchers"}` counts |
| `GET /admin/api/tenants` | every tenant |
| `POST /admin/api/tenants` | create one: `id` (or a slug of `name`), `name`, `domains`, `groups`, `idps`, `allowed_ips`, `dns` |
| `GET /admin/api/tenants/{id}` | one tenant |
| `PUT /admin/api/tenants/{id}` | replace its name, membership lists and routes; bumps `serial` and pushes the routes to its watchers |
| `DELETE /admin/api/tenants/{id}` | delete it (not `default`); ends its watches |

Serve `/admin/` only where administrators reach it: the token is a static
shared secret.

## Metrics

`GET /metrics` serves Prometheus metrics, without authentication:

| Metric | |
|---|---|
| `claimward_enrollments_total{tenant}` | successful enrollments |
| `claimward_active_peers` | enrolled peers |
| `claimward_tenants` | configured tenants |
| `claimward_route_watchers` | active RouteService watches |
| `claimward_tenant_route_serial{tenant}` | each tenant's route serial |
