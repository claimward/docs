---
title: "Operación"
weight: 70
description: "Ejecutar Claimward en producción: TLS, la pasarela, las concesiones, lo que un reinicio olvida, el proveedor de identidad, la API de administración y las métricas."
tags: [servidor, operación, wireguard, grpc]
---

## TLS

El servidor habla HTTP sin cifrar salvo que se establezcan `TLS_CERT`/`TLS_KEY`. Los tokens bearer
son credenciales, así que coloque **siempre** la API detrás de TLS, directamente o a través de un
proxy inverso (nginx, Caddy, un balanceador de carga).

El mismo certificado sirve el RouteService gRPC. Una observación de rutas lleva el
token bearer, y los clientes rechazan una observación sin cifrar salvo en loopback: un
servidor sin `TLS_CERT`/`TLS_KEY` (por ejemplo detrás de un proxy que solo
termina HTTPS) registra dispositivos, pero estos no reciben actualizaciones de rutas en directo, y
registra una advertencia en el log al arrancar. Establezca `GRPC_ENDPOINT` en el `host:port` en el que los dispositivos
alcanzan el RouteService, con un nombre que cubra el certificado.

## Pasarela {#gateway}

- Levante `wg0` con `wg-quick` o systemd-networkd al arrancar; Claimward solo
  gestiona sus pares. Ejecute el servidor con los permisos para configurar la interfaz
  (root, o `CAP_NET_ADMIN`).
- Active `net.ipv4.ip_forward`, y reglas de NAT o de cortafuegos, si los clientes enrutan
  más allá de la subred de la VPN.
- `GET /healthz` es la sonda de actividad (liveness).

## Concesiones {#leases}

`LEASE_TTL` (24 horas por defecto) equilibra seguridad y rotación. El recolector
elimina los pares caducados cada minuto, de modo que los dispositivos revocados o desconectados desaparecen
por sí solos. Para revocar uno de inmediato, anule el registro de su par, o elimínelo con
`wg set wg0 peer <key> remove`.

A partir de claimward-vpn-client v0.3.1 (las aplicaciones a partir de v0.2.0), el helper renueva
la concesión mientras el túnel está activo, a la mitad del tiempo restante (entre 30 segundos
y 10 minutos), y se da de baja al hacer *Disconnect*. Un `LEASE_TTL` más corto, por tanto,
cuesta más heartbeats, no túneles cortados: la retirada de un inquilino, o una clave
que el proveedor go-authn retira, termina el túnel en la siguiente renovación (el
servidor responde `403`). Un servidor que ha olvidado un dispositivo (`404`) hace que
se registre de nuevo. Consulte [Concesiones]({{< relref "/architecture.md#leases" >}}).

Las aplicaciones v0.1.0 solo renuevan volviendo a conectarse, y dejan el par hasta que su
concesión termina tras *Disconnect*: con ellas, un dispositivo que permanece conectado más
de `LEASE_TTL` pierde su túnel cuando su par es recolectado.

## Estado {#state}

El servidor mantiene los pares registrados, el conjunto de direcciones y los inquilinos
**en memoria**. Un reinicio los olvida:

- los inquilinos vuelven a ser solo `default`, a partir de `PUSH_ROUTES` y `DNS`;
- a partir del servidor **v0.2.0**, los pares que una ejecución anterior dejó en `wg0` se
  **eliminan al arrancar**: todo par cuya única IP permitida sea un `/32` dentro de
  `VPN_CIDR`, la forma que el servidor da a cada par. Cualquier otro par
  (configurado a mano, un enlace site-to-site) se deja intacto. Si se conservaran, esos pares
  no serían de nadie: nunca recolectados, nunca comprobados contra la lista del proveedor,
  de modo que una persona desactivada antes del reinicio conservaría un túnel operativo. Los dispositivos
  se descubren desconocidos en su siguiente renovación de la concesión y se registran de nuevo (aplicaciones
  basadas en claimward-vpn-client v0.3.1); hasta entonces su túnel no transporta
  nada. El helper renueva como máximo cada 10 minutos, así que tras un reinicio un
  dispositivo puede quedar cortado hasta 10 minutos. Volver a conectarse lo restablece
  de inmediato.
- el servidor **v0.1.0** deja esos pares en `wg0`: nunca los recolecta, y
  puede asignar sus direcciones a dispositivos nuevos (WireGuard enruta entonces la
  dirección al nuevo par). Tras reiniciarlo, vacíe los pares
  (`wg-quick down wg0 && wg-quick up wg0`, o `wg set … remove`) y haga que los
  dispositivos se conecten de nuevo.

Para varias pasarelas o un registro de auditoría duradero, los paquetes `store`, `ipam` y
`tenant` necesitan una base de datos detrás.

## Proveedor de identidad {#identity-provider}

Por defecto, Claimward hace iniciar sesión a las personas con **GitHub** (device flow): cree una
OAuth App de GitHub con **Device Flow** activado y restrinja el acceso con
`GITHUB_ALLOWED_ORGS`. Para **OIDC**, establezca `AUTH_PROVIDER=oidc` con un
cliente PKCE nativo/público, y restrinja con `OIDC_ALLOWED_DOMAINS`. Para
**go-authn**, establezca `AUTH_PROVIDER=go-authn` con el cliente propio de la pasarela: el
proveedor decide entonces qué claves pueden conectarse, y una pasarela que no puede obtener
su lista no admite a nadie nuevo. Consulte
[Proveedores de identidad]({{< relref "/identity-providers.md" >}}).

## API de administración y WebUI {#admin-api-and-webui}

Con `ADMIN_TOKEN` establecido, el servidor sirve una WebUI Svelte integrada en
`/admin/` y una API bajo `/admin/api/`, protegidas por
`Authorization: Bearer <ADMIN_TOKEN>` (comparado en tiempo constante). Sin él,
`/admin/` responde `503`. Los archivos de la WebUI se sirven sin autenticación;
esta pide el token y lo envía con cada llamada.

| Método y ruta | |
|---|---|
| `GET /admin/api/overview` | recuentos `{"tenants", "peers", "watchers"}` |
| `GET /admin/api/tenants` | todos los inquilinos |
| `POST /admin/api/tenants` | crea uno: `id` (o un slug de `name`), `name`, `domains`, `groups`, `idps`, `allowed_ips`, `dns` |
| `GET /admin/api/tenants/{id}` | un inquilino |
| `PUT /admin/api/tenants/{id}` | reemplaza su nombre, sus listas de pertenencia y sus rutas; incrementa `serial` y envía las rutas a sus observadores |
| `DELETE /admin/api/tenants/{id}` | lo elimina (excepto `default`); termina sus observaciones |

Sirva `/admin/` solo donde lleguen los administradores: el token es un secreto
compartido estático.

## Métricas {#metrics}

`GET /metrics` sirve métricas de Prometheus, sin autenticación:

| Métrica | |
|---|---|
| `claimward_enrollments_total{tenant}` | registros realizados con éxito |
| `claimward_active_peers` | pares registrados |
| `claimward_tenants` | inquilinos configurados |
| `claimward_route_watchers` | observaciones activas del RouteService |
| `claimward_tenant_route_serial{tenant}` | el número de serie de rutas de cada inquilino |
