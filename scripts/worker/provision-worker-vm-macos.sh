#!/bin/bash
set -euo pipefail

# ============================================================================
# Worker VM Provisioner (macOS Side, Apple Virtualization.framework)
# ============================================================================
# This script runs on the Mac mini and:
#   1. Validates the autoinstall ISO copied from Mint
#   2. Creates VM disk images (OS + HLS storage)
#   3. Writes a Swift helper that uses Virtualization.framework to boot the VM
#   4. Compiles and runs the Swift helper
#
# Requires macOS 13+ (Ventura) on Apple Silicon.
# No third-party tools (UTM, tart, etc.) — native Virtualization.framework only.
# ============================================================================

# === CONFIG ===
VM_NAME="awr-ffmpeg"
VM_DIR="$HOME/VMs/${VM_NAME}"

AUTOINSTALL_ISO="$HOME/worker-autoinstall.iso"
CIDATA_ISO="$HOME/worker-cidata.iso"

OS_DISK_SIZE_GB=20
HLS_DISK_SIZE_GB=20

RAM_MB=4096
CPU_COUNT=4

# Fixed MAC (passed from the Mint provisioner; must match the autoinstall
# netplan macaddress match so the VM lands on its static IP).
WORKER_MAC="${1:-02:52:56:00:64:06}"

# === 1. Sanity checks ===
if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: Apple Virtualization.framework requires Apple Silicon (arm64)."
  exit 1
fi

SW_VER=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo "$SW_VER" | cut -d. -f1)
if (( MACOS_MAJOR < 13 )); then
  echo "ERROR: macOS 13 (Ventura) or later required for full Virtualization.framework support. Got: $SW_VER"
  exit 1
fi

if [ ! -f "$AUTOINSTALL_ISO" ]; then
  echo "ERROR: Autoinstall ISO not found at: $AUTOINSTALL_ISO"
  exit 1
fi
if [ ! -f "$CIDATA_ISO" ]; then
  echo "ERROR: CIDATA seed ISO not found at: $CIDATA_ISO"
  exit 1
fi

mkdir -p "$VM_DIR"

# === 2. Clean up stale VM state from any previous failed run ===
# The EFI variable store records boot entries; a stale store from a failed
# install causes the EFI firmware to try wrong boot devices and idle silently.
# The OS disk must also be zeroed so the installer can partition it fresh.
if [ -f "$VM_DIR/vm.pid" ]; then
  OLD_PID=$(cat "$VM_DIR/vm.pid")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "Stopping existing VM (PID $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null || true
    sleep 2
  fi
  rm -f "$VM_DIR/vm.pid"
fi
rm -f "$VM_DIR/os.img" "$VM_DIR/os.img.efi" "$VM_DIR/vm.log"
echo "Cleared stale VM state."

# === 3. Create disk images ===
OS_DISK="$VM_DIR/os.img"
HLS_DISK="$VM_DIR/hls.img"

echo "Creating OS disk (${OS_DISK_SIZE_GB}GB)..."
dd if=/dev/zero bs=1m count=$(( OS_DISK_SIZE_GB * 1024 )) of="$OS_DISK" 2>/dev/null

if [ ! -f "$HLS_DISK" ]; then
  echo "Creating HLS disk (${HLS_DISK_SIZE_GB}GB)..."
  dd if=/dev/zero bs=1m count=$(( HLS_DISK_SIZE_GB * 1024 )) of="$HLS_DISK" 2>/dev/null
fi

# === 4. Write Swift VM runner ===
SWIFT_RUNNER="$VM_DIR/run-vm.swift"

cat > "$SWIFT_RUNNER" <<'SWIFT'
import Virtualization
import Foundation

guard CommandLine.arguments.count == 8 else {
    fputs("Usage: run-vm <autoinstall-iso|none> <cidata-iso|none> <os-disk> <hls-disk> <ram-mb> <cpu-count> <mac>\n", stderr)
    exit(1)
}

// Pass "none" for the ISO/cidata paths to boot the installed OS from disk
// (phase B) instead of the installer (phase A).
let isoPath    = CommandLine.arguments[1]
let ciDataPath = CommandLine.arguments[2]
let osDisk     = CommandLine.arguments[3]
let hlsDisk    = CommandLine.arguments[4]
let ramMB      = Int(CommandLine.arguments[5]) ?? 4096
let cpuCount   = Int(CommandLine.arguments[6]) ?? 4
let macStr     = CommandLine.arguments[7]

// --- Boot loader: EFI ---
let efi = VZEFIBootLoader()
let efiStoreURL = URL(fileURLWithPath: osDisk + ".efi")
let efiStore: VZEFIVariableStore
if FileManager.default.fileExists(atPath: efiStoreURL.path) {
    efiStore = VZEFIVariableStore(url: efiStoreURL)
} else {
    efiStore = try! VZEFIVariableStore(creatingVariableStoreAt: efiStoreURL, options: [])
}
efi.variableStore = efiStore

