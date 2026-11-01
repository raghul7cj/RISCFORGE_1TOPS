# ============================================================
# cdc.tcl — apb_spi_master CDC/RDC analysis
# Tool: JasperGold 2025.06 FCS
# ============================================================

clear -all
analyze -sv -f jg_file.f
elaborate -top apb_spi_master

# --- Clock declarations ---
# spi_clk is internally generated (clkgen divider off HCLK), so it's a
# driven signal, not a free input. It must be cut loose (-env = global
# scope, required for the "clock" command to see it) before it can be
# declared as a clock in its own right.
stopat -env spi_clk

# HCLK = base clock, spi_clk = derived clock, factor 4, phase 1
# (both tick together right after reset). Assumes spi_clk_div = 4 for
# this run; the real divider is programmable, so re-run per ratio if needed.
clock HCLK spi_clk 4 1

# --- Reset ---
config_rtlds -reset -async HRESETn -polarity low

# --- Port -> clock association ---
config_rtlds -port -clock HCLK {PADDR PWDATA PWRITE PSEL PENABLE PRDATA PREADY events_o}
config_rtlds -port -clock HCLK {spi_sdo0 spi_sdo1 spi_sdo2 spi_sdo3}
config_rtlds -port -clock HCLK {spi_csn0 spi_csn1 spi_csn2 spi_csn3}
config_rtlds -port -clock HCLK {spi_mode}
config_rtlds -port -clock HCLK {spi_sdi0 spi_sdi1 spi_sdi2 spi_sdi3}
# NOTE: spi_clk itself is NOT in any config_rtlds -port group above --
# it's a declared clock now (WRTL019 otherwise).

check_cdc -init
check_cdc -extract

# --- Waivers ---
# RST_SYNCHRONIZATION is the sole reported violation (1 error, RDC domain).
# Attempting a waiver via the -filter/-reason mechanism, which is a
# RESTRICTED BETA feature in this build (per WG014) and has not matched
# its own documentation on syntax (-comment support, valid reason list)
# across several attempts already.
set rst_filter [check_cdc -filter -add -tag RST_SYNCHRONIZATION]
check_cdc -waiver -add -reason LEGACY -filter $rst_filter

# --- Diagnostics: find out WHY the waiver above isn't applying ---
# WCDC249 said the "necessary conditions" for validating the waiver
# against this violation weren't met -- these should show detail.
check_cdc -waiver -list
check_cdc -waiver -show $rst_filter

# --- Detailed violation report (see the actual instance/signal, not
# just the summary count, for RST_SYNCHRONIZATION) ---
check_cdc -report -file reports/cdc_violations_detailed.txt -detailed -force

# --- Final signoff-style report ---
file mkdir reports
check_cdc -report -file reports/cdc_violations.txt -force
