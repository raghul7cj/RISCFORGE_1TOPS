# RISC-V 5-Stage Processor - Module Hierarchy & Data Flow Documentation

## 📊 Architecture Overview

The RISCFORGE 5-stage RISC-V processor follows a classic pipeline architecture with:
- **5 Pipeline Stages:** IF → ID → EX → MEM → WB
- **Forwarding Unit:** Data forwarding from MEM and WB stages
- **Hazard Controller:** Stall and flush generation for pipeline integrity
- **3 Memory Subsystems:** Instruction Memory (IMEM), Data Memory (DMEM), Register File (RF)

---

## 🎯 Top-Level Module Hierarchy

```
top.v (RISC-V 5-Stage Processor)
├── fetch_cycle.v (IF Stage)
│   ├── Mux2 (NextPC selection multiplexer)
│   ├── PC (Program counter register)
│   ├── Instruction_Memory (IMEM: 1024x32 ROM)
│   └── PC_Adder (PC + 4 computation)
│
├── decode_cycle.v (ID Stage)
│   ├── Control_Unit_Top
│   │   ├── Main_Decoder (opcode-level decoding)
│   │   ├── ALU_Decoder (ALU operation selection)
│   │   └── opcode_check (legal instruction validation)
│   ├── Register_File (32x32 register array)
│   └── Sign_Extend (immediate generator)
│
├── execute_cycle.v (EX Stage)
│   ├── Mux_3_by_1 (ForwardA multiplexer)
│   ├── Mux_3_by_1 (ForwardB multiplexer)
│   ├── Mux2 (ALU source B selection)
│   ├── ALU (32-bit arithmetic/logic unit)
│   ├── JB_unit (branch/jump decision logic)
│   └── PC_Adder (branch target calculation)
│
├── memory_cycle.v (MEM Stage)
│   ├── ls_unit (load/store alignment unit)
│   └── Data_Memory (DMEM: 1024x32 RAM)
│
├── writeback_cycle.v (WB Stage)
│   └── Result Mux (combinational result selection)
│
└── hazard_unit.v (Hazard & Forwarding Control)
    ├── Forwarding logic (ForwardAE, ForwardBE)
    ├── Stall logic (StallF, StallD)
    └── Flush logic (FlushE, FlushD)
```

---

## 🔌 Detailed Interface Mapping

### **1. FETCH STAGE (IF) - fetch_cycle.v**

#### Inputs:
| Port | Width | Source | Description |
|------|-------|--------|-------------|
| `clk` | 1 | Global | System clock (posedge) |
| `rst` | 1 | Global | Active-low reset |
| `PCSrcE` | 1 | hazard_unit | Branch/jump taken signal |
| `PCTargetE` | 32 | execute_cycle | Branch/jump target address |
| `StallF` | 1 | hazard_unit | Stall fetch stage (freeze PC) |
| `StallD` | 1 | hazard_unit | Stall decode stage (freeze IF/ID reg) |
| `FlushD` | 1 | hazard_unit | Flush decode stage (branch taken) |

#### Outputs:
| Port | Width | Destination | Description |
|------|-------|-------------|-------------|
| `InstrD` | 32 | decode_cycle | Instruction to decode |
| `PCD` | 32 | decode_cycle | Program counter (before +4) |
| `PCPlus4D` | 32 | decode_cycle | PC + 4 value |

#### Internal Modules:
```verilog
Mux2 PC_Mux:
  Input:  a=PCPlus4F[31:0], b=PCTargetE[31:0], s=PCSrcE
  Output: c=PC_F[31:0]
  Purpose: Select next PC (sequential or branch target)

PC program_counter:
  Input:  clk, rst, PC_Next=PC_F[31:0], StallF
  Output: PC=PCF[31:0]
  Purpose: Store and manage PC register

Instruction_Memory IMEM:
  Input:  A[31:2]=PCF[31:2], rst
  Output: RD[31:0]=InstrF
  Purpose: Fetch instruction from memory

PC_Adder PC_adder:
  Input:  a=PCF[31:0], b=32'h4
  Output: c=PCPlus4F[31:0]
  Purpose: Compute PC + 4
```

#### Data Flow:
```
PC_Mux → PC (next PC)
PC → IMEM (address), PC_Adder (operand)
IMEM → IF regfile (instruction)
PC_Adder → IF regfile (PC+4)
```

---

