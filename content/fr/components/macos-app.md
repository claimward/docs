---
title: "Application macOS"
linkTitle: "Application macOS"
weight: 4
description: "claimward-vpn-app-osx : une application Go native (une fenêtre et une icône de la barre des menus, dessinées par go-widgets avec les champs de texte et menus locaux du système), avec un helper LaunchDaemon root."
tags: [macos, application, helper, go-widgets]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.8.0** est une application native écrite en Go : une fenêtre et une icône de la
barre des menus, dessinées par [go-widgets](https://github.com/go-widgets), avec les
`NSTextField` et `NSPopUpButton` du système pour les saisies. Il n'y a ni webview, ni
serveur web local, ni JavaScript (avant v0.7.0, la fenêtre était une page Svelte dans
une webview). Sa logique (connexion, choix du locataire, connexion au VPN) et son helper
sont les composants partagés
[`pkg/appcore` et `pkg/helper`]({{< relref "/components/client.md" >}}) ; le modèle de
vue est `pkg/appvm`, le même que celui des applications Linux et Windows.

## Conception {#design}

```text
 claimward-app (one process, as you)
 ├─ window         go-widgets, with NSTextField / NSPopUpButton embedded
 ├─ status item    NSStatusItem: status / Open Claimward… / Connect / Disconnect / Quit
 ├─ notifications  when the tunnel drops or the session expires (from the app bundle)
 └─ view model     pkg/appvm over appcore: sign-in, tenant choice, session
        │ Unix socket (JSON), 0660 root:admin
        ▼
   claimward-helper (root LaunchDaemon)
   enrolls with the server, wireguard-go: utunN, route pushes
```

L'application est un seul processus non privilégié qui détient tout l'état. Les saisies
(URL du serveur, identifiants client) sont les champs de texte du système, avec sa méthode
de saisie et sa correction orthographique ; les choix du fournisseur et du locataire sont
des menus locaux. Le [helper]({{< relref "/components/helper.md" >}}) s'enrôle auprès du
serveur et détient le tunnel. Fermer la fenêtre quitte l'application, comme sous Linux et Windows.

La fenêtre a un en-tête (le logo Claimward, le titre et **Settings**), une barre latérale
**Servers** à gauche avec **+** et **−** sous la liste, et à droite le panneau de détail du
serveur sélectionné : son nom, le menu local **Tenant** avec **Refresh**, l'état de la
session, la connexion, Connect et Disconnect, et le journal de connexion. Le formulaire de
réglages s'ouvre dans une fenêtre à part, pour que l'état reste visible ; il s'affiche dans
la fenêtre principale là où une seconde fenêtre ne peut pas s'ouvrir.

## Compilation {#build}

Avec [go-task](https://taskfile.dev) :

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Lancez le bundle plutôt que le binaire nu : les notifications sont refusées à un
processus qui n'est pas dans un bundle d'application, si bien qu'avec un binaire nu une
coupure du tunnel n'arrive que dans le journal. À la main (plus de chaîne Node) :

```sh
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Configuration {#configure}

`~/Library/Application Support/Claimward/config.json`, pour les versions fondées sur le
client v0.10.0 ou ultérieur (le format est décrit sur la page du client) :

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com"}
  ]
}
```

Seule l'URL du serveur est configurée ; les fournisseurs viennent du serveur. Avec
GitHub et go-authn, un clic sur **Connect** affiche un code à saisir sur la page
indiquée ; avec OIDC, le navigateur ouvre la page de connexion du fournisseur. Les
versions plus anciennes (client v0.9.0 et antérieur) lisaient `server_url`, `provider`,
`github_client_id`, `oidc_issuer` et `oidc_client_id`.

## Installer le helper et lancer l'application {#install-the-helper-and-run}

```sh
sudo ./scripts/install-helper.sh https://vpn.example.org   # more servers may follow
open dist/Claimward.app                                    # then click Connect
```

L'installateur copie le helper dans `/Library/PrivilegedHelperTools/`, écrit
`/Library/Application Support/Claimward/helper.json` (appartenant à root, mode `0644`)
avec les serveurs indiqués, et charge le LaunchDaemon `com.claimward.helper`.
Le socket du helper est `/var/run/claimward-helper.sock`, `0660`,
`root:admin` ; il journalise dans `/var/log/claimward-helper.log`.
`sudo ./scripts/uninstall-helper.sh` le supprime.

## Locataires {#tenants}

Une personne appartenant à plusieurs locataires en choisit un dans le menu local **Tenant** du panneau de détail,
qui les liste dès que le serveur les a proposés ; **Refresh** les redemande. Le
choix vaut pour la session ; une nouvelle connexion l'oublie. Un **Connect** depuis la
barre des menus que le serveur refuse faute de choix ouvre la fenêtre.

## Publication {#release}

`.github/workflows/release.yml` construit `Claimward.dmg` sur les tags `v*` et
le joint à la version publiée. Lorsque les secrets de signature sont définis, il signe l'application
avec un Developer ID, puis notarise et agrafe le DMG ; sans eux, il se rabat
sur une signature ad hoc, que Gatekeeper bloque sur un DMG téléchargé. Le
dépôt ne contient aucun secret de signature, si bien que les DMG publiés (v0.1.0 et
v0.2.0) sont **signés ad hoc et non notarisés**. Le DMG contient l'application (avec le binaire du helper à l'intérieur) ; le
helper s'installe comme ci-dessus.

{{< callout type="info" >}}
**Reste à faire :** le helper installé avec SMJobBless, une version signée avec un
Developer ID, et le DNS appliqué sur macOS.
{{< /callout >}}

## Session et serveurs

La session (jetons et clé WireGuard de l'appareil) vit dans `session.enc`, scellée
avec AES-GCM ; la clé est conservée dans le **Keychain** de connexion. Elle n'est jamais
écrite en clair sur le disque et il n'y a aucun repli en clair : si le Keychain est
verrouillé ou indisponible (client v0.5.0 et ultérieur), la connexion échoue avec une erreur
qui le dit. Un `session.json` en `0600` d'une ancienne version est déplacé dans le
magasin au premier démarrage, ou supprimé en cas d'échec.

Le MTU du tunnel est le `mtu` du serveur, abaissé pour tenir dans le chemin vers
le serveur (le MTU de l'interface vers son point d'accès, moins 60 en IPv4 ou 80
en IPv6) et jamais inférieur à 1280 (client v0.6.0, `pkg/pathmtu`).

Le serveur doit être une URL **https**. Depuis v0.7.0, il n'y a plus d'API d'interface en
bouclage ni de jeton de lancement : la fenêtre et la logique partagent un seul processus.
