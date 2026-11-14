// Independent machine-mode subset for directed synchronous-exception/MRET tests.
// This is an architectural model of the tested subset, not the DUT's CSR datapath.
package rv32_machine_reference_pkg;
  import rv32_reference_pkg::*;

  localparam logic [31:0] INSN_ECALL = 32'h0000_0073;
  localparam logic [31:0] INSN_EBREAK = 32'h0010_0073;
  localparam logic [31:0] INSN_ILLEGAL = 32'hffff_ffff;
  localparam logic [31:0] INSN_MRET  = 32'h3020_0073;
  localparam logic [11:0] CSR_MSTATUS = 12'h300;
  localparam logic [11:0] CSR_MTVEC   = 12'h305;
  localparam logic [11:0] CSR_MEPC    = 12'h341;
  localparam logic [11:0] CSR_MCAUSE  = 12'h342;
  localparam logic [11:0] CSR_MIE = 12'h304;
  localparam logic [11:0] CSR_MTVAL   = 12'h343;

  typedef struct packed {
    logic [31:0] mstatus;
    logic [31:0] mtvec;
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
    logic [31:0] mie;
  } machine_state_t;

  function automatic logic [31:0] enc_csr(
    input logic [2:0] operation,
    input logic [4:0] rd,
    input logic [11:0] address,
    input logic [4:0] rs1
  );
    return {address, rs1, operation, rd, 7'b1110011};
  endfunction

  // ---- CSR state: only explicitly supported addresses and register forms ----
  function automatic logic [31:0] read_machine_csr(
    input machine_state_t state,
    input logic [11:0] address
  );
    case (address)
      CSR_MSTATUS: return state.mstatus;
      CSR_MTVEC:   return state.mtvec;
      CSR_MEPC:    return state.mepc;
      CSR_MCAUSE:  return state.mcause;
      CSR_MTVAL:   return state.mtval;
      CSR_MIE:     return state.mie;
      default: $fatal(1, "RV32_MACHINE unsupported CSR %03x", address);
    endcase
  endfunction

  // Architectural asynchronous entry. PC is supplied by the independent
  // retirement model, never by the DUT's accepted interrupt or trap packet.
  task automatic enter_interrupt(
    input logic [31:0] next_unretired_pc,
    input logic [30:0] cause,
    inout machine_state_t state
  );
    if (!state.mstatus[3] || !state.mie[cause])
      $fatal(1, "RV32_MACHINE reference IRQ is masked");
    state.mepc = next_unretired_pc;
    state.mcause = {1'b1, cause};
    state.mtval = 0;
    state.mstatus[7] = state.mstatus[3];
    state.mstatus[3] = 0;
    state.mstatus[12:11] = 2'b11;
  endtask

  task automatic step_machine(
    input logic [31:0] pc,
    input logic [31:0] instruction,
    inout logic [31:0] gpr[0:31],
    inout logic gpr_known[0:31],
    inout machine_state_t state,
    output logic [31:0] next_pc,
    output logic writes_gpr,
    output logic [4:0] rd,
    output logic [31:0] result,
    output logic writes_mem,
    output logic [31:0] mem_address,
    output logic [31:0] mem_value,
    output logic takes_exception,
    output logic returns_from_trap
  );
    logic [11:0] address;
    logic [4:0] rs1;
    logic [31:0] old_value;
    logic [31:0] write_value;
    bit write_csr;
    bit synchronous_fault;
    logic [31:0] fault_cause;
    logic [31:0] fault_value;
    logic [31:0] effective_address;
    takes_exception = 0;
    returns_from_trap = 0;
    synchronous_fault = 0;
    fault_cause = 0;
    fault_value = 0;
    if ($isunknown({pc, instruction, state}) || pc[1:0] != 0)
      $fatal(1, "RV32_MACHINE invalid predictor input");
    next_pc = pc + 4;
    rd = instruction[11:7];
    writes_gpr = 0;
    writes_mem = 0;
    mem_address = 0;
    mem_value = 0;
    result = 0;

    // ---- Independently classify only supported faulting encodings ----
    // Unsupported valid opcodes are still rejected, never mislabeled illegal.
    if (instruction == INSN_ILLEGAL) begin
      synchronous_fault = 1;
      fault_cause = 2;
      fault_value = instruction;
    end else if (instruction == INSN_EBREAK) begin
      synchronous_fault = 1;
      fault_cause = 3;
      fault_value = pc; // Project breakpoint tval contract.
    end else if (instruction == INSN_ECALL) begin
      synchronous_fault = 1;
      fault_cause = 11;
    end else if ((instruction[6:0] == 7'b0000011 || instruction[6:0] == 7'b0100011) &&
                 instruction[14:12] == 3'b010) begin
      rs1 = instruction[19:15];
      if (!gpr_known[rs1]) $fatal(1, "RV32_MACHINE unknown memory base x%0d", rs1);
      effective_address = gpr[rs1] + (instruction[6:0] == 7'b0000011 ?
                                     imm_i(instruction) : imm_s(instruction));
      if (effective_address[1:0] != 0) begin
        synchronous_fault = 1;
        fault_cause = instruction[6:0] == 7'b0000011 ? 4 : 6;
        fault_value = effective_address;
      end else if (instruction[6:0] == 7'b0000011) begin
        $fatal(1, "RV32_MACHINE aligned load semantics not implemented in this subset");
      end
    end

    // ---- All synchronous entries share one architectural state transition ----
    if (synchronous_fault) begin
      state.mepc = pc;
      state.mcause = fault_cause;
      state.mtval = fault_value;
      state.mstatus[7] = state.mstatus[3];
      state.mstatus[3] = 0;
      state.mstatus[12:11] = 2'b11;
      next_pc = state.mtvec & 32'hffff_fffc;
      takes_exception = 1;
    end else if (instruction[6:0] != 7'b1110011) begin
      execute(pc, instruction, gpr, gpr_known, next_pc, writes_gpr,
              rd, result, writes_mem, mem_address, mem_value);
    end else if (instruction == INSN_MRET) begin
      next_pc = state.mepc;
      state.mstatus[3] = state.mstatus[7];
      state.mstatus[7] = 1;
      state.mstatus[12:11] = 2'b11;
      returns_from_trap = 1;
    end else begin
      // CSRRW and CSRRS, register source only. Other SYSTEM encodings fail.
      if (instruction[14:12] != 3'b001 && instruction[14:12] != 3'b010)
        $fatal(1, "RV32_MACHINE unsupported SYSTEM %08x", instruction);
      address = instruction[31:20];
      rs1 = instruction[19:15];
      if (!gpr_known[rs1]) $fatal(1, "RV32_MACHINE unknown CSR source x%0d", rs1);
      old_value = read_machine_csr(state, address);
      write_csr = instruction[14:12] == 3'b001 || rs1 != 0;
      write_value = instruction[14:12] == 3'b001 ? gpr[rs1] : old_value | gpr[rs1];
      if (write_csr) begin
        case (address)
          CSR_MSTATUS: state.mstatus = (write_value & 32'h0000_188a) |
                                          (state.mstatus & ~32'h0000_188a);
          CSR_MTVEC: begin
            state.mtvec = {write_value[31:2], 1'b0, (write_value[1:0] == 2'b01)};
          end
          CSR_MEPC: state.mepc = write_value & 32'hffff_fffc;
          CSR_MCAUSE: state.mcause = write_value;
          CSR_MTVAL: state.mtval = write_value;
          CSR_MIE: state.mie = write_value & 32'hffff_0880;
        endcase
      end
      result = old_value;
      writes_gpr = rd != 0;
      if (writes_gpr) begin
        gpr[rd] = result;
        gpr_known[rd] = 1;
      end
    end
    gpr[0] = 0;
    gpr_known[0] = 1;
  endtask
endpackage
