---
title: "Identitätsanbieter"
weight: 30
description: "Standardmäßig GitHub, ein beliebiger OpenID-Connect-Issuer oder ein go-authn-Anbieter, der außerdem festhält, wem jeder WireGuard-Schlüssel gehört."
tags: [github, oidc, go-authn, server]
---

Der Server und die Apps wählen jeweils einen Anbieter über seinen Namen, und sie müssen übereinstimmen:
`AUTH_PROVIDER` auf dem Server, `"provider"` in der `config.json` der App (oder
`CLAIMWARD_AUTH_PROVIDER`). Das Bearer-Token, das die App erhält, ist auf der Leitung opak;
wie der Server es prüft, hängt vom Anbieter ab.

| Anbieter | Anmeldung auf dem Gerät | An den Server gesendetes Bearer-Token | Wie der Server es prüft |
|---|---|---|---|
| `github` (Standard) | OAuth Device Flow | GitHub-OAuth-Access-Token | GitHub-API (`/user`, `/user/orgs`), optionale Allowlist für Organisationen |
| `oidc` | Authorization Code + PKCE, im Browser | OIDC-ID-Token | Signatur, Issuer, Audience; optionale Allowlist für E-Mail-Domains |
| `go-authn` | Device Flow, dann Registrierung des Schlüssels | go-authn-Access-Token (`at+jwt`) | Signatur, Issuer, Audience, `typ`; der Schlüssel muss vom selben Subject registriert sein |

## GitHub

Der Standard. Die App führt den GitHub-**Device Flow** aus: Sie zeigt einen Code und die
Seite an, auf der er einzugeben ist, und öffnet diese Seite im Browser. Es wird nur eine Client-ID
benötigt, kein Secret; legen Sie also eine GitHub-**OAuth App** mit aktiviertem **Device Flow**
an. Die App fordert `read:user`, `user:email` und `read:org` an.

Der Server ermittelt die Person über die GitHub-API mit deren Token: Ihre
numerische ID ist das Subject (`github:<id>`), ihre Organisationen
(`/user/orgs`) sind ihre Gruppen für die [Mandanten]({{< relref "/tenants.md" >}}), und
ihre öffentliche E-Mail-Adresse, sofern sie eine hat, gilt als verifiziert. Mit
`GITHUB_ALLOWED_ORGS` ist eine aktive Mitgliedschaft in einer dieser Organisationen
erforderlich. Setzen Sie `GITHUB_API_URL` für GitHub Enterprise.

```sh
AUTH_PROVIDER=github
GITHUB_ALLOWED_ORGS=my-org,my-other-org
```

## OpenID Connect

`AUTH_PROVIDER=oidc` mit `OIDC_ISSUER` (ermittelt über
`/.well-known/openid-configuration`) und `OIDC_CLIENT_ID`, der Audience, die das ID-Token
tragen muss. Die App führt den Authorization Code Flow mit PKCE aus: Sie öffnet
den Browser und empfängt die Weiterleitung auf `http://127.0.0.1:<port>/callback`,
mit einem bei jeder Anmeldung gewählten Port. Sie fordert `openid profile email
offline_access` an. Registrieren Sie einen **öffentlichen/nativen** Client, ohne Secret.

Der Server übernimmt das Subject, die E-Mail-Adresse und `email_verified`, den
`preferred_username` und den Claim `groups` (eine Liste oder eine einzelne Zeichenkette). Mit
`OIDC_ALLOWED_DOMAINS` muss die Domain der E-Mail-Adresse eine davon sein.

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) ist ein OpenID-Connect-Anbieter
vor einer SAML-Föderation (RENATER, eduGAIN). Er hält außerdem fest,
**wem jeder WireGuard-Schlüssel gehört**, sodass ein gültiges Token nicht mehr genügt, um
ein Gerät zu registrieren:

1. Die App meldet sich mit dem **Device Flow** des Anbieters an, Scope
   `openid wireguard`. Dieses Token öffnet das Schlüsselregister des Anbieters und
   sonst nichts: Der Anbieter adressiert ein Token, das einen seiner eigenen Scopes trägt,
   ausschließlich an sich selbst.
