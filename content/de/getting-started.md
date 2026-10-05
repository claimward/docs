---
title: "Erste Schritte"
weight: 10
description: "Ein WireGuard-Gateway mit claimward-vpn-server aufsetzen, einen Anmelde-Client registrieren und ein erstes Gerät mit der macOS-, Linux- oder Windows-App verbinden."
tags: [wireguard, server, github, oidc]
---

Diese Anleitung führt durch das Aufsetzen eines Gateways und das Verbinden eines ersten Geräts. Das
Gateway ist ein Linux-Host; auf dem Gerät läuft eine der drei Desktop-Apps.

## 1. Das WireGuard-Gateway vorbereiten (Linux) {#1-prepare-the-wireguard-gateway-linux}

Legen Sie die Schnittstelle `wg0` mit einem Serverschlüssel und einem Listen-Port an. Claimward
verwaltet die *Peers* dieser Schnittstelle; die Schnittstelle selbst legt es nicht an.

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

## 2. Die Steuerungsebene starten {#2-run-the-control-plane}

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

Der Server benötigt die Rechte, `wg0` zu konfigurieren (root oder `CAP_NET_ADMIN`). Er
lauscht auf `:8443` (`LISTEN_ADDR`) für die Registrierungs-API und auf `:8444`
(`GRPC_ADDR`) für den RouteService. Alle Variablen finden Sie in der
[Server-Referenz]({{< relref "/components/server.md" >}}); für
Experimente ohne echte Schnittstelle setzen Sie `WG_DRYRUN=true`.

## 3. Den Anmelde-Client registrieren {#3-register-the-sign-in-client}

{{< tabs >}}
  {{< tab name="GitHub (Standard)" >}}
Legen Sie eine GitHub-**OAuth App** an (für eine Organisation oder persönlich) und **aktivieren Sie den Device
Flow** in ihren Einstellungen. Die Apps benötigen nur ihre **Client-ID**, kein Secret. Sie
fordern die Scopes `read:user`, `user:email` und `read:org` an.
  {{< /tab >}}
  {{< tab name="OpenID Connect" >}}
Legen Sie in Ihrem Identitätsanbieter einen **nativen/öffentlichen** Client mit PKCE und der
Loopback-Weiterleitung `http://127.0.0.1:<port>/callback` an. Der Port wird bei
jeder Anmeldung gewählt, daher muss der Anbieter jeden Loopback-Port akzeptieren (RFC 8252). Kein
Client-Secret. Starten Sie den Server mit `AUTH_PROVIDER=oidc`, `OIDC_ISSUER` und
`OIDC_CLIENT_ID`.
  {{< /tab >}}
  {{< tab name="go-authn" >}}
Deklarieren Sie bei einem [go-authn/bridge](https://github.com/go-authn/bridge)-Anbieter
zwei Clients: denjenigen, mit dem sich Personen anmelden (`device = true`,
`wireguard_keys = true`, eine `refresh_lifetime`), und den eigenen Client des Gateways
(`wireguard_peers`). Starten Sie den Server mit `AUTH_PROVIDER=go-authn`. Siehe
[Identitätsanbieter]({{< relref "/identity-providers.md#go-authn" >}}).
  {{< /tab >}}
{{< /tabs >}}

## 4. Ein Gerät verbinden {#4-connect-a-device}

Jede App hat einen **privilegierten Helper**, der sich beim Server registriert und
den Tunnel besitzt; er wird einmalig als Administrator installiert, zusammen mit den Servern, mit denen er sich
verbinden darf. Die App selbst läuft unter Ihrem Benutzer.

{{< tabs >}}
  {{< tab name="macOS" >}}
Aus einem Checkout von
[claimward-vpn-app-osx](https://github.com/claimward/claimward-vpn-app-osx):

```sh
sudo ./scripts/install-helper.sh https://vpn.example.com   # the root LaunchDaemon
task start:bundle                                          # build Claimward.app and open it
```

Tragen Sie dann die Server-URL, den Anbieter und seine Client-ID unter
**Configuration…** ein (oder in `~/Library/Application Support/Claimward/config.json`),
und klicken Sie auf **Connect**. Siehe die [macOS-App]({{< relref "/components/macos-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Linux" >}}
Aus einem Checkout von
[claimward-vpn-app-linux](https://github.com/claimward/claimward-vpn-app-linux):

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

Melden Sie sich ab und wieder an (das Installationsprogramm fügt Sie der Gruppe `claimward` hinzu), starten Sie
**Claimward VPN** aus dem Menü Ihrer Desktopumgebung, tragen Sie die Einstellungen ein und klicken Sie auf
**Connect**. Siehe die [Linux-App]({{< relref "/components/linux-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Windows" >}}
Aus einem Release-Ordner, der von `scripts/package.sh` aus
[claimward-vpn-app-windows](https://github.com/claimward/claimward-vpn-app-windows) erstellt wurde,
in einer PowerShell **mit erhöhten Rechten**:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.com -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Melden Sie sich von Windows ab und wieder an (das Installationsprogramm fügt Sie der Gruppe
**Claimward Users** hinzu), starten Sie **Claimward VPN** aus dem Startmenü und
klicken Sie auf **Connect**. Siehe die [Windows-App]({{< relref "/components/windows-app.md" >}}).
  {{< /tab >}}
{{< /tabs >}}

Eine Person, die mehreren Mandanten angehört, wird gebeten, einen davon zu wählen, bevor die
Verbindung hergestellt wird; siehe [Mandanten]({{< relref "/tenants.md" >}}).


Das Gerät hat nun eine Tunnelschnittstelle (`utunN` unter macOS, `utun` unter Linux, den
Wintun-Adapter **Claimward** unter Windows) mit seiner Adresse `10.80.0.x/32` und
leitet die Netze des Mandanten darüber.

{{< callout type="warning" >}}
Die Erneuerung der Lease kommt mit claimward-vpn-client v0.3.1, in den Apps ab
v0.2.0: Von da an erneuert der Helper die Lease, solange der Tunnel steht, und
meldet sich bei *Disconnect* ab. Die Apps in v0.1.0 tun das nicht: Eine Verbindung, die
länger als `LEASE_TTL` (standardmäßig 24 Stunden) besteht, wird vom Gateway entfernt,
und ein erneutes Verbinden beginnt eine neue Lease. Siehe
[Leases]({{< relref "/architecture.md#leases" >}}).
{{< /callout >}}
