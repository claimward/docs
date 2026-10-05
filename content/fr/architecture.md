---
title: "Architecture"
weight: 20
description: "Un plan de contrôle qui vérifie la connexion et programme la passerelle, un plan de données qui est du WireGuard pur, et un helper privilégié sur chaque appareil entre les deux."
tags: [wireguard, serveur, helper, grpc]
---

Claimward sépare un **plan de contrôle**, le serveur, du **plan de données**,
le tunnel WireGuard entre un appareil et la passerelle. L'authentification est
déléguée à votre fournisseur d'identité : Claimward ne voit jamais de mot de passe.

Sur un appareil, une **application** non privilégiée connecte la personne et conserve la
session ; un **helper privilégié** (root, ou SYSTEM sous Windows) s'enrôle auprès du
serveur et possède le tunnel. L'application ne parle jamais elle-même au serveur.

## Déroulement complet de l'enrôlement {#end-to-end-enrollment-flow}

```text
 ┌──────────┐ 1. sign-in: GitHub device flow, OIDC code + PKCE,  ┌──────────┐
 │   app    │    or go-authn device flow (+ key registration)    │   IdP    │
 │ (as you) │◀─────────────────── bearer token ──────────────────│          │
 └────┬─────┘                                                    └──────────┘
      │ 2. socket: connect {server_url, bearer, private key, tenant}
      ▼
 ┌──────────┐ 3. POST /api/v1/enroll                ┌─────────────────────────┐
 │  helper  │    Authorization: Bearer <token>      │  claimward-vpn-server   │
 │ (root)   │    {public_key, device, tenant}  ───▶ │  verify the bearer      │
 │          │                                       │  choose the tenant      │
 │          │ ◀─── 4. {assigned_ip,                 │  allocate an address    │
 │          │       server_public_key, endpoint,    │  wgctrl: add the peer   │
 │          │       allowed_ips, dns,               │  (AllowedIPs = ip/32)   │
 │          │       grpc_endpoint, keepalive,       └───────────┬─────────────┘
 │          │       lease_expires_at}                           │ RouteService
 │          │ ◀═════════════ 6. gRPC Watch (TLS) ═══════════════╛ (live routes)
 │          │
 │          │ 5. wireguard-go: utunN / Wintun "Claimward", address, routes
 └────┬─────┘
      ╚═══════════════════ WireGuard tunnel ════════════════════▶ private network
```

