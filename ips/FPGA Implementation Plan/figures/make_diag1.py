import matplotlib.pyplot as plt
import matplotlib.patches as patches
import numpy as np
import os

out_dir = r"c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\FPGA Implementation Plan\figures"

plt.rcParams['font.family'] = 'sans-serif'
plt.rcParams['font.sans-serif'] = ['DejaVu Sans', 'Arial', 'Helvetica']

# -------------------------------------------------------------
# 1. Stage Gate Roadmap
# -------------------------------------------------------------
fig, ax = plt.subplots(figsize=(11, 2.8), dpi=300)
ax.axis('off')

stages = [
    ("S0", "Filelist\nAudit", "DONE\n(0 Missing)", "#1b5e20", "#c8e6c9"),
    ("S1", "RTL Structural\nLint", "DONE\n(0 Errors)", "#1b5e20", "#c8e6c9"),
    ("S2", "Structural\nChecks", "DONE\n(0 Blackbox)", "#1b5e20", "#c8e6c9"),
    ("S3", "Defect\nTriage", "DONE\n(1615 Warn)", "#1b5e20", "#c8e6c9"),
    ("S4", "Synthesis\nBaseline", "NEXT\n(OOC)", "#0d47a1", "#bbdefb"),
    ("S5", "Constraints\n& Pinout", "PENDING\n(XDC)", "#555555", "#eeeeee"),
    ("S6", "Place &\nRoute", "PENDING\n(Timing)", "#555555", "#eeeeee"),
    ("S7", "Bitstream\nGen", "PENDING\n(Hardware)", "#555555", "#eeeeee"),
]

x_start = 0.05
y = 0.5
box_w = 0.095
box_h = 0.65
spacing = 0.12

for i, (code, title, status, border_col, fill_col) in enumerate(stages):
    cx = x_start + i * spacing
    # Draw box
    rect = patches.FancyBboxPatch((cx, y - box_h/2), box_w, box_h,
                                  boxstyle="round,pad=0.02,rounding_size=0.03",
                                  ec=border_col, fc=fill_col, lw=1.8)
    ax.add_patch(rect)
    
    # Text
    ax.text(cx + box_w/2, y + 0.16, code, ha='center', va='center', fontsize=11, fontweight='bold', color=border_col)
    ax.text(cx + box_w/2, y, title, ha='center', va='center', fontsize=8.5, color='#212121')
    ax.text(cx + box_w/2, y - 0.20, status, ha='center', va='center', fontsize=7.5, fontweight='bold', color=border_col)
    
    # Arrow to next
    if i < len(stages) - 1:
        ax.annotate('', xy=(cx + box_w + spacing - box_w, y), xytext=(cx + box_w, y),
                    arrowprops=dict(arrowstyle="->", color="#757575", lw=1.5))

ax.set_xlim(0, 1.02)
ax.set_ylim(0, 1.0)
plt.tight_layout()
fig.savefig(os.path.join(out_dir, "diag1_stages.png"), bbox_inches='tight')
plt.close(fig)
print("diag1 done")

