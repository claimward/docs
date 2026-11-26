---
title: "Bibliothèque client"
linkTitle: "Bibliothèque client"
weight: 2
description: "claimward-vpn-client : la bibliothèque Go que partagent les applications et le serveur — connexion, protocole réseau, tunnel, helper privilégié et cœur des applications. Elle ne fournit aucun binaire."
tags: [client, go, wireguard, grpc]
---

[`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client)
**v0.7.0** est une **bibliothèque** Go. Elle ne fournit aucun binaire : les programmes exécutables
sont ceux des applications (`cmd/claimward-app` et `cmd/claimward-helper` dans le dépôt
de chaque application). Le serveur l'importe aussi, pour les types réseau et les stubs gRPC.

{{< callout type="info" >}}
Il n'existe pas de client en ligne de commande `claimward`. Les versions antérieures de ce module
en avaient un (`cmd/claimward`, avec `login` et `connect`) ; il a été supprimé, et
c'est sur le module réduit à la bibliothèque que s'appuient les applications.
{{< /callout >}}

## Paquets {#packages}

| Paquet | Rôle |
|---------|---------|
| `pkg/protocol` | le contrat réseau (`/enroll`, `/tenants`, `/heartbeat`, `/deregister`), partagé avec le serveur |
| `pkg/routespb` | les stubs gRPC/protobuf générés du RouteService, partagés avec le serveur |
| `pkg/auth` | la connexion interactive derrière un `Provider` : device flow GitHub (par défaut), code d'autorisation OIDC + PKCE, ou device flow go-authn, dont le fournisseur enregistre aussi la clé de l'appareil (`KeyRegistrar`) |
| `pkg/oidc` | le flux OIDC code d'autorisation + PKCE : découverte, redirection en boucle locale (loopback) |
| `pkg/browser` | ouvre une URL dans le navigateur par défaut avec des chemins d'ouverture absolus, pour fonctionner depuis des applications graphiques |
| `pkg/client` | `Enroll`, `Tenants`, `Heartbeat`, `Deregister` auprès du serveur, et `TunnelConfig` pour transformer une `EnrollResponse` en `wgtun.Config` |
| `pkg/wgkey` | génération et analyse des clés WireGuard |
| `pkg/pathmtu` | ajuste le MTU du tunnel au chemin : le `mtu` du serveur (1420 par défaut), abaissé au MTU de l'interface vers le point d'accès moins 60 (IPv4) ou 80 (IPv6), jamais sous 1280, jamais au-dessus de la valeur du serveur ; bibliothèque standard seule |
| `pkg/wgtun` | tunnel WireGuard en espace utilisateur avec `wireguard-go`, plus l'adresse et les routes : `ifconfig`/`route` sur macOS, `ip` sur Linux, un adaptateur Wintun via `winipcfg` sur Windows (avec DNS et MTU) ; nécessite des privilèges |
| `pkg/routeclient` | surveille le RouteService du serveur et signale les mises à jour de routes ; TLS sauf vers la boucle locale |
| `pkg/appcore` | la logique des applications, commune aux trois : connexion, locataire choisi pour la session, connexion et déconnexion via le helper, état pour l'interface |
| `pkg/appvm` | le modèle de vue des applications, sans interface : l'écran à afficher, ce que chaque commande peut faire, l'interrogation de l'état et les événements (tunnel coupé, session expirée) ; chaque application l'adapte à ses widgets |
| `pkg/helper` | le helper privilégié, commun aux trois applications : enrôle, possède le tunnel, surveille les envois de routes |
| `pkg/hproto`, `pkg/helperclient` | le protocole de socket du helper, et le client de l'application pour ce protocole |
| `pkg/tokenstore` | la session (bearer, jeton de rafraîchissement, clé privée de l'appareil, locataire choisi) dans le magasin de secrets du système : Keychain macOS, DPAPI Windows, Secret Service Linux ; aucun repli en clair |

## Fichiers sur l'appareil {#files-on-the-device}

| Fichier | Contenu |
|---|---|
| `<config dir>/Claimward/config.json` | la configuration de l'application (`appcore.Config`), `0600`, sa socket peut être surchargée par `CLAIMWARD_HELPER_SOCKET` |
| `<config dir>/claimward/session.enc` (macOS et Linux), `session.dpapi` (Windows) | la session scellée ; sa clé est dans le Keychain (macOS) ou le Secret Service (Linux), ou le blob est protégé par DPAPI. Sous Linux, le blob est scellé avec AES-GCM et seule sa clé est dans le Secret Service. |

`<config dir>` est le `os.UserConfigDir()` de Go : `~/Library/Application Support` sur
macOS, `~/.config` sur Linux, `%AppData%` sur Windows.

Voici le format du **client v0.10.0 et ultérieur**, qui se connecte à plusieurs
serveurs à la fois. La personne ne saisit que l'URL d'un serveur ; le nom, les
fournisseurs, l'exclusivité et le logo sont lus dans le
`/.well-known/claimward-configuration` du serveur.

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com", "provider": "campus"},
    {"url": "https://lab.example.org"}
  ],
  "socket_path": "/var/run/claimward-helper.sock"
}
```

| Clé de `config.json` | |
|---|---|
| `version` | `2` |
| `servers[].url` | l'URL de base du serveur (`https://` ; `http://` seulement en boucle locale) ; doit faire partie de celles pour lesquelles le helper est configuré |
| `servers[].provider` | facultatif : l'`id` du fournisseur choisi dans le document du serveur |
| `socket_path` | facultatif : la socket du helper, si ce n'est pas celle par défaut. Peut être surchargée par `CLAIMWARD_HELPER_SOCKET`, la seule variable restante |

Un fichier de la v0.9.0 ou antérieure (`server_url`, `provider`, `github_client_id`,
`oidc_issuer`, `oidc_client_id`, et les variables `CLAIMWARD_SERVER`,
`CLAIMWARD_AUTH_PROVIDER`, `CLAIMWARD_GITHUB_CLIENT_ID`, `CLAIMWARD_OIDC_*`) est
migré une fois au premier chargement. Un serveur **exclusif** est refusé tant qu'un
autre est connecté, et tout autre est refusé tant qu'un serveur exclusif l'est ; le
refus nomme le serveur bloquant. Linux et Windows ne tiennent pour l'instant qu'un
tunnel à la fois ; macOS en tient un par serveur.

## Utilisation dans vos propres outils {#use-in-your-own-tooling}

```go
ctx := context.Background()

// 1. Sign in. GitHub is the default provider (device flow).
provider, err := auth.New(auth.Config{Provider: "github", GitHubClientID: "Iv1.0123456789abcdef"})
if err != nil {
	log.Fatal(err)
}
tok, err := provider.Login(ctx, func(p auth.DevicePrompt) {
	fmt.Printf("visit %s and enter code %s\n", p.VerificationURI, p.UserCode)
})
if err != nil {
	log.Fatal(err)
}

// 2. A key pair, and with go-authn the PUBLIC key registered first: the
//    token for the server is the one RegisterKey returns.
keys, err := wgkey.Generate()
if err != nil {
	log.Fatal(err)
}
if reg, ok := provider.(auth.KeyRegistrar); ok {
	if tok, err = reg.RegisterKey(ctx, tok, keys.Public.String(), "laptop"); err != nil {
		log.Fatal(err)
	}
}

// 3. Enroll; "" lets the server use the person's only tenant.
c := client.New("https://vpn.example.com")
resp, err := c.Enroll(ctx, tok.Value, keys.Public,
	protocol.DeviceInfo{Name: "laptop", OS: "linux", Platform: "my-tool"}, "")
if err != nil {
	log.Fatal(err)
}

// 4. The tunnel (needs privileges), and optionally live routes.
cfg, err := client.TunnelConfig(resp, keys.Private)
if err != nil {
	log.Fatal(err)
}
tun, err := wgtun.Up(cfg)
if err != nil {
	log.Fatal(err)
}
defer tun.Close()
if resp.GRPCEndpoint != "" {
	go routeclient.Watch(ctx, resp.GRPCEndpoint, tok.Value, keys.Public.String(),
		func(u routeclient.Update) { _ = tun.UpdateRoutes(u.AllowedIPs) })
}
```

Un client de longue durée renouvelle son bail avec `c.Heartbeat` avant
`resp.LeaseExpiresAt`, et supprime son pair avec `c.Deregister` lorsqu'il a terminé.

## Notes par plateforme {#platform-notes}

- **DNS.** Les serveurs DNS du serveur ne sont appliqués que sur **Windows** ; sur macOS
  et Linux, ils sont transportés par le protocole mais `pkg/wgtun` ne les applique
  pas encore.
- **Les envois de routes** remplacent les IP autorisées et les routes ; les changements DNS
  contenus dans un envoi ne sont pas appliqués.
- **Windows.** Le périphérique est un adaptateur Wintun nommé `Claimward` : `wintun.dll`
  (provenant de <https://www.wintun.net>, signé par WireGuard LLC) doit se trouver à côté de
  l'exécutable qui appelle `wgtun.Up`, ce dont se charge le packaging de l'application
  Windows. L'adresse, les routes, le DNS et le MTU sont configurés via `winipcfg` (l'API IP
  Helper, en Go pur, `CGO_ENABLED=0`).
- **Stockage de la session.** Le magasin de secrets de la plateforme : le Keychain de
  connexion macOS (qui détient une clé AES-GCM ; la session est scellée dans `session.enc`), DPAPI
  sous Windows (`session.dpapi`), et sous Linux aussi un `session.enc` scellé, dont la clé
  AES-GCM est conservée dans le Secret Service via `secret-tool`. Depuis
  **v0.5.0**, il n'y a aucun repli en clair et `CLAIMWARD_ALLOW_PLAINTEXT_SESSION`
  est sans effet : sans magasin utilisable, l'enregistrement de la session échoue et la
  connexion échoue avec une erreur qui nomme ce qui manque (sous Linux, installez et déverrouillez
  un fournisseur de Secret Service tel que gnome-keyring ou KeePassXC, ainsi que `secret-tool`).
  Un ancien `session.json` est lu une fois, déplacé dans le magasin et supprimé, ou
  supprimé si le magasin le refuse. Les tests des autres paquets utilisent
  `tokenstore.UseMemory()`.
