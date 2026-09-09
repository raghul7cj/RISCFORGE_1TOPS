// ============================================================================
// RISC-V Trap Controller (CLIC + Exception Priority Selector)
// ============================================================================
// Module: trap_controller
//
// Purpose:
//   Implements RISC-V synchronous exception priority and integrates with 
//   Core-Local Interrupt Controller (CLIC) for asynchronous interrupt handling.
//
// Architecture:
//   - Combinatorial trap selection (detects prioritized trap)
//   - Synchronous trap capture (registered on clock edge)
//   - PC routing from each pipeline stage to MEPC
//
// Architecture Compliance:
//   - RISC-V Privileged ISA Manual v1.12
//   - RISC-V CLIC Specification
//
// Exception Code Reference (RISC-V):
//   0:  Instruction address misaligned
//   1:  Instruction access fault
//   2:  Illegal instruction
//   3:  Breakpoint
//   4:  Load address misaligned
//   5:  Load access fault
//   6:  Store/AMO address misaligned
//   7:  Store/AMO access fault
//   11: Environment call from M-mode
//
// ============================================================================

module trap_controller #(
    parameter XLEN = 32,
    parameter SrcW = 8,    // CLIC Source Width
    parameter PC_W = 32    // Program Counter Width
) (
    // Clock & Reset
    input  wire                clk,
    input  wire                rst_n,
    
    // Fetch (IF) stage exceptions + PC
    input wire                 instr_misaligned_if,
    input wire                 instr_access_fault_if,
    input wire [PC_W-1:0]      pc_if,
    
    // Decode (ID) stage exceptions + PC
    input wire                 illegal_instr_id,
    input wire                 ebreak_id,
    input wire                 ecall_m_id,
    input wire [PC_W-1:0]      pc_id,
    
    // Memory (MEM) stage exceptions + PC
    input wire                 load_misaligned_mem,
    input wire                 load_access_fault_mem,
    input wire                 store_misaligned_mem,
    input wire                 store_access_fault_mem,
    input wire [PC_W-1:0]      pc_mem,
    
    // CLIC Interface
    input  wire                irq_valid_i,     // Handshake from CLIC
    output wire                irq_ready_o,     // Ready to accept interrupt
    input  wire [SrcW-1:0]     irq_id_i,        // Interrupt ID
    input  wire [7:0]          irq_level_i,     // Interrupt Level
    input  wire                irq_shv_i,       // Selective Hardware Vectoring
    input  wire [1:0]          irq_priv_i,      // Privilege Level
    output wire                irq_kill_req_o,  // Pipeline flush request
    input  wire                irq_kill_ack_i,  // Pipeline flush acknowledge

    // Machine Status & CSR Info
    input wire                 mstatus_mie,     // Global interrupt enable from MSTATUS

    input wire [31:0]          mtvec_i,         // Trap Vector Base Address
    input wire [31:0]          mepc_i,          // Current MEPC (for nested traps)
    input wire [31:0]          mtval_i,         // Current MTVAL (for nested traps)
    input wire [31:0]          mcause_i,        // Current MCAUSE (for nested traps)
    input wire [31:0]          mip_i,           // Interrupt Pending
    input wire [31:0]          mie_i,           // Interrupt Enable

    input wire                 instr_is_mret_i, // Signal indicating current instruction is MRET (for return handling)
    
    // Synchronous Trap Outputs (valid after clock edge)
    output reg                 trap_valid_o,        // Trap is being serviced
    output reg [30:0]          trap_cause_o,        // Exception/Interrupt code/ID
    output reg [PC_W-1:0]      trap_pc_o,           // PC of faulting instruction
    output reg [31:0]          trap_addr_o,         // Exception-specific information (mtval)
    output reg                 trap_is_interrupt_o  // 1=interrupt, 0=exception

    // Port C to csr regfile for writing into CSR
    output reg csr_waddr_exc_o, // Address of CSR to write for exception info (e.g., mtval)  
    output reg [31:0] csr_wdata_exc_o, // Data to write into CSR for exception info
    output reg csr_wen_exc_o,   // Write enable for CSR write on exception

    // MIP bits for software, timer, and external interrupts (for CSR readback)
    output reg timer_intr_o,           // Timer interrupt pending (for mip)
    output reg ext_intr_o,             // External interrupt pending (for mip)
    output reg msft_intr_o,             // Software interrupt pending (for mip, set by writes to mip MSIP bit)

    //csr target , Trap Entry and Return address 
    output reg [31:0] trap_target_o,           // Target address for trap entry (from mtvec) or return (from mepc
    output reg trap_branch_o,             // Branch signal for trap entry/return (asserted when trap is taken or return is executed

    output reg [4:0] flush_pipeline_onehot 

);

    // ========================================================================
    // COMBINATORIAL TRAP SELECTION LOGIC
    // ========================================================================
    // Detects which trap to take (priority multiplexer).
    // These signals are NOT registered; they feed directly into the sync logic.
    // ========================================================================
    
    wire no_exception = ~(instr_misaligned_if
                         | instr_access_fault_if
                         | illegal_instr_id
                         | ebreak_id
                         | ecall_m_id
                         | load_misaligned_mem
                         | load_access_fault_mem
                         | store_misaligned_mem
                         | store_access_fault_mem);

    // Combinatorial selection outputs (UNREGISTERED)
    reg                trap_selected;
    reg  [30:0]         trap_cause_comb;
    reg  [PC_W-1:0]     trap_pc_comb;
    reg                 trap_is_interrupt_comb;
    
    // ========================================================================
    // PRIORITY MULTIPLEXER (RISC-V Table 3.7 - COMBINATORIAL)
    // ========================================================================
    // Priority order (decreasing):
    //   1. IF Exceptions  (Fetch error)
    //   2. ID Exceptions  (Illegal, EBREAK, ECALL)
    //   3. MEM Exceptions (Load/Store alignment/faults)
    //   4. CLIC Interrupt (Only if no higher priority exception exists)
    // ========================================================================

    // Priority mux is combinatorial and implements RISC-V Table 3.7 order.
    // Synchronous exceptions take precedence over asynchronous interrupts.
    // The ordering implemented below (highest -> lowest):
    //  - Instruction address misaligned (0)
    //  - Instruction access fault     (1)
    //  - Illegal instruction          (2)
    //  - Breakpoint (EBREAK)         (3)
    //  - Load address misaligned     (4)
    //  - Load access fault           (5)
    //  - Store/AMO address misaligned(6)
    //  - Store/AMO access fault      (7)
    //  - Environment calls (ecall)  (8,9,11) handled in decode stage when present
    //  - (Page faults / other synchronous exceptions should be added if inputs available)
    // Interrupts are only selected when no synchronous exception is pending
    // and global interrupt enable (`mstatus_mie`) permits.
    always @(*) begin
        trap_selected          = 1'b0;
        trap_is_interrupt_comb = 1'b0;
        trap_cause_comb        = 31'd0;
        trap_pc_comb           = {PC_W{1'b0}};

        // ---------------------------
        // Synchronous exceptions
        // ---------------------------
        if (instr_misaligned_if) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd0; // Instruction address misaligned
            trap_pc_comb    = pc_if;
        end
        else if (instr_access_fault_if) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd1; // Instruction access fault
            trap_pc_comb    = pc_if;
        end
        else if (illegal_instr_id) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd2; // Illegal instruction
            trap_pc_comb    = pc_id;
        end
        else if (ebreak_id) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd3; // Breakpoint
            trap_pc_comb    = pc_id;
        end
        // Environment calls (ECALL) - prioritized after breakpoint per Table 3.7
        else if (ecall_m_id) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd11; // ECALL from M-mode
            trap_pc_comb    = pc_id;
        end
        // Memory exceptions (load/store)
        else if (load_misaligned_mem) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd4; // Load address misaligned
            trap_pc_comb    = pc_mem;
        end
        else if (load_access_fault_mem) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd5; // Load access fault
            trap_pc_comb    = pc_mem;
        end
        else if (store_misaligned_mem) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd6; // Store address misaligned
            trap_pc_comb    = pc_mem;
        end
        else if (store_access_fault_mem) begin
            trap_selected   = 1'b1;
            trap_cause_comb = 31'd7; // Store access fault
            trap_pc_comb    = pc_mem;

        // ---------------------------
        // Asynchronous interrupts (checked between instructions)
        // Only consider interrupts when no synchronous exception present
        // and global interrupt enable allows it.
        // ---------------------------
        end else if (no_exception && mstatus_mie && irq_valid_i) begin
            trap_selected          = 1'b1;
            trap_is_interrupt_comb = 1'b1;
            // Map CLIC interrupt ID to mcause code for M-mode interrupts when known.
            // Common RISC-V machine-level mcause codes are:
            //   3 = Machine software interrupt
            //   7 = Machine timer interrupt
            //  11 = Machine external interrupt
            // If irq_id_i already encodes mcause code, pass it through; otherwise
            // implement mapping here (example mapping below for common IDs).
            unique case (irq_id_i)
                // Example: CLIC may use the same codes as mcause
                // If so, these cases simply copy the code.
                // Map known CLIC IDs to mcause codes (machine-mode examples):
                'd3:  trap_cause_comb = 31'd3;  // Machine software interrupt
                'd7:  trap_cause_comb = 31'd7;  // Machine timer interrupt
                'd11: trap_cause_comb = 31'd11; // Machine external interrupt
                default: begin
                    // If not a known mapping, place raw irq id into low bits of cause.
                    // The interrupt bit is provided separately via trap_is_interrupt_comb.
                    trap_cause_comb = {{(31-SrcW){1'b0}}, irq_id_i};
                end
            endcase
            // For interrupts, use fetch PC as MEPC by default (point to interrupted instruction)
            trap_pc_comb = pc_if;
        end
    end

    //MIP bits for software, timer, and external interrupts are directly driven by the CLIC interrupt valid/id signals.
    always @(*) begin
        ext_intr_o = irq_valid_i && (irq_id_i == 11); // Example: ID 11 for external
        timer_intr_o = irq_valid_i && (irq_id_i == 7); // Example: ID 7 for timer
        msft_intr_o = irq_valid_i && (irq_id_i == 3); // Example: ID 3 for software
    end

    // ========================================================================
    // SYNCHRONOUS TRAP CAPTURE LOGIC (REGISTERED)
    // ========================================================================
    // Trap outputs are captured synchronously on clock edge.
    // This allows CSR status/priority to be evaluated and resolved before
    // the trap handler executes. Trap is considered "taken" one cycle after
    // the trap condition is detected.
    // ========================================================================

    always @(posedge clk or negedge rst_n) begin
        if (~rst_n) begin
            trap_valid_o         <= 1'b0;
            trap_is_interrupt_o  <= 1'b0;
            trap_cause_o         <= 31'd0;
            trap_pc_o            <= {PC_W{1'b0}};
            trap_addr_o          <= 32'd0;
        end
        else begin
            // Synchronously capture trap selection
            trap_valid_o         <= trap_selected;
            trap_is_interrupt_o  <= trap_is_interrupt_comb;
            trap_cause_o         <= trap_cause_comb;
            trap_pc_o            <= trap_pc_comb;
            // mtval_o would be populated from pipeline data (faulting address, etc.)
            // Placeholder: Route fault_addr_mem or instruction bits if needed
            if (trapcause_comb == 31'd1 || trapcause_comb == 31'd0 || trapcause_comb == 31'd2) begin
                trap_addr_o <= pc_if; // Example: for instruction fetch faults, mtval = faulting instruction address
            end
            else if (trapcause_comb == 31'd4 || trapcause_comb == 31'd6) begin
                trap_addr_o <= pc_mem; // Example: for load/store misalignments, mtval = faulting instruction address
            end
            else if (trapcause_comb == 31'd5 || trapcause_comb == 31'd7) begin
                trap_addr_o <= pc_mem; // Example: for load/store access faults, mtval = faulting instruction address
            end
            else begin
                trap_addr_o <= 32'h0; // Default mtval for other exceptions/interrupts
            end
             
        end
    end

    //next state logic for Trap Entry and Return
    // ========================================================================
    always @(*) begin
        if (trap_taken) begin
            trap_target_o = mtvec_i; // On trap entry, target is mtvec
            trap_branch_o = 1'b1;    // Assert branch signal for trap entry
            case (trap_pc_comb)
                pc_if: flush_pipeline_onehot = 4'b0001; // Flush ID stage
                pc_id: flush_pipeline_onehot = 4'b0011; // Flush EX + ID stages
                pc_mem: flush_pipeline_onehot = 4'b1111; // Flush entire pipeline (ID, EX, MEM, WB)
                default: flush_pipeline_onehot = 4'b0000; // No flush if unknown stage (should not happen)

            endcase
        end
        else if ( instr_is_mret_i )begin
            trap_target_o = mepc_i; // On return, target is mepc
            trap_branch_o = 1'b1;   // Assert branch signal for return
            flush_pipeline_onehot = pipeline_busy? 4'b0000: 4'b0001; // Flush ID,EX pipeline on return to ensure clean state
        end
    end


    

    // ========================================================================
    // CLIC FLOW CONTROL (COMBINATORIAL WITH SYNC READINESS)
    // ========================================================================
    // irq_ready_o signals when an interrupt is actually being accepted
    // (selected by the priority mux). This becomes combinatorial with respect
    // to the CLIC, allowing it to immediately dequeue if ready.
    //
    // irq_kill_req_o requests pipeline flush for both exceptions and interrupts.
    // ========================================================================

    assign irq_ready_o    = trap_selected && trap_is_interrupt_comb;

    // Pipeline flush request: triggered when trap is taken
    // In a sophisticated design, this might hold until irq_kill_ack_i is asserted
    assign irq_kill_req_o = trap_valid_o;

endmodule

