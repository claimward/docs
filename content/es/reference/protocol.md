---
title: "Protocolo de registro"
linkTitle: "Protocolo de registro"
weight: 1
description: "La API HTTP entre el helper de un dispositivo y claimward-vpn-server, sus errores, y el RouteService gRPC."
tags: [protocolo, servidor, grpc]
---

El contrato de comunicación entre los clientes y el servidor. Se define una sola vez en
[`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
(HTTP) y `proto/routes/v1/routes.proto` (gRPC), y ambos lados lo importan.

Cada petición autenticada envía el token bearer de la persona como
`Authorization: Bearer <token>`, nunca en el cuerpo: un **token de acceso OAuth
de GitHub** (`AUTH_PROVIDER=github`), un **token de ID OIDC** (`oidc`), o un
**token de acceso de go-authn** (`go-authn`). Los cuerpos de las peticiones son JSON, como máximo
64 KiB, y los campos desconocidos se rechazan.

## `POST /api/v1/enroll`

Petición:

```json
{
  "public_key": "<wireguard base64 public key>",
  "device": { "name": "alice-mbp", "os": "darwin", "platform": "app-osx" },
  "tenant": "hpc"
}
```

`tenant` es opcional: sin él, el servidor usa el único inquilino de la persona.
Los helpers envían `os` `darwin`, `linux` o `windows` y `platform`
`app-osx`, `app-linux` o `app-windows`.

Respuesta `200`:

```json
{
  "assigned_ip": "10.80.0.5/32",
  "server_public_key": "<base64>",
  "endpoint": "vpn.example.com:51820",
  "allowed_ips": ["10.80.0.0/24"],
  "dns": ["10.80.0.1"],
  "grpc_endpoint": "vpn.example.com:8444",
  "persistent_keepalive": 25,
  "lease_expires_at": "2026-10-06T10:00:00Z"
}
```

`allowed_ips` y `dns` son los del inquilino. `dns` se omite cuando el inquilino no
tiene ninguno, y `grpc_endpoint` cuando el servidor no anuncia ningún RouteService
(`GRPC_ENDPOINT`). El protocolo también tiene un `mtu` opcional, que el servidor
(v0.2.0) nunca establece.

## `GET /api/v1/tenants`

Respuesta `200`: los inquilinos a los que puede conectarse quien hace la llamada.

```json
[ { "id": "default", "name": "Default" } ]
```

## `POST /api/v1/heartbeat`

```json
{ "public_key": "<base64>" }
```

Respuesta `200`: `{ "lease_expires_at": "..." }`. `404 not_enrolled` si la clave
no está registrada por quien hace la llamada, `403 not_a_member` en cuanto la persona ha dejado el
inquilino de la sesión, `403 key_not_registered` (go-authn) en cuanto el proveedor
ya no lista la clave.

## `POST /api/v1/deregister`

```json
{ "public_key": "<base64>" }
```

Respuesta `204`, también para una clave que no está registrada. `403 not_owner` si la clave
pertenece a otra persona.

## `GET /healthz`

Respuesta `200`: `{ "status": "ok" }`, sin autenticación.

## Errores {#errors}

Las respuestas que no son 2xx contienen:

```json
{ "error": "invalid_token", "message": "…" }
```

| Código | Estado | Significado |
|------|--------|---------|
| `missing_token` / `invalid_token` | 401 | sin token bearer, o la verificación del proveedor ha fallado (incluida una lista de organizaciones o dominios permitidos) |
| `bad_public_key` / `bad_request` | 400 | entrada mal formada |
| `key_not_registered` | 403 | go-authn: esta persona no ha registrado la clave en el proveedor |
| `not_a_member` | 403 | el inquilino solicitado no es uno de los de quien hace la llamada, o ha dejado de serlo |
| `not_owner` | 403 | baja (deregister): la clave pertenece a otra persona |
| `not_enrolled` | 404 | heartbeat: quien hace la llamada no ha registrado esta clave |
| `key_taken` | 409 | registro: la clave está registrada por otra persona |
| `tenant_required` | 409 | registro: quien hace la llamada pertenece a varios inquilinos y no ha indicado ninguno; el mensaje los enumera |
| `pool_exhausted` | 503 | ninguna dirección libre en `VPN_CIDR` |
| `gateway_error` | 500 | no se ha podido añadir el par a WireGuard |

## RouteService (gRPC)

```protobuf
package claimward.routes.v1;

service RouteService {
  rpc Watch(WatchRequest) returns (stream RouteUpdate);
}
message WatchRequest { string public_key = 1; }
message RouteUpdate {
  repeated string allowed_ips = 1;
  repeated string dns = 2;
  uint64 serial = 3;   // increases on each change
}
```

El servidor escucha en `GRPC_ADDR` y anuncia `GRPC_ENDPOINT` en la
respuesta de registro. El token bearer viaja en los metadatos,
`authorization: Bearer <token>`, y se verifica igual que en la API HTTP. `Watch`
envía el conjunto actual de inmediato y después uno nuevo cada vez que cambian las rutas
del inquilino, para el inquilino **en el que se registró el dispositivo**, determinado por `public_key`,
que debe estar registrada por quien hace la llamada (`NOT_FOUND` en caso contrario,
`PERMISSION_DENIED` en cuanto la persona ha dejado ese inquilino).

El servidor lo sirve sobre TLS con `TLS_CERT`/`TLS_KEY`. Los clientes
(`pkg/routeclient`) se comunican con él por TLS, verificado con las raíces del sistema,
salvo hacia una dirección de loopback, y rechazan uno sin cifrar.
