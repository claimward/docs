---
title: "Arquitectura"
weight: 20
description: "Un plano de control que verifica el inicio de sesión y programa la pasarela, un plano de datos que es WireGuard sin más, y un helper con privilegios en cada dispositivo entre ambos."
tags: [wireguard, servidor, helper, grpc]
---

Claimward separa un **plano de control**, el servidor, del **plano de datos**,
el túnel WireGuard entre un dispositivo y la pasarela. La autenticación se
delega en su proveedor de identidad: Claimward nunca ve una contraseña.

En un dispositivo, una **aplicación** sin privilegios hace iniciar sesión a la persona y conserva la
sesión; un **helper con privilegios** (root, o SYSTEM en Windows) se registra en el
servidor y es dueño del túnel. La aplicación nunca habla con el servidor por sí misma.

## Flujo de registro de extremo a extremo {#end-to-end-enrollment-flow}

```text
 ┌──────────┐ 1. sign-in: GitHub device flow, OIDC code + PKCE,  ┌──────────┐
 │   app    │    or go-authn device flow (+ key registration)    │   IdP    │
 │ (as you) │◀─────────────────── bearer token ──────────────────│          │
 └────┬─────┘                                                    └──────────┘
      │ 2. socket: connect {server_url, bearer, private key, tenant}
      ▼
 ┌──────────┐ 3. POST /api/v1/enroll                ┌─────────────────────────┐
 │  helper  │    Authorization: Bearer <token>      │  claimward-vpn-server   │
 │ (root)   │    {public_key, device, tenant}  ───▶ │  verify the bearer      │
 │          │                                       │  choose the tenant      │
 │          │ ◀─── 4. {assigned_ip,                 │  allocate an address    │
 │          │       server_public_key, endpoint,    │  wgctrl: add the peer   │
 │          │       allowed_ips, dns,               │  (AllowedIPs = ip/32)   │
 │          │       grpc_endpoint, keepalive,       └───────────┬─────────────┘
 │          │       lease_expires_at}                           │ RouteService
 │          │ ◀═════════════ 6. gRPC Watch (TLS) ═══════════════╛ (live routes)
 │          │
 │          │ 5. wireguard-go: utunN / Wintun "Claimward", address, routes
 └────┬─────┘
      ╚═══════════════════ WireGuard tunnel ════════════════════▶ private network
```

1. La aplicación hace iniciar sesión a la persona con el proveedor configurado: **GitHub** por
   defecto (flujo de dispositivo OAuth), cualquier emisor **OpenID Connect** (código de
   autorización con PKCE, en el navegador) o un proveedor **go-authn** (flujo de dispositivo).
   El bearer que obtiene es un token de acceso de GitHub, un ID token OIDC o un token
   de acceso go-authn. Con go-authn, la clave **pública** del dispositivo se
   registra primero en el proveedor, y el bearer es el token que devuelve ese
   registro.
2. La aplicación genera el par de claves WireGuard del dispositivo en el primer inicio de sesión y
   lo conserva en su archivo de sesión hasta que la persona cierra la sesión, de modo que el dispositivo
   conserva su clave pública entre conexiones (y su dirección mientras está registrado). Para conectarse, entrega al helper la URL del servidor, el bearer, la
   clave privada y el inquilino elegido para la sesión, a través del socket del helper.
3. El helper comprueba que el servidor es **uno de los que nombra su propia configuración**,
   y luego llama a `POST /api/v1/enroll` con la clave pública del dispositivo y el
   bearer.
4. El servidor **verifica** el bearer (una llamada a la API de GitHub, un ID token OIDC o
   un token de acceso go-authn cuyo sujeto debe poseer la clave), aplica cualquier
   lista de organizaciones o de dominios de correo permitidos, elige el **inquilino**, **asigna** una
   dirección VPN y **programa la pasarela** (`wgctrl`) con un par cuya única
   IP permitida es ese `/32`. Responde con los parámetros del túnel: la dirección,
   su propia clave pública, el endpoint, las rutas y servidores DNS del inquilino, el
   keepalive, el endpoint del RouteService y el fin de la concesión.
