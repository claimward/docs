---
title: "Biblioteca cliente"
linkTitle: "Biblioteca cliente"
weight: 2
description: "claimward-vpn-client: la biblioteca Go que comparten las aplicaciones y el servidor — inicio de sesión, protocolo de red, túnel, helper con privilegios y núcleo de las aplicaciones. No incluye ningún binario."
tags: [client, go, wireguard, grpc]
---

[`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client)
**v0.12.0** es una **biblioteca** Go. No incluye ningún binario: los programas ejecutables
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
| `pkg/pathmtu` | ajusta la MTU del túnel al camino: el `mtu` del servidor (1420 por defecto), reducido a la MTU de la interfaz hacia el endpoint menos 60 (IPv4) u 80 (IPv6), nunca por debajo de 1280, nunca por encima del valor del servidor; solo biblioteca estándar |
| `pkg/wgtun` | túnel WireGuard en espacio de usuario con `wireguard-go`, más dirección y rutas: `ifconfig`/`route` en macOS, `ip` en Linux, un adaptador Wintun mediante `winipcfg` en Windows (con DNS y MTU); requiere privilegios |
| `pkg/routeclient` | observa el RouteService del servidor y notifica las actualizaciones de rutas; TLS salvo hacia loopback |
| `pkg/appcore` | la lógica de las aplicaciones, compartida por las tres: inicio de sesión, el inquilino elegido para la sesión, conexión y desconexión a través del helper, estado para la interfaz |
| `pkg/appvm` | el modelo de vista de las aplicaciones, sin interfaz: la pantalla que se muestra, lo que puede hacer cada orden, la consulta del estado, los eventos (túnel caído, sesión caducada) y, desde v0.12.0, los datos de cada túnel (`State.Tunnel`: interfaz, dirección, endpoint, IP permitidas, DNS, MTU, bytes recibidos y enviados, último handshake); cada aplicación lo adapta a sus widgets |
| `pkg/helper` | el helper con privilegios, compartido por las tres aplicaciones: registra el dispositivo, es dueño del túnel, observa las rutas enviadas y aprueba servidores con el consentimiento del sistema ([Aprobación de servidores](../../server-approval/)) |
| `pkg/hproto`, `pkg/helperclient` | el protocolo de socket del helper, y el cliente de la aplicación para él: `Approve`, `ApproveElevated`, `Revoke`, `Approved` y los errores tipados `*NotApprovedError` y `ErrApprovalDenied` |
| `pkg/macauth` | Authorization Services de macOS para la aprobación de servidores: `Obtain(prompt)` en la aplicación, `Verify` en el helper |
| `pkg/tokenstore` | la sesión (bearer, token de refresco, clave privada del dispositivo, inquilino elegido) en el almacén de secretos del sistema: Keychain de macOS, DPAPI de Windows, Secret Service de Linux; sin alternativa en texto claro |

## Archivos en el dispositivo {#files-on-the-device}

| Archivo | Qué |
|---|---|
| `<config dir>/Claimward/config.json` | la configuración de la aplicación (`appcore.Config`), `0600`, su socket puede sustituirse con `CLAIMWARD_HELPER_SOCKET` |
| `<config dir>/claimward/session.enc` (macOS y Linux), `session.dpapi` (Windows) | la sesión sellada; su clave está en el Keychain (macOS) o en el Secret Service (Linux), o el blob está protegido por DPAPI. En Linux, el blob se sella con AES-GCM y solo su clave está en el Secret Service. |

`<config dir>` es `os.UserConfigDir()` de Go: `~/Library/Application Support` en
macOS, `~/.config` en Linux, `%AppData%` en Windows.

Este es el formato del **cliente v0.10.0 y posteriores**, que se conecta a varios
servidores a la vez. La persona escribe solo la URL de un servidor; el nombre, los
proveedores, la exclusividad y el logotipo se leen del
`/.well-known/claimward-configuration` del servidor.

```json
{
  "version": 2,
  "servers": [
    {"url": "https://vpn.example.com", "provider": "campus"},
    {"url": "https://lab.example.org"}
  ],
  "socket_path": "/var/run/claimward-helper.sock"
}
```

| Clave de `config.json` | |
|---|---|
| `version` | `2` |
| `servers[].url` | la URL base del servidor (`https://`; `http://` solo en loopback); debe ser una de las configuradas en el helper |
| `servers[].provider` | opcional: el `id` del proveedor elegido del documento del servidor |
| `socket_path` | opcional: el socket del helper, si no es el predeterminado. Puede sustituirse con `CLAIMWARD_HELPER_SOCKET`, la única variable que queda |

Un archivo de la v0.9.0 o anterior (`server_url`, `provider`, `github_client_id`,
`oidc_issuer`, `oidc_client_id` y las variables `CLAIMWARD_SERVER`,
`CLAIMWARD_AUTH_PROVIDER`, `CLAIMWARD_GITHUB_CLIENT_ID`, `CLAIMWARD_OIDC_*`) se migra
una vez en la primera carga. Un servidor **exclusivo** se rechaza mientras haya otro
conectado, y cualquier otro se rechaza mientras haya uno exclusivo conectado; el
rechazo nombra el servidor que bloquea. Desde **v0.11.0** todas las plataformas
mantienen un túnel por servidor, cada uno en su propia interfaz determinista (abajo).

Desde v0.11.0 el `servers` del helper es opcional (la preaprobación del administrador)
y un servidor que la persona añade solo es de confianza cuando el sistema ha dado su
consentimiento: véase [Aprobación de servidores](../../server-approval/). El `helper.json`
del helper incorpora `approvals`, el archivo de servidores aprobados.

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
- **Nombres de interfaz.** Una interfaz por servidor, nombrada a partir de la URL del
  servidor por `wgtun.InterfaceName`: macOS `utunN` (numerada por el kernel), Linux `cw-`
  y diez dígitos hexadecimales del SHA-256 de la URL (13 bytes, dentro de los 15 de
  `IFNAMSIZ`), Windows `Claimward <host> <6 hex>`. Reconectar sustituye la interfaz; un
  resto con ese nombre se elimina antes, y un dispositivo TUN de Linux desaparece con su
  proceso, así que un helper que se cuelga no deja ninguno.
- **Windows.** El dispositivo es un adaptador Wintun, uno por servidor (véase arriba): `wintun.dll`
  (de <https://www.wintun.net>, firmado por WireGuard LLC) debe estar junto al
  ejecutable que llama a `wgtun.Up`, de lo cual se encarga el empaquetado de la aplicación
  de Windows. La dirección, las rutas, el DNS y la MTU se configuran mediante `winipcfg` (la API IP
  Helper, Go puro, `CGO_ENABLED=0`).
- **Almacén de la sesión.** El almacén de secretos de la plataforma: el Keychain de inicio de
  sesión de macOS (guarda una clave AES-GCM; la sesión se sella en `session.enc`), DPAPI de
  Windows (`session.dpapi`) y, en Linux, también un `session.enc` sellado, cuya clave
  AES-GCM se guarda en el Secret Service mediante `secret-tool`. Desde
  **v0.5.0** no hay alternativa en texto claro y `CLAIMWARD_ALLOW_PLAINTEXT_SESSION`
  no tiene efecto: sin un almacén utilizable, guardar la sesión falla y el inicio de
  sesión falla con un error que nombra lo que falta (en Linux, instale y desbloquee un proveedor
  de Secret Service como gnome-keyring o KeePassXC, e instale `secret-tool`).
  Un `session.json` antiguo se lee una vez, se traslada al almacén y se elimina, o se
  elimina si el almacén lo rechaza. Las pruebas de otros paquetes usan
  `tokenstore.UseMemory()`.
