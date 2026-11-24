---
title: "Server"
linkTitle: "Server"
weight: 1
description: "claimward-vpn-server: verifies the sign-in, allocates VPN addresses, programs the WireGuard gateway, streams tenant routes over gRPC, and serves an admin API and metrics."
tags: [server, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.10.0** is the control plane. It verifies the bearer a device presents,
allocates VPN addresses, and programs the WireGuard gateway with one peer per
enrolled device. It runs on the gateway host, beside an existing `wg0`: Linux
(nftables) or, from v0.10.0, OpenBSD (pf, see [OpenBSD](#openbsd)).

## What it serves

| Listener | Path | Purpose |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | verify, choose the tenant, allocate an address, add the peer, return the tunnel configuration |
| | `GET /api/v1/tenants` | the tenants the caller may connect to |
| | `POST /api/v1/heartbeat` | renew the device's lease |
| | `POST /api/v1/deregister` | remove the peer |
| | `GET /healthz` | liveness |
| | `/admin/` | admin API and WebUI, when the `admin-token` credential exists |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | streams the tenant's routes and their updates |
| `METRICS_ADDR` (no default: off unless set) | `GET /metrics` | Prometheus metrics, on a listener of their own, never on `LISTEN_ADDR` |

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
| `METRICS_ADDR` | | — (off) | separate listener for `/metrics`, served **only when set** (since v0.9.0 there is no default port: the old `127.0.0.1:9090` clashed with Prometheus); never on `LISTEN_ADDR`. It names every tenant: keep it on loopback or a private network |
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
A second one since v0.9.0, for systemd with `DynamicUser=yes`: systemd leaves
the file `root:root`, mode `0400`, plus a read-only POSIX ACL entry for the
service's uid (`src/core/exec-credential.c:338-361`, `src/shared/acl-util.c:448-494`),
so `stat` shows `0440`. The server reads `system.posix_acl_access` from the open
descriptor and accepts exactly `user::` (no write or execute), `user:<its uid>:r--`, `group::---`,
`mask::r--`, `other::---`; any other named user or group, any write or execute
bit, or a malformed or oversized value is refused. The error gives the fix.

| Platform | `CREDENTIALS_DIRECTORY` | Owner and mode |
|----------|-------------------------|----------------|
| systemd | set by `LoadCredentialEncrypted=` | with `DynamicUser=yes` (as shipped): root-owned with a read-only ACL for the service's uid, accepted; with a fixed `User=` on a filesystem without ACLs: the service user, `0400`. Private tmpfs |
| Docker Swarm | `/run/secrets`, set by hand | `mode: 0400` on the secret |
| Docker Compose | `/run/secrets`, set by hand | the host file's: `chown` and `chmod 0400` it, and set `user:` to match |
| Podman | `/run/secrets`, set by hand | `--secret ...,mode=0400` (Quadlet: `Secret=...,mode=0400`) |
| Kubernetes | the Secret volume's mount path, set by hand | `defaultMode: 0440` and `fsGroup`: the files are `root:<fsGroup>`, accepted by the group rule above, so the pod runs as a non-root uid with every capability dropped but `NET_ADMIN`. `add: [NET_ADMIN]` alone does not give a non-root uid the capability (no ambient set): the image's binary needs `setcap cap_net_admin=+ep` (per capabilities(7), not measured on a cluster) |
| s6 (no systemd) | `/run/sdcreds/claimward-server`, set by `sdcreds s6-run` | the service user, `0400`, in a private tmpfs (see [s6](#s6-deploy)) |
| otherwise | any directory | `chmod 0400`, owned by the service user |

Ready-made units for systemd, Compose, Podman, Kubernetes and s6 are in the
repository's `deploy/` directory, with the `systemd-creds encrypt` steps. Hosts
without systemd get the same directory from `go-authn/sdcreds` (see
[s6](#s6-deploy)); the server does not depend on it.

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

## OpenBSD (pf) {#openbsd}

From v0.10.0 the server also runs on OpenBSD, where it enforces the access
policy with pf instead of nftables. It talks to the kernel directly through the
`/dev/pf` ioctls; it never runs `pfctl`, and there is no `pfctl` fallback.

- **Supported releases: OpenBSD 7.9 and 8.0.** They share one `struct pf_rule`
  layout, which the server checks against the running release. On any other
  release the server refuses to start rather than risk encoding a rule wrongly.
- **You own `pf.conf`.** The server never edits the main ruleset. Add one line to
  `/etc/pf.conf` and keep `pf` enabled:

  ```text
  anchor "claimward"
  ```

  The server loads the policy into that anchor. At start it reads the main
  ruleset back and verifies that it calls `anchor "claimward"`.
- **It refuses to start** when `/dev/pf` cannot be opened read-write (it must
  start as root), when pf is disabled, when the main ruleset does not call the
  anchor (the policy would be loaded and filter nothing), and when `pf.conf`
  has `set skip on` for the WireGuard interface (`wg0`, `wg*`), because pf would
  then never see the peers' traffic.
- **Same policy as on Linux.** Default deny on traffic arriving on
  `WG_INTERFACE`; only IPv4 is allowed, and IPv6 across the tunnel is dropped.
  The MSS clamp (`TUNNEL_MTU`) covers both families, as a `match ... scrub
  (max-mss N)` rule.
- **Atomic and fail closed.** The anchor and its tables are replaced in one pf
  transaction, then read back and compared with what was meant to be loaded. If
  that fails, deny-all is loaded. The anchor stays in place when the process
  exits. Table names carry a per-load generation suffix, so that the short
  window between the table commit and the rule commit can never apply one
  tenant's rules to another tenant's peers.
- **No `pledge(2)`.** The `pf` promise lets a process issue only twelve of the
  `DIOC*` ioctls (`sys/kern/kern_pledge.c`, `pledge_ioctl`), and the server also
  needs `DIOCRINADEFINE`, `DIOCXROLLBACK`, `DIOCGETRULES`, `DIOCGETRULE`,
  `DIOCXEND` and `DIOCRGETADDRS`. Any other ioctl would kill the process, and a
  pledge cannot be widened later. Run it as a dedicated service under `rcctl`
  and keep the rest of the host locked down.

### Deploying on OpenBSD (rc.d) {#openbsd-deploy}

From v0.10.1 the repository ships `deploy/openbsd/`: an `rc.d(8)` script, an
`environment.example`, a `hostname.wg0.example` and a `pf.conf.example`.

- **It runs as root.** The WireGuard peer configuration of `wg(4)` is behind
  `suser(9)` (`sys/net/if_wg.c`), and `/dev/pf` is guarded only by its device
  node, which is root-only: `pfopen` (`sys/net/pf_ioctl.c`) checks nothing else.
  OpenBSD has no privileged group that would let a `_claimward` user do either,
  so the script sets `daemon_user="root"`.
- **Secrets are files** in `/etc/claimward/credentials`, a `0700` directory owned
  by root, with each file `0400` and owned by root (`install(1)`). The script
  sets `CREDENTIALS_DIRECTORY` to it; no secret goes in the environment, in
  arguments or in a URL. The non-secret settings are in
  `/etc/claimward/environment`.
- **`wg0` must exist** before the server starts: `hostname.wg0` carries the same
  private key as the `wg-private-key` credential (mode `0640`).

```sh
install -m 0555 claimward-server /usr/local/bin/claimward-server
install -d -m 0755 /etc/claimward
install -d -m 0700 /etc/claimward/credentials
install -m 0400 wg-private-key /etc/claimward/credentials/wg-private-key
install -m 0600 environment.example /etc/claimward/environment   # then edit
install -m 0640 hostname.wg0.example /etc/hostname.wg0           # then edit
sh /etc/netstart wg0
install -m 0555 claimward_server /etc/rc.d/claimward_server
rcctl enable claimward_server
rcctl start claimward_server && rcctl check claimward_server
```

The log goes to syslog (`/var/log/daemon`). The CI runs this script in real
OpenBSD 7.9 and 8.0 virtual machines: `rcctl start`, the startup line,
`rcctl check` and `rcctl stop`, then a start without the anchor in `pf.conf`,
which must fail.

## Deploying under s6 (sdcreds) {#s6-deploy}

From v0.10.2 the repository ships `deploy/s6/claimward-server/` (`run` and
`finish`) for hosts without systemd. `sdcreds s6-run` (go-authn/sdcreds v0.2.0
or later) decrypts every file of its `--source` directory into a private tmpfs,
writes each one `0400` and owned by `--user`, sets `CREDENTIALS_DIRECTORY`, and
starts the server as that user. A file owned by the process's own uid with no
group or other access is the first shape the loader accepts, so the loader is
unchanged. Nothing secret goes in the environment, in argv or in a URL.

- **One capability, kept on purpose.** The server needs `CAP_NET_ADMIN` (wgctrl,
  nftables, the interface MTU). `s6-run` empties every capability set of the
  service by default and keeps `no_new_privs`; the example passes
  `--keep-cap=CAP_NET_ADMIN`, so the server runs with exactly that one
  (`CapEff` `0x1000`). The capability acts on the network namespace the
  supervision tree runs in: the host's, unless you start `s6-svscan` inside one
  of its own (`ip netns exec`).
- **Names.** Each file of `--source` is named like its credential
  (`wg-private-key`, `github-token`, `admin-token`, `goauthn-gateway-secret`) and
  encrypted with `sdcreds encrypt --name=<that name>`; any other name stops the
  start. `s6-run` needs root and `CAP_SYS_ADMIN` (it mounts).
- **Configuration** that is not secret goes in `/etc/claimward/env`, read by the
  `run` script.
- **Containers** do not need it: Compose, Podman and Kubernetes mount secrets as
  files already (table above).

The CI runs this directory under a real `s6-svscan`, in a network namespace
with a real WireGuard link and nftables (not a dry run). It checks that the log
holds the public key derived from the encrypted credential (and not a control
key), that the server runs as the service user with `CapEff` `0x1000` and
`no_new_privs`, that no secret is in its environment, that a credential file
with mode `0644` is refused, and that stopping the service removes the mount.

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
