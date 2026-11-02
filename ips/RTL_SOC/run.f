// =============================================================================
// RISCFORGE 1TOPS - shared simulation filelist (not run directly)
// =============================================================================
// Pulled in by every test filelist in ../tests/. Holds the simulator flags and
// the design sources common to all tests. Do not add a testbench, firmware
// include path, core list or -top here - each tests/<test>.f adds its own.
//
// Run a test from ips/RTL_SOC/sim/ (every path below and in filelists/ is
// relative to it; xcelium.d, *.shm and logs then stay inside sim/):
//     cd sim
//     xrun -f ../tests/<test>.f -l logs/<test>.log            # normal run
//     xrun -f ../tests/<test>.f -l logs/<test>.log +VERBOSE   # extra prints
// =============================================================================

-sv
-timescale 1ns/1ps

// Hierarchical read/write access for the testbenches' backdoor probes,
// force/release, and $shm_probe.
-access +rwc

// Selects the $shm_* branch of the testbenches' waveform blocks.
-define XCELIUM

// -----------------------------------------------------------------------------
// Design (shared by every test). The core list (core.f or core_stub.f) is
// chosen in each tests/<test>.f.
// -----------------------------------------------------------------------------
-f ../filelists/inc.f
-f ../filelists/ip.f
-f ../filelists/soc_rtl.f
-f ../filelists/models.f
