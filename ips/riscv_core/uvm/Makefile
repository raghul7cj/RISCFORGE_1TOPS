UNIT  ?= alu
TEST  ?= $(UNIT)_test
SEED  ?= 1
N     ?= 5000
SEEDS ?= 1 2 3
GUI   ?= 0

RTL = ../rtl
FILES_alu = $(RTL)/ALU.v alu/alu_pkg.sv
FILES_dec = $(RTL)/Control_Unit_Top.v $(RTL)/Main_Decoder.v $(RTL)/ALU_Decoder.v $(RTL)/opcode_check.v \
            $(RTL)/Sign_Extend.v dec/dec_pkg.sv
FILES_haz = $(RTL)/hazard_unit.v haz/haz_pkg.sv

OPTS = -uvm -sv -timescale 1ns/1ps -access +rwc -incdir $(UNIT) -top $(UNIT)_tb -svseed $(SEED) \
       -xmlibdirname xcelium_$(UNIT).d -coverage all -covoverwrite -covscope $(UNIT) -covtest $(TEST)_$(SEED)
ifeq ($(GUI),1)
OPTS += -gui
endif

REGRESS = alu:alu_test dec:dec_test dec:dec_illegal_test haz:haz_test
UNITS   = alu dec haz

all: run

run:
	mkdir -p logs
	xrun $(OPTS) $(FILES_$(UNIT)) +UVM_TESTNAME=$(TEST) +N=$(N) -l logs/$(TEST)_$(SEED).log < /dev/null

regress:
	@mkdir -p logs
	@rm -f logs/summary.txt
	@for t in $(REGRESS); do for s in $(SEEDS); do \
	  u=$${t%%:*}; tn=$${t##*:}; log=logs/$${tn}_$$s.log; rm -f $$log; \
	  $(MAKE) --no-print-directory run UNIT=$$u TEST=$$tn SEED=$$s N=$(N) > logs/$${tn}_$$s.make 2>&1; \
	  if [ -f $$log ] && grep -q "UVM_ERROR :    0" $$log && grep -q "UVM_FATAL :    0" $$log; then r=PASS; else r=FAIL; fi; \
	  echo "$$r $$tn seed $$s" >> logs/summary.txt; \
	  echo "$$r  $$tn  seed $$s  `grep -hE '\[(ALU|DEC|HAZ)\] (checked|legal:|illegal:)|\[COV\]' $$log 2>/dev/null | sed 's/.*\] //' | tr '\n' ' '`"; \
	  if [ $$r = FAIL ] && [ ! -f $$log ]; then tail -5 logs/$${tn}_$$s.make; fi; \
	done; done; \
	echo "DONE: `grep -c PASS logs/summary.txt` PASS, `grep -c FAIL logs/summary.txt` FAIL"

cov_report:
	@mkdir -p logs
	@for u in $(UNITS); do \
	  if [ -d cov_work/$$u ]; then \
	    imc -execcmd "merge -overwrite cov_work/$$u/* -out all; load -run cov_work/$$u/all; report -summary -out logs/cov_$$u.txt; exit" > logs/imc_$$u.log 2>&1; \
	    echo "== $$u: logs/cov_$$u.txt"; \
	  fi; \
	done

clean:
	rm -rf xcelium*.d xrun.history xrun.key waves.shm logs cov_work

.PHONY: all run regress cov_report clean
