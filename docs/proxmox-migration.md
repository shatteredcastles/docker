# Proxmox + NAS migration checklist

Moving `hs` from bare-metal Ubuntu to Proxmox on the MS-01, splitting out Home Assistant and DNS, and later moving storage from the Synology to a DIY Unraid NAS.

Tick boxes as you go (`- [x]`). Each phase says whether services go down.

## Target layout

```
MS-01 · Proxmox VE (ZFS mirror on 2× SN850X)
 ├─ CT 100  dns    Debian LXC: AdGuard Home + Tailscale subnet router
 ├─ VM 101  haos   Home Assistant OS + Mosquitto, Piper (and Whisper) apps
 ├─ VM 102  hs     Ubuntu Server + Docker: this repo, iGPU passed through
 ├─ Kingston NVMe  Frigate recordings (after the old Ubuntu is retired)
 └─ Host: NUT (UPS over USB), SMART, backups to NAS
```

Start order: `dns` (1) → `haos` (2) → `hs` (3).

## IP plan

| What | IP | Notes |
|---|---|---|
| Router | 192.168.0.1 | Gateway |
| Synology | 192.168.0.2 | Existing |
| Hue bridge | 192.168.0.5 | Existing, **don't reuse** |
| Proxmox host `pve` | **192.168.0.10** | New. Web UI: `https://192.168.0.10:8006` |
| `dns` LXC | **192.168.0.53** | New. AdGuard + Tailscale |
| `hs` VM | **192.168.0.56** | Same as today, so port forwards, NFS permissions and integrations keep working |
| `haos` VM | **192.168.0.57** | New. Was `192.168.0.56:8123` |
| Storage link (later) | 10.10.10.0/24 | 10G DAC between the MS-01 and the NAS |

MS-01 network ports (MAC → chip):
- `58:47:ca:78:bc:68`: I226-V 2.5G, **the port you use today**
- `58:47:ca:78:bc:69`: I226-LM 2.5G, vPro/AMT capable (unused)
- 2× X710 SFP+ 10G (unused, for the NAS link later)

---

## Phase 0: Preparation (no downtime)

### 0.1 Reserve the IPs
- [ ] In the router admin, check the DHCP client list: `.10`, `.53` and `.57` must be unused. They didn't answer a ping on 2026-10-30, but the router is the source of truth.
- [ ] Make sure those three addresses are **outside the DHCP pool**. If they're inside, shrink the pool or create reservations for them.
- [ ] Find where the router sets the **DNS server handed out by DHCP**. Today it's probably `192.168.0.56`, and it changes to `192.168.0.53` in Phase 2.

### 0.2 Back up everything that isn't in git
- [ ] `sudo crontab -l`: confirm `backup-all.sh` is scheduled. Write down the line.
- [ ] Run it once: `sudo ~/docker/scripts/hs/backup-all.sh`, then check `~/synology/data/backups/hs/` for fresh dumps.
- [ ] Commit the repo, including the untracked Lidarr and Navidrome files: `git status`, then `git add`, `git commit`, `git push`.
- [ ] Copy host config and secrets to the NAS. **`.env` and `secrets/` are not in git or in backup-all.**
  ```bash
  D=~/synology/data/backups/hs/host-config
  mkdir -p $D && chmod 700 $D
  cp ~/docker/.env $D/
  sudo cp -r ~/docker/secrets $D/     # sudo: some secret files are root-only
  sudo cp /etc/fstab /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml $D/
  sudo cp -r /srv/telegraf-scripts $D/
  sudo cp ~/docker/appdata/adguard/conf/AdGuardHome.yaml $D/
  crontab -l > $D/crontab-james.txt
  sudo crontab -l > $D/crontab-root.txt
  grep -E '^(docker|render|video):' /etc/group > $D/groups.txt
  sudo chown -R james:james $D
  ```
  The old Ubuntu drive stays untouched until Phase 3, so this is a convenience copy, not your only copy.

### 0.3 Find every MQTT client
Mosquitto moves to `192.168.0.57`, so anything that connects to it has to be repointed.
- [ ] `docker logs mosquitto 2>&1 | grep -i 'new client' | grep -oE 'from [0-9.]+.* as [^ ]+' | sort -u`
- [ ] Write down anything other than Frigate and Home Assistant. Each one needs its broker address changed in Phase 2.

### 0.4 Get the installer and tools ready
- [ ] Download the latest **Proxmox VE 9.x ISO** from https://www.proxmox.com/en/downloads.
- [ ] Write it to a USB stick (2 GB or more) with Balena Etcher. In Rufus, use **DD mode**.
- [ ] Download the latest **MS-01 BIOS** from Minisforum's support page and follow its USB instructions (optional, but recommended).
- [ ] Have an HDMI monitor and a USB keyboard for the MS-01.
- [ ] Save a strong **Proxmox root password** in Vaultwarden.
- [ ] Optional: practise by installing Proxmox in a VM with virt-manager on the current box, using 8 GB RAM and 2 disks.

