compile: RISC_top_tb.v memfile.hex
	iverilog -o tb.vvp RISC_top_tb.v 
	
display: tb.vvp
	vvp tb.vvp	

waveform: 
	gtkwave RISC_Core.vcd	
	