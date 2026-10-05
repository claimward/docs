---
title: "Aplicación macOS"
linkTitle: "Aplicación macOS"
weight: 4
description: "claimward-vpn-app-osx: una aplicación de la barra de menús en Go cuya ventana es una aplicación de página única Svelte en un webview, con un helper LaunchDaemon de root."
tags: [macos, aplicación, helper, svelte]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.2.0** es una aplicación de la barra de menús (bandeja del sistema) escrita en Go cuya **interfaz de usuario
completa es una aplicación de página única Svelte representada en un webview**. Su lógica (inicio de sesión,
elección del inquilino, conexión) y su helper son los compartidos
[`pkg/appcore` y `pkg/helper`]({{< relref "/components/client.md" >}}).

## Diseño {#design}

```text
 claimward-app (tray process, as you)
 ├─ systray     menu: status / Open Claimward… / Configuration… / Connect / Disconnect / Quit
 ├─ uiserver    loopback HTTP: embedded Svelte SPA + token-guarded JSON API
 └─ appcore     sign-in, tenant choice, session; drives the helper
        │ spawns "claimward-app ui <url>"     │ Unix socket (JSON), 0660 root:admin
        ▼                                     ▼
   webview (WKWebView)                   claimward-helper (root LaunchDaemon)
   renders the Svelte UI                 enrolls with the server, wireguard-go: utunN,
                                         route pushes
```

El proceso de la bandeja del sistema posee todo el estado y sirve tanto la interfaz como una pequeña API JSON en
`127.0.0.1`, protegida por un token generado en cada arranque y comparado en tiempo constante. El
webview es una ventana ligera que apunta a esa URL de loopback, en un proceso aparte
porque solo un bucle de ejecución Cocoa puede poseer el hilo principal. El
[helper]({{< relref "/components/helper.md" >}}) se registra en el servidor y
gestiona el túnel; la aplicación no tiene privilegios.

## Compilación {#build}

Con [go-task](https://taskfile.dev):

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Ejecute el bundle en lugar del binario suelto: un binario suelto iniciado desde un
agente de la barra de menús no puede traer su ventana al frente. A mano:

```sh
cd frontend && npm install && npm run build && cd ..   # the Svelte UI, embedded with go:embed
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Configuración {#configure}

`~/Library/Application Support/Claimward/config.json`, también editable desde
**Configuration…** (GitHub es el valor predeterminado):

```json
{
  "server_url": "https://vpn.example.com",
  "provider": "github",
  "github_client_id": "Iv1.0123456789abcdef"
}
```

Para OIDC, establezca `"provider": "oidc"`; para go-authn, `"provider": "go-authn"`, con
`"oidc_issuer"` y `"oidc_client_id"`. Con GitHub y go-authn, al hacer clic en
**Connect** se muestra un código que se debe introducir en la página indicada; con OIDC el navegador
abre la página de inicio de sesión del proveedor.

## Instalar el helper y ejecutar {#install-the-helper-and-run}

```sh
sudo ./scripts/install-helper.sh https://vpn.example.org   # more servers may follow
open dist/Claimward.app                                    # then click Connect
```

El instalador copia el helper en `/Library/PrivilegedHelperTools/`, escribe
`/Library/Application Support/Claimward/helper.json` (propiedad de root, modo `0644`)
con los servidores indicados, y carga el LaunchDaemon `com.claimward.helper`.
El socket del helper es `/var/run/claimward-helper.sock`, `0660`,
`root:admin`; registra en `/var/log/claimward-helper.log`.
`sudo ./scripts/uninstall-helper.sh` lo elimina.

## Inquilinos {#tenants}

Una persona que pertenece a varios inquilinos elige uno en la ventana ("Choose a tenant…"),
que los ofrece en cuanto el servidor indica que hay que elegir, o a petición. La
elección se mantiene durante la sesión; un nuevo inicio de sesión la olvida. Un **Connect** desde la
barra de menús que el servidor rechaza a falta de elección abre la ventana.

## Publicación {#release}

`.github/workflows/release.yml` compila `Claimward.dmg` con las etiquetas `v*` y
lo adjunta a la versión publicada. Cuando los secretos de firma están definidos, firma la aplicación
con un Developer ID y notariza y grapa (staple) el DMG; sin ellos recurre
a una firma ad hoc, que Gatekeeper bloquea en un DMG descargado. El
repositorio no contiene secretos de firma, por lo que los DMG publicados (v0.1.0 y
v0.2.0) están **firmados ad hoc y no notarizados**. El DMG contiene la aplicación (con el binario del helper dentro); el
helper se instala como se ha descrito más arriba.

{{< callout type="info" >}}
**Pendiente:** el token de sesión en el Keychain (hoy es un archivo `0600`),
el helper instalado con SMJobBless, una versión firmada con un
Developer ID, y el DNS aplicado en macOS.
{{< /callout >}}
