#!/bin/bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (macOS Side, Apple Virtualization.framework)
# ============================================================================

VM_NAME="awr-ffmpeg"
VM_DIR="$HOME/VMs/${VM_NAME}"

AUTOINSTALL_ISO="$HOME/worker-autoinstall.iso"
CIDATA_ISO="$HOME/worker-cidata.iso"

OS_DISK_SIZE_GB=20
HLS_DISK_SIZE_GB=20

RAM_MB=4096
CPU_COUNT=4

WORKER_MAC="${1:-02:52:56:00:64:06}"

# --- Sanity checks ---
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Apple Silicon required."
  exit 1
fi

SW_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$SW_VER" | cut -d. -f1)
if (( MACOS_MAJOR < 13 )); then
  echo "ERROR: macOS 13+ required."
  exit 1
fi

if [ ! -f "$AUTOINSTALL_ISO" ]; then
  echo "ERROR: Autoinstall ISO missing."
  exit 1
fi
if [ ! -f "$CIDATA_ISO" ]; then
  echo "ERROR: CIDATA ISO missing."
  exit 1
fi

mkdir -p "$VM_DIR"

# --- Kill stale VM processes ---
pkill -f "${VM_DIR}/run-vm" 2>/dev/null || true
for _ in $(seq 1 10); do
  pgrep -f "${VM_DIR}/run-vm" >/dev/null 2>&1 || break
  sleep 1
done
pkill -9 -f "${VM_DIR}/run-vm" 2>/dev/null || true
sleep 1

rm -f "$VM_DIR/vm.pid" "$VM_DIR/vm.log"

# --- Create disks if missing ---
OS_DISK="$VM_DIR/os.img"
HLS_DISK="$VM_DIR/hls.img"

if [ ! -f "$OS_DISK" ]; then
  echo "Creating OS disk..."
  dd if=/dev/zero bs=1m count=$(( OS_DISK_SIZE_GB * 1024 )) of="$OS_DISK" 2>/dev/null
else
  echo "OS disk exists — NOT recreating."
fi

if [ ! -f "$HLS_DISK" ]; then
  echo "Creating HLS disk..."
  dd if=/dev/zero bs=1m count=$(( HLS_DISK_SIZE_GB * 1024 )) of="$HLS_DISK" 2>/dev/null
else
  echo "HLS disk exists — NOT recreating."
fi

# --- Copy Swift runner from repo ---
SWIFT_RUNNER="$VM_DIR/run-vm.swift"
cp "$HOME/scripts/worker/run-vm.swift" "$SWIFT_RUNNER"

echo "Swift VM runner copied to: $SWIFT_RUNNER"

# --- Compile + sign ---
SWIFT_BIN="$VM_DIR/run-vm"

swiftc -framework Virtualization -o "$SWIFT_BIN" "$SWIFT_RUNNER"

ENTITLEMENTS="$VM_DIR/entitlements.plist"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.virtualization</key>
    <true/>
</dict>
</plist>
PLIST

codesign --sign - --entitlements "$ENTITLEMENTS" --force "$SWIFT_BIN"

# --- Phase A: autoinstall only if EFI store missing ---
if [ ! -f "$VM_DIR/os.img.efi" ]; then
  echo "=== Phase A: Running autoinstall ==="
  "$SWIFT_BIN" \
    "$AUTOINSTALL_ISO" \
    "$CIDATA_ISO" \
    "$OS_DISK" \
    "$HLS_DISK" \
    "$RAM_MB" \
    "$CPU_COUNT" \
    "$WORKER_MAC" \
    > "$VM_DIR/vm-install.log" 2>&1
else
  echo "OS already installed — skipping autoinstall."
fi

# --- Wait for helper to release disk locks ---
for _ in $(seq 1 10); do
  pgrep -f "${VM_DIR}/run-vm" >/dev/null 2>&1 || break
  sleep 1
done
sleep 2

# --- Phase B: boot installed OS ---
echo "=== Phase B: Booting installed OS ==="
nohup "$SWIFT_BIN" \
  none \
  none \
  "$OS_DISK" \
  "$HLS_DISK" \
  "$RAM_MB" \
  "$CPU_COUNT" \
  "$WORKER_MAC" \
  > "$VM_DIR/vm.log" 2>&1 &

echo $! > "$VM_DIR/vm.pid"
echo "VM booted from disk (PID $(cat "$VM_DIR/vm.pid"))."
echo "Worker VM should come online shortly."
