# NEPTUNE Radar V3 for Linux

## Requirements

- Ubuntu 22.04 LTSC
- 1 vCPU core
- 4 GB RAM (maybe less will work but I didn't test)
- 50 GB NVMe disk space
- Internet access during install
- `sudo` access

## One-Line Install

Ubuntu / Debian:

```bash
curl -fsSL https://raw.githubusercontent.com/pubgdma/NEPTUNE-RADAR-LINUX-V3/main/install-from-github.sh | sudo bash
```

Default install path:
- `/opt/neptune-radar`

Default service:
- `neptune-radar`

Use the radar in a desktop or mobile browser.
- Desktop browsers open the normal desktop layout automatically.
- Mobile phones open the mobile layout automatically.
- If needed, you can force a view manually:
  - Desktop: http://ipFromVPS:7823/?view=desktop
  - Mobile: http://ipFromVPS:7823/?view=mobile
- The default radar address stays: http://ipFromVPS:7823/


## Manual Local Install

From the radar folder:

```bash
sudo ./install-ubuntu.sh
```

## Start / Stop

Start manually:

```bash
./start-radar.sh
```

Stop manually:

```bash
./stop-radar.sh
```

Important:
- keep the terminal or systemd service running while using the radar
- `start-radar.sh` is the Linux launcher
- enabled instances are read from `config/config.toml`

Systemd:

```bash
sudo systemctl start neptune-radar
sudo systemctl stop neptune-radar
sudo systemctl restart neptune-radar
journalctl -u neptune-radar -f
```

## Web Radar Connection

In Neptune, connect to:
- IP: `127.0.0.1`
- Port: the enabled instance port from `config/config.toml`

Default browser URL:
- `http://127.0.0.1:7823`

If you run the radar on a VPS, LAN, or VPN:
- keep `ip = "0.0.0.0"`

## Multiple Instances

Edit:
- `config/config.toml`

Example:

```toml
[server]
ip = "0.0.0.0"

[[instances]]
id = "7823"
port = 7823
enabled = true

[[instances]]
id = "7824"
port = 7824
enabled = true

[[instances]]
id = "7825"
port = 7825
enabled = false
```

Rules:
- each instance must use a unique port
- every instance with `enabled = true` will start
- `start-radar.sh` launches all enabled instances

Examples:
- one enabled instance = one radar
- three enabled instances = three radars

Browser examples:
- `http://127.0.0.1:7823`
- `http://127.0.0.1:7824`

## Password Protection

Edit:
- `config/password.toml`

Disabled:

```toml
password = ""
```

Enabled:

```toml
password = "MySecret123"
```

Behavior:
- empty password = no login page
- non-empty password = browser login required

## Updating

Run:

```bash
./update-radar.sh
```

This updates the Linux package files while keeping local runtime/config files in place.
It also removes stale empty folders that do not exist in GitHub anymore.

## Uninstall

Run:

```bash
sudo ./uninstall-ubuntu.sh
```
