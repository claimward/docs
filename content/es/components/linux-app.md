---
title: "Aplicación Linux"
linkTitle: "Aplicación Linux"
weight: 5
description: "claimward-vpn-app-linux: una ventana y un icono en la bandeja del sistema dibujados en Go puro con go-widgets, y un helper reforzado ejecutado por systemd."
tags: [linux, aplicación, helper, systemd]
---

[`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux)
**v0.2.1** es una **ventana y un icono en la bandeja del sistema dibujados en Go puro** con
[go-widgets](https://github.com/go-widgets): sin webview, sin GTK, sin cgo
(`CGO_ENABLED=0`). Un **helper con privilegios** ejecutado por systemd gestiona el túnel
WireGuard. La lógica es la de la aplicación macOS: ambas usan
[`pkg/appcore` y `pkg/helper`]({{< relref "/components/client.md" >}}).

## Diseño {#design}

```text
 claimward-app (your session)
 ├─ internal/view        go-widgets/toolkit widgets, bound with go-widgets/mvvmtk
 ├─ internal/trayview    tray icon + menu (StatusNotifierItem over D-Bus)
 ├─ internal/viewmodel   all state as go-widgets/mvvm observables and commands
 └─ appcore              sign-in, tenant, session; drives the helper
        │ X11 / Wayland                  │ unix socket, JSON, 0660 root:claimward
        ▼                                ▼
   the window, the tray            claimward-helper (root, systemd)
                                   enrolls with a configured server,
                                   wireguard-go TUN + ip(8), route pushes
```

La aplicación se ejecuta con su usuario y nunca toca la configuración de red ni
el servidor directamente: todo pasa por el [helper]({{< relref "/components/helper.md" >}}).
El modelo de vista contiene todo el estado y no importa ningún widget; la CI impone
MVVM con [mvvmlint](https://github.com/go-widgets/mvvmlint) y "ninguna
interfaz dibujada a mano" con [bricolint](https://github.com/go-widgets/bricolint).

## Qué hace {#what-it-does}

- **Estado**: quién ha iniciado sesión, si está conectado o no, la dirección y la interfaz,
  el inquilino de la sesión, si el helper responde, el servidor. Se consulta
  cada 2 segundos.
- **Inicio de sesión**: en un flujo de dispositivo, la ventana muestra el código y un botón *Open sign-in
  page* (`xdg-open`); el inicio de sesión se puede cancelar.
- **Inquilino**: cuando el servidor rechaza una conexión porque la persona pertenece
  a varios, la ventana lo indica y ofrece una lista desplegable; *Choose tenant* solicita
  la lista de antemano. El inquilino no se puede cambiar mientras se está conectado.
- **Connect / Disconnect / Sign out**, **Settings** (URL del servidor, proveedor,
  ID de cliente de GitHub, emisor e ID de cliente OIDC) y el **historial de conexiones**.
- **Bandeja del sistema**: una línea de estado, *Connect*, *Disconnect*, *Open window*, *Quit*; el
  icono aparece en color mientras se está conectado. Cerrar la ventana deja la aplicación en la
  bandeja del sistema; *Quit* deja el túnel tal como está.

La bandeja del sistema necesita un host StatusNotifierItem (KDE Plasma, GNOME con la
extensión *AppIndicator and KStatusNotifierItem Support*, waybar…). Sin
él, o si el elemento de la bandeja no puede colocarse en el bus de sesión, la aplicación lo indica al
arrancar y cerrar la ventana la cierra.

## Instalación {#install}

Compile con su propio usuario (Go 1.27.1 o posterior) y después instale como root:

```sh
CGO_ENABLED=0 go build -trimpath -o bin/ ./cmd/...
sudo ./scripts/install.sh --server https://vpn.example.com
```

`install.sh`:

1. crea el grupo `claimward` y le añade a usted (`$SUDO_USER`, o
   `--user`): **cierre la sesión y vuelva a iniciarla** para que surta efecto;
2. instala `claimward-app` en `/usr/local/bin` y `claimward-helper` en
   `/usr/local/sbin` (`--prefix` para cambiarlo);
3. escribe `/etc/claimward/helper.json`, `root:root`, modo `0644`, con el
   servidor indicado (un archivo existente se conserva);
4. instala e inicia `claimward-helper.service`, y espera a su socket;
5. instala la entrada de escritorio y el icono.

Inicie **Claimward VPN** desde el menú del escritorio; `claimward-app -hidden`
arranca en la bandeja del sistema (para una entrada de inicio automático). `sudo ./scripts/uninstall.sh`
lo elimina todo y detiene el helper, lo que desactiva el túnel; `--purge`
elimina además `/etc/claimward` y el grupo.

## Configuración {#configure}

La aplicación: `~/.config/Claimward/config.json`, escrito por el formulario de ajustes,
modo `0600`, sobrescrito por las variables `CLAIMWARD_*` (véase la
[biblioteca cliente]({{< relref "/components/client.md#files-on-the-device" >}})).
La sesión es `~/.config/claimward/session.json`, modo `0600`.

El helper: `/etc/claimward/helper.json` (véase
[Helper con privilegios]({{< relref "/components/helper.md" >}})); después de editarlo,
`sudo systemctl restart claimward-helper`.

## La unidad reforzada {#the-hardened-unit}

`claimward-helper.service` conserva solo `CAP_NET_ADMIN`, `CAP_NET_RAW` y
`CAP_CHOWN`, con `NoNewPrivileges`, `ProtectSystem=strict` y solo `/run`
con permiso de escritura, `ProtectHome`, únicamente `/dev/net/tun` de `/dev`, familias de direcciones
limitadas a unix, inet, inet6 y netlink, y las llamadas al sistema de `@system-service`.
`systemd-analyze security claimward-helper` le asigna 2.5 (OK). Pertenecer al
grupo `claimward` significa tener permiso para activar y desactivar la VPN.

{{< callout type="info" >}}
**Verificado** en una máquina virtual Ubuntu 24.04 (arm64) frente a un servidor
sustituto. **Aún no verificado**, según el README: un escritorio GNOME o KDE
real, Wayland, HiDPI, un inicio de sesión con un proveedor de identidad real, y un
claimward-vpn-server real. El archivo de sesión todavía no está en un llavero.
{{< /callout >}}
