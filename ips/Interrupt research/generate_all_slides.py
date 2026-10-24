# generate_all_slides.py
import os
import zipfile
import xml.etree.ElementTree as ET

from build_v2_slides import (
    xml_escape, slide_header, slide_footer, title_shape, slide_num_shape,
    bullets_shape, callout_box, note_shape, table_graphic_frame
)

UNPACKED_SLIDES = os.path.join("unpacked", "ppt", "slides")

def make_slide1():
    # Title slide (slideLayout1)
    xml = slide_header()
    xml += """<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="2" name="Title 2"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr><p:ph type="ctrTitle"/></p:nvPr>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="336000" y="320040"/>
      <a:ext cx="11520000" cy="1600200"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
    <a:ln><a:noFill/></a:ln>
  </p:spPr>
  <p:txBody>
    <a:bodyPr anchorCtr="0" anchor="b" bIns="45700" lIns="91425" spcFirstLastPara="1" rIns="91425" wrap="square" tIns="45700">
      <a:spAutoFit/>
    </a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr indent="0" lvl="0" marL="0" rtl="0" algn="ctr">
        <a:lnSpc><a:spcPct val="95000"/></a:lnSpc>
        <a:spcBef><a:spcPts val="0"/></a:spcBef>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:r>
        <a:rPr sz="3200" b="1"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>Low-Latency, Starvation-Free Interrupt Front End for Small RISC-V Microcontrollers</a:t>
      </a:r>
      <a:endParaRPr sz="3200"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill></a:endParaRPr>
    </a:p>
    <a:p>
      <a:pPr indent="0" lvl="0" marL="0" rtl="0" algn="ctr">
        <a:lnSpc><a:spcPct val="90000"/></a:lnSpc>
        <a:spcBef><a:spcPts val="800"/></a:spcBef>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:r>
        <a:rPr sz="1800" b="0"><a:solidFill><a:srgbClr val="595959"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>Fixed-priority classes with round-robin arbitration and preemption in a core-local design</a:t>
      </a:r>
      <a:endParaRPr sz="1800"><a:solidFill><a:srgbClr val="595959"/></a:solidFill></a:endParaRPr>
    </a:p>
  </p:txBody>
</p:sp>
<p:pic>
  <p:nvPicPr>
    <p:cNvPr id="3" name="Crest Image 3"/>
    <p:cNvPicPr preferRelativeResize="0"/>
    <p:nvPr/>
  </p:nvPicPr>
  <p:blipFill rotWithShape="1">
    <a:blip r:embed="rId3"><a:alphaModFix/></a:blip>
    <a:srcRect b="0" l="0" r="0" t="0"/>
    <a:stretch/>
  </p:blipFill>
  <p:spPr>
    <a:xfrm>
      <a:off x="5118420" y="2259000"/>
      <a:ext cx="1955160" cy="1955160"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
    <a:ln><a:noFill/></a:ln>
  </p:spPr>
</p:pic>
<p:graphicFrame>
  <p:nvGraphicFramePr>
    <p:cNvPr id="4" name="Author Table 4"/>
    <p:cNvGraphicFramePr/>
    <p:nvPr/>
  </p:nvGraphicFramePr>
  <p:xfrm>
    <a:off x="336000" y="4484160"/>
    <a:ext cx="11520000" cy="2000000"/>
  </p:xfrm>
  <a:graphic>
    <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
      <a:tbl>
        <a:tblPr bandRow="1" firstRow="1"><a:noFill/></a:tblPr>
        <a:tblGrid>
          <a:gridCol w="5760000"/>
          <a:gridCol w="5760000"/>
        </a:tblGrid>
        <a:tr h="1959850">
          <a:tc>
            <a:txBody>
              <a:bodyPr/><a:lstStyle/>
              <a:p><a:pPr algn="l"><a:buNone/></a:pPr><a:r><a:rPr sz="2200" b="1"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>Presented By:</a:t></a:r></a:p>
              <a:p><a:pPr algn="l"><a:spcBef><a:spcPts val="400"/></a:spcBef><a:buNone/></a:pPr><a:r><a:rPr sz="1800" b="1"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>Raghul C J (CJ)</a:t></a:r></a:p>
              <a:p><a:pPr algn="l"><a:buNone/></a:pPr><a:r><a:rPr sz="1600"><a:solidFill><a:srgbClr val="595959"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>B.Tech ECE, IIIT Allahabad</a:t></a:r></a:p>
              <a:p><a:pPr algn="l"><a:buNone/></a:pPr><a:r><a:rPr sz="1600"><a:solidFill><a:srgbClr val="595959"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>SONIC-MCU</a:t></a:r></a:p>
              <a:p><a:pPr algn="l"><a:buNone/></a:pPr><a:r><a:rPr sz="1600"><a:solidFill><a:srgbClr val="7F7F7F"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>September 2026</a:t></a:r></a:p>
            </a:txBody>
            <a:tcPr marL="91450" marR="91450" marT="45725" marB="45725"><a:lnL w="0"><a:noFill/></a:lnL><a:lnR w="0"><a:noFill/></a:lnR><a:lnT w="0"><a:noFill/></a:lnT><a:lnB w="0"><a:noFill/></a:lnB></a:tcPr>
          </a:tc>
          <a:tc>
            <a:txBody>
              <a:bodyPr/><a:lstStyle/>
              <a:p><a:pPr algn="r"><a:buNone/></a:pPr><a:r><a:rPr sz="2200" b="1"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>Supervised By:</a:t></a:r></a:p>
              <a:p><a:pPr algn="r"><a:spcBef><a:spcPts val="400"/></a:spcBef><a:buNone/></a:pPr><a:r><a:rPr sz="1800" b="1"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>[Supervisor Name]</a:t></a:r></a:p>
              <a:p><a:pPr algn="r"><a:buNone/></a:pPr><a:r><a:rPr sz="1600"><a:solidFill><a:srgbClr val="595959"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>Department of ECE</a:t></a:r></a:p>
              <a:p><a:pPr algn="r"><a:buNone/></a:pPr><a:r><a:rPr sz="1600"><a:solidFill><a:srgbClr val="595959"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>IIIT Allahabad, India</a:t></a:r></a:p>
            </a:txBody>
            <a:tcPr marL="91450" marR="91450" marT="45725" marB="45725"><a:lnL w="0"><a:noFill/></a:lnL><a:lnR w="0"><a:noFill/></a:lnR><a:lnT w="0"><a:noFill/></a:lnT><a:lnB w="0"><a:noFill/></a:lnB></a:tcPr>
          </a:tc>
        </a:tr>
      </a:tbl>
    </a:graphicData>
  </a:graphic>
</p:graphicFrame>
"""
    xml += slide_footer()
    return xml

