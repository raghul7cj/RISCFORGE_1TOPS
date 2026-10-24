# build_v2_slides.py
import os
import xml.etree.ElementTree as ET
import zipfile

UNPACKED = "unpacked"

def xml_escape(text):
    return (text.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace('"', "&quot;")
                .replace("'", "&apos;"))

def slide_header():
    return """<?xml version='1.0' encoding='UTF-8' standalone='yes'?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
       xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
       xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
       xmlns:mv="urn:schemas-microsoft-com:mac:vml"
       xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
       xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"
       xmlns:dgm="http://schemas.openxmlformats.org/drawingml/2006/diagram"
       xmlns:o="urn:schemas-microsoft-com:office:office"
       xmlns:v="urn:schemas-microsoft-com:vml"
       xmlns:pvml="urn:schemas-microsoft-com:office:powerpoint"
       xmlns:com="http://schemas.openxmlformats.org/drawingml/2006/compatibility"
       xmlns:p14="http://schemas.microsoft.com/office/powerpoint/2010/main"
       xmlns:p15="http://schemas.microsoft.com/office/powerpoint/2012/main"
       xmlns:ahyp="http://schemas.microsoft.com/office/drawing/2018/hyperlinkcolor">
<p:cSld>
<p:spTree>
<p:nvGrpSpPr>
  <p:cNvPr id="1" name="Group 1"/>
  <p:cNvGrpSpPr/>
  <p:nvPr/>
</p:nvGrpSpPr>
<p:grpSpPr>
  <a:xfrm>
    <a:off x="0" y="0"/>
    <a:ext cx="0" cy="0"/>
    <a:chOff x="0" y="0"/>
    <a:chExt cx="0" cy="0"/>
  </a:xfrm>
</p:grpSpPr>
"""

def slide_footer():
    return """</p:spTree>
</p:cSld>
<p:clrMapOvr>
  <a:masterClrMapping/>
</p:clrMapOvr>
</p:sld>
"""

def title_shape(sp_id, title_text, y=99000, h=535531, align="ctr", color="262626"):
    return f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="{sp_id}" name="Title {sp_id}"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr><p:ph type="title"/></p:nvPr>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="336000" y="{y}"/>
      <a:ext cx="11520000" cy="{h}"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
    <a:ln><a:noFill/></a:ln>
  </p:spPr>
  <p:txBody>
    <a:bodyPr anchorCtr="0" anchor="ctr" bIns="45700" lIns="91425" spcFirstLastPara="1" rIns="91425" wrap="square" tIns="45700">
      <a:noAutofit/>
    </a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr indent="0" lvl="0" marL="0" rtl="0" algn="{align}">
        <a:lnSpc><a:spcPct val="90000"/></a:lnSpc>
        <a:spcBef><a:spcPts val="0"/></a:spcBef>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:r>
        <a:rPr lang="en-US" sz="2600" b="1">
          <a:solidFill><a:srgbClr val="{color}"/></a:solidFill>
          <a:latin typeface="Calibri"/>
        </a:rPr>
        <a:t>{xml_escape(title_text)}</a:t>
      </a:r>
      <a:endParaRPr/>
    </a:p>
  </p:txBody>
</p:sp>
"""

def slide_num_shape(sp_id):
    return f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="{sp_id}" name="SlideNum {sp_id}"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr><p:ph idx="12" type="sldNum"/></p:nvPr>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="9517800" y="6573875"/>
      <a:ext cx="2743200" cy="365125"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
    <a:ln><a:noFill/></a:ln>
  </p:spPr>
  <p:txBody>
    <a:bodyPr anchorCtr="0" anchor="ctr" bIns="45700" lIns="91425" spcFirstLastPara="1" rIns="91425" wrap="square" tIns="45700">
      <a:noAutofit/>
    </a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr indent="0" lvl="0" marL="0" rtl="0" algn="r">
        <a:spcBef><a:spcPts val="0"/></a:spcBef>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
        <a:buNone/>
      </a:pPr>
      <a:fld id="{{00000000-1234-1234-1234-123412341234}}" type="slidenum">
        <a:rPr lang="en-US"/>
        <a:t>‹#›</a:t>
      </a:fld>
      <a:endParaRPr/>
    </a:p>
  </p:txBody>
</p:sp>
"""

