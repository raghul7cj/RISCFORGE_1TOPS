# =============================================================================
# RISCFORGE 1TOPS — JasperGold Superlint Tcl Script
# =============================================================================
# Tool: Cadence JasperGold 2025.06 FCS 64-bit
# Top:  riscforge_soc_subsystem
# =============================================================================

clear -all

# Enable Superlint Rules across all domains (LINT, STRUCTURAL, CODINGSTYLE, AUTO_FORMAL, etc.)
config_rtlds -rule -enable -domain all

# Analyze and elaborate design
analyze -sv -f jg_soc.f
elaborate -top riscforge_soc_subsystem

# Clocks and Resets
clock clk_i
reset ~hard_rst_ni ~soft_rst_ni

# Initialize and extract Superlint checks
check_superlint -init
check_superlint -extract -top

# Output reports directory
file mkdir reports

# Dump Superlint reports
check_superlint -report -setup -file reports/superlint_setup.txt -force
check_superlint -report -summary -file reports/superlint_summary.txt -force
check_superlint -report -violation -detailed -verbose all -file reports/superlint_violations.txt -force
check_superlint -report -violation -order severity -file reports/superlint_violations_by_severity.txt -force
check_superlint -report -violation -csv -file reports/superlint_violations.csv -force
check_superlint -report -signoff -file reports/superlint_signoff.txt -force
check_superlint -report -signoff -html -file reports/superlint_signoff.html -force

puts "==============================================================="
puts "  JasperGold Superlint SoC Analysis Complete!                  "
puts "==============================================================="

exit -force