1. L'application connecte la personne avec le fournisseur configuré : **GitHub** par
   défaut (OAuth device flow), tout émetteur **OpenID Connect** (code
   d'autorisation avec PKCE, dans le navigateur) ou un fournisseur **go-authn** (device flow).
   Le bearer qu'elle obtient est un jeton d'accès GitHub, un jeton d'identité OIDC ou un jeton
   d'accès go-authn. Avec go-authn, la clé **publique** de l'appareil est d'abord
   enregistrée auprès du fournisseur, et le bearer est le jeton que cet enregistrement
   renvoie.
2. L'application génère la paire de clés WireGuard de l'appareil à la première connexion et
   la conserve dans son fichier de session jusqu'à ce que la personne se déconnecte, si bien que l'appareil
   garde sa clé publique d'une connexion à l'autre (et son adresse tant qu'il est enrôlé). Pour se connecter, elle remet au helper l'URL du serveur, le bearer, la
   clé privée et le locataire choisi pour la session, via le socket du helper.
3. Le helper vérifie que le serveur est **l'un de ceux que nomme sa propre configuration**,
   puis appelle `POST /api/v1/enroll` avec la clé publique de l'appareil et le
   bearer.
4. Le serveur **vérifie** le bearer (un appel à l'API GitHub, un jeton d'identité OIDC ou
   un jeton d'accès go-authn dont le sujet doit posséder la clé), applique une éventuelle
   liste d'autorisation d'organisations ou de domaines de messagerie, choisit le **locataire**, **alloue** une
   adresse VPN et **programme la passerelle** (`wgctrl`) avec un pair dont la seule
   IP autorisée est ce `/32`. Il répond avec les paramètres du tunnel : l'adresse,
   sa propre clé publique, le point de terminaison, les routes et serveurs DNS du locataire, le
   keepalive, le point de terminaison du RouteService et la fin du bail.
5. Le helper monte un tunnel en espace utilisateur avec `wireguard-go`, donne à
   l'interface son adresse et installe les routes.
6. Quand le serveur annonce un RouteService (`GRPC_ENDPOINT`), le helper
   le surveille via gRPC : les modifications de routes apportées au locataire atteignent l'appareil
   sans nouvel enrôlement.

## Baux {#leases}

Chaque enrôlement porte un **bail** de `LEASE_TTL` (24 heures par défaut). Un
processus de nettoyage en arrière-plan sur le serveur supprime, chaque minute, les pairs dont le bail
a pris fin, si bien qu'un appareil perdu ou révoqué disparaît de lui-même de la passerelle. Avec
go-authn, un bail ne survit jamais à l'enregistrement de la clé auprès du fournisseur.

Le serveur renouvelle un bail sur `POST /api/v1/heartbeat`, et supprime un pair
immédiatement sur `POST /api/v1/deregister`.

À partir de **claimward-vpn-client v0.3.1**, c'est-à-dire à partir des versions de l'application qui
l'intègrent (les applications macOS, Linux et Windows à partir de v0.2.0), le helper entretient lui-même le bail tant que
le tunnel est monté. Il renouvelle à la moitié de ce qu'il reste au bail, jamais avant
30 secondes ni après 10 minutes, et agit selon la réponse :

| Le serveur répond | Le helper |
|---|---|
| un bail renouvelé | renouvelle de nouveau à la moitié de celui-ci |
| `404 not_enrolled` : il a oublié l'appareil (le bail a expiré, ou le serveur a redémarré) | s'enrôle de nouveau avec la même clé et le même locataire, et remonte le tunnel à partir de cette réponse ; si cela échoue aussi, démonte le tunnel |
| `403` (`not_a_member`, `key_not_registered`) : accès retiré | démonte le tunnel, et en indique la raison (`last_error`) |
| `401`, un `5xx`, ou rien | réessaie dans la minute, avant la fin du bail |

Le helper renouvelle avec le dernier bearer qui lui a été remis. Cela suffit pour un
jeton GitHub, pas pour un jeton d'accès go-authn, qui expire en quelques minutes et
que seule l'application peut rafraîchir. Aussi, tant que l'application tourne, `pkg/appcore` remet au
helper un bearer frais (l'action `renew` du helper) à 40 % de ce qu'il reste au bail
(au plus 8 minutes d'intervalle), avant l'échéance du renouvellement propre au helper. Une application redémarrée alors qu'un
tunnel est actif commence à le faire dès sa première interrogation d'état.

*Disconnect* (le `down` du helper) **désinscrit** le pair, rendant son
adresse immédiatement. Un helper qui s'arrête (son gestionnaire de services l'arrête,
ou la machine s'éteint) démonte le tunnel sans se désinscrire,
si bien qu'un helper redémarré retrouve le bail toujours en place, et que le bail d'une machine arrêtée
expire sur le serveur.

{{< callout type="info" >}}
Les applications v0.1.0 reposent sur des versions antérieures du client, qui ne font rien de tout cela :
elles ne renouvellent un bail qu'en se reconnectant, et laissent le pair sur la passerelle
après *Disconnect* jusqu'à la fin de son bail.
{{< /callout >}}

## Frontières de confiance {#trust-boundaries}

- Le **serveur** est le seul composant qui parle au fournisseur d'identité pour
  vérifier une connexion, et le seul autorisé à modifier les pairs de la passerelle.
- Sur l'appareil, le **helper** est le seul processus privilégié. Tout ce qui
  peut atteindre son socket peut lui demander d'agir, il agit donc dans le cadre de sa propre
  configuration : il ne s'enrôle qu'auprès des serveurs que nomme cette configuration et
  n'accepte aucune configuration de tunnel venant d'une requête. Voir
  [Helper privilégié]({{< relref "/components/helper.md" >}}).
- L'**application** s'exécute sous l'identité de la personne. Elle détient la session (jeton porteur et clé
  de l'appareil) dans un fichier `0600` de son répertoire de configuration.
- Une surveillance des routes transporte le jeton porteur, elle passe donc par **TLS** sauf vers une
  adresse de bouclage.
- Le contrat de communication se trouve en un seul endroit,
  [`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
  et `pkg/routespb`, importés à la fois par les clients et par le serveur.
