---
title: "Locataires"
weight: 40
description: "Les routes sont rattachées à des locataires. Une personne peut appartenir à plusieurs d'entre eux et en choisit un par session ; l'appareil se connecte à celui-là."
tags: [locataires, serveur, grpc]
---

Un **locataire** est un ensemble de routes (`allowed_ips`) et de serveurs DNS, ainsi que
les règles qui disent qui lui appartient. Une personne peut appartenir à plusieurs
locataires : elle en choisit un par session, et l'appareil se connecte à celui-là.

## Appartenance {#membership}

Une personne appartient à tout locataire qui mentionne l'un des éléments suivants :

| Champ | Comparé à |
|---|---|
| `domains` | le domaine d'une adresse e-mail **vérifiée** (une adresse non vérifiée n'est qu'une chaîne saisie par la personne) |
| `groups` | la revendication `groups` du jeton (OIDC ; go-authn : droits eduPerson), ou les organisations GitHub de la personne |
| `idps` | l'établissement qui s'est porté garant d'elle : l'`idp` de go-authn, un entity ID SAML |

Une personne qui ne correspond à aucun appartient au locataire `default`, et seulement dans ce cas.

## D'où viennent les locataires {#where-tenants-come-from}

Le serveur démarre avec un seul locataire, `default`, dont les routes sont `PUSH_ROUTES`
(par défaut `VPN_CIDR`) et dont les serveurs DNS sont `DNS`. Les autres locataires sont
créés, modifiés et supprimés via l'[API d'administration et la WebUI]({{< relref "/operations.md#admin-api-and-webui" >}}),
qui modifient les trois listes d'appartenance à côté des routes. Le locataire par défaut
ne peut pas être supprimé.

{{< callout type="warning" >}}
Les locataires sont conservés **en mémoire** (v0.2.0) : un redémarrage du serveur ne laisse que
le locataire `default`, reconstruit à partir de l'environnement.
{{< /callout >}}

## En choisir un par session {#choosing-one-per-session}

| Requête | Ce que fait le serveur |
|---|---|
| `GET /api/v1/tenants` | liste les locataires auxquels l'appelant peut se connecter, `[{"id", "name"}]`, pour qu'un client propose le choix |
| `POST /api/v1/enroll` avec `tenant` | le locataire doit être l'un d'eux, sinon `403 not_a_member` |
| `POST /api/v1/enroll` sans `tenant` | l'unique locataire de l'appelant ; une personne qui en a plusieurs reçoit `409 tenant_required`, avec la liste dans le message, plutôt que d'être routée vers un réseau qu'elle n'a pas choisi |
| `POST /api/v1/heartbeat` | refusé avec `403 not_a_member` dès que la personne ne fait plus partie du locataire de la session |
| RouteService `Watch` | diffuse les routes du locataire **dans lequel l'appareil s'est enrôlé**, retrouvé par la clé de l'appareil, qui doit être celle de l'appelant |

Dans les applications (`pkg/appcore`) :

- **`Tenants`** demande au serveur, via le helper, quels locataires la personne
  peut rejoindre ;
- **`SetTenant`** enregistre le choix dans la session, et uniquement un locataire que le
  serveur a proposé ; une nouvelle connexion l'oublie ;
- **`Connect`** enrôle l'appareil dans ce locataire. Une personne qui en a plusieurs et n'a pas
  choisi reçoit `ErrTenantRequired`, avec les locataires dans l'état.

Une personne qui n'a qu'un locataire ne choisit jamais. L'application macOS ouvre sa fenêtre lorsqu'un
**Connect** depuis la barre des menus est refusé faute de choix ; les applications Linux et
Windows affichent le choix dans leur fenêtre. L'application Linux ne permet pas de changer de
locataire pendant la connexion.

## Mises à jour des routes {#route-updates}

Modifier les routes d'un locataire incrémente son `serial` et pousse le nouvel ensemble vers chaque
appareil qui surveille ce locataire via le RouteService gRPC. Le helper remplace
les allowed IPs du pair WireGuard et ajoute ou retire les routes correspondantes,
sans nouvel enrôlement. Supprimer un locataire met fin à ses surveillances.