### 0.5 Prepare the repo changes on a branch (ask Claude)
These stay on a `proxmox-migration` branch and get merged during Phase 2:
- [ ] `stack.yml`: remove `homeassistant.yml`, `mosquitto.yml`, `piper.yml` and `adguard.yml`.
- [ ] `peanut.yml`: remove the `nut-server` service and set `NUT_HOST=192.168.0.10`.
- [ ] `appdata/traefik3/rules/hs/app-haos-no-auth.yml`: change the `haos-svc` URL to `http://192.168.0.57:8123`.
- [ ] New Traefik file rule for AdGuard pointing to `http://192.168.0.53:80`, plus a Homepage entry.
- [ ] `appdata/frigate/config/config.yml`: set `mqtt.host` to `192.168.0.57`, and drop recording retention to 1 day for now.
- [ ] Update the README host table: Proxmox VM, not "Proxmox LXC".

---

## Phase 1: Install Proxmox and build the guests (downtime: 2–3 h, then back to Ubuntu)

At the end of this phase you boot back into the old Ubuntu. Nothing on the Kingston gets changed.

### 1.1 Shut down cleanly
- [ ] Tell the household that DNS and Home Assistant will be down. Optionally set the router's secondary DHCP DNS to `1.1.1.1` for the evening.
- [ ] `cd ~/docker && docker compose down`
- [ ] `sudo shutdown -h now`, then unplug power.

