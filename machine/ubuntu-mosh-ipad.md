# Always-on Ubuntu server via Tailscale and mosh from iPad

**Tailscale plus mosh is the most resilient way to maintain a persistent shell session from an iPad to a headless Ubuntu server.** Tailscale creates an encrypted WireGuard mesh network that punches through NAT and firewalls without port forwarding, while mosh keeps your terminal session alive across iPad sleep/wake cycles, cellular-to-WiFi transitions, and even device reboots. This guide covers every step from a fresh Ubuntu 24.04 install to typing `mosh myserver` on your iPad and having an indestructible connection.

---

## Step 1: Install Tailscale on Ubuntu 24.04

On a fresh Ubuntu 24.04 LTS (Noble Numbat) server, add the official Tailscale stable repository and install via apt. Do not use snap or third-party PPAs.

```bash
# Add Tailscale's GPG signing key
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
  | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null

# Add the stable repository for Ubuntu 24.04 (noble)
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
  | sudo tee /etc/apt/sources.list.d/tailscale.list

# Update and install
sudo apt-get update
sudo apt-get install -y tailscale
```

This installs two components: the `tailscaled` daemon and the `tailscale` CLI. If you prefer a single command, the official convenience script auto-detects your distro:

```bash
curl -fsSL https://tailscale.com/install.sh | sh
```

Verify the installation:

```bash
tailscale version
```

---

## Step 2: Authenticate and bring Tailscale online

The Tailscale daemon (`tailscaled`) is automatically enabled and started after package installation. Confirm it is running:

```bash
sudo systemctl status tailscaled
```

Now authenticate the server to your tailnet. You have two paths depending on whether you want interactive or fully automated authentication.

### Option A — Interactive login (simplest for a one-off server)

```bash
sudo tailscale up --operator=$USER --hostname=my-ubuntu-server
```

The CLI prints a URL like `https://login.tailscale.com/a/abc123xyz`. Open this URL in any browser (on your phone, laptop, iPad—anywhere), sign in with your identity provider (Google, GitHub, Apple, Microsoft, etc.), and approve the device. The terminal returns immediately once you authorize.

The `--operator=$USER` flag lets your normal user account run `tailscale` commands without `sudo` going forward. The `--hostname` flag sets the MagicDNS name you will use to connect from your iPad.

### Option B — Auth key for fully unattended provisioning

For servers you provision via scripts, cloud-init, or Ansible, generate a pre-authentication key so no browser interaction is needed.

1. Open the Tailscale admin console: **https://login.tailscale.com/admin/settings/keys**
2. Click **Generate auth key**.
3. Configure the key:
   - **Reusable**: No (one-off is safer for a single server).
   - **Ephemeral**: No (you want this device to persist).
   - **Tags**: Add `tag:server`. **Tagging a device automatically disables key expiry**, which is exactly what you want for an always-on server.
4. Copy the key (it starts with `tskey-auth-`).

Then on the server:

```bash
sudo tailscale up \
  --authkey=tskey-auth-kXYZ123EXAMPLE \
  --operator=$USER \
  --hostname=my-ubuntu-server \
  --advertise-tags=tag:server
```

The server joins your tailnet instantly with no browser flow. Because it is tagged `tag:server`, **key expiry is disabled by default**—the node never needs re-authentication.

> **Note on tags and ACLs**: Before using tags, you must define them in your tailnet policy file (ACLs) under `tagOwners`. For example:
> ```json
> "tagOwners": {
>   "tag:server": ["autogroup:admin"]
> }
> ```
> Without this, `--advertise-tags` will be rejected.

### Verify connectivity

```bash
tailscale status          # Lists all devices on your tailnet
tailscale ip -4           # Shows this server's Tailscale IPv4 (100.x.y.z)
```

---

## Step 3: Ensure Tailscale is persistent and survives reboots

The apt package automatically installs a systemd unit for `tailscaled`. It should already be enabled, but confirm and lock it down:

