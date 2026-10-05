---
title: "Components"
weight: 50
description: "The server, the shared client library, the privileged helper, and the macOS, Linux and Windows apps."
---

{{< cards >}}
  {{< card link="server/" title="Server" icon="server" subtitle="claimward-vpn-server v0.1.0: the control plane on the gateway host." >}}
  {{< card link="client/" title="Client library" icon="collection" subtitle="claimward-vpn-client v0.2.1: what the apps and the server share." >}}
  {{< card link="helper/" title="Privileged helper" icon="shield-check" subtitle="The root or SYSTEM process that enrolls and owns the tunnel." >}}
  {{< card link="macos-app/" title="macOS app" icon="desktop-computer" subtitle="claimward-vpn-app-osx v0.1.0: menu-bar app, Svelte UI in a webview." >}}
  {{< card link="linux-app/" title="Linux app" icon="desktop-computer" subtitle="claimward-vpn-app-linux v0.1.0: window and tray in pure Go, systemd helper." >}}
  {{< card link="windows-app/" title="Windows app" icon="desktop-computer" subtitle="claimward-vpn-app-windows v0.1.0: window and tray in pure Go, helper service, Wintun." >}}
{{< /cards >}}
