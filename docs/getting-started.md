# Getting started

This walks through standing up a gateway and connecting your first device. It
assumes a Linux host for the gateway and any OIDC provider you control.

## 1. Prepare the WireGuard gateway (Linux)

Create the `wg0` interface with a server key and a listen port. Claimward manages
*peers* on this interface; it does not create the interface itself.

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

## 2. Run the control plane

```sh
export AUTH_PROVIDER=github                     # default
export GITHUB_ALLOWED_ORGS=claimward            # optional authz (recommended)
export WG_ENDPOINT=vpn.example.com:51820
export WG_PRIVATE_KEY_FILE=/etc/wireguard/server.key
export VPN_CIDR=10.80.0.0/24
export TLS_CERT=/etc/claimward/fullchain.pem   # or terminate TLS at a proxy
export TLS_KEY=/etc/claimward/privkey.pem

go run github.com/claimward/claimward-vpn-server/cmd/claimward-server@latest
```

See the [server reference](components/server.md) for every variable. For local
experiments without a real interface, set `WG_DRYRUN=true`. To use OIDC instead
of GitHub, set `AUTH_PROVIDER=oidc` with `OIDC_ISSUER` / `OIDC_CLIENT_ID`.

## 3. Register the OAuth client

=== "GitHub (default)"

    Create a GitHub **OAuth App** (org or personal) and **enable Device Flow**
    in its settings. Only the **client id** is needed by clients — no secret.
    Scopes used: `read:user`, `user:email`, `read:org`.

=== "OIDC"

    In your IdP, create a **native/public** client with PKCE enabled and the
    loopback redirect `http://127.0.0.1:<port>/callback`. No client secret.

## 4. Connect a device

=== "CLI"

    ```sh
    export CLAIMWARD_SERVER=https://vpn.example.com
    export CLAIMWARD_GITHUB_CLIENT_ID=Iv1.0123456789abcdef   # GitHub OAuth app

    claimward login            # GitHub device flow: open the URL, enter the code
    sudo -E claimward connect  # enroll + bring up the tunnel
    ```

=== "macOS app"

    Configure `~/Library/Application Support/Claimward/config.json`, install the
    helper (`sudo ./scripts/install-helper.sh`), launch the app and click
    **Connect**. See the [macOS app guide](components/macos-app.md).

You should now have a `utun`/`wg` interface with your assigned `10.80.0.x`
address and a route into the private network.
