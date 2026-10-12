# FanControl — Porting Guide (moving to another machine)

Applies to: FanControl 1.5.0

> 中文版见 [`移植说明.md`](移植说明.md).

---

## 1. The short version: three conditions

| Condition | Requirement | If not met |
|---|---|---|
| **1. It must be a hackintosh** | You can edit OpenCore's `config.plist` | A real Mac won't load a third-party kext — the whole approach is impossible |
| **2. The Super I/O chip must be Nuvoton NCT679x** | `NCT6790D`…`NCT6798D`, `NCT679BD`, or `NCT6779D` | Other chips (ITE, Winbond, NCT6776D, …) are unsupported |
| **3. It must be an Intel machine** | The kext is built for x86_64 | It cannot load on Apple Silicon |

**All three met → it works.** Run the self-check once after installing to confirm:

```sh
zsh /usr/local/sbin/fancontrol-check
```

It checks each item and prints a verdict at the end.

> By the way: if that machine is a **real Mac** (not a hackintosh), don't use this —
> real Macs can control their fans with off-the-shelf software like Macs Fan Control,
> and injecting a kext there is neither needed nor permitted.

---

## 2. What to watch for on macOS 15

The userspace programs (the GUI, `fanctl`, `gpufand`) are compiled for a **macOS 13.0** target,
so they run as-is on macOS 15, and they are built as **x86_64 + arm64 universal binaries**.

On the kext side:

- This package is based on **VirtualSMC 1.3.8 + Lilu 1.7.2**; both support macOS 15.
- Since macOS 11, third-party kexts **can only be injected through OpenCore** — you can no longer
  drop them into `/Library/Extensions` (they won't load, and you'll get a
  "system extension blocked" prompt).
- The kext's `OSBundleLibraries` requires `VirtualSMC >= 1.0.0` and `Lilu >= 1.2.0`,
  so the VirtualSMC and Lilu in your EFI can't be too old.

**There is no difference between macOS 15 and macOS 26 for this approach** — the same kext and the
same configuration work on both.

---

## 3. Two things you must do after installing

### 1. Put `SMCSuperIO.kext` into your EFI

The installer places the Nuvoton-write-capable kext at:

```
/usr/local/share/fancontrol/SMCSuperIO.kext
```

