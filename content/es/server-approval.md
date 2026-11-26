---
title: "Aprobación de servidores"
linkTitle: "Aprobación de servidores"
weight: 35
description: "Cómo decide el helper de root confiar en un servidor que nombra la aplicación: la preaprobación del administrador o el consentimiento del propio sistema operativo, recordado en un archivo que solo root puede escribir y revocable en cualquier momento."
tags: [security, helper, approval, macos, linux, windows]
---

El helper se ejecuta como root (SYSTEM en Windows) y un servidor con el que se registra
elige las rutas y el par del túnel de la máquina: un servidor hostil es cada paquete de
la máquina, enviado allí. Desde el **cliente v0.11.0** el helper acepta un servidor de la
aplicación solo si se cumple una de estas condiciones:

1. la configuración del administrador lo nombra (`servers` en `helper.json`, ahora
   opcional: la **preaprobación**);
2. fue **aprobado** antes, y sigue diciendo lo mismo que entonces;
3. se aprueba **ahora**, con el consentimiento del sistema operativo, obtenido por el
   propio helper.

Un indicador de la aplicación, un campo de la petición o una afirmación de cualquier tipo
nunca es consentimiento.

## Qué se pide al sistema

| Plataforma | Consentimiento |
|---|---|
| macOS | derecho de Authorization Services `com.claimward.helper.approve-server`, regla `authenticate-admin-nonshared`: nombre y contraseña de un administrador, cada vez. La aplicación obtiene la autorización (`macauth.Obtain`) y envía su forma externa de 32 bytes; el helper hace que el sistema la verifique y la destruye, así que un token compra una aprobación. Un token falsificado no nombra nada en el sistema y se rechaza |
| Linux | acción polkit `com.claimward.helper.approve-server` (`auth_admin`), consultada al bus del sistema para el proceso que está tras el socket: su pid de `SO_PEERCRED` y su hora de inicio de `/proc/<pid>/stat`, lo que impide la reutilización de pids. El archivo de política está en `packaging/polkit/` y va en `/usr/share/polkit-1/actions/` |
| Windows | un segundo socket, `C:\ProgramData\Claimward\approve.sock`, cuya ACL nombra solo a SYSTEM y Administradores: un usuario estándar no puede conectarse sin elevación UAC. Solo cuenta una petición que llegó por él |

Sin autorizador configurado, el helper rechaza toda aprobación: falla cerrado. Una
petición rechazada, o que el sistema no puede responder, no cambia nada.

## Qué se recuerda

El helper guarda los servidores aprobados en un archivo que solo root puede escribir:

| Plataforma | Archivo |
|---|---|
| macOS | `/var/db/claimward/approved-servers.json` |
| Linux | `/var/lib/claimward/approved-servers.json` |
| Windows | `C:\ProgramData\Claimward\approved-servers.json` |

Cada entrada es la URL canónica del servidor y el SHA-256 de su **identidad de
descubrimiento**: su nombre y sus proveedores de identidad (id, tipo, emisor, ids de
cliente). Un servidor que cambia alguno de ellos no es el que se aprobó: el helper lo
rechaza (`server_identity_changed`) hasta que se apruebe de nuevo. Que el servidor sea
exclusivo, su logotipo y los nombres visibles de los proveedores no forman parte de la
identidad, ni tampoco su certificado TLS, que se renueva cada pocas semanas (la conexión
se verifica contra la PKI web en cada uso).

El archivo se lee de nuevo en cada uso, así que **borrarlo, o quitar una línea, revoca de
inmediato**; la acción `revoke` hace lo mismo para un servidor. El helper nunca edita la
lista `servers` del administrador.

## Errores que ve la aplicación

| Código | Significado |
|---|---|
| `server_not_approved` | el servidor no está ni preaprobado ni aprobado: pedir a la persona que lo apruebe |
| `server_identity_changed` | estaba aprobado y ya no dice lo mismo: aprobarlo de nuevo |
| `approval_denied` | no se dio el consentimiento del sistema |

## Límites, dichos con claridad

- En macOS el **texto del aviso lo aporta la aplicación** que pregunta, así que un
  proceso hostil del grupo del socket puede lograr que el sistema pida a un
  administrador aprobar su propio servidor, y un administrador distraído puede decir que
  sí. La credencial es la de un administrador, nunca se guarda en caché y vale para una
  aprobación.
- En Windows, un proceso elevado puede aprobar cualquier cosa, pues un administrador
  puede editar el archivo de todos modos.
- Linux tampoco tiene caché: `auth_admin` pregunta cada vez.