```bash
# Enable on boot and start now (idempotent if already running)
sudo systemctl enable --now tailscaled

# Verify it is enabled
systemctl is-enabled tailscaled
# Expected output: enabled

# Check it's active
systemctl is-active tailscaled
# Expected output: active
```

The service unit (`/lib/systemd/system/tailscaled.service`) is configured with `Restart=on-failure`, so if the daemon crashes it restarts automatically. After a reboot, `tailscaled` starts before most other services (it hooks into `network-pre.target`), and the node reconnects to your tailnet using its stored credentials in `/var/lib/tailscale/`. No re-authentication is needed.

**Enable automatic updates** so Tailscale stays current without manual intervention:

```bash
sudo tailscale set --auto-update
```

Tailscale stages updates for roughly one week after release to verify stability, then applies them automatically via apt.

---

## Step 4: Disable key expiry for always-on access

If you used a tagged auth key (Option B above), key expiry is already disabled. If you used interactive login (Option A), you must disable it manually:

1. Go to **https://login.tailscale.com/admin/machines**.
2. Find your server → click the **⋯** menu → **Disable key expiry**.

Without this, the node key expires after **180 days** and the server drops off your tailnet until you re-authenticate—a disaster for a headless machine. Disabling key expiry only removes the periodic SSO re-auth requirement; WireGuard data-plane keys still rotate automatically every few minutes.

For long-lived infrastructure that outlasts the 90-day maximum lifespan of auth keys, consider **OAuth clients** instead. Generate one at **https://login.tailscale.com/admin/settings/oauth**. OAuth client secrets can be used in place of `--authkey` and have no expiration limit.

---

## Optional: Create a new admin user with sudo and SSH access

If you do not already have a non-root user to connect as (for example on a fresh cloud image where you only have `root`), create a dedicated admin user before going further. Running mosh/SSH as a normal user with `sudo` is safer than logging in as `root` directly.

Run these commands as `root` (or with `sudo` from an existing admin account).

### Create the user

```bash
# Replace "youruser" with the username you want.
# --create-home makes /home/youruser; --shell sets bash as the login shell.
sudo adduser --gecos "" youruser
```

`adduser` is the friendly Ubuntu wrapper: it creates the home directory, copies skeleton dotfiles from `/etc/skel`, and interactively prompts you to set a password. The `--gecos ""` flag skips the optional "Full Name / Room Number" questions. If you prefer a fully non-interactive setup, use the lower-level `useradd` instead:

```bash
sudo useradd --create-home --shell /bin/bash youruser
sudo passwd youruser        # set the password when prompted
```

### Grant admin (sudo) privileges

On Ubuntu, members of the `sudo` group get full administrative rights. Add the new user to it:

```bash
sudo usermod -aG sudo youruser
```

Verify the membership:

```bash
groups youruser
# Expected to include: ... sudo ...
```

> **Optional — passwordless sudo**: If you want this user to run `sudo` without being prompted for a password (convenient for automation, slightly less secure), drop a sudoers file. Always edit sudoers with `visudo` so syntax errors can't lock you out:
> ```bash
> echo 'youruser ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/youruser
> sudo chmod 0440 /etc/sudoers.d/youruser
> sudo visudo -c          # validate syntax
> ```

### Make the user available over SSH

Any user with a valid shell and password (or an authorized key) can already log in over SSH — there is no per-user "enable SSH" switch in OpenSSH by default. To set up key-based access for the new user, create their `.ssh` directory and install a public key:

```bash
# Run as the new user, or fix ownership afterwards if run as root.
sudo install -d -m 700 -o youruser -g youruser /home/youruser/.ssh
sudo install -m 600 -o youruser -g youruser /dev/null /home/youruser/.ssh/authorized_keys

# Append the iPad/Blink public key (paste the full line):
echo "ssh-ed25519 AAAA... your-key-comment" \
  | sudo tee -a /home/youruser/.ssh/authorized_keys >/dev/null
```

