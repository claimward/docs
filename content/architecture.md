---
title: "Architecture"
weight: 20
description: "A control plane that verifies the sign-in and programs the gateway, a data plane that is plain WireGuard, and a privileged helper on each device between the two."
tags: [wireguard, server, helper, grpc]
---

Claimward separates a **control plane**, the server, from the **data plane**,
the WireGuard tunnel between a device and the gateway. Authentication is
delegated to your identity provider: Claimward never sees a password.

On a device, an unprivileged **app** signs the person in and keeps the
session; a **privileged helper** (root, or SYSTEM on Windows) enrolls with the
server and owns the tunnel. The app never talks to the server itself.

## End-to-end enrollment flow

```text
 ┌──────────┐ 1. sign-in: GitHub device flow, OIDC code + PKCE,  ┌──────────┐
 │   app    │    or go-authn device flow (+ key registration)    │   IdP    │
 │ (as you) │◀─────────────────── bearer token ──────────────────│          │
 └────┬─────┘                                                    └──────────┘
      │ 2. socket: connect {server_url, bearer, private key, tenant}
      ▼
 ┌──────────┐ 3. POST /api/v1/enroll                ┌─────────────────────────┐
 │  helper  │    Authorization: Bearer <token>      │  claimward-vpn-server   │
 │ (root)   │    {public_key, device, tenant}  ───▶ │  verify the bearer      │
 │          │                                       │  choose the tenant      │
 │          │ ◀─── 4. {assigned_ip,                 │  allocate an address    │
 │          │       server_public_key, endpoint,    │  wgctrl: add the peer   │
 │          │       allowed_ips, dns,               │  (AllowedIPs = ip/32)   │
 │          │       grpc_endpoint, keepalive,       └───────────┬─────────────┘
 │          │       lease_expires_at}                           │ RouteService
 │          │ ◀═════════════ 6. gRPC Watch (TLS) ═══════════════╛ (live routes)
 │          │
 │          │ 5. wireguard-go: utunN / Wintun "Claimward", address, routes
 └────┬─────┘
      ╚═══════════════════ WireGuard tunnel ════════════════════▶ private network
```

1. The app signs the person in with the configured provider: **GitHub** by
   default (OAuth device flow), any **OpenID Connect** issuer (authorization
   code with PKCE, in the browser), or a **go-authn** provider (device flow).
   The bearer it gets is a GitHub access token, an OIDC ID token, or a go-authn
   access token. With go-authn, the device's **public** key is first
   registered at the provider, and the bearer is the token that registration
   returns.
2. The app generates the device's WireGuard key pair at the first sign-in and
   keeps it in its session file until the person signs out, so the device
   keeps its public key across connections (and its address while it is enrolled). To connect, it hands the helper the server URL, the bearer, the
   private key and the tenant chosen for the session, over the helper's socket.
3. The helper checks that the server is **one its own configuration names**,
   then calls `POST /api/v1/enroll` with the device's public key and the
   bearer.
4. The server **verifies** the bearer (a GitHub API call, an OIDC ID token, or
   a go-authn access token whose subject must own the key), applies any
   organisation or email-domain allowlist, picks the **tenant**, **allocates** a
   VPN address and **programs the gateway** (`wgctrl`) with a peer whose only
   allowed IP is that `/32`. It answers with the tunnel parameters: the address,
   its own public key, the endpoint, the tenant's routes and DNS servers, the
   keepalive, the RouteService endpoint and the lease's end.
5. The helper brings up a userspace tunnel with `wireguard-go`, gives the
   interface its address and installs the routes.
6. When the server advertises a RouteService (`GRPC_ENDPOINT`), the helper
   watches it over gRPC: route changes made to the tenant reach the device
   without enrolling again.

## Leases

Each enrollment carries a **lease** of `LEASE_TTL` (24 hours by default). A
background reaper on the server removes, every minute, the peers whose lease
has ended, so a lost or revoked device falls off the gateway on its own. With
go-authn a lease never outlives the key's registration at the provider.

The server renews a lease on `POST /api/v1/heartbeat`, and removes a peer at
once on `POST /api/v1/deregister`. **The v0.1.0 apps call neither**: they
renew a lease by connecting again, which enrolls again, and a *Disconnect*
takes the tunnel down on the device while the peer stays on the gateway until
its lease ends. A tunnel kept up past its lease stops carrying traffic when the
reaper removes the peer; connecting again fixes it.

## Trust boundaries

- The **server** is the only component that talks to the identity provider to
  verify a sign-in, and the only one with rights to change the gateway's peers.
- On the device, the **helper** is the only privileged process. Anything that
  can reach its socket can ask it to act, so it acts within its own
  configuration: it enrolls only with the servers that configuration names and
  takes no tunnel configuration from a request. See
  [Privileged helper]({{< relref "/components/helper.md" >}}).
- The **app** runs as the person. It holds the session (bearer token and device
  key) in a `0600` file in their configuration directory.
- A route watch carries the bearer token, so it runs over **TLS** except to a
  loopback address.
- The wire contract lives in one place,
  [`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
  and `pkg/routespb`, imported by both the clients and the server.