### **2. DECODE STAGE (ID) - decode_cycle.v**

#### Inputs:
| Port | Width | Source | Description |
|------|-------|--------|-------------|
| `clk` | 1 | Global | System clock |
| `rst` | 1 | Global | Active-low reset |
| `InstrD` | 32 | fetch_cycle | Instruction from IF |
| `PCD` | 32 | fetch_cycle | PC value from IF |
| `PCPlus4D` | 32 | fetch_cycle | PC+4 from IF |
| `RegWriteW` | 1 | memory_cycle | Write-back stage write enable |
| `RDW` | 5 | memory_cycle | Write-back destination register |
| `ResultW` | 32 | writeback_cycle | Write-back data result |
| `FlushE` | 1 | hazard_unit | Flush execute stage |

#### Outputs:
| Port | Width | Destination | Description |
|------|-------|-------------|-------------|
| **Control Signals:** | | | |
| `RegWriteE` | 1 | execute_cycle | Register write enable |
| `ALUSrcE` | 1 | execute_cycle | ALU source B: 0=register, 1=immediate |
| `MemWriteE` | 1 | execute_cycle | Data memory write enable |
| `ResultSrcE` | 2 | execute_cycle | Write-back mux select (00=ALU, 01=Load, 10=PC+4) |
| `ALUControlE` | 4 | execute_cycle | ALU operation code |
| `BranchE` | 4 | execute_cycle | Branch control (B[3:0]) |
| `JumpE` | 2 | execute_cycle | Jump control (J[1:0]) |
| `lsunitE` | 5 | execute_cycle | Load/store control bus |
| `LUISrcE` | 1 | execute_cycle | LUI/AUIPC distinction |
| `isLUIE` | 1 | execute_cycle | U-type instruction flag |
| **Data Signals:** | | | |
| `RD1_E` | 32 | execute_cycle | Register read port 1 data |
| `RD2_E` | 32 | execute_cycle | Register read port 2 data |
| `Imm_Ext_E` | 32 | execute_cycle | Sign-extended immediate |
| `RD_E` | 5 | execute_cycle | Destination register |
| `PCE` | 32 | execute_cycle | PC forwarded to EX |
| `PCPlus4E` | 32 | execute_cycle | PC+4 forwarded to EX |
| `RS1_E` | 5 | hazard_unit | Source register 1 address |
| `RS2_E` | 5 | hazard_unit | Source register 2 address |
| `RS1_D` | 5 | hazard_unit | Source register 1 (decode) |
| `RS2_D` | 5 | hazard_unit | Source register 2 (decode) |
| `illegal_instr` | 1 | hazard_unit | Illegal instruction flag |

#### Internal Modules:
```verilog
Control_Unit_Top control:
  Input:  Op[6:0]=InstrD[6:0], funct3[2:0]=InstrD[14:12], funct7_30=InstrD[30]
  Output: RegWrite, ImmSrc[1:0], ALUSrc, MemWrite, ResultSrc[1:0],
          Branch[3:0], Jump[1:0], lsunit[4:0], ALUControl[3:0],
          LUISrcE, isLUIE, illegal_instr
  Purpose: Decode instruction to control signals

Register_File rf:
  Input:  WE3=RegWriteW, WD3[31:0]=ResultW,
          A1[4:0]=InstrD[19:15], A2[4:0]=InstrD[24:20], A3[4:0]=RDW
  Output: RD1[31:0], RD2[31:0]
  Purpose: Register file read/write with forwarding

Sign_Extend extension:
  Input:  In[31:0]=InstrD, ImmSrc[1:0], LUI
  Output: Imm_Ext[31:0]
  Purpose: Generate signed/zero-extended immediates
```

#### Instruction Field Extraction:
```verilog
RS1_D = InstrD[19:15]     // Source register 1
RS2_D = InstrD[24:20]     // Source register 2
RD_D  = InstrD[11:7]      // Destination register (in ID/EX register)
```

#### Data Flow:
```
InstrD → Control Unit, RS1/RS2 extraction, Imm Gen
Control Unit → control signals to ID/EX register
RS1/RS2 → Register File
Register File → RD1_E, RD2_E to ID/EX register
Imm Gen → Imm_Ext_E to ID/EX register
```

---

### **3. EXECUTE STAGE (EX) - execute_cycle.v**

