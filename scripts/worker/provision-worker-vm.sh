#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (Mint Side)
# ============================================================================
# This script runs on Linux Mint and performs:
#   1. Generate autoinstall user-data + meta-data (nocloud format)
#   2. Build custom autoinstall ISO (EFI-only, ARM-compatible)
#   3. Copy ISO to Mac mini
#   4. Copy macOS-side VM creation script to Mac mini
#   5. SSH into Mac mini to launch VM using Apple Virtualization
#   6. Wait for worker VM to come online
#   7. Trigger worker bootstrap
#
# Apple Virtualization.framework is EFI/UEFI only — no BIOS/ISOLINUX needed.
# ============================================================================

# === CONFIG ===
ISO_ORIG="ubuntu-24.04-live-server-arm64.iso"
ISO_CUSTOM="ubuntu-autoinstall.iso"

MAC_VM_SCRIPT="provision-worker-vm-macos.sh"
MAC_VM_SCRIPT_REMOTE="/Users/${MAC_USER}/${MAC_VM_SCRIPT}"

WORKER_BOOTSTRAP="./scripts/worker/bootstrap.sh"

# === 1. Ensure required tools are installed ===
for pkg in xorriso curl openssl; do
  if ! command -v "$pkg" &>/dev/null; then
    echo "Installing missing dependency: $pkg"
    sudo apt-get install -y "$pkg"
  fi
done

# === 2. Download original Ubuntu ARM ISO ===
if [ ! -f "$ISO_ORIG" ]; then
  echo "Downloading Ubuntu ARM ISO..."
  curl -L -o "$ISO_ORIG" https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-arm64.iso
fi

# === 3. Generate hashed password ===
HASHED_PASS=$(openssl passwd -6 "$VM_PASS")

# === 3. Create nocloud autoinstall files ===
# Ubuntu autoinstall uses cloud-init nocloud source:
#   user-data = autoinstall config
#   meta-data  = required but can be empty
cat > user-data <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: worker-arm
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

touch meta-data

echo "Generated user-data and meta-data"

# === 4. Extract ISO and inject autoinstall files ===
echo "Extracting ISO..."
rm -rf iso-src
mkdir -p iso-src

xorriso -osirrox on -indev "$ISO_ORIG" -extract / iso-src
chmod -R u+w iso-src

echo "Injecting autoinstall files..."
cp user-data iso-src/user-data
cp meta-data iso-src/meta-data

# === 5. Patch GRUB config to trigger autoinstall on first boot ===
# Apple Virtualization boots via EFI/GRUB — inject kernel args so
# cloud-init reads from the ISO itself (ds=nocloud;s=/cdrom/).
GRUB_CFG="iso-src/boot/grub/grub.cfg"
if [ -f "$GRUB_CFG" ]; then
  echo "Patching GRUB config for autoinstall..."
  # Append autoinstall + nocloud datasource to the first linux line
  sed -i 's|^\(\s*linux\s.*\)|\1 autoinstall ds=nocloud\;s=/cdrom/|' "$GRUB_CFG"
else
  echo "WARNING: GRUB config not found at $GRUB_CFG — autoinstall may not trigger automatically."
fi

# === 6. Build EFI-only autoinstall ISO ===
# Apple Virtualization.framework is UEFI-only (ARM). No BIOS/ISOLINUX needed.
echo "Building EFI-only autoinstall ISO..."
xorriso -as mkisofs \
  -o "$ISO_CUSTOM" \
  -r \
  -V "Ubuntu 24.04 AutoInstall" \
  -J \
  --efi-boot-part \
  --efi-boot-image \
  -e boot/grub/efi.img \
  -no-emul-boot \
  iso-src/

echo "Custom autoinstall ISO created: $ISO_CUSTOM"

# === 7. Copy ISO to Mac mini ===
echo "Copying ISO to Mac mini..."
scp "$ISO_CUSTOM" "${MAC_USER}@${MAC_HOST}:/Users/${MAC_USER}/worker-autoinstall.iso"

# === 8. Copy macOS VM creation script to Mac mini ===
echo "Copying macOS VM creation script..."
scp "$MAC_VM_SCRIPT" "${MAC_USER}@${MAC_HOST}:${MAC_VM_SCRIPT_REMOTE}"

# === 9. Ensure macOS script is executable ===
ssh "${MAC_USER}@${MAC_HOST}" "chmod +x ${MAC_VM_SCRIPT_REMOTE}"

# === 10. Trigger VM creation on macOS ===
echo "Triggering VM creation on Mac mini..."
ssh "${MAC_USER}@${MAC_HOST}" "${MAC_VM_SCRIPT_REMOTE}"

# === 11. Wait for worker VM to come online ===
echo "Waiting for worker VM to become reachable..."

WORKER_IP="${WORKER_IP:-192.168.1.50}"

until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no "${VM_USER}@${WORKER_IP}" 'echo ok' 2>/dev/null; do
  sleep 5
done

echo "=== Worker VM is online ==="

# === 12. Run worker bootstrap ===
echo "Running worker bootstrap..."
bash "$WORKER_BOOTSTRAP" "$WORKER_IP"

echo "=== Worker VM provision complete ==="
