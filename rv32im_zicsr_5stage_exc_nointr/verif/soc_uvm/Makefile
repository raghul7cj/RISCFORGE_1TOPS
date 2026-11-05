TEST     ?= soc_hello_test
PROG     ?= hello
SEED     ?= 1
VENDOR_F ?= vendor.f
ARGS     ?=

SIM_OPTS = -uvm -sv -timescale 1ns/1ps -access +rwc -top tb_top -svseed $(SEED)

all: run

sw:
	$(MAKE) -C sw PROG=$(PROG)

run: sw
	xrun $(SIM_OPTS) -f $(VENDOR_F) -f rtl.f -f tb.f \
	  +UVM_TESTNAME=$(TEST) +HEX=sw/$(PROG).hex $(ARGS) -l $(TEST).log

hello:
	$(MAKE) run TEST=soc_hello_test PROG=hello

echo:
	$(MAKE) run TEST=soc_uart_echo_test PROG=uart_echo

regress: hello echo

clean:
	rm -rf xcelium.d xrun.* *.log *.history *.key waves.shm
	$(MAKE) -C sw clean

.PHONY: all sw run hello echo regress clean
