---
title: "Approbation des serveurs"
linkTitle: "Approbation des serveurs"
weight: 35
description: "Comment le helper root décide de faire confiance à un serveur que nomme l'application : la pré-approbation de l'administrateur, ou le consentement du système d'exploitation lui-même, retenu dans un fichier que seul root peut écrire et révocable à tout moment."
tags: [security, helper, approval, macos, linux, windows]
---

Le helper s'exécute en root (SYSTEM sous Windows) et un serveur auprès duquel il
s'enrôle choisit les routes et le pair du tunnel de la machine : un serveur hostile est
chaque paquet de la machine, envoyé là-bas. Depuis le **client v0.11.0**, le helper ne
prend un serveur de l'application que si l'une de ces conditions est remplie :

1. la configuration de l'administrateur le nomme (`servers` dans `helper.json`,
   désormais facultatif : la **pré-approbation**) ;
2. il a été **approuvé** auparavant, et dit toujours ce qu'il disait alors ;
3. il est approuvé **maintenant**, avec le consentement du système d'exploitation,
   obtenu par le helper lui-même.

Un indicateur de l'application, un champ de la requête ou une affirmation de quelque
sorte n'est jamais un consentement.

## Ce qui est demandé au système

| Plateforme | Consentement |
|---|---|
| macOS | droit Authorization Services `com.claimward.helper.approve-server`, règle `authenticate-admin-nonshared` : nom et mot de passe d'un administrateur, à chaque fois. L'application obtient l'autorisation (`macauth.Obtain`) et envoie sa forme externe de 32 octets ; le helper la fait vérifier par le système et la détruit, donc un jeton achète une approbation. Un jeton forgé ne nomme rien dans le système et est refusé |
| Linux | action polkit `com.claimward.helper.approve-server` (`auth_admin`), demandée au bus système pour le processus derrière le socket : son pid via `SO_PEERCRED` et son heure de démarrage via `/proc/<pid>/stat`, ce qui déjoue la réutilisation des pid. Le fichier de politique est livré dans `packaging/polkit/` et va dans `/usr/share/polkit-1/actions/` |
| Windows | un second socket, `C:\ProgramData\Claimward\approve.sock`, dont l'ACL ne nomme que SYSTEM et les Administrateurs : un utilisateur standard ne peut s'y connecter sans élévation UAC. Seule compte une requête arrivée par là |

Sans autorisateur configuré, le helper refuse toute approbation : il échoue fermé. Une
requête refusée, ou à laquelle le système ne peut répondre, ne change rien.

## Ce qui est retenu

Le helper garde les serveurs approuvés dans un fichier que seul root peut écrire :

| Plateforme | Fichier |
|---|---|
| macOS | `/var/db/claimward/approved-servers.json` |
| Linux | `/var/lib/claimward/approved-servers.json` |
| Windows | `C:\ProgramData\Claimward\approved-servers.json` |

Chaque entrée est l'URL canonique du serveur et le SHA-256 de son **identité de
découverte** : son nom et ses fournisseurs d'identité (id, genre, émetteur, identifiants
client). Un serveur qui change l'un d'eux n'est pas celui qui a été approuvé : le helper
le refuse (`server_identity_changed`) jusqu'à nouvelle approbation. Que le serveur soit
exclusif, son logo et les noms d'affichage des fournisseurs ne font pas partie de
l'identité, pas plus que son certificat TLS, renouvelé toutes les quelques semaines (la
connexion est vérifiée contre la PKI web à chaque usage).

Le fichier est relu à chaque usage, donc **le supprimer, ou retirer une ligne, révoque
aussitôt** ; l'action `revoke` fait de même pour un serveur. La liste `servers` de
l'administrateur n'est jamais modifiée par le helper.

## Erreurs vues par l'application

| Code | Sens |
|---|---|
| `server_not_approved` | le serveur n'est ni pré-approuvé ni approuvé : demander à la personne de l'approuver |
| `server_identity_changed` | il était approuvé et ne dit plus la même chose : l'approuver à nouveau |
| `approval_denied` | le consentement du système n'a pas été donné |

## Limites, énoncées

- Sous macOS, le **texte de l'invite est fourni par l'application** qui demande : un
  processus hostile du groupe du socket peut donc faire demander par le système à un
  administrateur d'approuver son propre serveur, et un administrateur distrait peut dire
  oui. Le justificatif est celui d'un administrateur, jamais mis en cache, et vaut pour
  une approbation.
- Sous Windows, un processus élevé peut tout approuver, puisqu'un administrateur peut de
  toute façon modifier le fichier.
- Linux n'a pas non plus de cache : `auth_admin` demande à chaque fois.
