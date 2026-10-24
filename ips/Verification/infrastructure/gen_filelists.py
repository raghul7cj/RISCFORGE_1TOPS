#!/usr/bin/env python3
# =============================================================================
# RISCFORGE 1TOPS -- filelist generator / preflight gate
# =============================================================================
# Reads the canonical manifest rf_filelist.txt and emits the tool-specific
# compile lists used by both simulator flows:
#
#   local  : AMD Vivado XSim 2022.2 on Windows
#             xvlog --sv -d FSDB -f soc_verification.xsim.f
#             xelab soc_tb_top -s soc_sim_snap --timescale 1ns/1ps
#             xsim  soc_sim_snap -runall
#   remote : Synopsys VCS U-2023.03 / Cadence Xcelium on Linux
#             vcs  -sverilog -full64 -timescale=1ns/1ps +define+FSDB \
#                  -f soc_verification.esi.f -top soc_tb_top -o simv
#             xrun -sv -timescale 1ns/1ps +define+FSDB \
#                  -f soc_verification.esi.f -top soc_tb_top
#
# Two list dialects are emitted rather than one, because the include-path and
# define syntax is NOT interchangeable between the tool families:
#
#   Vivado XSim   includes: -i <dir>          defines: -d NAME
#   VCS / Xcelium includes: +incdir+<dir>     defines: +define+NAME
#
# xvlog rejects a bare '+incdir+' line inside a -f list (it tries to open it as
# a source file) and has no -timescale option at all; VCS and Xcelium reject
# '-i'. Driving both families from one hand-written list is what produced the
# original failures, so each family gets a generated list from one manifest.
#
# Every emitted path is ABSOLUTE. That is the other half of the point: a `-f`
# list resolves its entries against the tool's working directory, not against
# the list's own location, which is what made the previous hand-written lists
# break as soon as the runner cd'd anywhere other than one hard-coded directory.
#
# USAGE
#   gen_filelists.py --check              preflight only, non-zero on missing
#   gen_filelists.py --emit               preflight, then write the tool lists
#   gen_filelists.py --emit --allow-missing   write lists despite OPT gaps
#   gen_filelists.py --emit --print-cmd        also print the tool invocations
#
# EXIT CODES
#   0  ok
#   2  a required (SRC/VSRC/INCDIR) entry does not exist on disk
#   3  an optional (OPT) entry is missing  -> blocked unless --allow-missing
#   4  bad usage / unreadable manifest
# =============================================================================

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# Verification/infrastructure -> Verification -> <repo root>
REPO_ROOT = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir))
MANIFEST = os.path.join(HERE, "rf_filelist.txt")
# Generated lists live beside the manifest so that every historical reference to
# Verification/infrastructure/soc_verification.* keeps resolving.
OUT_DIR = HERE


class Entry(object):
    __slots__ = ("kind", "rel", "abspath", "exists")

    def __init__(self, kind, rel, abspath, exists):
        self.kind = kind
        self.rel = rel
        self.abspath = abspath
        self.exists = exists


def parse_manifest(path):
    """Return (entries, top, defines). Raises SystemExit on malformed input."""
    entries = []
    top = None
    defines = []
    try:
        handle = open(path, "r")
    except IOError as exc:
        sys.stderr.write("ERROR: cannot read manifest %s: %s\n" % (path, exc))
        sys.exit(4)

    with handle:
        for lineno, raw in enumerate(handle, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) != 2:
                sys.stderr.write(
                    "ERROR: %s:%d: expected '<DIRECTIVE> <value>', got %r\n"
                    % (path, lineno, line))
                sys.exit(4)
            directive, value = parts[0].upper(), parts[1].strip()

            if directive == "TOP":
                top = value
            elif directive == "DEFINE":
                defines.append(value)
            elif directive in ("INCDIR", "SRC", "VSRC", "OPT"):
                rel = value.replace("\\", "/")
                abspath = os.path.normpath(os.path.join(REPO_ROOT, rel))
                exists = os.path.isdir(abspath) if directive == "INCDIR" \
                    else os.path.isfile(abspath)
                entries.append(Entry(directive, rel, abspath, exists))
            else:
                sys.stderr.write(
                    "ERROR: %s:%d: unknown directive %r\n"
                    % (path, lineno, directive))
                sys.exit(4)

    if top is None:
        sys.stderr.write("ERROR: manifest declares no TOP\n")
        sys.exit(4)
    return entries, top, defines


