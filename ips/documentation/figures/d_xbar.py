"""fig03 -- axi_lite_xbar internals: independent read / write arbitration.

RTL read (axi_lite_xbar.sv + its two generated sub-blocks):
  rtl/ips/axi_lite_xbar/axi_lite_xbar.sv               top, fully connected
  rtl/ips/axi_lite_xbar/include/axi/axi_lite_mux.sv    one per far-side target
  rtl/ips/axi_lite_xbar/include/axi/axi_lite_demux.sv  one per initiator
  rtl/ips/axi_lite_xbar/tb_axi_lite_xbar.sv            Cfg: 2 x 3, MaxTrans 4
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass
import _figstyle as fs

TITLE = ("Read and write are arbitrated independently \u2014 a slave that stalls "
         "its read channel cannot block anyone else's write")
SUB = ("Read left to right:   initiator  \u2192  address decode  \u2192  demux  \u2192  crossbar wiring  \u2192  mux  \u2192  1-of-3 target fan-out.   "
       "Write path on top, read path below; the two grey insets are side logic, not on the datapath.")

# Light tint bands that group each direction of travel.  They carry no
# content of their own -- they only say "everything in this band belongs
# to the same direction", which is what the figure is about.
BAND_W_X, BAND_W_Y, BAND_W, BAND_W_H = 29.6, 38.8, 72.4, 19.8   # write path
BAND_R_X, BAND_R_Y, BAND_R_W, BAND_R_H = 29.6, 12.6, 72.4, 17.8  # read path
C_WRITE_BAND, C_READ_BAND = "#FBF0E4", "#E8F2FB"

CW = "#B45F06"          # write-path hue (peach family)
CB = "#B45F06"
CR = "#1F4E79"          # read-path hue (blue family)
CD = "#BF8F00"          # address decode (yellow)
CE = "#C00000"          # decode-error / fault

# ----------------------------------------------------------------- geometry
XI0, XI1 = 1.5, 22.0        # initiator port (one tall box)
XD0, XD1 = 30.0, 43.5       # addr_decode
XM0, XM1 = 47.0, 63.0       # axi_lite_demux
XC0, XC1 = 69.0, 75.0       # gen_xbar_slv_cross  (pure wiring)
XU0, XU1 = 80.0, 100.0      # axi_lite_mux
XB = 102.0                  # fan-out bar: mst_ports_req_o[0..2]
XR0, XR1 = 105.0, 123.5     # targets

WY0, WY1 = 42.6, 57.0       # write-half blocks
WT_Y = 58.4                 # write-half block title
RY0, RY1 = 16.0, 28.5       # read-half blocks
RT_Y = 29.9                 # read-half block title
MY0, MY1 = 31.8, 38.6       # mid band (insets)

L_AW, L_W, L_B = 55.4, 43.8, 39.6      # write lanes (AW fwd, W fwd, B ret)
L_AR, L_R = 24.2, 14.0                # read lanes  (AR fwd, R ret)
L_GAW, L_GAR = 49.6, 17.8             # arbiter-idx -> select-FIFO push wires
X_GAP1 = 26.0                          # annotation lane right of the initiator
Y_BAR0, Y_BAR1 = 13.0, 56.5

AW_RR = (80.5, 51.0, 54.6)            # mux rr_arb_tree (AW)   x0, y0, y1
AW_WF = (90.5, 51.0, 54.6)            # mux i_w_fifo
AW_BF = (90.5, 45.2, 48.0)            # mux i_b_fifo
AR_RR = (80.5, 19.4, 23.0)            # mux rr_arb_tree (AR)
AR_RF = (90.5, 19.4, 23.0)            # mux i_r_fifo
DM_WF = (48.0, 51.0, 54.6)            # demux i_w_fifo
DM_BF = (56.0, 45.2, 48.0)            # demux i_b_fifo
DM_RF = (48.0, 18.0, 23.0)            # demux i_r_fifo
X_SEL, X_SELM = 51.5, 84.25           # select-push taps
X_WSELM, X_WSEL = 94.75, 92.5         # response-FIFO taps (mux)
X_DSEL, X_DSELM = 59.25, 51.5         # response-FIFO taps (demux)

fig, ax = fs.slide(TITLE, SUB)
XW, YH = fs.canvas(ax)
fig._qaname = "fig03_axi_xbar_internals"

fs.block(ax, BAND_W_X, BAND_W_Y, BAND_W, BAND_W_H, "", kind="plain",
         ls="none", lw=0.0, box_alpha=C_WRITE_BAND, zorder=0)
fs.block(ax, BAND_R_X, BAND_R_Y, BAND_R_W, BAND_R_H, "", kind="plain",
         ls="none", lw=0.0, box_alpha=C_READ_BAND, zorder=0)

# ============================================================= layer 1: ports
# box bottom kept at 12.5 (not 8.0) so the card does not carry a ~8-unit dead
# area under its last text line; the R lane at L_R=14.0 still lands well above
# the bottom corner.
init = fs.block(ax, XI0, 12.5, XI1 - XI0, 45.5, "", kind="bus")
XIC = (XI0 + XI1) / 2
fs.label(ax, XIC, 55.6, "AXI-Lite initiator port i", fs=8.6, weight="bold",
         color=CR)
fs.label(ax, XIC, 53.7, "slv_ports_req_i[i]", fs=7.0, style="italic", color=CR)
fs.label(ax, XIC, 52.2, "slv_ports_resp_o[i]", fs=7.0, style="italic", color=CR)
fs.label(ax, XIC, 49.9, "write half", fs=7.4, weight="bold", color=CW)
for i, t in enumerate(["AW  AWADDR / AWVALID / AWREADY",
                       "W   WDATA WSTRB / WVALID WREADY",
                       "B   BRESP / BVALID / BREADY"]):
    fs.label(ax, 3.0, 48.1 - i * 1.85, t, fs=6.4, ha="left", color="#7B3F00")
fs.label(ax, 3.0, 43.1, "AW = write address,  W = write data,", fs=6.0,
         ha="left", color=fs.GREY, style="italic")
fs.label(ax, 3.0, 41.9, "B = write response", fs=6.0, ha="left",
         color=fs.GREY, style="italic")
fs.label(ax, XIC, 40.2, "read half", fs=7.4, weight="bold", color=CR)
for i, t in enumerate(["AR  ARADDR / ARVALID / ARREADY",
                       "R   RDATA RRESP / RVALID RREADY"]):
    fs.label(ax, 3.0, 38.4 - i * 1.85, t, fs=6.4, ha="left", color="#12395C")
fs.label(ax, 3.0, 34.8, "AR = read address,  R = read data", fs=6.0,
         ha="left", color=fs.GREY, style="italic")
fs.label(ax, 3.0, 33.6, "and read response", fs=6.0, ha="left",
         color=fs.GREY, style="italic")
fs.label(ax, XIC, 30.0, "generated × NoSlvPorts = 2", fs=7.4, weight="bold",
         color=CR)
fs.label(ax, XIC, 27.8, "one axi_lite_demux per initiator,", fs=6.4,
         style="italic", color=CR)
fs.label(ax, XIC, 26.3, "one axi_lite_mux per far-side target", fs=6.4,
         style="italic", color=CR)

# The figure's thesis, restated where the eye enters.
fs.block(ax, 3.0, 18.0, 17.5, 5.0, "", kind="plain", lw=0.9,
         box_alpha="#E9F1F9")
fs.label(ax, XIC, 21.3, "write path and read path", fs=6.4, weight="bold",
         color=fs.ACCENT)
fs.label(ax, XIC, 19.6, "share no buffer", fs=6.4, weight="bold",
         color=fs.ACCENT)

# Legend lives in the empty bottom-left corner, not inside the port card.
fs.legend_row(ax, 2.0, 9.0, [
    ("box", fs.S_WRITE, "write AW/W/B lane"),
    ("line", CR, "read AR/R lane"),
    ("box", fs.S_ADDR, "address decode"),
    ("box", "#EDEDED", "4-deep select FIFO"),
    ("box", fs.S_ALARM, "decode error"),
], fs=6.0, gap=0.35, vertical=True)


# ---- cross: pure wiring, one generate block, no logic of its own
fs.block(ax, XC0, 12.4, XC1 - XC0, 45.6, "", kind="plain", ls="--", lw=1.0,
         box_alpha="#F7FAFD", zorder=1)
fs.label(ax, (XC0 + XC1) / 2, 31.9, "gen_xbar_slv_cross", fs=6.6,
         weight="bold", color="#4F7391", rot=90)

# ---- targets.  NB the RTL names the *initiator* side slv_ports_* and the far
#      side mst_ports_* -- inverted vs. the AXI convention.
fs.block(ax, XR0, 49.4, XR1 - XR0, 8.6, "mst_ports_req_o[0]", kind="mem",
         sub="IDRAM  (instruction RAM)\n0x0000_0000", sub_fs=7.0)
fs.block(ax, XR0, 41.8, XR1 - XR0, 6.8, "mst_ports_req_o[1]", kind="mem",
         sub="DDRAM  (data RAM)\n0x0001_0000", sub_fs=7.0)
fs.block(ax, XR0, 13.0, XR1 - XR0, 26.0, "", kind="periph")
XRC = (XR0 + XR1) / 2
fs.label(ax, XRC, 37.2, "mst_ports_req_o[2]", fs=8.4, weight="bold",
         color="#1E5B2A")
fs.label(ax, XRC, 34.6, "axi_lite_to_apb bridge", fs=7.2, style="italic",
         color="#1E5B2A")
for i, t in enumerate(["APB0 I2C     0x4000_0000", "APB1 Timer0  0x4000_1000",
                       "APB2 UART    0x4000_2000", "APB3 GPIO    0x4000_3000"]):
    fs.label(ax, XRC, 32.2 - i * 2.0, t, fs=6.9, color="#1E5B2A")
for i, t in enumerate(["APB4 SPI     0x4000_4000",
                       "APB5 Timer1  0x4000_5000"]):
    fs.label(ax, XRC, 22.4 - i * 2.0, t, fs=6.9, color="#1E5B2A")
fs.label(ax, XRC, 17.4, "PSEL = APB slave select", fs=6.4, style="italic",
         color="#1E5B2A")
fs.label(ax, XRC, 15.6, "PENABLE = APB strobe", fs=6.4, style="italic",
         color="#1E5B2A")
fs.label(ax, XRC, 14.2, "addresses here are this testbench's own",
         fs=6.0, style="italic", color=fs.GREY)

# solid grey fan-out bar.  fs.bus() paints a white core inside the bar, which on
# a white page reads as two separate grey wires -> use a plain thick line.
fs.wire(ax, (XB, Y_BAR0), (XB, Y_BAR1), color=fs.GREY, lw=5.0, arrow=False,
        zorder=2)
fs.label(ax, XB + 0.6, 10.2, "1-of-3\ntarget select", fs=6.2, weight="bold",
         color="#404040")

# ============================================== layer 2: decode / demux / mux
fs.block(ax, XD0, 52.4, XD1 - XD0, 5.8, "i_axi_aw_decode", kind="addr",
         fs=8.0, bold=True)
fs.label(ax, (XD0 + XD1) / 2, 51.1, "addr_decode \u2192 dec_aw", fs=6.6,
         color="#7F6000")
fs.block(ax, XD0, 21.3, XD1 - XD0, 5.8, "i_axi_ar_decode", kind="addr",
         fs=8.0, bold=True)
fs.label(ax, (XD0 + XD1) / 2, 20.0, "addr_decode \u2192 dec_ar", fs=6.6,
         color="#7F6000")

# ---- one demux instance per initiator, drawn as two independent halves
for yy, h, kind, cap, col in ((WY0, WY1 - WY0, "write", "write", CB),
                              (RY0, RY1 - RY0, "req", "read", CR)):
    fs.block(ax, XM0, yy, XM1 - XM0, h, "", kind=kind,
             box_alpha="#FEF7F1" if kind == "write" else "#F4F9FE",
             lw=1.0, ls="--", zorder=1)
    fs.label(ax, (XM0 + XM1) / 2, WT_Y if kind == "write" else RT_Y,
             "i_axi_lite_demux  (%s half)" % cap, fs=8.2, weight="bold", color=col)

# ---- one mux instance per far-side target, drawn as two independent halves
for yy, h, kind, cap, col in ((WY0, WY1 - WY0, "write", "write", CB),
                              (RY0, RY1 - RY0, "req", "read", CR)):
    fs.block(ax, XU0, yy, XU1 - XU0, h, "", kind=kind,
             box_alpha="#FEF7F1" if kind == "write" else "#F4F9FE",
             lw=1.0, ls="--", zorder=1)
    fs.label(ax, (XU0 + XU1) / 2, WT_Y if kind == "write" else RT_Y,
             "i_axi_lite_mux  (%s half)" % cap, fs=8.2, weight="bold", color=col)


def fifo(r, name, hue, w=7.0, dep="4 deep"):
    x0, y0, y1 = r
    fs.block(ax, x0, y0, w, y1 - y0, name, kind="mux", fs=7.4, bold=True,
             tc=hue, sub=dep, sub_fs=6.4)


fs.label(ax, (XM0 + XM1) / 2, 26.8, "one per initiator", fs=6.4,
         style="italic", color=CR)
fs.label(ax, 86.0, 26.8, "one per target  \u00d7 3", fs=6.4,
         style="italic", color=CR)
fs.label(ax, 55.0, 43.4, "one per initiator", fs=6.4,
         style="italic", color=CB)
fs.label(ax, 86.0, 43.4, "one per target  \u00d7 3", fs=6.4,
         style="italic", color=CB)

fifo(DM_WF, "i_w_fifo", CB)
fifo(DM_BF, "i_b_fifo", CB, w=6.5)
fifo(DM_RF, "i_r_fifo", CR)
fifo(AW_WF, "i_w_fifo", CB, w=8.5)
fifo(AW_BF, "i_b_fifo", CB, w=8.5)
fifo(AR_RF, "i_r_fifo", CR, w=8.5)
for r, sub, hue in ((AW_RR, "AW grant", CB), (AR_RR, "AR grant", CR)):
    x0, y0, y1 = r
    fs.block(ax, x0, y0, 7.5, y1 - y0, "rr_arb_tree", kind="ctrl", fs=7.2,
             bold=True, tc=hue, sub=sub, sub_fs=6.4)

# ============================================ layer 3: write-path wires (peach)
def wf(p0, p1, via=None, lw=1.8, **kw):
    fs.wire(ax, p0, p1, via=via, color=CB, lw=lw, **kw)


def rf(p0, p1, via=None, lw=1.8, **kw):
    fs.wire(ax, p0, p1, via=via, color=CR, lw=lw, **kw)


def onw(x, y, s, c=None, fs_=6.6, pad=0.9):
    fs.onwire(ax, x, y, s, fs=fs_, color=c or CB, ec=c or "#E8C4A8", pad=pad)


# --- AW : decode -> demux -> cross -> rr_arb_tree -> i_w_fifo -> target fan-out
wf((XI1, L_AW), (XD0, L_AW))
wf((XD1, L_AW), (XM0, L_AW))
onw(X_GAP1, L_AW, "AWVALID \u0026\n!w_fifo_full", fs_=6.2, pad=0.35)
wf((XM1, L_AW), (XC0, L_AW))
onw(66.0, L_AW, "AW")
wf((XC1, L_AW), (X_SELM, L_AW), via=[(X_SELM, L_AW)])
wf((X_SELM, L_AW), (X_SELM, AW_RR[2]))
wf((X_SELM, L_GAW), (X_WSEL, L_GAW), via=[(X_SELM, L_GAW)])
wf((X_WSEL, L_GAW), (X_WSEL, AW_WF[1]))
onw((X_SELM + X_WSEL) / 2, L_GAW, "aw_select", fs_=6.0)
wf((X_WSEL, AW_WF[2]), (XB, L_AW), via=[(X_WSEL, L_AW)])
wf((X_SEL, L_AW), (X_SEL, DM_WF[2]))
onw((X_SEL + 55.0) / 2 + 2.0, L_AW, "slv_aw_select", fs_=6.2, pad=0.6)

# --- W : straight through the mux, gated by w_select
wf((XI1, L_W), (XM0, L_W))
wf((XM1, L_W), (XC0, L_W))
onw(66.0, L_W, "W")
wf((XC1, L_W), (XU0, L_W))
wf((XU1, L_W), (XB, L_W))
wf((X_WSELM, L_B), (X_WSELM, AW_BF[1]))

# --- B : write response comes back through i_b_fifo (b_select)
wf((XB, L_B), (XI1, L_B))
onw(X_GAP1, L_B, "b_valid \u0026\nb_select", fs_=6.2, pad=0.35)
wf((X_DSEL, DM_BF[1]), (X_DSEL, L_B))

# --- target fan-out taps
for ty in (54.0, 45.6, 19.0):
    fs.wire(ax, (XB, ty), (XR0, ty), color=fs.GREY, lw=1.8)


# ============================================= layer 3b: read-path wires (blue)
rf((XI1, L_AR), (XD0, L_AR))
rf((XD1, L_AR), (XM0, L_AR))
onw(X_GAP1, L_AR, "ARVALID \u0026\n!r_fifo_full", fs_=6.2, pad=0.35, c=CR)
rf((XM1, L_AR), (XC0, L_AR))
onw(66.0, L_AR, "AR", c=CR)
rf((XC1, L_AR), (X_SELM, L_AR), via=[(X_SELM, L_AR)])
rf((X_SELM, L_AR), (X_SELM, AR_RR[2]))
rf((X_SELM, L_GAR), (X_WSEL, L_GAR), via=[(X_SELM, L_GAR)])
rf((X_WSEL, L_GAR), (X_WSEL, AR_RF[1]))
onw((X_SELM + X_WSEL) / 2, L_GAR, "ar_select", fs_=6.0, c=CR)
rf((X_WSEL, AR_RF[2]), (XB, L_AR), via=[(X_WSEL, L_AR)])
rf((X_SEL, L_AR), (X_SEL, DM_RF[2]))
onw((X_SEL + 55.0) / 2 + 2.0, L_AR, "slv_ar_select", fs_=6.2, pad=0.6, c=CR)

# --- R : read response comes back through i_r_fifo (r_select)
rf((XB, L_R), (XI1, L_R))
onw(X_GAP1, L_R, "r_valid \u0026\nr_select", fs_=6.2, pad=0.35, c=CR)
rf((X_WSELM, L_R), (X_WSELM, AR_RF[1]))
rf((X_DSELM, DM_RF[1]), (X_DSELM, L_R))


# ============================== layer 4: mid-band insets (nothing crosses them)
fs.block(ax, 24.0, MY0, 44.0, MY1 - MY0, "", kind="plain", ls="--", lw=1.0,
         box_alpha="#FCFCFC", zorder=1)
fs.label(ax, 25.0, MY1 - 1.4,
         "side logic — AW arbitration-lock FSM, inside i_axi_lite_mux",
         fs=7.4, weight="bold", color=fs.GREY, ha="left")
fs.block(ax, 25.0, MY0 + 1.6, 20.0, 3.0, "S0 : lock_aw_valid_q = 0", kind="write",
         fs=7.0, bold=True, sub="free \u2014 a new AW may be granted", sub_fs=6.2)
fs.block(ax, 49.0, MY0 + 1.6, 18.0, 3.0, "S1 : lock_aw_valid_q = 1", kind="write",
         fs=7.0, bold=True, sub="held \u2014 AW is re-sent", sub_fs=6.2)
fs.wire(ax, (45.0, MY0 + 4.0), (49.0, MY0 + 4.0), color=CB, lw=1.6)
fs.wire(ax, (49.0, MY0 + 2.6), (45.0, MY0 + 2.6), color=CB, lw=1.6)
fs.label(ax, 47.0, MY0 + 1.0,
         "S0\u2192S1 : aw_valid \u0026 !mst_aw_ready      S1\u2192S0 : mst_aw_ready",
         fs=6.2, color="#7B3F00")

fs.block(ax, 76.0, MY0, 23.0, MY1 - MY0, "", kind="plain", ls="--", lw=1.0,
         box_alpha="#FDF6F6", zorder=1)
fs.label(ax, 77.0, MY1 - 1.4, "side logic — decode-error loop",
         fs=7.4, weight="bold", color=CE, ha="left")
fs.block(ax, 77.0, MY0 + 1.6, 10.0, 3.0, "i_dec_err_conv", kind="alarm",
         fs=6.8, bold=True, sub="axi_lite_to_axi", sub_fs=6.0)
fs.block(ax, 87.6, MY0 + 1.6, 10.4, 3.0, "i_axi_err_slv", kind="alarm",
         fs=6.8, bold=True, sub="RESP_DECERR", sub_fs=6.0)
fs.wire(ax, (87.0, MY0 + 4.0), (87.6, MY0 + 4.0), color=CE, lw=1.6)
fs.wire(ax, (87.6, MY0 + 2.6), (87.0, MY0 + 2.6), color=CE, lw=1.6)
fs.label(ax, 87.5, MY0 + 1.0,
         "per initiator:  dec error → idx = NoMstPorts",
         fs=6.2, color="#8B0000")

# ============================ layer 5: policy notes, budgets, legend, footer
fs.note(ax, 33.0, 2.6, 19.0, 5.2,
        "RTL naming is inverted:\ninitiator = slv_ports_*_i/o,\n"
        "far side = mst_ports_*_o/i,\naddr_map_i : 3 rules",
        fs=6.0, pad_y=0.5, valign="center")

fs.note(ax, 53.0, 2.6, 19.0, 5.2,
        "rr_arb_tree = ROUND-ROBIN,\none tree per direction.\n"
        "No fixed priority order:\nthe last grant is served last.",
        fs=6.0, pad_y=0.5, valign="center")

fs.note(ax, 73.0, 2.6, 19.0, 5.2,
        "i_w/i_b/i_r_fifo = fifo_v3,\nDEPTH = MaxTrans = 4.\n"
        "spill_register.Bypass = 1\non all 5 channels (NO_LATENCY)",
        fs=6.0, pad_y=0.5, valign="center")

fs.eqbox(ax, 33.0, 8.6, 66.0, 3.6,
         "aw_ready = rr_arb_tree.AW.grant \u0026 !w_fifo_full        "
         "ar_ready = rr_arb_tree.AR.grant \u0026 !r_fifo_full\n"
         "two separate 4-deep select FIFOs  \u21d2  a full read buffer "
         "never removes aw_valid, and vice versa",
         fs=6.8)

fs.footer(fig, "Independent read/write arbitration is what removes head-of-line "
              "blocking: the AW grant is gated only by i_w_fifo and the AR grant "
              "only by i_r_fifo, so a target that stalls RDATA cannot hold up a "
              "store to any other target \u2014 no shared buffer couples the two "
              "directions.")

fs.pad_limits(ax, 0.055)

if __name__ == "__main__":
    fs.qa_report(fig)
    fs.save(fig, "fig03_axi_xbar_internals.png")