def make_slide2():
    # Objective / Introduction
    xml = slide_header()
    xml += title_shape(10, "Objective / Introduction")
    xml += slide_num_shape(11)
    bullets = [
        "Small RISC-V MCUs have few interrupt sources but still need bounded response time",
        "Provable worst-case interrupt response, not only low average latency",
        "Reduce interrupt acceptance latency in small-class, low-area cores",
        "Predictable real-time behaviour for latency-critical applications",
        "Suit area- and cost-bound MCUs with a slow or contended data bus",
        "Approach: core-local interrupt front end, no bus traffic for claim or completion"
    ]
    xml += bullets_shape(12, bullets, y=860000, cy=4400000, sz=1800, spcAft=1100)
    xml += callout_box(13, "Thesis: Core-local front end with zero bus contention, enabling formal worst-case bounds on small RISC-V cores",
                       y=5350000, cy=850000, bg="F2F2F2", text_color="C00000", sz=1800, bold=True)
    xml += slide_footer()
    return xml

def make_slide3():
    # Literature Survey (1/4) - Existing Designs
    xml = slide_header()
    xml += title_shape(20, "Literature Survey (1/4) - Existing Designs")
    xml += slide_num_shape(21)
    headers = ["Design", "Interface", "Priority", "Nesting", "Fairness", "Dispatch"]
    col_widths = [1600000, 2400000, 2200000, 1300000, 1800000, 1947120]
    rows = [
        ["PicoRV32 IRQ [3]", "Custom instructions (getq, setq, retirq)", "Software bitmask", "None", "Software", "Single entry, software decode"],
        ["Ibex [2]", "Standard privileged CSRs", "Fixed: fast lines first, lowest ID first", "Software only", "None", "Vectored, base + 4xID"],
        ["PLIC [4]", "Memory-mapped claim / complete", "Per-source priority + threshold", "Threshold only", "None", "Software via claim"],
        ["PULP CLIC [1, 5]", "CSRs + memory-mapped config", "Level, then priority, then ID", "Yes", "None", "Selective HW vectoring, xnxti"],
        ["CV32RT fastirq [1]", "CLIC + banked registers", "As CLIC", "Yes", "None", "HW vectoring + background save"],
        ["This work", "Core-local front end + custom CSRs", "Fixed classes", "Yes, class-based", "HW round-robin, wait at most n - 1", "mtvec / vector"]
    ]
    xml += table_graphic_frame(22, 457200, 850000, 11247120, 5100000, col_widths, headers, rows, highlight_last_col=False, highlight_row_idx=5, cell_sz=1300)
    xml += note_shape(23, "Fairness column: policy among equal-priority sources. Entries as documented in [1-5].", y=6150000)
    xml += slide_footer()
    return xml

