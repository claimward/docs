---
title: "Documentación de Claimward"
linkTitle: "Inicio"
type: docs
cascade:
  type: docs
description: "Claimward es una solución autoalojada de acceso a la red Zero Trust basada en WireGuard: las personas inician sesión con el proveedor de identidad que usted ya tiene, y su dispositivo se registra como par WireGuard de su pasarela."
# Las tarjetas de abajo enumeran las secciones: la barra lateral izquierda las repetiría.
sidebar:
  hide: true
toc: false
---

{{< brand-lockup >}}

**Claimward** es una solución autoalojada de acceso a la red Zero Trust basada en
[WireGuard](https://www.wireguard.com/). Las personas inician sesión con el proveedor
de identidad que usted ya tiene (GitHub, cualquier proveedor OpenID Connect o un
proveedor [go-authn](https://github.com/go-authn/bridge) delante de una federación
SAML); a continuación, Claimward registra su dispositivo como par WireGuard de su
pasarela, con una dirección propia y las rutas del inquilino que hayan elegido.

Todo está escrito en Go. La aplicación macOS dibuja su ventana con Svelte en una
webview; las aplicaciones Linux y Windows son Go puro
([go-widgets](https://github.com/go-widgets), sin cgo).

{{< cards >}}
  {{< card link="getting-started/" title="Primeros pasos" icon="lightning-bolt" subtitle="Ponga en marcha una pasarela y conecte un primer dispositivo." >}}
  {{< card link="architecture/" title="Arquitectura" icon="puzzle" subtitle="Plano de control, plano de datos, el flujo de registro y las concesiones." >}}
  {{< card link="identity-providers/" title="Proveedores de identidad" icon="finger-print" subtitle="GitHub (por defecto), OpenID Connect, o go-authn con su registro de claves WireGuard." >}}
  {{< card link="tenants/" title="Inquilinos" icon="users" subtitle="Quién pertenece a dónde, y el inquilino elegido para cada sesión." >}}
  {{< card link="components/" title="Componentes" icon="cube" subtitle="El servidor, la biblioteca cliente, el helper con privilegios y las tres aplicaciones de escritorio." >}}
  {{< card link="reference/protocol/" title="Referencia del protocolo" icon="code" subtitle="La API de registro y el RouteService gRPC." >}}
  {{< card link="operations/" title="Operación" icon="cog" subtitle="TLS, la pasarela, las concesiones, el estado, la API de administración y las métricas." >}}
{{< /cards >}}

## Las piezas {#the-pieces}

| Repositorio | Versión | Qué es |
|------------|---------|------------|
| [`claimward-vpn-server`](https://github.com/claimward/claimward-vpn-server) | v0.2.0 | Plano de control: verifica el inicio de sesión, asigna direcciones, programa la pasarela WireGuard, transmite las rutas de los inquilinos por gRPC, API de administración y métricas |
| [`claimward-vpn-client`](https://github.com/claimward/claimward-vpn-client) | v0.3.1 | **Biblioteca** Go compartida por las aplicaciones y el servidor: protocolo de comunicación, proveedores de inicio de sesión, túnel, helper con privilegios, núcleo de la aplicación. No incluye ningún binario |
| [`claimward-vpn-app-osx`](https://github.com/claimward/claimward-vpn-app-osx) | v0.2.0 | Aplicación macOS: aplicación de la barra de menús en Go, interfaz Svelte en una webview, helper LaunchDaemon como root |
| [`claimward-vpn-app-linux`](https://github.com/claimward/claimward-vpn-app-linux) | v0.2.1 | Aplicación Linux: ventana y bandeja del sistema en Go puro, helper ejecutado por systemd |
| [`claimward-vpn-app-windows`](https://github.com/claimward/claimward-vpn-app-windows) | v0.3.0 | Aplicación Windows: ventana y bandeja del sistema en Go puro, helper como servicio de Windows, túnel Wintun |

{{< callout type="info" >}}
**Estado.** Son las primeras versiones publicadas. Queda por llegar, según cada
repositorio: el token de sesión en el almacén de secretos de la plataforma (Keychain,
un llavero, el Administrador de credenciales de Windows), una aplicación macOS firmada
y notarizada, un MSI para Windows, el DNS aplicado en macOS y Linux, y un estado en el
servidor que sobreviva a un reinicio. El README de cada repositorio enumera lo que falta.
{{< /callout >}}
