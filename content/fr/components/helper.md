---
title: "Helper privilégié"
linkTitle: "Helper privilégié"
weight: 3
description: "Le processus root ou SYSTEM de chaque application : il ne s'enrôle qu'auprès des serveurs que nomme sa propre configuration, n'accepte aucune configuration de tunnel venant d'une requête, et écoute sur une socket que seul son groupe peut atteindre."
tags: [helper, sécurité, macos, linux, windows]
---

Chaque application dispose d'un **helper privilégié** : un LaunchDaemon root sur macOS, un service
systemd sur Linux, le service **ClaimwardHelper** (LocalSystem) sur Windows. C'est
le seul processus privilégié de l'application. Les trois partagent le même code,
`pkg/helper` de [claimward-vpn-client](https://github.com/claimward/claimward-vpn-client) ;
chaque application ne fournit qu'un `main` qui charge la configuration et se met à l'écoute.

Le helper assure la communication avec le serveur en plus du tunnel : il s'enrôle,
monte le tunnel et surveille les envois de routes. Sur macOS, la protection de la vie privée
« Réseau local » empêche une application non privilégiée de joindre un serveur du réseau local, et root en est
exempté ; les autres plateformes suivent le même chemin pour que les trois applications se comportent
de la même façon.

## Le protocole de socket {#the-socket-protocol}

Une requête JSON par connexion, une réponse JSON (`pkg/hproto`) :

| Action | Ce que fait le helper |
|---|---|
| `connect` | s'enrôle auprès du serveur nommé dans la requête, si sa configuration l'autorise, avec le bearer, la clé privée, le nom d'appareil et le locataire fournis ; monte le tunnel ; surveille le RouteService |
| `tenants` | demande au serveur à quels locataires le bearer peut se connecter |
| `down` | démonte le tunnel |
| `status` | connecté ou non, l'interface, l'adresse, le locataire |

## Borné par sa propre configuration {#bounded-by-its-own-configuration}

Tout processus capable d'atteindre la socket du helper peut le faire agir ; ce qu'il
fait est donc borné par **sa propre** configuration, jamais par la requête :

- **Il ne s'enrôle qu'auprès d'un serveur que nomme sa configuration.** Un helper qui
  prendrait le serveur dans la requête laisserait n'importe quel processus local le diriger vers
  un serveur de son choix, répondant avec des routes pour `0.0.0.0/0` : chaque paquet de
  la machine, envoyé là où ce processus l'aurait décidé.
- **Il n'accepte aucune configuration de tunnel venant d'une requête.** Le tunnel est ce que ce
  serveur a répondu lors de l'enrôlement. Les anciennes actions `up` et `update-routes`,
  qui en acceptaient une, ont disparu.
- **Sa configuration doit appartenir à root** (à SYSTEM ou aux Administrateurs sur
  Windows) **et n'être modifiable par personne d'autre**, sinon le helper ne démarre pas :
  celui qui l'écrit choisit les serveurs de confiance.

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "claimward",
  "socket": "/var/run/claimward-helper.sock"
}
```

| Clé | |
|---|---|
| `servers` | **obligatoire** : les serveurs auprès desquels le helper peut s'enrôler. Le `server_url` de l'application doit en faire partie (comparaison sans `/` final) |
| `group` | qui peut utiliser la socket en plus de root : `admin` sur macOS, `claimward` sur Linux, `Claimward Users` sur Windows par défaut |
| `socket` | `/var/run/claimward-helper.sock` par défaut, `C:\ProgramData\Claimward\helper.sock` sur Windows |

| Plateforme | `helper.json` |
|---|---|
| macOS | `/Library/Application Support/Claimward/helper.json` |
| Linux | `/etc/claimward/helper.json` |
| Windows | `C:\ProgramData\Claimward\helper.json` |

## La socket : macOS et Linux {#the-socket-macos-and-linux}

La socket est en **`0660`**, appartenant à root et au groupe du helper. Elle est créée
avec un umask restrictif, de sorte qu'elle n'existe jamais avec un mode plus large, dans un répertoire
que seul root peut modifier (le helper refuse un répertoire que quelqu'un d'autre pourrait modifier, puisque cette personne
pourrait remplacer la socket par la sienne et recevoir le bearer de l'application). La
socket de l'ancien helper était en `0666`.

## La socket : Windows {#the-socket-windows}

Sur Windows, les mêmes règles prennent la forme d'ACL, que le helper pose et relit
lui-même plutôt que de compter sur un installateur pour l'avoir fait :

- le répertoire de la socket, `C:\ProgramData\Claimward`, reçoit une DACL **protégée**
  (rien n'est hérité de ProgramData, qui permet à tout utilisateur d'y créer des fichiers) :
  SYSTEM et Administrateurs en contrôle total, le groupe de la socket autorisé
  à le lister et à le traverser, rien de plus. Il est créé portant déjà cette
  DACL, et un répertoire qui est une jonction ou un lien est refusé ;
- la socket reçoit sa propre DACL : SYSTEM, Administrateurs, et le groupe autorisé
  à se connecter (lecture/écriture) ;
- le groupe est le groupe local **`Claimward Users`**, que l'installateur
  crée. S'il n'existe pas, la socket est ouverte à **INTERACTIVE**
  (toute personne connectée à la machine, en console ou par Bureau à distance) et le
  helper consigne qu'il l'a fait ;
- `helper.json` doit **appartenir à SYSTEM ou aux Administrateurs, et n'être modifiable par
  personne d'autre** : le helper lit le propriétaire et la DACL du fichier et refuse toute
  entrée d'autorisation accordant l'écriture, l'ajout, la suppression, `WRITE_DAC`, `WRITE_OWNER` ou
  l'écriture/tous droits génériques à un autre SID, ainsi qu'une DACL nulle.

Les règles (`pkg/helper/acl.go`) sont des fonctions pures, testées sur toutes les plateformes ;
le job de CI Windows les applique à de vrais fichiers et les relit.

## Surveillance des routes sur TLS {#route-watches-over-tls}

Une surveillance des routes transporte le jeton porteur ; `pkg/routeclient` l'exécute donc sur
**TLS**, vérifié par rapport aux autorités racines du système, sauf vers une adresse de boucle locale.
Face à un serveur dont le RouteService n'est pas en TLS, la négociation échoue avant l'envoi du
jeton, et le tunnel reste monté sans mises à jour des routes en direct.

L'arrêt du helper démonte le tunnel.