(This kext has the **same name and the same bundle id `ru.joedm.SMCSuperIO`** as the SMCSuperIO
already in your EFI — it merely adds **write** access for Nuvoton NCT679x.
**Replace the file; don't keep both.**)

Steps:

1. Mount the EFI partition. Find which EFI contains `EFI/OC/OpenCore.efi`:

   ```sh
   diskutil list                       # find the EFI partition (usually 200MB)
   sudo diskutil mount diskXs1
   ```

2. **Back up the original first:**

   ```sh
   cd /Volumes/EFI/EFI/OC/Kexts
   cp -R SMCSuperIO.kext SMCSuperIO.kext.bak-$(date +%Y%m%d)
   ```

3. Replace it:

   ```sh
   rm -rf SMCSuperIO.kext
   cp -R /usr/local/share/fancontrol/SMCSuperIO.kext .
   ```

4. Edit `EFI/OC/config.plist` and, under `Kernel → Add`, **make sure this entry exists and the order is right**:

   - `SMCSuperIO.kext` must come **after** `VirtualSMC.kext` (a dependency must precede its dependant)
   - Also confirm `Lilu.kext` comes before `VirtualSMC.kext`

   > ⚠️ OpenCore injects **in order**. An entry whose dependency isn't in place yet is
   > **silently skipped** — no error, not even a load attempt in the log. This is the easiest trap
   > to fall into.

5. Reboot.

### 2. Confirm the pump channel (**important**)

Every machine numbers its fan channels differently. The built-in default is **ch6** (this author's
ASUS layout). **You must re-check it on a different machine**, or you might put a real water-cooling
pump under ordinary fan control — throttling the pump starves the loop of coolant flow.

How to check (read-only, safe):

1. Open FanControl, let the machine idle for a few minutes, and watch the live RPM of each channel
   in the "Fan channels" table.
2. **The channel whose speed is clearly high, nearly constant, and doesn't track CPU temperature
   is the pump.** (On this machine that's ch6 / AUXFAN4 at ≈2800 RPM; every other fan sits at 400–900.)
3. Cross-check: run a stress load. Channels that rise with it are fans; the one that doesn't move is
   the pump.

> ⚠️ **Do not** use `gpufan scan` to test this — it drives **every** channel to 100% and back down
> to 0%, including the pump.

Once confirmed, write it into the config:

```sh
sudo sh -c 'echo pump_channel = <channel> >> /usr/local/etc/fancontrol.conf'
sudo launchctl kickstart -k system/com.shohart.gpufand
```

Until that config exists, the GUI shows an orange warning above "Fan channels".

---

## 4. Install

### Option A: the installer package

```sh
sudo installer -pkg FanControl-1.5.0.pkg -target /
```

Or double-click the `.pkg`. **Note: this package has no Apple Developer signature** — if double-clicking
says "cannot be opened because it is from an unidentified developer":

- Right-click → Open → Open again, or
- System Settings → Privacy & Security → click "Open Anyway" at the bottom, or
- Just use the `installer` command above.

### Option B: build from source (equivalent, and you can see every step)

```sh
cd FanControl
zsh build.sh                                              # build
sudo zsh install.sh                                       # install
```

---

## 5. What gets installed

| Path | Description |
|---|---|
| `/Applications/FanControl.app` | The GUI (x86_64 + arm64 universal), with a custom icon; stays in the menu bar while running |
| `/usr/local/sbin/fanctl` | The privileged helper — the **only** thing that writes to SMC |
| `/usr/local/sbin/gpufand` | The temperature → duty-cycle daemon |
| `/usr/local/sbin/fancontrol-check` | Compatibility self-check script |
| `/Library/LaunchDaemons/com.shohart.gpufand.plist` | The launch daemon (starts at boot) |
| `/usr/local/etc/gpufand.conf` | Temperature-curve configuration |
| `/usr/local/etc/fancontrol.conf` | Per-machine settings (the pump channel) |
| `/etc/sudoers.d/fancontrol` | Passwordless rule — authorizes **only** the five `fanctl` subcommands |
| `/usr/local/share/fancontrol/` | The kext, default config, this guide, and the uninstall script |

### About starting at login

- **The `gpufand` daemon: yes, it starts at boot.** `RunAtLoad = true`, so the mode you picked
  (Silent / Standard / Performance / …) is restored automatically after a reboot.
- **The `FanControl.app` GUI: since 1.4.1 you can enable "Start at login" from the menu-bar panel.**

  It uses the system's login-item mechanism (`SMAppService`), so you can see it — and turn it off —
  under System Settings → General → Login Items.

  After boot it opens the main window automatically; **just close it** — the menu-bar icon stays.

  > If you don't want a window popping up at boot, leave this switch off. Speed control itself is
  > done by `gpufand`; the GUI is only needed when you want to change settings.

### About the Monitor page (new in 1.3)

The top of the left column has two tabs: **Control / Monitor**. The Monitor page has 8 panels you can
toggle independently:

| Panel | Contents | Data source |
|---|---|---|
| CPU | Total usage, user/system split, load, history graph, **per-core** usage | `host_processor_info` |
| GPU | Fan RPM / temperature / power / clocks / utilization | `IOAccelerator` in `IORegistry` |
| Memory | Used/total, wired, compressed, swap | `host_statistics64` + `sysctl` |
| Storage | Used space per volume | `getmntinfo` |
| Network | Up/down throughput (measured on a 2-second poll) | `sysctl NET_RT_IFLIST2` |
| Processes | Top 10 processes by CPU | Two `libproc` samples, differenced |
| Sensors | CPU 8 cores + GPU temperature | SMC |
| System | CPU model, logical cores, uptime, load | `sysctl` |

Toggles are remembered in preferences and restored next launch; there's also a
"Show all / Hide all" switch. **Everything is read-only, needs no root, and writes nothing.**
It's implemented in the `fanctl sys` subcommand, so you can also run it in a terminal:

```sh
/usr/local/sbin/fanctl sys
```

> On CPU power: this machine is Intel, and the `IOReport` "Energy Model" group doesn't exist on
> Intel (it's Apple Silicon only), so **there is no CPU power panel**.
> GPU power is visible in the "GPU" panel.

### About the menu bar (new in 1.4)

While running, the app **lives in the right side of the menu bar**, showing
"fan icon + CPU temperature + GPU temperature" by default. Click it for a panel; the lower half has
**8 switches** — turn on whichever you want to see:

| Item | Shows |
|---|---|
| Fan icon | Just an icon, no number |
| CPU temperature | Hottest CPU core |
| GPU temperature | GPU temperature (from SMC's RadeonSensor) |
| CPU usage | Total utilization |
| Memory | Used percentage |
| Fan RPM | Fastest of the controlled fans (**excluding the pump**) |
| GPU fan | The GPU's own fan RPM |
| Network | Downlink rate (compact, e.g. `1.2M`) |

Toggles are remembered in preferences (`fancontrol.menuBarItems`) and restored next launch.
Each menu-bar item carries its own icon, so they're easy to tell apart.

At the bottom of the panel are three buttons: **Open main window / Refresh now / Quit**.

A few things to note:

- **Closing the main window ≠ quitting.** The menu-bar icon stays; click "Open main window" or the
  Dock icon to bring it back. To really quit, use the power button in the panel or ⌘Q.
- **If all 8 items are off, a single fan icon remains** — otherwise the menu bar would become
  unclickable and the settings unreachable forever.
- All of this is read-only sampling: it writes nothing and needs no extra privileges.

> **Implementation note (for anyone modifying the code):** the menu-bar items do *not* use SwiftUI's
> `MenuBarExtra`. In practice its label **only takes the first `Image` as the button icon and the
> first `Text` as the title**, silently discarding the rest (HStack+ForEach, concatenated Text,
> `.fixedSize()`, and `Label` were all tried). Since "multiple items each with an icon and a value"
> isn't expressible that way, the app uses AppKit's `NSStatusItem` instead, drawing the SF Symbol and
> the text together via `attributedTitle` + `NSTextAttachment`. The code is in `app/StatusItem.swift`.

### About GPU fans (new in 1.2 — **read-only, cannot be controlled**)

The "GPU" panel shows the graphics card's **fan RPM / duty / temperature / power / core clock /
utilization**. The data comes from the `IOAccelerator` node in `IORegistry`; read-only, no root.

**Why it can't be controlled:**

GPU fans are managed jointly by the card's firmware PowerPlay table and the GPU driver. macOS exposes
**no public write interface**, and there's no ADL / Afterburner-style tool. Writing the card's I2C
directly, bypassing the driver, just gets overwritten by the driver and risks damaging the card.

**If you really want to change it, there's exactly one route — edit the curve statically:**

Injecting `PP_PhmSoftPowerPlayTable` (a soft PowerPlay table) into the card via OpenCore's
`DeviceProperties` lets you change the fan curve / disable Zero RPM / change the start temperature.
**It takes effect on reboot and affects macOS only** (Windows uses its own driver).
Reference implementation: `perez987/RX6600XT-on-macOS-with-softPowerPlayTable`;
tool: olarila's `ZeroRPMBuilder for macOS`. If you break something, delete that `DeviceProperties`
entry to roll back.

**Notes:**

- A GPU with no driver (e.g. NVIDIA 20/30-series under macOS) **doesn't show this panel** —
  there's no node in IORegistry at all, so nothing can be read.
- The panel's "temperature" comes from IORegistry; the GPU temperature in "Temperature source" on the
  left comes from SMC (`TG0D`/`TG0P`, provided by the RadeonSensor kext). They usually agree but serve
  different purposes: the former is display only, the latter is the one that **actually feeds the fan
  curve**.
- Case fans are in fact **already tracking GPU temperature** — `source = TG0D,TG0P` in `gpufand.conf`
  is the GPU temperature, and with multiple sources the one demanding the highest duty wins.
  So when the GPU heats up, case fans speed up on their own.

---

## 6. Uninstall

```sh
sudo zsh /usr/local/share/fancontrol/uninstall.sh
```

This hands all fans back to the BIOS, then removes the daemon, helper, sudoers rule, and GUI.
(The kext and this guide under `/usr/local/share/fancontrol/` are kept — delete them by hand if you want.)

To revoke only the privilege escalation, without uninstalling:

```sh
sudo rm -f /etc/sudoers.d/fancontrol
```

---

## 7. FAQ

**Q: `fancontrol-check` says SMC has no `F<n>Md` keys, so fans can't be controlled.**

That means the write-capable SMCSuperIO isn't loaded. Check, in order:

1. Is the `SMCSuperIO.kext` in your EFI **the one this package provides** (you can `strings` it and
   look for `Nuvoton NCT679`)?
2. Is it registered under `config.plist → Kernel → Add`, with `Enabled` set to `true`?
3. Does it come **after** `VirtualSMC.kext`?
4. Is the chip model on the whitelist (`ioreg -l -w0 | grep ChipName`)?

**Q: The GUI opens, but "Apply" reports a permission error.**

The username in `/etc/sudoers.d/fancontrol` was written at install time from whoever was logged in then.
If you've changed accounts, re-run the installer, or edit the username in that file by hand.

**Q: A fan stops at 0% and won't come back.**

Some fans stall below a certain duty and don't restart on their own. Raise the "Minimum duty" slider to
15–25% and click Apply; or click "Hand back to BIOS" and let the motherboard take over.

**Q: GPU temperature doesn't show.**

That's an ordering issue between the `RadeonSensor` and `SMCRadeonGPU` kexts — `SMCRadeonGPU` depends
on `RadeonSensor` and must come **after** it. Nothing to do with this app.

**Q: The GPU panel is missing entirely, or an item shows "—".**

The 1.2 GPU monitoring only works for **GPUs that have a driver**:

- **Panel missing entirely** → there's no `IOAccelerator` node with fan data in `IORegistry`.
  Typical case: a GPU with no driver (NVIDIA 20/30-series under macOS).
- **One item shows "—"** → this card doesn't expose that field; different cards expose different fields.
- **Everything shows "—"** → this card provides none of these statistics.

To see the raw data (read-only, no root):

```sh
/usr/local/sbin/fanctl gpu
```

A healthy run looks like:

```json
{"ok":true,"gpu":{"fanRPM":521,"fanPercent":14.0,"temp":49,"power":46.0,
                  "coreClock":221,"memClock":2300,"utilization":3}}
```

**Q: I have Macs Fan Control / TG Pro — will they conflict?**

No. They and `gpufand` all operate through the same SMC keys, and whoever writes last wins.
(In fact, now that writable `F<n>Tg`/`F<n>Md` keys exist in SMC, Macs Fan Control might be able to
control the fans too — worth a try.)

**Q: I can't find the FanControl icon in the menu bar.**

First confirm the app is running (is its icon in the Dock?). The menu-bar item only exists while the
app runs. Since 1.4.1 you can turn on "Start at login" from the menu-bar panel (via system login items),
but it's **off by default** — if you never enabled it, you'll need to open the app yourself after a reboot.

If the app is running but there's no menu-bar item: the menu bar is too crowded and the system hid it.
Since macOS 13, items that don't fit are hidden automatically. Close a few other menu-bar utilities,
or reduce the displayed items to 2–3.

**Q: The numbers in the menu bar don't match the main window.**

The menu bar refreshes **every 2 seconds**, and the main window refreshes in sync, but a screenshot or
a glance always lands slightly before or after. Also, "Fan RPM" in the menu bar is the **fastest of the
controlled fans** (excluding the pump), whereas the fan list in the main window shows each channel's
own value.

**Q: After closing the main window the app is still there — didn't it quit cleanly?**

That's **intentional** — closing the window just hides it; the menu-bar icon stays.
To really quit: click the menu-bar icon → the power button at the bottom-right of the panel, or press ⌘Q.