def report(entries):
    """Split entries into present-required, missing-required, missing-optional."""
    missing_required = [e for e in entries if not e.exists and e.kind != "OPT"]
    missing_optional = [e for e in entries if not e.exists and e.kind == "OPT"]
    return missing_required, missing_optional


def emit_printerr(text):
    sys.stderr.write(text)
    sys.stderr.flush()


def preflight(entries):
    """Print the preflight report. Return True when elaboration may proceed."""
    missing_required, missing_optional = report(entries)

    if missing_required:
        emit_printerr("\nPREFLIGHT FAILED -- %d required source(s) missing.\n"
                      % len(missing_required))
        emit_printerr("These are path bugs: the manifest names a file that does\n"
                      "not exist in this tree. Fix the manifest.\n\n")
        for e in missing_required:
            emit_printerr("  [MISSING %s] %s\n" % (e.kind, e.rel))
        emit_printerr("")
        return False

    if missing_optional:
        emit_printerr("\nPREFLIGHT BLOCKED -- %d optional source(s) missing.\n"
                      % len(missing_optional))
        emit_printerr("The manifest is internally consistent, but the design\n"
                      "cannot be elaborated without these. They exist on the\n"
                      "remote VLSI tree and were never mirrored here.\n\n")
        for e in missing_optional:
            emit_printerr("  [MISSING %s] %s\n" % (e.kind, e.rel))
        emit_printerr("\n  Remote origin: /home/iiita/MALAY_SOC/rtl/"
                      "SOC_FILES/include/register_interface/\n")
        emit_printerr("  Restore to:    %s\n"
                      % os.path.join(REPO_ROOT, "apb_uart-main",
                                     "include", "register_interface"))
        emit_printerr("  Re-run with --allow-missing to emit the lists anyway\n"
                      "  (the compile will then fail inside the GPIO block).\n\n")
        return False

    counts = {}
    for e in entries:
        counts[e.kind] = counts.get(e.kind, 0) + 1
    emit_printerr("[preflight] ok -- %s\n"
                  % ", ".join("%d %s" % (v, k) for k, v in sorted(counts.items())))
    return True


def q(path):
    """Render an absolute path for a tool command line / filelist.

    Always emitted with FORWARD slashes and quoted when it contains a space.
    Vivado XSim accepts forward slashes on Windows, and forward slashes are what
    VCS/Xcelium require on Linux -- so one rendering is valid for both, and a
    list generated on Windows is still usable if it is copied to the server.
    """
    posix = path.replace("\\", "/")
    if " " in posix:
        return '"%s"' % posix
    return posix


def write_sim_f(entries, top, defines, outdir):
    """Emit the Vivado XSim `-f` list: xvlog spells includes `-i <dir>`.

    XSim rejects a bare `+incdir+` line inside a `-f` list (it tries to open it
    as a source file), and it has no `-timescale` option at all -- the default
    timescale is set at xelab time. Defines are rendered as `-d NAME`.
    """
    path = os.path.join(outdir, "soc_verification.xsim.f")
    lines = [
        "// =============================================================================",
        "// RISCFORGE 1TOPS -- SoC-level verification filelist, Vivado XSim dialect",
        "//                    (GENERATED, do not edit)",
        "// =============================================================================",
        "// Generated by Verification/infrastructure/gen_filelists.py from",
        "// Verification/infrastructure/rf_filelist.txt. Edit the manifest, not this file.",
        "//",
        "// All paths are absolute so the list is independent of the caller's working",
        "// directory -- identical behaviour for local XSim and remote VCS/Xcelium.",
        "//",
        "//   xvlog --sv -f soc_verification.xsim.f",
        "//   xelab soc_tb_top -s soc_sim_snap --timescale 1ns/1ps",
        "//   xsim  soc_sim_snap -runall",
        "// =============================================================================",
        "",
    ]
    for d in defines:
        lines.append("-d %s" % d)
    # XSIM is injected here (and only in this emitter) rather than in the
    # tool-agnostic manifest, because it must not leak into the VCS/Xcelium list.
    # axi_lite_xbar.sv:116-118 guards a block of vendor AXI assertions with
    # `ifndef VERILATOR / `ifndef XSIM, but nothing ever defined XSIM, so the
    # guard never fired and xelab died on
    #   ERROR: [XSIM 43-3980] File ".../axi_lite_xbar.sv" Line 118 :
    #   The SystemVerilog feature "Default Disable iff declaration" is not
    #   supported yet for simulation.
    # Defining XSIM selects the vendor's own intended XSim behaviour. The block
    # contains assertions only, so suppressing it changes no RTL function.
    lines.append("-d XSIM")
    if defines:
        lines.append("")
    lines.append("// ---- include paths (xvlog -i) ----")
    for e in entries:
        if e.kind == "INCDIR":
            lines.append("-i %s" % q(e.abspath))
    lines.append("")
    lines.append("// ---- sources, in compile order ----")
    for e in entries:
        if e.kind in ("SRC", "VSRC"):
            lines.append(q(e.abspath))
    lines.append("")
    write(path, lines)
    return path


