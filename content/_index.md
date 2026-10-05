---
title: "Claimward documentation"
linkTitle: "Home"
type: docs
cascade:
  type: docs
description: "Claimward is a self-hosted Zero-Trust network access solution built on WireGuard: people sign in with the identity provider you already have, and their device is enrolled as a WireGuard peer of your gateway."
# The cards below list the sections: the left sidebar would repeat them.
sidebar:
  hide: true
toc: false
---

{{< brand-lockup >}}

**Claimward** is a self-hosted Zero-Trust network access solution built on
[WireGuard](https://www.wireguard.com/). People sign in with the identity
provider you already have (GitHub, any OpenID Connect provider, or a
[go-authn](https://github.com/go-authn/bridge) provider in front of a SAML
federation); Claimward then enrolls their device as a WireGuard peer of your
gateway, with an address of its own and the routes of the tenant they chose.

Everything is written in Go. The macOS app draws its window with Svelte in a
webview; the Linux and Windows apps are pure Go
([go-widgets](https://github.com/go-widgets), no cgo).

{{< cards >}}
  {{< card link="getting-started/" title="Getting started" icon="lightning-bolt" subtitle="Stand up a gateway and connect a first device." >}}
  {{< card link="architecture/" title="Architecture" icon="puzzle" subtitle="Control plane, data plane, the enrollment flow and leases." >}}
  {{< card link="identity-providers/" title="Identity providers" icon="finger-print" subtitle="GitHub (default), OpenID Connect, or go-authn with its WireGuard key registry." >}}
  {{< card link="tenants/" title="Tenants" icon="users" subtitle="Who belongs where, and the tenant chosen for each session." >}}
  {{< card link="components/" title="Components" icon="cube" subtitle="The server, the client library, the privileged helper and the three desktop apps." >}}
  {{< card link="reference/protocol/" title="Protocol reference" icon="code" subtitle="The enrollment API and the gRPC RouteService." >}}
  {{< card link="operations/" title="Operations" icon="cog" subtitle="TLS, the gateway, leases, state, the admin API and metrics." >}}
{{< /cards >}}

## The pieces

| Repository | Release | What it is |
|------------|---------|------------|
| [`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server) | v0.2.0 | Control plane: verifies the sign-in, allocates addresses, programs the WireGuard gateway, streams tenant routes over gRPC, admin API and metrics |
| [`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client) | v0.3.1 | Go **library** shared by the apps and the server: wire protocol, sign-in providers, tunnel, privileged helper, app core. It ships no binary |
| [`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx) | v0.2.0 | macOS app: Go menu-bar app, Svelte UI in a webview, root LaunchDaemon helper |
| [`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux) | v0.2.0 | Linux app: window and tray in pure Go, helper run by systemd |
| [`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows) | v0.2.0 | Windows app: window and tray in pure Go, helper as a Windows service, Wintun tunnel |

{{< callout type="info" >}}
**Status.** These are first releases. Still to come, according to each
repository: the session token in the platform's secret store (Keychain,
a keyring, the Windows Credential Manager), a signed and notarized macOS app,
an MSI for Windows, DNS applied on macOS and Linux, and state on the server
that survives a restart. Each repository's README lists what remains.
{{< /callout >}}
