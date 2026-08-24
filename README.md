# Acer Power Control - Omarchy

## 🎬 Video Demo

[![Watch the video](https://img.youtube.com/vi/Hq3Wk7YZY-s/0.jpg)](https://youtu.be/Hq3Wk7YZY-s)

GPU power and turbo mode setup for Acer Nitro/Predator laptops running [Omarchy](https://omarchy.com).

Unlocks the full GPU power range (up to 60W) by enabling the `acer_wmi` predator mode kernel module option, setting the platform profile to performance, and enabling NVIDIA Dynamic Boost via `nvidia-powerd`.

## Requirements

- **OS**: [Omarchy](https://omarchy.com) (Arch Linux) — works on Omarchy 4 ("Quattro") and earlier
- **Hardware**: Acer Nitro or Predator laptop with NVIDIA dGPU
- **Kernel**: Must have `CONFIG_ACER_WMI` enabled (default on Arch)

## Quick Start

```bash
git clone https://github.com/28allday/Acer-Power-Control-Omarchy.git
cd Acer-Power-Control-Omarchy
chmod +x setup-acer-turbo.sh
./setup-acer-turbo.sh
```

The script will re-run with `sudo` automatically if not run as root.

**First run requires a reboot** - the `predator_v4` module option only takes effect after reboot. Run the script again after rebooting to complete setup.

## What It Does

The script performs four steps:

### 1. Configure acer_wmi Module

Writes `/etc/modprobe.d/acer-wmi.conf` with `predator_v4=1` to enable turbo power mode support in the Acer WMI kernel module.

### 2. Activate Predator Mode

Checks `/sys/module/acer_wmi/parameters/predator_v4` to verify the module option is active. If not, prompts for a reboot.

### 3. Set Platform Profile to Performance

Switches the laptop to the `performance` platform profile, unlocking higher GPU power states controlled by the Embedded Controller (EC).

On Omarchy 4 this goes through `omarchy-powerprofiles-set ac performance`. Omarchy 4 remembers a separate profile for mains and for battery, and re-applies it every time you log in or plug/unplug the laptop — so setting the profile any other way gets quietly undone. Recording it as the **AC** profile makes it stick, and leaves your battery profile untouched.

On systems without that helper the script falls back to `powerprofilesctl`, and then to a direct write to `/sys/firmware/acpi/platform_profile`.

### 4. Enable nvidia-powerd

Enables and starts `nvidia-powerd.service` for NVIDIA Dynamic Boost, which allows the GPU to dynamically allocate power between the CPU and GPU based on workload.

## Usage After Setup

After each reboot, press the **Turbo Key** (NitroSense button) on your keyboard to cycle through GPU power levels:

```
35W -> 40W -> 50W -> 60W (max)
```

Press it 3-4 times until you reach the desired power level.

### Quick Check

```bash
nvidia-smi -q -d POWER | grep 'Current Power Limit'
```

## Files Modified

| Path | Purpose |
|------|---------|
| `/etc/modprobe.d/acer-wmi.conf` | Enables `predator_v4=1` module option |
| `~/.local/state/omarchy/powerprofiles/ac` | Records `performance` as your on-mains profile (Omarchy 4) |
| `/sys/firmware/acpi/platform_profile` | Set to `performance` (fallback path only, runtime, not persistent) |

## Uninstalling

```bash
# Remove module config
sudo rm -f /etc/modprobe.d/acer-wmi.conf

# Go back to the balanced profile on mains (Omarchy 4)
omarchy-powerprofiles-set ac balanced

# Disable nvidia-powerd if desired
sudo systemctl disable nvidia-powerd

# Reboot to restore defaults
```

## Credits

- [Omarchy](https://omarchy.com) - The Arch Linux distribution this was built for
- [Acer WMI kernel module](https://www.kernel.org/) - Provides predator/turbo mode support

## License

This project is provided as-is for the Omarchy community.
