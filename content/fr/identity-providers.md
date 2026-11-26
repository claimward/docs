---
title: "Fournisseurs d'identité"
weight: 30
description: "Plusieurs fournisseurs à la fois, listés dans un fichier : GitHub, n'importe quel émetteur OpenID Connect, ou un fournisseur go-authn, qui sait aussi à qui appartient chaque clé WireGuard."
tags: [github, oidc, go-authn, serveur]
---

Depuis le serveur v0.14.0 (**rupture de compatibilité**), le serveur accepte **plusieurs** fournisseurs
d'identité à la fois, listés dans un fichier JSON désigné par `PROVIDERS_FILE`. Les anciennes
variables à fournisseur unique (`AUTH_PROVIDER`, `OIDC_ISSUER`, `OIDC_CLIENT_ID`,
`OIDC_ALLOWED_DOMAINS`, `GITHUB_CLIENT_ID`, `GITHUB_ALLOWED_ORGS`,
`GOAUTHN_GATEWAY_CLIENT_ID`) ne sont plus lues, et le serveur refuse de
démarrer tant que l'une d'elles est définie. Le jeton porteur (bearer) qu'obtient l'application est opaque sur le réseau ;
la façon dont le serveur le vérifie dépend du fournisseur.

## Le fichier des fournisseurs

`PROVIDERS_FILE` est un objet JSON avec une liste `providers`. Les champs inconnus sont
refusés, et le fichier fait 1 Mio au plus :

```json
{"providers":[
  {"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]},
  {"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org"]},
  {"id":"renater","kind":"go-authn","name":"RENATER","oidc_issuer":"https://login.example.org","oidc_client_id":"claimward","gateway_client_id":"claimward-gw"}
]}
```

Chaque fournisseur a un `id` (le nom par lequel une requête le désigne), un `kind` et un
`name` (montré à la personne). Les autres champs dépendent du `kind` :

| `kind` | Connexion sur l'appareil | Jeton porteur envoyé au serveur | Champs en plus de `id`, `kind`, `name` | Fichier secret |
|---|---|---|---|---|
| `github` | flux d'appareil OAuth (device flow) | jeton d'accès OAuth GitHub | `github_client_id`, `api_url` (GitHub Enterprise), `allowed_orgs` | `provider-<id>-secret` |
| `oidc` | code d'autorisation + PKCE, dans le navigateur | jeton d'identité (ID token) OIDC | `oidc_issuer`, `oidc_client_id`, `allowed_domains` | aucun |
| `go-authn` | flux d'appareil, puis enregistrement de la clé | jeton d'accès go-authn (`at+jwt`) | `oidc_issuer`, `oidc_client_id`, `gateway_client_id` | `provider-<id>-gateway-secret` |

Les fichiers secrets sont des identifiants, des fichiers de `CREDENTIALS_DIRECTORY`, jamais des
variables (voir [Identifiants]({{< relref "/components/server.md#credentials" >}})).
Ils s'appelaient `github-client-secret` et `goauthn-gateway-secret` avant la v0.14.0.

**La requête désigne son fournisseur.** Chaque appel d'API porte l'en-tête
`Claimward-Provider: <id>` (gRPC : la métadonnée `claimward-provider`), et son
jeton est vérifié par ce fournisseur **seul** : un jeton du fournisseur A est refusé
quand la requête désigne B. Sans en-tête, c'est `401 missing_provider` ; un identifiant que le serveur
ne liste pas donne `401 unknown_provider`. Le
[document de découverte]({{< relref "/reference/protocol.md#discovery" >}}) (version
2) liste les fournisseurs, sans aucun secret : un client n'a donc besoin que de l'URL du serveur.

**Une identité par émetteur et par `sub`.** L'identité est `issuer#sub` pour `oidc`
et `go-authn`, et `github:<id>` pour `github` : le même `sub` chez deux émetteurs est
deux personnes, et la seconde ne peut pas prendre l'appareil de la première.

