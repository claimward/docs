---
title: "Application Linux"
linkTitle: "Application Linux"
weight: 5
description: "claimward-vpn-app-linux : une fenêtre et une icône dans la zone de notification dessinées en pur Go avec go-widgets, et un helper durci exécuté par systemd."
tags: [linux, application, helper, systemd]
---

[`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux)
**v0.2.1** est **une fenêtre et une icône dans la zone de notification dessinées en pur Go** avec
[go-widgets](https://github.com/go-widgets) : pas de webview, pas de GTK, pas de cgo
(`CGO_ENABLED=0`). Un **helper privilégié** exécuté par systemd détient le tunnel
WireGuard. La logique est celle de l'application macOS : toutes deux utilisent
[`pkg/appcore` et `pkg/helper`]({{< relref "/components/client.md" >}}).

## Conception {#design}

```text
 claimward-app (your session)
 ├─ internal/view        go-widgets/toolkit widgets, bound with go-widgets/mvvmtk
 ├─ internal/trayview    tray icon + menu (StatusNotifierItem over D-Bus)
 ├─ internal/viewmodel   all state as go-widgets/mvvm observables and commands
 └─ appcore              sign-in, tenant, session; drives the helper
        │ X11 / Wayland                  │ unix socket, JSON, 0660 root:claimward
        ▼                                ▼
   the window, the tray            claimward-helper (root, systemd)
                                   enrolls with a configured server,
                                   wireguard-go TUN + ip(8), route pushes
```

L'application s'exécute sous votre identité et ne touche jamais à la configuration réseau ni au
serveur lui-même : tout passe par le [helper]({{< relref "/components/helper.md" >}}).
Le modèle de vue détient chaque élément d'état et n'importe aucun widget ; la CI impose
MVVM avec [mvvmlint](https://github.com/go-widgets/mvvmlint) et « aucune
interface dessinée à la main » avec [bricolint](https://github.com/go-widgets/bricolint).

## Ce qu'elle fait {#what-it-does}

- **État** : qui est connecté, connecté au VPN ou non, l'adresse et l'interface,
  le locataire de la session, si le helper répond, le serveur. Il est interrogé
  toutes les 2 secondes.
- **Connexion** : pour un device flow, la fenêtre affiche le code et un bouton *Open sign-in
  page* (`xdg-open`) ; la connexion peut être annulée.
- **Locataire** : lorsque le serveur refuse une connexion parce que la personne appartient
  à plusieurs locataires, la fenêtre le signale et propose une liste déroulante ; *Choose tenant* demande
  la liste à l'avance. Le locataire ne peut pas être changé pendant la connexion.
- **Connect / Disconnect / Sign out**, **Settings** (URL du serveur, fournisseur,
  ID client GitHub, émetteur et ID client OIDC), et le **journal de connexion**.
- **Zone de notification** : une ligne d'état, *Connect*, *Disconnect*, *Open window*, *Quit* ;
  l'icône est en couleur pendant la connexion. Fermer la fenêtre laisse l'application dans la
  zone de notification ; *Quit* laisse le tunnel tel quel.

La zone de notification nécessite un hôte StatusNotifierItem (KDE Plasma, GNOME avec l'extension
*AppIndicator and KStatusNotifierItem Support*, waybar…). Sans
hôte, ou si l'élément de la zone de notification ne peut pas être placé sur le bus de session, l'application le signale au
démarrage et fermer la fenêtre la quitte.

## Installation {#install}

Compilez sous votre identité (Go 1.27.1 ou ultérieur), puis installez en tant que root :

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

`install.sh` :

1. crée le groupe `claimward` et vous y ajoute (`$SUDO_USER`, ou
   `--user`) : **déconnectez-vous puis reconnectez-vous** pour que cela s'applique ;
2. installe `claimward-app` dans `/usr/local/bin` et `claimward-helper` dans
   `/usr/local/sbin` (`--prefix` pour changer) ;
3. écrit `/etc/claimward/helper.json`, `root:root`, mode `0644`, avec le
   serveur indiqué (un fichier existant est conservé) ;
4. installe et démarre `claimward-helper.service`, et attend son socket ;
5. installe l'entrée de bureau et l'icône.

Lancez **Claimward VPN** depuis le menu du bureau ; `claimward-app -hidden`
démarre dans la zone de notification (pour une entrée de démarrage automatique). `sudo ./scripts/uninstall.sh`
supprime le tout et arrête le helper, ce qui ferme le tunnel ; `--purge`
supprime aussi `/etc/claimward` et le groupe.

## Configuration {#configure}

L'application : `~/.config/Claimward/config.json`, écrit par le formulaire des paramètres,
mode `0600`, surchargé par les variables `CLAIMWARD_*` (voir la
[bibliothèque client]({{< relref "/components/client.md#files-on-the-device" >}})).
La session est `~/.config/claimward/session.json`, mode `0600`.

Le helper : `/etc/claimward/helper.json` (voir
[Helper privilégié]({{< relref "/components/helper.md" >}})) ; après l'avoir modifié,
`sudo systemctl restart claimward-helper`.

## L'unité durcie {#the-hardened-unit}

`claimward-helper.service` ne conserve que `CAP_NET_ADMIN`, `CAP_NET_RAW` et
`CAP_CHOWN`, avec `NoNewPrivileges`, `ProtectSystem=strict` et seul `/run`
accessible en écriture, `ProtectHome`, `/dev/net/tun` seul depuis `/dev`, des familles d'adresses
limitées à unix, inet, inet6 et netlink, et les appels système
`@system-service`. `systemd-analyze security claimward-helper` lui attribue 2.5 (OK). Appartenir
au groupe `claimward` signifie être autorisé à activer et désactiver le VPN.

{{< callout type="info" >}}
**Vérifié** dans une machine virtuelle Ubuntu 24.04 (arm64) face à un serveur
de substitution. **Pas encore vérifié**, selon le README : un vrai bureau GNOME ou KDE,
Wayland, HiDPI, une connexion auprès d'un vrai fournisseur d'identité, et un
vrai claimward-vpn-server. Le fichier de session n'est pas encore dans un trousseau.
{{< /callout >}}
