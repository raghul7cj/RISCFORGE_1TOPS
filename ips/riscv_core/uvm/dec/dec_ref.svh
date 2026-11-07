typedef struct packed {
  bit        reg_write;
  bit [1:0]  imm_src;
  bit        alu_src;
  bit        mem_write;
  bit [1:0]  result_src;
  bit [3:0]  branch;
  bit [1:0]  jump;
  bit [4:0]  lsunit;
  bit        lui_src;
  bit        is_lui;
  bit        csr_valid;
  bit        csr_imm;
  bit [1:0]  csr_op;
  bit        is_mret;
} dec_ctrl_t;

localparam bit [6:0] OP_LUI = 7'h37, OP_AUIPC = 7'h17, OP_JAL = 7'h6F, OP_JALR = 7'h67,
                     OP_BR = 7'h63, OP_LD = 7'h03, OP_ST = 7'h23, OP_IMM = 7'h13,
                     OP_REG = 7'h33, OP_FENCE = 7'h0F, OP_SYS = 7'h73;

function automatic bit dec_legal(input bit [31:0] i);
  bit [6:0] op = i[6:0];
  bit [2:0] f3 = i[14:12];
  bit [6:0] f7 = i[31:25];
  case (op)
    OP_LUI, OP_AUIPC, OP_JAL: return 1;
    OP_JALR:  return f3 == 3'b000;
    OP_BR:    return f3 != 3'b010 && f3 != 3'b011;
    OP_LD:    return f3 inside {3'b000, 3'b001, 3'b010, 3'b100, 3'b101};
    OP_ST:    return f3 inside {3'b000, 3'b001, 3'b010};
    OP_IMM:   if (f3 == 3'b001) return f7 == 7'h00;
              else if (f3 == 3'b101) return f7 == 7'h00 || f7 == 7'h20;
              else return 1;
    OP_REG:   if (f7 == 7'h01) return 1;
              else if (f7 == 7'h20) return f3 == 3'b000 || f3 == 3'b101;
              else return f7 == 7'h00;
    OP_FENCE: return f3 == 3'b000 || f3 == 3'b001;
    OP_SYS:   if (f3 == 3'b000) return i inside {32'h0000_0073, 32'h0010_0073, 32'h3020_0073, 32'h1050_0073};
              else return f3 != 3'b100;
    default:  return 0;
  endcase
endfunction

function automatic bit [31:0] dec_imm_ref(input bit [31:0] i);
  case (i[6:0])
    OP_ST:            return {{20{i[31]}}, i[31:25], i[11:7]};
    OP_BR:            return {{20{i[31]}}, i[7], i[30:25], i[11:8], 1'b0};
    OP_JAL:           return {{12{i[31]}}, i[19:12], i[20], i[30:21], 1'b0};
    OP_LUI, OP_AUIPC: return {i[31:12], 12'd0};
    OP_IMM:           if (i[14:12] == 3'b001 || i[14:12] == 3'b101) return {27'd0, i[24:20]};
                      else return {{20{i[31]}}, i[31:20]};
    default:          return {{20{i[31]}}, i[31:20]};
  endcase
endfunction

function automatic bit dec_imm_used(input bit [31:0] i);
  return i[6:0] inside {OP_LUI, OP_AUIPC, OP_JAL, OP_JALR, OP_BR, OP_LD, OP_ST, OP_IMM};
endfunction

function automatic bit [3:0] dec_aluctl_ref(input bit [31:0] i);
  bit [2:0] f3 = i[14:12];
  case (i[6:0])
    OP_LD, OP_ST: return 4'b0000;
    OP_JALR:      return 4'b0110;
    OP_BR:        case (f3)
                    3'b000, 3'b001: return 4'b0001;
                    3'b100, 3'b101: return 4'b1111;
                    default:        return 4'b1100;
                  endcase
    OP_IMM, OP_REG:
                  case (f3)
                    3'b000: return (i[5] && i[30]) ? 4'b0001 : 4'b0000;
                    3'b001: return 4'b1000;
                    3'b010: return 4'b1111;
                    3'b011: return 4'b1100;
                    3'b100: return 4'b0111;
                    3'b101: return i[30] ? 4'b1010 : 4'b1001;
                    3'b110: return 4'b0101;
                    default: return 4'b0100;
                  endcase
    default:      return 4'b0000;
  endcase
endfunction

function automatic bit dec_aluctl_used(input bit [31:0] i);
  if (i[6:0] == OP_REG && i[31:25] == 7'h01) return 0;
  return i[6:0] inside {OP_LD, OP_ST, OP_JALR, OP_BR, OP_IMM, OP_REG};
endfunction

function automatic dec_ctrl_t dec_ref(input bit [31:0] i);
  dec_ctrl_t c;
  bit [6:0] op = i[6:0];
  c.reg_write  = op inside {OP_LUI, OP_AUIPC, OP_LD, OP_JAL, OP_JALR, OP_IMM, OP_REG, OP_SYS};
  c.imm_src    = (op == OP_ST) ? 2'b01 : (op == OP_BR) ? 2'b10 : (op == OP_JAL) ? 2'b11 : 2'b00;
  c.alu_src    = op inside {OP_LUI, OP_AUIPC, OP_JAL, OP_JALR, OP_ST, OP_LD, OP_IMM};
  c.mem_write  = (op == OP_ST);
  c.result_src = (op == OP_LD) ? 2'b01 : (op inside {OP_JAL, OP_JALR}) ? 2'b10 : (op == OP_SYS) ? 2'b11 : 2'b00;
  c.branch     = {op == OP_BR, i[14:12]};
  c.jump       = {op inside {OP_JAL, OP_JALR}, op[3]};
  c.lsunit     = {op inside {OP_LD, OP_ST}, op[5], i[14:12]};
  c.lui_src    = op[5];
  c.is_lui     = op inside {OP_LUI, OP_AUIPC};
  c.csr_valid  = (op == OP_SYS);
  c.csr_imm    = (op == OP_SYS) ? i[14] : 1'b0;
  c.csr_op     = (op == OP_SYS) ? i[13:12] : 2'b00;
  c.is_mret    = (i == 32'h3020_0073);
  return c;
endfunction
