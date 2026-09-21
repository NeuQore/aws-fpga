#!/usr/bin/env python3
"""Generate Vivado read_verilog TCL for CVA6 + F2 wrapper sources."""

import os
import subprocess
import sys
from pathlib import Path

CL_DIR = Path(os.environ["CL_DIR"]).resolve()
CVA6 = Path(os.environ.get("CVA6_REPO_DIR", "/projects/prj1/sle-wajahat/cva6")).resolve()
TARGET = os.environ.get("TARGET_CFG", "cv64a6_imafdc_sv39")
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else CL_DIR / "build/scripts/cva6_sources.tcl"
LIST = CL_DIR / "build/scripts/cva6_files.f"

os.environ["CVA6_REPO_DIR"] = str(CVA6)
os.environ["TARGET_CFG"] = TARGET
os.environ["HPDCACHE_DIR"] = str(CVA6 / "core/cache_subsystem/hpdcache")

# Vivado's Tcl `exec` fails when a child writes to stderr, even on a zero exit
# code. The CVA6 Makefile emits $(warning ...) lines there, so capture make's
# output and only surface it (on stdout) if make actually fails.
proc = subprocess.run(
    [
        "make",
        "-C",
        str(CVA6),
        "-f",
        "Makefile",
        "-f",
        str(CL_DIR / "build/scripts/print_cva6_src.mk"),
        "print-cva6-src",
        f"target={TARGET}",
        "RISCV=/usr",
        f"OUT={LIST}",
        f"CVA6_REPO_DIR={CVA6}",
    ],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)
if proc.returncode != 0:
    print(proc.stdout)
    print(f"ERROR: CVA6 filelist generation failed (make exit {proc.returncode})")
    sys.exit(proc.returncode)

skip_substrings = (
    "ariane_xilinx.sv",
    "ariane_peripherals_xilinx.sv",
    "ariane_peripherals.sv",
    "ariane_testharness.sv",
    "ariane-ethernet",
    "bootrom_",
    "fan_ctrl.sv",
    "SimDTM.sv",
    "SimJTAG.sv",
    "/tb/common/uart.sv",
    "rvfi_tracer.sv",
    "instr_tracer",
    "/DPTI/",
    "encapsulator",
    "cva6_iti",
    "rv_tracer",
    "slicer_DPTI",
    "axi_test.sv",
    "apb_test.sv",
    "riscv-dbg",
    "cva6_rvfi.sv",
    # pulp's `sync` collides with the AWS shell's own encrypted `sync` module
    # used by sh_ddr/flop_ccf. Nothing in this SoC reaches the dead
    # edge_detect -> sync_wedge -> sync chain, so drop it to keep AWS's version.
    "common_cells/src/sync.sv",
    "common_cells/src/sync_wedge.sv",
    "common_cells/src/edge_detect.sv",
)

incdirs = [
    f"{CVA6}/core/include",
    f"{CVA6}/vendor/pulp-platform/common_cells/include",
    f"{CVA6}/vendor/pulp-platform/axi/include",
    f"{CVA6}/corev_apu/register_interface/include",
    f"{CVA6}/corev_apu/tb/common",
    f"{CVA6}/common/local/util",
    f"{CVA6}/corev_apu/instr_tracing/ITI/include",
    f"{CVA6}/core/cache_subsystem/hpdcache/rtl/include",
    f"{CVA6}/core/cache_subsystem/hpdcache/rtl/src/utils/ecc",
    f"{CVA6}/core/cvfpu/src",
    f"{CVA6}/core/cvfpu/src/common_cells/include",
    f"{CVA6}/core/cvfpu/src/fpu_div_sqrt_mvp/hdl",
    f"{CL_DIR}/design",
]
hdk = os.environ.get("HDK_COMMON_DIR")
if hdk:
    incdirs.append(f"{hdk}/shell_stable/design/interfaces")

files = []
seen = set()
for line in LIST.read_text().splitlines():
    p = line.strip()
    if not p or p.startswith("#"):
        continue
    if any(s in p for s in skip_substrings):
        continue
    if p.startswith("+incdir+"):
        incdirs.append(p[len("+incdir+") :])
        continue
    if p not in seen:
        seen.add(p)
        files.append(p)

# Extra SoC pieces not always in the FPGA list
extras = [
    CVA6 / "corev_apu/src/ariane.sv",
    CVA6 / "corev_apu/clint/axi_lite_interface.sv",
    CVA6 / "corev_apu/clint/clint.sv",
    CVA6 / "common/local/util/sram.sv",
    CVA6 / "common/local/util/tc_sram_fpga_wrapper.sv",
    CVA6 / "vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx64.sv",
    CVA6 / "vendor/pulp-platform/fpga-support/rtl/SyncSpRamBeNx32.sv",
    CVA6 / "vendor/pulp-platform/fpga-support/rtl/SyncSpRam.sv",
    CVA6 / "vendor/pulp-platform/axi/src/axi_pkg.sv",
    # CPU DRAM path: PULP 64b -> 512b conversion. Clock crossing uses the
    # AWS/Xilinx cl_axi_clock_converter to avoid the shell's incompatible
    # module named `sync`.
    # Keep the complete transitive set explicit because these blocks are not
    # part of every CVA6 FPGA target file list.
    CVA6 / "vendor/pulp-platform/common_cells/src/onehot_to_bin.sv",
    CVA6 / "vendor/pulp-platform/axi/src/axi_dw_upsizer.sv",
    CVA6 / "vendor/pulp-platform/axi/src/axi_dw_downsizer.sv",
    CVA6 / "vendor/pulp-platform/axi/src/axi_dw_converter.sv",
]
for e in extras:
    s = str(e)
    if e.exists() and s not in seen:
        files.append(s)
        seen.add(s)

missing = [f for f in files if not Path(f).exists()]
if missing:
    print("WARNING: missing source files:")
    for m in missing[:30]:
        print("  ", m)

lines = [
    f"set_property include_dirs [list {' '.join(incdirs)}] [current_fileset]",
    "read_verilog -sv [list \\",
]
for f in files:
    lines.append(f"  {f} \\")
lines.append("]")
OUT.write_text("\n".join(lines) + "\n")
print(f"Wrote {OUT} ({len(files)} files)")
