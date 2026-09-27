import re
import os
from collections import defaultdict

report_path = r"c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\spyglass\reports\spyglass_moresimple.rpt"

file_issues = defaultdict(lambda: defaultdict(list))
rule_counts = defaultdict(int)
severity_counts = defaultdict(int)

# Line format: ID Rule Alias Severity File Line Wt Message
pattern = re.compile(r'^\s*\[([0-9A-Fa-f]+)\]\s+(\S+)\s+(\S+)?\s+(Error|Warning|SynthesisError|SynthesisWarning|Info|INFO)\s+(\S+)\s+(\d+)\s+(\d+)\s+(.*)$')

with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        m = pattern.match(line)
        if m:
            id_, rule, alias, severity, filepath, lineno, wt, msg = m.groups()
            file_issues[filepath][rule].append({
                'id': id_,
                'severity': severity,
                'line': lineno,
                'msg': msg
            })
            rule_counts[rule] += 1
            severity_counts[severity] += 1

print(f"Total files with issues: {len(file_issues)}")
print("\n--- Severity Breakdown ---")
for sev, count in sorted(severity_counts.items(), key=lambda x: x[1], reverse=True):
    print(f"{sev:20}: {count}")

print("\n--- File Breakdown ---")
for fp, rules in sorted(file_issues.items(), key=lambda x: sum(len(v) for v in x[1].values()), reverse=True):
    total = sum(len(v) for v in rules.values())
    print(f"\nFile: {fp} (Total: {total})")
    for r, items in sorted(rules.items(), key=lambda x: len(x[1]), reverse=True):
        print(f"  [{r}] ({len(items)}): {items[0]['msg'][:90]}...")

