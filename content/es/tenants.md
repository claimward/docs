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
| `members` | **logins** de GitHub, nombrados uno a uno y fijados al identificador numérico de la cuenta (más abajo) |

{{< callout type="warning" >}}
**Una persona que no coincide con ningún inquilino es rechazada** (v0.5.0,
cambio incompatible): `403 not_a_member` en `/api/v1/tenants` y
`/api/v1/enroll`, y el `Watch` gRPC es rechazado. Ya no hay inquilino de
reserva: el inquilino `default` solo recibe a quienes nombran sus propios
`domains`, `groups`, `idps` o `members`. Un ID de inquilino desconocido es un
error, nunca las rutas del inquilino `default`.
{{< /callout >}}

**Migración desde v0.4.x.** Quienes antes caían en `default` ahora deben ser
nombrados por él: dé a la entrada `default` de `TENANTS_FILE` los `domains`,
`groups`, `idps` o `members` que los nombran y reinicie. El inquilino `default`
creado solo con `PUSH_ROUTES` y `DNS` no nombra a nadie.

### Miembros nombrados {#members}

`members` lista logins de GitHub, legibles pero renombrables: un login puede
liberarse y ser registrado por otra persona. El servidor **fija** por tanto cada
login al identificador numérico de la cuenta. Al cargar un inquilino
(`TENANTS_FILE`) o al crearlo o actualizarlo mediante la API de administración,
llama a `GET {GITHUB_API_URL}/users/{login}` (10 s de tiempo límite, respuesta
limitada a 64 KiB, la cuenta debe ser un `User`) y guarda el par en el campo
`pinned`, de solo lectura. Una persona es miembro cuando el sujeto de su token es
`github:<id>` para un ID fijado: una cuenta renombrada cuyo antiguo login
pertenece ahora a otra persona es rechazada. Un **login no resoluble es un
error**: el servidor se niega a arrancar y la API de administración responde
`400`. La API y la WebUI muestran los logins; para seguir un cambio de nombre,
edite de nuevo el inquilino. La resolución se autentica con la credencial `github-token` (un archivo en
`CREDENTIALS_DIRECTORY`, enviado como bearer: 5000 solicitudes por hora en
github.com). Un inquilino con `members` y sin `github-token` impide el arranque;
el token nunca se envía por HTTP sin cifrar, salvo a una dirección loopback.

Un miembro nombrado también es admitido por la puerta de entrada de GitHub sin
pertenecer a una organización permitida (véase los [proveedores de identidad]({{< relref "/identity-providers.md" >}})).

## De dónde vienen los inquilinos {#where-tenants-come-from}

El servidor arranca con un solo inquilino, `default`, cuyas rutas son `PUSH_ROUTES`
(por defecto `VPN_CIDR`) y cuyos servidores DNS son `DNS`. Los demás inquilinos se
crean, modifican y eliminan mediante la [API de administración y la WebUI]({{< relref "/operations.md#admin-api-and-webui" >}}),
que modifican las cuatro listas de pertenencia junto a las rutas. El inquilino por defecto
no se puede eliminar.

{{< callout type="warning" >}}
Los inquilinos se guardan **en memoria** (v0.2.0): un reinicio del servidor solo deja
el inquilino `default`, reconstruido a partir del entorno.
{{< /callout >}}

## Política de acceso {#access-policy}

Las rutas de un inquilino no solo se anuncian: la pasarela las **aplica**. Un
inquilino puede llevar una `policy`, una lista de reglas que dicen qué destino
puede alcanzar un par, con qué protocolo y qué puertos:

```json
[{"id": "default", "policy": [
  {"cidr": "10.20.0.5/32", "proto": "tcp", "ports": [445, 88]},
  {"cidr": "10.20.0.5/32", "proto": "udp", "ports": [88]}
]}]
```

- `proto` es `tcp` o `udp`; `ports` son números o rangos (`"9000-9010"`) y son
  obligatorios. Solo IPv4.
- Los `allowed_ips` enviados a los clientes se **derivan de la política** (los
  CIDR distintos): lo que un dispositivo enruta y lo que la pasarela deja pasar
  no pueden divergir. El formato de las rutas no cambia.
- La pasarela posee una tabla nftables, `inet claimward`, instalada por netlink
  (Linux, `CAP_NET_ADMIN`), o en OpenBSD el ancla pf `claimward` cargada por
  `/dev/pf` (véase [OpenBSD]({{< relref "/components/server.md#openbsd" >}})).
  Ambas se reemplazan atómicamente al arrancar y en cada
  cambio de par o de inquilino. El tráfico que llega de la interfaz WireGuard se
  **deniega por defecto**, tanto en la cadena de reenvío como en la de entrada
  (el servidor de archivos puede ser el propio host de la pasarela); la
  dirección de cada par se confronta con las reglas de su inquilino. El DNS debe
  nombrarse en la política como todo lo demás.
- **Cierre ante el fallo**: si el conjunto de reglas no puede instalarse, el
  servidor no arranca, y se rechaza un registro cuyo conjunto de reglas no puede
  instalarse (`500 gateway_error`).
- Un inquilino con `allowed_ips` y sin `policy` se aplica como cualquier
  protocolo, cualquier puerto, hacia esos CIDR.

Los inquilinos con política se cargan al arrancar desde el archivo JSON que
nombra `TENANTS_FILE` (un arreglo de inquilinos con los campos de la API de
administración); la API de administración también acepta `policy`. La interfaz
web de administración aún no la edita.

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