If your `sshd_config` restricts logins with an `AllowUsers` or `AllowGroups` directive, you must add the new user (or their group) there too, then reload SSH:

```bash
# Check whether a restriction exists:
sudo grep -E '^(AllowUsers|AllowGroups)' /etc/ssh/sshd_config

# If AllowUsers is present, append the new user, e.g.:
#   AllowUsers existinguser youruser
sudo systemctl reload ssh
```

Now confirm you can log in as the new user from your iPad (or any SSH client) before locking down root access:

```bash
ssh youruser@my-ubuntu-server
sudo whoami        # should print: root
```

Once you have verified the new admin user works, proceed with the mosh/SSH setup below and use this username everywhere the guide says `youruser`.

---

## Step 5: Install and configure mosh and SSH on the server

Mosh uses SSH for its initial handshake (authentication, launching `mosh-server`, exchanging a session key), then switches to a UDP-based protocol for the ongoing session. You need both OpenSSH and mosh installed.

```bash
sudo apt update
sudo apt install -y openssh-server mosh
```

Verify both are working:

```bash
sudo systemctl enable --now ssh
systemctl is-active ssh       # Should say: active
mosh-server --version         # Should say: mosh 1.4.0
```

### Locale configuration (critical for mosh)

**Mosh requires a UTF-8 locale on the server.** This is the number-one cause of mosh connection failures. Ubuntu 24.04 usually has this set correctly, but verify and fix if needed:

```bash
locale | grep LANG
# Expected: LANG=en_US.UTF-8 (or another UTF-8 locale)
```

If it shows `POSIX`, `C`, or a non-UTF-8 locale:

```bash
sudo locale-gen en_US.UTF-8
sudo update-locale LANG=en_US.UTF-8
# Log out and back in, or: export LANG=en_US.UTF-8
```

### Clean up orphaned mosh sessions

Mosh-server processes linger indefinitely by default if a client disconnects ungracefully. Set a timeout by adding this to `/etc/environment`:

```bash
echo 'MOSH_SERVER_NETWORK_TMOUT=604800' | sudo tee -a /etc/environment
```

This tells mosh-server to self-terminate after **7 days** (604800 seconds) of no client contact. Adjust to taste.

### A note on Tailscale SSH versus standard SSH

Tailscale offers its own SSH server (`tailscale up --ssh`) that authenticates users via their tailnet identity—no SSH keys needed. While convenient, **Tailscale SSH has known compatibility issues with mosh**. Mosh expects a standard OpenSSH server for its handshake. For a reliable mosh setup, **use standard OpenSSH** and do not enable `--ssh`. You can always enable Tailscale SSH later for browser-based SSH access from the admin console without affecting mosh.

---

## Step 6: Firewall rules for Tailscale and mosh

### How Tailscale interacts with UFW

Since approximately August 2023, Tailscale automatically inserts iptables rules that **accept all inbound traffic on the `tailscale0` interface**. These rules operate at a lower level than UFW and effectively bypass it for any Tailscale-routed traffic. This means mosh's UDP ports (60001–60999) are already open for connections arriving over Tailscale, even if UFW blocks them on public interfaces.

### Recommended firewall configuration

The cleanest approach is to deny everything on public interfaces and explicitly allow all Tailscale traffic:

```bash
# Reset to clean defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow all traffic on the Tailscale interface (belt-and-suspenders)
sudo ufw allow in on tailscale0

# Optional: keep SSH open on public interface for emergency access
# sudo ufw allow 22/tcp

# Enable the firewall
sudo ufw enable
```

With this configuration, **your server has zero public-facing ports** (or just SSH if you uncomment that line), yet mosh, SSH, and every other service are fully accessible over Tailscale. This is the ideal security posture for a headless server.

Verify your rules:

