---
title: "Client-Bibliothek"
linkTitle: "Client-Bibliothek"
weight: 2
description: "claimward-vpn-client: die Go-Bibliothek, die sich die Apps und der Server teilen – Anmeldung, das Wire-Protokoll, der Tunnel, der privilegierte Helper und der App-Kern. Sie liefert kein Binary aus."
tags: [client, go, wireguard, grpc]
---

[`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client)
**v0.3.1** ist eine Go-**Bibliothek**. Sie liefert kein Binary aus: Die ausführbaren Programme sind
die der Apps (`cmd/claimward-app` und `cmd/claimward-helper` in jedem App-Repository).
Auch der Server importiert sie, für die Wire-Typen und die gRPC-Stubs.

{{< callout type="info" >}}
Es gibt keinen Kommandozeilen-Client `claimward`. Frühere Versionen dieses Moduls
hatten einen (`cmd/claimward`, mit `login` und `connect`); er wurde entfernt, und
das reine Bibliotheksmodul ist die Grundlage der Apps.
{{< /callout >}}

## Pakete {#packages}

| Paket | Zweck |
|---------|---------|
| `pkg/protocol` | der Wire-Vertrag (`/enroll`, `/tenants`, `/heartbeat`, `/deregister`), gemeinsam mit dem Server |
| `pkg/routespb` | generierte gRPC/Protobuf-Stubs des RouteService, gemeinsam mit dem Server |
| `pkg/auth` | interaktive Anmeldung hinter einem `Provider`: GitHub Device Flow (Standard), OIDC Code + PKCE oder go-authn Device Flow, dessen Anbieter außerdem den Schlüssel des Geräts registriert (`KeyRegistrar`) |
| `pkg/oidc` | der OIDC-Ablauf Authorization Code + PKCE: Discovery, Loopback-Weiterleitung |
| `pkg/browser` | öffnet eine URL im Standardbrowser mit absoluten Pfaden zu den Öffnerprogrammen, damit es aus GUI-Apps heraus funktioniert |
| `pkg/client` | `Enroll`, `Tenants`, `Heartbeat`, `Deregister` gegen den Server sowie `TunnelConfig`, um eine `EnrollResponse` in eine `wgtun.Config` umzuwandeln |
| `pkg/wgkey` | Erzeugung und Parsen von WireGuard-Schlüsseln |
| `pkg/wgtun` | WireGuard-Tunnel im Userspace mit `wireguard-go`, dazu Adresse und Routen: `ifconfig`/`route` unter macOS, `ip` unter Linux, ein Wintun-Adapter über `winipcfg` unter Windows (mit DNS und MTU); benötigt Privilegien |
| `pkg/routeclient` | beobachtet den RouteService des Servers und meldet Aktualisierungen der Routen; TLS, außer zu Loopback |
| `pkg/appcore` | die Logik der Apps, gemeinsam für alle drei: Anmeldung, der für die Sitzung gewählte Mandant, Verbinden und Trennen über den Helper, Status für die Oberfläche |
| `pkg/helper` | der privilegierte Helper, gemeinsam für die drei Apps: registriert, besitzt den Tunnel, beobachtet gepushte Routen |
| `pkg/hproto`, `pkg/helperclient` | das Socket-Protokoll des Helpers und der Client der App dafür |
| `pkg/tokenstore` | die Sitzung (Bearer-Token, Refresh-Token, privater Schlüssel des Geräts, gewählter Mandant) in einer JSON-Datei mit `0600` |

## Dateien auf dem Gerät {#files-on-the-device}

| Datei | Was |
|---|---|
| `<config dir>/Claimward/config.json` | die Konfiguration der App (`appcore.Config`), `0600`, überschrieben durch die Variablen `CLAIMWARD_*` |
| `<config dir>/claimward/session.json` | die Sitzung (`pkg/tokenstore`), `0600` |

`<config dir>` ist Go's `os.UserConfigDir()`: `~/Library/Application Support` unter
macOS, `~/.config` unter Linux, `%AppData%` unter Windows.

| Schlüssel in `config.json` | Variable | |
|---|---|---|
| `server_url` | `CLAIMWARD_SERVER` | die Basis-URL des Servers; muss eine sein, für die der Helper konfiguriert ist |
| `provider` | `CLAIMWARD_AUTH_PROVIDER` | `github` (Standard), `oidc` oder `go-authn` |
| `github_client_id` | `CLAIMWARD_GITHUB_CLIENT_ID` | die Client-ID der GitHub-OAuth-App |
| `oidc_issuer` | `CLAIMWARD_OIDC_ISSUER` | `oidc` und `go-authn` |
| `oidc_client_id` | `CLAIMWARD_OIDC_CLIENT_ID` | `oidc` und `go-authn` |
| `socket_path` | `CLAIMWARD_HELPER_SOCKET` | der Socket des Helpers, falls nicht der Standard |

## Verwendung in eigenen Werkzeugen {#use-in-your-own-tooling}

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

Ein langlebiger Client erneuert seine Lease mit `c.Heartbeat` vor
`resp.LeaseExpiresAt` und entfernt seinen Peer mit `c.Deregister`, wenn er fertig ist.

## Hinweise zu den Plattformen {#platform-notes}

- **DNS.** Die DNS-Server des Servers werden nur unter **Windows** angewendet; unter macOS
  und Linux werden sie im Protokoll übertragen, aber `pkg/wgtun` wendet sie noch
  nicht an.
- **Gepushte Routen** ersetzen die erlaubten IPs und die Routen; DNS-Änderungen in einem
  Push werden nicht angewendet.
- **Windows.** Das Gerät ist ein Wintun-Adapter namens `Claimward`: `wintun.dll`
  (von <https://www.wintun.net>, signiert von WireGuard LLC) muss neben der
  ausführbaren Datei liegen, die `wgtun.Up` aufruft, worum sich das Packaging der Windows-App
  kümmert. Adresse, Routen, DNS und MTU werden über `winipcfg` gesetzt (die IP
  Helper API, reines Go, `CGO_ENABLED=0`).
- **Sitzungsspeicher.** Eine Datei mit `0600`; die Verlagerung in den Geheimnisspeicher der Plattform
  steht noch aus.