def make_slide4():
    # Literature Survey (2/4) - Cost and Takeaways
    xml = slide_header()
    xml += title_shape(30, "Literature Survey (2/4) - Cost and Takeaways")
    xml += slide_num_shape(31)
    bullets = [
        "PicoRV32: size-optimised core, CPI 4-5, so cycles are not comparable",
        "Ibex: 15 fast lines + 3 standard + NMI; fixed order, no fairness",
        "PLIC: bus round trip for every claim and complete",
        "PULP CLIC: about 176 GE per source in config registers [1] (buys programmable level / priority)",
        "CV32RT: +36% register file, +21% ID stage [1] (buys banked context save)"
    ]
    xml += bullets_shape(32, bullets, y=900000, cy=4200000, sz=1800, spcAft=1200)
    xml += callout_box(33, "Takeaway: Fast paths cost logic and programmability; small designs give no fairness guarantee",
                       y=5300000, cy=850000, bg="F2F2F2", text_color="C00000", sz=1800, bold=True)
    xml += slide_footer()
    return xml

def make_slide5():
    # Literature Survey (3/4) - Latency and Overhead Comparison
    xml = slide_header()
    xml += title_shape(40, "Literature Survey (3/4) - Latency and Overhead Comparison")
    xml += slide_num_shape(41)
    headers = ["Metric", "PLIC [4]", "CLIC [5, 1]", "PicoRV32 [3]", "Ibex fast [2]", "This work"]
    col_widths = [2200000, 1750000, 1750000, 1600000, 1800000, 2147120]
    rows = [
        ["Location", "Bus slave (AXI / APB)", "Core-local port", "Inside pipeline", "Core fast port", "Core-local front end"],
        ["Entry latency (cycles, est.)", "35-45", "6-8", "about 8", "6-8", "To be measured (baseline: 6 uncontended, about 40 worst)"],
        ["Claim overhead", "15-25 bus cycles", "0 (HW vectoring)", "0", "0", "0 (no bus)"],
        ["Complete overhead", "12-18 bus cycles", "0 (xnxti)", "0", "SW bus write", "0 (auto-clear at WB commit)"],
        ["Round trip, leaf ISR (est.)", "62-88+", "about 40", "about 30", "about 55", "To be measured"],
        ["Bus contention", "High (shared crossbar)", "Zero", "Zero", "Partial (completion write)", "Zero"]
    ]
    xml += table_graphic_frame(42, 457200, 850000, 11247120, 5100000, col_widths, headers, rows, highlight_last_col=True, highlight_row_idx=None, cell_sz=1250)
    xml += note_shape(43, "NOTE: Other designs' cycle counts are indicative estimates, core- and configuration-dependent (PicoRV32 CPI 4-5); not measured on a common core.", y=6150000)
    xml += slide_footer()
    return xml

