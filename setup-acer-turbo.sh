#!/bin/bash
set -e

echo "=== Acer Nitro GPU Power Setup ==="
echo ""

# Root is required because this script writes to system config files
# (/etc/modprobe.d/) and kernel interfaces (/sys/firmware/).
# If not root, it re-launches itself with sudo so the user doesn't
# have to remember to type "sudo" manually.
if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

CONF="/etc/modprobe.d/acer-wmi.conf"

# Step 1: Ensure predator_v4 module option is configured
#
# The acer_wmi kernel module talks to the Acer laptop's WMI interface.
# By default it runs in basic mode. Setting predator_v4=1 tells the
# module to enable "Predator" mode, which unlocks the higher GPU power
# states (up to 60W) that the Embedded Controller (EC) can provide.
#
# This writes a config file that the kernel reads at boot time when
# loading the acer_wmi module. It only needs to be written once — after
# that the file persists across reboots.
if ! grep -qs "predator_v4=1" "$CONF" 2>/dev/null; then
    echo "Configuring acer_wmi with predator_v4=1 ..."
    echo "options acer_wmi predator_v4=1" > "$CONF"
    echo "Written: $CONF"
fi

# Step 2: Check if predator_v4 is active (requires reboot after first run)
#
# The module option from Step 1 only takes effect when the acer_wmi
# module is loaded — which happens at boot. This step reads the live
# kernel parameter to see if predator_v4 is actually active right now.
#
# If it shows "Y", we're good. If not, a reboot is needed so the
# kernel reloads the module with the new option. The script exits here
# on first run and asks the user to reboot, then run it again.
CURRENT=$(cat /sys/module/acer_wmi/parameters/predator_v4 2>/dev/null || echo "unknown")

if [[ "$CURRENT" != "Y" ]]; then
    echo ""
    echo "predator_v4 is not active yet."
    echo "A reboot is required for the module option to take effect."
    echo ""
    read -p "Reboot now? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        echo "Rebooting..."
        systemctl reboot
    else
        echo "Reboot when ready, then run this script again."
    fi
    exit 0
fi

echo "predator_v4: active"

# Step 3: Set platform profile to performance
#
# Linux exposes a "platform profile" interface that controls the
# laptop's overall power/thermal strategy. The options are typically:
#   - low-power    (quiet, battery-friendly, fans stay low)
#   - balanced     (default, moderate performance)
#   - performance  (full power, fans spin up as needed)
#
# Setting "performance" tells the laptop firmware to allow the CPU and
# GPU to draw more power. This is a runtime setting — it does NOT
# survive a reboot, so it needs to be set each time (or automated
# via a systemd service).
echo "performance" > /sys/firmware/acpi/platform_profile 2>/dev/null && \
    echo "Platform profile: performance" || \
    echo "Warning: Could not set platform profile"

# Step 4: Enable nvidia-powerd for Dynamic Boost
#
# nvidia-powerd is NVIDIA's Dynamic Boost daemon. It monitors CPU and
# GPU workloads in real time and shifts power between them dynamically.
# For example, in a GPU-heavy game it gives more wattage to the GPU;
# in a CPU-heavy compile it shifts power to the CPU.
#
# This step enables the service so it starts automatically on every
# boot and also starts it immediately. If the service doesn't exist
# (e.g. no NVIDIA driver installed), it's skipped gracefully.
if systemctl is-enabled nvidia-powerd &>/dev/null; then
    echo "nvidia-powerd: enabled"
else
    if systemctl enable --now nvidia-powerd &>/dev/null; then
        echo "nvidia-powerd: enabled and started"
    else
        echo "nvidia-powerd: not available (optional)"
    fi
fi

# Show current GPU power state
#
# Queries nvidia-smi to display the current and maximum power limits
# so the user can verify the setup worked. After pressing the Turbo
# key a few times, the "Current Power Limit" should climb up to 60W.
echo ""
CURRENT_PL=$(nvidia-smi -q -d POWER 2>/dev/null | grep "Current Power Limit" | head -1 | awk '{print $5, $6}')
MAX_PL=$(nvidia-smi -q -d POWER 2>/dev/null | grep "Max Power Limit" | head -1 | awk '{print $5, $6}')
echo "GPU power limit: ${CURRENT_PL:-unknown} (max: ${MAX_PL:-unknown})"

echo ""
echo "=== Setup complete ==="
echo ""
echo "The platform profile is set to 'performance' but GPU power is"
echo "controlled by the EC (Embedded Controller) via the Turbo key."
echo ""
echo "After each reboot, press the TURBO KEY (NitroSense button) on"
echo "your keyboard to cycle through GPU power levels:"
echo ""
echo "  35W -> 40W -> 50W -> 60W (max)"
echo ""
echo "Press it 3-4 times until nvidia-smi shows 60W."
echo ""
echo "Quick check command:"
echo "  nvidia-smi -q -d POWER | grep 'Current Power Limit'"
echo ""
