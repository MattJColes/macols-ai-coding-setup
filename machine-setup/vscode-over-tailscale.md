# VS Code Remote-SSH over Tailscale

Connect VS Code to your always-on Ubuntu server over Tailscale using Remote-SSH with password authentication.

---

## 1. Install the Remote-SSH extension

Open VS Code → Extensions (`Ctrl+Shift+X`) → search **Remote - SSH** (by Microsoft) → Install.

## 2. Configure your local SSH config

Edit `~/.ssh/config` on your local machine (macOS/Linux) or `C:\Users\you\.ssh\config` (Windows):

```
Host tailscale-hostname
    HostName tailscale-hostname
    User admin
```

The `HostName` is the Tailscale MagicDNS name. You can also use the Tailscale IP (`100.x.y.z`) or the full FQDN (`tailscale-hostname.tail1234.ts.net`).

## 3. Connect

1. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`).
2. Type **Remote-SSH: Connect to Host…**
3. Select `tailscale-hostname`.
4. VS Code prompts for the password for `admin` — enter it.
5. On first connect, VS Code installs its server component on the remote machine automatically.
6. Open any folder and you're working remotely with full IntelliSense, terminal, debugging, and extensions.
