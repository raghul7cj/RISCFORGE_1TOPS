# Milestone 1 Bus Monitors Investigation Report (AXI4-Lite & APB 6-Slot)

## 1. Observation

### 1.1 Existing Bus Monitor Implementations
Direct inspection of `Verification/infrastructure/monitors/axi_lite_monitor.sv` and `Verification/infrastructure/monitors/apb_monitor.sv` reveals:

1. **`axi_lite_monitor.sv`**:
   - Lines 7-42: Declares flat discrete port inputs (`awaddr`, `awprot`, `awvalid`, `awready`, `wdata`, `wstrb`, `wvalid`, `wready`, `bresp`, `bvalid`, `bready`, `araddr`, `arprot`, `arvalid`, `arready`, `rdata`, `rresp`, `rvalid`, `rready`).
   - Line 44: Declares `axi_txn_t ring_buffer [0:RING_BUFFER_DEPTH-1];` with parameter `RING_BUFFER_DEPTH = 64`.
   - Lines 84-110:
     ```systemverilog
     // Completed Write Transaction (B handshake)
     if (bvalid && bready && !freeze) begin
       ring_buffer[head_ptr].timestamp <= cycle_cnt;
       ring_buffer[head_ptr].addr      <= latched_awaddr;
       ring_buffer[head_ptr].data      <= latched_wdata;
       ring_buffer[head_ptr].strb      <= latched_wstrb;
       ring_buffer[head_ptr].resp      <= bresp;
       ring_buffer[head_ptr].is_write  <= 1'b1;

       head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
       total_axi_writes <= total_axi_writes + 1;
     end

     // Completed Read Transaction (R handshake)
     if (rvalid && rready && !freeze) begin
       int next_ptr;
       next_ptr = (bvalid && bready && !freeze) ? ((head_ptr + 1) % RING_BUFFER_DEPTH) : head_ptr;

       ring_buffer[next_ptr].timestamp <= cycle_cnt;
       ring_buffer[next_ptr].addr      <= latched_araddr;
       ring_buffer[next_ptr].data      <= rdata;
       ring_buffer[next_ptr].strb      <= 4'hF;
       ring_buffer[next_ptr].resp      <= rresp;
       ring_buffer[next_ptr].is_write  <= 1'b0;

       head_ptr <= (next_ptr + 1) % RING_BUFFER_DEPTH;
       total_axi_reads <= total_axi_reads + 1;
     end
     ```
   - Race condition on `head_ptr`: If both B and R handshakes complete in the same clock cycle, both branches assign non-blocking updates to `head_ptr` (`head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH` at line 92 vs `head_ptr <= (next_ptr + 1) % RING_BUFFER_DEPTH` at line 108). In SystemVerilog, the second assignment overwrites the first.
   - Latching race condition: Lines 76-81 latch `latched_awaddr <= awaddr;` non-blockingly. If AW/W and B handshakes occur in the same clock cycle (common in fast/cached/SRAM transactions), `ring_buffer[head_ptr].addr` samples the stale previous value of `latched_awaddr`.
   - Struct field under-population: `axi_txn_t` in `tb_pkg.sv` (lines 475-498) defines 20 fields (`timestamp`, `rel_cycle`, `seq`, `addr`, `data`, `strb`, `resp`, `is_write`, `prot`, `aw_hs`, `w_hs`, `b_hs`, `aw_wait`, `w_wait`, `b_wait`, `aw_to_w`, `aw_to_b`, `ar_to_r`, `is_mmio`, `apb_slot`, `decoded`). `axi_lite_monitor.sv` populates only 6 fields (`timestamp`, `addr`, `data`, `strb`, `resp`, `is_write`), leaving all others zero or undefined.

