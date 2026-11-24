---
title: "Servidor"
linkTitle: "Servidor"
weight: 1
description: "claimward-vpn-server: verifica el inicio de sesión, asigna direcciones VPN, programa la pasarela WireGuard, transmite las rutas de los inquilinos por gRPC, y sirve una API de administración y métricas."
tags: [servidor, wireguard, grpc, github, oidc, go-authn]
---

[`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server)
**v0.10.0** es el plano de control. Verifica el bearer que presenta un dispositivo,
asigna direcciones VPN y programa la pasarela WireGuard con un par por cada
dispositivo registrado. Se ejecuta en el host de la pasarela, junto a un `wg0` existente: Linux
(nftables) o, desde la v0.10.0, OpenBSD (pf, véase [OpenBSD](#openbsd)).

## Lo que sirve {#what-it-serves}

| Listener | Ruta | Función |
|---|---|---|
| `LISTEN_ADDR` (`:8443`) | `POST /api/v1/enroll` | verificar, elegir el inquilino, asignar una dirección, añadir el par, devolver la configuración del túnel |
| | `GET /api/v1/tenants` | los inquilinos a los que puede conectarse quien llama |
| | `POST /api/v1/heartbeat` | renovar la concesión del dispositivo |
| | `POST /api/v1/deregister` | eliminar el par |
| | `GET /healthz` | estado de actividad (liveness) |
| | `/admin/` | API de administración y WebUI, cuando existe la credencial `admin-token` |
| `GRPC_ADDR` (`:8444`) | `claimward.routes.v1.RouteService/Watch` | transmite las rutas del inquilino y sus actualizaciones |
| `METRICS_ADDR` (sin valor por defecto: desactivado si no se define) | `GET /metrics` | métricas Prometheus, en un listener propio, nunca en `LISTEN_ADDR` |

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
| `TUNNEL_MTU` | | derivado | MTU de la interfaz WireGuard, de 1280 a 9000, anunciada como `mtu`; cualquier otro valor impide el arranque. Sin definir: MTU del enlace de salida menos 80, como máximo 1420, como mínimo 1280. La misma tabla atómica `inet claimward` también reduce el MSS de cada SYN TCP que cruza la interfaz (reenviado en ambos sentidos, y entrada para la propia pasarela) a esta MTU menos 40 (IPv4) o 60 (IPv6) |
| `LISTEN_ADDR` | | `:8443` | dirección de escucha HTTP |
| `GRPC_ADDR` | | `:8444` | dirección de escucha del RouteService; los flujos `Watch` se reautorizan cada 15 s y terminan cuando la identidad deja de estar permitida |
| `METRICS_ADDR` | | — (desactivado) | escucha separada para `/metrics`, servida **solo si se define** (desde la v0.9.0 no hay puerto por defecto: el antiguo `127.0.0.1:9090` chocaba con Prometheus); nunca en `LISTEN_ADDR`. Nombra cada tenant: manténgala en loopback o en una red privada |
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
Una excepción desde la v0.7.1: se acepta un archivo del uid 0 con modo exactamente
`0440` si su grupo es el gid del servidor o uno de sus grupos suplementarios (lo
que produce un volumen Secret de Kubernetes con `fsGroup`). Otra desde la v0.9.0,
para systemd con `DynamicUser=yes`: systemd deja el archivo `root:root`, modo
`0400`, más una entrada de ACL POSIX de solo lectura para el uid del servicio
(`src/core/exec-credential.c:338-361`, `src/shared/acl-util.c:448-494`), así que
`stat` muestra `0440`. El servidor lee `system.posix_acl_access` del descriptor
abierto y acepta exactamente `user::` (sin escritura ni ejecución), `user:<su uid>:r--`, `group::---`,
`mask::r--`, `other::---`; cualquier otro usuario o grupo con nombre, cualquier
bit de escritura o ejecución, o un valor mal formado o demasiado grande se
rechaza. El error indica cómo corregirlo.

| Plataforma | `CREDENTIALS_DIRECTORY` | Propietario y modo |
|----------|-------------------------|----------------|
| systemd | definido por `LoadCredentialEncrypted=` | con `DynamicUser=yes` (como se entrega): propiedad de root con una ACL de solo lectura para el uid del servicio, aceptada; con un `User=` fijo en un sistema de archivos sin ACL: el usuario del servicio, `0400`. tmpfs privado |
| Docker Swarm | `/run/secrets`, definido a mano | `mode: 0400` en el secreto |
| Docker Compose | `/run/secrets`, definido a mano | los del archivo del host: `chown` y `chmod 0400`, y ajuste `user:` |
| Podman | `/run/secrets`, definido a mano | `--secret ...,mode=0400` (Quadlet: `Secret=...,mode=0400`) |
| Kubernetes | la ruta de montaje del volumen Secret, definida a mano | `defaultMode: 0440` y `fsGroup`: los archivos son `root:<fsGroup>`, aceptados por la regla de grupo anterior, así que el pod se ejecuta con un uid no root y sin ninguna capability salvo `NET_ADMIN`. `add: [NET_ADMIN]` solo no da la capability a un uid no root (sin conjunto ambiente): el binario de la imagen necesita `setcap cap_net_admin=+ep` (según capabilities(7), no medido en un clúster) |
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

## OpenBSD (pf) {#openbsd}

Desde la v0.10.0 el servidor también funciona en OpenBSD, donde aplica la
política de acceso con pf en lugar de nftables. Habla directamente con el núcleo
mediante los ioctls de `/dev/pf`; nunca ejecuta `pfctl`, y no hay alternativa
con `pfctl`.

- **Versiones admitidas: OpenBSD 7.9 y 8.0.** Comparten la misma disposición de
  `struct pf_rule`, que el servidor comprueba contra la versión en ejecución. En
  cualquier otra versión el servidor se niega a arrancar antes que arriesgarse a
  codificar mal una regla.
- **`pf.conf` es suyo.** El servidor nunca modifica el conjunto de reglas
  principal. Añada una línea a `/etc/pf.conf` y mantenga `pf` activado:

  ```text
  anchor "claimward"
  ```

  El servidor carga la política en esa ancla. Al arrancar relee el conjunto de
  reglas principal y comprueba que llama a `anchor "claimward"`.
- **Se niega a arrancar** cuando `/dev/pf` no puede abrirse en lectura y
  escritura (debe arrancar como root), cuando pf está desactivado, cuando el
  conjunto de reglas principal no llama a la ancla (la política se cargaría sin
  filtrar nada) y cuando `pf.conf` tiene `set skip on` para la interfaz
  WireGuard (`wg0`, `wg*`), porque entonces pf nunca vería el tráfico de los
  pares.
- **La misma política que en Linux.** Denegación por defecto del tráfico que
  llega por `WG_INTERFACE`; solo se permite IPv4, y el IPv6 a través del túnel
  se descarta. El ajuste del MSS (`TUNNEL_MTU`) cubre ambas familias, como una
  regla `match ... scrub (max-mss N)`.
- **Atómico y cerrado por defecto.** La ancla y sus tablas se sustituyen en una
  sola transacción de pf, y después se releen y se comparan con lo que se quería
  cargar. Si eso falla, se carga una denegación total. La ancla permanece al
  salir el proceso. Los nombres de tabla llevan un sufijo de generación por
  carga, de modo que la breve ventana entre la confirmación de las tablas y la
  de las reglas nunca puede aplicar las reglas de un tenant a los pares de otro.
- **Sin `pledge(2)`.** La promesa `pf` solo permite doce de los ioctls `DIOC*`
  (`sys/kern/kern_pledge.c`, `pledge_ioctl`), y el servidor necesita además
  `DIOCRINADEFINE`, `DIOCXROLLBACK`, `DIOCGETRULES`, `DIOCGETRULE`, `DIOCXEND` y
  `DIOCRGETADDRS`. Cualquier otro ioctl mataría el proceso, y un pledge no puede
  ampliarse después. Ejecútelo como servicio dedicado bajo `rcctl` y mantenga
  el resto del equipo bloqueado.

### Despliegue en OpenBSD (rc.d) {#openbsd-deploy}

Desde la v0.10.1 el repositorio incluye `deploy/openbsd/`: un script `rc.d(8)`,
un `environment.example`, un `hostname.wg0.example` y un `pf.conf.example`.

- **Se ejecuta como root.** La configuración de los pares WireGuard de `wg(4)`
  está tras `suser(9)` (`sys/net/if_wg.c`), y `/dev/pf` solo está protegido por
  su nodo de dispositivo, reservado a root: `pfopen` (`sys/net/pf_ioctl.c`) no
  comprueba nada más. OpenBSD no tiene un grupo privilegiado que permita a un
  usuario `_claimward` hacer ninguna de las dos cosas, así que el script fija
  `daemon_user="root"`.
- **Los secretos son archivos** en `/etc/claimward/credentials`, un directorio
  `0700` propiedad de root, con cada archivo `0400` y propiedad de root
  (`install(1)`). El script fija `CREDENTIALS_DIRECTORY` a ese directorio;
  ningún secreto va en el entorno, en los argumentos ni en una URL. Los ajustes
  no secretos están en `/etc/claimward/environment`.
- **`wg0` debe existir** antes de que arranque el servidor: `hostname.wg0` lleva
  la misma clave privada que el secreto `wg-private-key` (modo `0640`).

```sh
install -m 0555 claimward-server /usr/local/bin/claimward-server
install -d -m 0755 /etc/claimward
install -d -m 0700 /etc/claimward/credentials
install -m 0400 wg-private-key /etc/claimward/credentials/wg-private-key
install -m 0600 environment.example /etc/claimward/environment   # luego editar
install -m 0640 hostname.wg0.example /etc/hostname.wg0           # luego editar
sh /etc/netstart wg0
install -m 0555 claimward_server /etc/rc.d/claimward_server
rcctl enable claimward_server
rcctl start claimward_server && rcctl check claimward_server
```

El registro va a syslog (`/var/log/daemon`). La CI ejecuta este script en
máquinas virtuales OpenBSD 7.9 y 8.0 reales: `rcctl start`, la línea de
arranque, `rcctl check` y `rcctl stop`, y después un arranque sin el ancla en
`pf.conf`, que debe fallar.

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