### 1.2 Install the drives
- [ ] Open the MS-01 (see the Minisforum manual). Check the slot labels against the manual:
  - **PCIe 4.0 x4 slot** (the one that also takes U.2/22110): SN850X #1. If it has an **M.2/U.2 switch**, set it to **M.2**.
  - **PCIe 3.0 x4 slot**: SN850X #2
  - **PCIe 3.0 x2 slot**: the existing Kingston (move it here if it isn't already)
- [ ] Optional, for AMT later: move the LAN cable to the **other** 2.5G port (the I226-LM, MAC `...:bc:69`). If you skip this, leave it where it is.

### 1.3 BIOS (press `Del` at power-on; `F7` is the boot menu)
- [ ] Flash the BIOS update first, if you downloaded one.
- [ ] **Intel VMX / Virtualization**: Enabled
- [ ] **VT-d**: Enabled
- [ ] **SR-IOV support**: Enabled, if the option exists
- [ ] Integrated graphics: leave enabled
- [ ] **Secure Boot**: Disabled
- [ ] **Restore on AC power loss**: Power On (or Last State)
- [ ] Save and exit.

### 1.4 Install Proxmox
- [ ] Boot the USB stick (`F7`), then choose **Install Proxmox VE (Graphical)**.
- [ ] **Target harddisk** → **Options**:
  - Filesystem: **zfs (RAID1)**
  - Harddisk 0: WD_BLACK SN850X 1TB
  - Harddisk 1: WD_BLACK SN850X 1TB
  - Harddisk 2: **`-- do not use --`**. This is the Kingston, so **double-check it.**
  - Advanced: `ashift=12`, compress `on`. Leave the rest at defaults.
- [ ] Location: United States / `America/Denver` / U.S. keyboard.
- [ ] Password: the one from 0.4. Email: your address (used for alerts).
- [ ] Management network:
  - Interface: the one showing a **link** (MAC `...:bc:68`, or `...:bc:69` if you moved the cable)
  - Hostname: `pve.shatteredcastle.com`
  - IP: `192.168.0.10/24`
  - Gateway: `192.168.0.1`
  - DNS: `192.168.0.1` (the router; Proxmox shouldn't depend on its own DNS container)
- [ ] Install, pull the USB stick when prompted, and let it reboot.
- [ ] From your laptop, open `https://192.168.0.10:8006` and accept the certificate warning. Log in as `root`, realm **Linux PAM**.

### 1.5 First-time setup
- [ ] **pve → Updates → Repositories**:
  - Select `pve-enterprise` → **Disable**
  - Select the `ceph ... enterprise` entry → **Disable**
  - **Add** → **No-Subscription** → Add
- [ ] **pve → Updates → Refresh**, then **Upgrade** (a shell opens; answer `Y`). Reboot if a new kernel was installed.
- [ ] **pve → Shell**: `zpool status` should show `rpool` as a `mirror-0` with both SN850Xs `ONLINE`.

### 1.6 Backup storage on the Synology
- [ ] Synology DSM: **Control Panel → Shared Folder → Create**, name `proxmox`, on volume1.
- [ ] Edit `proxmox` → **NFS Permissions → Create**:
  - Hostname/IP: `192.168.0.10`
  - Privilege: Read/Write
  - Squash: **Map all users to admin**
  - Security: sys
  - ✓ Enable asynchronous, ✓ Allow connections from non-privileged ports, ✓ Allow users to access mounted subfolders
- [ ] Proxmox: **Datacenter → Storage → Add → NFS**:
  - ID: `synology`
  - Server: `192.168.0.2`
  - Export: `/volume1/proxmox` (choose it from the dropdown)
  - Content: **VZDump backup file**, **ISO image**

### 1.7 Prepare the host for GPU passthrough
Run these in **pve → Shell**.
- [ ] `lspci -nn | grep -i vga`: expect `00:02.0 ... Raptor Lake-P [Iris Xe Graphics] [8086:a7a0]`.
- [ ] Turn on the IOMMU on the kernel command line:
  ```bash
  proxmox-boot-tool status
  ```
  - If it says **systemd-boot** (the usual case for ZFS with Secure Boot off): `nano /etc/kernel/cmdline`, add ` intel_iommu=on iommu=pt` to the end of the single line, then run `proxmox-boot-tool refresh`.
  - If it says **grub**: `nano /etc/default/grub`, add `intel_iommu=on iommu=pt` inside `GRUB_CMDLINE_LINUX_DEFAULT="..."`, then run `update-grub`.
- [ ] Hand the iGPU to VFIO instead of the host driver:
  ```bash
  printf 'vfio\nvfio_iommu_type1\nvfio_pci\n' >> /etc/modules
  echo 'options vfio-pci ids=8086:a7a0' > /etc/modprobe.d/vfio.conf
  echo 'softdep i915 pre: vfio-pci'   >> /etc/modprobe.d/vfio.conf
  echo 'blacklist i915' > /etc/modprobe.d/blacklist-i915.conf
  update-initramfs -u -k all
  reboot
  ```
  The HDMI output goes black partway through boot from now on. That's expected; use the web UI.
- [ ] Check it worked:
  - `dmesg | grep -iE 'DMAR|IOMMU' | head` shows the IOMMU enabled
  - `lspci -nnk -s 00:02.0` shows `Kernel driver in use: vfio-pci`

### 1.8 Create the `hs` VM (ID 102)
- [ ] Download the installer: **pve → local (pve) → ISO Images → Download from URL**. Paste the **Ubuntu Server 26.04 LTS** ISO link from https://ubuntu.com/download/server, click **Query URL**, then **Download**. 24.04 LTS is also fine.
- [ ] Click **Create VM** (top right):
  - **General**: VM ID `102`, Name `hs`. Under Advanced: ✓ Start at boot, Start/Shutdown order `3`, Startup delay `30`.
  - **OS**: the Ubuntu ISO, type Linux 6.x kernel.
  - **System**:
    - Machine **q35**, BIOS **OVMF (UEFI)**
    - ✓ Add EFI Disk on `local-zfs`, **✗ Pre-Enroll keys**
    - SCSI controller **VirtIO SCSI single**, ✓ QEMU Agent
  - **Disks**: SCSI, `local-zfs`, **500 GiB**, ✓ Discard, ✓ IO thread. Under Advanced: ✓ SSD emulation.
  - **CPU**: 1 socket, **14 cores**, Type **host**.
  - **Memory**: **22528 MiB**. Under Advanced: **✗ Ballooning device** (required for passthrough).
  - **Network**: Bridge `vmbr0`, Model VirtIO, **✗ Firewall**.
  - Finish. Don't add the GPU yet.
- [ ] Start the VM and open **Console**. In the Ubuntu installer:
  - Type: **Ubuntu Server** (not minimized)
  - Network: edit `ens18` → IPv4 **Manual**:
    - Subnet `192.168.0.0/24`
    - Address `192.168.0.56`
    - Gateway `192.168.0.1`
    - Nameservers `192.168.0.1` (changes to `.53` in Phase 2)
  - Storage: Use an entire disk, and **untick "Set up this disk as an LVM group"**. Ubuntu's default LVM setup only uses about 100 GB of the disk.
  - Profile:
    - Your name: James
    - Server name: `hs`
    - Username: **`james`** (this gives UID 1000, which matches `PUID`)
  - ✓ Install OpenSSH server. Optionally import your keys from GitHub user `jimjam127`.
  - Featured snaps: none.
- [ ] When it finishes: **Hardware → CD/DVD Drive → Edit → Do not use any media**, then reboot.
- [ ] From your laptop: `ssh james@192.168.0.56`, then:
  ```bash
  sudo apt update && sudo apt full-upgrade -y
  sudo apt install -y qemu-guest-agent nfs-common rsync git curl \
      intel-media-va-driver-non-free vainfo intel-gpu-tools
  sudo systemctl enable --now qemu-guest-agent
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker james
  sudo shutdown -h now
  ```
- [ ] Add the GPU: **102 → Hardware → Add → PCI Device → Raw Device → `0000:00:02.0`**:
  - ✗ All Functions
  - Under Advanced: ✓ ROM-Bar, ✓ PCI-Express, **✗ Primary GPU** (this keeps the web console working)
- [ ] Start the VM, SSH in, and check the GPU:
  ```bash
  ls -l /dev/dri                      # expect card* and renderD128
  sudo vainfo --display drm --device /dev/dri/renderD128   # lists H264/HEVC/VP9/AV1 profiles
  sudo intel_gpu_top                  # opens without error (q to quit)
  sudo dmesg | grep -iE 'i915|guc|huc' | tail
  ```
  - [ ] GuC and HuC should both show as loaded/authenticated. If HuC isn't loaded:
    ```bash
    echo 'options i915 enable_guc=3' | sudo tee /etc/modprobe.d/i915.conf
    sudo update-initramfs -u && sudo reboot
    ```
- [ ] **If the GPU doesn't work, stop and don't continue to Phase 2.** Boot back into Ubuntu (see 1.11) and work out the GPU first. Fallbacks, in order:
  1. **SR-IOV**: undo 1.7 (the vfio and blacklist files) and follow the `strongtz/i915-sriov-dkms` README on the host and in the VM.
  2. **Run Docker in a privileged LXC** instead of a VM, with `/dev/dri` bind-mounted in and NFS mounted on the host.

### 1.9 Create the `dns` LXC (ID 100)
- [ ] Get the template: **pve → local → CT Templates → Templates → `debian-13-standard`** → Download.
- [ ] Click **Create CT**:
  - **General**: CT ID `100`, Hostname `dns`, ✓ Unprivileged, ✓ Nesting, root password.
  - **Template**: debian-13-standard.
  - **Disks**: `local-zfs`, 8 GiB.
  - **CPU**: 1. **Memory**: 1024 MiB, Swap 512 MiB.
  - **Network**:
    - Bridge `vmbr0`
    - IPv4 **Static**: `192.168.0.53/24`, Gateway `192.168.0.1`
  - **DNS**: use host settings. Don't start it yet.
- [ ] **100 → Options**: ✓ Start at boot, Start/Shutdown order `1`.
- [ ] Give it the tunnel device Tailscale needs (pve Shell):
  ```bash
  cat >> /etc/pve/lxc/100.conf <<'EOF'
  lxc.cgroup2.devices.allow: c 10:200 rwm
  lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
  EOF
  pct start 100
  ```
- [ ] Install AdGuard Home (`pct enter 100`):
  ```bash
  apt update && apt full-upgrade -y && apt install -y curl
  curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v
  exit
  ```
- [ ] Copy your current AdGuard config from the old drive (pve Shell):
  ```bash
  lsblk -o NAME,SIZE,MODEL            # find the KINGSTON drive; root is partition 2
  mkdir -p /mnt/old && mount -o ro /dev/nvmeXn1p2 /mnt/old     # X = the Kingston
  pct exec 100 -- systemctl stop AdGuardHome
  pct push 100 /mnt/old/home/james/docker/appdata/adguard/conf/AdGuardHome.yaml /opt/AdGuardHome/AdGuardHome.yaml --perms 600
  pct exec 100 -- systemctl start AdGuardHome
  ```
- [ ] Open the AdGuard UI at `http://192.168.0.53` (or the port set under `http: address:` in the YAML).
  - If DNS-over-TLS (port 853) was set up with certificate paths from the old container, turn encryption off under **Settings → Encryption**, or fix the paths.
- [ ] **Filters → DNS rewrites**: make sure `*.shatteredcastle.com` → `192.168.0.56` exists (and the same for `*.shatteredcastles.com`). This keeps LAN traffic local instead of going out to the router and back.
- [ ] Test from your laptop: `nslookup google.com 192.168.0.53` and `nslookup jellyfin.shatteredcastle.com 192.168.0.53` (the second should return `.56`).
- [ ] Install Tailscale as a subnet router (`pct enter 100`):
  ```bash
  curl -fsSL https://tailscale.com/install.sh | sh
  printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' > /etc/sysctl.d/99-tailscale.conf
  sysctl -p /etc/sysctl.d/99-tailscale.conf
  tailscale up --advertise-routes=192.168.0.0/24 --accept-dns=false
  ```
  Open the login link it prints.
- [ ] In the Tailscale admin console:
  - **Machines → dns → Edit route settings** → approve `192.168.0.0/24`
  - **⋯ → Disable key expiry**
- [ ] **Tailscale admin → DNS → Nameservers → Add nameserver → Custom** → `192.168.0.53`, then ✓ **Override local DNS**.

### 1.10 Create the `haos` VM (ID 101)
- [ ] pve Shell: download the latest Home Assistant OS image and create the VM:
  ```bash
  cd /root
  VER=$(curl -s https://api.github.com/repos/home-assistant/operating-system/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
  echo "HAOS $VER"
  wget "https://github.com/home-assistant/operating-system/releases/download/${VER}/haos_ova-${VER}.qcow2.xz"
  xz -d "haos_ova-${VER}.qcow2.xz"

  qm create 101 --name haos --machine q35 --bios ovmf --ostype l26 \
    --cores 2 --cpu host --memory 4096 --balloon 0 \
    --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-single \
    --agent enabled=1 --onboot 1 --startup order=2
  qm set 101 --efidisk0 local-zfs:1,efitype=4m,pre-enrolled-keys=0
  qm set 101 --scsi0 "local-zfs:0,import-from=/root/haos_ova-${VER}.qcow2,discard=on,ssd=1,iothread=1"
  qm resize 101 scsi0 64G
  qm set 101 --boot order=scsi0
  rm "/root/haos_ova-${VER}.qcow2"
  qm start 101
  ```
  Secure Boot keys are off on purpose (`pre-enrolled-keys=0`), because HAOS won't boot with them.
- [ ] **101 → Console**: wait for the `ha >` prompt. That takes a few minutes on first boot.
- [ ] Give it a static IP from that console:
  ```
  ha network info          # note the interface name, e.g. enp0s18 or enp6s18
  ha network update <iface> --ipv4-method static \
    --ipv4-address 192.168.0.57/24 --ipv4-gateway 192.168.0.1 --ipv4-nameserver 192.168.0.53
  ```
- [ ] Open `http://192.168.0.57:8123`. It should show the onboarding screen. **Don't create a user or finish onboarding.** You'll restore your backup in Phase 2.

### 1.11 Boot back into Ubuntu
- [ ] pve Shell: `umount /mnt/old`, then **pve → Shutdown**.
- [ ] Power on and press `F7`. Choose the **ubuntu** entry on the Kingston.
- [ ] In the BIOS (`Del`), put the **ubuntu** entry first for now, so a power cut brings back the old system.
- [ ] Check that everything is back up: `dcps`, Home Assistant and DNS.

---

## Phase 2: Cutover (downtime: 2–4 h)

### 2.1 On the old Ubuntu, just before shutting down
- [ ] **Home Assistant backup**: Settings → System → Backups → **Backup now** → full backup, including the database. **Download** the `.tar` to your laptop.
- [ ] Save the **backup encryption key**: Settings → System → Backups → ⋮ → **Encryption key** → download the emergency kit. You can't restore without it.
- [ ] `sudo ~/docker/scripts/hs/backup-all.sh`
- [ ] Commit and push anything left in the repo.
- [ ] `cd ~/docker && docker compose down && sudo shutdown -h now`

### 2.2 Boot Proxmox and copy the data across
- [ ] Power on, open the BIOS (`Del`), put **Linux Boot Manager / proxmox** first, and save.
- [ ] Proxmox boots `dns`, then `haos`, then `hs`.
- [ ] pve Shell: `mount -o ro /dev/nvmeXn1p2 /mnt/old` (the Kingston, as in 1.9).
- [ ] In the `hs` VM, pull the data across. Root SSH on pve is allowed by default.
  ```bash
  sudo rsync -aHAX --numeric-ids --info=progress2 \
      root@192.168.0.10:/mnt/old/home/james/docker/ /home/james/docker/
  sudo rsync -aHAX --numeric-ids root@192.168.0.10:/mnt/old/srv/telegraf-scripts/ /srv/telegraf-scripts/
  rsync -a root@192.168.0.10:/mnt/old/home/james/Pictures/ ~/Pictures/
  rsync -a root@192.168.0.10:/mnt/old/home/james/Desktop/  ~/Desktop/      # optional
  mkdir -p ~/data/video/frigate     # recordings start fresh; the old ones stay on the Kingston
  ```
  About 160 GB, NVMe to NVMe. Expect 10–20 minutes.

### 2.3 Recreate the host setup in the `hs` VM
- [ ] NAS mounts:
  ```bash
  mkdir -p ~/synology/{data,media,downloads}
  ssh root@192.168.0.10 "grep 192.168.0.2 /mnt/old/etc/fstab" | sudo tee -a /etc/fstab
  sudo systemctl daemon-reload && sudo mount -a && df -h | grep synology
  ```
  The Synology already allows `192.168.0.56`, so no NAS changes are needed.
- [ ] Cron jobs:
  - `crontab -e` → add the `update-containers.sh` line (it's in `crontab-james.txt` from 0.2)
  - `sudo crontab -e` → add the root lines (`crontab-root.txt`, or `/mnt/old/var/spool/cron/crontabs/root` on pve)
- [ ] Shell aliases: add the line from the README to `~/.bashrc`.
- [ ] Group IDs (they're different on a fresh install):
  ```bash
  getent group render video docker              # new IDs
  ssh root@192.168.0.10 "grep -E '^(docker|render|video):' /mnt/old/etc/group"   # old IDs
  ```
  - [ ] `compose/hs/jellyfin.yml` `group_add`: replace `"992"` with the new **render** ID and `"44"` with the new **video** ID.
  - [ ] `.env`: set `DGID` to the new ID of whichever group `984` was before (most likely `docker`).
- [ ] Set the VM's DNS to AdGuard: `sudo nano /etc/netplan/50-cloud-init.yaml` (or whichever file is in `/etc/netplan/`). Under `nameservers:` → `addresses:`, make the list `192.168.0.53` then `192.168.0.1`. Then run `sudo netplan apply`.
- [ ] Merge the `proxmox-migration` branch from 0.5: `git merge proxmox-migration`.

### 2.4 Start the stack
- [ ] `cd ~/docker && dccheck && dcup`
- [ ] `dcps`: everything should be running and healthy. Check that `immich_postgres`, `paperless_db` and `mariadb` started cleanly (`dclogs <name>`).
- [ ] CrowdSec firewall bouncer, now that the LAPI container is up:
  ```bash
  curl -s https://install.crowdsec.net | sudo sh
  sudo apt install -y crowdsec-firewall-bouncer-iptables
  sudo rsync root@192.168.0.10:/mnt/old/etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml /etc/crowdsec/bouncers/
  sudo systemctl enable --now crowdsec-firewall-bouncer
  docker exec crowdsec cscli bouncers list     # both bouncers should show a recent "last pull"
  ```

### 2.5 Move the UPS software to the Proxmox host
The UPS USB cable is plugged into the MS-01, so the Proxmox host sees it directly.
- [ ] pve Shell: `apt install -y nut`
- [ ] `/etc/nut/nut.conf`: `MODE=netserver`
- [ ] `/etc/nut/ups.conf`: copy the `[ups]` block from `/mnt/old/home/james/docker/appdata/peanut/ups.conf` (driver `usbhid-ups`, port `auto`).
- [ ] `/etc/nut/upsd.conf`: `LISTEN 0.0.0.0 3493`
- [ ] `/etc/nut/upsd.users`: copy the `[upsmon]` user from the old `appdata/peanut/upsd.users`. If you want the Synology to shut down on power loss too, add:
  ```
  [monuser]
    password = secret
    upsmon secondary
  ```
  DSM uses those fixed credentials.
- [ ] `/etc/nut/upsmon.conf`:
  ```
  MONITOR ups@localhost 1 upsmon <password from upsd.users> primary
  SHUTDOWNCMD "/sbin/shutdown -h +0"
  ```
- [ ] `systemctl restart nut-server nut-monitor && upsc ups@localhost`: shows battery charge and status.
- [ ] Peanut (`peanut.yml`, already changed in 0.5) should now show the UPS from `192.168.0.10`.
- [ ] Optional: in Synology DSM, **Control Panel → Hardware & Power → UPS** → enable, choose **Synology UPS server**, server IP `192.168.0.10`.

### 2.6 Restore Home Assistant into `haos`
- [ ] Open `http://192.168.0.57:8123` → **Upload backup** → choose the `.tar` from 2.1 → enter the encryption key → restore. This takes 5–15 minutes.
- [ ] Install apps from **Settings → Apps → App store** (older versions call this Add-ons). For each one, ✓ Start on boot and ✓ Watchdog:
  - [ ] **File editor** (or Studio Code Server)
  - [ ] **Mosquitto broker**
  - [ ] **Piper**
  - [ ] **Whisper** (optional, for local speech-to-text)
- [ ] Reverse proxy settings: in File editor, replace the commented-out `http:` block in `configuration.yaml` with:
  ```yaml
  http:
    use_x_forwarded_for: true
    trusted_proxies:
      - 192.168.0.56     # Traefik in the hs VM
  ```
  Then restart from **Developer tools → Restart**.
- [ ] Mosquitto: on the app's **Configuration** tab → `logins`:
  ```yaml
  - username: frigate
    password: <FRIGATE_MQTT_PASS from .env>
  - username: ha
    password: <new password>
  ```
  Add any other clients you found in 0.3. Start the app. (`homeassistant` and `addons` are reserved usernames.)
- [ ] **MQTT integration** (it still points at `127.0.0.1`): **Settings → Devices & services → MQTT → ⋮ → Reconfigure**. Set broker `core-mosquitto`, port `1883`, user `ha`.
- [ ] **Piper**: delete the old Wyoming entry (`localhost:10200`). Add the Piper app's Wyoming entry, which should be auto-discovered. Then pick it under **Settings → Voice assistants**.
- [ ] **Frigate integration** (it points at `127.0.0.1:5000`): reconfigure it to `http://192.168.0.56:5000`. If it has no reconfigure option, delete it and add it again with that URL.
- [ ] Music Assistant (`192.168.0.56:8095`), InfluxDB (`192.168.0.56:8086`) and Hue (`192.168.0.5`) keep working as they are.
- [ ] **Settings → System → Network**:
  - Home Assistant URL, Internet: `https://haos.shatteredcastle.com`
  - Home Assistant URL, Local: `http://192.168.0.57:8123`
- [ ] Phones: in the Companion app, go to **Settings → Companion app → server → Internal URL** and set `http://192.168.0.57:8123`.
- [ ] Repoint any other MQTT clients from 0.3 to `192.168.0.57`.
- [ ] `docker restart frigate`, then check in Home Assistant that Frigate events arrive.

### 2.7 Switch the network over
- [ ] Router: set the DHCP DNS server to **`192.168.0.53`**. Remove the temporary `1.1.1.1` if you added it.
- [ ] Router port forwards are unchanged: 80, 443 and 21115–21119 still go to `192.168.0.56`.
- [ ] Renew DHCP on a laptop or phone (toggle Wi-Fi), then check that ads are blocked and `*.shatteredcastle.com` resolves to `.56`.

### 2.8 Test everything
- [ ] From outside (phone on cellular, Tailscale off): Jellyfin, Immich (`photos.`), Seerr, Audiobookshelf, Vaultwarden and `haos.` all load.
- [ ] Over Tailscale (phone on cellular, Tailscale on): `https://sonarr.shatteredcastle.com` and `https://192.168.0.10:8006` load.
- [ ] Jellyfin: play something 4K HEVC with a lower quality forced. **Dashboard → Activity** should show *Transcoding (HW)*, and `sudo intel_gpu_top` in `hs` should show Video/Render load.
- [ ] Frigate: on the **System** page, the OpenVINO detector shows GPU inference times, and all cameras are recording.
- [ ] Immich: upload a photo from your phone. Faces and search still work.
- [ ] *arr apps: a test grab downloads and imports. qBittorrent reports the VPN IP (gluetun).
- [ ] Peanut shows the UPS. Uptime Kuma is all green.
- [ ] `sudo ~/docker/scripts/hs/backup-all.sh` runs cleanly.

### 2.9 Proxmox backups
- [ ] **Datacenter → Backup → Add**: Storage `synology`, Schedule `02:00`, Selection **100, 101**, Mode **Snapshot**, Compression ZSTD. Retention: keep-daily 7, keep-weekly 4.
- [ ] **Add** a second job: Storage `synology`, Schedule `sun 02:30`, Selection **102**, Mode Snapshot, ZSTD. Retention: keep-weekly 4.
- [ ] Select each job → **Run now**, then check the backups appear under **synology → Backups**.

### 2.10 Tidy up
- [ ] Tailscale admin: remove the old `hs` machine. The `dns` LXC is now the way in.
- [ ] Update the README host table and push.

---

## Phase 3: After the cutover (no downtime)

### Within the first week (ask Claude)
- [ ] Delete the compose files and appdata for services that moved: `homeassistant`, `mosquitto`, `piper`, `adguard`, plus the `nut-server` config.
- [ ] Make admin apps **LAN/Tailscale only** with an IP-allowlist middleware chain: VS Code, Kasm, Firefox, Portainer, Dozzle, the *arr apps, qBittorrent, Glances. Tailscale clients reach Traefik from `192.168.0.53`, which is already in `LOCAL_IPS`.
- [ ] **gluetun port forwarding**: `VPN_PORT_FORWARDING=on`, a non-US PIA region (Canada), and automatic qBittorrent port updates. Or switch to a provider with WireGuard and port forwarding, such as ProtonVPN or AirVPN.
- [ ] **Immich**: switch to the `immich-machine-learning:release-openvino` image, then turn on QSV under **Administration → Video transcoding → Hardware acceleration**.
- [ ] **Frigate**: set `ffmpeg.hwaccel_args: preset-intel-qsv-h264` (or `-h265`, depending on your cameras), and run detection on the cameras' substreams.
- [ ] **Jellyfin**: **Dashboard → Playback → Transcoding**:
  - Intel QuickSync (QSV), device `/dev/dri/renderD128`
  - ✓ Hardware decoding for H264, HEVC, HEVC 10bit, VP9, VP9 10bit, AV1
  - ✓ Low-Power H.264/HEVC encoders
  - ✓ Allow HEVC encoding
  - ✓ Tone mapping (VPP)

### After about 2 weeks of stability: retire the old Ubuntu
- [ ] Turn the Kingston into the Frigate drive. **This erases the old system.** (pve Shell)
  ```bash
  umount /mnt/old 2>/dev/null
  ls -l /dev/disk/by-id/ | grep -i kingston          # use the nvme-KINGSTON_... name, not -part*
  wipefs -a /dev/disk/by-id/nvme-KINGSTON_<id>
  qm set 102 --scsi1 /dev/disk/by-id/nvme-KINGSTON_<id>,discard=on,ssd=1,iothread=1,backup=0
  ```
  `backup=0` keeps recordings out of the Proxmox backups.
- [ ] In `hs`:
  ```bash
  lsblk                                   # new ~1 TB disk, e.g. /dev/sdb
  sudo mkfs.ext4 -L frigate /dev/sdb
  echo 'LABEL=frigate /home/james/data/video/frigate ext4 defaults,noatime 0 2' | sudo tee -a /etc/fstab
  sudo mount -a && sudo chown james:james ~/data/video/frigate
  docker restart frigate
  ```
- [ ] Set Frigate recording retention back to 3 days.
- [ ] Remove the `ubuntu` boot entry from the BIOS boot order.

### Optional
- [ ] **Alerts**: Datacenter → Notifications → Add → Webhook to your ntfy (`https://ntfy.shatteredcastle.com/proxmox`), or set up Gotify/email.
- [ ] **Intel AMT** (remote power control and screen): needs the cable on the I226-LM port. Enable it in the BIOS, set it up in MEBx, and manage it with MeshCommander. After boot the screen goes blank because the GPU is passed through, but power control still works.
- [ ] **RAM**: when prices drop, fit 2×48 GB DDR5-5600 SO-DIMMs and give `hs` more memory.
- [ ] **ZFS health**: check `zpool status` monthly. Proxmox runs a ZFS scrub monthly by default.

---

## Phase 4: DIY NAS (later)

Deferred. Until this phase starts, the Synology stays the NAS, and Phases 0–3 assume it.

### 4.1 Buy and build
- [ ] Parts:
  - i3-14100 or 12100, B760M (micro-ATX) board with 4+ SATA ports and 2+ PCIe slots
  - 16 GB RAM
  - Fractal Node 804 or Jonsbo N5
  - 450–550 W 80+ Gold power supply
  - Intel X710-DA2 or ConnectX-4 Lx (used)
  - SFP+ DAC cable
  - USB stick (Samsung Bar or SanDisk Fit)
  - 4× 20 TB drives (or 3 to start)
- [ ] Build it. In the BIOS: Restore on AC power loss = Power On, set the USB stick to boot first, and enable ASPM/C-states so it idles at low power.
- [ ] **Burn in every drive before trusting it** (1–2 days): an extended SMART test, then a full write/read pass (`badblocks -wsv`, or Unraid's Preclear plugin).

### 4.2 Install Unraid
- [ ] Use the **Unraid USB Creator** to write the latest stable release to the stick.
- [ ] First boot: set a root password, then buy or activate the **Unleashed** license.
- [ ] **Settings → Network**: static IP on the 2.5G port (pick a free one, e.g. `192.168.0.3`). Give the SFP+ port `10.10.10.2/24`, no gateway, MTU 9000.
- [ ] **Main → Array**: Parity = one 20 TB drive, Disk 1–3 = the others. Filesystem **XFS**. Start the array and let the parity build finish.
- [ ] **Shares**:
  - `data`: primary storage Array (move to cache-first once an NVMe cache is added)
  - `photos`, `documents`, `backups`: Array for now (move to a ZFS mirror pool later)
  - Turn on NFS export for each one, with rule `192.168.0.56(rw,sec=sys) 10.10.10.0/24(rw,sec=sys)`
- [ ] Inside `data`: `media/{movies,tv,music,books,audiobooks,comics}` and `downloads/{torrents,usenet}/{incomplete,complete}`.

### 4.3 10G link on the MS-01
- [ ] Plug the DAC into SFP+ port 1 on each machine.
- [ ] Proxmox: **pve → System → Network → Create → Linux Bridge** `vmbr1`, ports `enp2s0f0np0`, MTU 9000, no IP. Apply.
- [ ] `hs` VM: **Hardware → Add → Network Device**, bridge `vmbr1`, VirtIO, MTU `1` (inherits from the bridge).
- [ ] In `hs`, add the second NIC to netplan: `10.10.10.56/24`, MTU 9000, no gateway. Test with `ping -M do -s 8972 10.10.10.2`.

### 4.4 Move the data (ask Claude for the compose changes)
- [ ] Copy media from the Synology to the NAS with rsync, then do a final top-up copy.
- [ ] Compose: replace `MEDIADIR` and `DOWNLOADSDIR` with a single `DATAROOT` mounted at `/data` in qBittorrent, SABnzbd, Sonarr, Radarr, Lidarr and Jellyfin. Update the root folders and download paths in each app.
- [ ] Check that hardlinks work: after an import, `ls -li` shows the same inode number in `downloads` and `media`.
- [ ] Immich: move `appdata/immich/upload` to the `photos` share. Keep the container path `/usr/src/app/upload` so the database paths stay valid.
- [ ] Paperless and Nextcloud data → `documents`.
- [ ] Proxmox: add an NFS storage for the NAS `backups` share at `10.10.10.2`, and point the backup jobs at it.

### 4.5 Turn the old Synology into the backup target
- [ ] After a week on the new NAS, wipe the Synology and create a `backups` share.
- [ ] Back up `photos`, `documents` and `backups` from the NAS to the Synology nightly (Kopia, restic or rsync), and to Backblaze B2 or similar for an offsite copy. Media doesn't need a backup.
- [ ] Later: install Proxmox Backup Server on the NAS for faster, incremental VM backups.
