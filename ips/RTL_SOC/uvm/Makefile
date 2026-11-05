TEST     ?= soc_hello_test
PROG     ?= hello
SEED     ?= 1
CROSS    ?= riscv64-unknown-elf-
ARGS     ?=
COV      ?= 0
GUI      ?= 0

NAME     = $(TEST)_$(PROG)
SIM_OPTS = -uvm -sv -timescale 1ns/1ps -access +rwc -top tb_top -svseed $(SEED)
FLASH_MODEL = ../../spi_slave_infinion/S25fs512s/model/s25fs512s.sv

ifeq ($(COV),1)
SIM_OPTS += -coverage all -covoverwrite -covtest $(NAME)_$(SEED)
endif

ifeq ($(GUI),1)
SIM_OPTS += -gui
endif

PROGS = hello uart_nofifo uart_echo gpio timer spi i2c mem mext trap lsu_hazard \
        isa mem_march mem_fault irq warm_reset timer_full uart_full i2c_full spi_full csr \
        uart_modes uart_err spi_more gpio_full i2c_more rand1 rand2 rand3 rand4 \
        irq_all uart_more spi_more2 i2c_more2 bus_fault fetch_fault flash_data

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
  soc_core_test:lsu_hazard \
  soc_core_test:isa \
  soc_core_test:mem_march \
  soc_fault_test:mem_fault \
  soc_irq_test:irq \
  soc_warm_reset_test:warm_reset \
  soc_timer_full_test:timer_full \
  soc_uart_full_test:uart_full \
  soc_i2c_full_test:i2c_full \
  soc_spi_full_test:spi_full \
  soc_core_test:csr \
  soc_uart_modes_test:uart_modes \
  soc_uart_err_test:uart_err \
  soc_spi_more_test:spi_more \
  soc_gpio_full_test:gpio_full \
  soc_i2c_more_test:i2c_more \
  soc_core_test:rand1 \
  soc_core_test:rand2 \
  soc_core_test:rand3 \
  soc_core_test:rand4 \
  soc_irq_all_test:irq_all \
  soc_uart_more_test:uart_more \
  soc_spi_more2_test:spi_more2 \
  soc_i2c_more2_test:i2c_more2 \
  soc_bus_fault_test:bus_fault \
  soc_core_test:fetch_fault \
  soc_hard_reset_test:warm_reset \
  flash:hello \
  flash:flash_data

all: run

sw:
	$(MAKE) -C sw PROG=$(PROG) CROSS=$(CROSS)

sw_all:
	for p in $(PROGS); do \
	  $(MAKE) -C sw PROG=$$p CROSS=$(CROSS) || exit 1; \
	done

compile:
	xrun $(SIM_OPTS) -elaborate -f soc_ip.f -f tb.f -l compile.log

run: sw
	mkdir -p logs
	xrun $(SIM_OPTS) -f soc_ip.f -f tb.f \
	  +UVM_TESTNAME=$(TEST) +HEX=sw/$(PROG).hex $(ARGS) -l logs/$(NAME).log

flash: TEST = soc_flash_boot_test
flash: sw
	mkdir -p logs
	cat sw/$(PROG).hex `test -f sw/$(PROG).dhex && echo sw/$(PROG).dhex` | awk '{print substr($$0,7,2); print substr($$0,5,2); print substr($$0,3,2); print substr($$0,1,2)}' > flash.mem
	xrun $(SIM_OPTS) +define+FLASH_BOOT +define+FW_WORDS=$$(wc -l < sw/$(PROG).hex) \
	  +define+FW_DATA=$$(test -f sw/$(PROG).dhex && wc -l < sw/$(PROG).dhex || echo 0) \
	  -f soc_ip.f $(FLASH_MODEL) -f tb.f \
	  +UVM_TESTNAME=soc_flash_boot_test $(ARGS) -l logs/flash_$(PROG).log

regress: sw_all
	mkdir -p logs
	rm -f logs/summary.txt
	for t in $(REGRESS); do \
	  test=$${t%%:*}; prog=$${t##*:}; \
	  if [ $$test = flash ]; then \
	    $(MAKE) --no-print-directory flash PROG=$$prog SEED=$(SEED) COV=$(COV) ARGS="$(ARGS)" > /dev/null 2>&1; \
	  else \
	    $(MAKE) --no-print-directory run TEST=$$test PROG=$$prog SEED=$(SEED) COV=$(COV) ARGS="$(ARGS)" > /dev/null 2>&1; \
	  fi; \
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
	rm -rf xcelium.d xrun.history xrun.key waves.shm logs cov_work compile.log rtl_trace.log flash.mem
	$(MAKE) -C sw clean

.PHONY: all sw sw_all compile run flash regress cov_report clean