2. **`apb_monitor.sv`**:
   - Lines 16-24:
     ```systemverilog
     input logic [31:0]          paddr,
     input logic [NUM_SLOTS-1:0] psel,
     input logic                 penable,
     input logic                 pwrite,
     input logic [31:0]          pwdata,
     input logic [NUM_SLOTS-1:0] pready,
     input logic [31:0]          prdata [0:NUM_SLOTS-1],
     input logic [NUM_SLOTS-1:0] pslverr
     ```
   - Port defect: Lacks `pstrb [3:0]` input port entirely. In APB4 and RISCFORGE GPIO (Feature 14), byte strobes determine sub-word write permissions and PSLVERR generation.
   - Simulator incompatibility: `input logic [31:0] prdata [0:NUM_SLOTS-1]` is an unpacked array of vectors. Vivado XSim 2022.2 frequently errors or crashes on unpacked arrays across module boundaries and clocking blocks (documented in `rf_monitor_if.sv:11-13`).
   - Lines 48-63:
     ```systemverilog
     for (int i = 0; i < NUM_SLOTS; i++) begin
       if (psel[i] && penable && pready[i] && !freeze) begin
         ring_buffer[head_ptr].timestamp <= cycle_cnt;
         ring_buffer[head_ptr].slot      <= i;
         ring_buffer[head_ptr].paddr     <= paddr;
         ring_buffer[head_ptr].pwdata    <= pwdata;
         ring_buffer[head_ptr].prdata    <= prdata[i];
         ring_buffer[head_ptr].pwrite    <= pwrite;
         ring_buffer[head_ptr].pslverr   <= pslverr[i];

         head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
         total_apb_trans <= total_apb_trans + 1;
         per_slot_trans[i] <= per_slot_trans[i] + 1;
       end
     end
     ```
   - Struct field under-population: Leaves `rel_cycle`, `seq`, `pstrb`, `wait_states`, `setup_cycle`, `access_cycle`, and `addr_match` unpopulated.

### 1.2 Packed Struct Definitions in `RTL_SOC/riscforge_soc_subsystem.sv`
In `RTL_SOC/riscforge_soc_subsystem.sv`:
1. Section 1 (Lines 340-386):
   - `aw_chan_t`: `{addr: logic[31:0], prot: axi_pkg::prot_t (3b)}` (35 bits)
   - `w_chan_t`: `{data: logic[31:0], strb: logic[3:0]}` (36 bits)
   - `b_chan_t`: `{resp: axi_pkg::resp_t (2b)}` (2 bits)
   - `ar_chan_t`: `{addr: logic[31:0], prot: axi_pkg::prot_t (3b)}` (35 bits)
   - `r_chan_t`: `{data: logic[31:0], resp: axi_pkg::resp_t (2b)}` (34 bits)
   - `axi_req_t`: `{aw: aw_chan_t, aw_valid: logic, w: w_chan_t, w_valid: logic, b_ready: logic, ar: ar_chan_t, ar_valid: logic, r_ready: logic}` (111 bits packed)
   - `axi_resp_t`: `{aw_ready: logic, w_ready: logic, b: b_chan_t, b_valid: logic, ar_ready: logic, r: r_chan_t, r_valid: logic}` (41 bits packed)
2. Section 2 (Lines 399-413):
   - `apb_req_t`: `{paddr: logic[31:0], pprot: axi_pkg::prot_t (3b), psel: logic, penable: logic, pwrite: logic, pwdata: logic[31:0], pstrb: logic[3:0]}` (74 bits packed)
   - `apb_resp_t`: `{pready: logic, prdata: logic[31:0], pslverr: logic}` (34 bits packed)
3. Lines 544-546:
   - `apb_req_t  [NUM_APB_SLAVES-1:0] apb_req;`
   - `apb_resp_t [NUM_APB_SLAVES-1:0] apb_resp;` (bridge side)
   - `apb_resp_t [NUM_APB_SLAVES-1:0] apb_resp_slv;` (slave side)
4. Section 9 Note (Lines 693-698):
   - Flat discrete AXI and APB signals were completely removed from `riscforge_soc_subsystem.sv`. The subsystem operates 100% on packed structs (`core_axi_req`, `core_axi_resp`, `xbar_slv_req`, `apb_req`, `apb_resp`).
   - Consequently, in `Verification/infrastructure/tb/soc_tb_top.sv` (lines 218-251), references to `dut.m0_awaddr`, `dut.m0_wdata`, `dut.apb_paddr`, `dut.apb_psel` fail elaboration because those nets do not exist.