**Locataires.** Un locataire gagne un champ `providers`, et ses groupes s'écrivent
`<id du fournisseur>:<groupe>`. Avec plusieurs fournisseurs, un locataire qui utilise `domains` ou
`idps` doit nommer `providers`, sinon le serveur échoue en mode fermé. Voir les
[locataires]({{< relref "/tenants.md" >}}).

**Logo.** `SERVER_LOGO_FILE` (un SVG, 64 Kio au plus, validé au démarrage) est
servi sur `/.well-known/claimward-logo.svg`, et le document de découverte donne
son `path` et son `sha256` sous `logo`.

## GitHub

L'application déroule le **flux d'appareil** (device flow) de GitHub : elle affiche un code et la
page où le saisir, et ouvre cette page dans le navigateur. Seul un identifiant client
est nécessaire sur l'appareil : créez donc une **OAuth App** GitHub avec **Device Flow**
activé, mettez son identifiant dans `github_client_id` et son secret client dans le fichier
`provider-<id>-secret`. L'application demande `read:user`, `user:email` et `read:org`.

Le serveur demande d'abord à GitHub, avec ce secret, si le jeton a été émis par
**cette OAuth App** (seuls ceux-là sont admis), puis identifie la personne via l'API GitHub :
son identifiant numérique est le sujet (`github:<id>`), ses organisations
(`/user/orgs`) sont ses groupes pour les [locataires]({{< relref "/tenants.md" >}}), et
son adresse électronique publique, lorsqu'elle en a une, est considérée comme vérifiée. Avec
`allowed_orgs`, l'appartenance active à l'une de ces organisations
l'admet, de même qu'une entrée `members` nommée d'un locataire (épinglée à
l'identifiant du compte, voir les [locataires]({{< relref "/tenants.md#members" >}})). La
liste n'est facultative que si un locataire a des membres : sans l'un ni l'autre,
le serveur refuse de démarrer, de même sans identifiant client ou sans fichier secret.
Définissez `api_url` pour GitHub Enterprise.

```json
{"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org","my-other-org"]}
```

## OpenID Connect

`kind` `oidc` avec `oidc_issuer` (découvert via
`/.well-known/openid-configuration`) et `oidc_client_id`, l'audience que le jeton
d'identité doit porter. L'application déroule le flux du code d'autorisation avec PKCE : elle ouvre
le navigateur et reçoit la redirection sur `http://127.0.0.1:<port>/callback`,
avec un port choisi à chaque connexion. Elle demande `openid profile email
offline_access`. Enregistrez un client **public/natif**, sans secret : ce type
n'a donc pas de fichier secret.

Le serveur prend le sujet, l'adresse électronique et `email_verified`, le
`preferred_username` et la revendication `groups` (une liste, ou une chaîne unique). Avec
`allowed_domains`, le domaine de l'adresse électronique doit être l'un de ceux-là, et l'adresse
doit être vérifiée.

```json
{"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]}
```

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) est un fournisseur OpenID Connect
placé devant une fédération SAML (RENATER, eduGAIN). Il sait aussi
**à qui appartient chaque clé WireGuard**, si bien qu'un jeton valide ne suffit plus pour
enrôler un appareil. Au plus un fournisseur du fichier est de ce type.

1. L'application se connecte avec le **flux d'appareil** du fournisseur, portée
   `openid wireguard`. Ce jeton ouvre le registre de clés du fournisseur et
   rien d'autre : le fournisseur adresse un jeton portant l'une de ses propres portées
   à lui seul.
2. À chaque connexion, l'application enregistre la clé **publique** de l'appareil
   (`POST /wireguard/key`), ce qui la renouvelle lorsqu'elle appartient déjà à la personne,
   puis rafraîchit pour `scope=openid` seul. On obtient ainsi un **jeton d'accès**
   adressé au serveur VPN. Le fournisseur fait tourner les jetons de rafraîchissement, et
   l'application conserve le nouveau. La clé privée ne quitte jamais l'appareil.
