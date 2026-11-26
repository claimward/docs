---
title: "Identitätsanbieter"
weight: 30
description: "Mehrere Anbieter gleichzeitig, in einer Datei aufgeführt: GitHub, ein beliebiger OpenID-Connect-Issuer oder ein go-authn-Anbieter, der außerdem festhält, wem jeder WireGuard-Schlüssel gehört."
tags: [github, oidc, go-authn, server]
---

Seit Server v0.14.0 (**inkompatible Änderung**) akzeptiert der Server **mehrere** Identitätsanbieter
gleichzeitig, aufgeführt in einer JSON-Datei, die `PROVIDERS_FILE` benennt. Die alten
Variablen für einen einzelnen Anbieter (`AUTH_PROVIDER`, `OIDC_ISSUER`, `OIDC_CLIENT_ID`,
`OIDC_ALLOWED_DOMAINS`, `GITHUB_CLIENT_ID`, `GITHUB_ALLOWED_ORGS`,
`GOAUTHN_GATEWAY_CLIENT_ID`) werden nicht mehr gelesen, und der Server startet
nicht, solange eine davon gesetzt ist. Das Bearer-Token, das die App erhält, ist auf der Leitung opak;
wie der Server es prüft, hängt vom Anbieter ab.

## Die Anbieter-Datei

`PROVIDERS_FILE` ist ein JSON-Objekt mit einer Liste `providers`. Unbekannte Felder werden
abgelehnt, und die Datei ist höchstens 1 MiB groß:

```json
{"providers":[
  {"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]},
  {"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org"]},
  {"id":"renater","kind":"go-authn","name":"RENATER","oidc_issuer":"https://login.example.org","oidc_client_id":"claimward","gateway_client_id":"claimward-gw"}
]}
```

Jeder Anbieter hat eine `id` (unter der eine Anfrage ihn benennt), ein `kind` und einen
`name` (der Person angezeigt). Die übrigen Felder hängen vom `kind` ab:

| `kind` | Anmeldung auf dem Gerät | An den Server gesendetes Bearer-Token | Felder außer `id`, `kind`, `name` | Secret-Datei |
|---|---|---|---|---|
| `github` | OAuth Device Flow | GitHub-OAuth-Access-Token | `github_client_id`, `api_url` (GitHub Enterprise), `allowed_orgs` | `provider-<id>-secret` |
| `oidc` | Authorization Code + PKCE, im Browser | OIDC-ID-Token | `oidc_issuer`, `oidc_client_id`, `allowed_domains` | keine |
| `go-authn` | Device Flow, dann Registrierung des Schlüssels | go-authn-Access-Token (`at+jwt`) | `oidc_issuer`, `oidc_client_id`, `gateway_client_id` | `provider-<id>-gateway-secret` |

Die Secret-Dateien sind Zugangsdaten, Dateien in `CREDENTIALS_DIRECTORY`, niemals
Variablen (siehe [Zugangsdaten]({{< relref "/components/server.md#credentials" >}})).
Vor v0.14.0 hießen sie `github-client-secret` und `goauthn-gateway-secret`.

**Die Anfrage benennt ihren Anbieter.** Jeder API-Aufruf trägt den Header
`Claimward-Provider: <id>` (gRPC: die Metadaten `claimward-provider`), und sein
Token wird von diesem Anbieter **allein** geprüft: Ein Token des Anbieters A wird abgelehnt,
wenn die Anfrage B benennt. Ohne Header gibt es `401 missing_provider`, eine ID, die der Server
nicht führt, ergibt `401 unknown_provider`. Das
[Discovery-Dokument]({{< relref "/reference/protocol.md#discovery" >}}) (Version
2) listet die Anbieter ohne jedes Secret auf, ein Client braucht also nur die URL des Servers.

**Eine Identität je Issuer und `sub`.** Die Identität ist `issuer#sub` für `oidc`
und `go-authn` und `github:<id>` für `github`: Dasselbe `sub` bei zwei Issuern sind
zwei Personen, und die zweite kann das Gerät der ersten nicht übernehmen.

**Mandanten.** Ein Mandant erhält ein Feld `providers`, und seine Gruppen werden
`<Anbieter-ID>:<Gruppe>` geschrieben. Bei mehreren Anbietern muss ein Mandant, der `domains` oder
`idps` verwendet, `providers` benennen, sonst schlägt der Server geschlossen fehl (fail closed). Siehe
[Mandanten]({{< relref "/tenants.md" >}}).

**Logo.** `SERVER_LOGO_FILE` (eine SVG, höchstens 64 KiB, beim Start validiert) wird
unter `/.well-known/claimward-logo.svg` ausgeliefert, und das Discovery-Dokument nennt
unter `logo` seinen `path` und seinen `sha256`.

## GitHub

Die App führt den GitHub-**Device Flow** aus: Sie zeigt einen Code und die
Seite an, auf der er einzugeben ist, und öffnet diese Seite im Browser. Auf dem Gerät wird nur eine Client-ID
benötigt; legen Sie also eine GitHub-**OAuth App** mit aktiviertem **Device Flow**
an, tragen Sie ihre ID in `github_client_id` ein und ihr Client-Secret in die Datei
`provider-<id>-secret`. Die App fordert `read:user`, `user:email` und `read:org` an.

