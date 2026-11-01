`timescale 1ns/1ps
// Focused block-level checks for the 13-source IRQ interface. This does not
// replace instruction-pipeline, firmware, or peripheral integration tests.
module tb_irq_restructure;
  reg clk = 0;
  always #5 clk = ~clk;
  reg rst_n = 0;
  reg [12:0] raw = 0, clear = 0;
  wire [12:0] pending;
  irq_gateway gw (.clk_i(clk), .rst_ni(rst_n), .irq_raw_i(raw),
    .edge_mode_i(13'h002), .event_mode_i(13'h1fe9), .clear_i(clear), .pend_o(pending));

  reg [12:0] arb_pending = 0;
  reg [31:0] mie = 32'hffff_ffff;
  reg global_mie = 1;
  reg [1:0] threshold = 0;
  reg commit = 0;
  reg [4:0] committed_id = 0;
  wire irq_valid;
  wire [4:0] irq_id;
  wire [1:0] irq_class;
  irq_arbiter arb (.clk_i(clk), .rst_ni(rst_n), .pend_i(arb_pending),
    .mie_i(mie), .mstatus_mie_i(global_mie), .mintprio_i(threshold),
    .wb_commit_i(commit), .wb_trap_cause_i(committed_id),
    .irq_pending_o(irq_valid), .irq_id_o(irq_id), .irq_class_o(irq_class));

  reg wb_valid = 0, wb_exc_valid = 0;
  reg [5:0] wb_cause = 0;
  wire [12:0] wb_clear;
  wire wb_irq;
  wb_trap_mret_commit_controller wb (.valid_W(wb_valid),
    .exc_valid_W(wb_exc_valid), .exc_cause_W(wb_cause), .exc_class_W(2'b0),
    .exc_tval_W(32'b0), .exc_pc_W(32'b0), .is_mret_W(1'b0),
    .mtvec_i(32'b0), .mepc_i(32'b0), .mstatus_i(32'b0),
    .clear_gateway_o(wb_clear), .wb_commit_irq_o(wb_irq));

  reg [11:0] csr_addr = 0, csr_write_addr = 0;
  reg [31:0] csr_write_data = 0;
  reg csr_write = 0, csr_trap = 0, csr_mret = 0, csr_ext = 0, csr_sw = 0;
  wire [31:0] csr_read, csr_mip, csr_mie, csr_mstatus, csr_mepc, csr_mcause;
  wire [1:0] csr_threshold;
  csr_regfile csr (.clk_i(clk), .rst_n_i(rst_n), .csr_raddr_i(csr_addr),
    .csr_rdata_o(csr_read), .csr_waddr_normal_i(csr_write_addr),
    .csr_wdata_normal_i(csr_write_data), .csr_write_en_normal_i(csr_write),
    .csr_waddr_mret_i(12'b0), .csr_wdata_mret_i(32'b0),
    .csr_write_en_mret_i(1'b0), .mret_commit_i(csr_mret), .trap_valid_i(csr_trap),
    .trap_cause_i(31'd19), .trap_pc_i(32'h120), .trap_addr_i(32'b0),
    .trap_addr_valid_i(1'b0), .trap_is_interrupt_i(1'b1), .instr_retired_i(1'b0),
    .timer_intr_i(pending[0]), .ext_intr_i(csr_ext), .msft_intr_i(csr_sw),
    .fast_intr_i({4'b0,pending[12:1]}), .mip_out_o(csr_mip),
    .mie_out_o(csr_mie), .mintprio_out_o(csr_threshold),
    .mstatus_out_o(csr_mstatus), .mepc_out_o(csr_mepc), .mcause_out_o(csr_mcause));

  integer fixed_order [0:7];
  integer stream_order [0:2];
  integer i, j, v, t, ptr, bgptr, expected_id, expected_class, idx, snapshots;
  integer en, glob, operation, next_id, upper_pattern, pair_bin, mask_value;
  reg [31:0] csr_test_data;
  reg found;

  // Samples are taken only after the corresponding expected behavior is checked.
  covergroup eligibility_cg with function sample(int source, int prio, bit en, bit global_en);
    option.per_instance = 1;
    source_cp: coverpoint source { bins sources[] = {[0:12]}; }
    threshold_cp: coverpoint prio { bins levels[] = {[0:3]}; }
    enable_cp: coverpoint en { bins disabled = {0}; bins enabled = {1}; }
    global_cp: coverpoint global_en { bins disabled = {0}; bins enabled = {1}; }
    source_gates: cross source_cp, threshold_cp, enable_cp, global_cp;
  endgroup

  covergroup rr_cg with function sample(int which, int event_kind);
    option.per_instance = 1;
    // 0..2: class-1 winner 19/18/27; 3..4: class-0 winner 17/16.
    winner_cp: coverpoint which { bins winners[] = {[0:4]}; }
    // 0 = matching commit, 1 = no commit, 2 = other-class commit.
    operation_cp: coverpoint event_kind { bins operations[] = {[0:2]}; }
    winner_operation: cross winner_cp, operation_cp;
  endgroup

  covergroup stream_choice_cg with function sample(int pointer, int mask);
    option.per_instance = 1;
    pointer_cp: coverpoint pointer { bins values[] = {[0:2]}; }
    mask_cp: coverpoint mask { bins values[] = {[0:7]}; }
    choices: cross pointer_cp, mask_cp;
  endgroup

  covergroup background_choice_cg with function sample(int pointer, int mask);
    option.per_instance = 1;
    pointer_cp: coverpoint pointer { bins values[] = {[0:1]}; }
    mask_cp: coverpoint mask { bins values[] = {[0:3]}; }
    choices: cross pointer_cp, mask_cp;
  endgroup

  covergroup fixed_pair_cg with function sample(int pair_index);
    option.per_instance = 1;
    pair_cp: coverpoint pair_index { bins pairs[] = {[0:27]}; }
  endgroup

  covergroup event_gateway_cg with function sample(int source, int scenario);
    option.per_instance = 1;
    source_cp: coverpoint source { bins events[] = {0,3,[5:12]}; }
    scenario_cp: coverpoint scenario { bins cases[] = {[0:3]}; }
    source_scenario: cross source_cp, scenario_cp;
  endgroup

  covergroup gpio_gateway_cg with function sample(int scenario);
    option.per_instance = 1;
    scenario_cp: coverpoint scenario { bins cases[] = {[0:3]}; }
  endgroup

  covergroup level_gateway_cg with function sample(int source, int scenario);
    option.per_instance = 1;
    source_cp: coverpoint source { bins levels[] = {2,4}; }
    scenario_cp: coverpoint scenario { bins cases[] = {[0:2]}; }
    source_scenario: cross source_cp, scenario_cp;
  endgroup

  covergroup csr_cg with function sample(int old_value, int new_value, int upper_pattern);
    option.per_instance = 1;
    old_cp: coverpoint old_value { bins values[] = {[0:3]}; }
    new_cp: coverpoint new_value { bins values[] = {[0:3]}; }
    upper_cp: coverpoint upper_pattern { bins zero = {0}; bins mixed = {1}; bins ones = {2}; }
    transitions: cross old_cp, new_cp;
  endgroup

  covergroup commit_cg with function sample(int source);
    option.per_instance = 1;
    source_cp: coverpoint source { bins sources[] = {[0:12]}; }
  endgroup

  covergroup commit_control_cg with function sample(int scenario);
    option.per_instance = 1;
    // No valid packet, no exception, synchronous exception, unsupported IRQ.
    scenario_cp: coverpoint scenario { bins cases[] = {[0:3]}; }
  endgroup

  covergroup csr_control_cg with function sample(int scenario);
    option.per_instance = 1;
    // Reset, trap-priority write suppression, MRET-priority write suppression.
    scenario_cp: coverpoint scenario { bins cases[] = {[0:2]}; }
  endgroup

  covergroup csr_irq_cg with function sample(int scenario);
    option.per_instance = 1;
    // MIE=0/1 on entry, MPIE=0/1 on MRET, SW MSIP, input MSIP, MEIP.
    scenario_cp: coverpoint scenario { bins cases[] = {[0:6]}; }
  endgroup

  covergroup mie_bits_cg with function sample(int bit_index);
    option.per_instance = 1;
    bit_cp: coverpoint bit_index { bins supported[] = {3,7,11,[16:31]}; }
  endgroup

  eligibility_cg eligibility_cov = new();
  rr_cg rr_cov = new();
  stream_choice_cg stream_choice_cov = new();
  background_choice_cg background_choice_cov = new();
  fixed_pair_cg fixed_pair_cov = new();
  event_gateway_cg event_cov = new();
  gpio_gateway_cg gpio_cov = new();
  level_gateway_cg level_cov = new();
  csr_cg csr_cov = new();
  commit_cg commit_cov = new();
  commit_control_cg commit_control_cov = new();
  csr_control_cg csr_control_cov = new();
  csr_irq_cg csr_irq_cov = new();
  mie_bits_cg mie_bits_cov = new();

  function automatic integer bit_for_id(input integer id);
    if (id == 7) bit_for_id = 0;
    else bit_for_id = id - 15;
  endfunction

  task automatic write_csr(input [11:0] addr, input [31:0] data);
    @(negedge clk); csr_write_addr = addr; csr_write_data = data; csr_write = 1;
    @(negedge clk); csr_write = 0;
  endtask

  task automatic set_stream_ptr(input integer p);
    @(negedge clk); commit = 1;
    case (p)
      0: committed_id = 27;
      1: committed_id = 19;
      2: committed_id = 18;
    endcase
    @(negedge clk); commit = 0;
  endtask

  task automatic set_background_ptr(input integer p);
    @(negedge clk); commit = 1; committed_id = p ? 17 : 16;
    @(negedge clk); commit = 0;
  endtask

  initial begin
    fixed_order[0]=7; fixed_order[1]=22; fixed_order[2]=24; fixed_order[3]=26;
    fixed_order[4]=20; fixed_order[5]=21; fixed_order[6]=23; fixed_order[7]=25;
    stream_order[0]=19; stream_order[1]=18; stream_order[2]=27;
    repeat (2) @(negedge clk); rst_n = 1;
    #1; if (csr_threshold !== 0 || csr_mie !== 0 || pending !== 0)
      $fatal(1,"reset state mismatch");
    csr_control_cov.sample(0);

    // Exhaustive request vectors at all thresholds and both RR pointer states.
    snapshots = 0;
    for (bgptr=0; bgptr<2; bgptr=bgptr+1) begin
    set_background_ptr(bgptr);
    for (ptr=0; ptr<3; ptr=ptr+1) begin
      set_stream_ptr(ptr);
      for (v=0; v<8192; v=v+1) begin
        arb_pending = v;
        for (t=0; t<4; t=t+1) begin
          threshold = t; #1;
          found=0; expected_id=0; expected_class=0;
          for (j=0; j<8; j=j+1)
            if (!found && arb_pending[bit_for_id(fixed_order[j])]) begin
              found=1; expected_id=fixed_order[j]; expected_class=2;
            end
          for (j=0; j<3; j=j+1) begin
            idx=(ptr+j)%3;
            if (!found && arb_pending[bit_for_id(stream_order[idx])]) begin
              found=1; expected_id=stream_order[idx]; expected_class=1;
            end
          end
          if (!found && arb_pending[bgptr ? 1 : 2]) begin
            found=1; expected_id=bgptr ? 16 : 17; expected_class=0;
          end
          if (!found && arb_pending[bgptr ? 2 : 1]) begin
            found=1; expected_id=bgptr ? 17 : 16; expected_class=0;
          end
          if (irq_valid !== (found && expected_class+1 > t) ||
              (irq_valid && (irq_id !== expected_id || irq_class !== expected_class)))
            $fatal(1,"arbiter mismatch vector=%h ptr=%0d threshold=%0d got=%b/%0d/%0d expected=%0d/%0d/%0d",
              arb_pending,ptr,t,irq_valid,irq_id,irq_class,found && expected_class+1 > t,expected_id,expected_class);
          if (t==0 && (arb_pending & ~13'h1018)==0) begin
            mask_value={arb_pending[12],arb_pending[3],arb_pending[4]};
            stream_choice_cov.sample(ptr,mask_value);
          end
          if (t==0 && (arb_pending & ~13'h0006)==0)
            background_choice_cov.sample(bgptr,arb_pending[2:1]);
          snapshots=snapshots+1;
        end
      end
    end
    end
    arb_pending=13'h1fff; threshold=0; mie=0; #1;
    if (irq_valid) $fatal(1,"mie mask did not block interrupt");
    for (i=0; i<13; i=i+1) begin
      expected_id = (i == 0) ? 7 : i+15;
      mie=32'b1 << expected_id; #1;
      if (!irq_valid || irq_id != expected_id)
        $fatal(1,"individual mie mask mismatch cause=%0d",expected_id);
    end
    global_mie=0; #1; if (irq_valid) $fatal(1,"global MIE did not block interrupt");
    global_mie=1;

    // Every pair of fixed-priority sources: compare wins over the later entry.
    pair_bin=0; threshold=0; mie=32'hffff_ffff;
    for (i=0; i<8; i=i+1)
      for (j=i+1; j<8; j=j+1) begin
        arb_pending=(13'b1 << bit_for_id(fixed_order[i])) |
                    (13'b1 << bit_for_id(fixed_order[j])); #1;
        if (!irq_valid || irq_id != fixed_order[i]) $fatal(1,"fixed pair mismatch");
        fixed_pair_cov.sample(pair_bin); pair_bin=pair_bin+1;
      end

    // Single-source eligibility: all source/threshold/mie/MIE combinations.
    for (i=0; i<13; i=i+1) begin
      expected_id=(i==0) ? 7 : i+15;
      expected_class=(i==1 || i==2) ? 0 : ((i==3 || i==4 || i==12) ? 1 : 2);
      arb_pending=13'b1 << i;
      for (t=0; t<4; t=t+1)
        for (en=0; en<2; en=en+1)
          for (glob=0; glob<2; glob=glob+1) begin
            threshold=t; mie=en ? (32'b1 << expected_id) : 0; global_mie=glob; #1;
            found=en && glob && (expected_class+1 > t);
            if (irq_valid !== found || (found && (irq_id != expected_id || irq_class != expected_class)))
              $fatal(1,"eligibility mismatch source=%0d threshold=%0d enable=%0d MIE=%0d",expected_id,t,en,glob);
            eligibility_cov.sample(i,t,en,glob);
          end
    end
    threshold=0; mie=32'hffff_ffff; global_mie=1;

    // Each RR winner: no commit, other-class commit, then matching commit.
    // Keep all members requested so pointer movement is observable at output.
    for (i=0; i<5; i=i+1) begin
      if (i<3) begin
        set_stream_ptr(i); arb_pending=(13'b1<<4)|(13'b1<<3)|(13'b1<<12);
        expected_id=stream_order[i]; next_id=stream_order[(i+1)%3];
      end else begin
        set_background_ptr(i-3); arb_pending=(13'b1<<2)|(13'b1<<1);
        expected_id=(i==3) ? 17 : 16; next_id=(i==3) ? 16 : 17;
      end
      #1; if (!irq_valid || irq_id != expected_id) $fatal(1,"RR initial winner mismatch");
      for (operation=1; operation<=2; operation=operation+1) begin
        @(negedge clk); commit=(operation==2); committed_id=(i<3) ? 17 : 19;
        @(negedge clk); commit=0; #1;
        if (!irq_valid || irq_id != expected_id) $fatal(1,"RR changed without matching commit");
        rr_cov.sample(i,operation);
      end
      @(negedge clk); commit=1; committed_id=expected_id;
      @(negedge clk); commit=0; #1;
      if (!irq_valid || irq_id != next_id) $fatal(1,"RR did not advance after commit");
      rr_cov.sample(i,0);
    end

    // Commit decoding must use the committed packet cause, not a live winner.
    wb_valid=1; wb_exc_valid=1;
    for (i=0; i<13; i=i+1) begin
      wb_cause = 6'h20 | ((i==0) ? 7 : i+15); #1;
      if (wb_clear !== (13'b1 << i) || !wb_irq) $fatal(1,"commit clear mismatch bit=%0d",i);
      commit_cov.sample(i);
    end
    wb_cause=6'd7; #1; if (wb_clear || wb_irq) $fatal(1,"exception cleared an IRQ");
    commit_control_cov.sample(2);
    wb_cause=6'h20 | 6'd3; #1;
    if (wb_clear || !wb_irq) $fatal(1,"unsupported IRQ clear mismatch");
    commit_control_cov.sample(3);
    wb_cause=6'h20 | 6'd7; wb_exc_valid=0; #1;
    if (wb_clear || wb_irq) $fatal(1,"invalid exception packet acknowledged");
    commit_control_cov.sample(1);
    wb_exc_valid=1; wb_valid=0; #1;
    if (wb_clear || wb_irq) $fatal(1,"invalid WB packet acknowledged");
    commit_control_cov.sample(0);

    // Pending/mip capture is independent of enables; an event on ack wins.
    @(negedge clk); raw=13'h1fe9;
    @(negedge clk); raw=0;
    #1; if ((pending & 13'h1fe9) !== 13'h1fe9) $fatal(1,"event capture failed");
    if (csr_mip !== ({4'b0,pending[12:1],16'b0} | (pending[0] << 7)))
      $fatal(1,"mip mapping failed: %h",csr_mip);
    @(negedge clk); clear=13'h1fe9; raw=13'h0008;
    @(negedge clk); clear=0; raw=0; #1;
    if (pending !== 13'h0008) $fatal(1,"event/ack coincidence failed: %h",pending);
    // Back-to-back event samples with ack on the second sample remain pending.
    @(negedge clk); raw=13'h0008;
    @(negedge clk); clear=13'h0008;
    @(negedge clk); raw=0; clear=0; #1;
    if (!pending[3]) $fatal(1,"adjacent event samples lost");
    @(negedge clk); clear=13'h0008;
    @(negedge clk); clear=0; #1; if (pending) $fatal(1,"ack failed");
    // Level sources pass through; GPIO rising edge is sticky until ack.
    @(negedge clk); raw=13'h0016; #1;
    if ((pending & 13'h0014) !== 13'h0014) $fatal(1,"level passthrough failed");
    @(negedge clk); raw=0; #1;
    if (pending !== 13'h0002) $fatal(1,"GPIO edge capture failed");
    @(negedge clk); clear=13'h0002;
    @(negedge clk); clear=0;

    // Exercise every configured per-cycle event input separately.
    for (i=0; i<13; i=i+1) begin
      if ((13'h1fe9 & (13'b1 << i)) != 0) begin
        @(negedge clk); raw=13'b1 << i;
        @(negedge clk); raw=0; #1;
        if (!pending[i]) $fatal(1,"event capture missing bit %0d",i);
        expected_id=(i==0) ? 7 : i+15;
        if (!csr_mip[expected_id]) $fatal(1,"mip mapping missing source %0d",expected_id);
        @(negedge clk); clear=13'b1 << i;
        @(negedge clk); clear=0; #1;
        if (pending[i]) $fatal(1,"event clear missing bit %0d",i);
        event_cov.sample(i,0);

        // 1,0,1: clear the first event, then capture a new event with ack.
        @(negedge clk); raw=13'b1 << i;
        @(negedge clk); raw=0; clear=13'b1 << i;
        @(negedge clk); raw=13'b1 << i;
        @(negedge clk); raw=0; clear=0; #1;
        if (!pending[i]) $fatal(1,"separated event lost bit %0d",i);
        event_cov.sample(i,1);
        @(negedge clk); clear=13'b1 << i;
        @(negedge clk); clear=0;

        // Consecutive asserted cycles, with ack at the second sample.
        @(negedge clk); raw=13'b1 << i;
        @(negedge clk); clear=13'b1 << i;
        @(negedge clk); raw=0; clear=0; #1;
        if (!pending[i]) $fatal(1,"consecutive event lost bit %0d",i);
        event_cov.sample(i,2);
        @(negedge clk); clear=13'b1 << i;
        @(negedge clk); clear=0;

        // Held-high event is treated as an event each sampled cycle.
        @(negedge clk); raw=13'b1 << i;
        repeat (3) @(negedge clk);
        clear=13'b1 << i;
        @(negedge clk); raw=0; clear=0; #1;
        if (!pending[i]) $fatal(1,"held event/ack lost bit %0d",i);
        event_cov.sample(i,3);
        @(negedge clk); clear=13'b1 << i;
        @(negedge clk); clear=0;
      end
    end

    // GPIO edge: capture, held high with ack, coincident new edge, rearm.
    @(negedge clk); raw=13'h002;
    @(negedge clk); #1; if (!pending[1]) $fatal(1,"GPIO edge missing"); gpio_cov.sample(0);
    clear=13'h002;
    @(negedge clk); clear=0; #1;
    if (pending[1]) $fatal(1,"GPIO held level retriggered"); gpio_cov.sample(1);
    raw=0;
    @(negedge clk); raw=13'h002; clear=13'h002;
    @(negedge clk); raw=0; clear=0; #1;
    if (!pending[1]) $fatal(1,"GPIO edge did not win ack"); gpio_cov.sample(2);
    @(negedge clk); clear=13'h002;
    @(negedge clk); clear=0; raw=13'h002;
    @(negedge clk); raw=0; #1;
    if (!pending[1]) $fatal(1,"GPIO rearm failed"); gpio_cov.sample(3);
    @(negedge clk); clear=13'h002;
    @(negedge clk); clear=0;

    // I2C and UART are level pass-through; ack does not clear a held level.
    for (i=2; i<=4; i=i+2) begin
      @(negedge clk); raw=13'b1 << i; #1;
      if (!pending[i]) $fatal(1,"level assertion missing bit %0d",i); level_cov.sample(i,0);
      clear=13'b1 << i;
      @(negedge clk); #1;
      if (!pending[i]) $fatal(1,"level ack changed output bit %0d",i); level_cov.sample(i,1);
      raw=0; clear=0; #1;
      if (pending[i]) $fatal(1,"level deassertion missing bit %0d",i); level_cov.sample(i,2);
    end

    write_csr(12'h304,32'h0fff0080);
    if (csr_mie !== 32'h0fff0080) $fatal(1,"mie CSR fast bits mismatch");
    for (i=0; i<4; i=i+1) begin
      for (j=0; j<4; j=j+1) begin
        write_csr(12'h7c0,i);
        upper_pattern=(i*4+j)%3;
        case (upper_pattern)
          0: csr_test_data=j;
          1: csr_test_data=32'ha5a5_a5a4 | j;
          default: csr_test_data=32'hffff_fffc | j;
        endcase
        write_csr(12'h7c0,csr_test_data);
        csr_addr=12'h7c0; #1;
        if (csr_read !== j || csr_threshold !== j) $fatal(1,"mintprio CSR transition mismatch");
        csr_cov.sample(i,j,upper_pattern);
      end
    end
    write_csr(12'h7c0,2);
    @(negedge clk); csr_write=1; csr_write_addr=12'h7c0; csr_write_data=1; csr_trap=1;
    @(negedge clk); csr_write=0; csr_trap=0; #1;
    if (csr_threshold !== 2) $fatal(1,"trap changed mintprio"); csr_control_cov.sample(1);
    @(negedge clk); csr_write=1; csr_write_addr=12'h7c0; csr_write_data=1; csr_mret=1;
    @(negedge clk); csr_write=0; csr_mret=0; #1;
    if (csr_threshold !== 2) $fatal(1,"MRET changed mintprio"); csr_control_cov.sample(2);

    // CSR interrupt mask supports standard bits and all 16 fast bits.
    for (i=0; i<32; i=i+1) begin
      if ((i==3) || (i==7) || (i==11) || (i>=16)) begin
        write_csr(12'h304,32'b1 << i);
        if (csr_mie !== (32'b1 << i)) $fatal(1,"mie CSR bit %0d failed",i);
        mie_bits_cov.sample(i);
      end
    end
    write_csr(12'h304,32'hffff_ffff);
    if (csr_mie !== 32'hffff_0888) $fatal(1,"mie implemented-bit mask failed");
    // Trap entry captures MIE and metadata; MRET restores MIE from MPIE.
    for (i=0; i<2; i=i+1) begin
      write_csr(12'h300,i ? 32'h8 : 32'h0);
      @(negedge clk); csr_trap=1;
      @(negedge clk); csr_trap=0; #1;
      if (csr_mstatus[3] !== 0 || csr_mstatus[7] !== i ||
          csr_mepc !== 32'h120 || csr_mcause !== 32'h8000_0013 || csr_threshold !== 2)
        $fatal(1,"trap CSR capture mismatch MIE=%0d",i);
      csr_irq_cov.sample(i);
      @(negedge clk); csr_mret=1;
      @(negedge clk); csr_mret=0; #1;
      if (csr_mstatus[3] !== i || csr_mstatus[7] !== 1 || csr_threshold !== 2)
        $fatal(1,"MRET CSR restore mismatch MPIE=%0d",i);
      csr_irq_cov.sample(i+2);
    end
    write_csr(12'h344,32'h8); #1;
    if (!csr_mip[3]) $fatal(1,"software MSIP write missing");
    write_csr(12'h344,0); #1;
    if (csr_mip[3]) $fatal(1,"software MSIP clear failed"); csr_irq_cov.sample(4);
    csr_sw=1; #1; if (!csr_mip[3]) $fatal(1,"MSIP input missing");
    csr_sw=0; #1; if (csr_mip[3]) $fatal(1,"MSIP input clear failed"); csr_irq_cov.sample(5);
    csr_ext=1; #1; if (!csr_mip[11]) $fatal(1,"MEIP input missing");
    csr_ext=0; #1; if (csr_mip[11]) $fatal(1,"MEIP input clear failed"); csr_irq_cov.sample(6);
    $display("PASS: %0d arbitration snapshots plus gateway, mip/mie, mintprio and commit checks",snapshots);
    $finish;
  end
endmodule
