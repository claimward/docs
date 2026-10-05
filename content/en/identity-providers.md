---
title: "Identity providers"
weight: 30
description: "GitHub by default, any OpenID Connect issuer, or a go-authn provider, which also keeps whose each WireGuard key is."
tags: [github, oidc, go-authn, server]
---

The server and the apps each select a provider by name, and must agree:
`AUTH_PROVIDER` on the server, `"provider"` in the app's `config.json` (or
`CLAIMWARD_AUTH_PROVIDER`). The bearer the app obtains is opaque on the wire;
how the server verifies it depends on the provider.

| Provider | Sign-in on the device | Bearer sent to the server | How the server verifies it |
|---|---|---|---|
| `github` (default) | OAuth device flow | GitHub OAuth access token | GitHub API (`/user`, `/user/orgs`), optional organisation allowlist |
| `oidc` | authorization code + PKCE, in the browser | OIDC ID token | signature, issuer, audience; optional email-domain allowlist |
| `go-authn` | device flow, then key registration | go-authn access token (`at+jwt`) | signature, issuer, audience, `typ`; the key must be registered by the same subject |

## GitHub

The default. The app runs the GitHub **device flow**: it shows a code and the
page where to enter it, and opens that page in the browser. Only a client ID
is needed, no secret, so create a GitHub **OAuth App** with **Device Flow**
enabled. The app asks for `read:user`, `user:email` and `read:org`.

The server resolves the person through the GitHub API with their token: their
numeric ID is the subject (`github:<id>`), their organisations
(`/user/orgs`) are their groups for [tenants]({{< relref "/tenants.md" >}}), and
their public email, when they have one, counts as verified. With
`GITHUB_ALLOWED_ORGS`, an active membership of one of those organisations is
required. Set `GITHUB_API_URL` for GitHub Enterprise.

```sh
AUTH_PROVIDER=github
GITHUB_ALLOWED_ORGS=my-org,my-other-org
```

## OpenID Connect

`AUTH_PROVIDER=oidc` with `OIDC_ISSUER` (discovered through
`/.well-known/openid-configuration`) and `OIDC_CLIENT_ID`, the audience the ID
token must carry. The app runs the authorization code flow with PKCE: it opens
the browser and receives the redirect on `http://127.0.0.1:<port>/callback`,
with a port chosen at each sign-in. It asks for `openid profile email
offline_access`. Register a **public/native** client, without a secret.

The server takes the subject, the email and `email_verified`, the
`preferred_username` and the `groups` claim (a list, or a single string). With
`OIDC_ALLOWED_DOMAINS`, the email's domain must be one of those.

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) is an OpenID Connect
provider in front of a SAML federation (RENATER, eduGAIN). It also keeps
**whose each WireGuard key is**, so a valid token is no longer enough to
enroll a device:

1. The app signs in with the provider's **device flow**, scope
   `openid wireguard`. That token opens the provider's key registry and
   nothing else: the provider addresses a token carrying one of its own scopes
   to itself alone.
2. At every connection the app registers the device's **public** key
   (`POST /wireguard/key`), which renews it when it is already the person's,
   then refreshes for `scope=openid` alone. That gives an **access token**
   addressed to the VPN server. The provider rotates refresh tokens, and the
   app keeps the new one. The private key never leaves the device.
3. The server accepts only an access token (`typ: at+jwt`, RFC 9068) whose
   audience is `OIDC_CLIENT_ID`, never an ID token. It enrolls the key only if
   the provider's list has it **registered by the same subject**; otherwise it
   answers `403 key_not_registered`. A lease never outlives the key's
   registration.

The list comes from [go-authn/wireguard](https://github.com/go-authn/wireguard):

- it is **fetched with the gateway's own client** (`client_credentials`, scope
  `wireguard_peers`) and signed by the provider for that gateway alone
  (`typ: wireguard-peers+jwt`);
- it is fetched again every `GOAUTHN_PEER_LIST_INTERVAL` (30 seconds by
  default). A key the provider takes back (the person or their institution
  disabled, or the device removed) is dropped from `wg0` at the next fetch,
  and its heartbeat is refused;
- a list **older than one already seen** is refused, which is the replay
  protection;
- it **fails closed**: a list is valid five minutes, and past that the gateway
  admits nobody new, while tunnels already up end with their leases;
- the first list is fetched **before the server listens**: a gateway that
  cannot read it does not start;
- with `GOAUTHN_SSF=true`, the gateway also polls the provider's Shared Signals
  stream (SSF 1.0, poll delivery, RFC 8936) every `GOAUTHN_SSF_INTERVAL`. An
  event only makes the list be fetched at once: it is a trigger, never a
  decision, so a forged event buys one extra fetch and nothing else.

Tenants are matched on the token's `groups` (eduPerson entitlements) and
`idp` (the entity ID of the institution that vouched), and on the email's
domain only when the provider verified the address.

### Configuration

On the server:

```sh
AUTH_PROVIDER=go-authn
OIDC_ISSUER=https://login.example.org
OIDC_CLIENT_ID=claimward                       # the audience of the access tokens
GOAUTHN_GATEWAY_CLIENT_ID=claimward-gw         # the gateway's own client
GOAUTHN_GATEWAY_SECRET_FILE=/etc/claimward/claimward-gw.secret   # from a file only
GOAUTHN_SSF=true                               # optional
```

At the provider (go-authn/bridge's configuration):

```hcl
wireguard {
  lifetime = "24h"              # a key is listed this long; registering it again renews it
  max_keys = 10                 # devices per person
}

client "claimward" {            # the client people sign in with
  device           = true
  wireguard_keys   = true       # its tokens, with the wireguard scope, may register a key
  refresh_lifetime = "720h"
}

client "claimward-gw" {         # the gateway's own client
  secret_file     = "/etc/bridge/claimward-gw.secret"
  wireguard_peers = ["claimward"]   # it reads the keys registered through these clients
  ssf_receiver    = true            # optional: told at once when somebody is disabled
}
```

In the app's `config.json`:

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "go-authn",
  "oidc_issuer": "https://login.example.org",
  "oidc_client_id": "claimward"
}
```

## Adding a provider

On the server, implement `Verifier` (`internal/auth`) and register it in
`auth.New`. On the client, implement `Provider` (`pkg/auth`) and register it in
`auth.New`; a provider that keeps the devices' keys itself also implements
`KeyRegistrar`.