def write_esi_f(entries, top, defines, outdir):
    """Emit the EDA-SystemVerilog `-f` list shared by Synopsys VCS and Cadence
    Xcelium: both spell includes `+incdir+<dir>` and defines `+define+<name>`.
    """
    path = os.path.join(outdir, "soc_verification.esi.f")
    lines = [
        "// =============================================================================",
        "// RISCFORGE 1TOPS -- SoC-level verification filelist, VCS/Xcelium dialect",
        "//                    (GENERATED, do not edit)",
        "// =============================================================================",
        "// Generated by Verification/infrastructure/gen_filelists.py from",
        "// Verification/infrastructure/rf_filelist.txt. Edit the manifest, not this file.",
        "//",
        "// All paths are absolute so the list is independent of the caller's working",
        "// directory. Run it from the Linux mirror of this tree.",
        "//",
        "//   vcs  -sverilog -full64 -timescale=1ns/1ps -debug_access+all -kdb",
        "//        +define+FSDB -f soc_verification.esi.f -top %s -o simv" % top,
        "//   xrun -sv -timescale 1ns/1ps +define+FSDB",
        "//        -f soc_verification.esi.f -top %s" % top,
        "// =============================================================================",
        "",
        "$$define RISCFORGE_SOC_TB_TOP %s" % top,
        "",
    ]
    for d in defines:
        lines.append("+define+%s" % d)
    lines.append("")
    lines.append("// ---- include paths ----")
    for e in entries:
        if e.kind == "INCDIR":
            lines.append("+incdir+%s" % q(e.abspath))
    lines.append("")
    lines.append("// ---- sources, in compile order ----")
    for e in entries:
        if e.kind in ("SRC", "VSRC"):
            lines.append(q(e.abspath))
    lines.append("")
    write(path, lines)
    return path


def write_prj(entries, outdir, top):
    """Vivado XSim project file for `xelab -prj` / the Vivado IDE."""
    path = os.path.join(outdir, "soc_verification.prj")
    incdirs = [e.abspath for e in entries if e.kind == "INCDIR"]
    lines = [
        "# =============================================================================",
        "# RISCFORGE 1TOPS -- Vivado XSim project file (GENERATED, do not edit)",
        "# =============================================================================",
        "# Generated by Verification/infrastructure/gen_filelists.py from",
        "# Verification/infrastructure/rf_filelist.txt. Edit the manifest, not this file.",
        "#",
        "# Preferred headless flow (matches run_rf_mon_smoke.ps1):",
        "#   xvlog --sv -f soc_verification.f",
        "#   xelab %s -s soc_sim_snap" % top,
        "#   xsim  soc_sim_snap -runall",
        "# =============================================================================",
        "",
    ]
    for e in entries:
        if e.kind in ("SRC", "VSRC"):
            verb = "sv work" if e.kind == "SRC" else "verilog work"
            inc = " ".join('-i %s' % q(d) for d in incdirs)
            lines.append("%s %s %s" % (verb, q(e.abspath), inc))
    lines.append("")
    write(path, lines)
    return path


