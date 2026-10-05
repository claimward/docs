---
title: "Proveedores de identidad"
weight: 30
description: "GitHub por defecto, cualquier emisor OpenID Connect, o un proveedor go-authn, que además sabe a quién pertenece cada clave WireGuard."
tags: [github, oidc, go-authn, servidor]
---

El servidor y las aplicaciones seleccionan cada uno un proveedor por su nombre, y deben coincidir:
`AUTH_PROVIDER` en el servidor, `"provider"` en el `config.json` de la aplicación (o
`CLAIMWARD_AUTH_PROVIDER`). El bearer que obtiene la aplicación es opaco en la red;
la forma en que el servidor lo verifica depende del proveedor.

| Proveedor | Inicio de sesión en el dispositivo | Bearer enviado al servidor | Cómo lo verifica el servidor |
|---|---|---|---|
| `github` (por defecto) | OAuth device flow | access token OAuth de GitHub | API de GitHub (`/user`, `/user/orgs`), lista opcional de organizaciones permitidas |
| `oidc` | authorization code + PKCE, en el navegador | ID token OIDC | firma, emisor, audiencia; lista opcional de dominios de correo permitidos |
| `go-authn` | device flow, y después registro de la clave | access token de go-authn (`at+jwt`) | firma, emisor, audiencia, `typ`; la clave debe estar registrada por el mismo sujeto |

## GitHub

El proveedor por defecto. La aplicación ejecuta el **device flow** de GitHub: muestra un código y la
página donde introducirlo, y abre esa página en el navegador. Solo se necesita un client ID,
sin secreto, así que cree una **OAuth App** de GitHub con **Device Flow**
activado. La aplicación solicita `read:user`, `user:email` y `read:org`.

El servidor identifica a la persona a través de la API de GitHub con su token: su
ID numérico es el sujeto (`github:<id>`), sus organizaciones
(`/user/orgs`) son sus grupos para los [inquilinos]({{< relref "/tenants.md" >}}), y
su correo público, cuando lo tiene, se considera verificado. Con
`GITHUB_ALLOWED_ORGS`, se exige una pertenencia activa a una de esas organizaciones.
Establezca `GITHUB_API_URL` para GitHub Enterprise.

```sh
AUTH_PROVIDER=github
GITHUB_ALLOWED_ORGS=my-org,my-other-org
```

## OpenID Connect

`AUTH_PROVIDER=oidc` con `OIDC_ISSUER` (descubierto mediante
`/.well-known/openid-configuration`) y `OIDC_CLIENT_ID`, la audiencia que debe llevar el ID
token. La aplicación ejecuta el flujo authorization code con PKCE: abre
el navegador y recibe la redirección en `http://127.0.0.1:<port>/callback`,
con un puerto elegido en cada inicio de sesión. Solicita `openid profile email
offline_access`. Registre un cliente **público/nativo**, sin secreto.

El servidor toma el sujeto, el correo y `email_verified`, el
`preferred_username` y el claim `groups` (una lista, o una única cadena). Con
`OIDC_ALLOWED_DOMAINS`, el dominio del correo debe ser uno de ellos.

## go-authn

[go-authn/bridge](https://github.com/go-authn/bridge) es un proveedor OpenID Connect
situado delante de una federación SAML (RENATER, eduGAIN). Además sabe
**a quién pertenece cada clave WireGuard**, de modo que un token válido ya no basta para
registrar un dispositivo:

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
   audiencia sea `OIDC_CLIENT_ID`, nunca un ID token. Registra la clave solo si
   la lista del proveedor la tiene **registrada por el mismo sujeto**; en caso contrario
   responde `403 key_not_registered`. Una concesión nunca sobrevive al
   registro de la clave.

La lista procede de [go-authn/wireguard](https://github.com/go-authn/wireguard):

- se **obtiene con el cliente propio de la pasarela** (`client_credentials`, scope
  `wireguard_peers`) y el proveedor la firma solo para esa pasarela
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

En el servidor:

```sh
AUTH_PROVIDER=go-authn
OIDC_ISSUER=https://login.example.org
OIDC_CLIENT_ID=claimward                       # the audience of the access tokens
GOAUTHN_GATEWAY_CLIENT_ID=claimward-gw         # the gateway's own client
GOAUTHN_GATEWAY_SECRET_FILE=/etc/claimward/claimward-gw.secret   # from a file only
GOAUTHN_SSF=true                               # optional
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

En el `config.json` de la aplicación:

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "go-authn",
  "oidc_issuer": "https://login.example.org",
  "oidc_client_id": "claimward"
}
```

## Añadir un proveedor {#adding-a-provider}

En el servidor, implemente `Verifier` (`internal/auth`) y regístrelo en
`auth.New`. En el cliente, implemente `Provider` (`pkg/auth`) y regístrelo en
`auth.New`; un proveedor que guarda él mismo las claves de los dispositivos implementa también
`KeyRegistrar`.
