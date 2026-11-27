---
title: "Helper con privilegios"
linkTitle: "Helper con privilegios"
weight: 3
description: "El proceso root o SYSTEM de cada aplicación: solo registra el dispositivo en los servidores que nombra su propia configuración, no acepta ninguna configuración de túnel procedente de una solicitud, y escucha en un socket al que solo su grupo puede acceder."
tags: [helper, seguridad, macos, linux, windows]
---

Cada aplicación tiene un **helper con privilegios**: un LaunchDaemon root en macOS, un servicio
systemd en Linux, el servicio **ClaimwardHelper** (LocalSystem) en Windows. Es
el único proceso con privilegios de la aplicación. Los tres son el mismo código,
`pkg/helper` de [claimward-vpn-client](https://github.com/claimward/claimward-vpn-client);
cada aplicación aporta solo un `main` que carga la configuración y escucha.

El helper se encarga de la comunicación con el servidor además del túnel: registra el dispositivo,
levanta el túnel y observa las rutas enviadas. En macOS, la privacidad de "Red local"
impide que una aplicación sin privilegios acceda a un servidor de la LAN, y root está
exento; las demás plataformas siguen el mismo camino para que las tres aplicaciones se comporten
igual.

## El protocolo de socket {#the-socket-protocol}

Una solicitud JSON por conexión, una respuesta JSON (`pkg/hproto`):

| Acción | Lo que hace el helper |
|---|---|
| `connect` | registra el dispositivo en el servidor nombrado en la solicitud, si su configuración lo permite, con el bearer, la clave privada, el nombre del dispositivo y el inquilino indicados; levanta el túnel; observa el RouteService |
| `tenants` | pregunta al servidor a qué inquilinos puede conectarse el bearer |
| `down` | baja el túnel: el del servidor nombrado o, sin servidor, los del llamante (véase [De quién son los túneles](#whose-tunnels)) |
| `status` | por cada túnel del llamante: la interfaz, la dirección, el inquilino y, desde v0.12.0, sus datos en vivo (véase más abajo) |
| `approve` | desde v0.11.0: aprueba el servidor nombrado en la solicitud, si el sistema operativo da su consentimiento (véase [Aprobación de servidores](../../server-approval/)) |
| `revoke` | quita un servidor de los aprobados |
| `approved` | lista los servidores aprobados |

Desde v0.11.0 el helper mantiene **un túnel por servidor**, cada uno en su propia
interfaz, nombrada a partir de la URL del servidor: en Windows el adaptador ya no se llama
`Claimward` sino `Claimward <host> <6 hex>` (un **cambio incompatible** para todo lo que
buscara el adaptador por su nombre antiguo).

## Lo que `status` informa por túnel

Desde v0.12.0, cada túnel de la respuesta lleva, de solo lectura, lo que muestra
un panel de detalle (los campos vacíos se omiten):

| Campo | Significado |
|---|---|
| `interface`, `assigned_ip` | el nombre de la interfaz y la dirección, por separado |
| `endpoint` | el `host:puerto` del par, tal como lo tiene ahora el dispositivo |
| `allowed_ips` | los CIDR enrutados al túnel (siguen un envío de rutas) |
| `dns`, `mtu` | los servidores DNS asignados por el servidor y la MTU de la interfaz |
| `rx_bytes`, `tx_bytes` | bytes que el dispositivo ha recibido del par y le ha enviado desde que el túnel subió |
| `last_handshake` | el último handshake completado (ausente hasta que haya habido uno) |

Los valores en vivo se leen del propio dispositivo WireGuard (la operación `get`
de la UAPI multiplataforma): un endpoint que cambia o una ruta nueva se ven al
instante; si no se puede leer el dispositivo, se informa de los valores de la
inscripción y los contadores se quedan en cero. La respuesta nunca contiene una
clave ni un token. Desde v0.12.1, `status` lista solo los túneles del llamante
(sección siguiente). Las aplicaciones lo consultan una vez por segundo mientras
haya un panel de detalle abierto.

## De quién son los túneles {#whose-tunnels}

Desde v0.12.1, un túnel pertenece al usuario que lo levantó, y `status` (con sus
`last_errors`) solo muestra a un llamante sus propios túneles. En una máquina
compartida, un usuario ya no ve el endpoint, las rutas, la dirección ni los
contadores de otro.

- **El propietario se lee del kernel, nunca de la solicitud.** En `connect`, el
  helper pregunta al sistema operativo quién está al otro extremo de la conexión:
  el uid (`SO_PEERCRED` en Linux, `LOCAL_PEERCRED` en macOS y FreeBSD) o, en
  Windows, el SID de usuario del token del proceso que llama. Ningún campo de una
  solicitud puede nombrar un propietario.
- **root lo ve y lo hace todo**, igual que SYSTEM, un administrador elevado y
  cualquier llamante del socket elevado en Windows.
- **Actuar sobre el túnel de otro se rechaza:** `down` de un servidor nombrado,
  `renew`, `revoke` y un `connect` que lo reemplazaría responden con el
  `error_code` `tunnel_not_owned`. `down` sin servidor baja los túneles del
  llamante. Un `connect` rechazado no pregunta nada al servidor.
- **Un llamante que el sistema no sabe identificar** se rechaza. En Windows, un
  sistema que no responde a la pregunta del proceso par deja al llamante sin
  identificar: solo ve los túneles que crearon llamantes sin identificar, nunca
  los de un usuario identificado.
- **Límite:** un `connect` exclusivo rechazado porque otro túnel ocupa la máquina
  sigue nombrando ese servidor (`blocked_by`), pues la exclusividad es de toda la
  máquina.

El formato en el cable no cambia: no se añadió ningún campo, así que las
aplicaciones construidas para v0.12.0 funcionan tal cual.

## Limitado por su propia configuración {#bounded-by-its-own-configuration}

Cualquier proceso que pueda acceder al socket del helper puede hacerlo actuar, así que lo que
hace está limitado por **su propia** configuración, nunca por la solicitud:

- **Solo registra el dispositivo en un servidor que nombre su configuración, o que se
  aprobó con el consentimiento del sistema.** Un helper que
  tomara el servidor de la solicitud permitiría a cualquier proceso local dirigirlo a un
  servidor propio, que respondiera con rutas para `0.0.0.0/0`: todos los paquetes de
  la máquina, enviados adonde ese proceso eligiera. La aprobación es el aviso del propio
  sistema operativo (Authorization Services en macOS, polkit en Linux, un segundo socket
  elevado en Windows), nunca un campo de la solicitud: véase
  [Aprobación de servidores](../../server-approval/).
- **No acepta ninguna configuración de túnel de una solicitud.** El túnel es lo que ese
  servidor respondió en el registro. Las antiguas acciones `up` y `update-routes`,
  que aceptaban una, ya no existen.
- **Su configuración debe pertenecer a root** (a SYSTEM o a los Administradores en
  Windows) **y nadie más debe poder escribirla**, o el helper no arranca:
  quien la escribe elige en qué servidores se confía.

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "claimward",
  "socket": "/var/run/claimward-helper.sock"
}
```

| Clave | |
|---|---|
| `servers` | opcional desde v0.11.0: los servidores preaprobados por el administrador (comparados sin `/` final); los demás necesitan aprobación |
| `approvals` | opcional: dónde se guardan los servidores aprobados (el valor predeterminado por plataforma está en [Aprobación de servidores](../../server-approval/)) |
| `group` | quién puede usar el socket además de root: `admin` en macOS, `claimward` en Linux, `Claimward Users` en Windows de forma predeterminada |
| `socket` | `/var/run/claimward-helper.sock` de forma predeterminada, `C:\ProgramData\Claimward\helper.sock` en Windows |

| Plataforma | `helper.json` |
|---|---|
| macOS | `/Library/Application Support/Claimward/helper.json` |
| Linux | `/etc/claimward/helper.json` |
| Windows | `C:\ProgramData\Claimward\helper.json` |

## El socket: macOS y Linux {#the-socket-macos-and-linux}

El socket es **`0660`**, propiedad de root y del grupo del helper. Se crea
con una umask restrictiva, de modo que nunca existe con un modo más amplio, en un directorio
en el que solo root puede escribir (el helper rechaza uno en el que otro pudiera escribir, ya que
podría sustituir el socket por el suyo y recibir el bearer de la aplicación). El
socket del helper anterior era `0666`.

## El socket: Windows {#the-socket-windows}

En Windows las mismas reglas son ACL, que el helper establece y vuelve a leer
por sí mismo en lugar de confiar en que un instalador lo haya hecho:

- el directorio del socket, `C:\ProgramData\Claimward`, recibe una DACL **protegida**
  (nada heredado de ProgramData, que permite a cualquier usuario crear archivos
  allí): SYSTEM y Administradores con control total, el grupo del socket autorizado
  a listarlo y recorrerlo y nada más. Se crea ya con esa
  DACL, y se rechaza un directorio que sea una unión (junction) o un enlace;
- el socket recibe su propia DACL: SYSTEM, Administradores, y el grupo autorizado
  a conectarse (lectura/escritura);
- el grupo es el grupo local **`Claimward Users`**, que crea el instalador.
  Si no existe, el socket se abre a **INTERACTIVE**
  (todos los que han iniciado sesión en la máquina, en consola o por Escritorio remoto) y el
  helper registra en el log que lo ha hecho;
- `helper.json` debe ser **propiedad de SYSTEM o de Administradores, y nadie más debe poder
  escribirlo**: el helper lee el propietario y la DACL del archivo y rechaza cualquier
  entrada de permiso que conceda escritura, anexado, eliminación, `WRITE_DAC`, `WRITE_OWNER` o
  escritura/todo genéricos a otro SID, así como una DACL nula.

Las reglas (`pkg/helper/acl.go`) son funciones puras, probadas en todas las plataformas;
el job de CI de Windows las aplica a archivos reales y las vuelve a leer.

La aprobación tiene en Windows un **segundo socket**, `C:\ProgramData\Claimward\approve.sock`
(`helper.ListenElevated`, servido por `Server.ServeElevated`), cuya ACL nombra solo a SYSTEM y
Administradores: un usuario estándar no puede conectarse sin elevación UAC, y solo cuenta un
`approve` que llegó por él. La aplicación lo alcanza con `Client.ElevatedSocketPath` y
`ApproveElevated`.

## Empaquetar la política de polkit (Linux) {#packaging-the-polkit-policy}

El paquete de Linux instala `packaging/polkit/com.claimward.helper.approve-server.policy`
del repositorio del cliente en `/usr/share/polkit-1/actions/`. Sin ella polkit no conoce la
acción y toda aprobación se rechaza.

## Observación de rutas sobre TLS {#route-watches-over-tls}

Una observación de rutas lleva el token bearer, por lo que `pkg/routeclient` la ejecuta sobre
**TLS**, verificado contra las raíces del sistema, salvo hacia una dirección de loopback.
Frente a un servidor cuyo RouteService no usa TLS, el handshake falla antes de que
se envíe el token, y el túnel sigue activo sin actualizaciones de rutas en vivo.

Detener el helper baja el túnel.