def write(path, lines):
    try:
        handle = open(path, "w")
    except IOError as exc:
        sys.stderr.write("ERROR: cannot write %s: %s\n" % (path, exc))
        sys.exit(4)
    with handle:
        for line in lines:
            handle.write(line + "\n")


def main():
    ap = argparse.ArgumentParser(
        description="Generate RISCFORGE SoC verification filelists and "
                    "preflight the compile list.")
    ap.add_argument("--manifest", default=MANIFEST,
                    help="path to rf_filelist.txt (default: alongside this script)")
    ap.add_argument("--emit", action="store_true",
                    help="write the tool filelists (implies --check)")
    ap.add_argument("--check", action="store_true",
                    help="preflight only; do not write anything")
    ap.add_argument("--allow-missing", action="store_true",
                    help="emit the lists even when OPT entries are missing")
    ap.add_argument("--outdir", default=OUT_DIR,
                    help="output directory (default: Verification/build/sim)")
    ap.add_argument("--print-cmd", action="store_true",
                    help="print the xvlog / vcs / xrun invocations")
    args = ap.parse_args()

    if not args.emit and not args.check:
        args.check = True

    manifest = args.manifest
    if not os.path.isabs(manifest):
        manifest = os.path.join(HERE, manifest)

    entries, top, defines = parse_manifest(manifest)
    ok = preflight(entries)

    if not ok and not args.allow_missing:
        return 3 if not any(e.kind != "OPT" and not e.exists for e in entries) else 2
    if not ok and args.allow_missing and args.emit:
        emit_printerr("[gen_filelists] --allow-missing: emitting a list that "
                      "is known not to elaborate.\n")

    if not args.emit:
        return 0 if ok else 3

    if not os.path.isdir(args.outdir):
        try:
            os.makedirs(args.outdir)
        except OSError as exc:
            sys.stderr.write("ERROR: cannot create %s: %s\n" % (args.outdir, exc))
            sys.exit(4)

    xsim_f = write_sim_f(entries, top, defines, args.outdir)
    esi_f = write_esi_f(entries, top, defines, args.outdir)
    prj = write_prj(entries, args.outdir, top)

    emit_printerr("[gen_filelists] wrote %s\n" % xsim_f)
    emit_printerr("[gen_filelists] wrote %s\n" % esi_f)
    emit_printerr("[gen_filelists] wrote %s\n" % prj)

    if args.print_cmd:
        n_src = len([e for e in entries if e.kind in ("SRC", "VSRC") and e.exists])
        # XSim spells a macro definition `-d NAME`; VCS and Xcelium use
        # `+define+NAME`. They are not interchangeable, so render per tool.
        xsim_d = " ".join("-d %s" % d for d in defines)
        vcs_d = " ".join("+define+%s" % d for d in defines)
        emit_printerr("\n--- tool invocations (top=%s, %d sources) ---\n"
                      % (top, n_src))
        emit_printerr("  local  : xvlog --sv %s -f %s\n"
                      % (xsim_d, q(xsim_f)))
        emit_printerr("           xelab %s -s soc_sim_snap --timescale 1ns/1ps\n" % top)
        emit_printerr("           xsim  soc_sim_snap -runall \\\n"
                      "                +BOOT_MODE=WARM +IMEM_HEX=imem.hex +DMEM_HEX=dmem.hex\n")
        emit_printerr("  remote : vcs -sverilog -full64 -timescale=1ns/1ps \\\n"
                      "             -debug_access+all -kdb %s \\\n"
                      "             -f %s -top %s -o simv\n"
                      % (vcs_d, q(esi_f), top))
        emit_printerr("           ./simv +BOOT_MODE=WARM "
                      "+IMEM_HEX=imem.hex +DMEM_HEX=dmem.hex\n")
        emit_printerr("  xcelium: xrun -sv -timescale 1ns/1ps %s \\\n"
                      "             -f %s -top %s\n" % (vcs_d, q(esi_f), top))
        emit_printerr("")

    return 0


if __name__ == "__main__":
    sys.exit(main())
