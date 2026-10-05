---
title: "Protocole d'enrôlement"
linkTitle: "Protocole d'enrôlement"
weight: 1
description: "L'API HTTP entre le helper d'un appareil et claimward-vpn-server, ses erreurs, et le RouteService gRPC."
tags: [protocole, serveur, grpc]
---

Le contrat d'échange entre les clients et le serveur. Il est défini une seule fois dans
[`claimward-vpn-client/pkg/protocol`](https://github.com/claimward/claimward-vpn-client/tree/main/pkg/protocol)
(HTTP) et `proto/routes/v1/routes.proto` (gRPC), et importé par les deux côtés.

Chaque requête authentifiée envoie le jeton porteur (bearer) de la personne sous la forme
`Authorization: Bearer <token>`, jamais dans le corps : un **jeton d'accès OAuth
GitHub** (`AUTH_PROVIDER=github`), un **jeton d'identité (ID token) OIDC** (`oidc`), ou un
**jeton d'accès go-authn** (`go-authn`). Les corps de requête sont en JSON, d'au plus
64 Kio, et les champs inconnus sont refusés.

## `POST /api/v1/enroll`

Requête :

```json
{
  "public_key": "<wireguard base64 public key>",
  "device": { "name": "alice-mbp", "os": "darwin", "platform": "app-osx" },
  "tenant": "hpc"
}
```

`tenant` est facultatif : sans lui, le serveur utilise l'unique locataire de la personne.
Les helpers envoient `os` `darwin`, `linux` ou `windows` et `platform`
`app-osx`, `app-linux` ou `app-windows`.

Réponse `200` :

```json
{
  "assigned_ip": "10.80.0.5/32",
  "server_public_key": "<base64>",
  "endpoint": "vpn.example.com:51820",
  "allowed_ips": ["10.80.0.0/24"],
  "dns": ["10.80.0.1"],
  "grpc_endpoint": "vpn.example.com:8444",
  "persistent_keepalive": 25,
  "lease_expires_at": "2026-10-06T10:00:00Z"
}
```

`allowed_ips` et `dns` sont ceux du locataire. `dns` est omis lorsque le locataire n'en a
aucun, `grpc_endpoint` lorsque le serveur n'annonce aucun RouteService
(`GRPC_ENDPOINT`). Le protocole comporte aussi un `mtu` facultatif, que le serveur
(v0.2.0) ne définit jamais.

## `GET /api/v1/tenants`

Réponse `200` : les locataires auxquels l'appelant peut se connecter.

```json
[ { "id": "default", "name": "Default" } ]
```

## `POST /api/v1/heartbeat`

```json
{ "public_key": "<base64>" }
```

Réponse `200` : `{ "lease_expires_at": "..." }`. `404 not_enrolled` si la clé
n'est pas enrôlée par l'appelant, `403 not_a_member` dès que la personne a quitté le
locataire de la session, `403 key_not_registered` (go-authn) dès que le fournisseur ne
répertorie plus la clé.

## `POST /api/v1/deregister`

```json
{ "public_key": "<base64>" }
```

Réponse `204`, y compris pour une clé qui n'est pas enrôlée. `403 not_owner` si la clé
appartient à une autre personne.

## `GET /healthz`

Réponse `200` : `{ "status": "ok" }`, sans authentification.

## Erreurs {#errors}

Les réponses autres que 2xx portent :

```json
{ "error": "invalid_token", "message": "…" }
```

| Code | Statut | Signification |
|------|--------|---------|
| `missing_token` / `invalid_token` | 401 | pas de jeton porteur, ou la vérification du fournisseur a échoué (y compris une liste d'organisations ou de domaines autorisés) |
| `bad_public_key` / `bad_request` | 400 | entrée mal formée |
| `key_not_registered` | 403 | go-authn : la clé n'est pas enregistrée chez le fournisseur par cette personne |
| `not_a_member` | 403 | le locataire demandé ne fait pas partie de ceux de l'appelant, ou n'en fait plus partie |
| `not_owner` | 403 | désinscription : la clé appartient à une autre personne |
| `not_enrolled` | 404 | heartbeat : aucun enrôlement de cette clé par l'appelant |
| `key_taken` | 409 | enrôlement : la clé est enrôlée par une autre personne |
| `tenant_required` | 409 | enrôlement : l'appelant appartient à plusieurs locataires et n'en a nommé aucun ; le message les énumère |
| `pool_exhausted` | 503 | aucune adresse libre dans `VPN_CIDR` |
| `gateway_error` | 500 | le pair n'a pas pu être ajouté à WireGuard |

## RouteService (gRPC)

```protobuf
package claimward.routes.v1;

service RouteService {
  rpc Watch(WatchRequest) returns (stream RouteUpdate);
}
message WatchRequest { string public_key = 1; }
message RouteUpdate {
  repeated string allowed_ips = 1;
  repeated string dns = 2;
  uint64 serial = 3;   // increases on each change
}
```

Le serveur écoute sur `GRPC_ADDR` et annonce `GRPC_ENDPOINT` dans la
réponse d'enrôlement. Le jeton porteur circule dans les métadonnées,
`authorization: Bearer <token>`, et est vérifié comme pour l'API HTTP. `Watch`
envoie immédiatement l'ensemble courant, puis un nouveau à chaque modification des routes du locataire,
pour le locataire **dans lequel l'appareil s'est enrôlé**, retrouvé par `public_key`,
qui doit être enrôlée par l'appelant (`NOT_FOUND` sinon,
`PERMISSION_DENIED` dès que la personne a quitté ce locataire).

Le serveur le sert en TLS avec `TLS_CERT`/`TLS_KEY`. Les clients
(`pkg/routeclient`) lui parlent en TLS, vérifié par rapport aux autorités racines du système,
sauf vers une adresse de boucle locale, et refusent un service en clair.
