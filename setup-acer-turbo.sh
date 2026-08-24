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

# Step 0: Sanity-check that this kernel's acer_wmi supports predator_v4
#
# Without this check, unsupported hardware (or a kernel built without
# the option) would loop forever: the script would keep asking for a
# reboot that can never make predator_v4 appear. modinfo -p lists the
# parameters the module actually accepts, so we bail out early with a
# clear message instead.
if ! modinfo -p acer_wmi 2>/dev/null | grep -q "^predator_v4:"; then
    echo "Error: this kernel's acer_wmi module does not support the"
    echo "predator_v4 option (or the module is missing entirely)."
    echo "This script is for Acer Predator/Nitro laptops on a recent kernel."
    exit 1
fi

# Step 1: Ensure predator_v4 module option is configured
#
# The acer_wmi kernel module talks to the Acer laptop's WMI interface.
# By default it runs in basic mode. Setting predator_v4=1 tells the
# module to enable "Predator" mode, which unlocks the higher GPU power
# states (up to 60W) that the Embedded Controller (EC) can provide.
#
# This writes a config file that the kernel reads at boot time when
# loading the acer_wmi module. It only needs to be written once — after
# that the file persists across reboots. Any stale predator_v4 line is
# removed first so other options in the file are preserved rather than
# the whole file being overwritten.
if ! grep -qs "predator_v4=1" "$CONF"; then
    echo "Configuring acer_wmi with predator_v4=1 ..."
    [[ -f "$CONF" ]] && sed -i '/predator_v4/d' "$CONF"
    echo "options acer_wmi predator_v4=1" >> "$CONF"
    echo "Written: $CONF"
fi

# Step 2: Check if predator_v4 is active, reloading the module if not
#
# The module option from Step 1 only takes effect when the acer_wmi
# module is loaded. This step reads the live kernel parameter to see if
# predator_v4 is actually active right now.
#
# If it isn't, acer_wmi is a loadable module, so in most cases we can
# simply unload and reload it to pick up the new option — no reboot
# needed. The reboot prompt is only the fallback for when the reload
# fails (e.g. the module is busy or built into the kernel).
CURRENT=$(cat /sys/module/acer_wmi/parameters/predator_v4 2>/dev/null || echo "unknown")

if [[ "$CURRENT" != "Y" ]]; then
    echo "predator_v4 is not active yet. Trying a module reload..."
    if modprobe -r acer_wmi 2>/dev/null && modprobe acer_wmi 2>/dev/null; then
        CURRENT=$(cat /sys/module/acer_wmi/parameters/predator_v4 2>/dev/null || echo "unknown")
    fi
fi

if [[ "$CURRENT" != "Y" ]]; then
    echo ""
    echo "Module reload didn't activate predator_v4."
    echo "A reboot is required for the option to take effect."
    echo ""
    # "|| answer=n" keeps non-interactive runs (piped input, EOF on
    # stdin) from being killed by set -e mid-prompt.
    read -rp "Reboot now? [y/N] " answer || answer=n
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
# There are three ways to set it, tried best-first:
#
#   1. omarchy-powerprofiles-set — Omarchy 4 keeps its own record of the
#      profile you want on AC and on battery, and re-applies it at every
#      session start and every AC/battery transition. A plain
#      powerprofilesctl call is therefore undone the next time you log in
#      or unplug the laptop. Going through the helper stores the choice
#      where Omarchy looks for it, so it survives both. The "ac" key is
#      the one we want: this unlocks wattage that only matters on mains,
#      and it leaves the battery profile alone.
#
#      The record lives under the user's home, so this must run as the
#      invoking user rather than as root — otherwise it lands in root's
#      home and the desktop session never sees it.
#
#   2. powerprofilesctl — for a plain power-profiles-daemon system with
#      no Omarchy helper. The daemon considers itself the owner of the
#      platform profile, so a raw sysfs write behind its back can be
#      silently reset.
#
#   3. A direct sysfs write — last resort for systems with no daemon at
#      all, where the setting is runtime-only and lost on reboot.
if [[ -n "${SUDO_USER:-}" ]] && command -v omarchy-powerprofiles-set &>/dev/null; then
    if sudo -u "$SUDO_USER" omarchy-powerprofiles-set ac performance; then
        echo "Platform profile: performance on AC (via Omarchy, remembered)"
    else
        echo "Warning: omarchy-powerprofiles-set could not set the profile"
    fi
elif command -v powerprofilesctl &>/dev/null && systemctl is-active --quiet power-profiles-daemon; then
    powerprofilesctl set performance 2>/dev/null && \
        echo "Platform profile: performance (via power-profiles-daemon)" || \
        echo "Warning: powerprofilesctl could not set the profile"
else
    echo "performance" > /sys/firmware/acpi/platform_profile 2>/dev/null && \
        echo "Platform profile: performance (runtime only — re-run after reboot)" || \
        echo "Warning: Could not set platform profile"
fi

# Step 4: Enable nvidia-powerd for Dynamic Boost
#
# nvidia-powerd is NVIDIA's Dynamic Boost daemon. It monitors CPU and
# GPU workloads in real time and shifts power between them dynamically.
# For example, in a GPU-heavy game it gives more wattage to the GPU;
# in a CPU-heavy compile it shifts power to the CPU.
#
# This step enables the service so it starts automatically on every
# boot and also starts it immediately. is-active (not is-enabled) is
# checked first so a dead-but-enabled service still gets started. If
# the service doesn't exist (e.g. no NVIDIA driver installed), it's
# skipped gracefully.
if systemctl is-active --quiet nvidia-powerd 2>/dev/null; then
    echo "nvidia-powerd: running"
else
    if systemctl enable --now nvidia-powerd &>/dev/null; then
        echo "nvidia-powerd: enabled and started"
    else
        echo "nvidia-powerd: not available (optional)"
    fi
fi

# Show current GPU power state
#
# Queries nvidia-smi (once) to display the current and maximum power
# limits so the user can verify the setup worked. After pressing the
# Turbo key a few times, the "Current Power Limit" should climb up
# to 60W.
echo ""
POWER_INFO=$(nvidia-smi -q -d POWER 2>/dev/null || true)
CURRENT_PL=$(grep "Current Power Limit" <<<"$POWER_INFO" | head -1 | awk '{print $5, $6}')
MAX_PL=$(grep "Max Power Limit" <<<"$POWER_INFO" | head -1 | awk '{print $5, $6}')
echo "GPU power limit: ${CURRENT_PL:-unknown} (max: ${MAX_PL:-unknown})"

echo ""
echo "=== Setup complete ==="
echo ""
echo "GPU power is controlled by the EC (Embedded Controller) via the"
echo "Turbo key."
echo ""
echo "After each reboot, press the TURBO KEY (NitroSense button) on"
echo "your keyboard to cycle through GPU power levels. The levels are"
echo "defined by your machine's EC — e.g. on a Nitro 5 with a 60W GPU:"
echo ""
echo "  35W -> 40W -> 50W -> 60W"
echo ""
echo "Press it a few times until nvidia-smi shows ${MAX_PL:-the GPU maximum}."
echo ""
echo "Quick check command:"
echo "  nvidia-smi -q -d POWER | grep 'Current Power Limit'"
echo ""