def make_slide6():
    # Literature Survey (4/4) - Functional Comparison
    xml = slide_header()
    xml += title_shape(50, "Literature Survey (4/4) - Functional Comparison")
    xml += slide_num_shape(51)
    headers = ["Feature", "PLIC [4]", "CLIC [5, 1]", "PicoRV32 [3]", "Ibex fast [2]", "This work"]
    col_widths = [1900000, 1850000, 1850000, 1700000, 1800000, 2147120]
    rows = [
        ["Pulse capture", "Gateway (level or edge)", "Per-channel, supported", "Latched", "Level only, pulses dropped", "Latched (pulse-latch gateway)"],
        ["Priority", "Static per-source (MMIO)", "Dynamic level + priority", "None (flat mask)", "Fixed ID order", "Fixed classes (static map)"],
        ["Fairness among equal peers", "None (lower ID wins)", "None (ID tie-break)", "None", "None", "Round-robin, wait at most n - 1"],
        ["Preemption / nesting", "Software only (threshold)", "Full hardware (levels)", "None (disabled in ISR)", "Software only", "Hardware, class-based"],
        ["Vectoring", "Software via claim", "Selective HW vectoring", "Single entry", "Vectored, base + 4xID", "Common entry / vector"],
        ["Privileged-spec fit", "PLIC spec", "Smclic draft", "Non-compliant (custom instructions)", "Standard CSRs", "Custom, CLIC-inspired subset"]
    ]
    xml += table_graphic_frame(52, 457200, 850000, 11247120, 5100000, col_widths, headers, rows, highlight_last_col=True, highlight_row_idx=None, cell_sz=1250)
    xml += note_shape(53, "NOTE: Silicon area is not compared; the designs have different scope and are not directly comparable.", y=6150000)
    xml += slide_footer()
    return xml

def make_slide7():
    # Research Gap / Problem Statement
    xml = slide_header()
    xml += title_shape(60, "Research Gap / Problem Statement")
    xml += slide_num_shape(61)
    xml += callout_box(62, "PROBLEM: A small single-core MCU needs fast, predictable interrupt response without CLIC-level programmability, and without letting busy sources starve others.",
                       x=457200, y=850000, cx=11247120, cy=950000, bg="F2F2F2", text_color="262626", sz=1800, bold=True)
    bullets = [
        "Among the surveyed RISC-V designs [1-5], none gives hardware-bounded waiting for equal-priority sources",
        "Fast-interrupt designs (CLIC, CV32RT) add programmable state and banked registers",
        "Small designs (Ibex-style, PicoRV32) use fixed or software priority, so starvation is possible",
        "PLIC-style claim / complete costs bus cycles, which hurts on a slow or contended bus",
        "Our baseline shows it concretely: pulse lost, starvation, threshold on cause IDs, acceptance blocked by MUL/DIV"
    ]
    xml += bullets_shape(63, bullets, x=457200, y=1950000, cx=11247120, cy=4200000, sz=1750, spcAft=1100)
    xml += slide_footer()
    return xml

def make_slide8():
    # Novelty / Contribution
    xml = slide_header()
    xml += title_shape(70, "Novelty / Contribution")
    xml += slide_num_shape(71)
    bullets = [
        "Custom lightweight, CLIC-inspired subset (not PLIC / CLIC compliant)",
        "Two-level arbiter: fixed priority between classes, round-robin within a class",
        "Class-based hardware preemption",
        "Hardware-bounded wait: same-class source waits at most n - 1 services",
        "Pulse-latch gateway with auto-clear on WB commit; round-robin pointer rotates at commit",
        "Core-local: zero bus traffic for claim or completion",
        "Formal verification (JasperGold): baseline expected to give counterexamples, new design to prove four properties",
        "Round-robin itself is established (e.g. AVR controllers [6]); the contribution is the combination in a RISC-V core-local front end, with a formal bound",
        "Claim scoped to the surveyed designs [1-6]"
    ]
    xml += bullets_shape(72, bullets, x=457200, y=850000, cx=11247120, cy=5500000, sz=1600, spcAft=700)
    xml += slide_footer()
    return xml

