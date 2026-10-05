---
title: "Server"
linkTitle: "Server"
weight: 1
description: "claimward-vpn-server: verifies the sign-in, allocates VPN addresses, programs the WireGuard gateway, streams tenant routes over gRPC, and serves an admin API and metrics."
tags: [server, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.2.0** is the control plane. It verifies the bearer a device presents,
allocates VPN addresses, and programs the WireGuard gateway with one peer per
enrolled device. It runs on the Linux gateway host, beside an existing `wg0`.

## What it serves

| Listener | Path | Purpose |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | verify, choose the tenant, allocate an address, add the peer, return the tunnel configuration |
| | `GET /api/v1/tenants` | the tenants the caller may connect to |
| | `POST /api/v1/heartbeat` | renew the device's lease |
| | `POST /api/v1/deregister` | remove the peer |
| | `GET /healthz` | liveness |
| | `GET /metrics` | Prometheus metrics |
| | `/admin/` | admin API and WebUI, when `ADMIN_TOKEN` is set |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | streams the tenant's routes and their updates |

The API requests carry `Authorization: Bearer <token>`: a GitHub access token,
an OIDC ID token, or a go-authn access token, depending on `AUTH_PROVIDER`.
See the [enrollment protocol]({{< relref "/reference/protocol.md" >}}) for
the payloads.

With `TLS_CERT` and `TLS_KEY` both listeners use TLS. Without them the HTTP API
is plain (terminate TLS at a proxy), and so is the RouteService, which the
clients then refuse except on loopback: devices connect, but get no live route
updates.

## Configuration

All configuration is in the environment.

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | identity provider: `github`, `oidc` or `go-authn` |
| `GITHUB_ALLOWED_ORGS` | | — | CSV organisation allowlist (`github`): an active member of any is allowed |
| `GITHUB_API_URL` | | `https://api.github.com` | set for GitHub Enterprise |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | issuer URL (discovery) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | the audience tokens must carry |
| `OIDC_ALLOWED_DOMAINS` | | — | CSV email-domain allowlist (`oidc`) |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | the gateway's own client at the provider (`wireguard_peers`) |
| `GOAUTHN_GATEWAY_SECRET_FILE` | `go-authn` | — | its secret, **from a file only** |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | how often the list of registered keys is fetched |
| `GOAUTHN_SSF` | | `false` | also poll the provider's Shared Signals stream, so that a disabling is acted on at once; the gateway's client must be an SSF receiver there |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | how often the SSF stream is polled |
| `WG_ENDPOINT` | ✅ | — | public `host:port` of the gateway, advertised to clients |
| `WG_PRIVATE_KEY` / `WG_PRIVATE_KEY_FILE` | ✅ | — | the gateway's base64 private key (the variable wins over the file) |
| `WG_INTERFACE` | | `wg0` | interface to manage |
| `WG_DRYRUN` | | `false` | log peer operations instead of applying them (local development) |
| `VPN_CIDR` | | `10.80.0.0/24` | IPv4 address pool; its first host is the gateway's |
| `PUSH_ROUTES` | | `VPN_CIDR` | CSV routes of the `default` tenant |
| `DNS` | | — | CSV DNS servers of the `default` tenant |
| `KEEPALIVE` | | `25` | persistent keepalive advertised to clients (seconds) |
| `LEASE_TTL` | | `24h` | how long an enrollment lasts without a heartbeat |
| `LISTEN_ADDR` | | `:8443` | HTTP listen address |
| `GRPC_ADDR` | | `:8444` | RouteService listen address |
| `GRPC_ENDPOINT` | | — | `host:port` of the RouteService advertised to clients; empty, they do not watch |
| `ADMIN_TOKEN` | | — | bearer for the admin API and WebUI; empty disables them |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS, and TLS on the RouteService |
| `DEBUG` | | — | any value: debug logging (one line per request) |

## Authentication providers

Authentication is pluggable behind the `Verifier` interface
(`internal/auth`):

- **`github`** (default): the bearer is a GitHub OAuth access token from the
  device flow. The server resolves it through the GitHub API (`/user`,
  `/user/orgs`) and, with `GITHUB_ALLOWED_ORGS`, requires an active membership
  of one of those organisations. No client secret is involved.
- **`oidc`**: the bearer is an OIDC ID token, verified against the issuer with
  the audience `OIDC_CLIENT_ID` and the optional email-domain allowlist.
- **`go-authn`**: the bearer is an access token (`at+jwt`) from a
  [go-authn/bridge](https://github.com/go-authn/bridge) provider, and the
  device's key must be registered there by the same person. The server reads
  the provider's signed list of registered keys
  ([go-authn/wireguard](https://github.com/go-authn/wireguard)) and drops from
  `wg0` a key the provider takes back.

See [Identity providers]({{< relref "/identity-providers.md" >}}) for each
flow end to end.

## Enrollment rules

- **A key belongs to whoever enrolled it.** Enrolling a key another identity
  holds is refused (`409 key_taken`): a public key is public, and taking one
  over would give the power to deregister its owner's device.
- The same key enrolled again by its owner keeps its address and gets a new
  lease.
- The peer's only allowed IP is the device's `/32`, so devices cannot use each
  other's addresses.
- The tenant is the one the caller asked for, if they are a member, or their
  only one. See [Tenants]({{< relref "/tenants.md" >}}).

## How it programs the gateway

The server uses [`wgctrl`](https://pkg.go.dev/golang.zx2c4.com/wireguard/wgctrl)
to add and remove peers on an existing interface, and checks at start-up that
the interface exists. The interface itself (its private key and listen port)
is left to `wg-quick` or systemd-networkd at boot, which keeps the privileged
interface setup out of the long-running service.

## Run locally

With `WG_DRYRUN=true` no WireGuard device is touched:

```sh
export AUTH_PROVIDER=oidc
export OIDC_ISSUER=https://accounts.google.com
export OIDC_CLIENT_ID=xxxx.apps.googleusercontent.com
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY=$(wg genkey)
export WG_DRYRUN=true LISTEN_ADDR=:8080

go run ./cmd/claimward-server
```

`task run:dev` does the same with GitHub sign-in and an ephemeral key, and
`task dex` runs a local [Dex](https://dexidp.io/) to sign in against
(`deploy/dev/`).

{{< callout type="warning" >}}
**Run behind TLS.** Bearer tokens are credentials: always serve the API over
HTTPS, either with `TLS_CERT`/`TLS_KEY` or behind a TLS-terminating proxy, and
give the RouteService a certificate so that devices get live route updates.
{{< /callout >}}
