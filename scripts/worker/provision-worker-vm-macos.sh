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
VM_NAME="worker-arm"
VM_DIR="$HOME/VMs/${VM_NAME}"

ISO_PATH="$HOME/worker-autoinstall.iso"

OS_DISK_SIZE_GB=20
HLS_DISK_SIZE_GB=20

RAM_MB=4096
CPU_COUNT=4

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

if [ ! -f "$ISO_PATH" ]; then
  echo "ERROR: Autoinstall ISO not found at: $ISO_PATH"
  exit 1
fi

mkdir -p "$VM_DIR"

# === 2. Create disk images ===
OS_DISK="$VM_DIR/os.img"
HLS_DISK="$VM_DIR/hls.img"

if [ ! -f "$OS_DISK" ]; then
  echo "Creating OS disk (${OS_DISK_SIZE_GB}GB)..."
  dd if=/dev/zero bs=1m count=$(( OS_DISK_SIZE_GB * 1024 )) of="$OS_DISK" 2>/dev/null
fi

if [ ! -f "$HLS_DISK" ]; then
  echo "Creating HLS disk (${HLS_DISK_SIZE_GB}GB)..."
  dd if=/dev/zero bs=1m count=$(( HLS_DISK_SIZE_GB * 1024 )) of="$HLS_DISK" 2>/dev/null
fi

# === 3. Write Swift VM runner ===
SWIFT_RUNNER="$VM_DIR/run-vm.swift"

cat > "$SWIFT_RUNNER" <<'SWIFT'
import Virtualization
import Foundation

guard CommandLine.arguments.count == 5 else {
    fputs("Usage: run-vm <iso-path> <os-disk> <hls-disk> <ram-mb>\n", stderr)
    exit(1)
}

let isoPath   = CommandLine.arguments[1]
let osDisk    = CommandLine.arguments[2]
let hlsDisk   = CommandLine.arguments[3]
let ramMB     = Int(CommandLine.arguments[4]) ?? 4096

// --- Boot loader: EFI (required for Linux on Apple Virtualization) ---
let efi = VZEFIBootLoader()
let efiStore = try! VZEFIVariableStore(creatingVariableStoreAt: URL(fileURLWithPath: osDisk + ".efi"), options: [])
efi.variableStore = efiStore

// --- CPU & memory ---
let config = VZVirtualMachineConfiguration()
config.cpuCount = 4
config.memorySize = UInt64(ramMB) * 1024 * 1024
config.bootLoader = efi

// --- Storage: ISO (read-only) ---
let isoAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: isoPath), readOnly: true)
let isoDevice = VZVirtioBlockDeviceConfiguration(attachment: isoAttachment)

// --- Storage: OS disk ---
let osAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: osDisk), readOnly: false)
let osDevice = VZVirtioBlockDeviceConfiguration(attachment: osAttachment)

// --- Storage: HLS disk ---
let hlsAttachment = try! VZDiskImageStorageDeviceAttachment(url: URL(fileURLWithPath: hlsDisk), readOnly: false)
let hlsDevice = VZVirtioBlockDeviceConfiguration(attachment: hlsAttachment)

config.storageDevices = [isoDevice, osDevice, hlsDevice]

// --- Network: NAT (DHCP) ---
let network = VZVirtioNetworkDeviceConfiguration()
network.attachment = VZNATNetworkDeviceAttachment()
config.networkDevices = [network]

// --- Serial console (stdout) ---
let serial = VZVirtioConsoleDeviceSerialPortConfiguration()
let serialPort = VZFileHandleSerialPortAttachment(
    fileHandleForReading: FileHandle.standardInput,
    fileHandleForWriting: FileHandle.standardOutput
)
serial.attachment = serialPort
config.serialPorts = [serial]

// --- Entropy ---
config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]

try! config.validate()

let vm = VZVirtualMachine(configuration: config)

let sema = DispatchSemaphore(value: 0)
vm.start { result in
    switch result {
    case .success:
        print("VM started successfully.")
    case .failure(let err):
        fputs("Failed to start VM: \(err)\n", stderr)
        exit(1)
    }
}

// Keep process alive until VM stops
NotificationCenter.default.addObserver(forName: NSNotification.Name("VZVirtualMachineStateDidChange"), object: vm, queue: nil) { _ in
    if vm.state == .stopped || vm.state == .error {
        sema.signal()
    }
}

sema.wait()
SWIFT

echo "Swift VM runner written to: $SWIFT_RUNNER"

# === 4. Compile and run Swift VM runner ===
SWIFT_BIN="$VM_DIR/run-vm"

echo "Compiling Swift VM runner..."
swiftc \
  -framework Virtualization \
  -o "$SWIFT_BIN" \
  "$SWIFT_RUNNER"

echo "Starting VM '${VM_NAME}' via Apple Virtualization.framework..."
"$SWIFT_BIN" \
  "$ISO_PATH" \
  "$OS_DISK" \
  "$HLS_DISK" \
  "$RAM_MB"

echo "VM started. Autoinstall is running inside the VM."
echo "Mint can begin polling for SSH on the worker IP."
