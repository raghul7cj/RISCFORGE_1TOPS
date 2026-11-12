"""Re-verify the CSR/trap bench documentation claims against source and logs.

Checks run against the current checkout, not against a stored summary:

1. DUT port counts versus named connections in each testbench instance.
2. Every filelist source path exists.
3. The retained evidence hashes still match the bench/RTL sources.
4. Simulation markers match the numbers quoted in the documentation.
5. Every planned coverage bin was sampled exactly once.

Usage, from ``rtl/ips``:

    py Verification/tools/check_csr_trap_docs.py [artifact_dir]
"""
import re
import sys
from pathlib import Path

IPS = Path(__file__).resolve().parents[2]
VERIF = IPS / 'Verification'
DOCS = VERIF / 'doc'
ARTIFACT = Path(sys.argv[1]) if len(sys.argv) > 1 else VERIF / 'artifacts' / 'csr_trap_units_20261111_175150'

results = []


def check(name, passed, detail=''):
    results.append((name, passed, detail))


def read(path):
    return path.read_text(encoding='utf-8', errors='replace')


def module_ports(path):
    """Return the port names declared in a module's port list."""
    text = re.sub(r'//[^\n]*', '', read(path))
    header = re.search(r'\bmodule\s+\w+\b(.*?);', text, re.S)
    if header is None:
        return []
    body = header.group(1)
    if '#' in body:
        body = body[match_paren(body, body.index('(')) + 1:]
    start = body.index('(')
    body = body[start:match_paren(body, start) + 1]
    return re.findall(r'\b(?:input|output|inout)\b[^,]*?\b(\w+)\s*(?:,|\))', body)


def match_paren(text, open_index):
    """Index of the ')' matching the '(' at ``open_index``."""
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == '(':
            depth += 1
        elif text[index] == ')':
            depth -= 1
            if depth == 0:
                return index
    raise ValueError('unbalanced parentheses')


def named_connections(path, module):
    """Return the port names connected in every instance of ``module``."""
    text = read(path)
    ports = set()
    for match in re.finditer(r'\b' + module + r'\b', text):
        cursor = match.end()
        while cursor < len(text) and text[cursor] in ' \t\r\n':
            cursor += 1
        if cursor < len(text) and text[cursor] == '#':
            parameter_open = text.index('(', cursor)
            cursor = match_paren(text, parameter_open) + 1
        instance = re.match(r'\s*(\w+)\s*\(', text[cursor:])
        if instance is None:
            continue
        port_open = cursor + instance.end() - 1
        ports.update(re.findall(r'\.(\w+)\s*\(', text[port_open:match_paren(text, port_open)]))
    return ports


# 1. Port coverage ------------------------------------------------------------
csr_ports = module_ports(IPS / 'riscv_core/rtl/csr_regfile.v')
csr_connected = named_connections(VERIF / 'infrastructure/tb/tb_csr_corner_unit.sv', 'csr_regfile')
check('CSR unit: all csr_regfile ports connected',
      set(csr_ports) == csr_connected,
      f'{len(csr_connected)}/{len(csr_ports)} named, missing={sorted(set(csr_ports) - csr_connected)}, '
      f'extra={sorted(csr_connected - set(csr_ports))}')

# top.v keeps its port list across multiple lines with comments; count the
# connections the bench actually makes and compare to the declarations.
top_ports = module_ports(IPS / 'riscv_core/rtl/top.v')
core_connected = named_connections(VERIF / 'infrastructure/tb/tb_core_csr_trap.sv', 'top')
check('Core bench: all top ports connected',
      set(top_ports) == core_connected,
      f'{len(core_connected)}/{len(top_ports)} named, missing={sorted(set(top_ports) - core_connected)}, '
      f'extra={sorted(core_connected - set(top_ports))}')

# 2. Filelist integrity -------------------------------------------------------
for bench, expected in (('tb_csr_corner_unit.f', 4), ('tb_core_csr_trap.f', 39)):
    filelist = VERIF / 'filelists/tier1_unit' / bench
    sources = [line.split('//')[0].strip() for line in read(filelist).splitlines()]
    sources = [s for s in sources if s.endswith(('.sv', '.v'))]
    missing = [s for s in sources if not (IPS / s).exists()]
    check(f'{bench}: every source exists',
          len(sources) == expected and not missing,
          f'{len(sources)} listed, {len(missing)} missing {missing if missing else ""}')

# 3. Evidence identity --------------------------------------------------------
hashes = (ARTIFACT / 'source_sha256.txt')
if hashes.exists():
    mismatched = []
    entries = [line.split(None, 1) for line in read(hashes).splitlines() if line.strip()]
    for digest, relative in entries:
        import hashlib
        actual = hashlib.sha256((IPS / relative).read_bytes()).hexdigest()
        if actual != digest:
            mismatched.append(relative)
    check('Evidence hashes match current sources', not mismatched,
          f'{len(entries) - len(mismatched)}/{len(entries)} match, mismatched={mismatched}')
else:
    check('Evidence hashes match current sources', False, f'{hashes} missing')

# 4. Result markers -----------------------------------------------------------
unit_log = read(ARTIFACT / 'csr_corner_unit' / 'simulation.log')
core_log = read(ARTIFACT / 'core_csr_trap' / 'simulation.log')
done = re.search(r'UNIT_DONE\|checks=(\d+)\|failures=(\d+)\|spec_pending=(\d+)', unit_log)
check('Unit: UNIT_DONE marker present and zero failures',
      bool(done) and done.group(2) == '0',
      done.group(0) if done else 'marker missing')
check('Unit: 552 checks / 56 spec-pending',
      bool(done) and done.group(1) == '552' and done.group(3) == '56',
      done.groups() if done else 'marker missing')
check('Unit: finish time 8936 ns',
      '$finish called at time : 8936 ns' in unit_log,
      re.search(r'\$finish called at time : \S+ ns', unit_log).group(0) if '$finish called' in unit_log else 'missing')
core_skeleton = 'SKELETON/INCOMPLETE; checks=0; failures=0' in core_log
core_finish = re.search(r'\$finish called at time : (\S+) ns', core_log)
check('Core: skeleton marker and 30 ns finish',
      core_skeleton and bool(core_finish) and core_finish.group(1) == '30',
      f"marker={'present' if core_skeleton else 'missing'}, "
      f"finish={core_finish.group(0) if core_finish else 'missing'}")

# 5. Coverage bins ------------------------------------------------------------
hits = {}
for group, index in re.findall(r'BIN_HIT\|(\d+)\|(\d+)', unit_log):
    hits.setdefault(int(group), set()).add(int(index))
planned = {0: 8, 1: 168, 2: 40, 3: 16, 4: 4}
missing_bins = {g: sorted(set(range(n)) - hits.get(g, set())) for g, n in planned.items()}
total_hits = sum(len(v) for v in hits.values())
check('Unit: every planned bin sampled once',
      not any(missing_bins.values()),
      f'{total_hits} of {sum(planned.values())} bins, missing={ {g: v for g, v in missing_bins.items() if v} }')

# Report ----------------------------------------------------------------------
width = max(len(name) for name, _, _ in results)
for name, passed, detail in results:
    print(f"{'PASS' if passed else 'FAIL'}  {name.ljust(width)}  {detail}")
failed = sum(1 for _, passed, _ in results if not passed)
print(f'\n{len(results) - failed}/{len(results)} checks passed')
sys.exit(1 if failed else 0)
