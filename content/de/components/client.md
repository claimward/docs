---
title: "Client-Bibliothek"
linkTitle: "Client-Bibliothek"
weight: 2
description: "claimward-vpn-client: die Go-Bibliothek, die sich die Apps und der Server teilen – Anmeldung, das Wire-Protokoll, der Tunnel, der privilegierte Helper und der App-Kern. Sie liefert kein Binary aus."
tags: [client, go, wireguard, grpc]
---

[`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client)
**v0.12.0** ist eine Go-**Bibliothek**. Sie liefert kein Binary aus: Die ausführbaren Programme sind
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
| `pkg/pathmtu` | passt die Tunnel-MTU an den Pfad an: das `mtu` des Servers (Standard 1420), gesenkt auf die Schnittstellen-MTU zum Endpunkt minus 60 (IPv4) oder 80 (IPv6), nie unter 1280, nie über dem Wert des Servers; nur Standardbibliothek |
| `pkg/wgtun` | WireGuard-Tunnel im Userspace mit `wireguard-go`, dazu Adresse und Routen: `ifconfig`/`route` unter macOS, `ip` unter Linux, ein Wintun-Adapter über `winipcfg` unter Windows (mit DNS und MTU); benötigt Privilegien |
| `pkg/routeclient` | beobachtet den RouteService des Servers und meldet Aktualisierungen der Routen; TLS, außer zu Loopback |
| `pkg/appcore` | die Logik der Apps, gemeinsam für alle drei: Anmeldung, der für die Sitzung gewählte Mandant, Verbinden und Trennen über den Helper, Status für die Oberfläche |
| `pkg/appvm` | das View-Model der Apps, ohne Oberfläche: welcher Bildschirm gezeigt wird, was jeder Befehl darf, die Statusabfrage, die Ereignisse (Tunnel getrennt, Sitzung abgelaufen) und, seit v0.12.0, die Daten jedes Tunnels (`State.Tunnel`: Schnittstelle, Adresse, Endpunkt, erlaubte IPs, DNS, MTU, empfangene und gesendete Bytes, letzter Handshake); jede App passt es an ihre Widgets an |
| `pkg/helper` | der privilegierte Helper, gemeinsam für die drei Apps: registriert, besitzt den Tunnel, beobachtet gepushte Routen und genehmigt Server mit der Zustimmung des Systems ([Server-Genehmigung](../../server-approval/)) |
| `pkg/hproto`, `pkg/helperclient` | das Socket-Protokoll des Helpers und der Client der App dafür: `Approve`, `ApproveElevated`, `Revoke`, `Approved` und die typisierten Fehler `*NotApprovedError` und `ErrApprovalDenied` |
| `pkg/macauth` | Authorization Services von macOS für die Server-Genehmigung: `Obtain(prompt)` in der App, `Verify` im Helper |
| `pkg/tokenstore` | die Sitzung (Bearer-Token, Refresh-Token, privater Schlüssel des Geräts, gewählter Mandant) im Geheimnisspeicher des Betriebssystems: macOS-Keychain, Windows-DPAPI, Linux-Secret-Service; kein Klartext-Fallback |

## Dateien auf dem Gerät {#files-on-the-device}

| Datei | Was |
|---|---|
| `<config dir>/Claimward/config.json` | die Konfiguration der App (`appcore.Config`), `0600`, ihr Socket kann durch `CLAIMWARD_HELPER_SOCKET` überschrieben werden |
| `<config dir>/claimward/session.enc` (macOS und Linux), `session.dpapi` (Windows) | die versiegelte Sitzung; ihr Schlüssel liegt in der Keychain (macOS) oder im Secret Service (Linux), oder der Blob ist durch DPAPI geschützt. Unter Linux ist der Blob mit AES-GCM versiegelt, und nur sein Schlüssel liegt im Secret Service. |

`<config dir>` ist Go's `os.UserConfigDir()`: `~/Library/Application Support` unter
macOS, `~/.config` unter Linux, `%AppData%` unter Windows.

Das ist das Format des **Clients ab v0.10.0**, der sich mit mehreren Servern
gleichzeitig verbindet. Die Person gibt nur die URL eines Servers ein; Name,
Anbieter, Exklusivität und Logo werden aus dem
`/.well-known/claimward-configuration` des Servers gelesen.

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

| Schlüssel in `config.json` | |
|---|---|
| `version` | `2` |
| `servers[].url` | die Basis-URL des Servers (`https://`; `http://` nur für Loopback); muss eine sein, für die der Helper konfiguriert ist |
| `servers[].provider` | optional: die `id` des aus dem Dokument des Servers gewählten Anbieters |
| `socket_path` | optional: der Socket des Helpers, falls nicht der Standard. Kann durch `CLAIMWARD_HELPER_SOCKET` überschrieben werden, die einzige verbleibende Variable |

Eine Datei von v0.9.0 oder früher (`server_url`, `provider`, `github_client_id`,
`oidc_issuer`, `oidc_client_id` und die Variablen `CLAIMWARD_SERVER`,
`CLAIMWARD_AUTH_PROVIDER`, `CLAIMWARD_GITHUB_CLIENT_ID`, `CLAIMWARD_OIDC_*`) wird
beim ersten Laden einmalig migriert. Ein **exklusiver** Server wird abgelehnt, solange
ein anderer verbunden ist, und jeder andere, solange ein exklusiver verbunden ist; die
Ablehnung nennt den blockierenden Server. Seit **v0.11.0** hält jede Plattform einen
Tunnel pro Server, jeden auf seiner eigenen deterministischen Schnittstelle (unten).

Seit v0.11.0 ist `servers` des Helpers optional (die Vorab-Genehmigung durch den
Administrator), und ein Server, den die Person hinzufügt, gilt erst als vertrauenswürdig,
wenn das System zugestimmt hat: siehe [Server-Genehmigung](../../server-approval/). Die
`helper.json` des Helpers erhält `approvals`, die Datei der genehmigten Server.

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
- **Schnittstellennamen.** Eine Schnittstelle pro Server, aus der URL des Servers durch
  `wgtun.InterfaceName` benannt: macOS `utunN` (vom Kernel nummeriert), Linux `cw-` und
  zehn Hexziffern des SHA-256 der URL (13 Bytes, innerhalb der 15 von `IFNAMSIZ`),
  Windows `Claimward <Host> <6 Hex>`. Ein erneutes Verbinden ersetzt die Schnittstelle;
  ein Überbleibsel dieses Namens wird zuvor entfernt, und ein Linux-TUN-Gerät verschwindet
  mit seinem Prozess, ein abgestürzter Helper hinterlässt also keines.
- **Windows.** Das Gerät ist ein Wintun-Adapter, einer pro Server (siehe oben): `wintun.dll`
  (von <https://www.wintun.net>, signiert von WireGuard LLC) muss neben der
  ausführbaren Datei liegen, die `wgtun.Up` aufruft, worum sich das Packaging der Windows-App
  kümmert. Adresse, Routen, DNS und MTU werden über `winipcfg` gesetzt (die IP
  Helper API, reines Go, `CGO_ENABLED=0`).
- **Sitzungsspeicher.** Der Geheimnisspeicher der Plattform: die Login-Keychain von macOS
  (sie hält einen AES-GCM-Schlüssel; die Sitzung ist in `session.enc` versiegelt), Windows-DPAPI
  (`session.dpapi`) und unter Linux ebenfalls eine versiegelte `session.enc`, deren
  AES-GCM-Schlüssel im Secret Service über `secret-tool` liegt. Seit
  **v0.5.0** gibt es keinen Klartext-Fallback, und `CLAIMWARD_ALLOW_PLAINTEXT_SESSION`
  hat keine Wirkung: ohne nutzbaren Speicher schlägt das Speichern der Sitzung fehl, und die
  Anmeldung schlägt mit einem Fehler fehl, der benennt, was fehlt (unter Linux einen Secret-Service-Anbieter
  wie gnome-keyring oder KeePassXC installieren und entsperren, dazu `secret-tool`).
  Eine ältere `session.json` wird einmal gelesen, in den Speicher verschoben und gelöscht, oder
  gelöscht, wenn der Speicher sie ablehnt. Tests anderer Pakete verwenden
  `tokenstore.UseMemory()`.
