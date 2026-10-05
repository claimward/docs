---
title: "Getting started"
weight: 10
description: "Stand up a WireGuard gateway with claimward-vpn-server, register a sign-in client, and connect a first device with the macOS, Linux or Windows app."
tags: [wireguard, server, github, oidc]
---

This walks through standing up a gateway and connecting a first device. The
gateway is a Linux host; the device runs one of the three desktop apps.

## 1. Prepare the WireGuard gateway (Linux)

Create the `wg0` interface with a server key and a listen port. Claimward
manages the *peers* of this interface; it does not create the interface.

```ini
# /etc/wireguard/wg0.conf
[Interface]
Address = 10.80.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
```

```sh
wg genkey | tee server.key | wg pubkey > server.pub
sudo wg-quick up wg0
sudo sysctl -w net.ipv4.ip_forward=1   # if you route beyond the VPN subnet
```

## 2. Run the control plane

```sh
go install github.com/claimward/claimward-vpn-server/cmd/claimward-server@v0.1.0

export AUTH_PROVIDER=github                     # the default
export GITHUB_ALLOWED_ORGS=claimward            # optional authorization (recommended)
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY_FILE=/etc/wireguard/server.key
export VPN_CIDR=10.80.0.0/24
export TLS_CERT=/etc/claimward/fullchain.pem    # HTTPS, and TLS on the gRPC RouteService
export TLS_KEY=/etc/claimward/privkey.pem
export GRPC_ENDPOINT=vpn.example.com:8444       # where clients watch for route updates

sudo -E "$(go env GOPATH)/bin/claimward-server"
```

The server needs the rights to configure `wg0` (root, or `CAP_NET_ADMIN`). It
listens on `:8443` (`LISTEN_ADDR`) for the enrollment API and on `:8444`
(`GRPC_ADDR`) for the RouteService. See the
[server reference]({{< relref "/components/server.md" >}}) for every variable;
for experiments without a real interface, set `WG_DRYRUN=true`.

## 3. Register the sign-in client

{{< tabs >}}
  {{< tab name="GitHub (default)" >}}
Create a GitHub **OAuth App** (organisation or personal) and **enable Device
Flow** in its settings. The apps need only its **client ID**, no secret. They
ask for the scopes `read:user`, `user:email` and `read:org`.
  {{< /tab >}}
  {{< tab name="OpenID Connect" >}}
In your identity provider, create a **native/public** client with PKCE and the
loopback redirect `http://127.0.0.1:<port>/callback`. The port is picked at
each sign-in, so the provider must accept any loopback port (RFC 8252). No
client secret. Run the server with `AUTH_PROVIDER=oidc`, `OIDC_ISSUER` and
`OIDC_CLIENT_ID`.
  {{< /tab >}}
  {{< tab name="go-authn" >}}
At a [go-authn/bridge](https://github.com/go-authn/bridge) provider, declare
two clients: the one people sign in with (`device = true`,
`wireguard_keys = true`, a `refresh_lifetime`), and the gateway's own client
(`wireguard_peers`). Run the server with `AUTH_PROVIDER=go-authn`. See
[Identity providers]({{< relref "/identity-providers.md#go-authn" >}}).
  {{< /tab >}}
{{< /tabs >}}

## 4. Connect a device

Each app has a **privileged helper** that enrolls with the server and owns
the tunnel; it is installed once, as an administrator, with the servers it may
connect to. The app itself runs as you.

{{< tabs >}}
  {{< tab name="macOS" >}}
From a checkout of
[claimward-vpn-app-osx](https://github.com/claimward/claimward-vpn-app-osx):

```sh
sudo ./scripts/install-helper.sh https://vpn.example.com   # the root LaunchDaemon
task start:bundle                                          # build Claimward.app and open it
```

Then fill in the server URL, the provider and its client ID in
**Configuration…** (or in `~/Library/Application Support/Claimward/config.json`),
and click **Connect**. See the [macOS app]({{< relref "/components/macos-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Linux" >}}
From a checkout of
[claimward-vpn-app-linux](https://github.com/claimward/claimward-vpn-app-linux):

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

Log out and back in (the installer adds you to the `claimward` group), start
**Claimward VPN** from your desktop's menu, fill in the settings and click
**Connect**. See the [Linux app]({{< relref "/components/linux-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Windows" >}}
From a release folder built by `scripts/package.sh` of
[claimward-vpn-app-windows](https://github.com/claimward/claimward-vpn-app-windows),
in an **elevated** PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.com -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Sign out of Windows and back in (the installer adds you to the
**Claimward Users** group), start **Claimward VPN** from the Start Menu and
click **Connect**. See the [Windows app]({{< relref "/components/windows-app.md" >}}).
  {{< /tab >}}
{{< /tabs >}}

A person who belongs to several tenants is asked to choose one before the
connection is made; see [Tenants]({{< relref "/tenants.md" >}}).


The device now has a tunnel interface (`utunN` on macOS, `utun` on Linux, the
Wintun adapter **Claimward** on Windows) with its `10.80.0.x/32` address, and
routes to the tenant's networks through it.

{{< callout type="warning" >}}
The v0.1.0 apps do not renew their lease: a connection that stays up longer
than `LEASE_TTL` (24 hours by default) is removed from the gateway. Connecting
again enrolls again and starts a new lease. See
[Leases]({{< relref "/architecture.md#leases" >}}).
{{< /callout >}}
