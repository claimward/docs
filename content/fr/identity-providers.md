---
title: "Fournisseurs d'identité"
weight: 30
description: "GitHub par défaut, n'importe quel émetteur OpenID Connect, ou un fournisseur go-authn, qui sait aussi à qui appartient chaque clé WireGuard."
tags: [github, oidc, go-authn, serveur]
---

Le serveur et les applications choisissent chacun un fournisseur par son nom, et doivent être d'accord :
`AUTH_PROVIDER` sur le serveur, `"provider"` dans le `config.json` de l'application (ou
`CLAIMWARD_AUTH_PROVIDER`). Le jeton porteur (bearer) qu'obtient l'application est opaque sur le réseau ;
la façon dont le serveur le vérifie dépend du fournisseur.

| Fournisseur | Connexion sur l'appareil | Jeton porteur envoyé au serveur | Comment le serveur le vérifie |
|---|---|---|---|
| `github` (par défaut) | flux d'appareil OAuth (device flow) | jeton d'accès OAuth GitHub | API GitHub (`/user`, `/user/orgs`), liste d'organisations autorisées facultative |
| `oidc` | code d'autorisation + PKCE, dans le navigateur | jeton d'identité (ID token) OIDC | signature, émetteur, audience ; liste de domaines de messagerie autorisés facultative |
| `go-authn` | flux d'appareil, puis enregistrement de la clé | jeton d'accès go-authn (`at+jwt`) | signature, émetteur, audience, `typ` ; la clé doit avoir été enregistrée par le même sujet |

## GitHub

Le fournisseur par défaut. L'application déroule le **flux d'appareil** (device flow) de GitHub : elle affiche un code et la
page où le saisir, et ouvre cette page dans le navigateur. Seul un identifiant client
est nécessaire, sans secret : créez donc une **OAuth App** GitHub avec **Device Flow**
activé. L'application demande `read:user`, `user:email` et `read:org`.

Le serveur identifie la personne via l'API GitHub avec son jeton : son
identifiant numérique est le sujet (`github:<id>`), ses organisations
(`/user/orgs`) sont ses groupes pour les [locataires]({{< relref "/tenants.md" >}}), et
son adresse électronique publique, lorsqu'elle en a une, est considérée comme vérifiée. Avec
`GITHUB_ALLOWED_ORGS`, l'appartenance active à l'une de ces organisations est
exigée. Définissez `GITHUB_API_URL` pour GitHub Enterprise.

```sh
AUTH_PROVIDER=github
GITHUB_ALLOWED_ORGS=my-org,my-other-org
```

## OpenID Connect

`AUTH_PROVIDER=oidc` avec `OIDC_ISSUER` (découvert via
`/.well-known/openid-configuration`) et `OIDC_CLIENT_ID`, l'audience que le jeton
d'identité doit porter. L'application déroule le flux du code d'autorisation avec PKCE : elle ouvre
le navigateur et reçoit la redirection sur `http://127.0.0.1:<port>/callback`,
avec un port choisi à chaque connexion. Elle demande `openid profile email
offline_access`. Enregistrez un client **public/natif**, sans secret.

Le serveur prend le sujet, l'adresse électronique et `email_verified`, le
`preferred_username` et la revendication `groups` (une liste, ou une chaîne unique). Avec
`OIDC_ALLOWED_DOMAINS`, le domaine de l'adresse électronique doit être l'un de ceux-là.

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) est un fournisseur OpenID Connect
placé devant une fédération SAML (RENATER, eduGAIN). Il sait aussi
**à qui appartient chaque clé WireGuard**, si bien qu'un jeton valide ne suffit plus pour
enrôler un appareil :

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
   l'audience est `OIDC_CLIENT_ID`, jamais un jeton d'identité. Il n'enrôle la clé que si
   la liste du fournisseur l'indique **enregistrée par le même sujet** ; sinon il
   répond `403 key_not_registered`. Un bail ne survit jamais à l'enregistrement
   de la clé.

La liste provient de [go-authn/wireguard](https://github.com/go-authn/wireguard) :

- elle est **récupérée avec le client propre de la passerelle** (`client_credentials`, portée
  `wireguard_peers`) et signée par le fournisseur pour cette seule passerelle
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

Sur le serveur :

```sh
AUTH_PROVIDER=go-authn
OIDC_ISSUER=https://login.example.org
OIDC_CLIENT_ID=claimward                       # the audience of the access tokens
GOAUTHN_GATEWAY_CLIENT_ID=claimward-gw         # the gateway's own client
GOAUTHN_GATEWAY_SECRET_FILE=/etc/claimward/claimward-gw.secret   # from a file only
GOAUTHN_SSF=true                               # optional
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

Dans le `config.json` de l'application :

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "go-authn",
  "oidc_issuer": "https://login.example.org",
  "oidc_client_id": "claimward"
}
```

## Ajouter un fournisseur {#adding-a-provider}

Sur le serveur, implémentez `Verifier` (`internal/auth`) et enregistrez-le dans
`auth.New`. Sur le client, implémentez `Provider` (`pkg/auth`) et enregistrez-le dans
`auth.New` ; un fournisseur qui conserve lui-même les clés des appareils implémente aussi
`KeyRegistrar`.