#### Inputs:
| Port | Width | Source | Description |
|------|-------|--------|-------------|
| **Control:** | | | |
| `clk` | 1 | Global | System clock |
| `rst` | 1 | Global | Active-low reset |
| `RegWriteE` | 1 | decode_cycle | Register write control |
| `ALUSrcE` | 1 | decode_cycle | ALU operand B source |
| `MemWriteE` | 1 | decode_cycle | Memory write signal |
| `ResultSrcE` | 2 | decode_cycle | Write-back mux select |
| `ALUControlE` | 4 | decode_cycle | ALU operation code |
| `BranchE` | 4 | decode_cycle | Branch condition spec |
| `JumpE` | 2 | decode_cycle | Jump type indicator |
| `lsunitE` | 5 | decode_cycle | Load/store control |
| `LUISrcE` | 1 | decode_cycle | LUI/AUIPC selector |
| `isLUIE` | 1 | decode_cycle | U-type instruction flag |
| **Data:** | | | |
| `RD1_E` | 32 | decode_cycle | Register read data 1 |
| `RD2_E` | 32 | decode_cycle | Register read data 2 |
| `Imm_Ext_E` | 32 | decode_cycle | Immediate value |
| `RD_E` | 5 | decode_cycle | Destination register |
| `PCE` | 32 | decode_cycle | Program counter |
| `PCPlus4E` | 32 | decode_cycle | PC + 4 |
| **Forwarding:** | | | |
| `ForwardA_E` | 2 | hazard_unit | Forward select for operand A |
| `ForwardB_E` | 2 | hazard_unit | Forward select for operand B |
| `ResultW` | 32 | writeback_cycle | WB stage result (for forwarding) |
| `ALU_ResultM` | 32 | memory_cycle | MEM stage result (for forwarding) |

#### Outputs:
| Port | Width | Destination | Description |
|------|-------|-------------|-------------|
| **Branch Control:** | | | |
| `PCSrcE` | 1 | fetch_cycle | Branch/jump taken signal |
| `PCTargetE` | 32 | fetch_cycle | Branch/jump target address |
| **To MEM Stage:** | | | |
| `RegWriteM` | 1 | memory_cycle | Register write enable |
| `MemWriteM` | 1 | memory_cycle | Memory write enable |
| `ResultSrcM` | 2 | memory_cycle | Write-back mux select |
| `RD_M` | 5 | memory_cycle | Destination register |
| `lsunitM` | 5 | memory_cycle | Load/store control |
| `PCPlus4M` | 32 | memory_cycle | PC + 4 value |
| `WriteDataM` | 32 | memory_cycle | Store data (aligned in this stage) |
| `ALU_ResultM` | 32 | memory_cycle | ALU result / effective address |

#### Internal Modules:
```verilog
Mux_3_by_1 srca_mux:
  Input:  a=RD1_E, b=ResultW, c=ALU_ResultM, s=ForwardA_E[1:0]
  Output: d=Src_A[31:0]
  Purpose: Forward ALU source A operand

Mux_3_by_1 srcb_mux:
  Input:  a=RD2_E, b=ResultW, c=ALU_ResultM, s=ForwardB_E[1:0]
  Output: d=Src_B_interim[31:0]
  Purpose: Forward ALU source B operand

Mux2 alu_src_mux:
  Input:  a=Src_B_interim, b=Imm_Ext_E, s=ALUSrcE
  Output: c=Src_B[31:0]
  Purpose: Select ALU operand B (register or immediate)

ALU alu_instance:
  Input:  A[31:0]=Src_A, B[31:0]=Src_B, ALUControl[3:0]
  Output: Result[31:0], Zero
  Purpose: Perform arithmetic/logic/shift operations

PC_Adder branch_adder:
  Input:  a=PCE, b=Imm_Ext_E
  Output: c=PCTarget_jb[31:0]
  Purpose: Calculate branch target

JB_unit JB:
  Input:  Zero, J[1:0]=JumpE, B[3:0]=BranchE
  Output: yes (PCSrcE), JALR
  Purpose: Determine if branch/jump should be taken
```

#### ALU Operation Codes:
```verilog
0000: ADD    (A + B)
0001: SUB    (A - B)
0100: AND    (A & B)
0101: OR     (A | B)
0110: JALR   ((A+B) & ~1)  // Clear LSB for address alignment
0111: XOR    (A ^ B)
1000: SLL    (A << B[4:0])
1001: SRL    (A >> B[4:0])
1010: SRA    (A >>> B[4:0])  // Arithmetic shift
1100: SLTU   (A < B)  // Unsigned
1111: SLT    (A < B)  // Signed
```

