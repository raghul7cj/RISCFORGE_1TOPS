import urllib.request
import json

resp = urllib.request.urlopen('http://127.0.0.1:4096/session/ses_f06c51d06ffeM2m6wOVTfJnuLD/message')
msgs = json.loads(resp.read().decode('utf-8'))
out = []
for i, m in enumerate(msgs):
    role = m.get('role') or m.get('info', {}).get('role')
    out.append(f'# Message {i} [{role}]\n')
    for p in m.get('parts', []):
        ptype = p.get('type')
        if ptype == 'text':
            out.append('### Text:\n' + p.get('text', '') + '\n')
        elif ptype == 'reasoning':
            out.append('### Reasoning:\n' + p.get('text', '') + '\n')
        elif ptype == 'tool':
            name = p.get('name')
            inp = json.dumps(p.get('input'))
            out.append(f'### Tool: {name}\nInput: {inp}\n')

with open('Verification/opencode_space_bunny_raw_audit.md', 'w', encoding='utf-8') as f:
    f.write('\n\n'.join(out))

print('Saved raw audit with reasoning to Verification/opencode_space_bunny_raw_audit.md')
