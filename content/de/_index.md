---
title: "Claimward-Dokumentation"
linkTitle: "Startseite"
type: docs
cascade:
  type: docs
description: "Claimward ist eine selbst gehostete Zero-Trust-Lösung für den Netzwerkzugang auf Basis von WireGuard: Personen melden sich mit dem Identitätsanbieter an, den Sie bereits haben, und ihr Gerät wird als WireGuard-Peer Ihres Gateways registriert."
# Die Karten unten listen die Abschnitte auf: Die linke Seitenleiste würde sie wiederholen.
sidebar:
  hide: true
toc: false
---

{{< brand-lockup >}}

**Claimward** ist eine selbst gehostete Zero-Trust-Lösung für den Netzwerkzugang auf Basis von
[WireGuard](https://www.wireguard.com/). Personen melden sich mit dem Identitätsanbieter
an, den Sie bereits haben (GitHub, ein beliebiger OpenID-Connect-Anbieter oder ein
[go-authn](https://github.com/go-authn/bridge)-Anbieter vor einer SAML-Föderation);
Claimward registriert anschließend ihr Gerät als WireGuard-Peer Ihres
Gateways, mit einer eigenen Adresse und den Routen des gewählten Mandanten.

Alles ist in Go geschrieben. Die macOS-App zeichnet ihr Fenster mit Svelte in einer
Webview; die Linux- und die Windows-App sind reines Go
([go-widgets](https://github.com/go-widgets), kein cgo).

{{< cards >}}
  {{< card link="getting-started/" title="Erste Schritte" icon="lightning-bolt" subtitle="Ein Gateway aufsetzen und ein erstes Gerät verbinden." >}}
  {{< card link="architecture/" title="Architektur" icon="puzzle" subtitle="Steuerungsebene, Datenebene, der Registrierungsablauf und die Leases." >}}
  {{< card link="identity-providers/" title="Identitätsanbieter" icon="finger-print" subtitle="GitHub (Standard), OpenID Connect oder go-authn mit seinem Register der WireGuard-Schlüssel." >}}
  {{< card link="tenants/" title="Mandanten" icon="users" subtitle="Wer wohin gehört, und der für jede Sitzung gewählte Mandant." >}}
  {{< card link="components/" title="Komponenten" icon="cube" subtitle="Der Server, die Client-Bibliothek, der privilegierte Helper und die drei Desktop-Apps." >}}
  {{< card link="reference/protocol/" title="Protokollreferenz" icon="code" subtitle="Die Registrierungs-API und der gRPC-RouteService." >}}
  {{< card link="operations/" title="Betrieb" icon="cog" subtitle="TLS, das Gateway, Leases, Zustand, die Admin-API und Metriken." >}}
{{< /cards >}}

## Die Bausteine {#the-pieces}

| Repository | Release | Was es ist |
|------------|---------|------------|
| [`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server) | v0.2.0 | Steuerungsebene: prüft die Anmeldung, vergibt Adressen, programmiert das WireGuard-Gateway, streamt die Routen der Mandanten über gRPC, Admin-API und Metriken |
| [`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client) | v0.3.1 | Go-**Bibliothek**, die sich die Apps und der Server teilen: Wire-Protokoll, Anmeldeanbieter, Tunnel, privilegierter Helper, App-Kern. Sie liefert kein Binary aus |
| [`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx) | v0.2.0 | macOS-App: Menüleisten-App in Go, Svelte-Oberfläche in einer Webview, Helper als root-LaunchDaemon |
| [`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux) | v0.2.1 | Linux-App: Fenster und Infobereich in reinem Go, von systemd ausgeführter Helper |
| [`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows) | v0.3.0 | Windows-App: Fenster und Infobereich in reinem Go, Helper als Windows-Dienst, Wintun-Tunnel |

{{< callout type="info" >}}
**Stand.** Dies sind erste Releases. Laut den jeweiligen Repositorys steht
noch aus: das Sitzungstoken im Geheimnisspeicher der Plattform (Keychain,
ein Schlüsselbund, die Windows-Anmeldeinformationsverwaltung), eine signierte und notarisierte macOS-App,
ein MSI für Windows, unter macOS und Linux angewendetes DNS sowie ein Zustand auf dem Server,
der einen Neustart übersteht. Das README jedes Repositorys listet auf, was noch fehlt.
{{< /callout >}}
