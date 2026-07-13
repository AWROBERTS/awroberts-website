#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (Mint Side)
# ============================================================================
# This script runs on Linux Mint and performs:
#   1. Download Ubuntu ARM ISO (if missing/corrupt)
#   2. Extract ISO, inject autoinstall config, patch GRUB, rebuild ISO
#   3. Copy modified ISO to Mac mini
#   4. Copy macOS-side VM creation script to Mac mini
#   5. SSH into Mac mini to launch VM using Apple Virtualization
#   6. Wait for worker VM to come online
#   7. Trigger worker bootstrap
#
# Apple Virtualization.framework is EFI/UEFI only — ARM64 ISO required.
# ============================================================================

# === CONFIG ===
ISO_ORIG="ubuntu-24.04.4-live-server-arm64.iso"
ISO_CUSTOM="ubuntu-autoinstall.iso"
# Minimum expected ISO size: 1 GB
ISO_MIN_BYTES=1073741824

MAC_VM_SCRIPT="scripts/worker/provision-worker-vm-macos.sh"
MAC_VM_SCRIPT_REMOTE="/Users/${MAC_USER}/provision-worker-vm-macos.sh"

WORKER_BOOTSTRAP="./scripts/worker/bootstrap.sh"

# === 1. Ensure SSH key auth to Mac mini ===
if [ ! -f ~/.ssh/id_ed25519 ]; then
  echo "Generating SSH key..."
  ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
fi

if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${MAC_USER}@${MAC_HOST}" true 2>/dev/null; then
  echo "Installing SSH key on Mac mini (password required once)..."
  ssh-copy-id -i ~/.ssh/id_ed25519.pub "${MAC_USER}@${MAC_HOST}"
fi

# === 2. Ensure required tools are installed ===
for pkg in xorriso curl openssl libarchive-tools; do
  if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
    echo "Installing missing dependency: $pkg"
    sudo apt-get install -y "$pkg"
  fi
done

# === 3. Download Ubuntu ARM ISO (re-download if missing or corrupt) ===
ISO_SIZE=0
if [ -f "$ISO_ORIG" ]; then
  ISO_SIZE=$(stat -c%s "$ISO_ORIG")
fi

if [ "$ISO_SIZE" -lt "$ISO_MIN_BYTES" ]; then
  echo "ISO missing or too small (${ISO_SIZE} bytes) — downloading Ubuntu 24.04.4 ARM ISO..."
  rm -f "$ISO_ORIG"
  curl -L --fail -o "$ISO_ORIG" \
    https://cdimage.ubuntu.com/releases/24.04/release/ubuntu-24.04.4-live-server-arm64.iso
  ISO_SIZE=$(stat -c%s "$ISO_ORIG")
  if [ "$ISO_SIZE" -lt "$ISO_MIN_BYTES" ]; then
    echo "ERROR: ISO download failed or incomplete (${ISO_SIZE} bytes)."
    rm -f "$ISO_ORIG"
    exit 1
  fi
fi

echo "Ubuntu ISO ready: $ISO_ORIG ($(( ISO_SIZE / 1024 / 1024 )) MB)"

# === 4. Generate hashed password ===
HASHED_PASS=$(openssl passwd -6 "$VM_PASS")

# === 5. Extract ISO ===
echo "Extracting ISO..."
rm -rf iso-src
mkdir -p iso-src
bsdtar -xf "$ISO_ORIG" -C iso-src/
chmod -R u+w iso-src

# === 6. Inject autoinstall user-data and meta-data ===
# cloud-init reads user-data/meta-data from /cdrom/ (the ISO mount point)
# when kernel cmdline contains: ds=nocloud;s=/cdrom/
cat > iso-src/user-data <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: awr-ffmpeg
    username: $VM_USER
    password: "$HASHED_PASS"
  ssh:
    install-server: true
  storage:
    layout:
      name: direct
  packages:
    - curl
    - vim
  late-commands:
    - shutdown -h now
EOF

cat > iso-src/meta-data <<EOF
instance-id: awr-ffmpeg-$(date +%s)
local-hostname: awr-ffmpeg
EOF

echo "Injected user-data and meta-data into ISO"

# === 7. Patch GRUB config to add autoinstall kernel args ===
GRUB_CFG=$(find iso-src -name "grub.cfg" | head -1)
if [ -n "$GRUB_CFG" ]; then
  echo "Patching GRUB config: $GRUB_CFG"
  sed -i 's|^\(\s*linux\s.*\)|\1 autoinstall ds=nocloud;s=/cdrom/|' "$GRUB_CFG"
else
  echo "ERROR: grub.cfg not found in extracted ISO."
  exit 1
fi

# === 8. Find ARM EFI boot binary ===
# Ubuntu ARM ISOs use EFI/BOOT/BOOTAA64.EFI (not efi.img as on x86).
EFI_BIN=$(find iso-src -iname "BOOTAA64.EFI" | head -1)
if [ -z "$EFI_BIN" ]; then
  echo "ERROR: Cannot find BOOTAA64.EFI in extracted ISO."
  echo "EFI directory contents:"
  find iso-src -iname "*.EFI" 2>/dev/null || true
  exit 1
fi
EFI_REL="${EFI_BIN#iso-src/}"
echo "Found ARM EFI binary: $EFI_REL"

# === 9. Rebuild EFI-only autoinstall ISO ===
echo "Rebuilding ISO with autoinstall config..."
xorriso -as mkisofs \
  -o "$ISO_CUSTOM" \
  -r \
  -V "Ubuntu-AutoInstall" \
  -J \
  --efi-boot-part \
  --efi-boot-image \
  -e "$EFI_REL" \
  -no-emul-boot \
  iso-src/

echo "Custom autoinstall ISO created: $ISO_CUSTOM"

# === 10. Copy modified ISO to Mac mini ===
echo "Copying autoinstall ISO to Mac mini..."
scp "$ISO_CUSTOM" "${MAC_USER}@${MAC_HOST}:/Users/${MAC_USER}/worker-autoinstall.iso"

# === 11. Copy macOS VM creation script to Mac mini ===
echo "Copying macOS VM creation script..."
scp "$MAC_VM_SCRIPT" "${MAC_USER}@${MAC_HOST}:${MAC_VM_SCRIPT_REMOTE}"
ssh "${MAC_USER}@${MAC_HOST}" "chmod +x ${MAC_VM_SCRIPT_REMOTE}"

# === 12. Trigger VM creation on macOS ===
echo "Triggering VM creation on Mac mini..."
ssh "${MAC_USER}@${MAC_HOST}" "${MAC_VM_SCRIPT_REMOTE}"

# === 13. Wait for worker VM to come online ===
echo "Waiting for worker VM to become reachable..."

WORKER_IP="${WORKER_IP:-192.168.1.50}"

until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${VM_USER}@${WORKER_IP}" 'echo ok' 2>/dev/null; do
  sleep 5
done

echo "=== Worker VM is online ==="

# === 14. Run worker bootstrap ===
echo "Running worker bootstrap..."
bash "$WORKER_BOOTSTRAP" "$WORKER_IP"

echo "=== Worker VM provision complete ==="