def make_slide9():
    # Methodology - Candidate Solutions (3 columns)
    xml = slide_header()
    xml += title_shape(80, "Methodology - Candidate Solutions")
    xml += slide_num_shape(81)
    
    col_w = 3566160
    gap = 274320
    x0 = 457200
    x1 = x0 + col_w + gap
    x2 = x1 + col_w + gap
    
    # Col 1: ARCHITECTURES
    b1 = [
        "Software-decoded IRQ (PicoRV32 style)",
        "Memory-mapped claim / complete (PLIC style)",
        "Full CLIC / CV32RT-style fast path",
        "Custom core-local arbiter"
    ]
    xml += f"""<p:sp>
  <p:nvSpPr><p:cNvPr id="82" name="Col1H"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr><a:xfrm><a:off x="{x0}" y="850000"/><a:ext cx="{col_w}" cy="400000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>
  <p:txBody><a:bodyPr wrap="square" anchor="t"/><a:lstStyle/><a:p><a:pPr algn="l"/><a:r><a:rPr sz="1900" b="1"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>ARCHITECTURES</a:t></a:r></a:p></p:txBody>
</p:sp>
"""
    xml += bullets_shape(83, b1, x=x0, y=1300000, cx=col_w, cy=3300000, sz=1500, spcAft=800)
    
    # Col 2: ARBITRATION POLICIES
    b2 = [
        "Fixed priority",
        "Pure round-robin",
        "Priority classes + round-robin",
        "Aging priority",
        "Weighted round-robin",
        "Deficit round-robin"
    ]
    xml += f"""<p:sp>
  <p:nvSpPr><p:cNvPr id="84" name="Col2H"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr><a:xfrm><a:off x="{x1}" y="850000"/><a:ext cx="{col_w}" cy="400000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>
  <p:txBody><a:bodyPr wrap="square" anchor="t"/><a:lstStyle/><a:p><a:pPr algn="l"/><a:r><a:rPr sz="1900" b="1"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>ARBITRATION POLICIES</a:t></a:r></a:p></p:txBody>
</p:sp>
"""
    xml += bullets_shape(85, b2, x=x1, y=1300000, cx=col_w, cy=3300000, sz=1500, spcAft=600)
    
    # Col 3: LOAD / STARVATION CONTROL
    b3 = [
        "ISR budget / time slicing",
        "Interrupt coalescing",
        "Deferred software service",
        "Rate limiting"
    ]
    xml += f"""<p:sp>
  <p:nvSpPr><p:cNvPr id="86" name="Col3H"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
  <p:spPr><a:xfrm><a:off x="{x2}" y="850000"/><a:ext cx="{col_w}" cy="400000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>
  <p:txBody><a:bodyPr wrap="square" anchor="t"/><a:lstStyle/><a:p><a:pPr algn="l"/><a:r><a:rPr sz="1900" b="1"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>LOAD / STARVATION CONTROL</a:t></a:r></a:p></p:txBody>
</p:sp>
"""
    xml += bullets_shape(87, b3, x=x2, y=1300000, cx=col_w, cy=3300000, sz=1500, spcAft=800)
    
    xml += callout_box(88, "Chosen: Core-local front end, priority classes with inner round-robin, rate limiting, and abortable divide",
                       x=457200, y=5200000, cx=11247120, cy=900000, bg="F2F2F2", text_color="C00000", sz=1700, bold=True)
    xml += slide_footer()
    return xml

def make_slide10():
    # Why Fixed Priority Classes + Inner Round-Robin
    xml = slide_header()
    xml += title_shape(90, "Why Fixed Priority Classes + Inner Round-Robin")
    xml += slide_num_shape(91)
    bullets = [
        "Fixed between classes: watchdog / fault and timer get deterministic response",
        "Round-robin inside a class: no starvation among peers, wait at most n - 1 services",
        "Pure fixed priority starves low sources; pure round-robin delays critical events",
        "Cheap: one pointer per class, no age counters",
        "Aging, weighted and deficit round-robin: more state, harder timing analysis, excessive for 5-6 sources",
        "Full CLIC: programmable levels and vectoring not needed at 5-6 fixed sources, and no fairness among equals",
        "PLIC: bus round trip per claim and complete",
        "Small state makes the guarantee provable formally"
    ]
    xml += bullets_shape(92, bullets, y=850000, cy=5500000, sz=1700, spcAft=800)
    xml += slide_footer()
    return xml

def make_image_slide(sp_prefix, title, image_filename):
    # Image slides (11, 12, 13) have only a title and the image file name
    xml = slide_header()
    xml += title_shape(sp_prefix, title)
    xml += slide_num_shape(sp_prefix + 1)
    
    # Center placeholder box for image
    xml += f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="{sp_prefix + 2}" name="ImageBox {sp_prefix + 2}"/>
    <p:cNvSpPr/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="1500000" y="1800000"/>
      <a:ext cx="9192000" cy="3500000"/>
    </a:xfrm>
    <a:prstGeom prst="roundRect"><a:avLst><a:gd name="adj" fmla="val 2000"/></a:avLst></a:prstGeom>
    <a:solidFill><a:srgbClr val="F8F9FA"/></a:solidFill>
    <a:ln w="12700"><a:solidFill><a:srgbClr val="D0D5DD"/></a:solidFill></a:ln>
    <a:effectLst/>
  </p:spPr>
  <p:txBody>
    <a:bodyPr rtlCol="0" anchor="ctr" wrap="square" lIns="54864" rIns="54864" tIns="27432" bIns="27432"/>
    <a:lstStyle/>
    <a:p>
      <a:pPr algn="ctr"><a:spcAft><a:spcPts val="600"/></a:spcAft></a:pPr>
      <a:r>
        <a:rPr sz="2600" b="1" i="0">
          <a:solidFill><a:srgbClr val="C00000"/></a:solidFill>
          <a:latin typeface="Courier New"/>
        </a:rPr>
        <a:t>[IMAGE: {xml_escape(image_filename)}]</a:t>
      </a:r>
    </a:p>
  </p:txBody>
