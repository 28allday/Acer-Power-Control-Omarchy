# Acer Power Control - Omarchy

GPU power and turbo mode setup for Acer Nitro/Predator laptops running [Omarchy](https://omarchy.com).

Unlocks the full GPU power range (up to 60W) by enabling the `acer_wmi` predator mode kernel module option, setting the platform profile to performance, and enabling NVIDIA Dynamic Boost via `nvidia-powerd`.

## Requirements

- **OS**: [Omarchy](https://omarchy.com) (Arch Linux)
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

Writes `performance` to `/sys/firmware/acpi/platform_profile`, unlocking higher GPU power states controlled by the laptop's Embedded Controller (EC).

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
| `/sys/firmware/acpi/platform_profile` | Set to `performance` (runtime, not persistent) |

## Uninstalling

```bash
# Remove module config
sudo rm -f /etc/modprobe.d/acer-wmi.conf

# Disable nvidia-powerd if desired
sudo systemctl disable nvidia-powerd

# Reboot to restore defaults
```

## Credits

- [Omarchy](https://omarchy.com) - The Arch Linux distribution this was built for
- [Acer WMI kernel module](https://www.kernel.org/) - Provides predator/turbo mode support

## License

This project is provided as-is for the Omarchy community.
