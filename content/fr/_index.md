---
title: "Documentation de Claimward"
linkTitle: "Accueil"
type: docs
cascade:
  type: docs
description: "Claimward est une solution auto-hébergée d'accès réseau Zero Trust fondée sur WireGuard : les personnes se connectent avec le fournisseur d'identité que vous avez déjà, et leur appareil est enrôlé comme pair WireGuard de votre passerelle."
# Les cartes ci-dessous listent les sections : la barre latérale de gauche les répéterait.
sidebar:
  hide: true
toc: false
---

{{< brand-lockup >}}

**Claimward** est une solution auto-hébergée d'accès réseau Zero Trust fondée sur
[WireGuard](https://www.wireguard.com/). Les personnes se connectent avec le fournisseur
d'identité que vous avez déjà (GitHub, n'importe quel fournisseur OpenID Connect, ou un
fournisseur [go-authn](https://github.com/go-authn/bridge) placé devant une fédération
SAML) ; Claimward enrôle ensuite leur appareil comme pair WireGuard de votre
passerelle, avec une adresse qui lui est propre et les routes du locataire choisi.

Tout est écrit en Go. L'application macOS dessine sa fenêtre avec Svelte dans une
webview ; les applications Linux et Windows sont en Go pur
([go-widgets](https://github.com/go-widgets), sans cgo).

{{< cards >}}
  {{< card link="getting-started/" title="Prise en main" icon="lightning-bolt" subtitle="Mettre en place une passerelle et connecter un premier appareil." >}}
  {{< card link="architecture/" title="Architecture" icon="puzzle" subtitle="Plan de contrôle, plan de données, le flux d'enrôlement et les baux." >}}
  {{< card link="identity-providers/" title="Fournisseurs d'identité" icon="finger-print" subtitle="GitHub (par défaut), OpenID Connect, ou go-authn avec son registre de clés WireGuard." >}}
  {{< card link="tenants/" title="Locataires" icon="users" subtitle="Qui appartient à quoi, et le locataire choisi pour chaque session." >}}
  {{< card link="components/" title="Composants" icon="cube" subtitle="Le serveur, la bibliothèque client, le helper privilégié et les trois applications de bureau." >}}
  {{< card link="reference/protocol/" title="Référence du protocole" icon="code" subtitle="L'API d'enrôlement et le RouteService gRPC." >}}
  {{< card link="operations/" title="Exploitation" icon="cog" subtitle="TLS, la passerelle, les baux, l'état, l'API d'administration et les métriques." >}}
{{< /cards >}}

## Les éléments {#the-pieces}

| Dépôt | Version | Ce que c'est |
|------------|---------|------------|
| [`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server) | v0.2.0 | Plan de contrôle : vérifie la connexion, alloue les adresses, programme la passerelle WireGuard, diffuse les routes des locataires en gRPC, API d'administration et métriques |
| [`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client) | v0.3.1 | **Bibliothèque** Go partagée par les applications et le serveur : protocole réseau, fournisseurs de connexion, tunnel, helper privilégié, cœur des applications. Elle ne fournit aucun binaire |
| [`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx) | v0.2.0 | Application macOS : application Go de la barre des menus, interface Svelte dans une webview, helper LaunchDaemon root |
| [`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux) | v0.2.1 | Application Linux : fenêtre et zone de notification en Go pur, helper exécuté par systemd |
| [`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows) | v0.3.0 | Application Windows : fenêtre et zone de notification en Go pur, helper sous forme de service Windows, tunnel Wintun |

{{< callout type="info" >}}
**État d'avancement.** Ce sont des premières versions. Restent à venir, selon chaque
dépôt : le jeton de session dans le magasin de secrets de la plateforme (Keychain,
un trousseau, le Gestionnaire d'identification Windows), une application macOS signée
et notarisée, un MSI pour Windows, l'application des DNS sur macOS et Linux, et un état
côté serveur qui survive à un redémarrage. Le README de chaque dépôt liste ce qui reste à faire.
{{< /callout >}}
