---
title: "Windows app"
linkTitle: "Windows app"
weight: 6
description: "claimward-vpn-app-windows: a window and a notification-area icon in pure Go, the ClaimwardHelper service, and wireguard-go on a Wintun adapter."
tags: [windows, app, helper, wintun]
---

[`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows)
**v0.2.0** is a desktop app with a notification-area (tray) icon. Everything is
Go with `CGO_ENABLED=0`: the window and the tray are drawn by
[go-widgets](https://github.com/go-widgets) (no webview, no HTTP server in the
app), and the tunnel is [wireguard-go](https://git.zx2c4.com/wireguard-go) on a
[Wintun](https://www.wintun.net) adapter, configured through the IP Helper API.
Its logic and helper are the shared
[`pkg/appcore` and `pkg/helper`]({{< relref "/components/client.md" >}}).

## Design

```text
 claimward-app.exe (the person, unprivileged)
 ├─ internal/ui/view.go        widgets, bound by go-widgets/mvvmtk to …
 ├─ internal/ui/viewmodel.go   … the ViewModel: all state, observables and commands
 ├─ internal/ui/tray_binding   the tray menu, bound to the same ViewModel
 └─ appcore                    sign-in, session, tenant, helper client
        │ AF_UNIX socket, one JSON request each: C:\ProgramData\Claimward\helper.sock
        ▼
 claimward-helper.exe — the ClaimwardHelper service (LocalSystem)
   pkg/helper   enrolls with a server helper.json names, owns the tunnel
   pkg/wgtun    wireguard-go on the Wintun adapter "Claimward"; address, routes, DNS, MTU
```

The window shows the connection, the address and interface, who is signed in,
the tenant and whether the helper answers; the device-flow prompt with a
button that opens the page in the default browser (only an `https` page is
ever handed to the shell); **Connect / Disconnect / Sign out**; **Choose
tenant**; the settings, saved to `%AppData%\Claimward\config.json`; and the
connection log. The status is polled every 2 seconds. The tray menu offers
the status, Connect, Disconnect, Open and Quit. Closing the window quits the
app; the tunnel belongs to the service and stays up until Disconnect.

## Install

From a release folder (`scripts/package.sh` builds them, with Wintun), in an
**elevated** PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.org
# optionally, the app's settings for the current user as well:
.\install.ps1 -Server https://vpn.example.org -Provider github -GitHubClientId Iv1.0123456789abcdef
```

It copies the programs and `wintun.dll` to `C:\Program Files\Claimward`,
creates the local group **Claimward Users** and adds you to it, writes
`C:\ProgramData\Claimward\helper.json`, registers and starts the
**ClaimwardHelper** service, and adds a **Claimward VPN** Start Menu shortcut.
Membership takes effect at your **next sign-in to Windows**; until then the
socket refuses you. Add other people with
`Add-LocalGroupMember -Group 'Claimward Users' -Member <name>`.

`.\uninstall.ps1` removes the service, the shortcut and the programs;
`-RemoveData` also removes `C:\ProgramData\Claimward` and the group. There is
no MSI yet.

`package.sh` downloads `wintun-0.14.1.zip` from wintun.net and refuses it
unless its SHA-256 matches the one pinned in the script; the DLL is signed by
WireGuard LLC and is not in the repository.

## Configure

The app reads `%AppData%\Claimward\config.json`, then `CLAIMWARD_*` variables
(see the [client library]({{< relref "/components/client.md#files-on-the-device" >}})).
The session is `%AppData%\claimward\session.json`.

The helper reads `C:\ProgramData\Claimward\helper.json`:

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "Claimward Users",
  "socket": "C:\\ProgramData\\Claimward\\helper.sock"
}
```

The service logs to `C:\ProgramData\Claimward\helper.log`; from an elevated
console, `claimward-helper run` runs it in the foreground. The ACLs the helper
sets and checks are described under
[Privileged helper]({{< relref "/components/helper.md#the-socket-windows" >}}).

{{< callout type="info" >}}
**Still to come:** an MSI installer, and the session in the Windows Credential
Manager (DPAPI) rather than a per-user file.
{{< /callout >}}