</p:sp>
"""
    xml += slide_footer()
    return xml

def make_slide11():
    return make_image_slide(100, "Current SoC Architecture", "1790692217134_image.png")

def make_slide12():
    return make_image_slide(110, "Current Interrupt Implementation (Baseline)", "1790692236774_image.png")

def make_slide13():
    return make_image_slide(120, "Proposed Interrupt Architecture", "1790692252399_image.png")

def make_slide14():
    # Expected Outcomes
    xml = slide_header()
    xml += title_shape(130, "Expected Outcomes")
    xml += slide_num_shape(131)
    headers = ["Metric", "Baseline", "Target", "Evidence"]
    col_widths = [3800000, 2200000, 2200000, 3047120]
    rows = [
        ["Lost pulses (MIE = 0 or ISR running)", "Above 0 (counterexample)", "0", "JasperGold + stress simulation"],
        ["Same-class wait", "Unbounded", "At most n - 1 services", "JasperGold + adversarial storm"],
        ["Lower class granted before waiting higher class", "Possible", "Never", "JasperGold"],
        ["Auto-clear of a pending pulse", "Not applicable", "Only for the taken ID", "JasperGold"],
        ["Worst-case acceptance latency", "About 40 cycles (to be measured)", "To be measured", "RTL simulation, back-to-back divide"],
        ["Uncontended acceptance latency", "6 cycles (to be measured)", "No regression", "RTL simulation"],
        ["Preemption latency", "Not applicable", "To be measured", "RTL simulation"],
        ["Predicted vs measured worst-case response", "Not applicable", "Tightness ratio", "Response-time equation vs simulation"],
        ["Flops and GE", "Reference", "Delta per feature", "Synthesis"],
        ["Bus cycles per claim / complete", "0", "0", "By construction"]
    ]
    xml += table_graphic_frame(132, 457200, 800000, 11247120, 4200000, col_widths, headers, rows, highlight_last_col=False, highlight_row_idx=None, cell_sz=1150)
    xml += callout_box(133, "EXPECTED RESULT: Every source has a bounded wait; critical classes unaffected by peer traffic",
                       x=457200, y=5150000, cx=11247120, cy=700000, bg="F2F2F2", text_color="C00000", sz=1600, bold=True)
    xml += note_shape(134, "BOUNDS ASSUME: bounded ISR time, finite MIE = 0 windows, bounded arrival rate of higher classes",
                      x=457200, y=6000000, cy=300000, sz=1100)
    xml += slide_footer()
    return xml

def make_slide15():
    # Applications
    xml = slide_header()
    xml += title_shape(140, "Applications")
    xml += slide_num_shape(141)
    bullets = [
        "Watchdog and fault handling with guaranteed response",
        "Deadline / timer-driven real-time control loops",
        "Mixed-peripheral MCUs (UART, SPI, I2C, GPIO) where no channel may starve",
        "Area- and cost-bound microcontrollers",
        "SoCs with a slow or heavily contended data bus",
        "Deeply embedded and IoT edge nodes"
    ]
    xml += bullets_shape(142, bullets, y=900000, cy=5000000, sz=1850, spcAft=1400)
    xml += slide_footer()
    return xml

def make_slide16():
    # Future Work
    xml = slide_header()
    xml += title_shape(150, "Future Work")
    xml += slide_num_shape(151)
    bullets = [
        "Latency masking through register bank switching (background context save)",
        "ISR optimisation for starvation prevention: bounded work per ISR, deferred processing",
        "Interrupt coalescing and rate limiting for high-rate sources",
        "Aging or weighted variant for unequal traffic",
        "Programmable class map (CSR-configurable)",
        "Selective hardware vectoring for critical sources",
        "Shorter acceptance blocking from multi-cycle MUL / DIV",
        "Extended verification: constrained-random, riscv-dv, power on silicon"
    ]
    xml += bullets_shape(152, bullets, y=850000, cy=5500000, sz=1700, spcAft=900)
    xml += slide_footer()
    return xml

def make_slide17():
    # References
    xml = slide_header()
    xml += title_shape(160, "References")
    xml += slide_num_shape(161)
    refs = [
        "1.  R. Balas, A. Ottaviano, L. Benini, \"CV32RT: Enabling Fast Interrupt and Context Switching for RISC-V Microcontrollers,\" IEEE TVLSI, 2024.",
        "2.  lowRISC, Ibex documentation, \"Exceptions and Interrupts,\" ibex-core.readthedocs.io.",
        "3.  YosysHQ, PicoRV32 README, \"Custom Instructions for IRQ Handling,\" github.com/YosysHQ/picorv32.",
        "4.  RISC-V International, Privileged Architecture and PLIC specifications.",
        "5.  RISC-V, Smclic CLIC draft, github.com/riscv/riscv-fast-interrupt; PULP CLIC, github.com/pulp-platform/clic.",
        "6.  Microchip Technology, Application Note 40001982B, AVR interrupt controller."
    ]
    # No bullet chars for references, standard numbered list
    p_tags = []
    for r in refs:
        num, text = r.split(".  ", 1)
        p_tags.append(f"""    <a:p>
      <a:pPr algn="l" marL="457200" indent="-457200">
        <a:lnSpc><a:spcPct val="105000"/></a:lnSpc>
        <a:spcAft><a:spcPts val="1000"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:r>
        <a:rPr sz="1500" b="1" i="0"><a:solidFill><a:srgbClr val="C00000"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>[{num}]  </a:t>
      </a:r>
      <a:r>
        <a:rPr sz="1500" b="0" i="0"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>{xml_escape(text)}</a:t>
      </a:r>
    </a:p>""")
    body = "\n".join(p_tags)
    xml += f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="162" name="ReferencesBox 162"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="457200" y="880000"/>
      <a:ext cx="11247120" cy="5400000"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
  </p:spPr>
  <p:txBody>
    <a:bodyPr wrap="square" anchor="t" lIns="45720" rIns="45720" tIns="27432" bIns="27432">
      <a:spAutoFit/>
    </a:bodyPr>
    <a:lstStyle/>
{body}
  </p:txBody>
</p:sp>
"""
    xml += slide_footer()
    return xml