5. El helper levanta un túnel en espacio de usuario con `wireguard-go`, asigna a la
   interfaz su dirección e instala las rutas.
6. Cuando el servidor anuncia un RouteService (`GRPC_ENDPOINT`), el helper
   lo vigila por gRPC: los cambios de rutas hechos en el inquilino llegan al dispositivo
   sin volver a registrarse.

## Concesiones {#leases}

Cada registro lleva una **concesión** de `LEASE_TTL` (24 horas por defecto). Un
proceso de limpieza en segundo plano en el servidor elimina, cada minuto, los pares cuya concesión
ha terminado, de modo que un dispositivo perdido o revocado sale de la pasarela por sí solo. Con
go-authn, una concesión nunca sobrevive al registro de la clave en el proveedor.

El servidor renueva una concesión con `POST /api/v1/heartbeat`, y elimina un par de
inmediato con `POST /api/v1/deregister`.

A partir de **claimward-vpn-client v0.3.1**, es decir, desde las versiones de las aplicaciones que lo
incluyen (las aplicaciones macOS, Linux y Windows a partir de v0.2.0), el helper mantiene él mismo la concesión mientras
el túnel está activo. Renueva a la mitad de lo que le queda a la concesión, nunca antes
de 30 segundos ni después de 10 minutos, y actúa según la respuesta:

| El servidor responde | El helper |
|---|---|
| una concesión renovada | vuelve a renovar a la mitad de ella |
| `404 not_enrolled`: olvidó el dispositivo (la concesión caducó, o el servidor se reinició) | vuelve a registrarse con la misma clave y el mismo inquilino, y levanta el túnel a partir de esa respuesta; si eso también falla, desactiva el túnel |
| `403` (`not_a_member`, `key_not_registered`): acceso retirado | desactiva el túnel e informa del motivo (`last_error`) |
| `401`, un `5xx`, o nada | reintenta en menos de un minuto, antes de que termine la concesión |

El helper renueva con el último bearer que recibió. Eso basta para un
token de GitHub, no para un token de acceso go-authn, que caduca en minutos y
que solo la aplicación puede refrescar. Por eso, mientras la aplicación se ejecuta, `pkg/appcore` entrega al
helper un bearer nuevo (la acción `renew` del helper) al 40 % de lo que le queda a la concesión
(con un máximo de 8 minutos de intervalo), antes de que toque la renovación propia del helper. Una aplicación reiniciada con un
túnel en marcha empieza a hacerlo en su primera consulta de estado.

*Disconnect* (el `down` del helper) **da de baja** el par, devolviendo su
dirección de inmediato. Un helper que se está deteniendo (su gestor de servicios lo
detiene, o la máquina se apaga) desactiva el túnel sin darse de baja,
de modo que un helper reiniciado encuentra la concesión todavía ahí, y la concesión
de una máquina detenida caduca en el servidor.

{{< callout type="info" >}}
Las aplicaciones v0.1.0 están compiladas sobre versiones anteriores del cliente, que no hacen nada de esto:
solo renuevan una concesión volviendo a conectarse, y dejan el par en la pasarela
después de *Disconnect* hasta que termina su concesión.
{{< /callout >}}

## Fronteras de confianza {#trust-boundaries}

- El **servidor** es el único componente que habla con el proveedor de identidad para
  verificar un inicio de sesión, y el único con derechos para cambiar los pares de la pasarela.
- En el dispositivo, el **helper** es el único proceso con privilegios. Cualquier cosa que
  pueda alcanzar su socket puede pedirle que actúe, por eso actúa dentro de su propia
  configuración: solo se registra en los servidores que nombra esa configuración y
  no acepta ninguna configuración de túnel procedente de una petición. Véase
  [Helper con privilegios]({{< relref "/components/helper.md" >}}).
- La **aplicación** se ejecuta como la persona. Guarda la sesión (token bearer y clave
  del dispositivo) en un archivo `0600` de su directorio de configuración.
- Una observación de rutas lleva el token bearer, por eso pasa por **TLS** salvo hacia una
  dirección de loopback.
- El contrato de comunicación está en un solo lugar,
  [`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
  y `pkg/routespb`, importados tanto por los clientes como por el servidor.