def bullets_shape(sp_id, bullets, x=457200, y=914400, cx=11247120, cy=4600000, sz=1700, spcAft=1100):
    p_tags = []
    for b in bullets:
        # Check if bullet has prefix like 'Gap:' or 'Takeaway:' that can be bolded
        parts = b.split(": ", 1)
        if len(parts) == 2 and len(parts[0]) <= 25 and not parts[0].startswith("http"):
            lead, rest = parts[0] + ": ", parts[1]
            r_chunk = f"""<a:r>
        <a:rPr sz="{sz}" b="1" i="0"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>{xml_escape(lead)}</a:t>
      </a:r><a:r>
        <a:rPr sz="{sz}" b="0" i="0"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>{xml_escape(rest)}</a:t>
      </a:r>"""
        else:
            r_chunk = f"""<a:r>
        <a:rPr sz="{sz}" b="0" i="0"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr>
        <a:t>{xml_escape(b)}</a:t>
      </a:r>"""
            
        p_tags.append(f"""    <a:p>
      <a:pPr algn="l" marL="228600" indent="-228600">
        <a:lnSpc><a:spcPct val="105000"/></a:lnSpc>
        <a:spcAft><a:spcPts val="{spcAft}"/></a:spcAft>
        <a:buClr><a:srgbClr val="C00000"/></a:buClr>
        <a:buFont typeface="Arial"/>
        <a:buChar char="•"/>
      </a:pPr>
      {r_chunk}
    </a:p>""")
    
    body = "\n".join(p_tags)
    return f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="{sp_id}" name="TextBox {sp_id}"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="{x}" y="{y}"/>
      <a:ext cx="{cx}" cy="{cy}"/>
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

def callout_box(sp_id, text, x=457200, y=5500000, cx=11247120, cy=750000, bg="F2F2F2", text_color="C00000", sz=1700, bold=True):
    b_val = "1" if bold else "0"
    return f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="{sp_id}" name="Callout {sp_id}"/>
    <p:cNvSpPr/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="{x}" y="{y}"/>
      <a:ext cx="{cx}" cy="{cy}"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:solidFill><a:srgbClr val="{bg}"/></a:solidFill>
    <a:ln w="9525"><a:solidFill><a:srgbClr val="{bg}"/></a:solidFill></a:ln>
    <a:effectLst/>
  </p:spPr>
  <p:txBody>
    <a:bodyPr rtlCol="0" anchor="ctr" wrap="square" lIns="54864" rIns="54864" tIns="27432" bIns="27432"/>
    <a:lstStyle/>
    <a:p>
      <a:pPr algn="ctr"><a:spcAft><a:spcPts val="0"/></a:spcAft></a:pPr>
      <a:r>
        <a:rPr sz="{sz}" b="{b_val}" i="0">
          <a:solidFill><a:srgbClr val="{text_color}"/></a:solidFill>
          <a:latin typeface="Calibri"/>
        </a:rPr>
        <a:t>{xml_escape(text)}</a:t>
      </a:r>
    </a:p>
  </p:txBody>
</p:sp>
"""

def note_shape(sp_id, note_text, x=457200, y=6250000, cx=11247120, cy=320040, sz=1100):
    return f"""<p:sp>
  <p:nvSpPr>
    <p:cNvPr id="{sp_id}" name="Note {sp_id}"/>
    <p:cNvSpPr txBox="1"/>
    <p:nvPr/>
  </p:nvSpPr>
  <p:spPr>
    <a:xfrm>
      <a:off x="{x}" y="{y}"/>
      <a:ext cx="{cx}" cy="{cy}"/>
    </a:xfrm>
    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
    <a:noFill/>
  </p:spPr>
  <p:txBody>
    <a:bodyPr wrap="square" anchor="t" lIns="45720" rIns="45720" tIns="27432" bIns="27432">
      <a:spAutoFit/>
    </a:bodyPr>
    <a:lstStyle/>
    <a:p>
      <a:pPr algn="l">
        <a:lnSpc><a:spcPct val="105000"/></a:lnSpc>
        <a:spcAft><a:spcPts val="0"/></a:spcAft>
      </a:pPr>
      <a:r>
        <a:rPr sz="{sz}" b="0" i="0">
          <a:solidFill><a:srgbClr val="595959"/></a:solidFill>
          <a:latin typeface="Calibri"/>
        </a:rPr>
        <a:t>{xml_escape(note_text)}</a:t>
      </a:r>
    </a:p>
  </p:txBody>
