# t2chill

**Keep a T2 Mac mini (2018) cool under Linux, with no kernel patches needed.**

Linux runs well on the 2018 Mac mini, but it has no driver for the **T2 chip**, which is where Apple put fan control. Meanwhile, Apple's firmware lets the CPU draw **100W sustained / 125W burst** and sprint to full turbo, on the assumption that macOS will spin the fan up to match. Under Linux, that assumption breaks. The result:

- The CPU sits in the **80s–90s °C while mostly idle**, and cores spike to the **100°C limit**
- The CPU **throttles hundreds of times a minute**
- Possibly: **sudden power-offs with nothing in the logs**, if the Mac's own hardware protection kicks in. This was the suspected cause on the machine t2chill was built for, though it's not yet proven.

t2chill fixes the heat **at the source**. It stops the CPU from sprinting and caps how much power it can turn into heat. A server-style workload barely notices.

## Results

Measured on a Mac mini 2018 (Macmini8,1, Core i7-8700B, 32GB) running a Bitcoin and Lightning node on umbrelOS 2.0 (Debian 13, kernel 6.12):

| Setting | Throttle events per minute | Peak temperature |
|---|---|---|
| Firmware defaults | ~440 | 100°C |
| + `balance_power` | ~100 | 95°C |
| **+ turbo off (t2chill default)** | **0** over the measured window | 85°C (one brief spike; mostly 55–68°C) |

Average clock speed at idle went from **~3,755MHz to ~900MHz**. Before the fix, the cores were never actually resting.

## Does this apply to you?

- **Hardware:** built for the **Mac mini 2018 (`Macmini8,1`)**. It only uses standard Intel power controls, so it's safe on other T2 Intel Macs too, but it was only tested on the mini.
- **OS:** any Linux with **systemd** and the default **`intel_pstate`** CPU driver: Debian, Ubuntu, Fedora, Arch, umbrelOS, etc.
- **You'll need:** `sudo` access.

### Check before installing

You can run t2chill straight from the cloned folder without installing anything:

```bash
git clone https://github.com/Tomcatt/t2chill.git
cd t2chill
sudo ./t2chill status
```

Signs you need it:
- **The package temperature** reads in the 80s–90s while the machine is mostly idle.
- **"last 5s" shows throttle events.** Anything above zero on an idle machine means the CPU is hitting its temperature limit.
- **No fans are listed** in `sensors` or `/sys/class/hwmon/*/fan*`. That means Linux can't see the fan.

## Install

```bash
git clone https://github.com/Tomcatt/t2chill.git
cd t2chill
sudo ./install.sh                 # or: sudo ./install.sh --with-logger
```

The installer **applies the settings immediately and at every boot**, then prints a status report.

What it installs:

