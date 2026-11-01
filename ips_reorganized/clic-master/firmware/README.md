# RISC-V CLIC IP - Firmware & Driver Documentation

## 1. Upstream GitHub Provenance
* **Origin**: ETH Zurich & University of Bologna (PULP Platform)
* **Repository**: [pulp-platform/clic](https://github.com/pulp-platform/clic) (branch `master`)

## 2. RTL Match & Verification Status
* `clic_pkg.sv`: **100% Identical** to upstream `pulp-platform/clic/src/clic_pkg.sv`.
* `clic_target.sv`: **100% Identical** to upstream `pulp-platform/clic/src/clic_target.sv`.
* `clic.sv`: Matches upstream CLIC top architecture.

## 3. Driver & Configuration
* `clic.h`: Header providing memory-mapped macros and API functions conforming to the RISC-V CLIC standard and PULP `clicint_reg_pkg` register layout.
* `clic_drv.c`: Implementation for interrupt thresholding, individual interrupt enabling/disabling, priority levels, trigger modes, and software pending triggers.
* `clic_example.c`: Example demonstrating CLIC initialization and IRQ configuration.
