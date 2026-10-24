clear -all
check_superlint -init
config_rtlds -rule -enable -domain all
analyze -sv -f jg_soc.f
elaborate -top riscforge_soc_subsystem
clock clk_i
reset ~hard_rst_ni ~soft_rst_ni
check_superlint -extract -top
file mkdir reports
check_superlint -report -setup -file reports/superlint_setup.txt -force
check_superlint -report -summary -file reports/superlint_summary.txt -force
check_superlint -report -violation -detailed -verbose all -file reports/superlint_violations.txt -force
check_superlint -report -violation -order severity -file reports/superlint_violations_by_severity.txt -force
check_superlint -report -violation -csv -file reports/superlint_violations.csv -force
check_superlint -report -signoff -file reports/superlint_signoff.txt -force
check_superlint -report -signoff -html -file reports/superlint_signoff.html -force
puts "JasperGold Superlint SoC run completed."
exit -force
