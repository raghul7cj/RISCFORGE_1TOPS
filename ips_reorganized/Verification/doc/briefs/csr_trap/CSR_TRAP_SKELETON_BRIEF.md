# Standalone implementation brief: CSR/trap testbench skeleton

Workspace: `C:/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl`.

Implement only a connected SystemVerilog skeleton according to [CSR_TRAP_CORNER_TESTPLAN.md](../../plans/CSR_TRAP_CORNER_TESTPLAN.md), especially sections 9 and 10. Section 10 supersedes functional test examples for this task. No conversation history is needed.

## Authorized work

Create a module/task-based CSR unit bench and a lightweight OOP SV core corner-case environment. Follow the planned file layout where practical. Connect interfaces, virtual interface handles, object constructors, event queues/mailboxes, passive observation, memory-model shells and the actual DUT instances. Provide independent compilation filelists for each top and a short README describing file order and engineer extension points.

Keep code human readable: consistent indentation, whitespace between logical blocks, explicit named port connections, minimal helpful comments and short meaningful component names. Prefer a small explicit structure over a generic framework.

The engineer will design/sign off the reference model and coverage bins and will supply stimuli later. Leave `TODO(USER_REF_MODEL)`, `TODO(USER_COVERAGE)` and `TODO(USER_STIMULUS)` hooks with useful method signatures and types. Do not implement an oracle, expected architectural state transitions, coverage bins/crosses, scenarios, firmware or test assertions that resolve architectural behavior. If a model is necessary for progress, stop at that hook and report what it needs.

Default initialization may make ports deterministic. Memory-model shells must expose useful interfaces/configuration hooks without claiming a validated response model. Keep the core held in reset during an optional skeleton-only run unless an explicit completed stimulus exists. Finalization must state SKELETON/INCOMPLETE; it must not report PASS or coverage closure when checking is absent. Missing reference/coverage/stimulus must be explicit rather than silently accepted.

No DUT RTL changes, existing-test changes, tool installations, remote EDA runs, commits, pushes or additional agents. A local syntax/elaboration check is permitted if a suitable simulator is available; functional campaigns are deferred. If no compiler is available, report static inspection only.

## Target paths, relative to ips/Verification

- `infrastructure/tb/csr_trap/`: types package, CSR/core interfaces, OOP environment package and small supporting class files, instruction/data memory shells, README.
- `infrastructure/tb/tb_csr_corner_unit.sv` and `tb_core_csr_trap.sv`: two independent tops.
- `infrastructure/checkers/core_csr_trap_probe.sv` and `core_csr_trap_assertions.sv`: actual passive connections and an empty clearly marked assertion-extension module.
- `filelists/tier1_unit/tb_csr_corner_unit.f` and `tb_core_csr_trap.f`: invocation root `rtl/ips`, correct dependency order, exact top named in README. Avoid changing the canonical regression crosswalk while the suite is incomplete.

Read applicable `AGENTS.md`; inspect targeted sources in small excerpts. Avoid repository-wide searches or reading reports unrelated to the skeleton.

## DUT and dependency references, relative to rtl

- `ips/riscv_core/rtl/csr_regfile.v`: unit DUT, every actual port including validity/read outputs, normal write, MRET/trap ports, retirement and IRQ inputs, sidebands. Reset is active low. A leaf bench can drive raw ports; it must not claim pipeline coverage.
- `ips/riscv_core/rtl/top.v`: core DUT `top`, parameter `RESET_PC`. Ports are `clk`, active-low `rst`, `PCSrcE1`, all `imem_sram_*`, all `lsu_mem_*`, and IRQ inputs `fast_irq_i[15:0]`, `timer_irq_i`, `ext_irq_i`, `sw_irq_i`. Use exact declarations, not this prose as a substitute for checking widths.
- `ips/Verification/tb1_interrupts.f`: existing core-only RTL dependency reference. Its testbench/programs and architectural expectations must not be copied into this skeleton. Pay attention to exactly one `axi_pkg` declaration.
- `ips/Verification/filelists/tier1_unit/tb_irq_arbiter.f`: existing small IRQ dependency reference; preserve it unchanged.
- `ips/riscv_core/rtl/wb_trap_mret_commit_controller.v`: already instantiated in core `top`. Connect probes to real signals and instances rather than making a second synthetic controller substitute for core integration.
- `ips/riscv_core/rtl/hazard_unit.v`, `memory_cycle.v`, `execute_cycle.v`, `decode_cycle.v`: targeted signal references only when needed for probe connections. Core IRQ causes currently delivered are 7 and 16..27. Cause-map expectations belong to the deferred reference model.
- `ips/Verification/tb_irq_restructure.sv`: existing unit implementation/coverage ownership reference, not the new full-core checker.

The existing core-only address defaults (`RESET_PC=0x80000000`, data base `0x80001000`) may be used consistently as skeleton parameters. Instruction fetch has no external ready/error input. The core data interface exposes request, write, address/data/byte enables and response data/stall/error. Avoid adding AXI agents or a full SoC boundary to this skeleton.

## Required handback

List created/modified paths, how tops/components connect, TODO ownership, compile/elaboration command and exact result if run, any unavailable signal/tool, and structural risks needing review. Explicitly state that no reference model, coverage bins or stimuli were implemented and no functional correctness is claimed.
