---
title: "Identity providers"
weight: 30
description: "Several providers at once, listed in a file: GitHub, any OpenID Connect issuer, or a go-authn provider, which also keeps whose each WireGuard key is."
tags: [github, oidc, go-authn, server]
---

Since server v0.14.0 (**breaking**) the server accepts **several** identity
providers at once, listed in a JSON file named by `PROVIDERS_FILE`. The old
single-provider variables (`AUTH_PROVIDER`, `OIDC_ISSUER`, `OIDC_CLIENT_ID`,
`OIDC_ALLOWED_DOMAINS`, `GITHUB_CLIENT_ID`, `GITHUB_ALLOWED_ORGS`,
`GOAUTHN_GATEWAY_CLIENT_ID`) are no longer read, and the server refuses to
start while one of them is set. The bearer the app obtains is opaque on the
wire; how the server verifies it depends on the provider.

## The providers file

`PROVIDERS_FILE` is a JSON object with a `providers` list. Unknown fields are
refused, and the file is 1 MiB at most:

```json
{"providers":[
  {"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]},
  {"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org"]},
  {"id":"renater","kind":"go-authn","name":"RENATER","oidc_issuer":"https://login.example.org","oidc_client_id":"claimward","gateway_client_id":"claimward-gw"}
]}
```

Every provider has an `id` (what a request names it by), a `kind` and a
`name` (shown to the person). The other fields depend on the `kind`:

| `kind` | Sign-in on the device | Bearer sent to the server | Fields besides `id`, `kind`, `name` | Secret file |
|---|---|---|---|---|
| `github` | OAuth device flow | GitHub OAuth access token | `github_client_id`, `api_url` (GitHub Enterprise), `allowed_orgs` | `provider-<id>-secret` |
| `oidc` | authorization code + PKCE, in the browser | OIDC ID token | `oidc_issuer`, `oidc_client_id`, `allowed_domains` | none |
| `go-authn` | device flow, then key registration | go-authn access token (`at+jwt`) | `oidc_issuer`, `oidc_client_id`, `gateway_client_id` | `provider-<id>-gateway-secret` |

The secret files are credentials, files in `CREDENTIALS_DIRECTORY`, never
variables (see [Credentials]({{< relref "/components/server.md#credentials" >}})).
They were `github-client-secret` and `goauthn-gateway-secret` before v0.14.0.

**The request names its provider.** Every API call carries the header
`Claimward-Provider: <id>` (gRPC: the metadata `claimward-provider`), and its
token is verified by that provider **alone**: a token of provider A is refused
when the request names B. No header is `401 missing_provider`, an id the server
does not list is `401 unknown_provider`. The
[discovery document]({{< relref "/reference/protocol.md#discovery" >}}) (version
2) lists the providers, with no secret, so a client needs only the server's URL.

**One identity per issuer and `sub`.** The identity is `issuer#sub` for `oidc`
and `go-authn`, and `github:<id>` for `github`: the same `sub` at two issuers is
two people, and the second cannot take over the first's device.

**Tenants.** A tenant gains a `providers` field, and its groups are written
`<provider id>:<group>`. With several providers, a tenant that uses `domains` or
`idps` must name `providers`, or the server fails closed. See
[tenants]({{< relref "/tenants.md" >}}).

**Logo.** `SERVER_LOGO_FILE` (an SVG, 64 KiB at most, validated at start) is
served at `/.well-known/claimward-logo.svg`, and the discovery document gives
its `path` and `sha256` under `logo`.

## GitHub

The app runs the GitHub **device flow**: it shows a code and the page where to
enter it, and opens that page in the browser. Only a client ID is needed on the
device, so create a GitHub **OAuth App** with **Device Flow** enabled, put its
ID in `github_client_id`, and its client secret in the file
`provider-<id>-secret`. The app asks for `read:user`, `user:email` and
`read:org`.

The server first asks GitHub, with that secret, whether the token was minted by
**that OAuth app** (only those are admitted), then resolves the person through
the GitHub API: their numeric ID is the subject (`github:<id>`), their
organisations (`/user/orgs`) are their groups for
[tenants]({{< relref "/tenants.md" >}}), and their public email, when they have
one, counts as verified. With `allowed_orgs`, an active membership of one of
those organisations admits them, and so does being a named `members` entry of a
tenant (pinned to the account ID, see
[tenants]({{< relref "/tenants.md#members" >}})). The list is optional only
when a tenant has members: with neither, the server refuses to start, and so it
does without a client ID or without the secret file. Set `api_url` for GitHub
Enterprise.

```json
{"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org","my-other-org"]}
```

## OpenID Connect

`kind` `oidc` with `oidc_issuer` (discovered through
`/.well-known/openid-configuration`) and `oidc_client_id`, the audience the ID
token must carry. The app runs the authorization code flow with PKCE: it opens
the browser and receives the redirect on `http://127.0.0.1:<port>/callback`,
with a port chosen at each sign-in. It asks for `openid profile email
offline_access`. Register a **public/native** client, without a secret, so this
kind has no secret file.

The server takes the subject, the email and `email_verified`, the
`preferred_username` and the `groups` claim (a list, or a single string). With
`allowed_domains`, the email's domain must be one of those, and the email must
be verified.

```json
{"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]}
```

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) is an OpenID Connect
provider in front of a SAML federation (RENATER, eduGAIN). It also keeps
**whose each WireGuard key is**, so a valid token is no longer enough to
enroll a device. At most one provider of the file is of this kind.

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
   audience is the provider's `oidc_client_id`, never an ID token. It enrolls
   the key only if the provider's list has it **registered by the same
   subject**; otherwise it answers `403 key_not_registered`. A lease never
   outlives the key's registration.

The list comes from [go-authn/wireguard](https://github.com/go-authn/wireguard):

- it is **fetched with the gateway's own client** (`gateway_client_id`,
  `client_credentials`, scope `wireguard_peers`, its secret in
  `provider-<id>-gateway-secret`) and signed by the provider for that gateway
  alone (`typ: wireguard-peers+jwt`);
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

On the server, in `PROVIDERS_FILE`:

```json
{"providers":[
  {"id":"renater","kind":"go-authn","name":"RENATER",
   "oidc_issuer":"https://login.example.org",
   "oidc_client_id":"claimward",
   "gateway_client_id":"claimward-gw"}
]}
```

`oidc_client_id` is the audience of the access tokens, `gateway_client_id` the
gateway's own client. The environment adds the credentials directory, which
holds `wg-private-key` and `provider-renater-gateway-secret` (the gateway's
secret, a file only), and optionally the Shared Signals stream:

```sh
PROVIDERS_FILE=/etc/claimward/providers.json
CREDENTIALS_DIRECTORY=/etc/claimward/credentials
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

The client (v0.10.0 or later) reads the providers from the server's discovery
document, so its `config.json` needs only the server's URL, and it sends the
chosen provider's `id` in `Claimward-Provider`:

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com"}
  ]
}
```

(`provider` may be added to an entry to remember the chosen provider's `id`.)

## Adding a provider

On the server, implement `Verifier` (`internal/auth`) and register it in
`auth.New`. On the client, implement `Provider` (`pkg/auth`) and register it in
`auth.New`; a provider that keeps the devices' keys itself also implements
`KeyRegistrar`.
