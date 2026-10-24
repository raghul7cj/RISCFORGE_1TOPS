run 400ns
puts "u_dut.apb_req[0] = [get_value /rf_mon_smoke_tb/u_dut/apb_req[0]]"
puts "apb_if.pwrite = [get_value /rf_mon_smoke_tb/u_mon/apb_if/pwrite]"
puts "apb_if.pstrb = [get_value /rf_mon_smoke_tb/u_mon/apb_if/pstrb]"
puts "apb_if.pwdata = [get_value /rf_mon_smoke_tb/u_mon/apb_if/pwdata]"
run 200ns
puts "u_dut.apb_req[0] at 600ns = [get_value /rf_mon_smoke_tb/u_dut/apb_req[0]]"
puts "apb_if.pwrite at 600ns = [get_value /rf_mon_smoke_tb/u_mon/apb_if/pwrite]"
puts "apb_if.pstrb at 600ns = [get_value /rf_mon_smoke_tb/u_mon/apb_if/pstrb]"
exit
