---
title: "Aplicación macOS"
linkTitle: "Aplicación macOS"
weight: 4
description: "claimward-vpn-app-osx: una aplicación nativa en Go (una ventana y un icono de la barra de menús, dibujados con go-widgets y con los campos de texto y menús emergentes del sistema), con un helper LaunchDaemon de root."
tags: [macos, aplicación, helper, go-widgets]
---

[`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx)
**v0.8.0** es una aplicación nativa escrita en Go: una ventana y un icono de la barra
de menús, dibujados con [go-widgets](https://github.com/go-widgets), con los
`NSTextField` y `NSPopUpButton` del sistema para las entradas. No hay webview, ni
servidor web local, ni JavaScript (antes de v0.7.0 la ventana era una página Svelte en
un webview). Su lógica (inicio de sesión, elección del inquilino, conexión) y su helper
son los compartidos
[`pkg/appcore` y `pkg/helper`]({{< relref "/components/client.md" >}}); el modelo de
vista es `pkg/appvm`, el mismo que usan las aplicaciones Linux y Windows.

## Diseño {#design}

```text
 claimward-app (one process, as you)
 ├─ window         go-widgets, with NSTextField / NSPopUpButton embedded
 ├─ status item    NSStatusItem: status / Open Claimward… / Connect / Disconnect / Quit
 ├─ notifications  when the tunnel drops or the session expires (from the app bundle)
 └─ view model     pkg/appvm over appcore: sign-in, tenant choice, session
        │ Unix socket (JSON), 0660 root:admin
        ▼
   claimward-helper (root LaunchDaemon)
   enrolls with the server, wireguard-go: utunN, route pushes
```

La aplicación es un único proceso sin privilegios que posee todo el estado. Las entradas
(URL del servidor, identificadores de cliente) son los campos de texto del sistema, con su
método de entrada y su corrector ortográfico; las elecciones de proveedor e inquilino son
menús emergentes. El [helper]({{< relref "/components/helper.md" >}}) se registra en el
servidor y gestiona el túnel. Cerrar la ventana cierra la aplicación, como en Linux y Windows.

La ventana tiene una cabecera (la marca Claimward, el título y **Settings**), una barra
lateral **Servers** a la izquierda con **+** y **−** bajo la lista, y a la derecha el panel
de detalle del servidor seleccionado: su nombre, el menú emergente **Tenant** con
**Refresh**, el estado de la sesión, el inicio de sesión, Connect y Disconnect, y el
registro de conexión. El formulario de ajustes se abre en una ventana propia, para que el
estado siga visible; se muestra en la ventana principal donde no se puede abrir una segunda.

## Compilación {#build}

Con [go-task](https://taskfile.dev):

```sh
task config:init                                   # a starter config.json (local Dex)
task install-helper SERVER=https://vpn.example.org # build and install the helper (sudo)
task start:bundle                                  # build Claimward.app and open it
```

Ejecute el bundle en lugar del binario suelto: las notificaciones se rechazan a un
proceso que no está en un bundle de aplicación, así que con un binario suelto la caída
del túnel solo llega al registro. A mano (ya sin cadena Node):

```sh
CGO_ENABLED=1 go build -o bin/claimward-app    ./cmd/claimward-app
CGO_ENABLED=0 go build -o bin/claimward-helper ./cmd/claimward-helper
```

## Configuración {#configure}

`~/Library/Application Support/Claimward/config.json`, también editable desde la
ventana **Settings** (GitHub es el valor predeterminado):

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

Una persona que pertenece a varios inquilinos elige uno en el menú emergente **Tenant** del panel de detalle,
que los lista en cuanto el servidor los ha ofrecido; **Refresh** vuelve a pedirlos. La
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
**Pendiente:** el helper instalado con SMJobBless, una versión firmada con un
Developer ID, y el DNS aplicado en macOS.
{{< /callout >}}

## Sesión y servidores

La sesión (tokens y la clave WireGuard del dispositivo) vive en `session.enc`, sellada
con AES-GCM; la clave se guarda en el **Keychain** de inicio de sesión. Nunca se escribe
en claro en el disco y no hay alternativa en texto claro: si el Keychain está bloqueado o
no disponible (cliente v0.5.0 y posteriores), el inicio de sesión falla con un error que
lo indica. Un `session.json` `0600` de una versión anterior se traslada al almacén en el
primer arranque, o se elimina si eso falla.

La MTU del túnel es la `mtu` del servidor, reducida para caber en la ruta hacia
el servidor (la MTU de la interfaz hacia su endpoint, menos 60 en IPv4 u 80 en
IPv6) y nunca inferior a 1280 (cliente v0.6.0, `pkg/pathmtu`).

El servidor debe ser una URL **https**. Desde v0.7.0 ya no hay API de interfaz en
loopback ni token de lanzamiento: la ventana y la lógica comparten un único proceso.
