---
title: "Proveedores de identidad"
weight: 30
description: "Varios proveedores a la vez, listados en un archivo: GitHub, cualquier emisor OpenID Connect, o un proveedor go-authn, que además sabe a quién pertenece cada clave WireGuard."
tags: [github, oidc, go-authn, servidor]
---

Desde el servidor v0.14.0 (**cambio incompatible**), el servidor acepta **varios** proveedores de
identidad a la vez, listados en un archivo JSON indicado por `PROVIDERS_FILE`. Las antiguas
variables de un solo proveedor (`AUTH_PROVIDER`, `OIDC_ISSUER`, `OIDC_CLIENT_ID`,
`OIDC_ALLOWED_DOMAINS`, `GITHUB_CLIENT_ID`, `GITHUB_ALLOWED_ORGS`,
`GOAUTHN_GATEWAY_CLIENT_ID`) ya no se leen, y el servidor se niega a
arrancar mientras una de ellas esté definida. El bearer que obtiene la aplicación es opaco en la red;
la forma en que el servidor lo verifica depende del proveedor.

## El archivo de proveedores

`PROVIDERS_FILE` es un objeto JSON con una lista `providers`. Los campos desconocidos se
rechazan, y el archivo ocupa 1 MiB como máximo:

```json
{"providers":[
  {"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]},
  {"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org"]},
  {"id":"renater","kind":"go-authn","name":"RENATER","oidc_issuer":"https://login.example.org","oidc_client_id":"claimward","gateway_client_id":"claimward-gw"}
]}
```

Cada proveedor tiene un `id` (el nombre con el que una petición lo designa), un `kind` y un
`name` (que se muestra a la persona). Los demás campos dependen del `kind`:

| `kind` | Inicio de sesión en el dispositivo | Bearer enviado al servidor | Campos además de `id`, `kind`, `name` | Archivo secreto |
|---|---|---|---|---|
| `github` | OAuth device flow | access token OAuth de GitHub | `github_client_id`, `api_url` (GitHub Enterprise), `allowed_orgs` | `provider-<id>-secret` |
| `oidc` | authorization code + PKCE, en el navegador | ID token OIDC | `oidc_issuer`, `oidc_client_id`, `allowed_domains` | ninguno |
| `go-authn` | device flow, y después registro de la clave | access token de go-authn (`at+jwt`) | `oidc_issuer`, `oidc_client_id`, `gateway_client_id` | `provider-<id>-gateway-secret` |

Los archivos secretos son credenciales, archivos de `CREDENTIALS_DIRECTORY`, nunca
variables (véase [Credenciales]({{< relref "/components/server.md#credentials" >}})).
Antes de la v0.14.0 se llamaban `github-client-secret` y `goauthn-gateway-secret`.

**La petición designa a su proveedor.** Cada llamada a la API lleva la cabecera
`Claimward-Provider: <id>` (gRPC: el metadato `claimward-provider`), y su
token lo verifica ese proveedor **solo**: un token del proveedor A se rechaza
cuando la petición designa a B. Sin cabecera es `401 missing_provider`; un id que el servidor
no lista da `401 unknown_provider`. El
[documento de descubrimiento]({{< relref "/reference/protocol.md#discovery" >}}) (versión
2) lista los proveedores, sin ningún secreto, así que un cliente solo necesita la URL del servidor.

**Una identidad por emisor y `sub`.** La identidad es `issuer#sub` para `oidc`
y `go-authn`, y `github:<id>` para `github`: el mismo `sub` en dos emisores son
dos personas, y la segunda no puede apropiarse del dispositivo de la primera.

**Inquilinos.** Un inquilino gana un campo `providers`, y sus grupos se escriben
`<id del proveedor>:<grupo>`. Con varios proveedores, un inquilino que use `domains` o
`idps` debe nombrar `providers`, o el servidor falla en cerrado. Véase los
[inquilinos]({{< relref "/tenants.md" >}}).