### 1.3 Core AXI Master Port vs Crossbar Port 0 Taps
1. Direct observation of `riscforge_soc_subsystem.sv` Section 21b (lines 1262-1330):
   - Core MMIO port connects via `hybrid_mem_interface`:
     - `m_axi_req_o` -> `core_axi_req`
     - `m_axi_resp_i` <- `core_axi_resp`
   - `core_axi_req` / `core_axi_resp` feeds `axi_lite_timeout_monitor`:
     ```systemverilog
     axi_lite_timeout_monitor #(...) i_axi_lite_timeout_monitor (
       .slv_req_i           ( core_axi_req            ),
       .slv_resp_o          ( core_axi_resp           ),
       .mst_req_o           ( xbar_slv_req[0]         ),
       .mst_resp_i          ( xbar_slv_resp[0]        ),
       ...
     );
     ```
2. Direct observation of `bus_monitors/axi_lite_timeout_monitor.sv` (lines 4-26, 85-120):
   - When a transaction exceeds `TimeoutApb` (131,072 cycles) or `TimeoutDefault` (64 cycles), `axi_lite_timeout_monitor` directly replies to the core (`slv_resp_o` / `core_axi_resp`) with `SLVERR` and data `32'hDEAD_DEAD`.
   - Concurrently, it holds `mst_req_o` (`xbar_slv_req[0]`) asserted until the crossbar accepts it, and then swallows the orphan response with internal `b_ready`/`r_ready` high.
   - In `Verification/infrastructure/tb/rf_mon_probe.sv` (lines 18-27):
     ```systemverilog
     // This module flattens the CORE-side copy (dut.core_axi_req/resp, i.e.
     // the core <-> axi_lite_timeout_monitor boundary) onto the interface.
     ```

### 1.4 APB 6-Slot Mapping and GPIO 2 KB Window
1. Direct observation of `riscforge_soc_subsystem.sv` lines 683-690:
   ```systemverilog
   assign apb_addr_map[0] = '{idx: 32'd0, start_addr: 32'h4000_0000, end_addr: 32'h4000_1000}; // I2C (4 KB)
   assign apb_addr_map[1] = '{idx: 32'd1, start_addr: 32'h4000_1000, end_addr: 32'h4000_2000}; // Timer 0 (4 KB)
   assign apb_addr_map[2] = '{idx: 32'd2, start_addr: 32'h4000_2000, end_addr: 32'h4000_3000}; // UART (4 KB)
   // GPIO: 2 KB. The register block decodes only 11 address bits, so mapping the
   // full 4 KB would alias 0x4000_3800-0x4000_3FFF onto the real registers.
   assign apb_addr_map[3] = '{idx: 32'd3, start_addr: 32'h4000_3000, end_addr: 32'h4000_3800}; // GPIO (2 KB)
   assign apb_addr_map[4] = '{idx: 32'd4, start_addr: 32'h4000_4000, end_addr: 32'h4000_5000}; // SPI Master (4 KB)
   assign apb_addr_map[5] = '{idx: 32'd5, start_addr: 32'h4000_5000, end_addr: 32'h4000_6000}; // Timer 1 (4 KB)
   ```
2. Unmapped Gap:
   - Address range `0x4000_3800` to `0x4000_3FFF` (2 KB) does not match any APB rule.
   - `axi_lite_to_apb.sv` generates `DECERR` on unmapped access.
   - `PROJECT.md` Feature 37 (Stage 4 Proof) specifically injects access to `0x4000_3800` to prove `DECERR` generation and Load Access Fault trapping.
3. Bug in `Verification/infrastructure/checkers/mmio_path_scoreboard.sv` line 35:
   ```systemverilog
   if ((addr >= 32'h4000_3000) && (addr < 32'h4000_4000)) return 3; // GPIO
   ```
   `mmio_path_scoreboard.sv` treats the entire 4 KB block `0x4000_3000` - `0x4000_4000` as GPIO Slot 3. If an access touches `0x4000_3800`, hardware generates DECERR (no PSEL), but `mmio_path_scoreboard.sv` flags a false mismatch (`expected slot 3`).