#### Data Flow:
```
RD1_E, RD2_E → Forwarding Muxes
Forwarding Muxes → ALU inputs
Imm_Ext_E → ALU operand selector
ResultW, ALU_ResultM → Forwarding Mux inputs
PC, Imm_Ext_E → Branch target adder
ALU output → EX/MEM register, Back to hazard unit
Zero flag → JB_unit
```

---

### **4. MEMORY STAGE (MEM) - memory_cycle.v**

#### Inputs:
| Port | Width | Source | Description |
|------|-------|--------|-------------|
| `clk` | 1 | Global | System clock |
| `rst` | 1 | Global | Active-low reset |
| `RegWriteM` | 1 | execute_cycle | Register write enable |
| `MemWriteM` | 1 | execute_cycle | Data memory write enable |
| `ResultSrcM` | 2 | execute_cycle | Write-back mux select |
| `RD_M` | 5 | execute_cycle | Destination register |
| `lsunitM` | 5 | execute_cycle | Load/store control bus |
| `PCPlus4M` | 32 | execute_cycle | PC + 4 value |
| `WriteDataM` | 32 | execute_cycle | Store data (pre-aligned) |
| `ALU_ResultM` | 32 | execute_cycle | Address or ALU result |

#### Outputs:
| Port | Width | Destination | Description |
|------|-------|-------------|-------------|
| `RegWriteW` | 1 | writeback_cycle | Register write enable |
| `ResultSrcW` | 2 | writeback_cycle | Write-back mux select |
| `RD_W` | 5 | writeback_cycle | Destination register |
| `PCPlus4W` | 32 | writeback_cycle | PC + 4 value |
| `ALU_ResultW` | 32 | writeback_cycle | ALU result pass-through |
| `ReadDataW` | 32 | writeback_cycle | Load data (formatted) |

#### Internal Modules:
```verilog
ls_unit lsunit:
  Input:  in[31:0]=ReadDataM (from DMEM),
          in_s[31:0]=WriteDataM (store data),
          address[1:0]=ALU_ResultM[1:0],
          lsunit[4:0]
  Output: out[31:0] (formatted load),
          out_s[31:0] (aligned store),
          strobe[3:0] (byte enables)
  Purpose: Align and format load/store data

Data_Memory DMEM:
  Input:  clk, rst, WE=MemWriteM,
          WD[31:0] (write data from ls_unit),
          A[29:0]=ALU_ResultM[29:0],
          WSTRB[3:0] (from ls_unit)
  Output: RD[31:0]
  Purpose: Synchronous RAM for data storage
```

#### Load/Store Bus Encoding (lsunit):
```verilog
lsunit[4]   : Load/Store enable flag
lsunit[3]   : Opcode bit [5] (0=load, 1=store)
lsunit[2:0] : funct3 field

Encoding:
  lsunit[4:3]=2'b10 → LOAD  (funct3 determines width)
  lsunit[4:3]=2'b11 → STORE (funct3 determines width)
  
funct3 values:
  000: Byte (LB/SB)
  001: Half-word (LH/SH)
  010: Word (LW/SW)
  100: Byte unsigned (LBU)
  101: Half-word unsigned (LHU)
```

#### Data Flow:
```
ALU_ResultM → DMEM address, LSU address input
WriteDataM → LSU input
LSU → Strobe to DMEM, Aligned store data to DMEM
DMEM read → LSU for formatting
LSU output → ReadDataW
```

---

### **5. WRITE-BACK STAGE (WB) - writeback_cycle.v**

#### Inputs:
| Port | Width | Source | Description |
|------|-------|--------|-------------|
| `ResultSrcW` | 2 | memory_cycle | Write-back mux select |
| `PCPlus4W` | 32 | memory_cycle | PC + 4 value |
| `ALU_ResultW` | 32 | memory_cycle | ALU result |
| `ReadDataW` | 32 | memory_cycle | Load data |

#### Outputs:
| Port | Width | Destination | Description |
|------|-------|-------------|-------------|
| `ResultW` | 32 | register_file (decode) | Final result to register file |
| `ResultW` | 32 | hazard_unit forwarding | Forwarding path to EX stage |

