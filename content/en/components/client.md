---
title: "Client library"
linkTitle: "Client library"
weight: 2
description: "claimward-vpn-client: the Go library the apps and the server share — sign-in, the wire protocol, the tunnel, the privileged helper and the app core. It ships no binary."
tags: [client, go, wireguard, grpc]
---

[`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client)
**v0.7.0** is a Go **library**. It ships no binary: the runnable programs are
the apps' (`cmd/claimward-app` and `cmd/claimward-helper` in each app
repository). The server imports it too, for the wire types and the gRPC stubs.

{{< callout type="info" >}}
There is no `claimward` command-line client. Earlier versions of this module
had one (`cmd/claimward`, with `login` and `connect`); it was removed, and
the library-only module is what the apps build on.
{{< /callout >}}

## Packages

| Package | Purpose |
|---------|---------|
| `pkg/protocol` | the wire contract (`/enroll`, `/tenants`, `/heartbeat`, `/deregister`), shared with the server |
| `pkg/routespb` | generated gRPC/protobuf stubs of the RouteService, shared with the server |
| `pkg/auth` | interactive sign-in behind a `Provider`: GitHub device flow (default), OIDC code + PKCE, or go-authn device flow, whose provider also registers the device's key (`KeyRegistrar`) |
| `pkg/oidc` | the OIDC authorization code + PKCE flow: discovery, loopback redirect |
| `pkg/browser` | opens a URL in the default browser with absolute opener paths, so it works from GUI apps |
| `pkg/client` | `Enroll`, `Tenants`, `Heartbeat`, `Deregister` against the server, and `TunnelConfig` to turn an `EnrollResponse` into a `wgtun.Config` |
| `pkg/wgkey` | WireGuard key generation and parsing |
| `pkg/pathmtu` | fits the tunnel MTU to the path: the server's `mtu` (default 1420), lowered to the interface MTU towards the endpoint minus 60 (IPv4) or 80 (IPv6), never below 1280, never above the server's value; standard library only |
| `pkg/wgtun` | userspace WireGuard tunnel with `wireguard-go`, plus address and routes: `ifconfig`/`route` on macOS, `ip` on Linux, a Wintun adapter through `winipcfg` on Windows (with DNS and MTU); needs privileges |
| `pkg/routeclient` | watches the server's RouteService and reports route updates; TLS except to loopback |
| `pkg/appcore` | the apps' logic, shared by the three: sign-in, the tenant chosen for the session, connect and disconnect through the helper, status for the UI |
| `pkg/appvm` | the apps' view model, with no UI in it: the screen to show, what each command may do, the status poll, and the events (tunnel dropped, session expired); each app adapts it to its own widgets |
| `pkg/helper` | the privileged helper, shared by the three apps: enrolls, owns the tunnel, watches route pushes |
| `pkg/hproto`, `pkg/helperclient` | the helper's socket protocol, and the app's client for it |
| `pkg/tokenstore` | the session (bearer, refresh token, device private key, chosen tenant) in the OS secret store: macOS Keychain, Windows DPAPI, Linux Secret Service; no plaintext fallback |

## Files on the device

| File | What |
|---|---|
| `<config dir>/Claimward/config.json` | the app's configuration (`appcore.Config`), `0600`, its socket may be overridden by `CLAIMWARD_HELPER_SOCKET` |
| `<config dir>/claimward/session.enc` (macOS and Linux), `session.dpapi` (Windows) | the sealed session; its key is in the Keychain (macOS) or the Secret Service (Linux), or the blob is DPAPI-protected. On Linux the blob is sealed with AES-GCM and only its key is in the Secret Service. |

`<config dir>` is Go's `os.UserConfigDir()`: `~/Library/Application Support` on
macOS, `~/.config` on Linux, `%AppData%` on Windows.

This is the format of **client v0.10.0 and later**, which connects to several
servers at once. The person types only a server URL; the name, providers,
exclusivity and logo are read from the server's
`/.well-known/claimward-configuration`.

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com", "provider": "campus"},
    {"url": "https://lab.example.org"}
  ],
  "socket_path": "/var/run/claimward-helper.sock"
}
```

| `config.json` key | |
|---|---|
| `version` | `2` |
| `servers[].url` | the server's base URL (`https://`; `http://` only for loopback); must be one the helper is configured for |
| `servers[].provider` | optional: the `id` of the provider chosen from the server's document |
| `socket_path` | optional: the helper's socket, if not the default. May be overridden by `CLAIMWARD_HELPER_SOCKET`, the only variable left |

A file of v0.9.0 or earlier (`server_url`, `provider`, `github_client_id`,
`oidc_issuer`, `oidc_client_id`, and the `CLAIMWARD_SERVER`,
`CLAIMWARD_AUTH_PROVIDER`, `CLAIMWARD_GITHUB_CLIENT_ID`, `CLAIMWARD_OIDC_*`
variables) is migrated once on first load. An **exclusive** server is refused
while any other is connected, and any other is refused while an exclusive one is;
the refusal names the blocking server. Linux and Windows hold one tunnel at a
time for now; macOS holds one per server.

## Use in your own tooling

```go
ctx := context.Background()

// 1. Sign in. GitHub is the default provider (device flow).
provider, err := auth.New(auth.Config{Provider: "github", GitHubClientID: "Iv1.0123456789abcdef"})
if err != nil {
	log.Fatal(err)
}
tok, err := provider.Login(ctx, func(p auth.DevicePrompt) {
	fmt.Printf("visit %s and enter code %s\n", p.VerificationURI, p.UserCode)
})
if err != nil {
	log.Fatal(err)
}

// 2. A key pair, and with go-authn the PUBLIC key registered first: the
//    token for the server is the one RegisterKey returns.
keys, err := wgkey.Generate()
if err != nil {
	log.Fatal(err)
}
if reg, ok := provider.(auth.KeyRegistrar); ok {
	if tok, err = reg.RegisterKey(ctx, tok, keys.Public.String(), "laptop"); err != nil {
		log.Fatal(err)
	}
}

// 3. Enroll; "" lets the server use the person's only tenant.
c := client.New("https://vpn.example.com")
resp, err := c.Enroll(ctx, tok.Value, keys.Public,
	protocol.DeviceInfo{Name: "laptop", OS: "linux", Platform: "my-tool"}, "")
if err != nil {
	log.Fatal(err)
}

// 4. The tunnel (needs privileges), and optionally live routes.
cfg, err := client.TunnelConfig(resp, keys.Private)
if err != nil {
	log.Fatal(err)
}
tun, err := wgtun.Up(cfg)
if err != nil {
	log.Fatal(err)
}
defer tun.Close()
if resp.GRPCEndpoint != "" {
	go routeclient.Watch(ctx, resp.GRPCEndpoint, tok.Value, keys.Public.String(),
		func(u routeclient.Update) { _ = tun.UpdateRoutes(u.AllowedIPs) })
}
```

A long-lived client renews its lease with `c.Heartbeat` before
`resp.LeaseExpiresAt`, and removes its peer with `c.Deregister` when it is done.

## Platform notes

- **DNS.** The server's DNS servers are applied on **Windows** only; on macOS
  and Linux they are carried in the protocol but `pkg/wgtun` does not apply
  them yet.
- **Route pushes** replace the allowed IPs and the routes; DNS changes in a
  push are not applied.
- **Windows.** The device is a Wintun adapter named `Claimward`: `wintun.dll`
  (from <https://www.wintun.net>, signed by WireGuard LLC) must sit beside the
  executable that calls `wgtun.Up`, which the Windows app's packaging takes
  care of. Address, routes, DNS and MTU are set through `winipcfg` (the IP
  Helper API, pure Go, `CGO_ENABLED=0`).
- **Session store.** The platform's secret store: the macOS login Keychain
  (holding an AES-GCM key; the session is sealed in `session.enc`), Windows
  DPAPI (`session.dpapi`), and on Linux a sealed `session.enc` too, whose
  AES-GCM key is kept in the Secret Service through `secret-tool`. Since
  **v0.5.0** there is no plaintext fallback and `CLAIMWARD_ALLOW_PLAINTEXT_SESSION`
  has no effect: with no usable store, saving the session fails and sign-in
  fails with an error naming what is missing (on Linux, install and unlock a
  Secret Service provider such as gnome-keyring or KeePassXC, and `secret-tool`).
  A legacy `session.json` is read once, moved into the store and deleted, or
  deleted if the store refuses it. Tests of other packages use
  `tokenstore.UseMemory()`.
