# ----------------------------------------
# Jasper Version Info
# tool      : Jasper 2025.06
# platform  : Linux 3.10.0-1160.119.1.el7.x86_64
# version   : 2025.06 FCS 64 bits
# build date: 2025.06.25 13:01:28 UTC
# ----------------------------------------
# started   : 2026-08-30 18:23:23 IST
# hostname  : vlsi.iiita.ac.in.(none)
# pid       : 27365
# arguments : '-style' 'windows' '-label' 'session_0' '-console' '//127.0.0.1:36090' '-data' 'AAAAinicY2RgYLCp////PwMYMD6A0Aw2jAyoAMRnQhUJbEChGRhYEZIgpSIMugzFDKUMBQypDEUMOQyZDHkMJUBxAThbD4iTgTwGBjYGAKZvDes=' '-bridge_url' '172.16.33.51:34470' '-proj' '/home/iiita/MALAY_SOC/rtl/spi/jg/jgproject/sessionLogs/session_0' '-init' '-hidden' '/home/iiita/MALAY_SOC/rtl/spi/jg/jgproject/.tmp/.initCmds.tcl' 'lint.tcl'
check_superlint -init
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
