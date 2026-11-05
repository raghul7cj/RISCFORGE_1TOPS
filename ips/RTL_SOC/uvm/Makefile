TEST     ?= soc_hello_test
PROG     ?= hello
SEED     ?= 1
CROSS    ?= riscv64-unknown-elf-
ARGS     ?=
COV      ?= 0
GUI      ?= 0

NAME     = $(TEST)_$(PROG)
SIM_OPTS = -uvm -sv -timescale 1ns/1ps -access +rwc -top tb_top -svseed $(SEED)

ifeq ($(COV),1)
SIM_OPTS += -coverage all -covoverwrite -covtest $(NAME)_$(SEED)
endif

ifeq ($(GUI),1)
SIM_OPTS += -gui
endif

REGRESS = \
  soc_hello_test:hello \
  soc_hello_test:uart_nofifo \
  soc_uart_echo_test:uart_echo \
  soc_gpio_test:gpio \
  soc_timer_test:timer \
  soc_spi_test:spi \
  soc_i2c_test:i2c \
  soc_core_test:mem \
  soc_core_test:mext \
  soc_core_test:trap \
  soc_core_test:lsu_hazard

all: run

sw:
	$(MAKE) -C sw PROG=$(PROG) CROSS=$(CROSS)

sw_all:
	for p in hello uart_nofifo uart_echo gpio timer spi i2c mem mext trap lsu_hazard; do \
	  $(MAKE) -C sw PROG=$$p CROSS=$(CROSS) || exit 1; \
	done

compile:
	xrun $(SIM_OPTS) -elaborate -f soc_ip.f -f tb.f -l compile.log

run: sw
	mkdir -p logs
	xrun $(SIM_OPTS) -f soc_ip.f -f tb.f \
	  +UVM_TESTNAME=$(TEST) +HEX=sw/$(PROG).hex $(ARGS) -l logs/$(NAME).log

regress: sw_all
	mkdir -p logs
	rm -f logs/summary.txt
	for t in $(REGRESS); do \
	  test=$${t%%:*}; prog=$${t##*:}; \
	  $(MAKE) --no-print-directory run TEST=$$test PROG=$$prog SEED=$(SEED) COV=$(COV) ARGS="$(ARGS)" > /dev/null 2>&1; \
	  log=logs/$${test}_$${prog}.log; \
	  if grep -q "UVM_ERROR :    0" $$log && grep -q "UVM_FATAL :    0" $$log; then \
	    echo "PASS $$test $$prog" | tee -a logs/summary.txt; \
	  else \
	    echo "FAIL $$test $$prog" | tee -a logs/summary.txt; \
	  fi; \
	done

cov_report:
	imc -execcmd "merge -overwrite cov_work/scope/* -out all; load -run cov_work/scope/all; report -summary -out logs/cov_summary.txt; exit"

clean:
	rm -rf xcelium.d xrun.history xrun.key waves.shm logs cov_work compile.log rtl_trace.log
	$(MAKE) -C sw clean

.PHONY: all sw sw_all compile run regress cov_report clean