2. Bei jeder Verbindung registriert die App den **öffentlichen** Schlüssel des Geräts
   (`POST /wireguard/key`), was ihn erneuert, wenn er bereits der Person gehört,
   und frischt dann für `scope=openid` allein auf. Das ergibt ein **Access-Token**,
   das an den VPN-Server adressiert ist. Der Anbieter rotiert die Refresh-Tokens, und die
   App bewahrt das neue auf. Der private Schlüssel verlässt nie das Gerät.
3. Der Server akzeptiert nur ein Access-Token (`typ: at+jwt`, RFC 9068), dessen
   Audience `OIDC_CLIENT_ID` ist, niemals ein ID-Token. Er registriert den Schlüssel nur, wenn
   die Liste des Anbieters ihn als **vom selben Subject registriert** führt; andernfalls
   antwortet er `403 key_not_registered`. Eine Lease überdauert nie die
   Registrierung des Schlüssels.

Die Liste stammt von [go-authn/wireguard](https://github.com/go-authn/wireguard):

- sie wird **mit dem eigenen Client des Gateways abgerufen** (`client_credentials`, Scope
  `wireguard_peers`) und vom Anbieter allein für dieses Gateway signiert
  (`typ: wireguard-peers+jwt`);
- sie wird alle `GOAUTHN_PEER_LIST_INTERVAL` (standardmäßig 30 Sekunden)
  erneut abgerufen. Ein Schlüssel, den der Anbieter zurückzieht (die Person oder ihre Einrichtung
  deaktiviert oder das Gerät entfernt), wird beim nächsten Abruf aus `wg0` entfernt,
  und sein Heartbeat wird abgelehnt;
- eine Liste, die **älter ist als eine bereits gesehene**, wird abgelehnt; das ist der
  Schutz vor Replay-Angriffen;
- sie ist **ausfallsicher geschlossen** (fail closed): Eine Liste ist fünf Minuten gültig, danach lässt das Gateway
  niemanden Neues mehr zu, während bereits aufgebaute Tunnel mit ihren Leases enden;
- die erste Liste wird abgerufen, **bevor der Server lauscht**: Ein Gateway, das
  sie nicht lesen kann, startet nicht;
- mit `GOAUTHN_SSF=true` fragt das Gateway außerdem den Shared-Signals-Stream des Anbieters
  (SSF 1.0, Poll-Zustellung, RFC 8936) alle `GOAUTHN_SSF_INTERVAL` ab. Ein
  Ereignis bewirkt nur, dass die Liste sofort abgerufen wird: Es ist ein Auslöser, niemals eine
  Entscheidung, sodass ein gefälschtes Ereignis einen zusätzlichen Abruf bewirkt und sonst nichts.

Mandanten werden anhand der `groups` des Tokens (eduPerson-Entitlements) und
`idp` (der Entity-ID der Einrichtung, die gebürgt hat) zugeordnet, und anhand der Domain der E-Mail-Adresse
nur dann, wenn der Anbieter die Adresse verifiziert hat.

### Konfiguration {#configuration}

Auf dem Server:

```sh
AUTH_PROVIDER=go-authn
OIDC_ISSUER=https://login.example.org
OIDC_CLIENT_ID=claimward                       # the audience of the access tokens
GOAUTHN_GATEWAY_CLIENT_ID=claimward-gw         # the gateway's own client
GOAUTHN_GATEWAY_SECRET_FILE=/etc/claimward/claimward-gw.secret   # from a file only
GOAUTHN_SSF=true                               # optional
```

Beim Anbieter (Konfiguration von go-authn/bridge):

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

In der `config.json` der App:

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "go-authn",
  "oidc_issuer": "https://login.example.org",
  "oidc_client_id": "claimward"
}
```

## Einen Anbieter hinzufügen {#adding-a-provider}

Implementieren Sie auf dem Server `Verifier` (`internal/auth`) und registrieren Sie ihn in
`auth.New`. Implementieren Sie auf dem Client `Provider` (`pkg/auth`) und registrieren Sie ihn in
`auth.New`; ein Anbieter, der die Schlüssel der Geräte selbst verwaltet, implementiert außerdem
`KeyRegistrar`.