3. Le serveur n'accepte qu'un jeton d'accès (`typ: at+jwt`, RFC 9068) dont
   l'audience est l'`oidc_client_id` du fournisseur, jamais un jeton d'identité. Il n'enrôle la clé que si
   la liste du fournisseur l'indique **enregistrée par le même sujet** ; sinon il
   répond `403 key_not_registered`. Un bail ne survit jamais à l'enregistrement
   de la clé.

La liste provient de [go-authn/wireguard](https://github.com/go-authn/wireguard) :

- elle est **récupérée avec le client propre de la passerelle** (`gateway_client_id`,
  `client_credentials`, portée `wireguard_peers`, son secret dans
  `provider-<id>-gateway-secret`) et signée par le fournisseur pour cette seule passerelle
  (`typ: wireguard-peers+jwt`) ;
- elle est récupérée de nouveau toutes les `GOAUTHN_PEER_LIST_INTERVAL` (30 secondes par
  défaut). Une clé que le fournisseur reprend (la personne ou son établissement
  désactivés, ou l'appareil supprimé) est retirée de `wg0` à la récupération suivante,
  et son heartbeat est refusé ;
- une liste **plus ancienne qu'une liste déjà vue** est refusée, ce qui constitue la protection
  contre le rejeu ;
- elle **échoue en mode fermé** (fail closed) : une liste est valable cinq minutes, et au-delà la passerelle
  n'admet plus personne de nouveau, tandis que les tunnels déjà établis se terminent avec leurs baux ;
- la première liste est récupérée **avant que le serveur n'écoute** : une passerelle qui
  ne peut pas la lire ne démarre pas ;
- avec `GOAUTHN_SSF=true`, la passerelle interroge aussi le flux Shared Signals du fournisseur
  (SSF 1.0, livraison par interrogation, RFC 8936) toutes les `GOAUTHN_SSF_INTERVAL`. Un
  événement ne fait que provoquer la récupération immédiate de la liste : c'est un déclencheur, jamais une
  décision, si bien qu'un événement forgé n'obtient qu'une récupération supplémentaire et rien d'autre.

Les locataires sont mis en correspondance sur les `groups` du jeton (droits eduPerson) et
`idp` (l'entity ID de l'établissement qui s'est porté garant), et sur le domaine
de l'adresse électronique uniquement lorsque le fournisseur a vérifié l'adresse.

### Configuration

Sur le serveur, dans `PROVIDERS_FILE` :

```json
{"providers":[
  {"id":"renater","kind":"go-authn","name":"RENATER",
   "oidc_issuer":"https://login.example.org",
   "oidc_client_id":"claimward",
   "gateway_client_id":"claimward-gw"}
]}
```

`oidc_client_id` est l'audience des jetons d'accès, `gateway_client_id` le client propre
de la passerelle. L'environnement ajoute le répertoire des identifiants, qui contient
`wg-private-key` et `provider-renater-gateway-secret` (le secret de la passerelle,
uniquement en fichier), et éventuellement le flux Shared Signals :

```sh
PROVIDERS_FILE=/etc/claimward/providers.json
CREDENTIALS_DIRECTORY=/etc/claimward/credentials
GOAUTHN_SSF=true                               # facultatif
```

Chez le fournisseur (configuration de go-authn/bridge) :

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

Le client (v0.10.0 ou ultérieur) lit les fournisseurs dans le document de découverte
du serveur : son `config.json` n'a donc besoin que de l'URL du serveur, et il envoie
l'`id` du fournisseur choisi dans `Claimward-Provider` :

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com"}
  ]
}
```

(On peut ajouter `provider` à une entrée pour mémoriser l'`id` du fournisseur choisi.)

## Ajouter un fournisseur {#adding-a-provider}

Sur le serveur, implémentez `Verifier` (`internal/auth`) et enregistrez-le dans
`auth.New`. Sur le client, implémentez `Provider` (`pkg/auth`) et enregistrez-le dans
`auth.New` ; un fournisseur qui conserve lui-même les clés des appareils implémente aussi
`KeyRegistrar`.
