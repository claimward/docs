---
title: "Biblioteca cliente"
linkTitle: "Biblioteca cliente"
weight: 2
description: "claimward-vpn-client: la biblioteca Go que comparten las aplicaciones y el servidor — inicio de sesión, protocolo de red, túnel, helper con privilegios y núcleo de las aplicaciones. No incluye ningún binario."
tags: [client, go, wireguard, grpc]
---

[`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client)
**v0.3.1** es una **biblioteca** Go. No incluye ningún binario: los programas ejecutables
son los de las aplicaciones (`cmd/claimward-app` y `cmd/claimward-helper` en el repositorio
de cada aplicación). El servidor también la importa, por los tipos de red y los stubs gRPC.

{{< callout type="info" >}}
No existe ningún cliente de línea de comandos `claimward`. Las versiones anteriores de este módulo
tenían uno (`cmd/claimward`, con `login` y `connect`); se eliminó, y
el módulo que solo contiene la biblioteca es la base sobre la que se construyen las aplicaciones.
{{< /callout >}}

## Paquetes {#packages}

| Paquete | Función |
|---------|---------|
| `pkg/protocol` | el contrato de red (`/enroll`, `/tenants`, `/heartbeat`, `/deregister`), compartido con el servidor |
| `pkg/routespb` | stubs gRPC/protobuf generados del RouteService, compartidos con el servidor |
| `pkg/auth` | inicio de sesión interactivo detrás de un `Provider`: flujo de dispositivo de GitHub (predeterminado), código OIDC + PKCE, o flujo de dispositivo de go-authn, cuyo proveedor también registra la clave del dispositivo (`KeyRegistrar`) |
| `pkg/oidc` | el flujo de código de autorización OIDC + PKCE: descubrimiento, redirección a loopback |
| `pkg/browser` | abre una URL en el navegador predeterminado con rutas absolutas al programa que la abre, para que funcione desde aplicaciones gráficas |
| `pkg/client` | `Enroll`, `Tenants`, `Heartbeat`, `Deregister` contra el servidor, y `TunnelConfig` para convertir un `EnrollResponse` en un `wgtun.Config` |
| `pkg/wgkey` | generación y análisis de claves WireGuard |
| `pkg/wgtun` | túnel WireGuard en espacio de usuario con `wireguard-go`, más dirección y rutas: `ifconfig`/`route` en macOS, `ip` en Linux, un adaptador Wintun mediante `winipcfg` en Windows (con DNS y MTU); requiere privilegios |
| `pkg/routeclient` | observa el RouteService del servidor y notifica las actualizaciones de rutas; TLS salvo hacia loopback |
| `pkg/appcore` | la lógica de las aplicaciones, compartida por las tres: inicio de sesión, el inquilino elegido para la sesión, conexión y desconexión a través del helper, estado para la interfaz |
| `pkg/helper` | el helper con privilegios, compartido por las tres aplicaciones: registra el dispositivo, es dueño del túnel, observa las rutas enviadas |
| `pkg/hproto`, `pkg/helperclient` | el protocolo de socket del helper, y el cliente de la aplicación para él |
| `pkg/tokenstore` | la sesión (bearer, token de refresco, clave privada del dispositivo, inquilino elegido) en un archivo JSON `0600` |

## Archivos en el dispositivo {#files-on-the-device}

| Archivo | Qué |
|---|---|
| `<config dir>/Claimward/config.json` | la configuración de la aplicación (`appcore.Config`), `0600`, sustituida por las variables `CLAIMWARD_*` |
| `<config dir>/claimward/session.json` | la sesión (`pkg/tokenstore`), `0600` |

`<config dir>` es `os.UserConfigDir()` de Go: `~/Library/Application Support` en
macOS, `~/.config` en Linux, `%AppData%` en Windows.

| Clave de `config.json` | Variable | |
|---|---|---|
| `server_url` | `CLAIMWARD_SERVER` | la URL base del servidor; debe ser una de las configuradas en el helper |
| `provider` | `CLAIMWARD_AUTH_PROVIDER` | `github` (predeterminado), `oidc` o `go-authn` |
| `github_client_id` | `CLAIMWARD_GITHUB_CLIENT_ID` | el client ID de la aplicación OAuth de GitHub |
| `oidc_issuer` | `CLAIMWARD_OIDC_ISSUER` | `oidc` y `go-authn` |
| `oidc_client_id` | `CLAIMWARD_OIDC_CLIENT_ID` | `oidc` y `go-authn` |
| `socket_path` | `CLAIMWARD_HELPER_SOCKET` | el socket del helper, si no es el predeterminado |

## Uso en sus propias herramientas {#use-in-your-own-tooling}

```go
ctx := context.Background()

// 1. Sign in. GitHub is the default provider (device flow).
provider, err := auth.New(auth.Config{Provider: "github", GitHubClientID: "Iv1.0123456789abcdef"})
if err != nil {
	log.Fatal(err)
}
tok, err := provider.Login(ctx, func(p auth.DevicePrompt) {
	fmt.Printf("visit %s and enter code %s\n", p.VerificationURI, p.UserCode)
})
if err != nil {
	log.Fatal(err)
}

// 2. A key pair, and with go-authn the PUBLIC key registered first: the
//    token for the server is the one RegisterKey returns.
keys, err := wgkey.Generate()
if err != nil {
	log.Fatal(err)
}
if reg, ok := provider.(auth.KeyRegistrar); ok {
	if tok, err = reg.RegisterKey(ctx, tok, keys.Public.String(), "laptop"); err != nil {
		log.Fatal(err)
	}
}

// 3. Enroll; "" lets the server use the person's only tenant.
c := client.New("https://vpn.example.com")
resp, err := c.Enroll(ctx, tok.Value, keys.Public,
	protocol.DeviceInfo{Name: "laptop", OS: "linux", Platform: "my-tool"}, "")
if err != nil {
	log.Fatal(err)
}

// 4. The tunnel (needs privileges), and optionally live routes.
cfg, err := client.TunnelConfig(resp, keys.Private)
if err != nil {
	log.Fatal(err)
}
tun, err := wgtun.Up(cfg)
if err != nil {
	log.Fatal(err)
}
defer tun.Close()
if resp.GRPCEndpoint != "" {
	go routeclient.Watch(ctx, resp.GRPCEndpoint, tok.Value, keys.Public.String(),
		func(u routeclient.Update) { _ = tun.UpdateRoutes(u.AllowedIPs) })
}
```

Un cliente de larga duración renueva su concesión con `c.Heartbeat` antes de
`resp.LeaseExpiresAt`, y elimina su par con `c.Deregister` cuando termina.

## Notas por plataforma {#platform-notes}

- **DNS.** Los servidores DNS del servidor se aplican solo en **Windows**; en macOS
  y Linux viajan en el protocolo, pero `pkg/wgtun` todavía no
  los aplica.
- **Rutas enviadas**: sustituyen las IP permitidas y las rutas; los cambios de DNS de un
  envío no se aplican.
- **Windows.** El dispositivo es un adaptador Wintun llamado `Claimward`: `wintun.dll`
  (de <https://www.wintun.net>, firmado por WireGuard LLC) debe estar junto al
  ejecutable que llama a `wgtun.Up`, de lo cual se encarga el empaquetado de la aplicación
  de Windows. La dirección, las rutas, el DNS y la MTU se configuran mediante `winipcfg` (la API IP
  Helper, Go puro, `CGO_ENABLED=0`).
- **Almacén de la sesión.** Un archivo `0600`; trasladarlo al almacén de secretos de la plataforma
  está aún pendiente.
