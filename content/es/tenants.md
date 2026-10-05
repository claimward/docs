---
title: "Inquilinos"
weight: 40
description: "Las rutas están asociadas a inquilinos. Una persona puede pertenecer a varios y elige uno por sesión; el dispositivo se conecta a ese."
tags: [inquilinos, servidor, grpc]
---

Un **inquilino** es un conjunto de rutas (`allowed_ips`) y de servidores DNS, junto con las reglas
que indican quién pertenece a él. Una persona puede pertenecer a varios inquilinos: elige
uno por sesión, y el dispositivo se conecta a ese.

## Pertenencia {#membership}

Una persona pertenece a todo inquilino que nombre cualquiera de estos elementos:

| Campo | Se compara con |
|---|---|
| `domains` | el dominio de una dirección de correo **verificada** (una no verificada es una cadena que la persona escribió) |
| `groups` | la claim `groups` del token (OIDC; go-authn: entitlements eduPerson), o las organizaciones de GitHub de la persona |
| `idps` | la institución que respondió por ella: el `idp` de go-authn, un entity ID SAML |

Una persona que no coincide con ninguno pertenece al inquilino `default`, y solo en ese caso.

## De dónde vienen los inquilinos {#where-tenants-come-from}

El servidor arranca con un solo inquilino, `default`, cuyas rutas son `PUSH_ROUTES`
(por defecto `VPN_CIDR`) y cuyos servidores DNS son `DNS`. Los demás inquilinos se
crean, modifican y eliminan mediante la [API de administración y la WebUI]({{< relref "/operations.md#admin-api-and-webui" >}}),
que modifican las tres listas de pertenencia junto a las rutas. El inquilino por defecto
no se puede eliminar.

{{< callout type="warning" >}}
Los inquilinos se guardan **en memoria** (v0.2.0): un reinicio del servidor solo deja
el inquilino `default`, reconstruido a partir del entorno.
{{< /callout >}}

## Elegir uno por sesión {#choosing-one-per-session}

| Petición | Lo que hace el servidor |
|---|---|
| `GET /api/v1/tenants` | enumera los inquilinos a los que puede conectarse quien llama, `[{"id", "name"}]`, para que un cliente ofrezca la elección |
| `POST /api/v1/enroll` con `tenant` | el inquilino debe ser uno de ellos; si no, `403 not_a_member` |
| `POST /api/v1/enroll` sin `tenant` | el único inquilino de quien llama; una persona que está en varios recibe `409 tenant_required`, con la lista en el mensaje, en lugar de ser enrutada a una red que no eligió |
| `POST /api/v1/heartbeat` | rechazado con `403 not_a_member` en cuanto la persona deja de estar en el inquilino de la sesión |
| RouteService `Watch` | transmite las rutas del inquilino **en el que se registró el dispositivo**, que se encuentra por la clave del dispositivo, la cual debe ser la de quien llama |

En las aplicaciones (`pkg/appcore`):

- **`Tenants`** pregunta al servidor, a través del helper, a qué inquilinos puede
  unirse la persona;
- **`SetTenant`** registra la elección en la sesión, y solo un inquilino que el
  servidor haya ofrecido; un nuevo inicio de sesión la olvida;
- **`Connect`** registra el dispositivo en ese inquilino. Una persona que está en varios y no ha
  elegido recibe `ErrTenantRequired`, con los inquilinos en el estado.

Una persona que está en un solo inquilino nunca elige. La aplicación macOS abre su ventana cuando un
**Connect** desde la barra de menús se rechaza por falta de elección; las aplicaciones Linux y
Windows muestran la elección en su ventana. La aplicación Linux no permite cambiar de
inquilino mientras está conectada.

## Actualizaciones de rutas {#route-updates}

Modificar las rutas de un inquilino incrementa su `serial` y envía el nuevo conjunto a todos los
dispositivos que vigilan ese inquilino a través del RouteService gRPC. El helper reemplaza
las IP permitidas del par WireGuard y añade o elimina las rutas correspondientes,
sin volver a registrarse. Eliminar un inquilino pone fin a sus observaciones.