**Logotipo.** `SERVER_LOGO_FILE` (un SVG, 64 KiB como máximo, validado al arrancar) se
sirve en `/.well-known/claimward-logo.svg`, y el documento de descubrimiento da
su `path` y su `sha256` en `logo`.

## GitHub

La aplicación ejecuta el **device flow** de GitHub: muestra un código y la
página donde introducirlo, y abre esa página en el navegador. En el dispositivo solo se necesita un client ID,
así que cree una **OAuth App** de GitHub con **Device Flow**
activado, ponga su ID en `github_client_id` y su secreto de cliente en el archivo
`provider-<id>-secret`. La aplicación solicita `read:user`, `user:email` y `read:org`.

El servidor pregunta primero a GitHub, con ese secreto, si el token lo emitió
**esa OAuth App** (solo se admiten los suyos), y después identifica a la persona a través de la API de GitHub: su
ID numérico es el sujeto (`github:<id>`), sus organizaciones
(`/user/orgs`) son sus grupos para los [inquilinos]({{< relref "/tenants.md" >}}), y
su correo público, cuando lo tiene, se considera verificado. Con
`allowed_orgs`, la pertenencia activa a una de esas organizaciones la
admite, y también una entrada `members` nombrada de un inquilino (fijada al
identificador de la cuenta, véase los [inquilinos]({{< relref "/tenants.md#members" >}})). La
lista es opcional solo si un inquilino tiene miembros: sin ninguno de los dos, el
servidor se niega a arrancar, y lo mismo sin client ID o sin archivo secreto.
Establezca `api_url` para GitHub Enterprise.

```json
{"id":"hub","kind":"github","name":"GitHub","github_client_id":"Iv1.0123456789abcdef","allowed_orgs":["my-org","my-other-org"]}
```

## OpenID Connect

`kind` `oidc` con `oidc_issuer` (descubierto mediante
`/.well-known/openid-configuration`) y `oidc_client_id`, la audiencia que debe llevar el ID
token. La aplicación ejecuta el flujo authorization code con PKCE: abre
el navegador y recibe la redirección en `http://127.0.0.1:<port>/callback`,
con un puerto elegido en cada inicio de sesión. Solicita `openid profile email
offline_access`. Registre un cliente **público/nativo**, sin secreto: este tipo
no tiene, pues, archivo secreto.

El servidor toma el sujeto, el correo y `email_verified`, el
`preferred_username` y el claim `groups` (una lista, o una única cadena). Con
`allowed_domains`, el dominio del correo debe ser uno de ellos, y el correo debe
estar verificado.

```json
{"id":"campus","kind":"oidc","name":"Campus","oidc_issuer":"https://idp.example.org","oidc_client_id":"claimward","allowed_domains":["example.org"]}
```

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) es un proveedor OpenID Connect
situado delante de una federación SAML (RENATER, eduGAIN). Además sabe
**a quién pertenece cada clave WireGuard**, de modo que un token válido ya no basta para
registrar un dispositivo. Como máximo un proveedor del archivo es de este tipo.

1. La aplicación inicia sesión con el **device flow** del proveedor, scope
   `openid wireguard`. Ese token abre el registro de claves del proveedor y
   nada más: el proveedor dirige un token que lleva uno de sus propios scopes
   únicamente a sí mismo.
2. En cada conexión, la aplicación registra la clave **pública** del dispositivo
   (`POST /wireguard/key`), lo que la renueva si ya pertenece a la persona,
   y después hace un refresh solo para `scope=openid`. Así obtiene un **access token**
   dirigido al servidor VPN. El proveedor rota los refresh tokens, y la
   aplicación conserva el nuevo. La clave privada nunca sale del dispositivo.
3. El servidor solo acepta un access token (`typ: at+jwt`, RFC 9068) cuya
   audiencia sea el `oidc_client_id` del proveedor, nunca un ID token. Registra la clave solo si
   la lista del proveedor la tiene **registrada por el mismo sujeto**; en caso contrario
   responde `403 key_not_registered`. Una concesión nunca sobrevive al
   registro de la clave.