// --- CPU & memory ---
let config = VZVirtualMachineConfiguration()
config.cpuCount = cpuCount
config.memorySize = UInt64(ramMB) * 1024 * 1024
config.bootLoader = efi

// --- Storage ---
// Phase A (install): ISO + CIDATA + OS + HLS. Phase B (run installed OS):
// OS + HLS only, so EFI boots from the installed disk rather than the ISO.
var storageDevices: [VZStorageDeviceConfiguration] = []

// Ubuntu boot ISO (read-only, EFI boots from here during install)
if isoPath != "none" {
    let isoAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: isoPath), readOnly: true)
    storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: isoAttachment))
}

// CIDATA seed ISO (read-only, cloud-init reads user-data from here).
// cloud-init automatically detects any disk labeled "CIDATA" and loads
// user-data/meta-data from it — no kernel cmdline datasource args needed.
if ciDataPath != "none" {
    let ciDataAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: ciDataPath), readOnly: true)
    storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: ciDataAttachment))
}

// OS disk (always attached)
let osAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: osDisk), readOnly: false)
storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: osAttachment))

// HLS disk (always attached)
let hlsAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: hlsDisk), readOnly: false)
storageDevices.append(VZVirtioBlockDeviceConfiguration(attachment: hlsAttachment))

config.storageDevices = storageDevices

// --- Network: NAT with a fixed MAC (so the VM keeps a stable DHCP/static identity) ---
let network = VZVirtioNetworkDeviceConfiguration()
network.attachment = VZNATNetworkDeviceAttachment()
if let mac = VZMACAddress(string: macStr) {
    network.macAddress = mac
} else {
    fputs("WARNING: invalid MAC '\(macStr)', using a random address.\n", stderr)
}
config.networkDevices = [network]

// --- Serial console -> stderr (flows to vm.log via nohup redirect) ---
let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
let serialPort = VZFileHandleSerialPortAttachment(
    fileHandleForReading: FileHandle.standardInput,
    fileHandleForWriting: FileHandle.standardError
)
serial.attachment = serialPort
config.serialPorts = [serial]

// --- Entropy ---
config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

try! config.validate()

// VZVirtualMachine must be used on the main queue; RunLoop keeps callbacks alive.
let vm = VZVirtualMachine(configuration: config, queue: DispatchQueue.main)

DispatchQueue.main.async {
    vm.start { result in
        switch result {
        case .success:
            fputs("VM started successfully.\n", stderr)
        case .failure(let err):
            fputs("Failed to start VM: \(err)\n", stderr)
            exit(1)
        }
    }
}

let observer = NotificationCenter.default.addObserver(
    forName: NSNotification.Name("com.apple.Virtualization.VZVirtualMachine.stateDidChange"),
    object: vm,
    queue: nil
) { _ in
    DispatchQueue.main.async {
        if vm.state == .stopped || vm.state == .error {
            fputs("VM stopped (state: \(vm.state.rawValue)).\n", stderr)
            exit(0)
        }
    }
}

_ = observer

RunLoop.main.run()
SWIFT

echo "Swift VM runner written to: $SWIFT_RUNNER"

# === 5. Compile, sign, and run Swift VM runner ===
SWIFT_BIN="$VM_DIR/run-vm"

echo "Compiling Swift VM runner..."
swiftc \
  -framework Virtualization \
  -o "$SWIFT_BIN" \
  "$SWIFT_RUNNER"

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

echo "Signing VM runner with virtualization entitlement..."
codesign --sign - --entitlements "$ENTITLEMENTS" --force "$SWIFT_BIN"

# === Phase A: Autoinstall (foreground; boots from ISO, exits on shutdown) ===
# The autoinstall user-data ends with `shutdown -h now`, so the runner returns
# once installation completes and the VM powers off. Running in the foreground
# gives us a clear "install done" signal before we boot the installed system.
echo "=== Phase A: Running autoinstall (this blocks until install completes) ==="
"$SWIFT_BIN" \
  "$AUTOINSTALL_ISO" \
  "$CIDATA_ISO" \
  "$OS_DISK" \
  "$HLS_DISK" \
  "$RAM_MB" \
  "$CPU_COUNT" \
  "$WORKER_MAC" \
  > "$VM_DIR/vm-install.log" 2>&1
echo "Autoinstall finished; VM powered off after install."

# === Phase B: Boot the installed OS (background; no install media attached) ===
# Passing "none" for the ISO and CIDATA paths detaches them, so EFI boots from
# the installed OS disk. This is the phase that brings SSH up on the network.
echo "=== Phase B: Booting installed OS from disk ==="
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
echo "VM booted from disk in background (PID $(cat "$VM_DIR/vm.pid")). Log: $VM_DIR/vm.log"
echo "Worker VM should come up on the network shortly; Mint can poll for SSH."
