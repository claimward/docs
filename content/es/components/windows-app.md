---
title: "Aplicación Windows"
linkTitle: "Aplicación Windows"
weight: 6
description: "claimward-vpn-app-windows: una ventana y un icono en el área de notificación en Go puro, el servicio ClaimwardHelper, y wireguard-go sobre un adaptador Wintun."
tags: [windows, aplicación, helper, wintun]
---

[`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows)
**v0.3.0** es una aplicación de escritorio con un icono en el área de notificación (bandeja del sistema). Todo es
Go con `CGO_ENABLED=0`: la ventana y la bandeja del sistema las dibuja
[go-widgets](https://github.com/go-widgets) (sin webview, sin servidor HTTP en la
aplicación), y el túnel es [wireguard-go](https://git.zx2c4.com/wireguard-go) sobre un
adaptador [Wintun](https://www.wintun.net), configurado mediante la IP Helper API.
Su lógica y su helper son los compartidos
[`pkg/appcore` y `pkg/helper`]({{< relref "/components/client.md" >}}).

## Diseño {#design}

```text
 claimward-app.exe (the person, unprivileged)
 ├─ internal/ui/view.go        widgets, bound by go-widgets/mvvmtk to …
 ├─ internal/ui/viewmodel.go   … the ViewModel: all state, observables and commands
 ├─ internal/ui/tray_binding   the tray menu, bound to the same ViewModel
 └─ appcore                    sign-in, session, tenant, helper client
        │ AF_UNIX socket, one JSON request each: C:\ProgramData\Claimward\helper.sock
        ▼
 claimward-helper.exe — the ClaimwardHelper service (LocalSystem)
   pkg/helper   enrolls with a server helper.json names, owns the tunnel
   pkg/wgtun    wireguard-go on the Wintun adapter "Claimward"; address, routes, DNS, MTU
```

La ventana muestra la conexión, la dirección y la interfaz, quién ha iniciado sesión,
el inquilino y si el helper responde; el aviso del flujo de dispositivo con un
botón que abre la página en el navegador predeterminado (solo se entrega al shell
una página `https`); **Connect / Disconnect / Sign out**; **Choose
tenant**; los ajustes, guardados en `%AppData%\Claimward\config.json`; y el
historial de conexiones. El estado se consulta cada 2 segundos. El menú de la bandeja del sistema ofrece
el estado, Connect, Disconnect, Open y Quit. Cerrar la ventana cierra la
aplicación; el túnel pertenece al servicio y permanece activo hasta Disconnect.

El icono de la bandeja del sistema aparece a partir de **v0.3.0**. Antes, la biblioteca de la bandeja no tenía
implementación para Windows de la llamada que hace la aplicación, y la aplicación ignoraba el
error, de modo que v0.1.0 y v0.2.0 no mostraban **ningún icono en la bandeja**. v0.3.0 se compila con la
biblioteca de la bandeja que la implementa (go-widgets/tray v0.14.0). Esto está comprobado por la
compilación y por las pruebas propias de la biblioteca, pero aún no en un escritorio Windows. Dos
carencias conocidas: un icono que no se puede añadir se notifica en stderr, que una
compilación con ventana no muestra
([#6](https://github.com/claimward/claimward-vpn-app-windows/issues/6)), y
al salir puede quedar un icono fantasma hasta que el puntero pasa por encima
([go-widgets/tray#37](https://github.com/go-widgets/tray/issues/37)).

## Instalación {#install}

Desde una carpeta de versión publicada (`scripts/package.sh` las genera, con Wintun), en un
PowerShell **con privilegios elevados**:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1 -Server https://vpn.example.org
# optionally, the app's settings for the current user as well:
.\install.ps1 -Server https://vpn.example.org -Provider github -GitHubClientId Iv1.0123456789abcdef
```

Copia los programas y `wintun.dll` en `C:\Program Files\Claimward`,
crea el grupo local **Claimward Users** y le añade a usted, escribe
`C:\ProgramData\Claimward\helper.json`, registra e inicia el servicio
**ClaimwardHelper**, y añade un acceso directo **Claimward VPN** al menú Inicio.
La pertenencia surte efecto en su **próximo inicio de sesión en Windows**; hasta entonces el
socket le rechaza. Añada a otras personas con
`Add-LocalGroupMember -Group 'Claimward Users' -Member <name>`.

`.\uninstall.ps1` elimina el servicio, el acceso directo y los programas;
`-RemoveData` elimina además `C:\ProgramData\Claimward` y el grupo. Todavía no
hay MSI.

`package.sh` descarga `wintun-0.14.1.zip` de wintun.net y lo rechaza
salvo que su SHA-256 coincida con el fijado en el script; la DLL está firmada por
WireGuard LLC y no está en el repositorio.

## Configuración {#configure}

La aplicación lee `%AppData%\Claimward\config.json` y después las variables `CLAIMWARD_*`
(véase la [biblioteca cliente]({{< relref "/components/client.md#files-on-the-device" >}})).
La sesión es `%AppData%\claimward\session.json`.

El helper lee `C:\ProgramData\Claimward\helper.json`:

```json
{
  "servers": ["https://vpn.example.org"],
  "group": "Claimward Users",
  "socket": "C:\\ProgramData\\Claimward\\helper.sock"
}
```

El servicio registra en `C:\ProgramData\Claimward\helper.log`; desde una consola
con privilegios elevados, `claimward-helper run` lo ejecuta en primer plano. Las ACL que el helper
establece y comprueba se describen en
[Helper con privilegios]({{< relref "/components/helper.md#the-socket-windows" >}}).

{{< callout type="info" >}}
**Pendiente:** un instalador MSI, y la sesión en el Administrador de credenciales
de Windows (DPAPI) en lugar de un archivo por usuario.
{{< /callout >}}