4. In `Verification/infrastructure/tb/tb_pkg.sv` (lines 83-112):
   - `apb_slot_size_log2(slot)` returns 11 for GPIO, 12 for all others.
   - `get_expected_apb_slot(32'h4000_3800)` returns `RF_APB_NONE` (6).

### 1.5 64-Entry Circular Ring Buffer & Freeze Input
1. Standalone buffer:
   - Fixed capacity `RING_BUFFER_DEPTH = 64`.
   - Modulo pointer advance: `head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH`.
   - Freezing: `freeze` (active-high synchronous) prevents writes and pointer increments: `if (!freeze) begin ... end`.
2. Class-based buffer (`tb_pkg::rf_ring_base` lines 613-709):
   - Implements bounded dynamic queue `m_mem[$]` capped at `DEPTH` (default 256 or 64).
   - On full, pops oldest element: `void'(m_mem.pop_front()); m_mem.push_back(t);`.
   - Supports newest-first dumps, search by timestamp, and freezing via `m_frozen_at`.

---

## 2. Logic Chain

1. **Interface Mismatch**:
   - `riscforge_soc_subsystem` has strictly packed struct ports (`core_axi_req`, `core_axi_resp`, `apb_req`, `apb_resp`).
   - `axi_lite_monitor.sv` and `apb_monitor.sv` expose flat discrete ports.
   - `soc_tb_top.sv` currently tries to connect to non-existent internal wires (`dut.m0_awaddr`, `dut.apb_paddr`).
   - **Inference**: Testbench elaboration in Vivado XSim and VCS will immediately fail with unresolved hierarchical reference errors unless either:
     - (A) `soc_tb_top.sv` creates explicit continuous unpack assignments from `dut.core_axi_req.*` and `dut.apb_req[i].*` into the module monitors, OR
     - (B) The probe module `rf_mon_probe.sv` is utilized, which already cleanly flattens these structs onto `rf_axil_if` and `rf_apb_if` and binds to the class-based monitors (`rf_axil_monitor`, `rf_apb_monitor`).

2. **Probe Tap Selection**:
   - Probing `core_axi_req` / `core_axi_resp` (upstream of timeout monitor) observes transactions directly from the CPU core's perspective, including any synthetic `SLVERR` injected on timeout.
   - Probing `xbar_slv_req[0]` / `xbar_slv_resp[0]` (downstream of timeout monitor) observes transactions entering the crossbar, including post-timeout drain cycles, but misses the timely error delivery to the core.
   - **Inference**: For verifying core execution, CPU LSU tracking, protocol SVAs, and MMIO scoreboard path validation, `core_axi_req` / `core_axi_resp` is the single source of truth.

3. **Decode Boundary for GPIO and Fault Injection**:
   - Hardware address map in `riscforge_soc_subsystem.sv` gives GPIO only 2 KB (`0x4000_3000` to `0x4000_37FF`).
   - `mmio_path_scoreboard.sv` incorrectly grants 4 KB (`0x4000_3000` to `0x4000_3FFF`) to GPIO.
   - When Stage 4 Proof runs fault injection against `0x4000_3800`, hardware returns DECERR with no PSEL asserted.
   - **Inference**: `mmio_path_scoreboard.sv` will report a false assertion failure (`[SCOREBOARD-PATH-01]`) during Stage 4 unless line 35 is corrected to `(addr >= 32'h4000_3000) && (addr < 32'h4000_3800)`.

4. **Race Conditions and Structural Bugs in `axi_lite_monitor.sv` and `apb_monitor.sv`**:
   - If both write response (B) and read response (R) complete in the same clock cycle, `axi_lite_monitor.sv` executes conflicting non-blocking writes to `head_ptr`.
   - Single-cycle write responses cause `latched_awaddr` to be read before its non-blocking update has completed, capturing corrupt addresses in the ring buffer.
   - `apb_monitor.sv` uses unpacked port arrays (`prdata [0:NUM_SLOTS-1]`), violating Vivado XSim boundary requirements.
   - `apb_monitor.sv` lacks `pstrb` input, preventing byte-strobe verification.
   - Neither module monitor populates full `axi_txn_t` / `apb_txn_t` metadata (latencies, slot decode, MMIO flags).
   - **Inference**: For the standalone modules to function reliably without crashing simulators or corrupting trace history, they must be hardened to eliminate pointer races, support single-cycle completion, use packed vectors for `prdata`, add `pstrb`, and fully populate transaction records.

