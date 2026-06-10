# Server — `claimward-vpn-server`

The control plane. It verifies OIDC ID tokens, allocates VPN addresses, and
programs the WireGuard gateway with one peer per enrolled device. It is designed
to run co-located on the Linux gateway host.

## Endpoints

All authenticated requests carry `Authorization: Bearer <id_token>`.

| Method & path | Purpose |
|---------------|---------|
| `POST /api/v1/enroll` | Verify, allocate an IP, add the peer, return tunnel config |
| `POST /api/v1/heartbeat` | Renew the device's lease |
| `POST /api/v1/deregister` | Remove the peer |
| `GET /healthz` | Liveness |

See the [enrollment protocol](../reference/protocol.md) for payloads.

## Configuration

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | identity provider: `github` or `oidc` |
| `GITHUB_ALLOWED_ORGS` | | — | CSV org allowlist (github); members of any are allowed |
| `GITHUB_API_URL` | | `https://api.github.com` | set for GitHub Enterprise |
| `OIDC_ISSUER` | when `oidc` | — | issuer URL (discovery) |
| `OIDC_CLIENT_ID` | when `oidc` | — | expected token audience |
| `OIDC_ALLOWED_DOMAINS` | | — | CSV email-domain allowlist (oidc) |
| `WG_ENDPOINT` | ✅ | — | public `host:port` advertised to clients |
| `WG_PRIVATE_KEY` / `WG_PRIVATE_KEY_FILE` | ✅ | — | base64 server key |
| `WG_INTERFACE` | | `wg0` | kernel interface to manage |
| `WG_DRYRUN` | | `false` | log peer ops instead of applying (local dev) |
| `VPN_CIDR` | | `10.80.0.0/24` | address pool; `.1` is the gateway |
| `PUSH_ROUTES` | | `VPN_CIDR` | CSV `AllowedIPs` pushed to clients |
| `DNS` | | — | CSV DNS servers pushed to clients |
| `KEEPALIVE` | | `25` | persistent keepalive (seconds) |
| `LEASE_TTL` | | `24h` | lease duration without heartbeat |
| `LISTEN_ADDR` | | `:8443` | bind address |
| `TLS_CERT` / `TLS_KEY` | | — | enable HTTPS (else terminate TLS at a proxy) |

## Authentication providers

Auth is pluggable behind a `Verifier` interface (`internal/auth`):

- **`github` (default)** — clients sign in with the GitHub OAuth **device flow**
  and send the resulting access token. The server validates it against the
  GitHub API (`/user`) and, if `GITHUB_ALLOWED_ORGS` is set, requires active
  membership in one of those orgs. No client secret is involved.
- **`oidc`** — clients send an OIDC ID token, verified against the issuer with
  the audience and optional email-domain allowlist.

The bearer is opaque on the wire, so adding a provider is server-local: implement
`Verifier` and register it in the factory.

## How it programs the gateway

The server uses [`wgctrl`](https://pkg.go.dev/golang.zx2c4.com/wireguard/wgctrl)
to add and remove peers on an existing interface. On enrollment it sets a peer
whose `AllowedIPs` is exactly the client's assigned `/32`, so devices cannot
spoof each other's addresses. Peer setup of the interface itself (private key,
listen port) is left to `wg-quick`/systemd at boot.

!!! warning "Run behind TLS"
    ID tokens are bearer credentials. Always serve over HTTPS — either set
    `TLS_CERT`/`TLS_KEY` or place the server behind a TLS-terminating proxy.
