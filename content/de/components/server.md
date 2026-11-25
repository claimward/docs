---
title: "Server"
linkTitle: "Server"
weight: 1
description: "claimward-vpn-server: prüft die Anmeldung, vergibt VPN-Adressen, programmiert das WireGuard-Gateway, streamt die Routen der Mandanten über gRPC und stellt eine Admin-API und Metriken bereit."
tags: [server, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.10.0** ist die Steuerungsebene. Er prüft das Bearer-Token, das ein Gerät vorlegt,
vergibt VPN-Adressen und programmiert das WireGuard-Gateway mit einem Peer pro
registriertem Gerät. Er läuft auf dem Gateway-Host, neben einem vorhandenen `wg0`: Linux
(nftables) oder, ab v0.10.0, OpenBSD (pf, siehe [OpenBSD](#openbsd)).

## Was er bereitstellt {#what-it-serves}

| Listener | Pfad | Zweck |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | prüfen, den Mandanten wählen, eine Adresse vergeben, den Peer hinzufügen, die Tunnelkonfiguration zurückgeben |
| | `GET /api/v1/tenants` | die Mandanten, mit denen sich der Aufrufer verbinden darf |
| | `POST /api/v1/heartbeat` | die Lease des Geräts erneuern |
| | `POST /api/v1/deregister` | den Peer entfernen |
| | `GET /healthz` | Liveness |
| | `/admin/` | Admin-API und WebUI, wenn die Credential `admin-token` existiert |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | streamt die Routen des Mandanten und ihre Aktualisierungen |
| `METRICS_ADDR` (kein Standard: aus, solange nicht gesetzt) | `GET /metrics` | Prometheus-Metriken, auf einem eigenen Listener, nie auf `LISTEN_ADDR` |

Die API-Anfragen tragen `Authorization: Bearer <token>`: ein GitHub-Access-Token,
ein OIDC-ID-Token oder ein go-authn-Access-Token, je nach `AUTH_PROVIDER`.
Die Nutzdaten sind im
[Registrierungsprotokoll]({{< relref "/reference/protocol.md" >}})
beschrieben.

Mit `TLS_CERT` und `TLS_KEY` verwenden beide Listener TLS. Ohne sie ist die HTTP-API
unverschlüsselt (terminieren Sie TLS an einem Proxy), ebenso der RouteService, den die
Clients dann ablehnen, außer über Loopback: Geräte verbinden sich, erhalten aber keine Live-Aktualisierungen
der Routen.

## Konfiguration {#configuration}

Die Einstellungen stehen in der Umgebung. **Secrets nicht**: Seit v0.6.0 sind
sie Dateien in einem Credentials-Verzeichnis, siehe [Credentials](#credentials) unten.

| Variable | Erforderlich | Standard | Hinweise |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | Identitätsanbieter: `github`, `oidc` oder `go-authn` |
| `GITHUB_ALLOWED_ORGS` | `github` | — | CSV-Allowlist der Organisationen: Ein aktives Mitglied einer davon wird zugelassen, ebenso ein benanntes Mandantenmitglied. Seit v0.5.0 ist sie **nur optional, wenn mindestens ein Mandant `members` hat**: Ohne beides startet der Server nicht, es gibt keine Ausnahme-Option (zuvor: Pflicht seit v0.4.0) |
| `GITHUB_API_URL` | | `https://api.github.com` | für GitHub Enterprise zu setzen |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | URL des Issuers (Discovery) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | die Audience, die Tokens tragen müssen |
| `OIDC_ALLOWED_DOMAINS` | | — | CSV-Allowlist der E-Mail-Domains (`oidc`); die E-Mail des Tokens muss verifiziert sein |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | der eigene Client des Gateways beim Anbieter (`wireguard_peers`) |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | wie oft die Liste der registrierten Schlüssel abgerufen wird |
| `GOAUTHN_SSF` | | `false` | zusätzlich den Shared-Signals-Stream des Anbieters abfragen, damit auf eine Deaktivierung sofort reagiert wird; der Client des Gateways muss dort SSF-Empfänger sein |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | wie oft der SSF-Stream abgefragt wird |
| `WG_ENDPOINT` | ✅ | — | öffentlicher `host:port` des Gateways, den Clients mitgeteilt |
| `CREDENTIALS_DIRECTORY` | ✅ | — | das Verzeichnis mit den Secret-Dateien, siehe [Credentials](#credentials) |
| `WG_INTERFACE` | | `wg0` | zu verwaltende Schnittstelle |
| `WG_DRYRUN` | | `false` | Peer-Operationen protokollieren statt sie anzuwenden (lokale Entwicklung) |
| `VPN_CIDR` | | `10.80.0.0/24` | IPv4-Adresspool; sein erster Host ist der des Gateways |
| `PUSH_ROUTES` | | `VPN_CIDR` | CSV-Routen des Mandanten `default` |
| `TENANTS_FILE` | | — | JSON-Datei mit Mandanten, beim Start geladen, samt [Zugriffsrichtlinie]({{< relref "/tenants.md#access-policy" >}}) |
| `DNS` | | — | CSV-DNS-Server des Mandanten `default` |
| `KEEPALIVE` | | `25` | den Clients mitgeteiltes Persistent Keepalive (Sekunden) |
| `LEASE_TTL` | | `24h` | wie lange eine Registrierung ohne Heartbeat gilt |
| `TUNNEL_MTU` | | abgeleitet | MTU der WireGuard-Schnittstelle, 1280 bis 9000, als `mtu` angekündigt; alles andere verweigert den Start. Ungesetzt: Uplink-MTU minus 80, höchstens 1420, mindestens 1280. Dieselbe atomare Tabelle `inet claimward` senkt außerdem das MSS jedes TCP-SYN, das die Schnittstelle quert (weitergeleitet in beide Richtungen sowie Eingang für das Gateway selbst), auf diese MTU minus 40 (IPv4) bzw. 60 (IPv6) |
| `LISTEN_ADDR` | | `:8443` | HTTP-Listen-Adresse |
| `GRPC_ADDR` | | `:8444` | Listen-Adresse des RouteService; `Watch`-Streams werden alle 15 s neu autorisiert und enden, wenn die Identität nicht mehr zugelassen ist |
| `METRICS_ADDR` | | — (aus) | eigener Listener für `/metrics`, **nur wenn gesetzt** (seit v0.9.0 gibt es keinen Standardport: der frühere `127.0.0.1:9090` kollidierte mit Prometheus); nie auf `LISTEN_ADDR`. Er nennt jeden Tenant: auf Loopback oder in einem privaten Netz halten |
| `MAX_DEVICES_PER_SUBJECT` | | `5` | Geräte, die eine Identität registrieren darf |
| `GRPC_ENDPOINT` | | — | den Clients mitgeteilter `host:port` des RouteService; ist er leer, beobachten sie nicht |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS und TLS auf dem RouteService |
| `DEBUG` | | — | beliebiger Wert: Debug-Protokollierung (eine Zeile pro Anfrage) |

## Credentials {#credentials}

Jedes Secret ist eine **Datei** im Verzeichnis, das `CREDENTIALS_DIRECTORY`
nennt, nie eine Umgebungsvariable: Eine Umgebung wird in jeden Kindprozess und
jeden Crash-Dump kopiert. systemd setzt die Variable für `LoadCredential=` und
`LoadCredentialEncrypted=`; auf den anderen Plattformen setzen Sie sie selbst.
Die Dateinamen sind fest, ein abschließender Zeilenumbruch wird entfernt.

| Datei | Erforderlich | Inhalt |
|------|----------|---------|
| `wg-private-key` | immer | der private Schlüssel des Gateways in Base64 |
| `admin-token` | nein | Bearer-Token der Admin-API und der WebUI; **ohne die Datei sind sie deaktiviert** |
| `goauthn-gateway-secret` | `AUTH_PROVIDER=go-authn` | das Secret des Gateway-Clients |
| `github-token` | wenn ein Mandant `members` hat | Bearer für `GET /users/{login}` (siehe [Mandanten]({{< relref "/tenants.md" >}})) |

Eine fehlende erforderliche Datei verhindert den Start und wird benannt. Vor dem
Lesen prüft der Server jede Datei über den offenen Deskriptor (`O_NOFOLLOW`,
dann `fstat`) und **verweigert** einen symbolischen Link, alles außer einer
regulären Datei, eine für Gruppe oder andere lesbare Datei, eine Datei, die
nicht der UID des Servers gehört, eine leere Datei und eine über 64 KiB. Eine
Ausnahme seit v0.7.1: Eine Datei der UID 0 mit genau dem Modus `0440` wird
akzeptiert, wenn ihre Gruppe die GID des Servers oder eine seiner
Zusatzgruppen ist (so ein Kubernetes-Secret-Volume mit `fsGroup`). Eine
zweite seit v0.9.0, für systemd mit `DynamicUser=yes`: systemd lässt die Datei
`root:root`, Modus `0400`, plus einen schreibgeschützten POSIX-ACL-Eintrag für
die UID des Dienstes (`src/core/exec-credential.c:338-361`,
`src/shared/acl-util.c:448-494`), sodass `stat` `0440` zeigt. Der Server liest
`system.posix_acl_access` vom offenen Deskriptor und akzeptiert genau
`user::` (ohne Schreiben oder Ausführen), `user:<seine UID>:r--`, `group::---`, `mask::r--`, `other::---`;
jeder andere benannte Benutzer oder jede Gruppe, jedes Schreib- oder
Ausführungsbit und ein fehlerhafter oder zu großer Wert werden abgelehnt. Die
Fehlermeldung nennt die Abhilfe.

| Plattform | `CREDENTIALS_DIRECTORY` | Eigentümer und Modus |
|----------|-------------------------|----------------|
| systemd | von `LoadCredentialEncrypted=` gesetzt | mit `DynamicUser=yes` (wie ausgeliefert): Eigentum von root mit schreibgeschützter ACL für die UID des Dienstes, akzeptiert; mit festem `User=` auf einem Dateisystem ohne ACL: der Dienstbenutzer, `0400`. Privates tmpfs |
| Docker Swarm | `/run/secrets`, von Hand gesetzt | `mode: 0400` am Secret |
| Docker Compose | `/run/secrets`, von Hand gesetzt | die der Host-Datei: `chown` und `chmod 0400`, und `user:` passend setzen |
| Podman | `/run/secrets`, von Hand gesetzt | `--secret ...,mode=0400` (Quadlet: `Secret=...,mode=0400`) |
| Kubernetes | der Mount-Pfad des Secret-Volumes, von Hand gesetzt | `defaultMode: 0440` und `fsGroup`: die Dateien sind `root:<fsGroup>`, von der Gruppenregel oben akzeptiert, daher läuft der Pod als Nicht-root-UID mit allen Capabilities außer `NET_ADMIN` entfernt. `add: [NET_ADMIN]` allein gibt einer Nicht-root-UID die Capability nicht (keine Ambient-Menge): Die Binärdatei im Image braucht `setcap cap_net_admin=+ep` (nach capabilities(7), nicht auf einem Cluster gemessen) |
| s6 (ohne systemd) | `/run/sdcreds/claimward-server`, von `sdcreds s6-run` gesetzt | der Dienstbenutzer, `0400`, in einem privaten tmpfs (siehe [s6](#s6-deploy)) |
| sonst | ein beliebiges Verzeichnis | `chmod 0400`, Eigentümer: der Dienstbenutzer |

Fertige Units für systemd, Compose, Podman, Kubernetes und s6 liegen im
Verzeichnis `deploy/` des Repositorys, mit den Schritten für `systemd-creds
encrypt`. Hosts ohne systemd erhalten dasselbe Verzeichnis von
`go-authn/sdcreds` (siehe [s6](#s6-deploy)); der Server hängt nicht davon ab.

Die Organisationsprüfung des Anbieters `github` verwendet `github-token` nicht:
Sie läuft mit dem Token der *Person*, ein privates Mitglied ist also nur
sichtbar, wenn dieses Token `read:org` trägt. Die Credential ist optional,
solange nur Organisationen verwendet werden.

{{< callout type="warning" >}}
**Migration von v0.5.0** (inkompatibel). `ADMIN_TOKEN`, `WG_PRIVATE_KEY`,
`WG_PRIVATE_KEY_FILE` und `GOAUTHN_GATEWAY_SECRET_FILE` werden nicht mehr
gelesen, und der Server verweigert den Start, solange eine davon gesetzt ist;
er nennt die anzulegende Datei. Legen Sie jeden Wert in seine Datei
(`admin-token`, `wg-private-key`, `goauthn-gateway-secret`), entfernen Sie die
Variable und setzen Sie `CREDENTIALS_DIRECTORY`. Ein Mandant mit `members`
braucht jetzt auch `github-token`.
{{< /callout >}}

## Authentifizierungsanbieter {#authentication-providers}

Die Authentifizierung ist hinter der Schnittstelle `Verifier` austauschbar
(`internal/auth`):

- **`github`** (Standard): Das Bearer-Token ist ein GitHub-OAuth-Access-Token aus dem
  Device Flow. Der Server löst es über die GitHub-API auf (`/user`,
  `/user/orgs`) und lässt mit `GITHUB_ALLOWED_ORGS` ein aktives Mitglied
  einer dieser Organisationen oder ein benanntes Mandantenmitglied zu (die Liste
  ist nur optional, wenn ein Mandant `members` hat). Es ist kein Client-Secret beteiligt.
- **`oidc`**: Das Bearer-Token ist ein OIDC-ID-Token, geprüft gegen den Issuer mit
  der Audience `OIDC_CLIENT_ID` und der optionalen Allowlist der E-Mail-Domains.
- **`go-authn`**: Das Bearer-Token ist ein Access-Token (`at+jwt`) eines
  [go-authn/bridge](https://github.com/go-authn/bridge)-Anbieters, und der
  Schlüssel des Geräts muss dort von derselben Person registriert sein. Der Server liest
  die signierte Liste der registrierten Schlüssel des Anbieters
  ([go-authn/wireguard](https://github.com/go-authn/wireguard)) und entfernt aus
  `wg0` einen Schlüssel, den der Anbieter zurückzieht.

Jeden Ablauf von Ende zu Ende finden Sie unter
[Identitätsanbieter]({{< relref "/identity-providers.md" >}}).

## Registrierungsregeln {#enrollment-rules}

- **Ein Schlüssel gehört demjenigen, der ihn registriert hat.** Das Registrieren eines Schlüssels, den eine andere Identität
  hält, wird abgelehnt (`409 key_taken`): Ein öffentlicher Schlüssel ist öffentlich, und ihn zu übernehmen
  gäbe die Macht, das Gerät seines Besitzers abzumelden.
- Derselbe Schlüssel, erneut von seinem Besitzer registriert, behält seine Adresse und erhält eine neue
  Lease.
- Die einzige erlaubte IP des Peers ist das `/32` des Geräts, sodass Geräte die Adressen der jeweils
  anderen nicht verwenden können.
- Der Mandant ist derjenige, den der Aufrufer angefordert hat, sofern er Mitglied ist, oder sein
  einziger. Siehe [Mandanten]({{< relref "/tenants.md" >}}).

## Wie er das Gateway programmiert {#how-it-programs-the-gateway}

Der Server verwendet [`wgctrl`](https://pkg.go.dev/golang.zx2c4.com/wireguard/wgctrl),
um Peers auf einer vorhandenen Schnittstelle hinzuzufügen und zu entfernen, und prüft beim Start, dass
die Schnittstelle existiert. Die Schnittstelle selbst (ihr privater Schlüssel und Listen-Port)
bleibt `wg-quick` oder systemd-networkd beim Booten überlassen, was die privilegierte
Einrichtung der Schnittstelle aus dem dauerhaft laufenden Dienst heraushält.

## OpenBSD (pf) {#openbsd}

Ab v0.10.0 läuft der Server auch unter OpenBSD und setzt die Zugriffsrichtlinie
dort mit pf statt mit nftables durch. Er spricht den Kernel direkt über die
ioctls von `/dev/pf` an; er startet nie `pfctl`, und es gibt keinen Rückfall auf
`pfctl`.

- **Unterstützte Versionen: OpenBSD 7.9 und 8.0.** Sie teilen sich dasselbe
  Layout von `struct pf_rule`, das der Server gegen die laufende Version prüft.
  Auf jeder anderen Version startet der Server nicht, statt eine Regel falsch zu
  kodieren.
- **`pf.conf` gehört Ihnen.** Der Server ändert den Hauptregelsatz nie. Fügen
  Sie `/etc/pf.conf` eine Zeile hinzu und lassen Sie `pf` aktiviert:

  ```text
  anchor "claimward"
  ```

  Der Server lädt die Richtlinie in diesen Anchor. Beim Start liest er den
  Hauptregelsatz zurück und prüft, dass er `anchor "claimward"` aufruft.
- **Er startet nicht,** wenn `/dev/pf` nicht lesend und schreibend geöffnet
  werden kann (er muss als root starten), wenn pf deaktiviert ist, wenn der
  Hauptregelsatz den Anchor nicht aufruft (die Richtlinie würde geladen, ohne
  etwas zu filtern) und wenn `pf.conf` für die WireGuard-Schnittstelle (`wg0`,
  `wg*`) `set skip on` enthält, weil pf den Datenverkehr der Peers dann nie
  sähe.
- **Dieselbe Richtlinie wie unter Linux.** Standardmäßig wird der auf
  `WG_INTERFACE` eingehende Verkehr verworfen; erlaubt ist nur IPv4, IPv6
  durch den Tunnel wird verworfen. Die MSS-Begrenzung (`TUNNEL_MTU`) gilt für
  beide Familien, als Regel `match ... scrub (max-mss N)`.
- **Atomar und fail-closed.** Anchor und Tabellen werden in einer einzigen
  pf-Transaktion ersetzt, danach zurückgelesen und mit dem verglichen, was
  geladen werden sollte. Schlägt das fehl, wird ein vollständiges Verwerfen
  geladen. Der Anchor bleibt beim Beenden des Prozesses bestehen. Tabellennamen
  tragen ein Generationssuffix pro Ladevorgang, sodass das kurze Fenster
  zwischen dem Übernehmen der Tabellen und dem der Regeln nie die Regeln eines
  Mandanten auf die Peers eines anderen anwenden kann.
- **Rechtetrennung (ab v0.11.0).** Das Versprechen `pf` von `pledge(2)` erlaubt
  nur zwölf der `DIOC*`-ioctls (`sys/kern/kern_pledge.c`, `pledge_ioctl`); der
  Server braucht zusätzlich `DIOCRINADEFINE`, `DIOCXROLLBACK`, `DIOCGETRULES`,
  `DIOCGETRULE`, `DIOCXEND` und `DIOCRGETADDRS`; jedes andere ioctl würde den
  Prozess beenden. Daher hat der Eltern-Prozess (root), der `/dev/pf` bedient,
  kein Pledge. Der unprivilegierte Kindprozess `_claimward`, der die Geheimnisse
  hält und das Netz bedient, wird vor dem Bedienen mit `unveil(2)` und
  `pledge(2)` eingeschränkt (siehe unten).
- **WireGuard-Peers (ab v0.11.0).** Vor v0.11.0 scheiterte unter OpenBSD eine
  Anmeldung beim Hinzufügen des Peers zu `wg(4)` (Issue Nr. 79). Der Server
  schreibt Peers jetzt mit den ioctls `SIOCSWG` und `SIOCGWG` aus
  `sys/net/if_wg.h` und liest sie mit einem eigenen Dekoder zurück. In echten
  OpenBSD-7.9- und -8.0-amd64-VMs geprüft: Das Strukturlayout stimmt mit dem des
  C-Compilers überein, und Hinzufügen, Ersetzen, Entfernen und Aufräumen
  funktionieren auf einer echten `wg(4)`-Schnittstelle. OpenBSD auf arm64 wird
  nur cross-kompiliert, nicht auf einem Kernel ausgeführt.

### Bereitstellung unter OpenBSD (rc.d) {#openbsd-deploy}

Ab v0.10.1 liefert das Repository `deploy/openbsd/` mit: ein `rc.d(8)`-Skript,
ein `environment.example`, ein `hostname.wg0.example` und ein `pf.conf.example`.

- **Zwei Prozesse (ab v0.11.0).** Die WireGuard-Peer-Konfiguration von `wg(4)`
  liegt hinter `suser(9)` (`sys/net/if_wg.c`), und `/dev/pf` ist nur durch
  seinen Geräteknoten geschützt, der root vorbehalten ist: `pfopen`
  (`sys/net/pf_ioctl.c`) prüft nichts weiter. OpenBSD hat keine privilegierte
  Gruppe, mit der ein unprivilegierter Benutzer das eine oder das andere dürfte;
  das Skript startet den Daemon daher als root (`daemon_user="root"`), und der
  Daemon teilt sich in zwei Prozesse. Der **Eltern-Prozess** (root) fügt Peers
  hinzu und entfernt sie, setzt die Tunnel-MTU und lädt den pf-Anchor; er liest
  kein Geheimnis, bedient kein Netz und macht nur `/dev/pf` per `unveil(2)`
  sichtbar. Das **Kind**, ausgeführt als Benutzer `_claimward`, hält die
  Geheimnisse, die TLS- und gRPC-Listener, den Identitätsanbieter und die
  Mandantenrichtlinie und wird vor dem Bedienen mit `unveil(2)` und `pledge(2)`
  (`stdio rpath inet dns`) eingeschränkt. Kann es die Rechte nicht abgeben,
  startet der Server nicht. Das Kind fragt den Eltern-Prozess über ein
  Socketpair, und dieser verweigert alles außerhalb des Adresspools
  (`VPN_CIDR`).
- **Der Benutzer `_claimward` muss existieren**, und die Ports müssen größer als
  1024 sein (die Vorgaben 8443 und 8444 sind es); um auf 443 zu bedienen,
  leiten Sie mit einem pf-`rdr-to` um.
- **Geheimnisse sind Dateien** in `/etc/claimward/credentials`, einem
  Verzeichnis `0700` im Besitz von `_claimward`, jede Datei `0400` und im Besitz
  von `_claimward` (`install(1)`). Das Skript setzt `CREDENTIALS_DIRECTORY`
  darauf; kein Geheimnis steht in der Umgebung, in Argumenten oder in einer URL.
  Die nicht geheimen Einstellungen stehen in `/etc/claimward/environment`, die
  root gehört.
- **`wg0` muss existieren**, bevor der Server startet: `hostname.wg0` enthält
  denselben privaten Schlüssel wie das Geheimnis `wg-private-key` (Modus `0640`).

```sh
install -m 0555 claimward-server /usr/local/bin/claimward-server
useradd -g =uid -c claimward -d /var/empty -s /sbin/nologin -r 1..999 _claimward
install -d -m 0755 -o root -g wheel /etc/claimward
install -d -m 0700 -o _claimward -g _claimward /etc/claimward/credentials
install -m 0400 -o _claimward -g _claimward wg-private-key /etc/claimward/credentials/wg-private-key
install -m 0600 -o root -g wheel environment.example /etc/claimward/environment   # dann bearbeiten
install -m 0640 -o root -g wheel hostname.wg0.example /etc/hostname.wg0           # dann bearbeiten
sh /etc/netstart wg0
install -m 0555 claimward_server /etc/rc.d/claimward_server
rcctl enable claimward_server
rcctl start claimward_server && rcctl check claimward_server
```

`rcctl start` meldet `(ok)` erst, wenn der Server auf `LISTEN_ADDR` Verbindungen
annimmt; ein Daemon, der vorher endet, etwa an einem Geheimnis, das dem Konto
`_claimward` nicht gehört, ergibt `(failed)`.

Das Protokoll geht an syslog (`/var/log/daemon`). Die CI führt dieses Skript in
echten OpenBSD-7.9- und -8.0-VMs aus: `rcctl start`, die Startzeile,
`rcctl check`, ein Eltern-Prozess als root mit einem Kind `_claimward`, eine
Anmeldung über das Kind, deren Peer auf `wg0` erscheint, und `rcctl stop`;
danach einen Start mit einem Geheimnis im Besitz von root und einen Start ohne
den Anchor in `pf.conf`, die beide fehlschlagen müssen.

## Bereitstellung unter s6 (sdcreds) {#s6-deploy}

Ab v0.10.2 liefert das Repository `deploy/s6/claimward-server/` (`run` und
`finish`) für Hosts ohne systemd mit. `sdcreds s6-run` (go-authn/sdcreds v0.2.0
oder neuer) entschlüsselt jede Datei seines `--source`-Verzeichnisses in ein
privates tmpfs, schreibt jede mit Modus `0400` und `--user` als Eigentümer,
setzt `CREDENTIALS_DIRECTORY` und startet den Server unter diesem Benutzer. Eine
Datei, die der UID des Prozesses gehört und für Gruppe und andere nicht
zugänglich ist, ist die erste Form, die der Lader akzeptiert; er bleibt also
unverändert. Kein Geheimnis geht durch die Umgebung, durch argv oder eine URL.

- **Eine Capability, absichtlich behalten.** Der Server braucht `CAP_NET_ADMIN`
  (wgctrl, nftables, MTU der Schnittstelle). Standardmäßig leert `s6-run` alle
  Capability-Mengen des Dienstes und lässt `no_new_privs` aktiv; das Beispiel
  übergibt `--keep-cap=CAP_NET_ADMIN`, sodass der Server mit genau dieser einen
  Capability läuft (`CapEff` `0x1000`). Sie wirkt auf den Netzwerk-Namespace, in
  dem der Supervisionsbaum läuft: den des Hosts, außer Sie starten `s6-svscan`
  in einem eigenen (`ip netns exec`).
- **Namen.** Jede Datei von `--source` heißt wie ihr Geheimnis
  (`wg-private-key`, `github-token`, `admin-token`, `goauthn-gateway-secret`) und
  wird mit `sdcreds encrypt --name=<dieser Name>` verschlüsselt; jeder andere
  Name stoppt den Start. `s6-run` braucht root und `CAP_SYS_ADMIN` (es mountet
  ein Dateisystem).
- **Nicht geheime Konfiguration** steht in `/etc/claimward/env`, das das
  `run`-Skript liest.
- **Container** brauchen es nicht: Compose, Podman und Kubernetes mounten
  Geheimnisse bereits als Dateien (Tabelle oben).

Die CI führt dieses Verzeichnis unter einem echten `s6-svscan` aus, in einem
Netzwerk-Namespace, mit einer echten WireGuard-Schnittstelle und nftables (kein
Trockenlauf). Sie prüft, dass das Log den aus dem verschlüsselten Geheimnis
abgeleiteten öffentlichen Schlüssel enthält (und keinen Kontrollschlüssel), dass
der Server als Dienstbenutzer mit `CapEff` `0x1000` und `no_new_privs` läuft,
dass kein Geheimnis in seiner Umgebung steht, dass eine Geheimnisdatei mit Modus
`0644` abgelehnt wird und dass das Stoppen des Dienstes den Mount entfernt.

## Lokal ausführen {#run-locally}

Mit `WG_DRYRUN=true` wird kein WireGuard-Gerät angetastet:

```sh
export AUTH_PROVIDER=oidc
export OIDC_ISSUER=https://accounts.google.com
export OIDC_CLIENT_ID=xxxx.apps.googleusercontent.com
export WG_ENDPOINT=vpn.example.com:51820
export CREDENTIALS_DIRECTORY=$HOME/.local/state/claimward-dev-creds
(umask 077; mkdir -p "$CREDENTIALS_DIRECTORY"; wg genkey > "$CREDENTIALS_DIRECTORY/wg-private-key")
chmod 0400 "$CREDENTIALS_DIRECTORY/wg-private-key"
export WG_DRYRUN=true LISTEN_ADDR=:8080

go run ./cmd/claimward-server
```

`task run:dev` tut dasselbe mit GitHub-Anmeldung und einem flüchtigen Schlüssel, und
`task dex` startet ein lokales [Dex](https://dexidp.io/), bei dem man sich anmelden kann
(`deploy/dev/`).

{{< callout type="warning" >}}
**Hinter TLS betreiben.** Bearer-Tokens sind Zugangsdaten: Stellen Sie die API immer über
HTTPS bereit, entweder mit `TLS_CERT`/`TLS_KEY` oder hinter einem Proxy, der TLS terminiert, und
geben Sie dem RouteService ein Zertifikat, damit Geräte Live-Aktualisierungen der Routen erhalten.
{{< /callout >}}