---

## 3. Caveats

1. **Dual Architecture Coexistence**:
   The repository contains two monitor frameworks:
   - Module-level standalone monitors (`axi_lite_monitor.sv`, `apb_monitor.sv`, etc.) instantiated in `soc_tb_top.sv`.
   - Interface/class-based monitor framework (`rf_monitor_if.sv`, `rf_monitors.sv`, `rf_mon_probe.sv`, `tb_pkg.sv`) validated in `rf_mon_smoke_tb.sv`.
   Both are compiled in `soc_verification.f`. If the project standardizes on the module-level monitors in `soc_tb_top.sv`, both module-level monitors and class monitors must be kept logically consistent.
2. **Bootloader Traffic Observability**:
   `core_axi_req` only observes traffic from the CPU. Bootloader SPI flash reads and ISRAM/DSRAM preloading pass through `xbar_slv_req[1]`. If bootloader AXI transactions need to be monitored in future milestones, a second AXI monitor instance must be tapped to `xbar_slv_req[1]`.
3. **Vivado XSim Clocking Block Quirk**:
   As documented in `rf_monitor_if.sv:375-381`, Vivado XSim 2022.2 returns `X` for `pstrb` and `prdata_flat` if read through clocking block `mon_cb`. Reading them directly off the interface or from raw module ports is required for XSim compatibility.

---

## 4. Conclusion & Complete Implementation Plan for Worker

### 4.1 Plan Summary
To deliver rock-solid, non-intrusive AXI4-Lite and APB 6-slot monitors with 64-entry freeze buffers compatible with both Vivado XSim and VCS/Xcelium, the Worker should execute the following 4 tasks:

---

### Task 1: Harden `axi_lite_monitor.sv`
**Target File**: `Verification/infrastructure/monitors/axi_lite_monitor.sv`

1. **Resolve Pointer Race & Dual Completion**:
   Calculate pointer increments combinationally before applying non-blocking updates:
   ```systemverilog
   logic b_fire, r_fire;
   assign b_fire = bvalid && bready && !freeze;
   assign r_fire = rvalid && rready && !freeze;

   always @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       head_ptr <= 0;
       ...
     end else begin
       cycle_cnt <= cycle_cnt + 1;
       ...
       case ({b_fire, r_fire})
         2'b10: head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
         2'b01: head_ptr <= (head_ptr + 1) % RING_BUFFER_DEPTH;
         2'b11: head_ptr <= (head_ptr + 2) % RING_BUFFER_DEPTH;
         default: ;
       endcase
     end
   end
   ```
2. **Fix Single-Cycle Handshake Latching**:
   For transactions where AW/W and B (or AR and R) complete in the same clock cycle, use the incoming port value directly rather than the registered latch:
   ```systemverilog
   logic [31:0] eff_awaddr;
   logic [31:0] eff_wdata;
   logic [3:0]  eff_wstrb;
   logic [31:0] eff_araddr;

   assign eff_awaddr = (awvalid && awready) ? awaddr : latched_awaddr;
   assign eff_wdata  = (wvalid  && wready)  ? wdata  : latched_wdata;
   assign eff_wstrb  = (wvalid  && wready)  ? wstrb  : latched_wstrb;
   assign eff_araddr = (arvalid && arready) ? araddr : latched_araddr;
   ```
3. **Populate Full `axi_txn_t` Fields**:
   Populate `rel_cycle`, `seq`, `prot`, `aw_wait`, `w_wait`, `b_wait`, `is_mmio`, `apb_slot`, and `decoded`:
   ```systemverilog
   ring_buffer[wr_idx].timestamp <= cycle_cnt;
   ring_buffer[wr_idx].rel_cycle <= cycle_cnt;
   ring_buffer[wr_idx].seq       <= total_axi_writes + total_axi_reads;
   ring_buffer[wr_idx].addr      <= eff_awaddr;
   ring_buffer[wr_idx].data      <= eff_wdata;
   ring_buffer[wr_idx].strb      <= eff_wstrb;
   ring_buffer[wr_idx].resp      <= bresp;
   ring_buffer[wr_idx].is_write  <= 1'b1;
   ring_buffer[wr_idx].prot      <= awprot;
   ring_buffer[wr_idx].is_mmio   <= is_mmio_addr(eff_awaddr);
   ring_buffer[wr_idx].apb_slot  <= get_expected_apb_slot(eff_awaddr);
   ring_buffer[wr_idx].decoded   <= (get_expected_apb_slot(eff_awaddr) != RF_APB_NONE);
   ```

