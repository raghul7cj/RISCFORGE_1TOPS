clear -all
config_rtlds -rule -disable -domain {all}
config_rtlds -rule -enable -domain {LINT}

analyze -sv -f jg_file.f
elaborate -top apb_spi_master

clock HCLK
reset ~HRESETn

check_superlint -init
check_superlint -extract -top

file mkdir reports
check_superlint -report -violation -detailed -file reports/superlint_violations.txt -force