#### Result Selection (Combinational Mux):
```verilog
ResultW = (ResultSrcW == 2'b00) ? ALU_ResultW :       // ALU result
          (ResultSrcW == 2'b01) ? ReadDataW :         // Load data
          (ResultSrcW == 2'b10) ? PCPlus4W : ALU_ResultW;
```

#### Data Flow:
```
ResultSrcW, ALU_ResultW, ReadDataW, PCPlus4W → Result Mux
Result Mux → ResultW
ResultW → Register File (write port), Back to forwarding muxes
```

---

### **6. HAZARD & FORWARDING UNIT (hazard_unit.v)**

#### Inputs:
| Port | Width | Source | Description |
|------|-------|--------|-------------|
| `rst` | 1 | Global | Active-low reset |
| **Register Write Status:** | | | |
| `RegWriteM` | 1 | execute_cycle | MEM stage write enable |
| `RegWriteW` | 1 | memory_cycle | WB stage write enable |
| **Destination Registers:** | | | |
| `RD_M` | 5 | execute_cycle | MEM destination register |
| `RD_W` | 5 | memory_cycle | WB destination register |
| **Source Registers (EX):** | | | |
| `Rs1_E` | 5 | decode_cycle | EX source register 1 |
| `Rs2_E` | 5 | decode_cycle | EX source register 2 |
| **Source Registers (ID):** | | | |
| `Rs1_D` | 5 | decode_cycle | ID source register 1 |
| `Rs2_D` | 5 | decode_cycle | ID source register 2 |
| **Destination Register (EX):** | | | |
| `RdE` | 5 | decode_cycle | EX destination register |
| **Control Status:** | | | |
| `ResultSrcE` | 2 | decode_cycle | EX write-back source (00/01 vs 10/11) |
| `PCSrcE` | 1 | execute_cycle | Branch/jump taken signal |
| `illegal_instr` | 1 | decode_cycle | Illegal instruction detected |

#### Outputs:
| Port | Width | Destination | Description |
|------|-------|-------------|-------------|
| **Forwarding Selects:** | | | |
| `ForwardAE` | 2 | execute_cycle | ALU operand A forward select |
| `ForwardBE` | 2 | execute_cycle | ALU operand B forward select |
| **Stall Signals:** | | | |
| `StallF` | 1 | fetch_cycle | Stall fetch stage |
| `StallD` | 1 | fetch_cycle | Stall decode stage |
| **Flush Signals:** | | | |
| `FlushE` | 1 | decode_cycle | Flush execute stage |
| `FlushD` | 1 | fetch_cycle | Flush decode stage |

#### Forwarding Logic:
```verilog
// ForwardA and ForwardB encoding:
00: No forwarding (use original register)
01: Forward from WB stage (ResultW)
10: Forward from MEM stage (ALU_ResultM)

// Forwarding condition for source A:
if (RegWriteM && Rs1_E != 5'd0 && RD_M == Rs1_E)
  ForwardAE = 2'b10;  // Forward from MEM
else if (RegWriteW && Rs1_E != 5'd0 && RD_W == Rs1_E)
  ForwardAE = 2'b01;  // Forward from WB
else
  ForwardAE = 2'b00;  // No forwarding

// Same logic applies to ForwardB with Rs2_E
```

#### Stall/Flush Logic:
```verilog
// Load-use hazard detection:
if (ResultSrcE == 2'b01 &&  // EX inst is a load
    (Rs1_D == RdE || Rs2_D == RdE))  // ID uses loaded value
  StallD = 1'b1, StallF = 1'b1;  // Stall ID and IF

// Branch/Jump flushing:
if (PCSrcE)  // Branch or jump taken
  FlushE = 1'b1, FlushD = 1'b1;  // Flush ID and EX
```

#### Data Flow:
```
RegWriteM, RD_M → Forwarding comparator (MEM stage)
RegWriteW, RD_W → Forwarding comparator (WB stage)
Rs1_E, Rs2_E → Forwarding comparator
Rs1_D, Rs2_D, RdE, ResultSrcE → Stall detection logic
PCSrcE → Flush generation
```

---

## 📈 Inter-Stage Signal Propagation

### **IF → ID Pipeline Register**
| Signal | Width | Purpose |
|--------|-------|---------|
| `InstrD` | 32 | Instruction fetched from memory |
| `PCD` | 32 | Program counter value |
| `PCPlus4D` | 32 | PC + 4 for exception handling |

