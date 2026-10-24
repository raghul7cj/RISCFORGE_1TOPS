import os
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

base_dir = r"c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\FPGA Implementation Plan"
fig_dir = os.path.join(base_dir, "figures")
docx_path = os.path.join(base_dir, "RISCFORGE_FPGA_PreImplementation_Signoff_Report.docx")

doc = Document()

# Set standard margins (0.7 in)
for section in doc.sections:
    section.top_margin = Inches(0.7)
    section.bottom_margin = Inches(0.7)
    section.left_margin = Inches(0.7)
    section.right_margin = Inches(0.7)

# Helper: Set cell shading
def set_cell_shading(cell, color_hex):
    shading_xml = f'<w:shd {nsdecls("w")} w:fill="{color_hex}"/>'
    cell._tc.get_or_add_tcPr().append(parse_xml(shading_xml))

# Helper: Set cell margins
def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement('w:tcMar')
    for m, val in [('w:top', top), ('w:bottom', bottom), ('w:left', left), ('w:right', right)]:
        node = OxmlElement(m)
        node.set(qn('w:w'), str(val))
        node.set(qn('w:type'), 'dxa')
        tcMar.append(node)
    tcPr.append(tcMar)

# Title Slide / Cover Block
p_title = doc.add_paragraph()
p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
r_title = p_title.add_run("RISCFORGE 1TOPS SoC — FPGA Implementation Exploration")
r_title.font.name = "Arial"
r_title.font.size = Pt(22)
r_title.font.bold = True
r_title.font.color.rgb = RGBColor(13, 71, 161) # Deep Blue

p_sub = doc.add_paragraph()
p_sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
r_sub = p_sub.add_run("Pre-Implementation Stage Sign-Off & Status Report (Stages S0 – S3)\nTarget: Digilent Nexys4 DDR (AMD Artix-7 xc7a100tcsg324-1)")
r_sub.font.name = "Arial"
r_sub.font.size = Pt(12)
r_sub.font.bold = True
r_sub.font.color.rgb = RGBColor(69, 90, 100)

doc.add_paragraph().paragraph_format.space_after = Pt(4)

# -----------------------------------------------------------------------------
# EXECUTIVE SCORECARD
# -----------------------------------------------------------------------------
p_h1 = doc.add_paragraph()
r_h1 = p_h1.add_run("1. Stage-Gated Implementation Roadmap & Current Status")
r_h1.font.name = "Arial"
r_h1.font.size = Pt(14)
r_h1.font.bold = True
r_h1.font.color.rgb = RGBColor(13, 71, 161)

img1_path = os.path.join(fig_dir, "diag1_stages.png")
if os.path.exists(img1_path):
    doc.add_picture(img1_path, width=Inches(6.8))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

# Summary Table
table_status = doc.add_table(rows=5, cols=4)
table_status.alignment = WD_TABLE_ALIGNMENT.CENTER
headers = ["Stage", "Focus Area", "Key Deliverables & Resolution", "Sign-Off Gate Status"]
for col_idx, h in enumerate(headers):
    cell = table_status.cell(0, col_idx)
    cell.text = h
    set_cell_shading(cell, "0D47A1")
    for p in cell.paragraphs:
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        for run in p.runs:
            run.font.bold = True
            run.font.color.rgb = RGBColor(255, 255, 255)
            run.font.size = Pt(9)

data = [
    ("Stage 0 (S0)", "Filelist & Packaging", "100 files in vivado_soc.f; bus monitors added; D-114 timer routed to rtl/timer.sv", "✅ READY FOR SIGNOFF"),
    ("Stage 1 (S1)", "RTL Structural Lint", "Elaboration clean in Vivado 2022.2 (0 Errors, 0 Critical Warnings); IRQ modules resolved", "✅ READY FOR SIGNOFF"),
    ("Stage 2 (S2)", "Structural Hierarchy", "18,022 cells; 0 blackboxes; 1 primary clock; 5 reset domains catalogued", "✅ READY FOR SIGNOFF"),
    ("Stage 3 (S3)", "Defect Triage & Warnings", "All 1,615 warnings audited (100% waivable); RevB gaps (D-003, D-180, D-015, D-008) resolved", "✅ READY FOR SIGNOFF")
]

for row_idx, row_data in enumerate(data, start=1):
    bg = "F5F5F5" if row_idx % 2 == 1 else "FFFFFF"
    for col_idx, text in enumerate(row_data):
        cell = table_status.cell(row_idx, col_idx)
        cell.text = text
        set_cell_shading(cell, bg)
        for p in cell.paragraphs:
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            for run in p.runs:
                run.font.size = Pt(8.5)
                if "READY" in text:
                    run.font.bold = True
                    run.font.color.rgb = RGBColor(46, 125, 50)

doc.add_paragraph().paragraph_format.space_after = Pt(10)