```bash
sudo ufw status verbose
```

### If you also need mosh over the public internet

If you sometimes connect without Tailscale, open the mosh UDP range on the public interface:

```bash
sudo ufw allow 60000:61000/udp
sudo ufw allow 22/tcp
```

For tighter security with few concurrent sessions, restrict the range:

```bash
sudo ufw allow 60000:60010/udp    # Supports ~10 concurrent mosh sessions
```

---

## Step 7: iPad-side setup

Three things need to happen on the iPad: install Tailscale, install a mosh-capable terminal, and configure the connection.

### Install and configure Tailscale on iPad

1. Download **Tailscale** from the App Store (free).
2. Launch the app → tap **Get Started**.
3. Accept the iOS prompt to install a **VPN configuration** (this creates a system-level VPN profile).
4. Tap **Log in** and sign in with the **same identity provider and account** you used on the server.
5. After login, your iPad appears in the Tailscale admin console alongside your server.

Open the Tailscale app and confirm you see both your iPad and `my-ubuntu-server` (or whatever hostname you chose) in the device list. The server's **100.x.y.z** Tailscale IP is shown here.

**On iOS 18+**, add Tailscale to Control Center for quick VPN toggling: long-press an empty area in Control Center → add the Tailscale widget.

### Install Blink Shell (the best mosh client for iPad)

**Blink Shell** is the gold-standard mosh terminal for iOS/iPadOS. It is the most mature, most actively developed, and has purpose-built Tailscale integration.

- **Price**: $19.99/year (Blink+ plan). A 14-day free trial is available. Students get 75% off ($4.99/year).
- **Alternatives**: Termius (free tier available, ~$10/month for Pro) and Prompt 3 by Panic (~$29.99 one-time) also support mosh, but Blink has the best mosh implementation and unique features like auto-installing mosh-server on remote hosts.

Install **Blink Shell** from the App Store and start the trial or subscribe.

### Generate SSH keys in Blink

Since we are using standard OpenSSH (not Tailscale SSH), you need SSH keys:

1. Open Blink Shell, type `config` (or press **⌘ ,**).
2. Go to **Keys** → tap **+** → **Generate New**.
3. Choose **Ed25519** (recommended). Name it `id_ed25519`.
4. Tap **Generate**. The private key is stored in the iOS Keychain, protected by the Secure Enclave.
5. Tap on the key → **Copy Public Key**.

Now install the public key on your server. From Blink:

```
ssh-copy-id youruser@my-ubuntu-server
```

Or manually SSH in with a password and paste the key:

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA... your-key-comment" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

### Configure a saved host in Blink

For one-command access, save your server:

1. In Blink: `config` → **Hosts** → **+**
2. **Host**: `myserver` (the alias you will type)
3. **Hostname**: `my-ubuntu-server` (MagicDNS name) or `100.x.y.z`
4. **User**: your Linux username
5. **Key**: select the Ed25519 key you generated
6. Save.

Now connecting is just: `mosh myserver`

---

## Step 8: Connect from iPad via mosh over Tailscale

With everything configured, the daily workflow is simple:

1. **Ensure Tailscale is active** on your iPad (VPN toggle on in the Tailscale app or Control Center).
2. **Open Blink Shell**.
3. **Connect**:

```
mosh youruser@my-ubuntu-server
```

Or using the saved host alias:

```
mosh myserver
```

Or with an explicit Tailscale IP:

```
mosh youruser@100.64.1.23
```

Mosh SSHs into the server, launches `mosh-server`, exchanges an AES-128 session key and a UDP port number, then drops the SSH connection. From this point, all communication happens over a single UDP port, encrypted by both mosh's AES-128 and Tailscale's WireGuard layer.

**If mosh-server isn't installed on the server**, Blink has a unique trick:

```
mosh --install-static youruser@my-ubuntu-server
```

This downloads and installs a static `mosh-server` binary on the remote host without root access.

