typedef struct packed {
  bit        rst;
  bit        reg_write_m;
  bit        reg_write_w;
  bit [4:0]  rd_m;
  bit [4:0]  rd_w;
  bit [4:0]  rs1_e;
  bit [4:0]  rs2_e;
  bit [4:0]  rs1_d;
  bit [4:0]  rs2_d;
  bit [4:0]  rd_e;
  bit [1:0]  result_src_e;
  bit        pcsrc_e;
  bit        csr_valid_d;
  bit [11:0] csr_raddr_d;
  bit [11:0] csr_addr_e;
  bit [11:0] csr_addr_m;
  bit [11:0] csr_addr_w;
  bit        csr_we_e;
  bit        csr_we_m;
  bit        csr_we_w;
  bit [3:0]  flush_onehot;
  bit        valid_e;
  bit        exc_e;
  bit        valid_m;
  bit        exc_m;
  bit        wb_redirect;
  bit        stall_mul;
  bit        mem_stall;
} haz_in_t;

typedef struct packed {
  bit [1:0] fwd_a;
  bit [1:0] fwd_b;
  bit       stall_f;
  bit       stall_d;
  bit       stall_e;
  bit       stall_m;
  bit       flush_d;
  bit       flush_e;
  bit       flush_m;
  bit       flush_w;
} haz_out_t;

function automatic bit [1:0] haz_fwd(input haz_in_t x, input bit [4:0] rs);
  if (!x.rst || rs == 5'd0) return 2'b00;
  if (x.reg_write_m && x.rd_m == rs) return 2'b10;
  if (x.reg_write_w && x.rd_w == rs) return 2'b01;
  return 2'b00;
endfunction

function automatic bit haz_load_use(input haz_in_t x);
  return x.result_src_e == 2'b01 && x.rd_e != 5'd0 && (x.rs1_d == x.rd_e || x.rs2_d == x.rd_e);
endfunction

function automatic bit haz_csr_gpr(input haz_in_t x);
  return x.result_src_e == 2'b11 && x.rd_e != 5'd0 && (x.rs1_d == x.rd_e || x.rs2_d == x.rd_e);
endfunction

function automatic bit haz_csr_raw(input haz_in_t x);
  return x.csr_valid_d && ((x.csr_we_e && x.csr_raddr_d == x.csr_addr_e) ||
                           (x.csr_we_m && x.csr_raddr_d == x.csr_addr_m) ||
                           (x.csr_we_w && x.csr_raddr_d == x.csr_addr_w));
endfunction

function automatic haz_out_t haz_ref(input haz_in_t x);
  haz_out_t o;
  bit hold  = haz_load_use(x) | haz_csr_gpr(x) | haz_csr_raw(x);
  bit exc_e = x.valid_e & x.exc_e;
  bit exc_m = x.valid_m & x.exc_m;
  o.fwd_a   = haz_fwd(x, x.rs1_e);
  o.fwd_b   = haz_fwd(x, x.rs2_e);
  o.stall_f = !x.wb_redirect && (hold | x.stall_mul | x.mem_stall);
  o.stall_d = o.stall_f;
  o.stall_e = !x.wb_redirect && x.mem_stall;
  o.stall_m = o.stall_e;
  o.flush_d = x.pcsrc_e | exc_e | exc_m | x.wb_redirect | x.flush_onehot[0];
  o.flush_e = (hold & ~x.mem_stall) | x.pcsrc_e | exc_m | x.wb_redirect | x.flush_onehot[1] | x.stall_mul;
  o.flush_m = x.wb_redirect | x.flush_onehot[2] | (x.stall_mul & ~x.mem_stall);
  o.flush_w = x.wb_redirect | x.flush_onehot[3];
  return o;
endfunction
