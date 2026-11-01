import os

html_path = r'Verification/documentation/RISCFORGE_Verification_Infrastructure.html'
svg_path = r'Verification/documentation/assets/riscforge_infra_architecture.svg'

with open(html_path, 'r', encoding='utf-8') as f:
    html_doc = f.read()

with open(svg_path, 'r', encoding='utf-8') as f:
    svg_doc = f.read()

old_nav = '<a href="#hardware-hierarchy" class="nav-link">1. Hardware Hierarchy</a>'
new_nav = '<a href="#infra-overview" class="nav-link">0. Infrastructure Map</a>\n    <a href="#hardware-hierarchy" class="nav-link">1. Hardware Hierarchy</a>'

if old_nav in html_doc:
    html_doc = html_doc.replace(old_nav, new_nav, 1)

target_sec1 = '  <!-- Section 1: System Structural & Hardware Hierarchy -->'

section_0 = f'''  <!-- Section 0: End-to-End Infrastructure Architecture Map -->
  <section id="infra-overview">
    <div class="section-header">
      <h2>0. End-to-End Verification Infrastructure &amp; Methodology Map</h2>
      <p>System-level visual architectural blueprint connecting canonical baseline identity, 3-tier boundary filelists, ephemeral sandboxed execution, strict anti-vacuity classification, and automated dynamic governance.</p>
    </div>
    <div class="card" style="padding: 1rem; overflow-x: auto; background: #ffffff;">
      <div style="min-width: 960px; max-width: 1240px; margin: 0 auto;">
{svg_doc}
      </div>
    </div>
  </section>

{target_sec1}'''

if target_sec1 in html_doc and 'id="infra-overview"' not in html_doc:
    html_doc = html_doc.replace(target_sec1, section_0, 1)

with open(html_path, 'w', encoding='utf-8') as f:
    f.write(html_doc)

print('Successfully embedded SVG diagram into RISCFORGE_Verification_Infrastructure.html')
