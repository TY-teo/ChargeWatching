<div align="center">

# ChargeWatch

**macOS menu bar charging power monitor + native-grade battery charge limit**

See exactly where every watt goes, and let the battery truly *rest* once it reaches your limit — no charging, no discharging, with the whole Mac running straight off the power adapter.

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Apple Silicon](https://img.shields.io/badge/charge%20limit-Apple%20Silicon-555555?style=flat-square&logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![Version](https://img.shields.io/badge/version-v0.7.0-2563EB?style=flat-square)](https://github.com/TY-teo/ChargeWatching/releases)
[![License](https://img.shields.io/badge/license-MIT-3DA639?style=flat-square)](LICENSE)

**English · [Русский](README.ru.md) · [简体中文](README.md)**

<table>
  <tr>
    <td><img src="picture/charge-limit-redesign-light.png" width="420" alt="ChargeWatch menu bar panel on macOS showing real-time charging power, system load and wall output (light mode)" /></td>
    <td><img src="picture/charge-limit-redesign-dark.png" width="420" alt="Setting a battery charge limit in ChargeWatch, a free open-source AlDente alternative for Apple Silicon (dark mode)" /></td>
  </tr>
</table>

</div>

---

## What is ChargeWatch

ChargeWatch is a free, open-source (MIT) macOS menu bar app for Apple Silicon Macs that does two things at once: it shows real-time charging power and it sets a battery charge limit. When the limit is reached, ChargeWatch stops charging without discharging the battery — the Mac runs straight off the power adapter while battery current stays near 0. It is a free AlDente alternative, and it can hold limits even below 80%, which the native macOS battery charge limit cannot.

> Repository note: the app is named **ChargeWatch**; the GitHub repository is **ChargeWatching** (`github.com/TY-teo/ChargeWatching`). They are the same project. The ChargeWatch app lives in the ChargeWatching repository.

ChargeWatch combines two jobs that other tools usually keep separate. Most battery tools either limit charging (AlDente, batt, Battery Toolkit) or monitor power (coconutBattery, Watts, Stats) — ChargeWatch is a single menu bar app that does both.

Key facts for quick reference:

- macOS menu bar charging power monitor: splits power into battery, system load, and wall output, computed from instantaneous voltage x current (not adapter nameplate ratings), sampled at about 1 Hz.
- macOS battery charge limit on Apple Silicon: writes the SMC charge-control key `CHTE` to stop charging at your limit (default 80%, configurable, can go below 80%) with no kernel extension and no Shortcuts dependency.
- Stop charging without discharging: at the limit the adapter stays connected, the system still sees external power, and the battery is held at roughly 0 current — no extra charge cycles.
- 5% hysteresis before recharge, optional 7-day full-charge calibration, and multiple fail-safes that restore normal charging on quit, crash, or any read error.
- Fully local and private: no network, no tracking; history stays in a local SQLite database.
- Requirements: macOS 13 or later for power monitoring; Apple Silicon (M-series) for the charge limit. Tested on macOS 26.4 Tahoe + Apple Silicon.

Keywords: ChargeWatch, ChargeWatch GitHub, macOS battery charge limit, battery charge limiter Apple Silicon, menu bar charging power monitor, charging wattage in the menu bar, free open-source AlDente alternative, stop charging without discharging, limit MacBook charging to 80% or below.

---

## In short

ChargeWatch is a small utility that lives in the macOS menu bar. It does two things, and does both properly:

1. **Show the real power** — it breaks the readings apart into "how many watts go into the battery", "how many watts the system itself consumes" and "how many watts the wall socket actually delivers". The numbers come from hardware telemetry — instantaneous voltage times current — not from the rating printed on the adapter.
2. **Protect the battery** — you can set a charge limit (80% by default). Once the limit is reached, ChargeWatch stops charging the battery but **does not disconnect the power adapter**: the whole Mac switches to adapter power and battery current is clamped to roughly 0, neither charging nor discharging, resting quietly near the limit.

This is not a crude "charge to full, then unplug and drain" approach — it takes the gentler "stop charging without discharging" route. The two chapters below explain the mechanism in full.

---

## Features

- **Three-way power breakdown**: into battery, system load and wall output, each shown separately.
- **Instantaneous measurement**: sampled at about 1 Hz, with an immediate extra sample whenever you plug or unplug power or the charge state changes.
- **Native-grade charge limit**: writes the Apple Silicon SMC register directly, with no dependency on Shortcuts and no third-party kernel extension.
- **Stop charging without discharging**: at the limit the battery rests and the adapter powers the machine, so no artificial charge cycles are created.
- **5% hysteresis**: recharging only resumes after the level drops more than 5%, avoiding repeated micro-cycles at the limit.
- **Full-charge calibration every 7 days**: periodically allows one full charge to keep the system's fuel-gauge readings accurate.
- **Fail-safe by design**: if the daemon exits, is killed, or hits a read error, normal charging is always restored automatically.
- **Local only, zero networking**: all data stays in a local SQLite database — nothing is uploaded, nothing is tracked.
- **Native SwiftUI interface**: follows the system light/dark appearance, with a lightweight permanent menu bar presence.
- **Multilingual interface**: English, Russian and Chinese. Follows the macOS language by default and can be switched in Settings.

---

## Screenshots

<div align="center">

<table>
  <tr>
    <td align="center"><img src="picture/charge-limit-redesign-light.png" width="420" alt="Charging power panel and charge limit slider in light mode" /><br/><sub>Light mode</sub></td>
    <td align="center"><img src="picture/charge-limit-redesign-dark.png" width="420" alt="Charging power panel and charge limit slider in dark mode" /><br/><sub>Dark mode</sub></td>
  </tr>
</table>

</div>

---

## Requirements

| Capability | Requirement |
| --- | --- |
| Power monitoring | macOS 13 or later |
| Charge limit | Apple Silicon (M-series chip), tested on macOS 26.4 Tahoe |

> The charge limit is implemented by writing an SMC charge-control key specific to Apple Silicon, so it is only available on Apple Silicon machines. On Intel Macs the power monitoring part works normally.

---

## Download and install

### 1. Download

Go to [Releases](https://github.com/TY-teo/ChargeWatching/releases), download `ChargeWatch-0.7.0.dmg`, open it and drag `ChargeWatch.app` into your Applications folder.

### 2. Opening it the first time (ad-hoc signature)

The app uses an ad-hoc signature (personal open-source distribution, not notarized by Apple), so macOS will block the first launch. Use either of these ways to allow it:

**Option 1: right-click to open**

Right-click the app (or Control-click it), choose "Open", then click "Open" again in the dialog. After that a normal double-click works.

**Option 2: remove the quarantine attribute**

```bash
xattr -dr com.apple.quarantine /Applications/ChargeWatch.app
```

### 3. Enabling the charge limit for the first time

The charge limit needs a daemon running as root to write to the SMC. The first time you flip the charge limit switch in the app, macOS **asks for your administrator password once** in order to install the daemon (`com.chenran.chargewatch.helper`). After that `launchd` starts it automatically and you will not be asked repeatedly.

---

## Usage

1. Once launched, the icon stays in the menu bar; click it to open the panel with the three power readings.
2. Drag the charge limit slider in the panel to your target percentage (60%–80% is recommended).
3. Turn the charge limit switch on and enter your administrator password once to install the daemon.
4. From then on, charging stops automatically at the limit and the adapter powers the machine — no manual steps needed.

---

## Protecting the battery: at the limit it does not discharge, the adapter powers everything

This is the most important difference between ChargeWatch and many similar tools, and the core of how it genuinely protects the battery.

### How it works

When the charge level reaches the limit you set, the daemon writes the charge-control key `CHTE = 1` to the SMC, which means **"stop charging, but keep the power adapter supplying power, and do not discharge the battery"**. At the same time it **deliberately does not disconnect the adapter** (the `CHIE` key, which disconnects it, is left in the connected state).

Three things are therefore true at once:

- the system still sees external power present (`ExternalConnected = Yes`);
- battery current is clamped to roughly 0 — **neither charging nor discharging**;
- the whole machine draws its power directly from the adapter.

So the battery simply rests near the limit, with almost no energy flowing in or out. It is never pushed to and held at 100% for long periods (high-voltage full charge is the main driver of calendar ageing in lithium batteries), and no artificial charge/discharge micro-cycles are created (cycle count is the other main consumer of lithium battery life). Both major sources of wear are reduced at the same time.

### Why not simply "disconnect the adapter and discharge down to the limit"

One class of tools on the market maintains the limit by writing "disconnect adapter" and forcing the level down. That approach has three problems:

- **It really is discharging**: the machine is plugged in, yet the limit is maintained by draining the battery, and every drop has to be charged back up — creating extra charge/discharge micro-cycles.
- **It pollutes the state**: disconnecting the adapter makes the external-power state the system reads look "unplugged", and combined with slow battery state refresh this easily produces high-frequency flapping: "limit → mistaken for unplugged → release → limit again".
- **Heat and stress**: discharging generates heat and adds cycle stress near full charge.

ChargeWatch takes the opposite route.

### Comparing the two approaches

| Aspect | ChargeWatch (CHTE stop-charge) | Adapter-disconnect approach |
| --- | --- | --- |
| Battery state once the limit is reached | Stops charging without discharging, current about 0 | Continuously discharging |
| Where the machine's power comes from | Directly from the power adapter | From the battery |
| Adds charge/discharge cycles? | No (battery rests) | Yes (repeated micro-cycles) |
| External-power state reading | Stays stable (Yes) | Easily polluted, flaps |
| Heat and cycle stress | Low | Higher |

### The supporting design decisions

- **More reliable detection of physical presence**: to decide whether power is plugged in, ChargeWatch reads the SMC `AC-W` key first (byte-wise), rather than the system state, which is polluted by the charge-control logic itself and refreshes slowly. This removes the flapping feedback loop at its root.
- **5% hysteresis**: after charging stops at the limit, recharging only begins once the level has drifted down by more than 5%; in between, the status quo is kept. Under stop-charge semantics the battery mostly drifts down slowly through natural self-discharge, so recharge events are very rare.
- **Full-charge calibration every 7 days**: when 7 days have passed since the last full charge, one charge to 100% is allowed, purely to calibrate the system's fuel gauge and keep the percentage estimate accurate — it is not routine full charging (set it to 0 to disable).
- **Actuator probing at startup**: as long as the machine supports charge-disable semantics, `CHTE` (no discharging) is preferred; only when it is entirely unsupported does it fall back to disconnecting the adapter. Every SMC write is read back and verified to make sure the command really took effect.
- **Fail-safe recovery**: on a termination signal, process exit, a battery read failure, the limit being disabled, a limit of 100, or power being unplugged — in any abnormal situation, normal charging is restored first. The daemon is supervised by `launchd` with `KeepAlive`, so a crash restarts it automatically.

---

## How the power figures are computed, and why they are accurate

Many battery tools simply read the adapter's nameplate rating (67 W, 96 W and so on), or read aggregate fields that are inflated or distorted. ChargeWatch instead takes **instantaneous voltage × instantaneous current** from the lowest-level hardware telemetry and derives the rest through conservation of energy, so the readings stay close to reality.

### Sources and formulas for the three metrics

| Metric | Data source (hardware telemetry) | Formula |
| --- | --- | --- |
| **Into battery** | `Voltage` (mV) and `InstantAmperage` (mA) reported by the battery's coulomb counter | `magnitude = abs(voltage × current) / 1_000_000` (mV×mA→W); the sign comes from `IsCharging`: positive when charging, negative when discharging |
| **System load** | `SystemPowerIn` (total power entering the Mac) and the into-battery power computed above | `system load = max(0, SystemPowerIn − into-battery power)`; on battery power alone it equals the battery discharge magnitude |
| **Wall output** | `SystemPowerIn` and `AdapterEfficiencyLoss` (adapter conversion loss) | `wall output = (SystemPowerIn + AdapterEfficiencyLoss) / 1000` |

### In plain language

- **Into battery**: the battery's present voltage (volts) times the current flowing into it (amps) is the power (watts) being poured into the battery. `InstantAmperage` (instantaneous current, which reflects plugging in immediately) is preferred; when it cannot be read, it falls back to `Amperage`, averaged over a few seconds (slightly laggy). The charging/discharging flag then decides the sign.
- **System load**: the power actually consumed by the chip, display and so on, derived by conservation of energy — when plugged in, part of the total power entering the Mac goes into the battery, and the rest is what the system itself uses. When not plugged in, everything the battery delivers is consumed by the system, so system load equals the battery discharge magnitude.
- **Wall output**: how many watts are actually drawn from the socket/adapter = the power genuinely entering the Mac + the power lost in the adapter's own conversion. Note that this is not the adapter's nameplate rating; the rating is only used for the descriptive label.

### Why it is accurate

- **Instantaneous V×I, not estimates or nameplate values**: the into-battery power comes straight from the instantaneous voltage and current measured and reported by the battery's coulomb counter / charge controller, multiplied together, with no rated values mixed in.
- **Deliberately avoiding distorted fields**: in testing, certain aggregate fields reported "battery power" of about 8 W while real charging was about 56 W, and the "system load" field was inflated by roughly 6×. ChargeWatch therefore derives the values from instantaneous V×I plus conservation of energy instead of reading those fields directly.
- **Total input matches the hardware readings**: wall output / total input is based on `SystemPowerIn`, whose value matches the adapter reading from `system_profiler` — it is measured hardware telemetry.
- **Correct signed decoding**: current is encoded as unsigned 64-bit; the code converts back to signed using 64 bits, avoiding the common bug where 32-bit truncation makes charge/discharge values go negative.

### A few notes

- What you see is an instantaneous snapshot taken about once per second, not a continuous integral.
- When power is connected but certain fields read 0 in the gap between samples, the related reading is recorded as "no data" rather than 0.
- System load is clamped to non-negative with `max(0, …)`, so extreme reading errors are truncated to 0.
- Desktops and models without a battery degrade automatically: only the AC-power state is shown, with no battery-related readings.

---

## What happens when you quit the app

When you quit, ChargeWatch **immediately disables the charge limit and restores normal charging** (the daemon writes charging back to allowed on its next cycle). In other words, after quitting, your charging behaves exactly as if the app had never been installed.

One thing to be clear about: quitting the app does **not** kill the background daemon. It stays resident in the system at extremely low cost (it reads the config once every 10 seconds and sleeps; it no longer controls charging and does not affect charging behaviour in any way). This is intentional:

- The daemon is a root component whose installation requires administrator authorization. If quitting uninstalled it, you would **have to enter your administrator password again every time you reopened the app and re-enabled the charge limit** — which is very tedious.
- Letting it stay resident and only do real work while you have the limit enabled means "authorize once, then toggle the limit whenever you like without entering a password again".

The simple version: **after you quit, a daemon does remain in the system, but it is idling and has no effect on normal use.** If you do want to remove it from the system entirely, run the single command in the "Complete uninstall" section below.

---

## Transparency and complete uninstall

ChargeWatch leaves three charge-limit-related traces in the system, all of them openly inspectable:

| Type | Path / identifier |
| --- | --- |
| LaunchDaemon | `/Library/LaunchDaemons/com.chenran.chargewatch.helper.plist` |
| Daemon binary | `/Library/PrivilegedHelperTools/com.chenran.chargewatch.helper` |
| Config file | `/Users/Shared/ChargeWatch/smc-limit.json` |
| SMC charge-control keys | `CHTE` (stop/allow charging), and `CHIE` (disconnect/connect adapter) when needed |

### Complete uninstall

Running the uninstall script stops and removes the daemon and **automatically restores normal charging** (writing back `CHTE=0`, `CHIE=0`):

```bash
sudo bash scripts/install-helper.sh uninstall
```

Then just drag `ChargeWatch.app` to the Trash. The local database can be deleted along with it:

```bash
rm -rf ~/Library/Application\ Support/ChargeWatch
```

---

## Privacy

ChargeWatch is a purely local app: it **does not use the network, upload anything, or track any data**. All power sampling history is stored only on your machine:

```
~/Library/Application Support/ChargeWatch/data.sqlite
```

Deleting that file clears the entire history.

---

## Building from source

Environment: an installed Xcode / Swift toolchain (Swift 5.9+).

```bash
git clone https://github.com/TY-teo/ChargeWatching.git
cd ChargeWatching

# Run for development
swift run

# Build and package as an .app
bash scripts/build-app.sh
```

Install/uninstall scripts for the charge limit daemon:

```bash
# Install (requires root; normally invoked automatically the first time the app enables the limit)
sudo bash scripts/install-helper.sh install

# Uninstall (restores charging)
sudo bash scripts/install-helper.sh uninstall
```

---

## Tech stack

- **Language**: Swift 5.9, built with Swift Package Manager.
- **Interface**: SwiftUI + MenuBarExtra, following the system appearance.
- **Power sampling**: IOKit reads of `AppleSmartBattery` and `PowerTelemetryData`, timed sampling at about 1 Hz plus an immediate extra sample on `IOPSNotification` power-state changes.
- **Charge control**: a lightweight daemon running as root reads and writes the Apple Silicon SMC registers directly, supervised by `launchd` (`RunAtLoad` + `KeepAlive`).
- **Data storage**: local SQLite, keeping recent samples in a rolling window and downsampling for long-term archiving.
- **Localization**: `.lproj` string tables in the SPM resource bundle (English, Russian, Chinese), following the system language by default with an override in Settings.

---

## Known limitations

- The charge limit only supports Apple Silicon models; on Intel Macs only power monitoring is available.
- Distributed with an ad-hoc signature, so the first launch has to be allowed manually (right-click to open, or `xattr`).
- Reading and writing the SMC directly is a low-level operation, and key support may differ between models and system versions; models that do not support `CHTE` fall back to the adapter-disconnect approach.
- Power readings are instantaneous snapshots once per second, not a continuous energy integral.
- Tested on macOS 26.4 Tahoe + Apple Silicon; other combinations may behave differently.

---

## ChargeWatch vs AlDente vs batt vs Battery Toolkit vs native macOS

All five can limit charging on Apple Silicon. The honest differences:

| | ChargeWatch | AlDente | batt | Battery Toolkit | Native macOS 26.4 |
| --- | --- | --- | --- | --- | --- |
| Price | Free | Free tier + paid Pro | Free | Free | Built in |
| Open source | Yes (MIT) | No | Yes (GPL-3.0) | Yes (BSD-3) | No |
| Interface | Menu bar app | Menu bar app | CLI | Menu bar app | System Settings |
| Charge limit | Any %, incl. below 80% | Any % | Any % | Any % | 80% only |
| Real-time wattage monitor | Yes (battery / system / wall) | Limited | No | No | No |
| Stop charging without discharging | Yes (CHTE) | Yes | Yes | Yes | Yes |
| Power history + CSV export | Yes | No | No | No | No |

ChargeWatch's niche: it is the free, open-source option that combines a charge limit (including below 80%) with a real-time charging power monitor and history in one menu bar app. If you only need a simple 80% cap, the native macOS setting is enough; if you want detailed wattage plus a sub-80% limit for free, ChargeWatch is built for that. Tool facts (pricing, license, platform) may change over time — verify on each project's page.

---

## FAQ

### Is ChargeWatch free and open source?
Yes. ChargeWatch is free and open-source under the MIT License. There is no paid tier and no in-app purchase.

### Is ChargeWatch a free AlDente alternative?
Yes. ChargeWatch is a free, open-source AlDente alternative for Apple Silicon Macs. It sets a battery charge limit and also shows real-time charging wattage in the menu bar, which AlDente does not focus on.

### How do I set a battery charge limit on macOS?
Open the ChargeWatch menu bar panel, drag the charge-limit slider to your target percentage (60%–80% is a good range), and turn the limit on. You enter your admin password once to install the helper, then it works automatically.

### Can ChargeWatch limit charging below 80%?
Yes. ChargeWatch can hold a charge limit below 80%. The native macOS 26.4 charge limit only goes down to 80%, so ChargeWatch gives finer control.

### Does ChargeWatch discharge the battery to hold the limit?
No. ChargeWatch stops charging while keeping the adapter connected, so the battery is not discharged to hold the limit. Battery current stays near 0 and the Mac runs on adapter power.

### Which Macs and macOS versions are supported?
Power monitoring works on macOS 13 and later. The battery charge limit requires an Apple Silicon (M-series) Mac and is tested on macOS 26.4 Tahoe.

### Does ChargeWatch collect any data?
No. ChargeWatch is fully local with no network access and no tracking. All history stays in a local SQLite database on your Mac.

### How is ChargeWatch different from the native macOS charge limit?
The native macOS 26.4 limit is 80% only and shows no power detail. ChargeWatch lets you pick any limit (including below 80%), adds a real-time wattage monitor, history, and CSV export.

### What language is the interface in?
English, Russian and Chinese. By default ChargeWatch follows your macOS language setting; you can also pick a language explicitly in Settings → Language.

---

## Acknowledgements

For its understanding of SMC charge control, ChargeWatch drew on — and gratefully acknowledges — the following excellent open-source projects and references:

- [charlie0129/batt](https://github.com/charlie0129/batt)
- [mhaeuser/Battery-Toolkit](https://github.com/mhaeuser/Battery-Toolkit)
- [AlDente](https://apphousekitchen.com/)
- Apple official documentation: [HT102338](https://support.apple.com/102338), [HT108055](https://support.apple.com/108055)

---

## Disclaimer

ChargeWatch writes directly to the SMC charge-control registers. Although the project includes read-back verification, 5% hysteresis, periodic calibration and multiple fail-safe designs, **low-level SMC writes still carry inherent risk, and by using this software you acknowledge and accept that risk yourself**. The author is not responsible for any hardware or data problems resulting from use of this software. If you have concerns, please read the source code before deciding whether to use it.

---

## License

This project is open source under the [MIT License](LICENSE).
