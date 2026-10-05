---
title: "Prise en main"
weight: 10
description: "Mettre en place une passerelle WireGuard avec claimward-vpn-server, déclarer un client de connexion, et connecter un premier appareil avec l'application macOS, Linux ou Windows."
tags: [wireguard, serveur, github, oidc]
---

Ce guide décrit la mise en place d'une passerelle et la connexion d'un premier appareil. La
passerelle est un hôte Linux ; l'appareil exécute l'une des trois applications de bureau.

## 1. Préparer la passerelle WireGuard (Linux) {#1-prepare-the-wireguard-gateway-linux}

Créez l'interface `wg0` avec une clé de serveur et un port d'écoute. Claimward
gère les *pairs* de cette interface ; il ne crée pas l'interface.

```ini
# /etc/wireguard/wg0.conf
[Interface]
Address = 10.80.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
```

```sh
wg genkey | tee server.key | wg pubkey > server.pub
sudo wg-quick up wg0
sudo sysctl -w net.ipv4.ip_forward=1   # if you route beyond the VPN subnet
```

## 2. Lancer le plan de contrôle {#2-run-the-control-plane}

```sh
go install github.com/claimward/claimward-vpn-server/cmd/claimward-server@v0.2.0

export AUTH_PROVIDER=github                     # the default
export GITHUB_ALLOWED_ORGS=claimward            # optional authorization (recommended)
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY_FILE=/etc/wireguard/server.key
export VPN_CIDR=10.80.0.0/24
export TLS_CERT=/etc/claimward/fullchain.pem    # HTTPS, and TLS on the gRPC RouteService
export TLS_KEY=/etc/claimward/privkey.pem
export GRPC_ENDPOINT=vpn.example.com:8444       # where clients watch for route updates

sudo -E "$(go env GOPATH)/bin/claimward-server"
```

Le serveur a besoin des droits pour configurer `wg0` (root, ou `CAP_NET_ADMIN`). Il
écoute sur `:8443` (`LISTEN_ADDR`) pour l'API d'enrôlement et sur `:8444`
(`GRPC_ADDR`) pour le RouteService. Voir la
[référence du serveur]({{< relref "/components/server.md" >}}) pour toutes les variables ;
pour des essais sans véritable interface, définissez `WG_DRYRUN=true`.

## 3. Déclarer le client de connexion {#3-register-the-sign-in-client}

{{< tabs >}}
  {{< tab name="GitHub (par défaut)" >}}
Créez une **OAuth App** GitHub (d'organisation ou personnelle) et **activez le Device
Flow** dans ses paramètres. Les applications n'ont besoin que de son **client ID**, sans secret. Elles
demandent les scopes `read:user`, `user:email` et `read:org`.
  {{< /tab >}}
  {{< tab name="OpenID Connect" >}}
Dans votre fournisseur d'identité, créez un client **natif/public** avec PKCE et la
redirection loopback `http://127.0.0.1:<port>/callback`. Le port est choisi à
chaque connexion, le fournisseur doit donc accepter n'importe quel port loopback (RFC 8252). Pas de
secret client. Lancez le serveur avec `AUTH_PROVIDER=oidc`, `OIDC_ISSUER` et
`OIDC_CLIENT_ID`.
  {{< /tab >}}
  {{< tab name="go-authn" >}}
Auprès d'un fournisseur [go-authn/bridge](https://github.com/go-authn/bridge), déclarez
deux clients : celui avec lequel les personnes se connectent (`device = true`,
`wireguard_keys = true`, un `refresh_lifetime`), et le client propre à la passerelle
(`wireguard_peers`). Lancez le serveur avec `AUTH_PROVIDER=go-authn`. Voir
[Fournisseurs d'identité]({{< relref "/identity-providers.md#go-authn" >}}).
  {{< /tab >}}
{{< /tabs >}}

## 4. Connecter un appareil {#4-connect-a-device}

Chaque application dispose d'un **helper privilégié** qui s'enrôle auprès du serveur et possède
le tunnel ; il est installé une seule fois, en tant qu'administrateur, avec les serveurs auxquels il peut
se connecter. L'application elle-même s'exécute sous votre compte.

{{< tabs >}}
  {{< tab name="macOS" >}}
Depuis une copie de travail de
[claimward-vpn-app-osx](https://github.com/claimward/claimward-vpn-app-osx) :

```sh
sudo ./scripts/install-helper.sh https://vpn.example.com   # the root LaunchDaemon
task start:bundle                                          # build Claimward.app and open it
```

Renseignez ensuite l'URL du serveur, le fournisseur et son client ID dans
**Configuration…** (ou dans `~/Library/Application Support/Claimward/config.json`),
puis cliquez sur **Connect**. Voir l'[application macOS]({{< relref "/components/macos-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Linux" >}}
Depuis une copie de travail de
[claimward-vpn-app-linux](https://github.com/claimward/claimward-vpn-app-linux) :

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

Déconnectez-vous puis reconnectez-vous à votre session (l'installateur vous ajoute au groupe `claimward`), lancez
**Claimward VPN** depuis le menu de votre bureau, renseignez les paramètres et cliquez sur
**Connect**. Voir l'[application Linux]({{< relref "/components/linux-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Windows" >}}
Depuis un dossier de version produit par `scripts/package.sh` de
[claimward-vpn-app-windows](https://github.com/claimward/claimward-vpn-app-windows),
dans un PowerShell **élevé** :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.com -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Fermez votre session Windows puis rouvrez-la (l'installateur vous ajoute au groupe
**Claimward Users**), lancez **Claimward VPN** depuis le menu Démarrer et
cliquez sur **Connect**. Voir l'[application Windows]({{< relref "/components/windows-app.md" >}}).
  {{< /tab >}}
{{< /tabs >}}

Une personne qui appartient à plusieurs locataires doit en choisir un avant que la
connexion soit établie ; voir [Locataires]({{< relref "/tenants.md" >}}).


L'appareil dispose maintenant d'une interface de tunnel (`utunN` sur macOS, `utun` sur Linux, l'adaptateur
Wintun **Claimward** sur Windows) avec son adresse `10.80.0.x/32`, et
de routes vers les réseaux du locataire passant par elle.

{{< callout type="warning" >}}
Le renouvellement des baux arrive avec claimward-vpn-client v0.3.1, dans les applications à partir de
v0.2.0 : dès lors, le helper renouvelle le bail tant que le tunnel est actif et
se désinscrit lors d'un *Disconnect*. Les applications v0.1.0 ne le font pas : une connexion qui reste
active plus longtemps que `LEASE_TTL` (24 heures par défaut) est retirée de la passerelle,
et une nouvelle connexion démarre un nouveau bail. Voir
[Baux]({{< relref "/architecture.md#leases" >}}).
{{< /callout >}}
