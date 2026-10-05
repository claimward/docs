---
title: "Application macOS"
linkTitle: "Application macOS"
weight: 4
description: "claimward-vpn-app-osx : une application Go de la barre des menus dont la fenêtre est une application monopage Svelte dans une webview, avec un helper LaunchDaemon root."
tags: [macos, application, helper, svelte]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.2.0** est une application de la barre des menus (zone de notification) écrite en Go dont **toute l'interface
utilisateur est une application monopage Svelte rendue dans une webview**. Sa logique (connexion,
choix du locataire, connexion au VPN) et son helper sont les composants partagés
[`pkg/appcore` et `pkg/helper`]({{< relref "/components/client.md" >}}).

## Conception {#design}

```text
 claimward-app (tray process, as you)
 ├─ systray     menu: status / Open Claimward… / Configuration… / Connect / Disconnect / Quit
 ├─ uiserver    loopback HTTP: embedded Svelte SPA + token-guarded JSON API
 └─ appcore     sign-in, tenant choice, session; drives the helper
        │ spawns "claimward-app ui <url>"     │ Unix socket (JSON), 0660 root:admin
        ▼                                     ▼
   webview (WKWebView)                   claimward-helper (root LaunchDaemon)
   renders the Svelte UI                 enrolls with the server, wireguard-go: utunN,
                                         route pushes
```

Le processus de la zone de notification détient tout l'état et sert à la fois l'interface et une petite API JSON sur
`127.0.0.1`, protégée par un jeton propre à chaque lancement, comparé en temps constant. La
webview est une fenêtre minimale pointée sur cette URL de bouclage, dans un processus distinct,
car une seule boucle d'exécution Cocoa peut posséder le fil principal. Le
[helper]({{< relref "/components/helper.md" >}}) s'enrôle auprès du serveur et
détient le tunnel ; l'application n'est pas privilégiée.

## Compilation {#build}

Avec [go-task](https://taskfile.dev) :

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Lancez le bundle plutôt que le binaire nu : un binaire nu démarré depuis un
agent de la barre des menus ne peut pas amener sa fenêtre au premier plan. À la main :

```sh
cd frontend && npm install && npm run build && cd ..   # the Svelte UI, embedded with go:embed
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Configuration {#configure}

`~/Library/Application Support/Claimward/config.json`, également modifiable depuis
**Configuration…** (GitHub est la valeur par défaut) :

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "github",
  "github_client_id": "Iv1.0123456789abcdef"
}
```

Pour OIDC, définissez `"provider": "oidc"`, pour go-authn `"provider": "go-authn"`, avec
`"oidc_issuer"` et `"oidc_client_id"`. Avec GitHub et go-authn, un clic sur
**Connect** affiche un code à saisir sur la page indiquée ; avec OIDC, le navigateur
ouvre la page de connexion du fournisseur.

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

Une personne appartenant à plusieurs locataires en choisit un dans la fenêtre (« Choose a tenant… »),
qui les propose dès que le serveur indique qu'un choix est possible, ou sur demande. Le
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
**Reste à faire :** le jeton de session dans le Keychain (c'est aujourd'hui un fichier
`0600`), le helper installé avec SMJobBless, une version signée avec un
Developer ID, et le DNS appliqué sur macOS.
{{< /callout >}}