| Path | What it is |
|---|---|
| `/usr/local/sbin/t2chill` | the tool |
| `/etc/systemd/system/t2chill.service` | applies the settings at boot; `stop` reverts them |
| `/etc/default/t2chill` | your settings (only created if it doesn't already exist) |
| `/var/lib/t2chill/` | backups of the original values, plus the thermal log |
| `/etc/systemd/system/t2chill-log.{service,timer}` | optional thermal logger (enabled by `--with-logger`) |

### `--with-logger` (recommended)

This records one line a minute to `/var/lib/t2chill/temps.csv`: temperature, hottest core, throttle count and clock speed. Each line is **synced to disk as it's written**, so if the machine ever dies suddenly, the readings from right before it survive. Use it to confirm the fix over days, not minutes. It grows by about 90KB a day.

### umbrelOS and other image-based systems

umbrelOS replaces its system files on every OS update, so `/usr/local`, `/etc` and `/var/lib` start fresh. To handle that:

1. Clone t2chill somewhere that survives updates, such as your home folder (`~/t2chill`).
2. **After every OS update, run `sudo ./install.sh` again** (with `--with-logger` if you use it). It takes seconds and recaptures the firmware defaults, which the update restores anyway.

## Use

| Command | What it does |
|---|---|
| `sudo t2chill status` | Settings, temperatures, and live power draw + throttle rate (without `sudo` it skips the live numbers) |
| `sudo t2chill apply` | Back up the current values, then apply your settings |
| `sudo t2chill revert` | Restore the firmware defaults saved by the first `apply` |
| `t2chill log` | Append one thermal reading to the log (normally the timer runs this) |
| `t2chill --version` | Version |

**Pause it:** `sudo systemctl stop t2chill` restores the firmware defaults right away.
**Resume:** `sudo systemctl start t2chill`

### Settings

Edit `/etc/default/t2chill`, then run `sudo systemctl restart t2chill`:

```bash
PL1_W=35          # sustained power limit, watts (firmware: 100)
PL2_W=45          # short burst limit, watts (firmware: 125)
EPP=balance_power # performance | balance_performance | balance_power | power
TURBO_OFF=1       # 1 = cap at base clock, 0 = keep turbo
```

If your machine needs more single-core speed and runs a lighter load, try `TURBO_OFF=0` first and watch the log. `balance_power` alone cut throttling by about 75% in testing.

### Reading the log

```bash
tail /var/lib/t2chill/temps.csv
# utc,pkg_c,max_core_c,pkg_throttle_total,avg_mhz,epp,no_turbo

# throttle events per minute over the last hour (should be ~0):
tail -60 /var/lib/t2chill/temps.csv | awk -F, 'NR==1{a=$4} END{print ($4-a)/59, "per minute"}'
```

## Uninstall

```bash
cd t2chill
sudo ./uninstall.sh               # keeps your settings, backups and log
sudo ./uninstall.sh --purge       # removes those too
```

Uninstalling **restores the firmware defaults immediately**, so there's no need to reboot. It removes the tool and its systemd units.

**If you deleted the cloned folder**, remove it by hand:

```bash
sudo systemctl disable --now t2chill-log.timer t2chill.service   # stop = revert
sudo rm -f /etc/systemd/system/t2chill.service /etc/systemd/system/t2chill-log.{service,timer} /usr/local/sbin/t2chill
sudo systemctl daemon-reload
sudo rm -rf /var/lib/t2chill /etc/default/t2chill               # optional
```

## How it works

t2chill sets three standard Linux kernel settings. That's all it does.

| Setting | Path | Default → t2chill | Why |
|---|---|---|---|
| Energy/performance preference | `/sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference` | `balance_performance` → `balance_power` | Stops the CPU from jumping to full speed on every brief bit of work. Those bursts created the hot spots. |
| Turbo | `/sys/devices/system/cpu/intel_pstate/no_turbo` | `0` → `1` | Caps the CPU at its base clock. Turbo sprints were what still drove cores to 95°C. |
| Package power limits | `/sys/class/powercap/intel-rapl:0/constraint_{0,1}_power_limit_uw` | 100W / 125W → 35W / 45W | A ceiling for heavy load. At idle the CPU draws only ~11W, so this rarely engages, but it stops a big job from pushing ~100W into a small box. |

**Safety:**
- **Nothing persists in hardware.** t2chill never writes to the firmware, NVRAM or the SMC. Every change is a runtime kernel setting, so **a reboot always restores the firmware defaults** whether or not t2chill is installed.
- **It backs up before every change.** `apply` saves the current values to `/var/lib/t2chill/before-<time>.env` first. The very first capture is kept as `firmware-defaults.env` and is never overwritten, and `revert` restores it.
- **It never breaks on missing controls.** If one isn't available on your system, it's skipped with a message.

**The trade-off:** with turbo off, single-threaded work runs at the CPU's base clock instead of its boost clock. On the i7-8700B that's 3.2GHz instead of up to 4.6GHz. Servers and other always-on boxes won't notice. A desktop doing heavy single-threaded work might, so try `TURBO_OFF=0`.

## Why not just control the fan?

That's the better fix where you can do it, and the **[t2linux](https://t2linux.org) project** makes it possible. Their patched kernels add the T2 drivers (`apple-bce`, plus an `applesmc` that works on T2 hardware), and `t2fanrd` then controls the fan properly.

t2chill exists for setups where you **can't or don't want to change the kernel**:
- appliance-style systems like umbrelOS
- stock distro kernels
- machines where you'd rather not rebuild out-of-tree drivers after every kernel update

The two can also be combined: a working fan plus less heat to remove.

## Tests

```bash
./tests/test.sh
```

The tests run every command against a fake `/sys` tree, so they need no root and touch no real hardware. They cover apply, the backup, revert restoring the exact values, config overrides, missing controls, and the logger.

## License

MIT. See [LICENSE](LICENSE). No warranty: you're changing CPU power settings on your own hardware. Everything is reversible, and a reboot resets it.
