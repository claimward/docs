# Client & CLI — `claimward-vpn-client`

This module is both the **shared client core** (imported by every app) and the
cross-platform **`claimward` CLI**.

## Packages

| Package | Purpose |
|---------|---------|
| `pkg/protocol` | Wire contract shared with the server (source of truth) |
| `pkg/oidc` | OIDC Authorization Code + PKCE browser login (discovery) |
| `pkg/wgkey` | WireGuard key generation / parsing |
| `pkg/wgtun` | Userspace tunnel via `wireguard-go` (+ darwin/linux iface & routes) |
| `pkg/client` | High-level: enroll → `wgtun.Config` |
| `pkg/tokenstore` | `0600` on-disk session store |

## CLI

```sh
go build -o bin/claimward ./cmd/claimward

export CLAIMWARD_SERVER=https://vpn.example.com
export CLAIMWARD_OIDC_ISSUER=https://your-issuer.example.com
export CLAIMWARD_OIDC_CLIENT_ID=claimward

claimward login            # browser OIDC login (no root)
sudo -E claimward connect  # enroll + bring up the tunnel (root; -E keeps env)
claimward status
claimward logout
```

`connect` runs in the foreground and tears the tunnel down (and deregisters the
peer) on `Ctrl-C`. Creating the tunnel interface and routes requires root, hence
`sudo`; `login`/`status` do not.

## Reuse in your own tooling

```go
cl := client.New("https://vpn.example.com")
resp, _ := cl.Enroll(ctx, idToken, pair.Public, protocol.DeviceInfo{
    Name: host, OS: "linux", Platform: "cli",
})
cfg, _ := client.TunnelConfig(resp, pair.Private)
tun, _ := wgtun.Up(cfg)
defer tun.Close()
```