def make_slide18():
    # Thank You (slideLayout3 blank layout)
    xml = slide_header()
    xml += """<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="170" name="ThankYouTitle"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="838200" y="2400000"/>
      <a:ext cx="10515600" cy="1400000"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
    <a:ln><a:noFill/></a:ln>
  </p:spPr>
  <p:txBody>
    <a:bodyPr anchorCtr="0" anchor="t" bIns="45700" lIns="91425" spcFirstLastPara="1" rIns="91425" wrap="square" tIns="45700">
      <a:noAutofit/>
    </a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr indent="0" lvl="0" marL="0" marR="0" rtl="0" algn="ctr">
        <a:lnSpc><a:spcPct val="90000"/></a:lnSpc>
        <a:spcBef><a:spcPts val="0"/></a:spcBef>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:r>
        <a:rPr b="1" i="0" lang="en-US" sz="5400" u="none" cap="none" strike="noStrike">
          <a:solidFill><a:srgbClr val="C00000"/></a:solidFill>
          <a:latin typeface="Calibri"/>
        </a:rPr>
        <a:t>Thank You</a:t>
      </a:r>
      <a:endParaRPr/>
    </a:p>
  </p:txBody>
</p:sp>
<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="171" name="QuestionsSub"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="3000000" y="3800000"/>
      <a:ext cx="6192000" cy="800000"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
    <a:ln><a:noFill/></a:ln>
  </p:spPr>
  <p:txBody>
    <a:bodyPr anchorCtr="0" anchor="t" bIns="45700" lIns="91425" spcFirstLastPara="1" rIns="91425" wrap="square" tIns="45700">
      <a:spAutoFit/>
    </a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr indent="0" lvl="0" marL="0" marR="0" rtl="0" algn="ctr">
        <a:spcBef><a:spcPts val="0"/></a:spcBef>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:r>
        <a:rPr b="0" i="0" lang="en-US" sz="2400" u="none" cap="none" strike="noStrike">
          <a:solidFill><a:srgbClr val="595959"/></a:solidFill>
          <a:latin typeface="Calibri"/>
        </a:rPr>
        <a:t>Questions?</a:t>
      </a:r>
      <a:endParaRPr/>
    </a:p>
  </p:txBody>
</p:sp>
"""
    xml += slide_footer()
    return xml

