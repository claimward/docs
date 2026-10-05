---
title: "Exploitation"
weight: 70
description: "Exploiter Claimward en production : TLS, la passerelle, les baux, ce qu'un redémarrage oublie, le fournisseur d'identité, l'API d'administration et les métriques."
tags: [serveur, exploitation, wireguard, grpc]
---

## TLS

Le serveur parle HTTP en clair sauf si `TLS_CERT`/`TLS_KEY` sont définis. Les jetons porteurs
sont des identifiants, placez donc **toujours** l'API derrière TLS, directement ou via un
proxy inverse (nginx, Caddy, un répartiteur de charge).

Le même certificat sert le RouteService gRPC. Une surveillance des routes transporte le
jeton porteur, et les clients refusent une surveillance en clair sauf en bouclage : un
serveur sans `TLS_CERT`/`TLS_KEY` (par exemple derrière un proxy qui ne fait que
terminer HTTPS) enrôle les appareils, mais ceux-ci ne reçoivent aucune mise à jour de routes en direct, et il
journalise un avertissement au démarrage. Définissez `GRPC_ENDPOINT` sur le `host:port` par lequel les appareils
atteignent le RouteService, avec un nom que couvre le certificat.

## Passerelle {#gateway}

- Montez `wg0` avec `wg-quick` ou systemd-networkd au démarrage ; Claimward ne fait que
  gérer ses pairs. Exécutez le serveur avec les droits de configurer l'interface
  (root, ou `CAP_NET_ADMIN`).
- Activez `net.ipv4.ip_forward`, ainsi que des règles NAT ou de pare-feu, si les clients routent
  au-delà du sous-réseau VPN.
- `GET /healthz` est la sonde de vivacité.

## Baux {#leases}

`LEASE_TTL` (24 heures par défaut) arbitre entre sécurité et renouvellement. Le processus de nettoyage
supprime les pairs expirés chaque minute, si bien que les appareils révoqués ou hors ligne disparaissent
d'eux-mêmes. Pour en révoquer un immédiatement, désinscrivez son pair, ou supprimez-le avec
`wg set wg0 peer <key> remove`.

À partir de claimward-vpn-client v0.3.1 (les applications à partir de v0.2.0), le helper renouvelle
le bail tant que le tunnel est monté, à la moitié de ce qu'il reste (entre 30 secondes
et 10 minutes), et se désinscrit sur *Disconnect*. Un `LEASE_TTL` plus court
coûte donc davantage de heartbeats, pas des tunnels coupés : un retrait d'un locataire, ou une clé
que le fournisseur go-authn reprend, met fin au tunnel au renouvellement suivant (le
serveur répond `403`). Un serveur qui a oublié un appareil (`404`) le fait
enrôler de nouveau. Voir [Baux]({{< relref "/architecture.md#leases" >}}).

Les applications v0.1.0 ne renouvellent qu'en se reconnectant, et laissent le pair jusqu'à la fin de son
bail après *Disconnect* : avec elles, un appareil qui reste connecté plus longtemps
que `LEASE_TTL` perd son tunnel quand son pair est nettoyé.

## État {#state}

Le serveur conserve les pairs enrôlés, le pool d'adresses et les locataires
**en mémoire**. Un redémarrage les oublie :

- les locataires reviennent à `default` seul, à partir de `PUSH_ROUTES` et `DNS` ;
- à partir du serveur **v0.2.0**, les pairs qu'une exécution précédente a laissés sur `wg0` sont
  **supprimés au démarrage** : tout pair dont la seule IP autorisée est un `/32` dans
  `VPN_CIDR`, la forme que le serveur donne à chaque pair. Tout autre pair
  (configuré à la main, un lien site à site) est laissé tel quel. Conservés, ces pairs
  n'appartiendraient à personne : jamais nettoyés, jamais confrontés à la liste du fournisseur,
  si bien qu'une personne désactivée avant le redémarrage garderait un tunnel fonctionnel. Les appareils
  se découvrent inconnus à leur prochain renouvellement de bail et s'enrôlent de nouveau (applications
  reposant sur claimward-vpn-client v0.3.1) ; d'ici là, leur tunnel ne transporte
  rien. Le helper renouvelle au plus toutes les 10 minutes, donc après un redémarrage un
  appareil peut être coupé jusqu'à 10 minutes. Se reconnecter le rétablit
  immédiatement.
- le serveur **v0.1.0** laisse ces pairs sur `wg0` : il ne les nettoie jamais, et
  il peut attribuer leurs adresses à de nouveaux appareils (WireGuard route alors
  l'adresse vers le nouveau pair). Après l'avoir redémarré, purgez les pairs
  (`wg-quick down wg0 && wg-quick up wg0`, ou `wg set … remove`) et faites
  se reconnecter les appareils.

Pour plusieurs passerelles ou une piste d'audit durable, les paquets `store`, `ipam` et
`tenant` ont besoin d'une base de données derrière eux.

## Fournisseur d'identité {#identity-provider}

Par défaut, Claimward connecte les personnes avec **GitHub** (device flow) : créez une
GitHub OAuth App avec **Device Flow** activé et restreignez l'accès avec
`GITHUB_ALLOWED_ORGS`. Pour **OIDC**, définissez `AUTH_PROVIDER=oidc` avec un
client PKCE natif/public, et restreignez avec `OIDC_ALLOWED_DOMAINS`. Pour
**go-authn**, définissez `AUTH_PROVIDER=go-authn` avec le client propre à la passerelle : le
fournisseur décide alors quelles clés peuvent se connecter, et une passerelle qui ne peut pas récupérer
sa liste n'admet aucun nouvel appareil. Voir
[Fournisseurs d'identité]({{< relref "/identity-providers.md" >}}).

## API d'administration et WebUI {#admin-api-and-webui}

Lorsque `ADMIN_TOKEN` est défini, le serveur sert une WebUI Svelte embarquée sur
`/admin/` et une API sous `/admin/api/`, protégées par
`Authorization: Bearer <ADMIN_TOKEN>` (comparé en temps constant). Sans lui,
`/admin/` répond `503`. Les fichiers de la WebUI sont servis sans authentification ;
elle demande le jeton et l'envoie avec chaque appel.

| Méthode et chemin | |
|---|---|
| `GET /admin/api/overview` | comptes `{"tenants", "peers", "watchers"}` |
| `GET /admin/api/tenants` | tous les locataires |
| `POST /admin/api/tenants` | en crée un : `id` (ou un slug de `name`), `name`, `domains`, `groups`, `idps`, `allowed_ips`, `dns` |
| `GET /admin/api/tenants/{id}` | un locataire |
| `PUT /admin/api/tenants/{id}` | remplace son nom, ses listes d'appartenance et ses routes ; incrémente `serial` et pousse les routes vers ses observateurs |
| `DELETE /admin/api/tenants/{id}` | le supprime (sauf `default`) ; met fin à ses surveillances |

Ne servez `/admin/` que là où les administrateurs y accèdent : le jeton est un secret
partagé statique.

## Métriques {#metrics}

`GET /metrics` sert des métriques Prometheus, sans authentification :

| Métrique | |
|---|---|
| `claimward_enrollments_total{tenant}` | enrôlements réussis |
| `claimward_active_peers` | pairs enrôlés |
| `claimward_tenants` | locataires configurés |
| `claimward_route_watchers` | surveillances RouteService actives |
| `claimward_tenant_route_serial{tenant}` | numéro de série des routes de chaque locataire |
