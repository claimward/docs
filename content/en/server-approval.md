---
title: "Server approval"
linkTitle: "Server approval"
weight: 35
description: "How the root helper decides to trust a server the app names: the administrator's pre-approval, or the operating system's own consent, remembered in a file only root can write and revocable at any time."
tags: [security, helper, approval, macos, linux, windows]
---

The helper runs as root (SYSTEM on Windows) and a server it enrolls with
chooses the routes and the peer of the machine's tunnel: a hostile server is
every packet of the machine, sent there. Since **client v0.11.0** the helper
takes a server from the app only if one of these holds:

1. the administrator's configuration names it (`servers` in `helper.json`,
   now optional: the **pre-approval**);
2. it was **approved** before, and still says what it said then;
3. it is approved **now**, with the consent of the operating system,
   obtained by the helper itself.

An app flag, a field of the request, or a claim of any kind is never consent.

## What is asked of the system

| Platform | Consent |
|---|---|
| macOS | Authorization Services right `com.claimward.helper.approve-server`, rule `authenticate-admin-nonshared`: an administrator's name and password, every time. The app obtains the authorization (`macauth.Obtain`) and sends its 32-byte external form; the helper has the system verify it and destroys it, so one token buys one approval. A forged token names nothing in the system and is refused |
| Linux | polkit action `com.claimward.helper.approve-server` (`auth_admin`), asked of the system bus for the process behind the socket: its pid from `SO_PEERCRED` and its start time from `/proc/<pid>/stat`, which defeats pid reuse. The policy file ships in `packaging/polkit/` and goes in `/usr/share/polkit-1/actions/` |
| Windows | a second socket, `C:\ProgramData\Claimward\approve.sock`, whose ACL names SYSTEM and Administrators only: a standard user cannot connect without UAC elevation. Only a request that came in on it counts |

With no authorizer configured the helper refuses every approval: it fails
closed. A request that is refused, or that the system cannot answer, changes
nothing.

## What is remembered

The helper keeps the approved servers in a file only root can write:

| Platform | File |
|---|---|
| macOS | `/var/db/claimward/approved-servers.json` |
| Linux | `/var/lib/claimward/approved-servers.json` |
| Windows | `C:\ProgramData\Claimward\approved-servers.json` |

Each entry is the server's canonical URL and the SHA-256 of its **discovery
identity**: its name and its identity providers (id, kind, issuer, client
ids). A server that changes one of those is not the one that was approved: the
helper refuses it (`server_identity_changed`) until it is approved again.
Whether the server is exclusive, its logo and the providers' display names are
not part of the identity, and neither is its TLS certificate, which is renewed
every few weeks (the connection is verified against the web PKI at each use).

The file is read afresh at every use, so **deleting it, or removing a line,
revokes at once**; the `revoke` action does the same for one server. An
administrator's `servers` list is never edited by the helper.

## Errors the app sees

| Code | Meaning |
|---|---|
| `server_not_approved` | the server is neither pre-approved nor approved: ask the person to approve it |
| `server_identity_changed` | it was approved, and no longer says the same: approve it again |
| `approval_denied` | the system's consent was not given |

## Limits, stated

- On macOS the **text of the prompt is supplied by the app** that asks, so a
  hostile process in the socket's group can make the system ask an
  administrator to approve its own server, and a distracted administrator can
  say yes. The credential is an administrator's, never cached, and good for one
  approval.
- On Windows, an elevated process can approve anything, as an administrator
  can edit the file anyway.
- Linux has no cache either: `auth_admin` asks every time.
