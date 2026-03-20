# zynq-qspi-dump

OpenOCD scripts to dump SPI flash from Xilinx Zynq-7000 devices via JTAG,
using the ARM AHB-AP (MEM-AP) for direct bus reads. No custom FPGA bitstream required.

Tested on **XC7Z015** with a **J-Link** probe and OpenOCD 0.12.

---

## How it works

The Zynq-7000 contains an ARM Cortex-A9 PS with a QSPI controller that exposes
the SPI flash as a linear memory window at `0xFC000000`. By accessing this window
through the ARM DAP's AHB-AP (AP 0) instead of through CPU instruction execution,
reads are stable even when the QSPI controller was not in linear mode before halting.

The script:
1. Halts both CPUs via JTAG
2. Configures the QSPI controller for linear mode with a standard `0x03` READ instruction
3. Switches to the AHB-AP target for direct bus reads (avoids CPU data abort / DSCR timeouts)
4. Reads 32 MB in 64 KB chunks with one automatic retry per chunk on error

---

## Requirements

**Hardware**
- Zynq-7000 target board (JTAG header accessible)
- J-Link debug probe (V9 or later recommended)

**Software**
- [OpenOCD](https://openocd.org/) >= 0.12
- J-Link drivers (libjlink / Segger J-Link Software)

---

## Files

| File | Description |
|------|-------------|
| `zynq_jlink.conf` | OpenOCD configuration: J-Link adapter + Zynq-7000 target + AHB-AP mem target |
| `dump_flash.tcl` | TCL script: QSPI init, AHB-AP switch, 32 MB chunked dump with retry |

---

## Usage

```bash
openocd -f zynq_jlink.conf -c "init; source dump_flash.tcl; dump_flash dump.bin; resume; shutdown"
```

Output is written to `dump.bin` (raw binary, 32 MB).

### Adjusting flash size

Edit `dump_flash.tcl` and change the `size` variable:

```tcl
set size   0x2000000    ;# 32 MB - adjust to match your flash
```

### Adjusting JTAG speed

Edit `zynq_jlink.conf`:

```
adapter speed 1000    ;# kHz - lower is more stable over long cables
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| No tap found | JTAG fused/disabled or bad wiring | Check JTAG pins, verify VTarget voltage |
| `zynq.ahb target not found` | Missing `mem_ap` line in conf | See comment at top of `dump_flash.tcl` |
| All chunks padded with `0xFF` | QSPI not clocked / AXI timeout | Board may need to boot first; try increasing `after` delay in `check_qspi` |
| `data abort` errors | CPU-based reads instead of AHB-AP | Ensure `targets zynq.ahb` is selected before reading |

---

## Notes

- The script forces `LQSPI_CFG = 0x80000003` (linear mode + `0x03` standard SPI read).
  If the board originally used Quad Read (`0x6B`), this is intentional - `0x03` avoids
  dummy-cycle and quad-mode initialization requirements and works on all SPI flash chips.
- The dump uses little-endian 32-bit word ordering as returned by the AHB-AP.
  Use [exbootimage](https://github.com/antmicro/zynq-mkbootimage) to verify content after dumping.
- Both CPUs are halted during the dump. `resume` is called automatically at the end.
