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

# === 0. Skip if worker VM is already healthy ===
WORKER_IP="${WORKER_IP}"
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "${VM_USER}@${WORKER_IP}" 'echo ok' 2>/dev/null; then
  echo "Worker VM is already reachable at ${WORKER_IP} — skipping provisioning."
  exit 0
fi
echo "Worker VM not reachable at ${WORKER_IP} — provisioning now."

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

# === 5. Prepare autoinstall files in a temp directory ===
# We inject files directly into the original ISO rather than extracting and
# rebuilding from scratch — this preserves the El Torito EFI boot catalog
# and hybrid GPT structure that Apple Virtualization.framework requires.
TMPWORK=$(mktemp -d)
trap 'rm -rf "$TMPWORK"' EXIT

# === 6. Extract GRUB config from original ISO (partial extract — fast) ===
bsdtar -xf "$ISO_ORIG" -C "$TMPWORK/" boot/grub/grub.cfg 2>/dev/null || \
  bsdtar -xf "$ISO_ORIG" -C "$TMPWORK/" boot/grub/grub.cfg
GRUB_CFG="$TMPWORK/boot/grub/grub.cfg"
chmod u+w "$GRUB_CFG"
echo "Patching GRUB config..."

# Set timeout=0 so GRUB boots immediately without waiting.
# Do NOT add `terminal_output serial` — on EFI ARM (Apple VZ) the virtio
# console is not a 16550 UART; that command hangs GRUB. Let the EFI console
# handle GRUB output. Linux gets console=hvc0 at the kernel level.
if grep -q 'set timeout=' "$GRUB_CFG"; then
  sed -i 's/set timeout=[0-9]*/set timeout=0/' "$GRUB_CFG"
else
  sed -i "1s|^|set timeout=0\n|" "$GRUB_CFG"
fi

# Add console=hvc0 to the kernel cmdline so the kernel + installer output
# reaches hvc0 (the virtio serial device → vm.log).
# autoinstall config is provided via a separate CIDATA seed ISO (step 7),
# so no ds=nocloud or autoinstall args are needed here.
sed -i 's|^\(\s*linux\s.*\)---|  \1console=hvc0 ---|' "$GRUB_CFG"
# Fallback: if no --- separator on the line, append at end
sed -i '/console=hvc0/! s|^\(\s*linux\s.*\)$|\1 console=hvc0|' "$GRUB_CFG"

echo "=== Patched grub.cfg ==="
cat "$GRUB_CFG"
echo "=== End grub.cfg ==="

# === 7. Create CIDATA seed ISO ===
# cloud-init automatically scans all attached disks for a filesystem labeled
# "CIDATA" and reads user-data / meta-data from it — no kernel cmdline args
# required. Ubuntu 24.04+ starts autoinstall automatically when cloud-init
# user-data contains an `autoinstall:` section.
mkdir -p "$TMPWORK/cidata"

cat > "$TMPWORK/cidata/user-data" <<EOF
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

cat > "$TMPWORK/cidata/meta-data" <<EOF
instance-id: awr-ffmpeg-$(date +%s)
local-hostname: awr-ffmpeg
EOF

CIDATA_ISO="$TMPWORK/cidata.iso"
echo "Creating CIDATA seed ISO..."
xorriso -as mkisofs \
  -V "CIDATA" \
  -J -r \
  -o "$CIDATA_ISO" \
  "$TMPWORK/cidata/"

# === 8. Inject patched grub.cfg into Ubuntu ISO (preserving EFI boot) ===
# Only the grub.cfg is modified — user-data/meta-data come from CIDATA ISO.
rm -f "$ISO_CUSTOM"
echo "Creating boot ISO (patching grub.cfg into original)..."
xorriso \
  -indev "$ISO_ORIG" \
  -outdev "$ISO_CUSTOM" \
  -boot_image any replay \
  -map "$TMPWORK/boot/grub/grub.cfg" /boot/grub/grub.cfg \
  -commit_eject none

echo "Boot ISO created: $ISO_CUSTOM"

# === 10. Copy ISOs to Mac mini ===
echo "Copying boot ISO to Mac mini..."
scp "$ISO_CUSTOM" "${MAC_USER}@${MAC_HOST}:/Users/${MAC_USER}/worker-autoinstall.iso"
echo "Copying CIDATA seed ISO to Mac mini..."
scp "$CIDATA_ISO" "${MAC_USER}@${MAC_HOST}:/Users/${MAC_USER}/worker-cidata.iso"

# === 11. Copy macOS VM creation script to Mac mini ===
echo "Copying macOS VM creation script..."
scp "$MAC_VM_SCRIPT" "${MAC_USER}@${MAC_HOST}:${MAC_VM_SCRIPT_REMOTE}"
ssh "${MAC_USER}@${MAC_HOST}" "chmod +x ${MAC_VM_SCRIPT_REMOTE}"

# === 12. Trigger VM creation on macOS ===
echo "Triggering VM creation on Mac mini..."
ssh "${MAC_USER}@${MAC_HOST}" "${MAC_VM_SCRIPT_REMOTE}"

# === 13. Wait for worker VM to come online ===
echo "Waiting for worker VM to become reachable..."

until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${VM_USER}@${WORKER_IP}" 'echo ok' 2>/dev/null; do
  sleep 5
done

echo "=== Worker VM is online ==="

# === 14. Run worker bootstrap ===
echo "Running worker bootstrap..."
bash "$WORKER_BOOTSTRAP" "$WORKER_IP"

echo "=== Worker VM provision complete ==="
