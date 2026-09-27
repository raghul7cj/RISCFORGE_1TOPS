// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Modified for the RISCFORGE SoC watchdog (source: OpenTitan earlgrey_1.0.0, 7d0af70):
// module renamed prim_subreg_ext -> watchdog_prim_subreg_ext to avoid a name clash with
// the PULP register_interface prim_subreg_ext used by the GPIO. Logic unchanged.
//
// Register slice conforming to Comportibility guide.

module watchdog_prim_subreg_ext #(
  parameter int unsigned DW = 32
) (
  input          re,
  input          we,
  input [DW-1:0] wd,

  input [DW-1:0] d,

  // output to HW and Reg Read
  output logic          qe,
  output logic          qre,
  output logic [DW-1:0] q,
  output logic [DW-1:0] ds,
  output logic [DW-1:0] qs
);

  // for external registers, there is no difference
  // between qs and ds
  assign ds = d;
  assign qs = d;
  assign q = wd;
  assign qe = we;
  assign qre = re;

endmodule
