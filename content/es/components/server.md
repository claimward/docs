---
title: "Servidor"
linkTitle: "Servidor"
weight: 1
description: "claimward-vpn-server: verifica el inicio de sesión, asigna direcciones VPN, programa la pasarela WireGuard, transmite las rutas de los inquilinos por gRPC, y sirve una API de administración y métricas."
tags: [servidor, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.2.0** es el plano de control. Verifica el bearer que presenta un dispositivo,
asigna direcciones VPN y programa la pasarela WireGuard con un par por cada
dispositivo registrado. Se ejecuta en el host Linux de la pasarela, junto a un `wg0` existente.

## Lo que sirve {#what-it-serves}

| Listener | Ruta | Función |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | verificar, elegir el inquilino, asignar una dirección, añadir el par, devolver la configuración del túnel |
| | `GET /api/v1/tenants` | los inquilinos a los que puede conectarse quien llama |
| | `POST /api/v1/heartbeat` | renovar la concesión del dispositivo |
| | `POST /api/v1/deregister` | eliminar el par |
| | `GET /healthz` | estado de actividad (liveness) |
| | `GET /metrics` | métricas Prometheus |
| | `/admin/` | API de administración y WebUI, cuando existe la credencial `admin-token` |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | transmite las rutas del inquilino y sus actualizaciones |

Las solicitudes a la API llevan `Authorization: Bearer <token>`: un token de acceso de GitHub,
un ID token OIDC o un token de acceso de go-authn, según `AUTH_PROVIDER`.
Consulte el [protocolo de registro]({{< relref "/reference/protocol.md" >}}) para
los contenidos de las solicitudes.

Con `TLS_CERT` y `TLS_KEY`, ambos listeners usan TLS. Sin ellos, la API HTTP
va en claro (termine TLS en un proxy), y también el RouteService, que los
clientes entonces rechazan salvo en loopback: los dispositivos se conectan, pero no reciben actualizaciones
de rutas en vivo.

## Configuración {#configuration}

Los ajustes están en el entorno. **Los secretos no**: desde v0.6.0 son
archivos de un directorio de credenciales, véase [Credenciales](#credentials) más abajo.

| Variable | Obligatoria | Predeterminado | Notas |
|----------|----------|---------|-------|
| `AUTH_PROVIDER` | | `github` | proveedor de identidad: `github`, `oidc` o `go-authn` |
| `GITHUB_ALLOWED_ORGS` | `github` | — | lista CSV de organizaciones permitidas: se admite a un miembro activo de cualquiera de ellas, y también a un miembro nombrado de un inquilino. Desde v0.5.0 es **opcional solo si al menos un inquilino tiene `members`**: sin ninguno de los dos el servidor se niega a arrancar, sin opción de excepción (antes: obligatoria desde v0.4.0) |
| `GITHUB_API_URL` | | `https://api.github.com` | se define para GitHub Enterprise |
| `OIDC_ISSUER` | `oidc`, `go-authn` | — | URL del emisor (descubrimiento) |
| `OIDC_CLIENT_ID` | `oidc`, `go-authn` | — | la audiencia que deben llevar los tokens |
| `OIDC_ALLOWED_DOMAINS` | | — | lista CSV de dominios de correo permitidos (`oidc`); el correo del token debe estar verificado |
| `GOAUTHN_GATEWAY_CLIENT_ID` | `go-authn` | — | el cliente propio de la pasarela en el proveedor (`wireguard_peers`) |
| `GOAUTHN_PEER_LIST_INTERVAL` | | `30s` | con qué frecuencia se obtiene la lista de claves registradas |
| `GOAUTHN_SSF` | | `false` | consultar también el flujo Shared Signals del proveedor, para que una desactivación se aplique de inmediato; el cliente de la pasarela debe ser allí un receptor SSF |
| `GOAUTHN_SSF_INTERVAL` | | `5s` | con qué frecuencia se consulta el flujo SSF |
| `WG_ENDPOINT` | ✅ | — | `host:port` público de la pasarela, anunciado a los clientes |
| `CREDENTIALS_DIRECTORY` | ✅ | — | el directorio que contiene los archivos secretos, véase [Credenciales](#credentials) |
| `WG_INTERFACE` | | `wg0` | interfaz que se gestiona |
| `WG_DRYRUN` | | `false` | registrar en el log las operaciones sobre pares en lugar de aplicarlas (desarrollo local) |
| `VPN_CIDR` | | `10.80.0.0/24` | conjunto de direcciones IPv4; su primer host es el de la pasarela |
| `PUSH_ROUTES` | | `VPN_CIDR` | rutas CSV del inquilino `default` |
| `TENANTS_FILE` | | — | archivo JSON de inquilinos cargado al arrancar, con su [política de acceso]({{< relref "/tenants.md#access-policy" >}}) |
| `DNS` | | — | servidores DNS CSV del inquilino `default` |
| `KEEPALIVE` | | `25` | keepalive persistente anunciado a los clientes (segundos) |
| `LEASE_TTL` | | `24h` | cuánto dura un registro sin heartbeat |
| `LISTEN_ADDR` | | `:8443` | dirección de escucha HTTP |
| `GRPC_ADDR` | | `:8444` | dirección de escucha del RouteService; los flujos `Watch` se reautorizan cada 15 s y terminan cuando la identidad deja de estar permitida |
| `METRICS_ADDR` | | `127.0.0.1:9090` | escucha separada para `/metrics` (loopback por defecto; ya no se sirve en `LISTEN_ADDR`) |
| `MAX_DEVICES_PER_SUBJECT` | | `5` | dispositivos que una identidad puede inscribir |
| `GRPC_ENDPOINT` | | — | `host:port` del RouteService anunciado a los clientes; si está vacío, no observan |
| `TLS_CERT` / `TLS_KEY` | | — | HTTPS, y TLS en el RouteService |
| `DEBUG` | | — | cualquier valor: log de depuración (una línea por solicitud) |

## Credenciales {#credentials}

Cada secreto es un **archivo** del directorio indicado por
`CREDENTIALS_DIRECTORY`, nunca una variable de entorno: el entorno se copia a
cada proceso hijo y a cada volcado de memoria. systemd define la variable para
`LoadCredential=` y `LoadCredentialEncrypted=`; en las demás plataformas la
define usted. Los nombres de archivo son fijos y se recorta un salto de línea
final.

| Archivo | Obligatorio | Contenido |
|------|----------|---------|
| `wg-private-key` | siempre | la clave privada base64 de la pasarela |
| `admin-token` | no | bearer de la API de administración y de la WebUI; **sin el archivo quedan desactivadas** |
| `goauthn-gateway-secret` | `AUTH_PROVIDER=go-authn` | el secreto del cliente de la pasarela |
| `github-token` | cuando algún inquilino tiene `members` | bearer para `GET /users/{login}` (véase [Inquilinos]({{< relref "/tenants.md" >}})) |

Un archivo obligatorio ausente impide el arranque y se nombra. Antes de leer,
el servidor comprueba cada archivo a través de su descriptor abierto
(`O_NOFOLLOW`, luego `fstat`) y **rechaza** un enlace simbólico, cualquier cosa
que no sea un archivo regular, un archivo legible por grupo u otros, un archivo
que no pertenece al uid del servidor, un archivo vacío y uno de más de 64 KiB.
El error indica cómo corregirlo.

| Plataforma | `CREDENTIALS_DIRECTORY` | Propietario y modo |
|----------|-------------------------|----------------|
| systemd | definido por `LoadCredentialEncrypted=` | el usuario del servicio, `0400`, en un tmpfs privado |
| Docker Swarm | `/run/secrets`, definido a mano | `mode: 0400` en el secreto |
| Docker Compose | `/run/secrets`, definido a mano | los del archivo del host: `chown` y `chmod 0400`, y ajuste `user:` |
| Podman | `/run/secrets`, definido a mano | `--secret ...,mode=0400` (Quadlet: `Secret=...,mode=0400`) |
| Kubernetes | la ruta de montaje del volumen Secret, definida a mano | `defaultMode: 0400`; los archivos son de root, así que el pod se ejecuta con uid 0 y sin ninguna capability salvo `NET_ADMIN` |
| otras | cualquier directorio | `chmod 0400`, propiedad del usuario del servicio |

Hay unidades listas para systemd, Compose, Podman y Kubernetes en el directorio
`deploy/` del repositorio, con los pasos de `systemd-creds encrypt`. Los hosts
sin systemd podrán obtener el mismo directorio de `go-authn/sdcreds`
(`sdcreds s6-run`) cuando se etiquete su primera versión; nada depende aún de
ello.

La comprobación de organización del proveedor `github` no usa `github-token`:
se hace con el token de la *persona*, así que una pertenencia privada solo es
visible si ese token lleva `read:org`. La credencial es opcional mientras solo
se usen organizaciones.

{{< callout type="warning" >}}
**Migración desde v0.5.0** (incompatible). `ADMIN_TOKEN`, `WG_PRIVATE_KEY`,
`WG_PRIVATE_KEY_FILE` y `GOAUTHN_GATEWAY_SECRET_FILE` ya no se leen, y el
servidor se niega a arrancar mientras una de ellas esté definida, indicando el
archivo que hay que crear. Ponga cada valor en su archivo (`admin-token`,
`wg-private-key`, `goauthn-gateway-secret`), elimine la variable y defina
`CREDENTIALS_DIRECTORY`. Un inquilino con `members` necesita ahora también
`github-token`.
{{< /callout >}}

## Proveedores de autenticación {#authentication-providers}

La autenticación es intercambiable detrás de la interfaz `Verifier`
(`internal/auth`):

- **`github`** (predeterminado): el bearer es un token de acceso OAuth de GitHub obtenido con el
  flujo de dispositivo. El servidor lo resuelve mediante la API de GitHub (`/user`,
  `/user/orgs`) y, con `GITHUB_ALLOWED_ORGS`, admite a un miembro activo
  de una de esas organizaciones, o a un miembro nombrado de un inquilino (la lista
  es opcional solo si un inquilino tiene `members`). No interviene ningún client secret.
- **`oidc`**: el bearer es un ID token OIDC, verificado contra el emisor con
  la audiencia `OIDC_CLIENT_ID` y la lista opcional de dominios de correo permitidos.
- **`go-authn`**: el bearer es un token de acceso (`at+jwt`) de un proveedor
  [go-authn/bridge](https://github.com/go-authn/bridge), y la
  clave del dispositivo debe haber sido registrada allí por la misma persona. El servidor lee
  la lista firmada de claves registradas del proveedor
  ([go-authn/wireguard](https://github.com/go-authn/wireguard)) y retira de
  `wg0` una clave que el proveedor revoca.

Consulte [Proveedores de identidad]({{< relref "/identity-providers.md" >}}) para cada
flujo de principio a fin.

## Reglas de registro {#enrollment-rules}

- **Una clave pertenece a quien la registró.** Se rechaza registrar una clave que posee
  otra identidad (`409 key_taken`): una clave pública es pública, y apropiarse de una
  daría el poder de dar de baja el dispositivo de su propietario.
- La misma clave registrada de nuevo por su propietario conserva su dirección y obtiene una nueva
  concesión.
- La única IP permitida del par es la `/32` del dispositivo, de modo que los dispositivos no pueden usar
  las direcciones de otros.
- El inquilino es el que pidió quien llama, si es miembro, o su
  único inquilino. Consulte [Inquilinos]({{< relref "/tenants.md" >}}).

## Cómo programa la pasarela {#how-it-programs-the-gateway}

El servidor usa [`wgctrl`](https://pkg.go.dev/golang.zx2c4.com/wireguard/wgctrl)
para añadir y eliminar pares en una interfaz existente, y comprueba al arrancar que
la interfaz existe. La propia interfaz (su clave privada y su puerto de escucha)
se deja a `wg-quick` o a systemd-networkd en el arranque, lo que mantiene la configuración
de la interfaz con privilegios fuera del servicio de larga duración.

## Ejecución en local {#run-locally}

Con `WG_DRYRUN=true` no se toca ningún dispositivo WireGuard:

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

`task run:dev` hace lo mismo con inicio de sesión de GitHub y una clave efímera, y
`task dex` ejecuta un [Dex](https://dexidp.io/) local contra el que iniciar sesión
(`deploy/dev/`).

{{< callout type="warning" >}}
**Ejecútelo detrás de TLS.** Los tokens bearer son credenciales: sirva siempre la API por
HTTPS, ya sea con `TLS_CERT`/`TLS_KEY` o detrás de un proxy que termine TLS, y
dé al RouteService un certificado para que los dispositivos reciban actualizaciones de rutas en vivo.
{{< /callout >}}
