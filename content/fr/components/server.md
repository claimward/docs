---
title: "Serveur"
linkTitle: "Serveur"
weight: 1
description: "claimward-vpn-server : vérifie la connexion, attribue les adresses VPN, programme la passerelle WireGuard, diffuse les routes des locataires via gRPC, et sert une API d'administration et des métriques."
tags: [serveur, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.2.0** est le plan de contrôle. Il vérifie le jeton porteur (bearer) que présente un appareil,
attribue les adresses VPN, et programme la passerelle WireGuard avec un pair par
appareil enrôlé. Il s'exécute sur l'hôte de passerelle Linux, à côté d'un `wg0` existant.

## Ce qu'il sert {#what-it-serves}

| Écoute | Chemin | Rôle |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | vérifier, choisir le locataire, attribuer une adresse, ajouter le pair, renvoyer la configuration du tunnel |
| | `GET /api/v1/tenants` | les locataires auxquels l'appelant peut se connecter |
| | `POST /api/v1/heartbeat` | renouveler le bail de l'appareil |
| | `POST /api/v1/deregister` | retirer le pair |
| | `GET /healthz` | vivacité |
| | `GET /metrics` | métriques Prometheus |
| | `/admin/` | API d'administration et WebUI, lorsque `ADMIN_TOKEN` est défini |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | diffuse les routes du locataire et leurs mises à jour |

Les requêtes de l'API portent `Authorization: Bearer <token>` : un jeton d'accès GitHub,
un jeton d'identité (ID token) OIDC, ou un jeton d'accès go-authn, selon `AUTH_PROVIDER`.
Voir le [protocole d'enrôlement]({{< relref "/reference/protocol.md" >}}) pour
le contenu des messages.

Avec `TLS_CERT` et `TLS_KEY`, les deux écoutes utilisent TLS. Sans eux, l'API HTTP
est en clair (terminez TLS sur un proxy), tout comme le RouteService, que les
clients refusent alors sauf en boucle locale : les appareils se connectent, mais ne reçoivent pas de mises à jour
de routes en direct.

## Configuration

Toute la configuration se fait par l'environnement.

| Variable | Requise | Défaut | Remarques |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | fournisseur d'identité : `github`, `oidc` ou `go-authn` |
| `GITHUB_ALLOWED_ORGS` | | — | liste CSV des organisations autorisées (`github`) : un membre actif de l'une d'elles est admis |
| `GITHUB_API_URL` | | `https://api.github.com` | à définir pour GitHub Enterprise |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | URL de l'émetteur (découverte) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | l'audience que les jetons doivent porter |
| `OIDC_ALLOWED_DOMAINS` | | — | liste CSV des domaines de messagerie autorisés (`oidc`) |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | le client propre de la passerelle chez le fournisseur (`wireguard_peers`) |
| `GOAUTHN_GATEWAY_SECRET_FILE` | `go-authn` | — | son secret, **uniquement depuis un fichier** |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | fréquence de récupération de la liste des clés enregistrées |
| `GOAUTHN_SSF` | | `false` | interroger aussi le flux Shared Signals du fournisseur, afin qu'une désactivation soit prise en compte immédiatement ; le client de la passerelle doit y être un récepteur SSF |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | fréquence d'interrogation du flux SSF |
| `WG_ENDPOINT` | ✅ | — | `host:port` public de la passerelle, annoncé aux clients |
| `WG_PRIVATE_KEY` / `WG_PRIVATE_KEY_FILE` | ✅ | — | la clé privée base64 de la passerelle (la variable l'emporte sur le fichier) |
| `WG_INTERFACE` | | `wg0` | interface à gérer |
| `WG_DRYRUN` | | `false` | journaliser les opérations sur les pairs au lieu de les appliquer (développement local) |
| `VPN_CIDR` | | `10.80.0.0/24` | plage d'adresses IPv4 ; son premier hôte est celui de la passerelle |
| `PUSH_ROUTES` | | `VPN_CIDR` | routes CSV du locataire `default` |
| `DNS` | | — | serveurs DNS CSV du locataire `default` |
| `KEEPALIVE` | | `25` | keepalive persistant annoncé aux clients (secondes) |
| `LEASE_TTL` | | `24h` | durée d'un enrôlement sans heartbeat |
| `LISTEN_ADDR` | | `:8443` | adresse d'écoute HTTP |
| `GRPC_ADDR` | | `:8444` | adresse d'écoute du RouteService |
| `GRPC_ENDPOINT` | | — | `host:port` du RouteService annoncé aux clients ; vide, ils ne surveillent rien |
| `ADMIN_TOKEN` | | — | jeton porteur pour l'API d'administration et la WebUI ; vide, elles sont désactivées |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS, et TLS sur le RouteService |
| `DEBUG` | | — | n'importe quelle valeur : journalisation de débogage (une ligne par requête) |

## Fournisseurs d'authentification {#authentication-providers}

L'authentification est modulaire, derrière l'interface `Verifier`
(`internal/auth`) :

- **`github`** (par défaut) : le jeton porteur est un jeton d'accès OAuth GitHub issu du
  flux d'appareil (device flow). Le serveur le résout via l'API GitHub (`/user`,
  `/user/orgs`) et, avec `GITHUB_ALLOWED_ORGS`, exige l'appartenance active
  à l'une de ces organisations. Aucun secret client n'intervient.
- **`oidc`** : le jeton porteur est un jeton d'identité OIDC, vérifié auprès de l'émetteur avec
  l'audience `OIDC_CLIENT_ID` et la liste facultative des domaines de messagerie autorisés.
- **`go-authn`** : le jeton porteur est un jeton d'accès (`at+jwt`) émis par un
  fournisseur [go-authn/bridge](https://github.com/go-authn/bridge), et la
  clé de l'appareil doit y avoir été enregistrée par la même personne. Le serveur lit
  la liste signée des clés enregistrées du fournisseur
  ([go-authn/wireguard](https://github.com/go-authn/wireguard)) et retire de
  `wg0` une clé que le fournisseur reprend.

Voir [Fournisseurs d'identité]({{< relref "/identity-providers.md" >}}) pour chaque
flux de bout en bout.

## Règles d'enrôlement {#enrollment-rules}

- **Une clé appartient à celui qui l'a enrôlée.** Enrôler une clé que détient une autre
  identité est refusé (`409 key_taken`) : une clé publique est publique, et s'en
  emparer donnerait le pouvoir de désinscrire l'appareil de son propriétaire.
- La même clé enrôlée de nouveau par son propriétaire conserve son adresse et obtient un nouveau
  bail.
- La seule IP autorisée du pair est le `/32` de l'appareil, de sorte que les appareils ne peuvent pas utiliser
  les adresses les uns des autres.
- Le locataire est celui que l'appelant a demandé, s'il en est membre, ou son
  unique locataire. Voir [Locataires]({{< relref "/tenants.md" >}}).

## Comment il programme la passerelle {#how-it-programs-the-gateway}

Le serveur utilise [`wgctrl`](https://pkg.go.dev/golang.zx2c4.com/wireguard/wgctrl)
pour ajouter et retirer des pairs sur une interface existante, et vérifie au démarrage que
l'interface existe. L'interface elle-même (sa clé privée et son port d'écoute)
est laissée à `wg-quick` ou à systemd-networkd au démarrage, ce qui tient la configuration privilégiée
de l'interface hors du service de longue durée.

## Exécuter en local {#run-locally}

Avec `WG_DRYRUN=true`, aucun périphérique WireGuard n'est touché :

```sh
export AUTH_PROVIDER=oidc
export OIDC_ISSUER=https://accounts.google.com
export OIDC_CLIENT_ID=xxxx.apps.googleusercontent.com
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY=$(wg genkey)
export WG_DRYRUN=true LISTEN_ADDR=:8080

go run ./cmd/claimward-server
```

`task run:dev` fait de même avec la connexion GitHub et une clé éphémère, et
`task dex` lance un [Dex](https://dexidp.io/) local auprès duquel se connecter
(`deploy/dev/`).

{{< callout type="warning" >}}
**Exécutez derrière TLS.** Les jetons porteurs sont des identifiants : servez toujours l'API en
HTTPS, soit avec `TLS_CERT`/`TLS_KEY`, soit derrière un proxy qui termine TLS, et
donnez un certificat au RouteService afin que les appareils reçoivent les mises à jour de routes en direct.
{{< /callout >}}