</p:sp>
"""

def table_graphic_frame(gf_id, x, y, cx, cy, col_widths, headers, rows, highlight_last_col=False, highlight_row_idx=None, cell_sz=1300):
    grid_cols = "\n".join([f'      <a:gridCol w="{w}"/>' for w in col_widths])
    
    # Header row
    hdr_cells = []
    for h in headers:
        hdr_cells.append(f"""        <a:tc>
          <a:txBody>
            <a:bodyPr wrap="square"/><a:lstStyle/>
            <a:p><a:r><a:rPr sz="{cell_sz + 100}" b="1" i="0"><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>{xml_escape(h)}</a:t></a:r></a:p>
          </a:txBody>
          <a:tcPr marL="54864" marR="54864" marT="27432" marB="27432" anchor="ctr">
            <a:lnL w="0"><a:noFill/></a:lnL><a:lnR w="0"><a:noFill/></a:lnR><a:lnT w="0"><a:noFill/></a:lnT>
            <a:lnB w="6350"><a:solidFill><a:srgbClr val="BFBFBF"/></a:solidFill></a:lnB>
            <a:solidFill><a:srgbClr val="C00000"/></a:solidFill>
          </a:tcPr>
        </a:tc>""")
    hdr_xml = f"""    <a:tr h="450000">
{chr(10).join(hdr_cells)}
    </a:tr>"""
    
    row_xmls = [hdr_xml]
    for r_idx, row in enumerate(rows):
        is_high_row = (highlight_row_idx is not None and r_idx == highlight_row_idx)
        cell_xmls = []
        for c_idx, val in enumerate(row):
            is_hdr_col = (c_idx == 0)
            is_last_col = (c_idx == len(row) - 1)
            is_bold = is_hdr_col or is_high_row or (highlight_last_col and is_last_col)
            b_flag = "1" if is_bold else "0"
            
            fill_xml = '<a:noFill/>'
            if is_high_row:
                fill_xml = '<a:solidFill><a:srgbClr val="F2F2F2"/></a:solidFill>'
            elif highlight_last_col and is_last_col:
                fill_xml = '<a:solidFill><a:srgbClr val="F9F9F9"/></a:solidFill>'
            elif r_idx % 2 == 1:
                fill_xml = '<a:solidFill><a:srgbClr val="FAFAFA"/></a:solidFill>'
                
            cell_xmls.append(f"""        <a:tc>
          <a:txBody>
            <a:bodyPr wrap="square"/><a:lstStyle/>
            <a:p><a:r><a:rPr sz="{cell_sz}" b="{b_flag}" i="0"><a:solidFill><a:srgbClr val="262626"/></a:solidFill><a:latin typeface="Calibri"/></a:rPr><a:t>{xml_escape(val)}</a:t></a:r></a:p>
          </a:txBody>
          <a:tcPr marL="54864" marR="54864" marT="27432" marB="27432" anchor="ctr">
            <a:lnL w="0"><a:noFill/></a:lnL><a:lnR w="0"><a:noFill/></a:lnR><a:lnT w="0"><a:noFill/></a:lnT>
            <a:lnB w="6350"><a:solidFill><a:srgbClr val="D9D9D9"/></a:solidFill></a:lnB>
            {fill_xml}
          </a:tcPr>
        </a:tc>""")
        row_xmls.append(f"""    <a:tr h="450000">
{chr(10).join(cell_xmls)}
    </a:tr>""")
        
    all_rows = "\n".join(row_xmls)
    return f"""<p:graphicFrame>
  <p:nvGraphicFramePr>
    <p:cNvPr id="{gf_id}" name="Table {gf_id}"/>
    <p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr>
    <p:nvPr/>
  </p:nvGraphicFramePr>
  <p:xfrm>
    <a:off x="{x}" y="{y}"/>
    <a:ext cx="{cx}" cy="{cy}"/>
  </p:xfrm>
  <a:graphic>
    <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">
      <a:tbl>
        <a:tblPr firstRow="0" bandRow="0"/>
        <a:tblGrid>
{grid_cols}
        </a:tblGrid>
{all_rows}
      </a:tbl>
    </a:graphicData>
  </a:graphic>
</p:graphicFrame>
"""

print("Helper definitions loaded successfully.")
