---
title: "Primeros pasos"
weight: 10
description: "Poner en marcha una pasarela WireGuard con claimward-vpn-server, registrar un cliente de inicio de sesión y conectar un primer dispositivo con la aplicación macOS, Linux o Windows."
tags: [wireguard, servidor, github, oidc]
---

Esta guía recorre la puesta en marcha de una pasarela y la conexión de un primer
dispositivo. La pasarela es un host Linux; el dispositivo ejecuta una de las tres aplicaciones de escritorio.

## 1. Preparar la pasarela WireGuard (Linux) {#1-prepare-the-wireguard-gateway-linux}

Cree la interfaz `wg0` con una clave de servidor y un puerto de escucha. Claimward
gestiona los *pares* de esta interfaz; no crea la interfaz.

```ini
# /etc/wireguard/wg0.conf
[Interface]
Address = 10.80.0.1/24
ListenPort = 51820
PrivateKey = <server-private-key>
```

```sh
wg genkey | tee server.key | wg pubkey > server.pub
sudo wg-quick up wg0
sudo sysctl -w net.ipv4.ip_forward=1   # if you route beyond the VPN subnet
```

## 2. Ejecutar el plano de control {#2-run-the-control-plane}

```sh
go install github.com/claimward/claimward-vpn-server/cmd/claimward-server@v0.2.0

export AUTH_PROVIDER=github                     # the default
export GITHUB_ALLOWED_ORGS=claimward            # optional authorization (recommended)
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY_FILE=/etc/wireguard/server.key
export VPN_CIDR=10.80.0.0/24
export TLS_CERT=/etc/claimward/fullchain.pem    # HTTPS, and TLS on the gRPC RouteService
export TLS_KEY=/etc/claimward/privkey.pem
export GRPC_ENDPOINT=vpn.example.com:8444       # where clients watch for route updates

sudo -E "$(go env GOPATH)/bin/claimward-server"
```

El servidor necesita los permisos para configurar `wg0` (root, o `CAP_NET_ADMIN`).
Escucha en `:8443` (`LISTEN_ADDR`) para la API de registro y en `:8444`
(`GRPC_ADDR`) para el RouteService. Consulte la
[referencia del servidor]({{< relref "/components/server.md" >}}) para todas las variables;
para experimentar sin una interfaz real, establezca `WG_DRYRUN=true`.

## 3. Registrar el cliente de inicio de sesión {#3-register-the-sign-in-client}

{{< tabs >}}
  {{< tab name="GitHub (por defecto)" >}}
Cree una **OAuth App** de GitHub (de organización o personal) y **active Device
Flow** en su configuración. Las aplicaciones solo necesitan su **client ID**, sin secreto.
Solicitan los scopes `read:user`, `user:email` y `read:org`.
  {{< /tab >}}
  {{< tab name="OpenID Connect" >}}
En su proveedor de identidad, cree un cliente **nativo/público** con PKCE y la
redirección de loopback `http://127.0.0.1:<port>/callback`. El puerto se elige en
cada inicio de sesión, por lo que el proveedor debe aceptar cualquier puerto de loopback (RFC 8252). Sin
secreto de cliente. Ejecute el servidor con `AUTH_PROVIDER=oidc`, `OIDC_ISSUER` y
`OIDC_CLIENT_ID`.
  {{< /tab >}}
  {{< tab name="go-authn" >}}
En un proveedor [go-authn/bridge](https://github.com/go-authn/bridge), declare
dos clientes: aquel con el que las personas inician sesión (`device = true`,
`wireguard_keys = true`, un `refresh_lifetime`), y el cliente propio de la pasarela
(`wireguard_peers`). Ejecute el servidor con `AUTH_PROVIDER=go-authn`. Consulte
[Proveedores de identidad]({{< relref "/identity-providers.md#go-authn" >}}).
  {{< /tab >}}
{{< /tabs >}}

## 4. Conectar un dispositivo {#4-connect-a-device}

Cada aplicación tiene un **helper con privilegios** que se registra en el servidor y gestiona
el túnel; se instala una sola vez, como administrador, con los servidores a los que puede
conectarse. La aplicación en sí se ejecuta con su usuario.

{{< tabs >}}
  {{< tab name="macOS" >}}
Desde una copia de trabajo de
[claimward-vpn-app-osx](https://github.com/claimward/claimward-vpn-app-osx):

```sh
sudo ./scripts/install-helper.sh https://vpn.example.com   # the root LaunchDaemon
task start:bundle                                          # build Claimward.app and open it
```

A continuación, indique la URL del servidor, el proveedor y su client ID en
**Configuration…** (o en `~/Library/Application Support/Claimward/config.json`),
y haga clic en **Connect**. Consulte la [aplicación macOS]({{< relref "/components/macos-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Linux" >}}
Desde una copia de trabajo de
[claimward-vpn-app-linux](https://github.com/claimward/claimward-vpn-app-linux):

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

Cierre la sesión y vuelva a iniciarla (el instalador le añade al grupo `claimward`), inicie
**Claimward VPN** desde el menú de su escritorio, complete la configuración y haga clic en
**Connect**. Consulte la [aplicación Linux]({{< relref "/components/linux-app.md" >}}).
  {{< /tab >}}
  {{< tab name="Windows" >}}
Desde una carpeta de versión generada por `scripts/package.sh` de
[claimward-vpn-app-windows](https://github.com/claimward/claimward-vpn-app-windows),
en un PowerShell **con privilegios elevados**:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.com -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Cierre la sesión de Windows y vuelva a iniciarla (el instalador le añade al grupo
**Claimward Users**), inicie **Claimward VPN** desde el menú Inicio y
haga clic en **Connect**. Consulte la [aplicación Windows]({{< relref "/components/windows-app.md" >}}).
  {{< /tab >}}
{{< /tabs >}}

A una persona que pertenece a varios inquilinos se le pide que elija uno antes de
establecer la conexión; consulte [Inquilinos]({{< relref "/tenants.md" >}}).


El dispositivo dispone ahora de una interfaz de túnel (`utunN` en macOS, `utun` en Linux, el
adaptador Wintun **Claimward** en Windows) con su dirección `10.80.0.x/32`, y
de rutas hacia las redes del inquilino a través de ella.

{{< callout type="warning" >}}
La renovación de la concesión llega con claimward-vpn-client v0.3.1, en las aplicaciones a partir de
v0.2.0: desde entonces el helper renueva la concesión mientras el túnel está activo y
se da de baja al hacer *Disconnect*. Las aplicaciones v0.1.0 no lo hacen: una conexión que permanece
activa más de `LEASE_TTL` (24 horas por defecto) se elimina de la pasarela,
y volver a conectarse inicia una nueva concesión. Consulte
[Concesiones]({{< relref "/architecture.md#leases" >}}).
{{< /callout >}}
