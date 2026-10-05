---
title: "Application Windows"
linkTitle: "Application Windows"
weight: 6
description: "claimward-vpn-app-windows : une fenêtre et une icône dans la zone de notification en pur Go, le service ClaimwardHelper, et wireguard-go sur un adaptateur Wintun."
tags: [windows, application, helper, wintun]
---

[`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows)
**v0.3.0** est une application de bureau avec une icône dans la zone de notification. Tout est
en Go avec `CGO_ENABLED=0` : la fenêtre et la zone de notification sont dessinées par
[go-widgets](https://github.com/go-widgets) (pas de webview, pas de serveur HTTP dans
l'application), et le tunnel est [wireguard-go](https://git.zx2c4.com/wireguard-go) sur un
adaptateur [Wintun](https://www.wintun.net), configuré via l'API IP Helper.
Sa logique et son helper sont les composants partagés
[`pkg/appcore` et `pkg/helper`]({{< relref "/components/client.md" >}}).

## Conception {#design}

```text
 claimward-app.exe (the person, unprivileged)
 ├─ internal/ui/view.go        widgets, bound by go-widgets/mvvmtk to …
 ├─ internal/ui/viewmodel.go   … the ViewModel: all state, observables and commands
 ├─ internal/ui/tray_binding   the tray menu, bound to the same ViewModel
 └─ appcore                    sign-in, session, tenant, helper client
        │ AF_UNIX socket, one JSON request each: C:\ProgramData\Claimward\helper.sock
        ▼
 claimward-helper.exe — the ClaimwardHelper service (LocalSystem)
   pkg/helper   enrolls with a server helper.json names, owns the tunnel
   pkg/wgtun    wireguard-go on the Wintun adapter "Claimward"; address, routes, DNS, MTU
```

La fenêtre affiche la connexion, l'adresse et l'interface, la personne connectée,
le locataire et si le helper répond ; l'invite du device flow avec un
bouton qui ouvre la page dans le navigateur par défaut (seule une page `https` est
jamais transmise au shell) ; **Connect / Disconnect / Sign out** ; **Choose
tenant** ; les paramètres, enregistrés dans `%AppData%\Claimward\config.json` ; et le
journal de connexion. L'état est interrogé toutes les 2 secondes. Le menu de la zone de notification propose
l'état, Connect, Disconnect, Open et Quit. Fermer la fenêtre quitte
l'application ; le tunnel appartient au service et reste actif jusqu'à Disconnect.

L'icône de la zone de notification apparaît à partir de la **v0.3.0**. Auparavant, la bibliothèque de la zone de notification n'avait pas
d'implémentation Windows de l'appel effectué par l'application, et l'application ignorait
l'erreur : les v0.1.0 et v0.2.0 n'affichaient donc **aucune icône dans la zone de notification**. La v0.3.0 est compilée avec la
bibliothèque de la zone de notification qui l'implémente (go-widgets/tray v0.14.0). Cela est vérifié par la
compilation et par les tests propres à la bibliothèque, pas encore sur un bureau Windows. Deux
lacunes connues : une icône qui ne peut pas être ajoutée est signalée sur stderr, qu'une
compilation fenêtrée n'affiche pas
([#6](https://github.com/claimward/claimward-vpn-app-windows/issues/6)), et
quitter peut laisser une icône fantôme jusqu'à ce que le pointeur passe dessus
([go-widgets/tray#37](https://github.com/go-widgets/tray/issues/37)).

## Installation {#install}

Depuis un dossier de version (`scripts/package.sh` les construit, avec Wintun), dans un
PowerShell **élevé** :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.org
# optionally, the app's settings for the current user as well:
.\install.ps1 -Server https://vpn.example.org -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Il copie les programmes et `wintun.dll` dans `C:\Program Files\Claimward`,
crée le groupe local **Claimward Users** et vous y ajoute, écrit
`C:\ProgramData\Claimward\helper.json`, enregistre et démarre le
service **ClaimwardHelper**, et ajoute un raccourci **Claimward VPN** au menu Démarrer.
L'appartenance prend effet à votre **prochaine connexion à Windows** ; d'ici là, le
socket vous refuse. Ajoutez d'autres personnes avec
`Add-LocalGroupMember -Group 'Claimward Users' -Member <name>`.

`.\uninstall.ps1` supprime le service, le raccourci et les programmes ;
`-RemoveData` supprime aussi `C:\ProgramData\Claimward` et le groupe. Il n'y a
pas encore de MSI.

`package.sh` télécharge `wintun-0.14.1.zip` depuis wintun.net et le refuse
si son SHA-256 ne correspond pas à celui épinglé dans le script ; la DLL est signée par
WireGuard LLC et ne se trouve pas dans le dépôt.

## Configuration {#configure}

L'application lit `%AppData%\Claimward\config.json`, puis les variables `CLAIMWARD_*`
(voir la [bibliothèque client]({{< relref "/components/client.md#files-on-the-device" >}})).
La session est `%AppData%\claimward\session.json`.

Le helper lit `C:\ProgramData\Claimward\helper.json` :

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "Claimward Users",
  "socket": "C:\\ProgramData\\Claimward\\helper.sock"
}
```

Le service journalise dans `C:\ProgramData\Claimward\helper.log` ; depuis une
console élevée, `claimward-helper run` l'exécute au premier plan. Les ACL que le helper
définit et vérifie sont décrites sous
[Helper privilégié]({{< relref "/components/helper.md#the-socket-windows" >}}).

{{< callout type="info" >}}
**Reste à faire :** un installateur MSI, et la session dans le Gestionnaire d'identification
Windows (DPAPI) plutôt que dans un fichier par utilisateur.
{{< /callout >}}