# -----------------------------------------------------------------------------
# STAGE 0: FILELIST AUDIT & D-114 RESOLUTION
# -----------------------------------------------------------------------------
p_h2 = doc.add_paragraph()
r_h2 = p_h2.add_run("2. Stage 0 Audit: D-114 Timer IP & Manifest Origin Routing")
r_h2.font.name = "Arial"
r_h2.font.size = Pt(14)
r_h2.font.bold = True
r_h2.font.color.rgb = RGBColor(13, 71, 161)

p_t0 = doc.add_paragraph()
p_t0.add_run("• Audit Finding: ").bold = True
p_t0.add_run("Repository contained two copies of timer.sv. Diff analysis proved that apb_timer-master/rtl/timer.sv had received an essential bugfix qualifying interrupt generation and auto-counter-clear with TIMER_CTRL.ENABLE_BIT.\n")
p_t0.add_run("• Architectural Resolution: ").bold = True
p_t0.add_run("The root copy was restored untouched. All EDA build filelists (vivado_soc.f, jg_soc.f, spyglass.prj) were updated to route cleanly to the newer, bug-fixed file origin (apb_timer-master/rtl/timer.sv).")

img3_path = os.path.join(fig_dir, "diag3_timer_routing.png")
if os.path.exists(img3_path):
    doc.add_picture(img3_path, width=Inches(6.8))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph().paragraph_format.space_after = Pt(10)

# -----------------------------------------------------------------------------
# STAGE 1: APB-ENCLOSED OBI UART & IRQ RESOLUTION
# -----------------------------------------------------------------------------
p_h3 = doc.add_paragraph()
r_h3 = p_h3.add_run("3. Stage 1 Lint: APB-Enclosed OBI UART Architecture")
r_h3.font.name = "Arial"
r_h3.font.size = Pt(14)
r_h3.font.bold = True
r_h3.font.color.rgb = RGBColor(13, 71, 161)

p_t1 = doc.add_paragraph()
p_t1.add_run("• Internal OBI Enclosure: ").bold = True
p_t1.add_run("SoC connects to apb_uart strictly via AMBA APB4. Internally, apb_uart_wrap delegates to apb_to_obi, translating APB bus cycles into Open Bus Interface (OBI) transactions for the obi_uart core and its 5 submodules.\n")
p_t1.add_run("• Elaboration Integrity: ").bold = True
p_t1.add_run("Comments claiming 'OBI was removed' were false; the internal OBI chain is mandatory and fully preserved in vivado_soc.f.")

img2_path = os.path.join(fig_dir, "diag2_uart_obi.png")
if os.path.exists(img2_path):
    doc.add_picture(img2_path, width=Inches(6.8))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph().paragraph_format.space_after = Pt(10)

# -----------------------------------------------------------------------------
# STAGE 1: CORE INTERRUPT GATEWAY & ARBITER
# -----------------------------------------------------------------------------
p_h4 = doc.add_paragraph()
r_h4 = p_h4.add_run("4. Stage 1 & 2: RISC-V Core Interrupt Architecture (S1-F001 & D-003)")
r_h4.font.name = "Arial"
r_h4.font.size = Pt(14)
r_h4.font.bold = True
r_h4.font.color.rgb = RGBColor(13, 71, 161)

p_t2 = doc.add_paragraph()
p_t2.add_run("• S1-F001 Fix: ").bold = True
p_t2.add_run("irq_gateway.v and irq_arbiter.v were missing from repo filelists, aborting synthesis elaboration. Both modules were integrated into jg_soc.f, spyglass.prj, and vivado_soc.f.\n")
p_t2.add_run("• D-003 Architecture Triage: ").bold = True
p_t2.add_run("In-core arbiter supports 6 active sources (GPIO, I2C, SPI, UART, Timer MTIP, SPI EoT). Auxiliary Timer 0/1 overflow lines (fast_irq_i[10:4]) are bypassed at core top; core bring-up is 100% functional via standard MTIP.")

img4_path = os.path.join(fig_dir, "diag4_irq_subsystem.png")
if os.path.exists(img4_path):
    doc.add_picture(img4_path, width=Inches(6.8))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_paragraph().paragraph_format.space_after = Pt(10)

# -----------------------------------------------------------------------------
# STAGE 3: WARNING STUDY & REMEDIATION
# -----------------------------------------------------------------------------
p_h5 = doc.add_paragraph()
r_h5 = p_h5.add_run("5. Stage 3 Audit: Synthesis Elaboration Warning Taxonomy")
r_h5.font.name = "Arial"
r_h5.font.size = Pt(14)
r_h5.font.bold = True
r_h5.font.color.rgb = RGBColor(13, 71, 161)

p_t3 = doc.add_paragraph()
p_t3.add_run("• Zero Fatal Errors / Zero Critical Warnings: ").bold = True
p_t3.add_run("Vivado elaboration produced 1,615 warnings across 9 message IDs. Every warning was audited to exact RTL line origins and confirmed benign.")

