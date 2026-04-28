#!/bin/bash
set -euo pipefail

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
if ! grep -Eqs '^[[:space:]]*options[[:space:]]+acer_wmi[[:space:]].*predator_v4=1' "$CONF" 2>/dev/null; then
    echo "Configuring acer_wmi with predator_v4=1 ..."
    echo "options acer_wmi predator_v4=1" > "$CONF"
    echo "Written: $CONF"
else
    echo "acer_wmi config: already configured"
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

# Step 4: Per-GPU power tuning
#
# Acer Nitro/Predator ships with NVIDIA, AMD, or Intel GPUs depending
# on the model. Detect what's present and apply the vendor-appropriate
# power knob. The acer_wmi + platform_profile steps above already
# unlocked the chassis side; this step is the GPU side.
GPU_VENDORS=$(lspci -nn | grep -Ei 'VGA|3D|Display' || true)
HAS_NVIDIA=0
HAS_AMD=0
HAS_INTEL=0
echo "$GPU_VENDORS" | grep -qi 'nvidia'        && HAS_NVIDIA=1
echo "$GPU_VENDORS" | grep -qiE 'amd|ati|advanced micro' && HAS_AMD=1
echo "$GPU_VENDORS" | grep -qi 'intel'         && HAS_INTEL=1

if [[ $HAS_NVIDIA -eq 1 ]]; then
    # nvidia-powerd is NVIDIA's Dynamic Boost daemon. It shifts power
    # between CPU and GPU based on workload. enable --now is a no-op if
    # already in that state, so call it unconditionally.
    if systemctl cat nvidia-powerd.service &>/dev/null; then
        if systemctl enable --now nvidia-powerd &>/dev/null; then
            echo "nvidia-powerd: enabled and started"
        else
            echo "nvidia-powerd: present but failed to enable"
        fi
    else
        echo "nvidia-powerd: not installed (optional, ships with nvidia-utils)"
    fi

    # Report current/max power limits via the machine-readable interface.
    if command -v nvidia-smi &>/dev/null; then
        echo ""
        nvidia-smi --query-gpu=name,power.limit,power.max_limit \
            --format=csv,noheader,nounits 2>/dev/null \
            | awk -F', ' '{printf "GPU power limit: %s — %s W (max: %s W)\n", $1, $2, $3}'
    fi
fi

if [[ $HAS_AMD -eq 1 ]]; then
    # AMD dGPUs (e.g. Radeon RX 6600M in AMD-Advantage Nitro models)
    # are tuned via amdgpu sysfs. Setting the DPM performance level to
    # "high" pins the GPU at its top P-state; the default "auto" lets
    # the driver scale. Done at runtime; does not survive reboot.
    AMD_SET=0
    for card in /sys/class/drm/card*/device; do
        [[ -e "$card/vendor" ]] || continue
        # AMD PCI vendor ID = 0x1002
        [[ "$(cat "$card/vendor" 2>/dev/null)" == "0x1002" ]] || continue
        [[ -w "$card/power_dpm_force_performance_level" ]] || continue
        echo high > "$card/power_dpm_force_performance_level" 2>/dev/null && AMD_SET=1
    done
    if [[ $AMD_SET -eq 1 ]]; then
        echo "amdgpu: power_dpm_force_performance_level=high"
    else
        echo "amdgpu: detected but no writable DPM control found"
    fi
fi

if [[ $HAS_INTEL -eq 1 && $HAS_NVIDIA -eq 0 && $HAS_AMD -eq 0 ]]; then
    # Intel-only system: platform_profile (step 3) plus intel_pstate
    # already cover Intel iGPU power. No additional knob needed.
    echo "Intel GPU: managed via platform_profile (no extra step)"
fi

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
echo "Press it 3-4 times until the GPU reaches 60W."
echo ""
echo "Quick check command:"
if [[ $HAS_NVIDIA -eq 1 ]]; then
    echo "  nvidia-smi --query-gpu=power.limit --format=csv,noheader"
elif [[ $HAS_AMD -eq 1 ]]; then
    echo "  cat /sys/class/drm/card*/device/hwmon/hwmon*/power1_cap 2>/dev/null"
else
    echo "  cat /sys/firmware/acpi/platform_profile"
fi
echo ""
