# Claimward

**Claimward** is a self-hosted Zero-Trust network access solution built on
[WireGuard](https://www.wireguard.com/) and OpenID Connect. Users authenticate
with your existing identity provider; Claimward then enrolls their device as a
WireGuard peer and brings up an encrypted tunnel to your private network.

It is written in Go, with a small Svelte UI for the desktop app.

<div class="grid cards" markdown>

- :material-server-network: **Control plane**
  A Go server verifies OIDC tokens and programs the WireGuard gateway.

- :material-laptop: **Clients**
  A cross-platform CLI and native desktop apps (macOS first).

- :material-key-chain: **Auth you already have**
  GitHub by default (device flow), or any OIDC provider — Google, Okta, Entra…

- :material-shield-lock: **Least privilege**
  One peer per device, leases that expire, scoped routes.

</div>

## The pieces

| Repository | What it is |
|------------|-----------|
| [`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server) | Control plane: OIDC verification, IP allocation, WireGuard peer management |
| [`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client) | Shared Go module (wire protocol, OIDC, tunnel) **and** the `claimward` CLI |
| [`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx) | macOS app: Go tray + Svelte webview UI + privileged helper |
| `claimward-vpn-app-linux` / `-windows` | Other desktop apps (planned) |

## Next

- [Getting started](getting-started.md) — stand up a gateway and connect a device.
- [Architecture](architecture.md) — how the enrollment flow works end to end.

!!! note "Status"
    Claimward is an early MVP. See each repository's README for the current
    hardening TODOs (TLS, helper socket permissions, Keychain, packaging).