def update_presentation_xml():
    # Update presentation.xml so slide order is strictly slide1.xml through slide18.xml
    pres_path = os.path.join("unpacked", "ppt", "presentation.xml")
    with open(pres_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Rebuild <p:sldIdLst>
    # rId mapping from presentation.xml.rels:
    # 1: rId7, 2: rId8, 3: rId9, 4: rId10, 5: rId11, 6: rId12, 7: rId13, 8: rId14, 9: rId15, 10: rId16
    # 11: rId18, 12: rId19, 13: rId20, 14: rId21, 15: rId22, 16: rId23, 17: rId24, 18: rId25
    rids = [
        ("256", "rId7"),
        ("257", "rId8"),
        ("258", "rId9"),
        ("259", "rId10"),
        ("260", "rId11"),
        ("261", "rId12"),
        ("262", "rId13"),
        ("263", "rId14"),
        ("264", "rId15"),
        ("265", "rId16"),
        ("266", "rId18"),
        ("267", "rId19"),
        ("268", "rId20"),
        ("269", "rId21"),
        ("270", "rId22"),
        ("271", "rId23"),
        ("272", "rId24"),
        ("273", "rId25"),
    ]
    new_sldIdLst = "<p:sldIdLst>" + "".join([f'<p:sldId id="{sid}" r:id="{rid}"/>' for sid, rid in rids]) + "</p:sldIdLst>"
    
    import re
    updated_content = re.sub(r'<p:sldIdLst>.*?</p:sldIdLst>', new_sldIdLst, content, flags=re.DOTALL)
    with open(pres_path, "w", encoding="utf-8") as f:
        f.write(updated_content)
    print("Updated presentation.xml <p:sldIdLst>")

def update_rels():
    # slide18.xml is Thank You, should use slideLayout3.xml
    rel18_path = os.path.join("unpacked", "ppt", "slides", "_rels", "slide18.xml.rels")
    with open(rel18_path, "r", encoding="utf-8") as f:
        c18 = f.read()
    c18 = c18.replace("slideLayout2.xml", "slideLayout3.xml")
    with open(rel18_path, "w", encoding="utf-8") as f:
        f.write(c18)
        
    # slide9.xml was Thank You (slideLayout3), now is Candidate Solutions (slideLayout2.xml)
    rel9_path = os.path.join("unpacked", "ppt", "slides", "_rels", "slide9.xml.rels")
    with open(rel9_path, "r", encoding="utf-8") as f:
        c9 = f.read()
    c9 = c9.replace("slideLayout3.xml", "slideLayout2.xml")
    with open(rel9_path, "w", encoding="utf-8") as f:
        f.write(c9)
    print("Updated slide rels.")

def build_all():
    generators = [
        make_slide1,
        make_slide2,
        make_slide3,
        make_slide4,
        make_slide5,
        make_slide6,
        make_slide7,
        make_slide8,
        make_slide9,
        make_slide10,
        make_slide11,
        make_slide12,
        make_slide13,
        make_slide14,
        make_slide15,
        make_slide16,
        make_slide17,
        make_slide18,
    ]
    
    for i, gen in enumerate(generators, 1):
        filename = f"slide{i}.xml"
        path = os.path.join(UNPACKED_SLIDES, filename)
        xml_content = gen()
        with open(path, "w", encoding="utf-8") as f:
            f.write(xml_content)
        print(f"Generated {filename}")

    update_presentation_xml()
    update_rels()
    
    # Pack back into Sem7_CJ_filled.pptx
    out_pptx = "Sem7_CJ_filled.pptx"
    if os.path.exists(out_pptx):
        os.remove(out_pptx)
        
    with zipfile.ZipFile(out_pptx, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk("unpacked"):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, "unpacked")
                z.write(full_path, rel_path)
    print(f"Successfully packaged {out_pptx}")

if __name__ == "__main__":
    build_all()
