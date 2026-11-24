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
| | `/admin/` | admin API and WebUI, when the `admin-token` credential exists |
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

Settings are in the environment. **Secrets are not**: since v0.6.0 they are
files in a credentials directory, see [Credentials](#credentials) below.

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | identity provider: `github`, `oidc` or `go-authn` |
| `GITHUB_ALLOWED_ORGS` | `github` | — | CSV organisation allowlist: an active member of any is allowed, and so is a named tenant member. Since v0.5.0 it is **optional only when at least one tenant has `members`**: with neither the server refuses to start, with no opt-out (before: required since v0.4.0) |
| `GITHUB_API_URL` | | `https://api.github.com` | set for GitHub Enterprise |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | issuer URL (discovery) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | the audience tokens must carry |
| `OIDC_ALLOWED_DOMAINS` | | — | CSV email-domain allowlist (`oidc`); the token's email must be verified |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | the gateway's own client at the provider (`wireguard_peers`) |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | how often the list of registered keys is fetched |
| `GOAUTHN_SSF` | | `false` | also poll the provider's Shared Signals stream, so that a disabling is acted on at once; the gateway's client must be an SSF receiver there |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | how often the SSF stream is polled |
| `WG_ENDPOINT` | ✅ | — | public `host:port` of the gateway, advertised to clients |
| `CREDENTIALS_DIRECTORY` | ✅ | — | the directory that holds the secret files, see [Credentials](#credentials) |
| `WG_INTERFACE` | | `wg0` | interface to manage |
| `WG_DRYRUN` | | `false` | log peer operations instead of applying them (local development) |
| `VPN_CIDR` | | `10.80.0.0/24` | IPv4 address pool; its first host is the gateway's |
| `PUSH_ROUTES` | | `VPN_CIDR` | CSV routes of the `default` tenant |
| `DNS` | | — | CSV DNS servers of the `default` tenant |
| `TENANTS_FILE` | | — | JSON file of tenants loaded at start, with their [access policy]({{< relref "/tenants.md#access-policy" >}}) |
| `KEEPALIVE` | | `25` | persistent keepalive advertised to clients (seconds) |
| `LEASE_TTL` | | `24h` | how long an enrollment lasts without a heartbeat |
| `TUNNEL_MTU` | | derived | MTU of the WireGuard interface, 1280 to 9000, advertised as `mtu`; anything else refuses to start. Unset: the uplink MTU minus 80, at most 1420, at least 1280. The same atomic `inet claimward` table also clamps the MSS of every TCP SYN crossing the interface (forwarded both ways, and input for the gateway itself) to this MTU minus 40 (IPv4) or 60 (IPv6) |
| `LISTEN_ADDR` | | `:8443` | HTTP listen address |
| `GRPC_ADDR` | | `:8444` | RouteService listen address; `Watch` streams are re-authorised every 15 s and end when the identity is no longer allowed |
| `METRICS_ADDR` | | `127.0.0.1:9090` | separate listener for `/metrics` (loopback by default; it is no longer served on `LISTEN_ADDR`) |
| `MAX_DEVICES_PER_SUBJECT` | | `5` | devices one identity may enroll |
| `GRPC_ENDPOINT` | | — | `host:port` of the RouteService advertised to clients; empty, they do not watch |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS, and TLS on the RouteService |
| `DEBUG` | | — | any value: debug logging (one line per request) |

## Credentials {#credentials}

Every secret is a **file** in the directory named by `CREDENTIALS_DIRECTORY`,
never an environment variable: an environment is copied into every child
process and every crash dump. systemd sets the variable for `LoadCredential=`
and `LoadCredentialEncrypted=`; on the other platforms you set it yourself. The
file names are fixed, and one trailing newline is trimmed.

| File | Required | Content |
|------|----------|---------|
| `wg-private-key` | always | the gateway's base64 private key |
| `admin-token` | no | bearer of the admin API and WebUI; **without the file they are disabled** |
| `goauthn-gateway-secret` | `AUTH_PROVIDER=go-authn` | the gateway client's secret |
| `github-token` | when any tenant has `members` | bearer for `GET /users/{login}` (see [Tenants]({{< relref "/tenants.md" >}})) |

A missing required file stops the start and names the file. Before reading, the
server checks each file through its open descriptor (`O_NOFOLLOW`, then
`fstat`) and **refuses** a symbolic link, anything but a regular file, a file
readable by group or other, a file not owned by the server's uid, an empty file
and one over 64 KiB. One exception since v0.7.1: a file owned by uid 0 with mode
exactly `0440` is accepted when its group is the server's gid or one of its
supplementary groups (what a Kubernetes Secret volume with `fsGroup` produces).
The error gives the fix.

| Platform | `CREDENTIALS_DIRECTORY` | Owner and mode |
|----------|-------------------------|----------------|
| systemd | set by `LoadCredentialEncrypted=` | the service user, `0400`, on a private tmpfs |
| Docker Swarm | `/run/secrets`, set by hand | `mode: 0400` on the secret |
| Docker Compose | `/run/secrets`, set by hand | the host file's: `chown` and `chmod 0400` it, and set `user:` to match |
| Podman | `/run/secrets`, set by hand | `--secret ...,mode=0400` (Quadlet: `Secret=...,mode=0400`) |
| Kubernetes | the Secret volume's mount path, set by hand | `defaultMode: 0440` and `fsGroup`: the files are `root:<fsGroup>`, accepted by the group rule above, so the pod runs as a non-root uid with every capability dropped but `NET_ADMIN`. `add: [NET_ADMIN]` alone does not give a non-root uid the capability (no ambient set): the image's binary needs `setcap cap_net_admin=+ep` (per capabilities(7), not measured on a cluster) |
| otherwise | any directory | `chmod 0400`, owned by the service user |

Ready-made units for systemd, Compose, Podman and Kubernetes are in the
repository's `deploy/` directory, with the `systemd-creds encrypt` steps. Hosts
without systemd will be able to get the same directory from `go-authn/sdcreds`
(`sdcreds s6-run`) once its first release is tagged; nothing depends on it yet.

The organisation check of the `github` provider does not use `github-token`: it
runs with the *person's* token, so a private membership is visible only if that
token carries `read:org`. The credential is optional while only organisations
are used.

{{< callout type="warning" >}}
**Migrating from v0.5.0** (breaking). `ADMIN_TOKEN`, `WG_PRIVATE_KEY`,
`WG_PRIVATE_KEY_FILE` and `GOAUTHN_GATEWAY_SECRET_FILE` are no longer read, and
the server refuses to start while one of them is set, naming the file to
create. Put each value in its file (`admin-token`, `wg-private-key`,
`goauthn-gateway-secret`), unset the variable and set `CREDENTIALS_DIRECTORY`.
A tenant with `members` now also needs `github-token`.
{{< /callout >}}

## Authentication providers

Authentication is pluggable behind the `Verifier` interface
(`internal/auth`):

- **`github`** (default): the bearer is a GitHub OAuth access token from the
  device flow. The server resolves it through the GitHub API (`/user`,
  `/user/orgs`) and, with `GITHUB_ALLOWED_ORGS`, admits an active
  member of one of those organisations, or a named tenant member (the list is
  optional only when a tenant has `members`). No client secret is involved.
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
export CREDENTIALS_DIRECTORY=$HOME/.local/state/claimward-dev-creds
(umask 077; mkdir -p "$CREDENTIALS_DIRECTORY"; wg genkey > "$CREDENTIALS_DIRECTORY/wg-private-key")
chmod 0400 "$CREDENTIALS_DIRECTORY/wg-private-key"
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