La lista procede de [go-authn/wireguard](https://github.com/go-authn/wireguard):

- se **obtiene con el cliente propio de la pasarela** (`gateway_client_id`,
  `client_credentials`, scope `wireguard_peers`, su secreto en
  `provider-<id>-gateway-secret`) y el proveedor la firma solo para esa pasarela
  (`typ: wireguard-peers+jwt`);
- se vuelve a obtener cada `GOAUTHN_PEER_LIST_INTERVAL` (30 segundos por
  defecto). Una clave que el proveedor retira (la persona o su institución
  desactivada, o el dispositivo eliminado) se quita de `wg0` en la siguiente obtención,
  y se rechaza su heartbeat;
- una lista **más antigua que otra ya vista** se rechaza, lo que constituye la
  protección contra la reproducción (replay);
- **falla en cerrado**: una lista es válida cinco minutos y, pasado ese plazo, la pasarela
  no admite a nadie nuevo, mientras que los túneles ya activos terminan con sus concesiones;
- la primera lista se obtiene **antes de que el servidor escuche**: una pasarela que
  no puede leerla no arranca;
- con `GOAUTHN_SSF=true`, la pasarela también consulta el flujo Shared Signals del
  proveedor (SSF 1.0, entrega por poll, RFC 8936) cada `GOAUTHN_SSF_INTERVAL`. Un
  evento solo provoca que la lista se obtenga de inmediato: es un desencadenante, nunca una
  decisión, así que un evento falsificado solo consigue una obtención adicional y nada más.

Los inquilinos se asocian según los `groups` del token (eduPerson entitlements) y
el `idp` (el entity ID de la institución que dio fe), y según el dominio del correo
solo cuando el proveedor ha verificado la dirección.

### Configuración {#configuration}

En el servidor, en `PROVIDERS_FILE`:

```json
{"providers":[
  {"id":"renater","kind":"go-authn","name":"RENATER",
   "oidc_issuer":"https://login.example.org",
   "oidc_client_id":"claimward",
   "gateway_client_id":"claimward-gw"}
]}
```

`oidc_client_id` es la audiencia de los access tokens, `gateway_client_id` el cliente propio
de la pasarela. El entorno añade el directorio de credenciales, que contiene
`wg-private-key` y `provider-renater-gateway-secret` (el secreto de la pasarela, solo en un archivo),
y opcionalmente el flujo Shared Signals:

```sh
PROVIDERS_FILE=/etc/claimward/providers.json
CREDENTIALS_DIRECTORY=/etc/claimward/credentials
GOAUTHN_SSF=true                               # opcional
```

En el proveedor (la configuración de go-authn/bridge):

```hcl
wireguard {
  lifetime = "24h"              # a key is listed this long; registering it again renews it
  max_keys = 10                 # devices per person
}

client "claimward" {            # the client people sign in with
  device           = true
  wireguard_keys   = true       # its tokens, with the wireguard scope, may register a key
  refresh_lifetime = "720h"
}

client "claimward-gw" {         # the gateway's own client
  secret_file     = "/etc/bridge/claimward-gw.secret"
  wireguard_peers = ["claimward"]   # it reads the keys registered through these clients
  ssf_receiver    = true            # optional: told at once when somebody is disabled
}
```

La aplicación (v0.9.0 o posterior) lee los proveedores del documento de descubrimiento
del servidor, así que su `config.json` solo necesita la URL del servidor, y envía el
`id` del proveedor elegido en `Claimward-Provider`:

```json
{
  "server_url": "https://vpn.example.com"
}
```

## Añadir un proveedor {#adding-a-provider}

En el servidor, implemente `Verifier` (`internal/auth`) y regístrelo en
`auth.New`. En el cliente, implemente `Provider` (`pkg/auth`) y regístrelo en
`auth.New`; un proveedor que guarda él mismo las claves de los dispositivos implementa también
`KeyRegistrar`.
