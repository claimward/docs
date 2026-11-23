---
title: "Tenants"
weight: 40
description: "Routes are scoped to tenants. A person may belong to several, and chooses one per session; the device connects to that one."
tags: [tenants, server, grpc]
---

A **tenant** is a set of routes (`allowed_ips`) and DNS servers, and the rules
that say who belongs to it. A person may belong to several tenants: they
choose one per session, and the device connects to that one.

## Membership

A person belongs to every tenant that names any of:

| Field | Matched against |
|---|---|
| `domains` | the domain of a **verified** email address (an unverified one is a string the person typed) |
| `groups` | the token's `groups` claim (OIDC; go-authn: eduPerson entitlements), or the person's GitHub organisations |
| `idps` | the institution that vouched for them: go-authn's `idp`, a SAML entity ID |
| `members` | GitHub **logins**, named one by one, pinned to the account's numeric ID (below) |

{{< callout type="warning" >}}
**A person who matches no tenant is refused** (v0.5.0, breaking): `403
not_a_member` on `/api/v1/tenants` and `/api/v1/enroll`, and the gRPC `Watch` is
refused. There is no fallback tenant any more: the `default` tenant receives
only those its own `domains`, `groups`, `idps` or `members` name. An unknown
tenant ID is an error, never the `default` tenant's routes.
{{< /callout >}}

**Migrating from v0.4.x.** People who used to land in `default` must now be
named by it: give the `default` entry of `TENANTS_FILE` the `domains`,
`groups`, `idps` or `members` that name them, then restart. The `default`
tenant created from `PUSH_ROUTES` and `DNS` alone names nobody.

### Named members {#members}

`members` lists GitHub logins, readable but renameable: a login can be released
and registered by somebody else. The server therefore **pins** each login to the
account's numeric ID. When a tenant is loaded (`TENANTS_FILE`) or created or
updated through the admin API, it calls `GET {GITHUB_API_URL}/users/{login}`
(10 s timeout, 64 KiB answer cap, the account must be a `User`) and stores the
pair in the read-only `pinned` field. A person is a member when their token's
subject is `github:<id>` for a pinned ID: a renamed account whose old login now
belongs to somebody else is refused. An **unresolvable login is an error**: the
server refuses to start, and the admin API answers `400`. The admin API and
WebUI show the logins; to follow a rename, edit the tenant again. Resolution is
authenticated with the `github-token` credential (a file in
`CREDENTIALS_DIRECTORY`, sent as a bearer: 5000 requests an hour on
github.com). A tenant with `members` and no `github-token` stops the start; the
token is never sent over plain HTTP except to a loopback address.

A named member is also admitted by the GitHub entry gate without belonging to
an allowed organisation (see [identity providers]({{< relref "/identity-providers.md" >}})).

## Where tenants come from

The server starts with one tenant, `default`, whose routes are `PUSH_ROUTES`
(by default `VPN_CIDR`) and whose DNS servers are `DNS`. Other tenants are
created, edited and deleted through the [admin API and WebUI]({{< relref "/operations.md#admin-api-and-webui" >}}),
which edit the four membership lists beside the routes. The default tenant
cannot be deleted.

{{< callout type="warning" >}}
Tenants are kept **in memory** (v0.2.0): a restart of the server leaves only
the `default` tenant, rebuilt from the environment.
{{< /callout >}}

## Access policy {#access-policy}

A tenant's routes are not only advertised: the gateway **enforces** them. A
tenant may carry a `policy`, a list of rules that say which destination a peer
may reach, on which protocol and ports:

```json
[{"id": "default", "policy": [
  {"cidr": "10.20.0.5/32", "proto": "tcp", "ports": [445, 88]},
  {"cidr": "10.20.0.5/32", "proto": "udp", "ports": [88]}
]}]
```

- `proto` is `tcp` or `udp`; `ports` are numbers or ranges (`"9000-9010"`), and
  are required. IPv4 only.
- The `allowed_ips` pushed to the clients are **derived from the policy**
  (the distinct CIDRs), so what a device routes and what the gateway lets
  through cannot drift apart. The route format is unchanged.
- The gateway owns one nftables table, `inet claimward`, installed through
  netlink (Linux, `CAP_NET_ADMIN`) and replaced atomically at start and at
  every peer or tenant change. Traffic arriving from the WireGuard interface is
  **denied by default**, in both the forward chain and the input chain (the
  file server may be the gateway host itself); each peer's address is matched
  against its tenant's rules. DNS must be named in the policy like anything
  else.
- **Fail closed**: if the ruleset cannot be installed, the server does not
  start, and an enrollment whose ruleset cannot be installed is refused
  (`500 gateway_error`).
- A tenant with `allowed_ips` and no `policy` is enforced as any protocol, any
  port, to those CIDRs.

Tenants with a policy are loaded at start from the JSON file named by
`TENANTS_FILE` (an array of tenants with the admin API's fields); the admin API
accepts `policy` too. The admin WebUI does not edit it yet.

## Choosing one per session

| Request | What the server does |
|---|---|
| `GET /api/v1/tenants` | lists the tenants the caller may connect to, `[{"id", "name"}]`, for a client to offer the choice |
| `POST /api/v1/enroll` with `tenant` | the tenant must be one of them, or `403 not_a_member` |
| `POST /api/v1/enroll` without `tenant` | the caller's only tenant; a person in several gets `409 tenant_required`, with the list in the message, rather than being routed into a network they did not choose |
| `POST /api/v1/heartbeat` | refused with `403 not_a_member` once the person is no longer in the session's tenant |
| RouteService `Watch` | streams the routes of the tenant **the device enrolled into**, found by the device's key, which must be the caller's |

In the apps (`pkg/appcore`):

- **`Tenants`** asks the server, through the helper, which tenants the person
  may join;
- **`SetTenant`** records the choice in the session, and only a tenant the
  server offered; a new sign-in forgets it;
- **`Connect`** enrolls into that tenant. A person in several who has not
  chosen gets `ErrTenantRequired`, with the tenants in the status.

A person in one tenant never chooses. The macOS app opens its window when a
**Connect** from the menu bar is refused for want of a choice; the Linux and
Windows apps show the choice in their window. The Linux app does not let the
tenant change while connected.

## Route updates

Editing a tenant's routes bumps its `serial` and pushes the new set to every
device watching that tenant over the gRPC RouteService. The helper replaces
the WireGuard peer's allowed IPs and adds or removes the matching routes,
without enrolling again. Deleting a tenant ends its watches.
