`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name : hybrid_mem_interface
// Description : Address-decoder and Bus Router mapping an incoming LSU memory
//               request transaction to either native SRAM or an AXI4-Lite bus.
//
//   The SRAM path is purely combinational, so the core reaches data memory
//   directly — only MMIO traffic pays the AXI round-trip.
//
//   The AXI request/response structs arrive as TYPE PARAMETERS rather than
//   from axi_pkg, matching how axi_lite_sram_if, bootloader and
//   axi_lite_to_apb are already parameterised in this SoC. axi_pkg is still
//   used for the response-code constants.
//////////////////////////////////////////////////////////////////////////////////

module hybrid_mem_interface #(
     parameter integer MEM_DEPTH      = 6048576,       // words (4 MB default)
     parameter [31:0]  DMEM_BASE_BYTE = 32'h8000_1000, // DMEM byte base address
     parameter [31:0]  MMIO_BASE      = 32'h4000_0000,
     parameter [31:0]  MMIO_LIMIT     = 32'h4000_FFFF,
     parameter type    axi_req_t      = logic,
     parameter type    axi_resp_t     = logic
) (
    input  logic        clk,
    input  logic        rst_n,

    // =========================================================================
    // 1. INPUT FROM LOAD/STORE UNIT (LSU Memory Access Bus)
    // =========================================================================
    input  logic        mem_req,        // Valid memory transaction request
    input  logic        mem_we,         // Write Enable (1=Write, 0=Read)
    input  logic [31:0] mem_addr,       // Target byte address
    input  logic [31:0] mem_wdata,      // Aligned data to be written
    input  logic [3:0]  mem_be,         // Byte enables / Write strobes
    
    output logic [31:0] mem_rdata,      // Routed read data back to LSU
    output logic        mem_stall,      // Aggregated stall signal back to LSU
    output logic        mem_err,        // Aggregated error fault signal back to LSU

    // =========================================================================
    // 2. OUTPUT TO NATIVE SRAM INTERFACE (DMEM Block)
    // =========================================================================
    output logic        sram_en,        // SRAM Chip Enable
    output logic        sram_we,        // SRAM Write Enable
    output logic [3:0]  sram_wmask,     // SRAM Byte write mask
    output logic [29:0] sram_addr,      // SRAM Word Address (Truncated [31:2])
    output logic [31:0] sram_wdata,     // SRAM Write Data
    
    input  logic [31:0] sram_rdata,     // SRAM Read Data input (2-cycle latency)

    // =========================================================================
    // 3. OUTPUT TO AXI4-LITE BUS (Struct-based Interface)
    // =========================================================================
    output axi_req_t  m_axi_req_o,
    input  axi_resp_t m_axi_resp_i
);

    // =========================================================================
    // ADDRESS MAP BOUNDARIES
    // =========================================================================
    localparam [31:0] SRAM_BASE  = DMEM_BASE_BYTE;
    localparam [31:0] SRAM_LIMIT = DMEM_BASE_BYTE + (MEM_DEPTH * 4) - 1;

    // Helper signal for Reads
    wire mem_re = ~mem_we;

    // =========================================================================
    // INTERNAL ROUTING WIRES AND REGISTERS
    // =========================================================================
    wire addr_in_sram_range = (mem_addr >= SRAM_BASE) && (mem_addr <= SRAM_LIMIT);
    wire addr_in_mmio_range = (mem_addr >= MMIO_BASE) && (mem_addr <= MMIO_LIMIT);
    wire addr_fault         = mem_req && !(addr_in_sram_range || addr_in_mmio_range);

    wire sram_req_active = mem_req & addr_in_sram_range;
    wire axi_req_active  = mem_req & addr_in_mmio_range;

    wire sram_stall_needed;
    logic axi_w_stall, axi_r_stall;
    logic axi_w_err,   axi_r_err;
    logic [31:0] axi_rdata_reg;

    // Internal channel driving registers
    logic [31:0] m_axi_awaddr;
    logic        m_axi_awvalid;
    logic [31:0] m_axi_wdata;
    logic [3:0]  m_axi_wstrb;
    logic        m_axi_wvalid;
    logic        m_axi_bready;

    logic [31:0] m_axi_araddr;
    logic        m_axi_arvalid;
    logic        m_axi_rready;

    // =========================================================================
    // 1. SRAM ROUTING & 2-CYCLE LATENCY CONTROLLER
    // =========================================================================
    always_comb begin
        sram_en    = sram_req_active;
        sram_we    = mem_we;
        sram_wmask = mem_be;
        sram_addr  = mem_addr[31:2]; 
        sram_wdata = mem_wdata;
    end

    // -------------------------------------------------------------------------
    // SRAM read latency: exactly ONE stall cycle.
    //
    // The SoC's sram_sp is a registered-output SRAM — address presented at
    // cycle T, rdata valid at T+1. The MEM stage needs the data in time to
    // format it and latch MEM/WB, so it must be held for one cycle:
    //
    //   T   : IDLE, req && !we  -> stall=1, address presented, MEM/WB holds
    //   T+1 : WAIT              -> stall=0, sram_rdata valid, MEM/WB latches
    //   T+2 : IDLE              -> next access may start immediately
    //
    // One cycle is the floor for a synchronous SRAM; going lower would require
    // generating the address a stage earlier (in EX).
    //
    // Writes are NOT stalled — nothing comes back — hence the !mem_we gate.
    //
    // NOTE: this was previously forced to 0 to mimic an asynchronous
    // Data_Memory model. Against the registered sram_sp that returns the
    // PRE-write / stale word on every load.
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        SRAM_IDLE  = 2'b00,
        SRAM_WAIT  = 2'b01
    } sram_state_e;

    sram_state_e sram_rd_state, next_sram_rd_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) sram_rd_state <= SRAM_IDLE;
        else        sram_rd_state <= next_sram_rd_state;
    end

    always_comb begin
        case (sram_rd_state)
            SRAM_IDLE: begin
                if (sram_req_active && !mem_we)
                    next_sram_rd_state = SRAM_WAIT;
                else
                    next_sram_rd_state = SRAM_IDLE;
            end
            SRAM_WAIT: begin
                next_sram_rd_state = SRAM_IDLE;
            end
            default: next_sram_rd_state = SRAM_IDLE;
        endcase
    end

    assign sram_stall_needed = (sram_rd_state == SRAM_IDLE) && sram_req_active && !mem_we;

    // =========================================================================
    // 2. AXI LITE - WRITE FSM
    // =========================================================================
    typedef enum logic [1:0] {
        AXI_WRITE_IDLE = 2'b00,
        AXI_WAIT_ADDR  = 2'b01,
        AXI_WAIT_DATA  = 2'b10,
        AXI_WAIT_RESP  = 2'b11
    } axi_wr_state_e;

    axi_wr_state_e axi_write_state, next_axi_write_state;

    always_comb begin
        case (axi_write_state)
            AXI_WRITE_IDLE: begin
                if (axi_req_active && mem_we) begin
                    case ({m_axi_resp_i.aw_ready, m_axi_resp_i.w_ready})
                        2'b11:   next_axi_write_state = AXI_WAIT_RESP; 
                        2'b10:   next_axi_write_state = AXI_WAIT_DATA; 
                        2'b01:   next_axi_write_state = AXI_WAIT_ADDR; 
                        default: next_axi_write_state = AXI_WRITE_IDLE;
                    endcase
                end else begin
                    next_axi_write_state = AXI_WRITE_IDLE;
                end
            end
            // State meaning is set by the valid outputs below:
            //   AXI_WAIT_ADDR keeps awvalid high -> the ADDRESS is still outstanding
            //   AXI_WAIT_DATA keeps wvalid  high -> the DATA    is still outstanding
            // Each must therefore poll ITS OWN ready, and once that channel is
            // accepted BOTH are done, so the next state is AXI_WAIT_RESP.
            //
            // These two checks used to be swapped (WAIT_ADDR polled w_ready and
            // went to WAIT_DATA; WAIT_DATA polled aw_ready). That deadlocked the
            // core on its first MMIO access: with the crossbar in CUT_ALL_AX mode
            // the AW spill register accepts the address a cycle before W, giving
            // {aw_ready,w_ready} = 2'b10 -> AXI_WAIT_DATA, which then waited on an
            // aw_ready that could never return, because the AW register stays full
            // until the write completes. mem_stall was held high forever and the
            // pipeline froze with the store still in MEM.
            AXI_WAIT_ADDR: begin
                if (m_axi_resp_i.aw_ready) next_axi_write_state = AXI_WAIT_RESP;
                else                       next_axi_write_state = AXI_WAIT_ADDR;
            end
            AXI_WAIT_DATA: begin
                if (m_axi_resp_i.w_ready)  next_axi_write_state = AXI_WAIT_RESP;
                else                       next_axi_write_state = AXI_WAIT_DATA;
            end
            AXI_WAIT_RESP: begin
                if (m_axi_resp_i.b_valid) next_axi_write_state = AXI_WRITE_IDLE;
                else                      next_axi_write_state = AXI_WAIT_RESP;
            end
            default: next_axi_write_state = AXI_WRITE_IDLE;
        endcase
    end

    always_comb begin
        m_axi_awvalid = (axi_write_state == AXI_WRITE_IDLE && axi_req_active && mem_we) || (axi_write_state == AXI_WAIT_ADDR);
        m_axi_wvalid  = (axi_write_state == AXI_WRITE_IDLE && axi_req_active && mem_we) || (axi_write_state == AXI_WAIT_DATA);
        m_axi_bready  = (axi_write_state == AXI_WAIT_RESP);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_write_state <= AXI_WRITE_IDLE;
            axi_w_stall     <= 1'b0;
            axi_w_err       <= 1'b0;
            m_axi_awaddr    <= '0;
            m_axi_wdata     <= '0;
            m_axi_wstrb     <= '0;
        end else begin
            axi_write_state <= next_axi_write_state;

            case (axi_write_state)
                AXI_WRITE_IDLE: begin
                    axi_w_err <= 1'b0;
                    if (axi_req_active && mem_we) begin
                        m_axi_wstrb  <= mem_be;
                        m_axi_awaddr <= mem_addr;
                        m_axi_wdata  <= mem_wdata;
                        axi_w_stall  <= 1'b1;
                    end else begin
                        axi_w_stall  <= 1'b0;
                        m_axi_wstrb  <= '0;
                        m_axi_awaddr <= '0;
                        m_axi_wdata  <= '0;
                    end
                end
                AXI_WAIT_ADDR, AXI_WAIT_DATA: begin
                    axi_w_stall <= 1'b1;
                    axi_w_err   <= 1'b0;
                end
                AXI_WAIT_RESP: begin
                    if (m_axi_resp_i.b_valid) begin
                        axi_w_stall  <= 1'b0;
                        axi_w_err    <= (m_axi_resp_i.b.resp != axi_pkg::RESP_OKAY);
                        m_axi_awaddr <= '0;
                        m_axi_wdata  <= '0;
                        m_axi_wstrb  <= '0;
                    end else begin
                        axi_w_stall  <= 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    // =========================================================================
    // 3. AXI LITE - READ FSM
    // =========================================================================
    typedef enum logic [1:0] {
        AXI_READ_IDLE = 2'b00,
        AXI_WAIT_READ = 2'b01
    } axi_rd_state_e;

    axi_rd_state_e axi_read_state, next_axi_read_state;

    always_comb begin
        case (axi_read_state)
            AXI_READ_IDLE: begin
                if (axi_req_active && mem_re && m_axi_resp_i.ar_ready) 
                    next_axi_read_state = AXI_WAIT_READ;
                else
                    next_axi_read_state = AXI_READ_IDLE;
            end
            AXI_WAIT_READ: begin
                if (m_axi_resp_i.r_valid) next_axi_read_state = AXI_READ_IDLE;
                else                       next_axi_read_state = AXI_WAIT_READ;
            end
            default: next_axi_read_state = AXI_READ_IDLE;
        endcase
    end

    always_comb begin
        m_axi_arvalid = (axi_read_state == AXI_READ_IDLE) && axi_req_active && mem_re;
        m_axi_rready  = (axi_read_state == AXI_WAIT_READ);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_read_state <= AXI_READ_IDLE;
            axi_r_stall    <= 1'b0;
            axi_r_err      <= 1'b0;
            axi_rdata_reg  <= '0;
            m_axi_araddr   <= '0;
        end else begin
            axi_read_state <= next_axi_read_state;

            case (axi_read_state)
                AXI_READ_IDLE: begin
                    axi_r_err <= 1'b0;
                    if (axi_req_active && mem_re) begin
                        axi_r_stall  <= 1'b1;
                        m_axi_araddr <= mem_addr;
                    end else begin
                        axi_r_stall  <= 1'b0;
                    end
                end
                AXI_WAIT_READ: begin
                    if (m_axi_resp_i.r_valid) begin
                        axi_r_stall   <= 1'b0;
                        axi_rdata_reg <= m_axi_resp_i.r.data;           
                        axi_r_err     <= (m_axi_resp_i.r.resp != axi_pkg::RESP_OKAY);
                    end else begin
                        axi_r_stall   <= 1'b1;
                    end
                end
                default: ;
            endcase
        end
    end

    // =========================================================================
    // 4. STRUCT ASSIGNMENTS (Master Request Port)
    // =========================================================================
    // Address / data / strobe are driven straight from the LSU bus, NOT from the
    // m_axi_*_q registers below.
    //
    // The valid outputs are combinational: awvalid/wvalid/arvalid assert in the
    // SAME cycle the LSU request arrives. The registers, however, only capture
    // mem_addr/mem_wdata/mem_be at the END of that cycle. So whenever the
    // crossbar accepted on the first cycle (its spill registers do exactly that
    // when empty), the channel carried the PREVIOUS value — 0 after reset — and
    // the transaction went out addressed to 0x00000000 instead of the peripheral.
    //
    // Sourcing them combinationally is safe because these signals are held stable
    // for the whole transaction: mem_stall freezes the pipeline (memory_cycle
    // holds MEM/WB, hazard_unit stalls IF/ID/EX), so ALU_ResultM / WriteDataM /
    // lsunitM cannot change until the access completes.
    always_comb begin
        m_axi_req_o.aw.addr  = mem_addr;
        m_axi_req_o.aw.prot  = '0;
        m_axi_req_o.aw_valid = m_axi_awvalid;
        m_axi_req_o.w.data   = mem_wdata;
        m_axi_req_o.w.strb   = mem_be;
        m_axi_req_o.w_valid  = m_axi_wvalid;
        m_axi_req_o.b_ready  = m_axi_bready;
        m_axi_req_o.ar.addr  = mem_addr;
        m_axi_req_o.ar.prot  = '0;
        m_axi_req_o.ar_valid = m_axi_arvalid;
        m_axi_req_o.r_ready  = m_axi_rready;
    end

    // =========================================================================
    // 5. AGGREGATION & MULTIPLEXING LAYER (Back to LSU)
    // =========================================================================
    // The handshake back to the LSU must be COMBINATIONAL.
    //
    // axi_w_stall / axi_r_stall are flops: they only rise the cycle AFTER the
    // request appears. So on the very cycle the LSU issued an MMIO access,
    // mem_stall still read 0 — memory_cycle latched MEM/WB and the instruction
    // retired before the bus transaction had even started. The symptom was the
    // whole 11-instruction program finishing in 24 cycles (far too few for two
    // AXI->APB round trips), loads returning the stale axi_rdata_reg (x3 = 0),
    // and the store never reaching the timer.
    //
    // Deriving stall/err/rdata directly from the FSM state closes the loop in
    // the same cycle. This is also what keeps the combinational AW/W/AR address
    // drive above legal: with the pipeline correctly frozen, mem_addr/mem_wdata
    // are stable for the whole transaction.
    wire axi_wr_done = (axi_write_state == AXI_WAIT_RESP) && m_axi_resp_i.b_valid;
    wire axi_rd_done = (axi_read_state  == AXI_WAIT_READ) && m_axi_resp_i.r_valid;

    wire axi_wr_busy = axi_req_active && mem_we && !axi_wr_done;
    wire axi_rd_busy = axi_req_active && mem_re && !axi_rd_done;

    always_comb begin
        mem_stall = sram_stall_needed | axi_wr_busy | axi_rd_busy;

        // Errors likewise have to be reported on the completing cycle: the
        // registered axi_w_err / axi_r_err would arrive after the core had
        // already retired the access, so a bus fault would be missed entirely.
        mem_err = addr_fault
                | (axi_wr_done && (m_axi_resp_i.b.resp != axi_pkg::RESP_OKAY))
                | (axi_rd_done && (m_axi_resp_i.r.resp != axi_pkg::RESP_OKAY));

        if (addr_in_sram_range)
            mem_rdata = sram_rdata;
        else if (axi_rd_done)
            mem_rdata = m_axi_resp_i.r.data;  // forward on the release cycle
        else
            mem_rdata = axi_rdata_reg;
    end

endmodule