---

### Task 2: Harden `apb_monitor.sv`
**Target File**: `Verification/infrastructure/monitors/apb_monitor.sv`

1. **Port Updates**:
   - Add `input logic [3:0] pstrb` input port.
   - Replace unpacked array `input logic [31:0] prdata [0:NUM_SLOTS-1]` with packed 1D bus:
     `input logic [NUM_SLOTS*32-1:0] prdata_flat` (or support both / slice `prdata_flat[i*32 +: 32]`) for guaranteed XSim elaboration stability.
2. **Wait State & Timing Tracking**:
   Track setup, access, and wait-state duration per slot:
   ```systemverilog
   logic [31:0] ws_cnt [0:NUM_SLOTS-1];
   always @(posedge clk or negedge rst_n) begin
     if (!rst_n) begin
       for (int s = 0; s < NUM_SLOTS; s++) ws_cnt[s] <= 0;
     end else begin
       for (int s = 0; s < NUM_SLOTS; s++) begin
         if (psel[s] && penable && !pready[s]) ws_cnt[s] <= ws_cnt[s] + 1;
         else if (psel[s] && penable && pready[s]) ws_cnt[s] <= 0;
       end
     end
   end
   ```
3. **Populate Full `apb_txn_t` Fields**:
   Record `pstrb`, `wait_states`, `setup_cycle`, `access_cycle`, and `addr_match`:
   ```systemverilog
   ring_buffer[head_ptr].timestamp   <= cycle_cnt;
   ring_buffer[head_ptr].rel_cycle   <= cycle_cnt;
   ring_buffer[head_ptr].seq         <= total_apb_trans;
   ring_buffer[head_ptr].slot        <= i;
   ring_buffer[head_ptr].paddr       <= paddr;
   ring_buffer[head_ptr].pwdata      <= pwdata;
   ring_buffer[head_ptr].prdata      <= prdata_flat[i*32 +: 32];
   ring_buffer[head_ptr].pstrb       <= pstrb;
   ring_buffer[head_ptr].pwrite      <= pwrite;
   ring_buffer[head_ptr].pready      <= 1'b1;
   ring_buffer[head_ptr].pslverr     <= pslverr[i];
   ring_buffer[head_ptr].wait_states <= ws_cnt[i];
   ring_buffer[head_ptr].addr_match  <= apb_slot_base(i);
   ```

---

### Task 3: Fix Bug in `mmio_path_scoreboard.sv`
**Target File**: `Verification/infrastructure/checkers/mmio_path_scoreboard.sv`

**Problem**: Line 35 gives GPIO 4 KB (`0x4000_3000` to `0x4000_4000`), whereas hardware decodes 2 KB (`0x4000_3000` to `0x4000_3800`), leaving `0x4000_3800`-`0x4000_3FFF` unmapped.

**Code Change**:
```systemverilog
// Before (Line 35):
if ((addr >= 32'h4000_3000) && (addr < 32'h4000_4000)) return 3; // GPIO

// After:
if ((addr >= 32'h4000_3000) && (addr < 32'h4000_3800)) return 3; // GPIO (2 KB)
// 0x4000_3800 - 0x4000_3FFF is an unmapped hole, returns -1
```

---

### Task 4: Fix Struct Tap Connections in `soc_tb_top.sv`
**Target File**: `Verification/infrastructure/tb/soc_tb_top.sv`

**Problem**: Lines 218-251 connect to non-existent nets `dut.m0_*` and `dut.apb_*`.

