---
title: "Privileged helper"
linkTitle: "Privileged helper"
weight: 3
description: "The root or SYSTEM process of each app: it enrolls only with the servers its own configuration names, takes no tunnel configuration from a request, and listens on a socket only its group can reach."
tags: [helper, security, macos, linux, windows]
---

Each app has a **privileged helper**: a root LaunchDaemon on macOS, a systemd
service on Linux, the **ClaimwardHelper** service (LocalSystem) on Windows. It
is the only privileged process of the app. All three are the same code,
`pkg/helper` of [claimward-vpn-client](https://github.com/claimward/claimward-vpn-client);
each app supplies only a `main` that loads the configuration and listens.

The helper does the server communication as well as the tunnel: it enrolls,
brings the tunnel up, and watches route pushes. On macOS "Local Network"
privacy blocks an unprivileged app from a server on the LAN and root is
exempt; the other platforms follow the same path so that the three apps behave
alike.

## The socket protocol

One JSON request per connection, one JSON response (`pkg/hproto`):

| Action | What the helper does |
|---|---|
| `connect` | enrolls with the server named in the request, if its configuration allows it, with the bearer, private key, device name and tenant given; brings the tunnel up; watches the RouteService |
| `tenants` | asks the server which tenants the bearer may connect to |
| `down` | takes the tunnel down |
| `status` | connected or not, the interface, the address, the tenant |
| `approve` | since v0.11.0: approves the server named in the request, if the operating system consents (see [Server approval](../../server-approval/)) |
| `revoke` | removes a server from the approved ones |
| `approved` | lists the approved servers |

Since v0.11.0 the helper holds **one tunnel per server**, each on its own
interface, named from the server's URL: on Windows the adapter is no longer
called `Claimward` but `Claimward <host> <6 hex>` (a **breaking change** for
anything that looked the adapter up by its old name).

## Bounded by its own configuration

Any process that can reach the helper's socket can make it act, so what it
does is bounded by **its own** configuration, never by the request:

- **It enrolls only with a server its configuration names, or one that was
  approved with the system's consent.** A helper that took the server from the
  request would let any local process point it at a server of its own,
  answering with routes for `0.0.0.0/0`: every packet of the machine, sent
  where that process chose. Approval is the operating system's own prompt
  (macOS Authorization Services, polkit on Linux, an elevated second socket on
  Windows), never a field of the request: see [Server approval](../../server-approval/).
- **It takes no tunnel configuration from a request.** The tunnel is what that
  server answered at enrollment. The earlier `up` and `update-routes` actions,
  which took one, are gone.
- **Its configuration must be root's** (SYSTEM's or the Administrators' on
  Windows) **and writable by nobody else**, or the helper does not start:
  whoever writes it chooses the servers trusted.

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "claimward",
  "socket": "/var/run/claimward-helper.sock"
}
```

| Key | |
|---|---|
| `servers` | optional since v0.11.0: the servers pre-approved by the administrator (compared without a trailing `/`); others need approval |
| `approvals` | optional: where the approved servers are kept (the default per platform is in [Server approval](../../server-approval/)) |
| `group` | who may use the socket beside root: `admin` on macOS, `claimward` on Linux, `Claimward Users` on Windows by default |
| `socket` | `/var/run/claimward-helper.sock` by default, `C:\ProgramData\Claimward\helper.sock` on Windows |

| Platform | `helper.json` |
|---|---|
| macOS | `/Library/Application Support/Claimward/helper.json` |
| Linux | `/etc/claimward/helper.json` |
| Windows | `C:\ProgramData\Claimward\helper.json` |

## The socket: macOS and Linux

The socket is **`0660`**, owned by root and the helper's group. It is created
with a restrictive umask, so it never exists with a wider mode, in a directory
only root can write (the helper refuses one somebody else could, since they
could replace the socket with their own and receive the app's bearer). The
earlier helper's socket was `0666`.

## The socket: Windows

On Windows the same rules are ACLs, which the helper sets and reads back
itself rather than trusting an installer to have done it:

- the socket's directory, `C:\ProgramData\Claimward`, gets a **protected** DACL
  (nothing inherited from ProgramData, which lets every user create files
  there): SYSTEM and Administrators in full control, the socket's group allowed
  to list and traverse it and nothing more. It is created already carrying that
  DACL, and a directory that is a junction or a link is refused;
- the socket gets its own DACL: SYSTEM, Administrators, and the group allowed
  to connect (read/write);
- the group is the local group **`Claimward Users`**, which the installer
  creates. If it does not exist the socket is opened to **INTERACTIVE**
  (everybody logged on at the machine, console or Remote Desktop) and the
  helper logs that it did;
- `helper.json` must be **owned by SYSTEM or Administrators, and writable by
  nobody else**: the helper reads the file's owner and DACL and refuses any
  allow entry that grants write, append, delete, `WRITE_DAC`, `WRITE_OWNER` or
  generic write/all to another SID, and a null DACL.

The rules (`pkg/helper/acl.go`) are pure functions, tested on every platform;
the Windows CI job applies them to real files and reads them back.

Approval has a **second socket** on Windows, `C:\ProgramData\Claimward\approve.sock`
(`helper.ListenElevated`, served by `Server.ServeElevated`), whose ACL names
SYSTEM and Administrators only: a standard user cannot connect without UAC
elevation, and only an `approve` that arrived there counts. The app reaches it
through `Client.ElevatedSocketPath` and `ApproveElevated`.

## Packaging the polkit policy (Linux)

The Linux package installs `packaging/polkit/com.claimward.helper.approve-server.policy`
of the client repository into `/usr/share/polkit-1/actions/`. Without it
polkit does not know the action and every approval is refused.

## Route watches over TLS

A route watch carries the bearer token, so `pkg/routeclient` runs it over
**TLS**, checked against the system's roots, except to a loopback address.
Against a server whose RouteService is not TLS the handshake fails before the
token is sent, and the tunnel stays up without live route updates.

Stopping the helper takes the tunnel down.