Der Server fragt zuerst mit diesem Secret bei GitHub nach, ob das Token von
**dieser OAuth App** ausgestellt wurde (nur diese werden zugelassen), und ermittelt dann die Person über die GitHub-API:
Ihre numerische ID ist das Subject (`github:<id>`), ihre Organisationen
(`/user/orgs`) sind ihre Gruppen für die [Mandanten]({{< relref "/tenants.md" >}}), und
ihre öffentliche E-Mail-Adresse, sofern sie eine hat, gilt als verifiziert. Mit
`allowed_orgs` lässt eine aktive Mitgliedschaft in einer dieser Organisationen
zu, ebenso ein benannter `members`-Eintrag eines Mandanten (an die Konto-ID
gebunden, siehe [Mandanten]({{< relref "/tenants.md#members" >}})). Die Liste ist nur
optional, wenn ein Mandant Mitglieder hat: Ohne beides startet der Server nicht, ebenso
ohne Client-ID oder ohne Secret-Datei. Setzen Sie `api_url` für GitHub Enterprise.

```json
{"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org","my-other-org"]}
```

## OpenID Connect

`kind` `oidc` mit `oidc_issuer` (ermittelt über
`/.well-known/openid-configuration`) und `oidc_client_id`, der Audience, die das ID-Token
tragen muss. Die App führt den Authorization Code Flow mit PKCE aus: Sie öffnet
den Browser und empfängt die Weiterleitung auf `http://127.0.0.1:<port>/callback`,
mit einem bei jeder Anmeldung gewählten Port. Sie fordert `openid profile email
offline_access` an. Registrieren Sie einen **öffentlichen/nativen** Client, ohne Secret; diese
Art hat daher keine Secret-Datei.

Der Server übernimmt das Subject, die E-Mail-Adresse und `email_verified`, den
`preferred_username` und den Claim `groups` (eine Liste oder eine einzelne Zeichenkette). Mit
`allowed_domains` muss die Domain der E-Mail-Adresse eine davon sein, und die Adresse
muss verifiziert sein.

```json
{"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]}
```

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) ist ein OpenID-Connect-Anbieter
vor einer SAML-Föderation (RENATER, eduGAIN). Er hält außerdem fest,
**wem jeder WireGuard-Schlüssel gehört**, sodass ein gültiges Token nicht mehr genügt, um
ein Gerät zu registrieren. Höchstens ein Anbieter der Datei ist von dieser Art.

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
   Audience der `oidc_client_id` des Anbieters ist, niemals ein ID-Token. Er registriert den Schlüssel nur, wenn
   die Liste des Anbieters ihn als **vom selben Subject registriert** führt; andernfalls
   antwortet er `403 key_not_registered`. Eine Lease überdauert nie die
   Registrierung des Schlüssels.

Die Liste stammt von [go-authn/wireguard](https://github.com/go-authn/wireguard):

- sie wird **mit dem eigenen Client des Gateways abgerufen** (`gateway_client_id`,
  `client_credentials`, Scope `wireguard_peers`, sein Secret in
  `provider-<id>-gateway-secret`) und vom Anbieter allein für dieses Gateway signiert
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

Auf dem Server, in `PROVIDERS_FILE`:

```json
{"providers":[
  {"id":"renater","kind":"go-authn","name":"RENATER",
   "oidc_issuer":"https://login.example.org",
   "oidc_client_id":"claimward",
   "gateway_client_id":"claimward-gw"}
]}
```

`oidc_client_id` ist die Audience der Access-Tokens, `gateway_client_id` der eigene Client
des Gateways. Die Umgebung ergänzt das Zugangsdaten-Verzeichnis, das `wg-private-key` und
`provider-renater-gateway-secret` enthält (das Secret des Gateways, nur als Datei),
sowie optional den Shared-Signals-Stream:

```sh
PROVIDERS_FILE=/etc/claimward/providers.json
CREDENTIALS_DIRECTORY=/etc/claimward/credentials
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

Der Client (ab v0.10.0) liest die Anbieter aus dem Discovery-Dokument des Servers; seine
`config.json` braucht daher nur die URL des Servers, und er sendet die `id` des gewählten
Anbieters im Header `Claimward-Provider`:

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com"}
  ]
}
```

(Ein Eintrag kann `provider` erhalten, um die `id` des gewählten Anbieters zu merken.)

## Einen Anbieter hinzufügen {#adding-a-provider}

Implementieren Sie auf dem Server `Verifier` (`internal/auth`) und registrieren Sie ihn in
`auth.New`. Implementieren Sie auf dem Client `Provider` (`pkg/auth`) und registrieren Sie ihn in
`auth.New`; ein Anbieter, der die Schlüssel der Geräte selbst verwaltet, implementiert außerdem
`KeyRegistrar`.
