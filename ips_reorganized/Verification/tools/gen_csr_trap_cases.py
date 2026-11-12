"""Generate explicit directed programs and the planned coverage-bin registry.

Expected literals describe individual tests, not a complete ISA reference model.
"""
from pathlib import Path
import argparse
import json

BASE = 0x80000000
DATA = 0x80001000
HANDLER = BASE + 0x400
GROUPS = ["u_status", "u_metadata", "u_collision", "u_counter", "u_reset",
          "c_exception", "c_csr_dependency", "c_irq_delivery", "c_irq_order",
          "c_irq_phase", "c_m_interrupt", "c_exception_overlap", "c_mret"]
registry = {name: [] for name in GROUPS}
cases = []


def i(op, rd, f3, rs1, immediate):
    return ((immediate & 4095) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op


def addi(rd, rs, value):
    return i(0x13, rd, 0, rs, value)


def csr(rd, address, rs, form=1):
    return i(0x73, rd, form, rs, address)


def store(rs, address_rs, offset=0, width=2):
    offset &= 4095
    return ((offset >> 5) << 25) | (rs << 20) | (address_rs << 15) | (width << 12) | ((offset & 31) << 7) | 0x23


def load(rd, address_rs, offset=0, width=2):
    return i(0x03, rd, width, address_rs, offset)


def branch(rs1, rs2, offset, form=0):
    return (((offset >> 12) & 1) << 31) | (((offset >> 5) & 63) << 25) | (rs2 << 20) | (rs1 << 15) | (form << 12) | (((offset >> 1) & 15) << 8) | (((offset >> 11) & 1) << 7) | 0x63


def jal(rd, offset):
    return (((offset >> 20) & 1) << 31) | (((offset >> 1) & 1023) << 21) | (((offset >> 11) & 1) << 20) | (((offset >> 12) & 255) << 12) | (rd << 7) | 0x6f


def constant(rd, value):
    value &= 0xffffffff
    high = ((value + 0x800) >> 12) & 0xfffff
    return [(high << 12) | (rd << 7) | 0x37, addi(rd, rd, value & 4095)]


def bin_id(group, label):
    result = len(registry[group])
    registry[group].append({"index": result, "id": f"{group}.{result:03}", "label": label})
    return result


def prefix(irq=False, release=0, threshold=0):
    words = constant(1, DATA) + constant(2, 0x13579bdf)
    words += constant(3, HANDLER) + [csr(0, 0x305, 3)]
    words += constant(4, 0x0fff0080 if release != 2 else 0) + [csr(0, 0x304, 4)]
    words += [addi(5, 0, 3 if release == 3 else threshold), csr(0, 0x7c0, 5)]
    words += [addi(6, 0, 8 if irq and release != 1 else 0), csr(0, 0x300, 6)]
    return words


def make(group, label, payload, *, cause=None, source=-1, trigger=0,
         release=0, latency=0, error=0, target_offset=0, handler="halt",
         pending=False, expected_registers=None, quiet=False, window=0,
         expected_memory=None, target_absolute=None):
    index = bin_id(group, label)
    words = prefix(source >= 0, release)
    target = BASE + 4 * (len(words) + target_offset)
    if target_absolute is not None:
        target = target_absolute
    words += payload
    words += [store(2, 1, 0xf0), jal(0, 0)]
    while len(words) < 256:
        words.append(0x13)
    if handler == "return_irq":
        words += [0x30200073, jal(0, 0)]
    elif handler == "skip_exception":
        words += [csr(28, 0x341, 0, 2), addi(28, 28, 4), csr(0, 0x341, 28), 0x30200073, jal(0, 0)]
    else:
        words += [jal(0, 0)]
    case = {
        "id": f"{group}_{index:03}", "group": group, "group_index": GROUPS.index(group),
        "bin": index, "label": label, "program": words, "target_pc": target,
        "source": source, "trigger": trigger, "window": window, "release": release,
        "latency": latency, "error_address": error, "cycle_budget": 240,
        "expectation": "spec_pending" if pending else "directed_literals",
        "expected_cause": cause, "expected_registers": expected_registers or {},
        "expected_memory": expected_memory or {}, "quiet": quiet,
        "handler": handler
    }
    if cause is not None and source < 0:
        case["expected_exception_pc"] = target
    cases.append(case)
    return case


def generate_unit_registry():
    for event in ("trap", "mret"):
        for mie in range(2):
            for mpie in range(2):
                bin_id("u_status", f"{event}: old MIE={mie}, MPIE={mpie}")
    causes = [(0, c) for c in (0, 2, 3, 4, 5, 6, 7, 11)] + [(1, c) for c in (7, *range(16, 28))]
    for kind, cause in causes:
        for pc_pattern in range(2):
            for address_valid in range(2):
                for value_pattern in range(2):
                    bin_id("u_metadata", f"irq={kind} cause={cause} pc_pattern={pc_pattern} addr_valid={address_valid} value_pattern={value_pattern}")
    addresses = (0x300, 0x304, 0x305, 0x340, 0x341, 0x342, 0x343, 0x7c0, 0x344, 0xb00, 0xb80, 0xb02, 0xb82)
    for event in ("normal+trap", "normal+mret", "all_three"):
        for address in addresses:
            bin_id("u_collision", f"{event}: normal target {address:03x}")
    bin_id("u_collision", "trap+mret without normal write")
    for counter in ("mcycle", "minstret"):
        for boundary in ("carry", "wrap"):
            bin_id("u_counter", f"{counter}: {boundary}")
    for counter in ("mcycle", "minstret"):
        for half in ("low", "high"):
            for event in ("increment", "trap", "mret"):
                bin_id("u_counter", f"{counter}.{half} write with {event}")
    for event in ("normal", "trap", "mret", "normal+trap"):
        bin_id("u_reset", "reset with " + event)


def exceptions():
    make("c_exception", "ECALL", [0x73], cause=11)
    make("c_exception", "EBREAK", [0x100073], cause=3)
    for label, word, pending in [
        ("bad_opcode", 0xffffffff, False), ("reserved_branch_funct3", branch(0, 0, 8, 2), True),
        ("reserved_shift_funct7", i(0x13, 8, 1, 0, 0xfe0), True),
        ("unsupported_SYSTEM", 0x10200073, True),
        ("invalid_CSR_address", csr(8, 0x399, 0, 2), True),
        ("write_readonly_CSR", csr(0, 0xc00, 2), True)
    ]:
        make("c_exception", label, [word], cause=2, pending=pending)
    make("c_exception", "taken_branch_misaligned", [branch(0, 0, 2)], cause=0)
    make("c_exception", "JAL_misaligned", [jal(8, 2)], cause=0)
    for low in range(4):
        payload = constant(9, BASE + 0x800 + low) + [i(0x67, 8, 0, 9, 0)]
        make("c_exception", f"JALR_raw_low_{low}", payload,
             cause=0 if low & 2 else None, target_offset=2, pending=(low == 1))
    make("c_exception", "untaken_misaligned_branch_guard", [branch(0, 2, 2)], quiet=True)
    for operation, form, store_op, offsets in [
        ("LH", 1, False, (1, 3)), ("LHU", 5, False, (1, 3)),
        ("SH", 1, True, (1, 3)), ("LW", 2, False, (1, 2, 3)),
        ("SW", 2, True, (1, 2, 3))
    ]:
        for offset in offsets:
            word = store(2, 1, offset, form) if store_op else load(8, 1, offset, form)
            case = make("c_exception", f"{operation}_misaligned_{offset}", [word], cause=6 if store_op else 4)
            case["expected_tval"] = DATA + offset
    for store_op in (False, True):
        for latency in (0, 1, 4):
            case = make("c_exception", f"{'store' if store_op else 'load'}_error_wait_{latency}",
                        [store(2, 1, 0x40) if store_op else load(8, 1, 0x40)],
                        cause=7 if store_op else 5, latency=latency, error=DATA + 0x40)
            case["expected_tval"] = DATA + 0x40
    for form in (0, 4, 1, 5, 2):
        for offset in (range(4) if form in (0, 4) else ((0, 2) if form in (1, 5) else (0,))):
            make("c_exception", f"aligned_load_guard_{form}_{offset}", [load(8, 1, offset, form)], quiet=True)


def dependencies():
    forms = (1, 2, 3, 5, 6, 7)
    def op(value, operand, form):
        return operand if form in (1, 5) else (value | operand if form in (2, 6) else value & ~operand)
    for producer in forms:
        for consumer in forms:
            after = op(0, 5, producer)
            payload = [addi(10, 0, 5), csr(8, 0x340, 10 if producer < 5 else 5, producer),
                       csr(9, 0x340, 10 if consumer < 5 else 5, consumer)]
            make("c_csr_dependency", f"adjacent_{producer}_{consumer}", payload,
                 target_offset=2, expected_registers={"9": after}, quiet=True)
    for producer in (1, 2, 3):
        for consumer in (1, 2, 3):
            for gap in (1, 2):
                after = op(0, 5, producer)
                payload = [addi(10, 0, 5), csr(8, 0x340, 10, producer)] + [addi(20, 20, 1)] * gap + [csr(9, 0x340, 10, consumer)]
                make("c_csr_dependency", f"gap_{producer}_{consumer}_{gap}", payload,
                     target_offset=len(payload)-1, expected_registers={"9": after}, quiet=True)
    for consumer in ("alu", "branch", "store_address", "store_data", "csr_source"):
        for gap in range(3):
            value = DATA if consumer == "store_address" else 5
            payload = constant(10, value) + [csr(0, 0x340, 10), csr(8, 0x340, 0, 2)]
            payload += [addi(20, 20, 1)] * gap
            expected = {}
            memory = {}
            if consumer == "alu":
                payload += [addi(9, 8, 3)]; expected = {"9": 8}
            elif consumer == "branch":
                payload += [branch(8, 10, 8), addi(9, 0, 99), addi(9, 0, 7)]; expected = {"9": 7}
            elif consumer == "store_address":
                payload += [store(2, 8, 0x20)]; memory = {str(DATA+0x20): 0x13579bdf}
            elif consumer == "store_data":
                payload += [store(8, 1, 0x20)]; memory = {str(DATA+0x20): 5}
            else:
                payload += [csr(0, 0x343, 8), csr(9, 0x343, 0, 2)]; expected = {"9": 5}
            make("c_csr_dependency", f"gpr_{consumer}_gap_{gap}", payload,
                 target_offset=4+gap, expected_registers=expected, expected_memory=memory, quiet=True)
    suppression = [
        ("rd_zero_write_read", [csr(0, 0x340, 2), csr(9, 0x340, 0, 2)], {"9": 0x13579bdf}),
        ("RS_zero_trap", [csr(8, 0x340, 0, 2), 0x73], {}),
        ("RC_zero_trap", [csr(8, 0x340, 0, 3), 0x73], {}),
        ("RSI_zero_trap", [csr(8, 0x340, 0, 6), 0x73], {}),
        ("RCI_zero_trap", [csr(8, 0x340, 0, 7), 0x73], {}),
        ("RW_zero_write_read", [csr(0, 0x340, 0), csr(9, 0x340, 0, 2)], {"9": 0}),
        ("RWI_zero_write_read", [csr(0, 0x340, 0, 5), csr(9, 0x340, 0, 2)], {"9": 0})
    ]
    for label, payload, expected in suppression:
        has_trap = payload[-1] == 0x73
        make("c_csr_dependency", label, payload, cause=11 if has_trap else None,
             target_offset=1, expected_registers=expected, quiet=not has_trap)


def interrupts():
    for source in (7, *range(16, 28)):
        for release in range(4):
            payload = [addi(20, 20, 1)] * 8
            if release == 1:
                payload += [addi(6, 0, 8), csr(0, 0x300, 6)]
            elif release == 2:
                payload += constant(4, 0x0fff0080) + [csr(0, 0x304, 4)]
            elif release == 3:
                payload += [csr(0, 0x7c0, 0)]
            payload += [addi(21, 0, 42)]
            make("c_irq_delivery", f"source_{source}_release_{release}", payload,
                 source=source, cause=0x80000000 | source, release=release,
                 trigger=1, handler="return_irq")
    for address in (0x300, 0x304, 0x7c0):
        for direction in ("allow", "block"):
            for stage in (2, 3):
                value = (8 if address == 0x300 else 0x80) if direction == "allow" else 0
                if address == 0x7c0:
                    value = 0 if direction == "allow" else 3
                payload = constant(10, value) + [csr(0, address, 10), addi(20, 20, 1)] * 1
                make("c_irq_order", f"gating_{address:03x}_{direction}_stage_{stage}", payload,
                     source=7, trigger=stage, target_offset=2, pending=True, handler="return_irq")
    for target in ("mtvec", "mepc"):
        for gap in range(3):
            address = 0x305 if target == "mtvec" else 0x341
            payload = constant(10, HANDLER if target == "mtvec" else BASE + 0x300)
            payload += [csr(0, address, 10)] + [addi(20, 20, 1)] * gap
            payload += [0x73 if target == "mtvec" else 0x30200073]
            make("c_irq_order", f"{target}_before_control_gap_{gap}", payload,
                 cause=11 if target == "mtvec" else None, target_offset=len(payload)-1,
                 pending=(target == "mepc"))
    phases = [("alu", 1), ("csr_E", 1), ("wait_entry", 4), ("wait_middle", 5),
              ("response", 6), ("before_mret", 9), ("at_mret", 10), ("after_mret", 11)]
    for source in (7, 16, 19):
        for label, trigger in phases:
            if "wait" in label or label == "response":
                payload = [load(8, 1), addi(21, 0, 42)]
            elif "mret" in label:
                payload = constant(10, BASE+0x300) + [csr(0, 0x341, 10), 0x30200073]
            else:
                payload = [csr(8, 0x340, 0, 2) if label == "csr_E" else addi(21, 0, 42)]
            make("c_irq_phase", f"source_{source}_{label}", payload, source=source,
                 trigger=trigger, latency=4, handler="return_irq", pending=True)
    for operation in range(8):
        for phase, trigger in (("issue", 1), ("busy", 7), ("completion", 8)):
            payload = [addi(10, 0, 100), addi(11, 0, 3),
                       (1 << 25) | (11 << 20) | (10 << 15) | (operation << 12) | (8 << 7) | 0x33,
                       store(8, 1, 0x20)]
            make("c_m_interrupt", f"operation_{operation}_{phase}", payload,
                 source=7, trigger=trigger, target_offset=2, handler="return_irq", pending=True)
    for operation in range(4, 8):
        payload = [addi(10, 0, 100), addi(11, 0, 0), (1 << 25) | (11 << 20) | (10 << 15) | (operation << 12) | (8 << 7) | 0x33]
        make("c_m_interrupt", f"operation_{operation}_divide_zero", payload,
             source=7, trigger=8, target_offset=2, handler="return_irq", pending=True)
    for operation in (4, 6):
        payload = constant(10, 0x80000000) + [addi(11, 0, -1), (1 << 25) | (11 << 20) | (10 << 15) | (operation << 12) | (8 << 7) | 0x33]
        make("c_m_interrupt", f"operation_{operation}_signed_overflow", payload,
             source=7, trigger=8, target_offset=3, handler="return_irq", pending=True)


def overlaps_and_returns():
    for name, word, cause in (("illegal", 0xffffffff, 2), ("ECALL", 0x73, 11), ("EBREAK", 0x100073, 3)):
        make("c_exception_overlap", f"ID_{name}_older_memory_wait", [load(8, 1), word],
             cause=cause, latency=4, target_offset=1, window=1)
    make("c_exception_overlap", "EX_misalignment_older_memory_wait", [load(8, 1), jal(9, 2)], cause=0, latency=4, target_offset=1, window=1)
    for store_op in (False, True):
        make("c_exception_overlap", f"misaligned_{'store' if store_op else 'load'}_after_wait",
             [load(8, 1), store(2, 1, 1, 1) if store_op else load(9, 1, 1, 1)],
             cause=6 if store_op else 4, latency=4, target_offset=1, window=1)
    for store_op in (False, True):
        make("c_exception_overlap", f"delayed_{'store' if store_op else 'load'}_error",
             [store(2, 1, 0x40) if store_op else load(8, 1, 0x40)],
             cause=7 if store_op else 5, latency=4, error=DATA+0x40, window=2)
    make("c_exception_overlap", "older_MEM_fault_younger_EX_fault", [load(8, 1, 0x40), jal(9, 2)], cause=5, error=DATA+0x40)
    make("c_exception_overlap", "older_MEM_fault_younger_IRQ", [load(8, 1, 0x40), addi(9, 0, 7)],
         cause=5, source=7, trigger=1, error=DATA+0x40, pending=True)
    for younger, word in (("store", store(2, 1, 0x20)), ("csr", csr(0, 0x340, 2)), ("gpr", addi(9, 0, 99))):
        case = make("c_exception_overlap", f"older_trap_younger_{younger}", [0x73, word], cause=11)
        case["forbid_younger"] = {"kind": younger, "pc": case["target_pc"]+4}
    make("c_exception_overlap", "trap_versus_branch_redirect", [0x73, branch(0, 0, 8)], cause=11)
    make("c_exception_overlap", "trap_versus_frontend_hold", [load(8, 1), 0x73], cause=11, latency=4, target_offset=1, window=1)
    make("c_exception_overlap", "flushed_exception_candidate", [jal(0, 8), 0x73, addi(9, 0, 7)], quiet=True)
    make("c_exception_overlap", "IRQ_arrives_in_invalid_slot", [addi(9, 0, 7)]*8,
         source=7, trigger=12, cause=0x80000007, handler="return_irq")
    make("c_exception_overlap", "M_issue_behind_memory_wait", [load(8, 1), 0x022082b3], latency=4, window=1, target_offset=1, pending=True)
    make("c_exception_overlap", "synchronous_exception_vs_IRQ", [0x73], cause=11, source=7, trigger=1)
    for mpie in range(2):
        for pending in range(2):
            payload = constant(10, BASE+0x300) + [csr(0, 0x341, 10), addi(11, 0, mpie*128), csr(0, 0x300, 11), 0x30200073]
            make("c_mret", f"MPIE_{mpie}_pending_{pending}", payload,
                 source=7 if pending else -1, trigger=10, target_offset=5, pending=True)
    for kind, payload in [
        ("ALU", [addi(8, 0, 42)]), ("CSR", [csr(8, 0x340, 0, 2)]),
        ("load", [load(8, 1)]), ("store", [store(2, 1, 0x20)]),
        ("MUL", [0x02210433]), ("DIV", [0x02214433])
    ]:
        make("c_mret", f"replay_{kind}", payload, source=7, trigger=1,
             cause=0x80000007, handler="return_irq", pending=True)
    make("c_mret", "consecutive_handler_entries", [addi(8, 0, 42)]*8,
         source=7, trigger=13, handler="return_irq", pending=True)
    index = bin_id("c_mret", "software_context_save_restore_if_nesting_approved")
    registry["c_mret"][index]["status"] = "spec_pending_no_stimulus: software nesting not approved"


def coverage_package(path):
    text = ["package csr_trap_coverage_pkg;", "  class observed_corner_coverage;", "    bit unit_scope;"]
    for group in GROUPS:
        count = len(registry[group])
        text += [f"    covergroup {group} with function sample(int index);",
                 "      option.per_instance = 1;",
                 f"      bin_cp: coverpoint index {{ bins planned[] = {{[0:{count-1}]}}; }}",
                 "    endgroup", ""]
    text += ["    function new(bit unit_scope);", "      this.unit_scope = unit_scope;", "      if (unit_scope) begin"]
    for group in GROUPS[:5]: text.append(f"        {group} = new();")
    text += ["      end else begin"]
    for group in GROUPS[5:]: text.append(f"        {group} = new();")
    text += ["      end", "    endfunction", "", "    function void sample_bin(int group_id, int index);", "      case (group_id)"]
    for number, group in enumerate(GROUPS): text.append(f"        {number}: if ({'unit_scope' if number < 5 else '!unit_scope'}) {group}.sample(index);")
    text += ["      endcase", '      $display("BIN_HIT|%0d|%0d", group_id, index);', "    endfunction", "", "    function void report();"]
    for number, group in enumerate(GROUPS):
        text.append(f'      if ({"unit_scope" if number < 5 else "!unit_scope"}) $display("OBSERVED_COVERAGE|{group}|%0.3f", {group}.get_inst_coverage());')
    text += ["    endfunction", "  endclass", "endpackage", ""]
    path.write_text("\n".join(text))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--coverage-package", type=Path)
    args = parser.parse_args()
    generate_unit_registry(); exceptions(); dependencies(); interrupts(); overlaps_and_returns()
    args.out.mkdir(parents=True, exist_ok=True)
    stimulus = []
    for case in cases:
        filename = case["id"] + ".hex"
        (args.out / filename).write_text("\n".join(f"{word & 0xffffffff:08x}" for word in case["program"]) + "\n")
        case["image"] = filename
        fields = [case["id"], case["group_index"], case["bin"], case["source"],
                  case["trigger"], f'{case["target_pc"]:08x}', case["latency"],
                  f'{case["error_address"]:08x}', case["cycle_budget"],
                  -1 if case["expected_cause"] is None else case["expected_cause"],
                  case["window"], len(case["program"]), filename]
        stimulus.append(" ".join(map(str, fields)))
    (args.out / "cases.stim").write_text("\n".join(stimulus) + "\n")
    (args.out / "manifest.json").write_text(json.dumps({"groups": registry, "cases": cases,
        "expectation_scope": "Directed per-case literals only. Full ISA/platform reference model remains deferred. Spec-pending cases retain pending status."}, indent=2))
    if args.coverage_package:
        coverage_package(args.coverage_package)
    print(json.dumps({"core_cases": len(cases), "bins": {g: len(v) for g, v in registry.items()}}, indent=2))


if __name__ == "__main__":
    main()
