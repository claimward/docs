---
title: "Serveur"
linkTitle: "Serveur"
weight: 1
description: "claimward-vpn-server : vérifie la connexion, attribue les adresses VPN, programme la passerelle WireGuard, diffuse les routes des locataires via gRPC, et sert une API d'administration et des métriques."
tags: [serveur, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.14.0** est le plan de contrôle. Il vérifie le jeton porteur (bearer) que présente un appareil,
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
| | `GET /.well-known/claimward-configuration` | document de découverte public, sans authentification (depuis v0.13.0), voir [le protocole]({{< relref "/reference/protocol.md#discovery" >}}) |
| | `GET /.well-known/claimward-logo.svg` | le logo du serveur, sans authentification, seulement lorsque `SERVER_LOGO_FILE` est défini (depuis v0.14.0), voir [le protocole]({{< relref "/reference/protocol.md#logo" >}}) |
| | `/admin/` | API d'administration et WebUI, lorsque l'identifiant `admin-token` existe |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | diffuse les routes du locataire et leurs mises à jour |
| `METRICS_ADDR` (pas de défaut : désactivé si non défini) | `GET /metrics` | métriques Prometheus, sur une écoute à part, jamais sur `LISTEN_ADDR` |

Les requêtes de l'API portent `Authorization: Bearer <token>` : un jeton d'accès GitHub,
un jeton d'identité (ID token) OIDC, ou un jeton d'accès go-authn, selon le fournisseur qu'elles
nomment dans l'en-tête `Claimward-Provider` (depuis v0.14.0, voir
[Fournisseurs d'identité](#providers)). Voir le [protocole d'enrôlement]({{< relref "/reference/protocol.md" >}}) pour
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
| `PROVIDERS_FILE` | ✅ | — | fichier JSON listant les fournisseurs d'identité (depuis v0.14.0, **rupture**), voir [Fournisseurs d'identité](#providers). Il remplace `AUTH_PROVIDER`, `OIDC_ISSUER`, `OIDC_CLIENT_ID`, `OIDC_ALLOWED_DOMAINS`, `GITHUB_CLIENT_ID`, `GITHUB_ALLOWED_ORGS` et `GOAUTHN_GATEWAY_CLIENT_ID` : le serveur refuse de démarrer tant que l'une d'elles est définie |
| `GITHUB_API_URL` | | `https://api.github.com` | l'API auprès de laquelle sont résolus les membres nommés des locataires ; à définir pour GitHub Enterprise. Chaque fournisseur `github` a son propre `api_url` dans le fichier des fournisseurs |
| `SERVER_LOGO_FILE` | | — | un logo SVG publié dans le document de découverte et à `/.well-known/claimward-logo.svg` (depuis v0.14.0) ; 64 Kio au plus, validé au démarrage (sans script, sans référence externe) : un fichier invalide refuse le démarrage |
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
| `SERVER_NAME` | | — | nom d'affichage publié dans le document de découverte (depuis v0.13.0) ; 100 caractères au plus, sans caractère de contrôle ; non défini, aucun nom n'est publié |
| `SERVER_EXCLUSIVE` | | `false` | publié dans le document de découverte (depuis v0.13.0) : ce serveur refuse de partager la machine avec d'autres tunnels Claimward ; les clients refusent de le connecter avec d'autres, et refusent les autres tant qu'il est connecté. `true` ou `false`, toute autre valeur refuse le démarrage |
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
| `provider-<id>-gateway-secret` | un fournisseur `go-authn` | le secret du client de la passerelle (était `goauthn-gateway-secret`, avant v0.14.0) |
| `provider-<id>-secret` | chaque fournisseur `github` | le secret client de l'application OAuth GitHub de ce fournisseur (voir `github_client_id` ; était `github-client-secret`, avant v0.14.0) |
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
`user::` (sans écriture ni exécution), `user:<son uid>:r--`, `group::---`, `mask::r--`, `other::---` ;
tout autre utilisateur ou groupe nommé, tout bit d'écriture ou d'exécution, ou
une valeur mal formée ou trop grande est refusé. L'erreur donne la correction.

| Plateforme | `CREDENTIALS_DIRECTORY` | Propriétaire et mode |
|----------|-------------------------|----------------|
| systemd | défini par `LoadCredentialEncrypted=` | avec `DynamicUser=yes` (comme livré) : propriété de root avec une ACL en lecture seule pour l'uid du service, acceptée ; avec un `User=` fixe sur un système de fichiers sans ACL : l'utilisateur du service, `0400`. tmpfs privé |
| Docker Swarm | `/run/secrets`, défini à la main | `mode: 0400` sur le secret |
| Docker Compose | `/run/secrets`, défini à la main | ceux du fichier de l'hôte : `chown` et `chmod 0400`, et ajustez `user:` |
| Podman | `/run/secrets`, défini à la main | `--secret ...,mode=0400` (Quadlet : `Secret=...,mode=0400`) |
| Kubernetes | le chemin de montage du volume Secret, défini à la main | `defaultMode: 0440` et `fsGroup` : les fichiers sont `root:<fsGroup>`, acceptés par la règle de groupe ci-dessus, donc le pod tourne avec un uid non root, toutes capacités retirées sauf `NET_ADMIN`. `add: [NET_ADMIN]` seul ne donne pas la capacité à un uid non root (pas d'ensemble ambiant) : le binaire de l'image doit porter `setcap cap_net_admin=+ep` (d'après capabilities(7), non mesuré sur un cluster) |
| s6 (sans systemd) | `/run/sdcreds/claimward-server`, défini par `sdcreds s6-run` | l'utilisateur du service, `0400`, dans un tmpfs privé (voir [s6](#s6-deploy)) |
| autres | n'importe quel répertoire | `chmod 0400`, propriété de l'utilisateur du service |

Des unités prêtes à l'emploi pour systemd, Compose, Podman, Kubernetes et s6 se
trouvent dans le répertoire `deploy/` du dépôt, avec les étapes de
`systemd-creds encrypt`. Les hôtes sans systemd obtiennent le même répertoire
avec `go-authn/sdcreds` (voir [s6](#s6-deploy)) ; le serveur n'en dépend pas.

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

## Fournisseurs d'identité {#providers}

Depuis v0.14.0 le serveur accepte **plusieurs** fournisseurs d'identité à la fois. Ils
sont listés dans le fichier JSON désigné par `PROVIDERS_FILE` (les champs inconnus
sont refusés, 1 Mio au plus) :

```json
{"providers":[
  {"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward"},
  {"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org"]}
]}
```

| `kind` | Champs en plus de `id`, `kind`, `name` | Fichier secret |
|--------|-------------------------------------|-------------|
| `github` | `github_client_id`, `api_url` (GitHub Enterprise), `allowed_orgs` | `provider-<id>-secret` |
| `oidc` | `oidc_issuer`, `oidc_client_id`, `allowed_domains` | aucun |
| `go-authn` | `oidc_issuer`, `oidc_client_id`, `gateway_client_id` | `provider-<id>-gateway-secret` |

- **`github`** : le jeton porteur est un jeton d'accès OAuth GitHub issu du flux d'appareil
  (device flow). Le serveur interroge GitHub ([Check a token](https://docs.github.com/en/rest/apps/oauth-applications#check-a-token))
  avec le secret du fournisseur avant de l'accepter, de sorte que seuls les jetons
  **de cette application OAuth** sont admis, puis le résout via l'API GitHub (`/user`,
  `/user/orgs`) et admet un membre actif de l'une des `allowed_orgs`, ou un membre
  nommé d'un locataire (la liste n'est facultative que si un locataire a des
  `members`). Sans identifiant client, sans fichier secret, ou sans liste ni
  membres nommés : le serveur refuse de démarrer, sans option de contournement.
- **`oidc`** : le jeton porteur est un jeton d'identité OIDC, vérifié auprès de l'émetteur avec
  l'audience `oidc_client_id` et la liste facultative `allowed_domains` (l'e-mail
  du jeton doit être vérifié).
- **`go-authn`** : le jeton porteur est un jeton d'accès (`at+jwt`) émis par un
  fournisseur [go-authn/bridge](https://github.com/go-authn/bridge), et la
  clé de l'appareil doit y avoir été enregistrée par la même personne. Le serveur lit
  la liste signée des clés enregistrées du fournisseur
  ([go-authn/wireguard](https://github.com/go-authn/wireguard)) et retire de
  `wg0` une clé que le fournisseur reprend. Au plus un fournisseur est de ce type.

**La requête nomme son fournisseur.** Chaque appel de l'API porte l'en-tête
`Claimward-Provider: <id>` (gRPC : la métadonnée `claimward-provider`), et son
jeton est jugé par ce fournisseur **seul** : un jeton du fournisseur A est refusé
quand la requête nomme B. Sans en-tête, c'est `401 missing_provider` ; un id que le serveur
ne liste pas donne `401 unknown_provider`. Le document de découverte liste les
fournisseurs (jamais un secret), de sorte qu'un client n'a besoin que de l'URL du serveur.

**Une identité par émetteur et `sub`.** L'identité est `issuer#sub` pour `oidc`
et `go-authn`, et `github:<id>` pour `github` : le même `sub` chez deux émetteurs
est deux personnes, et la seconde ne peut pas prendre l'appareil de la première.

**Locataires.** Un locataire gagne un champ `providers`, et ses groupes s'écrivent
`<id du fournisseur>:<groupe>`. Avec plusieurs fournisseurs, un locataire qui utilise `domains` ou
`idps` doit nommer `providers`, sans quoi le serveur échoue en mode fermé.

{{< callout type="warning" >}}
**Passage à v0.14.0** (rupture). `AUTH_PROVIDER`, `OIDC_ISSUER`,
`OIDC_CLIENT_ID`, `OIDC_ALLOWED_DOMAINS`, `GITHUB_CLIENT_ID`,
`GITHUB_ALLOWED_ORGS` et `GOAUTHN_GATEWAY_CLIENT_ID` ne sont plus lues, et
le serveur refuse de démarrer tant que l'une d'elles est définie, en nommant le fichier qui la remplace.
Écrivez le fichier des fournisseurs, renommez `github-client-secret` en
`provider-<id>-secret` et `goauthn-gateway-secret` en
`provider-<id>-gateway-secret`, écrivez les groupes des locataires sous la forme `<id du fournisseur>:<groupe>`,
et attendez-vous à un nouveau sujet pour chaque personne (`issuer#sub`, `github:<id>`), donc
les appareils s'enrôlent de nouveau. Utilisez le client v0.9.0 ou plus récent : les clients plus anciens n'envoient pas
l'en-tête.
{{< /callout >}}

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
- **Séparation des privilèges (depuis la v0.11.0).** La promesse `pf` de
  `pledge(2)` n'autorise que douze des ioctls `DIOC*`
  (`sys/kern/kern_pledge.c`, `pledge_ioctl`), alors que le serveur a aussi
  besoin de `DIOCRINADEFINE`, `DIOCXROLLBACK`, `DIOCGETRULES`, `DIOCGETRULE`,
  `DIOCXEND` et `DIOCRGETADDRS` ; tout autre ioctl tuerait le processus. Le
  parent root, qui pilote `/dev/pf`, n'a donc pas de pledge. L'enfant
  `_claimward`, sans privilège, qui détient les secrets et sert le réseau, est
  restreint par `unveil(2)` et `pledge(2)` avant de servir (voir plus bas).
- **Pairs WireGuard (depuis la v0.11.0).** Avant la v0.11.0, une inscription
  sous OpenBSD échouait à l'ajout du pair à `wg(4)` (ticket n° 79). Le serveur
  écrit désormais les pairs avec les ioctls `SIOCSWG` et `SIOCGWG` de
  `sys/net/if_wg.h` et les relit avec son propre décodeur. Vérifié dans de
  vraies machines virtuelles OpenBSD 7.9 et 8.0 amd64 : la disposition des
  structures est celle du compilateur C, et l'ajout, le remplacement, la
  suppression et le balayage fonctionnent sur une vraie interface `wg(4)`.
  OpenBSD arm64 est seulement compilé en croisé, pas exécuté sur un noyau.

### Déployer sous OpenBSD (rc.d) {#openbsd-deploy}

Depuis la v0.10.1, le dépôt fournit `deploy/openbsd/` : un script `rc.d(8)`, un
`environment.example`, un `hostname.wg0.example` et un `pf.conf.example`.

- **Deux processus (depuis la v0.11.0).** La configuration des pairs WireGuard
  de `wg(4)` est derrière `suser(9)` (`sys/net/if_wg.c`), et `/dev/pf` n'est
  protégé que par son nœud de périphérique, réservé à root : `pfopen`
  (`sys/net/pf_ioctl.c`) ne vérifie rien d'autre. OpenBSD n'a pas de groupe
  privilégié qui permettrait à un utilisateur sans privilège de faire l'un ou
  l'autre ; le script lance donc le démon en root (`daemon_user="root"`) et le
  démon se scinde en deux. Le **parent** (root) ajoute et retire les pairs,
  règle le MTU du tunnel et charge l'ancre pf ; il ne lit aucun secret, ne sert
  aucun réseau et ne fait `unveil(2)` que de `/dev/pf`. L'**enfant**, exécuté
  sous l'utilisateur `_claimward`, détient les secrets, les écouteurs TLS et
  gRPC, le fournisseur d'identité et la politique des tenants, et est restreint
  par `unveil(2)` et `pledge(2)` (`stdio rpath inet dns`) avant de servir. S'il
  ne peut pas abandonner ses privilèges, le serveur ne démarre pas. L'enfant
  s'adresse au parent par une socketpair, et le parent refuse tout ce qui sort
  du pool d'adresses (`VPN_CIDR`).
- **L'utilisateur `_claimward` doit exister** et les ports doivent être
  supérieurs à 1024 (les valeurs par défaut 8443 et 8444 le sont) ; pour servir
  sur 443, redirigez-le avec un `rdr-to` pf.
- **Les secrets sont des fichiers** dans `/etc/claimward/credentials`, un
  répertoire `0700` appartenant à `_claimward`, chaque fichier étant `0400` et
  appartenant à `_claimward` (`install(1)`). Le script y fixe
  `CREDENTIALS_DIRECTORY` ; aucun secret n'est dans l'environnement, dans les
  arguments ou dans une URL. Les réglages non secrets sont dans
  `/etc/claimward/environment`, qui reste à root.
- **`wg0` doit exister** avant le démarrage du serveur : `hostname.wg0` porte la
  même clé privée que le secret `wg-private-key` (mode `0640`).

```sh
install -m 0555 claimward-server /usr/local/bin/claimward-server
useradd -g =uid -c claimward -d /var/empty -s /sbin/nologin -r 1..999 _claimward
install -d -m 0755 -o root -g wheel /etc/claimward
install -d -m 0700 -o _claimward -g _claimward /etc/claimward/credentials
install -m 0400 -o _claimward -g _claimward wg-private-key /etc/claimward/credentials/wg-private-key
install -m 0600 -o root -g wheel environment.example /etc/claimward/environment   # puis éditer
install -m 0640 -o root -g wheel hostname.wg0.example /etc/hostname.wg0           # puis éditer
sh /etc/netstart wg0
install -m 0555 claimward_server /etc/rc.d/claimward_server
rcctl enable claimward_server
rcctl start claimward_server && rcctl check claimward_server
```

`rcctl start` ne répond `(ok)` que lorsque le serveur accepte des connexions
sur `LISTEN_ADDR` ; un démon qui se termine avant, par exemple sur un secret que
le compte `_claimward` ne possède pas, donne `(failed)`.

Le journal va dans syslog (`/var/log/daemon`). La CI exécute ce script dans de
vraies machines virtuelles OpenBSD 7.9 et 8.0 : `rcctl start`, la ligne de
démarrage, `rcctl check`, un parent root avec un enfant `_claimward`, une
inscription par l'enfant dont le pair apparaît sur `wg0`, et `rcctl stop` ;
puis un démarrage avec un secret appartenant à root, et un démarrage sans
l'ancre dans `pf.conf`, qui doivent tous deux échouer.

## Déployer sous s6 (sdcreds) {#s6-deploy}

Depuis la v0.10.2, le dépôt fournit `deploy/s6/claimward-server/` (`run` et
`finish`) pour les hôtes sans systemd. `sdcreds s6-run` (go-authn/sdcreds v0.2.0
ou plus récent) déchiffre chaque fichier de son répertoire `--source` dans un
tmpfs privé, écrit chacun en `0400` avec pour propriétaire `--user`, définit
`CREDENTIALS_DIRECTORY` et lance le serveur sous cet utilisateur. Un fichier dont
le propriétaire est l'uid du processus, sans accès pour le groupe ni les autres,
est la première forme que le chargeur accepte : il n'est donc pas modifié. Aucun
secret ne passe par l'environnement, par argv ni par une URL.

- **Une capacité, conservée exprès.** Le serveur a besoin de `CAP_NET_ADMIN`
  (wgctrl, nftables, MTU de l'interface). Par défaut, `s6-run` vide tous les
  ensembles de capacités du service et laisse `no_new_privs` actif ; l'exemple
  passe `--keep-cap=CAP_NET_ADMIN`, si bien que le serveur tourne avec cette
  seule capacité (`CapEff` `0x1000`). Elle agit sur l'espace de noms réseau dans
  lequel l'arbre de supervision s'exécute : celui de l'hôte, sauf si vous lancez
  `s6-svscan` dans un espace de noms à part (`ip netns exec`).
- **Noms.** Chaque fichier de `--source` porte le nom de son secret
  (`wg-private-key`, `github-token`, `admin-token`, `provider-<id>-secret`,
  `provider-<id>-gateway-secret`) et
  est chiffré avec `sdcreds encrypt --name=<ce nom>` ; tout autre nom arrête le
  démarrage. `s6-run` exige root et `CAP_SYS_ADMIN` (il monte un système de
  fichiers).
- **La configuration** non secrète va dans `/etc/claimward/env`, lu par le script
  `run`.
- **Les conteneurs** n'en ont pas besoin : Compose, Podman et Kubernetes montent
  déjà les secrets comme des fichiers (tableau ci-dessus).

La CI exécute ce répertoire sous un vrai `s6-svscan`, dans un espace de noms
réseau, avec une vraie interface WireGuard et nftables (pas un essai à blanc).
Elle vérifie que le journal contient la clé publique dérivée du secret chiffré
(et pas une clé témoin), que le serveur tourne sous l'utilisateur du service
avec `CapEff` `0x1000` et `no_new_privs`, qu'aucun secret n'est dans son
environnement, qu'un fichier de secret en mode `0644` est refusé, et que l'arrêt
du service supprime le montage.

## Exécuter en local {#run-locally}

Avec `WG_DRYRUN=true`, aucun périphérique WireGuard n'est touché :

```sh
cat > providers.json <<'EOF'
{"providers":[{"id":"google","kind":"oidc","name":"Google","oidc_issuer":"https://accounts.google.com","oidc_client_id":"xxxx.apps.googleusercontent.com"}]}
EOF
export PROVIDERS_FILE=$PWD/providers.json
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