### **ID → EX Pipeline Register**
| Signal | Width | Purpose |
|--------|-------|---------|
| **Control:** | | |
| `RegWriteE` | 1 | Register file write enable |
| `ALUSrcE` | 1 | ALU operand B source (reg/imm) |
| `MemWriteE` | 1 | Data memory write enable |
| `ResultSrcE` | 2 | Write-back mux select |
| `ALUControlE` | 4 | ALU operation code |
| `BranchE` | 4 | Branch condition specification |
| `JumpE` | 2 | Jump type (JAL/JALR) |
| `lsunitE` | 5 | Load/store control bus |
| `LUISrcE, isLUIE` | 2 | LUI/AUIPC handling |
| **Data:** | | |
| `RD1_E, RD2_E` | 32 | Register file read data |
| `Imm_Ext_E` | 32 | Sign-extended immediate |
| `RD_E` | 5 | Destination register address |
| `PCE, PCPlus4E` | 32 | Program counter values |

### **EX → MEM Pipeline Register**
| Signal | Width | Purpose |
|--------|-------|---------|
| `RegWriteM` | 1 | Register file write enable |
| `MemWriteM` | 1 | Data memory write enable |
| `ResultSrcM` | 2 | Write-back mux select |
| `RD_M` | 5 | Destination register address |
| `lsunitM` | 5 | Load/store control bus |
| `PCPlus4M` | 32 | PC + 4 for JAL write-back |
| `WriteDataM` | 32 | Store data (pre-aligned) |
| `ALU_ResultM` | 32 | ALU result / memory address |

### **MEM → WB Pipeline Register**
| Signal | Width | Purpose |
|--------|-------|---------|
| `RegWriteW` | 1 | Register file write enable |
| `ResultSrcW` | 2 | Write-back mux select |
| `RD_W` | 5 | Destination register address |
| `PCPlus4W` | 32 | PC + 4 for JAL |
| `ALU_ResultW` | 32 | ALU result pass-through |
| `ReadDataW` | 32 | Load data (formatted) |

---

## 🔄 Critical Data Paths

### **1. Register Data Read → Execute**
```
rf (ID) → RD1_D, RD2_D → ID/EX reg → RD1_E, RD2_E → 
  Forwarding muxes → Src_A, Src_B_interim → ALU
```

### **2. Forwarding Path (MEM)**
```
ALU_ResultM (EX/MEM reg) → WB stage → writeback_cycle →
  ResultW → Forwarding muxes in EX stage → ALU
```

### **3. Forwarding Path (WB)**
```
ResultW (WB stage) → Forwarding muxes in EX stage → ALU
```

### **4. Write-Back Path**
```
ALU_ResultW, ReadDataW, PCPlus4W → WB result mux →
  ResultW → Register_File write port
```

### **5. Branch Control Hazard**
```
PCSrcE, PCTargetE (EX) → PC mux (IF) → PC feedback loop
  (with StallF, StallD, FlushE, FlushD control)
```

### **6. Load-Use Hazard Stall**
```
Rs1_D, Rs2_D (ID) → Hazard unit detector →
  StallF, StallD (IF holds PC, ID holds IF/ID register) →
  Next cycle: EX result forwarded to execute stage
```

---

## 🎛️ Control Signal Encoding Reference

### **ALU Control Codes (4-bit)**
```
OPC[3:0] Operation         Inputs              Output
------   ---------         ------              ------
0000     ADD               A + B               32-bit result
0001     SUB               A - B               32-bit result
0100     AND               A & B               32-bit result
0101     OR                A | B               32-bit result
0110     JALR              (A+B) & ~1          32-bit address
0111     XOR               A ^ B               32-bit result
1000     SLL               A << B[4:0]         32-bit result
1001     SRL               A >> B[4:0]         32-bit result
1010     SRA               A >>> B[4:0]        32-bit signed result
1100     SLTU              A < B (unsigned)    1 or 0
1111     SLT               A < B (signed)      1 or 0
```

