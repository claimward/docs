---
title: "Serveur"
linkTitle: "Serveur"
weight: 1
description: "claimward-vpn-server : vérifie la connexion, attribue les adresses VPN, programme la passerelle WireGuard, diffuse les routes des locataires via gRPC, et sert une API d'administration et des métriques."
tags: [serveur, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.10.0** est le plan de contrôle. Il vérifie le jeton porteur (bearer) que présente un appareil,
attribue les adresses VPN, et programme la passerelle WireGuard avec un pair par
appareil enrôlé. Il s'exécute sur l'hôte de passerelle, à côté d'un `wg0` existant : Linux
(nftables) ou, depuis la v0.10.0, OpenBSD (pf, voir [OpenBSD](#openbsd)).

## Ce qu'il sert {#what-it-serves}

| Écoute | Chemin | Rôle |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | vérifier, choisir le locataire, attribuer une adresse, ajouter le pair, renvoyer la configuration du tunnel |
| | `GET /api/v1/tenants` | les locataires auxquels l'appelant peut se connecter |
| | `POST /api/v1/heartbeat` | renouveler le bail de l'appareil |
| | `POST /api/v1/deregister` | retirer le pair |
| | `GET /healthz` | vivacité |
| | `/admin/` | API d'administration et WebUI, lorsque l'identifiant `admin-token` existe |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | diffuse les routes du locataire et leurs mises à jour |
| `METRICS_ADDR` (pas de défaut : désactivé si non défini) | `GET /metrics` | métriques Prometheus, sur une écoute à part, jamais sur `LISTEN_ADDR` |

Les requêtes de l'API portent `Authorization: Bearer <token>` : un jeton d'accès GitHub,
un jeton d'identité (ID token) OIDC, ou un jeton d'accès go-authn, selon `AUTH_PROVIDER`.
Voir le [protocole d'enrôlement]({{< relref "/reference/protocol.md" >}}) pour
le contenu des messages.

Avec `TLS_CERT` et `TLS_KEY`, les deux écoutes utilisent TLS. Sans eux, l'API HTTP
est en clair (terminez TLS sur un proxy), tout comme le RouteService, que les
clients refusent alors sauf en boucle locale : les appareils se connectent, mais ne reçoivent pas de mises à jour
de routes en direct.

## Configuration

Les réglages sont dans l'environnement. **Les secrets non** : depuis v0.6.0 ce
sont des fichiers d'un répertoire d'identifiants, voir [Identifiants](#credentials) plus bas.

| Variable | Requise | Défaut | Remarques |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | fournisseur d'identité : `github`, `oidc` ou `go-authn` |
| `GITHUB_ALLOWED_ORGS` | `github` | — | liste CSV des organisations autorisées : un membre actif de l'une d'elles est admis, de même qu'un membre nommé d'un locataire. Depuis v0.5.0 elle n'est **facultative que si au moins un locataire a des `members`** : sans l'un ni l'autre le serveur refuse de démarrer, sans option de contournement (avant : obligatoire depuis v0.4.0) |
| `GITHUB_API_URL` | | `https://api.github.com` | à définir pour GitHub Enterprise |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | URL de l'émetteur (découverte) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | l'audience que les jetons doivent porter |
| `OIDC_ALLOWED_DOMAINS` | | — | liste CSV des domaines de messagerie autorisés (`oidc`) ; l'e-mail du jeton doit être vérifié |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | le client propre de la passerelle chez le fournisseur (`wireguard_peers`) |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | fréquence de récupération de la liste des clés enregistrées |
| `GOAUTHN_SSF` | | `false` | interroger aussi le flux Shared Signals du fournisseur, afin qu'une désactivation soit prise en compte immédiatement ; le client de la passerelle doit y être un récepteur SSF |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | fréquence d'interrogation du flux SSF |
| `WG_ENDPOINT` | ✅ | — | `host:port` public de la passerelle, annoncé aux clients |
| `CREDENTIALS_DIRECTORY` | ✅ | — | le répertoire qui contient les fichiers secrets, voir [Identifiants](#credentials) |
| `WG_INTERFACE` | | `wg0` | interface à gérer |
| `WG_DRYRUN` | | `false` | journaliser les opérations sur les pairs au lieu de les appliquer (développement local) |
| `VPN_CIDR` | | `10.80.0.0/24` | plage d'adresses IPv4 ; son premier hôte est celui de la passerelle |
| `PUSH_ROUTES` | | `VPN_CIDR` | routes CSV du locataire `default` |
| `TENANTS_FILE` | | — | fichier JSON de locataires chargé au démarrage, avec leur [politique d'accès]({{< relref "/tenants.md#access-policy" >}}) |
| `DNS` | | — | serveurs DNS CSV du locataire `default` |
| `KEEPALIVE` | | `25` | keepalive persistant annoncé aux clients (secondes) |
| `LEASE_TTL` | | `24h` | durée d'un enrôlement sans heartbeat |
| `TUNNEL_MTU` | | déduit | MTU de l'interface WireGuard, de 1280 à 9000, annoncé comme `mtu` ; toute autre valeur refuse le démarrage. Non défini : MTU de la liaison montante moins 80, au plus 1420, au moins 1280. La même table atomique `inet claimward` abaisse aussi le MSS de chaque SYN TCP traversant l'interface (transit dans les deux sens, et entrée pour la passerelle elle-même) à ce MTU moins 40 (IPv4) ou 60 (IPv6) |
| `LISTEN_ADDR` | | `:8443` | adresse d'écoute HTTP |
| `GRPC_ADDR` | | `:8444` | adresse d'écoute du RouteService ; les flux `Watch` sont ré-autorisés toutes les 15 s et se terminent quand l'identité n'est plus admise |
| `METRICS_ADDR` | | — (désactivé) | écouteur séparé pour `/metrics`, servi **seulement si défini** (depuis la v0.9.0 il n'y a plus de port par défaut : l'ancien `127.0.0.1:9090` entrait en conflit avec Prometheus) ; jamais sur `LISTEN_ADDR`. Il nomme chaque tenant : gardez-le en boucle locale ou sur un réseau privé |
| `MAX_DEVICES_PER_SUBJECT` | | `5` | appareils qu'une identité peut enrôler |
| `GRPC_ENDPOINT` | | — | `host:port` du RouteService annoncé aux clients ; vide, ils ne surveillent rien |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS, et TLS sur le RouteService |
| `DEBUG` | | — | n'importe quelle valeur : journalisation de débogage (une ligne par requête) |

## Identifiants {#credentials}

Chaque secret est un **fichier** du répertoire désigné par
`CREDENTIALS_DIRECTORY`, jamais une variable d'environnement : l'environnement
est copié dans chaque processus fils et chaque image mémoire. systemd définit la
variable pour `LoadCredential=` et `LoadCredentialEncrypted=` ; sur les autres
plateformes, vous la définissez vous-même. Les noms de fichiers sont fixes, et
un saut de ligne final est retiré.

| Fichier | Requis | Contenu |
|------|----------|---------|
| `wg-private-key` | toujours | la clé privée base64 de la passerelle |
| `admin-token` | non | jeton porteur de l'API d'administration et de la WebUI ; **sans le fichier, elles sont désactivées** |
| `goauthn-gateway-secret` | `AUTH_PROVIDER=go-authn` | le secret du client de la passerelle |
| `github-token` | quand un locataire a des `members` | jeton porteur pour `GET /users/{login}` (voir [Locataires]({{< relref "/tenants.md" >}})) |

Un fichier requis absent empêche le démarrage et est nommé. Avant de lire, le
serveur contrôle chaque fichier par son descripteur ouvert (`O_NOFOLLOW`, puis
`fstat`) et **refuse** un lien symbolique, tout ce qui n'est pas un fichier
ordinaire, un fichier lisible par le groupe ou les autres, un fichier qui
n'appartient pas à l'uid du serveur, un fichier vide et un fichier de plus de
64 Kio. Une exception depuis la v0.7.1 : un fichier appartenant à l'uid 0, de
mode exactement `0440`, est accepté si son groupe est le gid du serveur ou l'un
de ses groupes supplémentaires (ce que produit un volume Secret Kubernetes avec
`fsGroup`). Une seconde depuis la v0.9.0, pour systemd avec `DynamicUser=yes` :
systemd laisse le fichier `root:root`, mode `0400`, plus une entrée d'ACL POSIX
en lecture seule pour l'uid du service (`src/core/exec-credential.c:338-361`,
`src/shared/acl-util.c:448-494`), donc `stat` affiche `0440`. Le serveur lit
`system.posix_acl_access` depuis le descripteur ouvert et accepte exactement
`user::r--`, `user:<son uid>:r--`, `group::---`, `mask::r--`, `other::---` ;
tout autre utilisateur ou groupe nommé, tout bit d'écriture ou d'exécution, ou
une valeur mal formée ou trop grande est refusé. L'erreur donne la correction.

| Plateforme | `CREDENTIALS_DIRECTORY` | Propriétaire et mode |
|----------|-------------------------|----------------|
| systemd | défini par `LoadCredentialEncrypted=` | avec `DynamicUser=yes` (comme livré) : propriété de root avec une ACL en lecture seule pour l'uid du service, acceptée ; avec un `User=` fixe sur un système de fichiers sans ACL : l'utilisateur du service, `0400`. tmpfs privé |
| Docker Swarm | `/run/secrets`, défini à la main | `mode: 0400` sur le secret |
| Docker Compose | `/run/secrets`, défini à la main | ceux du fichier de l'hôte : `chown` et `chmod 0400`, et ajustez `user:` |
| Podman | `/run/secrets`, défini à la main | `--secret ...,mode=0400` (Quadlet : `Secret=...,mode=0400`) |
| Kubernetes | le chemin de montage du volume Secret, défini à la main | `defaultMode: 0440` et `fsGroup` : les fichiers sont `root:<fsGroup>`, acceptés par la règle de groupe ci-dessus, donc le pod tourne avec un uid non root, toutes capacités retirées sauf `NET_ADMIN`. `add: [NET_ADMIN]` seul ne donne pas la capacité à un uid non root (pas d'ensemble ambiant) : le binaire de l'image doit porter `setcap cap_net_admin=+ep` (d'après capabilities(7), non mesuré sur un cluster) |
| autres | n'importe quel répertoire | `chmod 0400`, propriété de l'utilisateur du service |

Des unités prêtes à l'emploi pour systemd, Compose, Podman et Kubernetes se
trouvent dans le répertoire `deploy/` du dépôt, avec les étapes de
`systemd-creds encrypt`. Les hôtes sans systemd pourront obtenir le même
répertoire avec `go-authn/sdcreds` (`sdcreds s6-run`) dès que sa première
version sera étiquetée ; rien n'en dépend pour l'instant.

Le contrôle d'organisation du fournisseur `github` n'utilise pas `github-token` :
il se fait avec le jeton de la *personne*, donc une appartenance privée n'est
visible que si ce jeton porte `read:org`. L'identifiant est facultatif tant que
seules des organisations sont utilisées.

{{< callout type="warning" >}}
**Migration depuis v0.5.0** (rupture). `ADMIN_TOKEN`, `WG_PRIVATE_KEY`,
`WG_PRIVATE_KEY_FILE` et `GOAUTHN_GATEWAY_SECRET_FILE` ne sont plus lues, et le
serveur refuse de démarrer tant que l'une d'elles est définie, en nommant le
fichier à créer. Mettez chaque valeur dans son fichier (`admin-token`,
`wg-private-key`, `goauthn-gateway-secret`), supprimez la variable et définissez
`CREDENTIALS_DIRECTORY`. Un locataire avec `members` exige désormais aussi
`github-token`.
{{< /callout >}}

## Fournisseurs d'authentification {#authentication-providers}

L'authentification est modulaire, derrière l'interface `Verifier`
(`internal/auth`) :

- **`github`** (par défaut) : le jeton porteur est un jeton d'accès OAuth GitHub issu du
  flux d'appareil (device flow). Le serveur le résout via l'API GitHub (`/user`,
  `/user/orgs`) et, avec `GITHUB_ALLOWED_ORGS`, admet un membre actif
  de l'une de ces organisations, ou un membre nommé d'un locataire (la liste
  n'est facultative que si un locataire a des `members`). Aucun secret client n'intervient.
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

## OpenBSD (pf) {#openbsd}

Depuis la v0.10.0, le serveur fonctionne aussi sous OpenBSD, où il applique la
politique d'accès avec pf au lieu de nftables. Il parle directement au noyau par
les ioctls de `/dev/pf` ; il n'exécute jamais `pfctl`, et il n'y a pas de repli
sur `pfctl`.

- **Versions prises en charge : OpenBSD 7.9 et 8.0.** Elles partagent la même
  disposition de `struct pf_rule`, que le serveur vérifie sur la version en
  cours. Sur toute autre version, le serveur refuse de démarrer plutôt que de
  risquer d'encoder une règle de travers.
- **`pf.conf` vous appartient.** Le serveur ne modifie jamais le jeu de règles
  principal. Ajoutez une ligne à `/etc/pf.conf` et gardez `pf` activé :

  ```text
  anchor "claimward"
  ```

  Le serveur charge la politique dans cette ancre. Au démarrage, il relit le jeu
  de règles principal et vérifie qu'il appelle `anchor "claimward"`.
- **Il refuse de démarrer** quand `/dev/pf` ne peut pas être ouvert en
  lecture-écriture (il doit démarrer en root), quand pf est désactivé, quand le
  jeu de règles principal n'appelle pas l'ancre (la politique serait chargée
  sans rien filtrer), et quand `pf.conf` contient `set skip on` pour l'interface
  WireGuard (`wg0`, `wg*`), car pf ne verrait alors jamais le trafic des pairs.
- **Même politique que sous Linux.** Refus par défaut du trafic arrivant sur
  `WG_INTERFACE` ; seul l'IPv4 est autorisé, et l'IPv6 à travers le tunnel est
  rejeté. Le plafonnement du MSS (`TUNNEL_MTU`) couvre les deux familles, sous
  la forme d'une règle `match ... scrub (max-mss N)`.
- **Atomique et fermé par défaut.** L'ancre et ses tables sont remplacées dans
  une seule transaction pf, puis relues et comparées à ce qui devait être
  chargé. En cas d'échec, un refus total est chargé. L'ancre reste en place à la
  sortie du processus. Les noms de tables portent un suffixe de génération par
  chargement, si bien que la courte fenêtre entre la validation des tables et
  celle des règles ne peut jamais appliquer les règles d'un tenant aux pairs d'un
  autre.
- **Pas de `pledge(2)`.** La promesse `pf` n'autorise que douze des ioctls
  `DIOC*` (`sys/kern/kern_pledge.c`, `pledge_ioctl`), alors que le serveur a
  aussi besoin de `DIOCRINADEFINE`, `DIOCXROLLBACK`, `DIOCGETRULES`,
  `DIOCGETRULE`, `DIOCXEND` et `DIOCRGETADDRS`. Tout autre ioctl tuerait le
  processus, et un pledge ne peut pas être élargi ensuite. Lancez-le comme
  service dédié sous `rcctl` et gardez le reste de la machine verrouillé.

## Exécuter en local {#run-locally}

Avec `WG_DRYRUN=true`, aucun périphérique WireGuard n'est touché :

```sh
export AUTH_PROVIDER=oidc
export OIDC_ISSUER=https://accounts.google.com
export OIDC_CLIENT_ID=xxxx.apps.googleusercontent.com
export WG_ENDPOINT=vpn.example.com:51820
export CREDENTIALS_DIRECTORY=$HOME/.local/state/claimward-dev-creds
(umask 077; mkdir -p "$CREDENTIALS_DIRECTORY"; wg genkey > "$CREDENTIALS_DIRECTORY/wg-private-key")
chmod 0400 "$CREDENTIALS_DIRECTORY/wg-private-key"
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