**Recommendation**:
Flatten `dut.core_axi_req` / `dut.core_axi_resp` and `dut.apb_req` / `dut.apb_resp` via continuous assignments:
```systemverilog
  // AXI-Lite Unpack from core_axi_req / core_axi_resp
  wire [31:0] mon_awaddr  = dut.core_axi_req.aw.addr;
  wire [2:0]  mon_awprot  = dut.core_axi_req.aw.prot;
  wire        mon_awvalid = dut.core_axi_req.aw_valid;
  wire        mon_awready = dut.core_axi_resp.aw_ready;
  wire [31:0] mon_wdata   = dut.core_axi_req.w.data;
  wire [3:0]  mon_wstrb   = dut.core_axi_req.w.strb;
  wire        mon_wvalid  = dut.core_axi_req.w_valid;
  wire        mon_wready  = dut.core_axi_resp.w_ready;
  wire [1:0]  mon_bresp   = dut.core_axi_resp.b.resp;
  wire        mon_bvalid  = dut.core_axi_resp.b_valid;
  wire        mon_bready  = dut.core_axi_req.b_ready;
  wire [31:0] mon_araddr  = dut.core_axi_req.ar.addr;
  wire [2:0]  mon_arprot  = dut.core_axi_req.ar.prot;
  wire        mon_arvalid = dut.core_axi_req.ar_valid;
  wire        mon_arready = dut.core_axi_resp.ar_ready;
  wire [31:0] mon_rdata   = dut.core_axi_resp.r.data;
  wire [1:0]  mon_rresp   = dut.core_axi_resp.r.resp;
  wire        mon_rvalid  = dut.core_axi_resp.r_valid;
  wire        mon_rready  = dut.core_axi_req.r_ready;

  // APB Unpack from apb_req / apb_resp
  wire [31:0] mon_paddr   = dut.apb_req[0].paddr;
  wire        mon_penable = dut.apb_req[0].penable;
  wire        mon_pwrite  = dut.apb_req[0].pwrite;
  wire [31:0] mon_pwdata  = dut.apb_req[0].pwdata;
  wire [3:0]  mon_pstrb   = dut.apb_req[0].pstrb;
  wire [5:0]  mon_psel;
  wire [5:0]  mon_pready;
  wire [5:0]  mon_pslverr;
  wire [5*32+31:0] mon_prdata_flat;

  genvar s_idx;
  generate
    for (s_idx = 0; s_idx < 6; s_idx++) begin : gen_apb_mon_unpack
      assign mon_psel[s_idx]                       = dut.apb_req[s_idx].psel;
      assign mon_pready[s_idx]                     = dut.apb_resp[s_idx].pready;
      assign mon_pslverr[s_idx]                    = dut.apb_resp[s_idx].pslverr;
      assign mon_prdata_flat[s_idx*32 +: 32]       = dut.apb_resp[s_idx].prdata;
    end
  endgenerate
```
And instantiate `axi_lite_monitor` and `apb_monitor` with these unpacked wires.

---

## 5. Verification Method

### 5.1 Verification Commands
1. **Monitor Smoke Test (Vivado XSim)**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   .\run_rf_mon_smoke.ps1
   ```
   **Pass Condition**: Zero compilation errors, all 6 monitor self-tests pass (`[SMOKE] pass M4.axil`, `[SMOKE] pass M5.apb`), post-mortem dump written to `monitor_postmortem.txt`.

2. **Full SoC Compilation Check (Vivado XSim)**:
   ```powershell
   cd "c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\Verification\infrastructure"
   xvlog --sv -prj soc_verification.prj
   xelab soc_tb_top -s soc_sim -debug typical
   ```
   **Pass Condition**: Clean elaboration with zero missing symbol/net errors.

3. **VCS / Xcelium Remote Syntax & Elaboration Check**:
   ```bash
   vcs -sverilog -f soc_verification.f -top soc_tb_top
   ```

### 5.2 Invalidation Conditions
This report's recommendations would be invalidated if:
1. `riscforge_soc_subsystem.sv` re-introduces flat AXI/APB signals into its module port list.
2. The address decode for GPIO in `riscforge_soc_subsystem.sv` is expanded from 2 KB to 4 KB.
3. The crossbar is modified to eliminate `axi_lite_timeout_monitor`.
