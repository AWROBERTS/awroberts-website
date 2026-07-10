#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (Autoinstall + QEMU)
# ============================================================================
# This script:
#   1. Generates autoinstall.yaml
#   2. Builds a custom autoinstall ISO
#   3. Creates VM disks (20G main + 20G HLS)
#   4. Boots QEMU with autoinstall enabled
#   5. Waits for SSH availability
#
# The worker bootstrap (containerd, kubeadm, join, etc.)
# is handled separately by scripts/worker/bootstrap.sh.
# ============================================================================

# === CONFIG ===
VM_NAME="worker-arm"
MAIN_DISK="worker-main.qcow2"
HLS_DISK="worker-hls.qcow2"
ISO_ORIG="ubuntu-24.04-live-server-arm64.iso"
ISO_CUSTOM="ubuntu-autoinstall.iso"
SSH_PORT=2222
VM_USER="awr"
VM_PASS="pastysmasher"
VM_HOST="localhost"

# === 1. Download original Ubuntu ARM ISO ===
if [ ! -f "$ISO_ORIG" ]; then
  echo "Downloading Ubuntu ARM ISO..."
  curl -L -o "$ISO_ORIG" https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-arm64.iso
fi

# === 2. Generate hashed password ===
HASHED_PASS=$(openssl passwd -6 "$VM_PASS")

# === 3. Create autoinstall.yaml ===
cat > autoinstall.yaml <<EOF
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
EOF

echo "Generated autoinstall.yaml"

# === 4. Extract ISO and inject autoinstall.yaml ===
echo "Extracting ISO..."
rm -rf iso-src
mkdir -p iso-src
bsdtar -C iso-src -xf "$ISO_ORIG"

echo "Injecting autoinstall.yaml..."
cp autoinstall.yaml iso-src/

# === 5. Build custom autoinstall ISO ===
echo "Building custom autoinstall ISO..."
xorriso -as mkisofs \
  -o "$ISO_CUSTOM" \
  -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -c boot.cat \
  -b isolinux.bin \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -eltorito-alt-boot \
  -e boot/grub/efi.img \
  -no-emul-boot \
  -isohybrid-gpt-basdat \
  iso-src

echo "Custom autoinstall ISO created: $ISO_CUSTOM"

# === 6. Create VM disks ===
echo "Creating VM disks..."
qemu-img create -f qcow2 "$MAIN_DISK" 20G
qemu-img create -f qcow2 "$HLS_DISK" 20G

# === 7. Launch VM with autoinstall ISO ===
echo "Launching VM with autoinstall ISO..."
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a72 \
  -m 4096 \
  -smp 4 \
  -drive if=none,file="$MAIN_DISK",id=main \
  -device virtio-blk-device,drive=main \
  -drive if=none,file="$HLS_DISK",id=hls \
  -device virtio-blk-device,drive=hls \
  -cdrom "$ISO_CUSTOM" \
  -boot d \
  -kernel-args "autoinstall ds=nocloud-net;s=file:///autoinstall.yaml" \
  -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
  -device virtio-net-device,netdev=net0 \
  -nographic &
VM_PID=$!

echo "Autoinstall running... waiting for SSH availability"

# === 8. Wait for SSH ===
until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no -p "${SSH_PORT}" "${VM_USER}@${VM_HOST}" 'echo ok' 2>/dev/null; do
  sleep 5
done

echo "=== VM is online via SSH ==="
echo "Worker VM provision complete."
echo "Next step: worker bootstrap will run via deploy-kubernetes.sh"
