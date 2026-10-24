# =============================================================================
# JasperGold Superlint - GPIO (gpio_apb_wrap, via gpio_lint_top)
#
# Run from rtl/gpio-master, the same directory the Xcelium testbench runs from:
#   jg -superlint lint.tcl
#
# Two passes, each a complete run, each with its own report:
#   1. LINT domain only - the sign-off report, same rule set as the I2C flow
#        reports/gpio_superlint_lint.txt
#   2. All rule domains - diagnostic; shows what pass 1 filters out, including
#      violations counted in the extraction summary but not in the LINT report
#        reports/gpio_superlint_all_domains.txt
# =============================================================================

proc run_superlint {domain_cmds report} {
  clear -all

  # config_rtlds is rejected (ERTL043) until an app is initialised
  check_superlint -init

  foreach cmd $domain_cmds {
    eval $cmd
  }

  analyze -sv -f gpio_lint.f
  elaborate -top gpio_lint_top

  clock clk_i
  reset ~rst_ni

  check_superlint -extract -top
  check_superlint -report -violation -detailed -file $report -force
}

file mkdir reports

# Pass 1: LINT domain only
run_superlint {
  {config_rtlds -rule -disable -domain {all}}
  {config_rtlds -rule -enable -domain {LINT}}
} reports/gpio_superlint_lint.txt

# Pass 2: every rule domain
run_superlint {
  {config_rtlds -rule -enable -domain {all}}
} reports/gpio_superlint_all_domains.txt