### **Branch Control Bus (4-bit) - BranchE[3:0]**
```
BranchE[3]   : Branch enable flag
BranchE[2:0] : Branch type (funct3)

Branch Types (funct3):
000: BEQ  (Branch Equal, taken if Zero=1)
001: BNE  (Branch Not Equal, taken if Zero=0)
100: BLT  (Branch Less Than signed, taken if ALU_result<0)
101: BGE  (Branch Greater/Equal signed, taken if ALU_result≥0)
110: BLTU (Branch Less Than unsigned, taken if ALU_result<0)
111: BGEU (Branch Greater/Equal unsigned, taken if ALU_result≥0)
```

### **Jump Control Bus (2-bit) - JumpE[1:0]**
```
JumpE[1]   : Jump enable
JumpE[0]   : Jump type (0=JAL, 1=JALR)

00: No jump
01: JALR (Jump And Link Register)
10: JAL (Jump And Link)
11: Reserved
```

### **Immediate Source (2-bit) - ImmSrc[1:0]**
```
00: I-type immediate (loads, immediate ALU ops)
01: S-type immediate (stores)
10: B-type immediate (branches)
11: J-type immediate (JAL)
```

### **Result Source (2-bit) - ResultSrc[1:0]**
```
00: ALU result (arithmetic, logic, shift operations)
01: Load data (from data memory)
10: PC + 4 (for JAL, JALR)
11: Reserved (defaults to ALU result)
```

---

## 📊 Memory-Mapped Layout

### **Instruction Memory (IMEM)**
- **Size:** 1024 × 32-bit (4 KB)
- **Address Range:** 0x00000000 - 0x00000FFC (word-aligned)
- **Access:** Asynchronous read
- **Contents:** Program instructions

### **Data Memory (DMEM)**
- **Size:** 1024 × 32-bit (4 KB)
- **Address Range:** 0x00000000 - 0x00000FFC (word-aligned)
- **Access:** Synchronous read/write with byte strobes
- **Features:** Per-byte write enable via WSTRB[3:0]

### **Register File**
- **Size:** 32 × 32-bit
- **Registers:** x0-x31 (RISC-V standard)
- **x0:** Hard-wired to zero
- **Read Ports:** 2 (asynchronous)
- **Write Port:** 1 (synchronous, same-cycle forwarding)

---

## 🔗 Complete Connection Summary

```
┌─────────────────────────────────────────────────────────────┐
│                    RISC-V 5-Stage Pipeline                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  IF Stage          ID Stage        EX Stage                  │
│  ┌──────┐          ┌──────┐        ┌──────┐                 │
│  │ IMEM │──Instr──>│ CTRL │        │ ALU  │                 │
│  │  PC  │          │  RF  │        │ JB   │                 │
│  │  +4  │          │ IMMU │        │ FWD  │                 │
│  └──────┘          └──────┘        └──────┘                 │
│     │                 │                │                     │
│     └─────────────────┴────────────────┴──────────────────┐  │
│                                                            │  │
│  MEM Stage              WB Stage                          │  │
│  ┌──────┐              ┌──────┐                           │  │
│  │ DMEM │────RF────>│ MUX  │                           │  │
│  │ LSU  │         └──────┘                           │  │
│  └──────┘             │                              │  │
│                       └─────────(Forwarding)─────────┘  │
│                                                          │
│  Hazard Unit (Central Controller)                       │
│  ├─ ForwardA, ForwardB  ──> EX stage forwarding muxes   │
│  ├─ StallF, StallD      ──> IF/ID pipeline hold         │
│  ├─ FlushE, FlushD      ──> Pipeline bubble insertion   │
│  └─ Monitors: register writes, register reads,           │
│     load-use dependencies, branch/jump taken status     │
│                                                          │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚡ Signal Timing & Synchronization

### **Clock Domains**
- **Single Clock Domain:** All components synchronous to rising edge of `clk`
- **Reset Synchronization:** Active-low `rst` signal (asynchronous)

### **Pipeline Register Behavior**
- **Normal Operation:** Data advances on rising clock edge
- **Stall (StallD):** IF/ID and ID/EX registers hold values
- **Stall (StallF):** PC register holds value
- **Flush (FlushE, FlushD):** Pipeline registers cleared to zero

### **Forwarding Latency**
- **MEM → EX Forwarding:** 1 cycle latency
- **WB → EX Forwarding:** 2 cycle latency
- **Load-Use Penalty:** 1 cycle stall (best case with forwarding)

---

**Document Version:** 1.0  
**Generated:** March 21, 2026  
**Architecture:** RISC-V RV32I  
**Implementation:** 5-Stage Pipeline with Hazard Unit