### Pair with tmux for bulletproof persistence

Mosh keeps your connection alive, but if `mosh-server` itself is killed (e.g., server reboot), the session is lost. Combine mosh with tmux for defense in depth:

```
mosh myserver -- tmux new-session -A -s main
```

This attaches to an existing tmux session named `main` or creates one. If the server reboots, `mosh-server` dies, but when you reconnect, `tmux new-session -A -s main` picks up right where you left off (tmux sessions survive as long as the tmux server process is running; for true reboot persistence, look into `tmux-resurrect`).

---

## Tips for rock-solid always-on connectivity

**Server-side hardening for reliability:**

- **Accept routes** if you need to reach other subnets advertised by other Tailscale nodes: `sudo tailscale set --accept-routes`. On Linux this defaults to off, unlike other platforms.
- **Lock SSH to key-based auth only** since the server is reachable exclusively over Tailscale. Edit `/etc/ssh/sshd_config`:
  ```
  PasswordAuthentication no
  PubkeyAuthentication yes
  ```
  Then `sudo systemctl restart ssh`.
- **Set a descriptive hostname** with `--hostname` during `tailscale up` so MagicDNS names are memorable. You can rename machines in the admin console too.
- **Monitor with journalctl**: `journalctl -u tailscaled -f` shows real-time Tailscale daemon logs. If connectivity drops, this is the first place to look.
- **For subnet routers or exit nodes only**: Enable IP forwarding (not needed for basic use):
  ```bash
  echo 'net.ipv4.ip_forward = 1' | sudo tee /etc/sysctl.d/99-tailscale.conf
  sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
  ```

**iPad-side tips for stable connections:**

- **Use `geo track` in Blink Shell**: Type `geo track` in the Blink prompt. This enables iOS location tracking, which grants Blink significantly more background execution time—iOS keeps location-aware apps alive longer. This is the single most effective trick for preventing iOS from killing Blink in the background.
- **MagicDNS is your friend**: Always connect by hostname rather than IP. MagicDNS resolution is local and instant (pushed to all devices, no TTL delays). If short names don't resolve, use the full FQDN: `my-ubuntu-server.tail1234.ts.net`.
- **Enable Tailscale notifications**: The iOS app alerts you when re-authentication is needed or the VPN disconnects.
- **iPad keyboard shortcuts in Blink**: **⌘ T** opens a new shell tab, **⌘ W** closes it, **⌘ 1-9** switches tabs. On an external keyboard, this makes Blink feel like a native terminal.

**Network resilience recap:**

| Scenario | What happens |
|---|---|
| iPad sleeps for hours | Mosh reconnects instantly on wake — session intact |
| Switch from WiFi to cellular | Mosh adapts seamlessly — UDP isn't tied to a TCP socket |
| Server reboots | Tailscale reconnects automatically; start a new mosh session (tmux session persists if tmux-server survived) |
| Tailscale key expires | Impossible if you disabled key expiry or used tags |
| ISP changes your public IP | Tailscale handles NAT traversal; no impact |

## TMUX persistant sessions

``` bash
cat >> ~/.bashrc << 'EOF'

# Auto-attach to tmux session over SSH
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ]; then
  tmux new-session -A -s main
fi
EOF
```

## Conclusion

The combination of Tailscale's zero-config WireGuard mesh and mosh's UDP-based roaming protocol solves the two hardest problems with remote access from an iPad: **getting through NAT/firewalls without port forwarding** and **surviving the aggressive background-process killing that iOS imposes on TCP connections**. By tagging the server during Tailscale setup, key expiry is automatically disabled. By using `ufw allow in on tailscale0` and denying everything else, the server exposes no public ports. And by pairing mosh with tmux, you get a session that survives network changes, device sleep, and even server reboots. The entire setup takes roughly 15 minutes, and the payoff is an iPad terminal experience that feels as reliable as sitting in front of the machine.