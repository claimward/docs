---
title: "Mandanten"
weight: 40
description: "Routen sind an Mandanten gebunden. Eine Person kann mehreren angehören und wählt einen pro Sitzung; das Gerät verbindet sich mit diesem."
tags: [mandanten, server, grpc]
---

Ein **Mandant** ist eine Menge von Routen (`allowed_ips`) und DNS-Servern sowie die Regeln,
die festlegen, wer ihm angehört. Eine Person kann mehreren Mandanten angehören: Sie
wählt einen pro Sitzung, und das Gerät verbindet sich mit diesem.

## Mitgliedschaft {#membership}

Eine Person gehört jedem Mandanten an, der eines der folgenden Merkmale nennt:

| Feld | Abgeglichen mit |
|---|---|
| `domains` | der Domain einer **verifizierten** E-Mail-Adresse (eine nicht verifizierte ist eine Zeichenkette, die die Person eingegeben hat) |
| `groups` | dem Claim `groups` des Tokens (OIDC; go-authn: eduPerson-Entitlements) oder den GitHub-Organisationen der Person |
| `idps` | der Einrichtung, die für sie gebürgt hat: das `idp` von go-authn, eine SAML-Entity-ID |

Eine Person, auf die nichts davon zutrifft, gehört dem Mandanten `default` an, und nur dann.

## Woher die Mandanten kommen {#where-tenants-come-from}

Der Server startet mit einem Mandanten, `default`, dessen Routen `PUSH_ROUTES`
(standardmäßig `VPN_CIDR`) und dessen DNS-Server `DNS` sind. Weitere Mandanten werden
über die [Admin-API und WebUI]({{< relref "/operations.md#admin-api-and-webui" >}}) angelegt, bearbeitet und gelöscht,
die neben den Routen die drei Mitgliedschaftslisten bearbeiten. Der Standardmandant
kann nicht gelöscht werden.

{{< callout type="warning" >}}
Mandanten werden **im Arbeitsspeicher** gehalten (v0.2.0): Ein Neustart des Servers lässt nur
den Mandanten `default` übrig, neu aufgebaut aus der Umgebung.
{{< /callout >}}

## Einen pro Sitzung wählen {#choosing-one-per-session}

| Anfrage | Was der Server tut |
|---|---|
| `GET /api/v1/tenants` | listet die Mandanten, mit denen sich der Aufrufer verbinden darf, `[{"id", "name"}]`, damit ein Client die Auswahl anbieten kann |
| `POST /api/v1/enroll` mit `tenant` | der Mandant muss einer davon sein, sonst `403 not_a_member` |
| `POST /api/v1/enroll` ohne `tenant` | der einzige Mandant des Aufrufers; eine Person in mehreren erhält `409 tenant_required`, mit der Liste in der Meldung, statt in ein Netz geleitet zu werden, das sie nicht gewählt hat |
| `POST /api/v1/heartbeat` | abgelehnt mit `403 not_a_member`, sobald die Person nicht mehr dem Mandanten der Sitzung angehört |
| RouteService `Watch` | streamt die Routen des Mandanten, **in den sich das Gerät registriert hat**, ermittelt über den Schlüssel des Geräts, der dem Aufrufer gehören muss |

In den Apps (`pkg/appcore`):

- **`Tenants`** fragt den Server über den Helper, welchen Mandanten die Person
  beitreten darf;
- **`SetTenant`** speichert die Wahl in der Sitzung, und nur einen Mandanten, den der
  Server angeboten hat; eine neue Anmeldung vergisst sie;
- **`Connect`** registriert sich in diesem Mandanten. Eine Person in mehreren, die nicht
  gewählt hat, erhält `ErrTenantRequired`, mit den Mandanten im Status.

Eine Person in nur einem Mandanten wählt nie. Die macOS-App öffnet ihr Fenster, wenn ein
**Connect** aus der Menüleiste mangels Auswahl abgelehnt wird; die Linux- und die
Windows-App zeigen die Auswahl in ihrem Fenster. Die Linux-App lässt keinen Wechsel des
Mandanten zu, solange eine Verbindung besteht.

## Aktualisierungen der Routen {#route-updates}

Das Bearbeiten der Routen eines Mandanten erhöht dessen `serial` und pusht die neue Menge an jedes
Gerät, das diesen Mandanten über den gRPC-RouteService beobachtet. Der Helper ersetzt
die erlaubten IPs des WireGuard-Peers und fügt die entsprechenden Routen hinzu oder entfernt sie,
ohne sich erneut zu registrieren. Das Löschen eines Mandanten beendet seine Beobachtungen.
