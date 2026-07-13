#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (Mint Side)
# ============================================================================
# This script runs on Linux Mint and performs:
#   1. Download Ubuntu ARM ISO (if missing/corrupt)
#   2. Generate cloud-init seed ISO (user-data + meta-data, labeled CIDATA)
#   3. Copy both ISOs to Mac mini
#   4. Copy macOS-side VM creation script to Mac mini
#   5. SSH into Mac mini to launch VM using Apple Virtualization
#   6. Wait for worker VM to come online
#   7. Trigger worker bootstrap
#
# The Ubuntu ISO is used unmodified. Autoinstall config is delivered via a
# separate CIDATA seed ISO that cloud-init detects automatically.
# Apple Virtualization.framework is EFI/UEFI only — ARM64 ISO required.
# ============================================================================

# === CONFIG ===
ISO_ORIG="ubuntu-24.04.4-live-server-arm64.iso"
ISO_SEED="ubuntu-autoinstall-seed.iso"
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
for pkg in xorriso curl openssl; do
  if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
    echo "Installing missing dependency: $pkg"
    sudo apt-get install -y "$pkg"
  fi
done

# === 2. Download Ubuntu ARM ISO (re-download if missing or corrupt) ===
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

# === 3. Generate hashed password ===
HASHED_PASS=$(openssl passwd -6 "$VM_PASS")

# === 4. Create cloud-init nocloud files ===
# cloud-init's nocloud datasource detects a disk/ISO labeled "CIDATA"
# containing user-data and meta-data — no ISO modification needed.
cat > user-data <<EOF
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

# meta-data must exist; instance-id prevents re-running on reboot
cat > meta-data <<EOF
instance-id: awr-ffmpeg-$(date +%s)
local-hostname: awr-ffmpeg
EOF

echo "Generated user-data and meta-data"

# === 5. Build CIDATA seed ISO ===
# xorriso creates a small ISO labeled "cidata" — cloud-init finds it automatically.
echo "Building seed ISO..."
xorriso -as mkisofs \
  -o "$ISO_SEED" \
  -V cidata \
  -J \
  -r \
  user-data \
  meta-data

echo "Seed ISO created: $ISO_SEED"

# === 6. Copy ISOs to Mac mini ===
echo "Copying Ubuntu ISO to Mac mini..."
scp "$ISO_ORIG" "${MAC_USER}@${MAC_HOST}:/Users/${MAC_USER}/worker-ubuntu.iso"

echo "Copying seed ISO to Mac mini..."
scp "$ISO_SEED" "${MAC_USER}@${MAC_HOST}:/Users/${MAC_USER}/worker-seed.iso"

# === 7. Copy macOS VM creation script to Mac mini ===
echo "Copying macOS VM creation script..."
scp "$MAC_VM_SCRIPT" "${MAC_USER}@${MAC_HOST}:${MAC_VM_SCRIPT_REMOTE}"
ssh "${MAC_USER}@${MAC_HOST}" "chmod +x ${MAC_VM_SCRIPT_REMOTE}"

# === 8. Trigger VM creation on macOS ===
echo "Triggering VM creation on Mac mini..."
ssh "${MAC_USER}@${MAC_HOST}" "${MAC_VM_SCRIPT_REMOTE}"

# === 9. Wait for worker VM to come online ===
echo "Waiting for worker VM to become reachable..."

WORKER_IP="${WORKER_IP:-192.168.1.50}"

until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${VM_USER}@${WORKER_IP}" 'echo ok' 2>/dev/null; do
  sleep 5
done

echo "=== Worker VM is online ==="

# === 10. Run worker bootstrap ===
echo "Running worker bootstrap..."
bash "$WORKER_BOOTSTRAP" "$WORKER_IP"

echo "=== Worker VM provision complete ==="
