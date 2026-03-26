#!/bin/bash
set -e

echo "=== Acer Nitro GPU Power Setup ==="
echo ""

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

CONF="/etc/modprobe.d/acer-wmi.conf"

# Step 1: Ensure predator_v4 module option is configured
if ! grep -qs "predator_v4=1" "$CONF" 2>/dev/null; then
    echo "Configuring acer_wmi with predator_v4=1 ..."
    echo "options acer_wmi predator_v4=1" > "$CONF"
    echo "Written: $CONF"
fi

# Step 2: Check if predator_v4 is active (requires reboot after first run)
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
echo "performance" > /sys/firmware/acpi/platform_profile 2>/dev/null && \
    echo "Platform profile: performance" || \
    echo "Warning: Could not set platform profile"

# Step 4: Enable nvidia-powerd for Dynamic Boost
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