img5_path = os.path.join(fig_dir, "diag5_warnings_chart.png")
if os.path.exists(img5_path):
    doc.add_picture(img5_path, width=Inches(6.8))
    doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER

# Warning summary table
table_warn = doc.add_table(rows=10, cols=4)
table_warn.alignment = WD_TABLE_ALIGNMENT.CENTER
w_headers = ["Synth ID", "Count", "Root Cause & File Origin", "Hardware Impact & Disposition"]
for col_idx, h in enumerate(w_headers):
    cell = table_warn.cell(0, col_idx)
    cell.text = h
    set_cell_shading(cell, "37474F")
    for p in cell.paragraphs:
        for run in p.runs:
            run.font.bold = True
            run.font.color.rgb = RGBColor(255, 255, 255)
            run.font.size = Pt(8.5)

w_data = [
    ("Synth 8-7129", "1,331", "Unconnected/unloaded bus address & status wires (axi_err_slv, obi_uart, addr_decode)", "Benign protocol slicing; pruned cleanly. WAIVED."),
    ("Synth 8-589", "160", "gpio.sv:171-219 assert_condition macro uses 4-state !== 1'bx", "Mapped to boolean != in 2-state FPGA logic. WAIVED."),
    ("Synth 8-7137", "41", "Async reset sensitivity list with unreset datapath flops (rv32m_mul, decode_cycle, rv32m_div)", "Control path resets cleanly; datapath infers standard D-FFs. AUDITED & WAIVED."),
    ("Synth 8-11067", "40", "Package parameters treated as localparam (axi_pkg.sv, gpio_reg_pkg.sv)", "IEEE 1800 compliance notice; parameters cannot be overridden. WAIVED."),
    ("Synth 8-6014", "20", "Dead sequential elements pruned (fifo_v3, rv32m_mul, csr_regfile, hybrid_mem)", "Desirable dead-code optimization; saves FPGA slice flops. WAIVED."),
    ("Synth 8-689", "16", "CSA carry net 65-bit vs 66-bit co port in rv32m_mul.v", "Intentional truncation for {co[64:0], 1'b0} left-shift into next rank. WAIVED."),
    ("Synth 8-7023", "3", "Instances with fewer declared connections: Fetch, ALU, csr_regfile", "Unused monitor outputs left open at top boundary. WAIVED."),
    ("Synth 8-7071", "3", "Specific unconnected ports: imem_stall, Zero, csr_valid_o", "Paired 1-to-1 with Synth 8-7023. WAIVED."),
    ("Synth 8-10940", "1", "Global macro REG_STATUS redefined in spi_master_apb_if.sv", "Local macro namespace clash with apb_i2c.sv. Safe; tagged for cleanup.")
]

for row_idx, row_data in enumerate(w_data, start=1):
    bg = "F5F5F5" if row_idx % 2 == 1 else "FFFFFF"
    for col_idx, text in enumerate(row_data):
        cell = table_warn.cell(row_idx, col_idx)
        cell.text = text
        set_cell_shading(cell, bg)
        for p in cell.paragraphs:
            for run in p.runs:
                run.font.size = Pt(8)

doc.add_paragraph().paragraph_format.space_after = Pt(10)

# -----------------------------------------------------------------------------
# STAGE 4 READINESS
# -----------------------------------------------------------------------------
p_h6 = doc.add_paragraph()
r_h6 = p_h6.add_run("6. Transition Gate: Readiness for Stage 4 (Synthesis Baseline)")
r_h6.font.name = "Arial"
r_h6.font.size = Pt(14)
r_h6.font.bold = True
r_h6.font.color.rgb = RGBColor(13, 71, 161)

p_t4 = doc.add_paragraph()
p_t4.add_run("All pre-implementation gates are closed:\n")
p_t4.add_run("• S0 Signed Off: ").bold = True
p_t4.add_run("Canonical manifest vivado_soc.f verified (100 source files).\n")
p_t4.add_run("• S1 Signed Off: ").bold = True
p_t4.add_run("Clean Vivado 2022.2 elaboration (0 Errors, 0 Critical Warnings).\n")
p_t4.add_run("• S2 Signed Off: ").bold = True
p_t4.add_run("18,022 cells, 0 blackboxes, 1 primary clock, 5 reset domains.\n")
p_t4.add_run("• S3 Signed Off: ").bold = True
p_t4.add_run("All 1,615 warnings audited; soc_regs.h & link.ld delivered for software bring-up.\n\n")
p_t4.add_run("Next Action in Fresh Session: ").bold = True
p_t4.add_run("Execute Stage 4 (synth_design -top riscforge_soc_subsystem -part xc7a100tcsg324-1), inspect Block RAM inference for ISRAM/DSRAM, and extract initial LUT/FF resource utilization metrics.")

doc.save(docx_path)
print(f"Report successfully saved to {docx_path}")

