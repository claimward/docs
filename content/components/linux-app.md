---
title: "Linux app"
linkTitle: "Linux app"
weight: 5
description: "claimward-vpn-app-linux: a window and a tray icon drawn in pure Go with go-widgets, and a hardened helper run by systemd."
tags: [linux, app, helper, systemd]
---

[`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux)
**v0.1.0** is a **window and a tray icon drawn in pure Go** with
[go-widgets](https://github.com/go-widgets): no webview, no GTK, no cgo
(`CGO_ENABLED=0`). A **privileged helper** run by systemd owns the WireGuard
tunnel. The logic is the macOS app's: both use
[`pkg/appcore` and `pkg/helper`]({{< relref "/components/client.md" >}}).

## Design

```text
 claimward-app (your session)
 ├─ internal/view        go-widgets/toolkit widgets, bound with go-widgets/mvvmtk
 ├─ internal/trayview    tray icon + menu (StatusNotifierItem over D-Bus)
 ├─ internal/viewmodel   all state as go-widgets/mvvm observables and commands
 └─ appcore              sign-in, tenant, session; drives the helper
        │ X11 / Wayland                  │ unix socket, JSON, 0660 root:claimward
        ▼                                ▼
   the window, the tray            claimward-helper (root, systemd)
                                   enrolls with a configured server,
                                   wireguard-go TUN + ip(8), route pushes
```

The app runs as you and never touches the network configuration or the
server itself: everything goes through the [helper]({{< relref "/components/helper.md" >}}).
The view model holds every piece of state and imports no widget; CI enforces
MVVM with [mvvmlint](https://github.com/go-widgets/mvvmlint) and "no
hand-drawn UI" with [bricolint](https://github.com/go-widgets/bricolint).

## What it does

- **Status**: who is signed in, connected or not, the address and interface,
  the session's tenant, whether the helper answers, the server. It is polled
  every 2 seconds.
- **Sign in**: for a device flow the window shows the code and an *Open sign-in
  page* button (`xdg-open`); the sign-in can be cancelled.
- **Tenant**: when the server refuses a connection because the person belongs
  to several, the window says so and offers a drop-down; *Choose tenant* asks
  for the list ahead of time. The tenant cannot be changed while connected.
- **Connect / Disconnect / Sign out**, **Settings** (server URL, provider,
  GitHub client ID, OIDC issuer and client ID), and the **connection log**.
- **Tray**: a status line, *Connect*, *Disconnect*, *Open window*, *Quit*; the
  icon is in colour while connected. Closing the window leaves the app in the
  tray; *Quit* leaves the tunnel as it is.

The tray needs a StatusNotifierItem host (KDE Plasma, GNOME with the
*AppIndicator and KStatusNotifierItem Support* extension, waybar…). Without
one the app says so, and closing the window quits it.

## Install

Build as yourself (Go 1.27.1 or later), then install as root:

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

`install.sh`:

1. creates the `claimward` group and adds you to it (`$SUDO_USER`, or
   `--user`): **log out and back in** for it to apply;
2. installs `claimward-app` to `/usr/local/bin` and `claimward-helper` to
   `/usr/local/sbin` (`--prefix` to change);
3. writes `/etc/claimward/helper.json`, `root:root`, mode `0644`, with the
   server given (an existing file is kept);
4. installs and starts `claimward-helper.service`, and waits for its socket;
5. installs the desktop entry and the icon.

Start **Claimward VPN** from the desktop's menu; `claimward-app -hidden`
starts in the tray (for an autostart entry). `sudo ./scripts/uninstall.sh`
removes it all and stops the helper, which takes the tunnel down; `--purge`
also removes `/etc/claimward` and the group.

## Configure

The app: `~/.config/Claimward/config.json`, written by the settings form,
mode `0600`, overridden by `CLAIMWARD_*` variables (see the
[client library]({{< relref "/components/client.md#files-on-the-device" >}})).
The session is `~/.config/claimward/session.json`, mode `0600`.

The helper: `/etc/claimward/helper.json` (see
[Privileged helper]({{< relref "/components/helper.md" >}})); after editing it,
`sudo systemctl restart claimward-helper`.

## The hardened unit

`claimward-helper.service` keeps only `CAP_NET_ADMIN`, `CAP_NET_RAW` and
`CAP_CHOWN`, with `NoNewPrivileges`, `ProtectSystem=strict` and only `/run`
writable, `ProtectHome`, `/dev/net/tun` alone from `/dev`, address families
limited to unix, inet, inet6 and netlink, and the `@system-service` system
calls. `systemd-analyze security claimward-helper` rates it 2.5 (OK). Being in
the `claimward` group means being allowed to bring the VPN up and down.

{{< callout type="info" >}}
**Verified** in an Ubuntu 24.04 (arm64) virtual machine against a stand-in
server. **Not yet verified**, according to the README: a real GNOME or KDE
desktop, Wayland, HiDPI, a sign-in against a real identity provider, and a
real claimward-vpn-server. The session file is not yet in a keyring.
{{< /callout >}}
