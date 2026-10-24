#!/bin/bash
# Compile every proof stage with the real RISC-V toolchain.
set -u
cd "/mnt/c/Users/cj/Desktop/1TOPS project/RISCFORGE_1TOPS-main/rtl/ips/Verification" || exit 1
mkdir -p build
RC=0
for t in stage1_hello stage2_watchdog stage3_monitor_count stage4_fault_inject stage5_reg_sweep stage6_polled_periph stage7_nested_irq; do
  echo "================ $t ================"
  riscv64-unknown-elf-gcc \
    -march=rv32im_zicsr -mabi=ilp32 -mcmodel=medlow -mno-relax \
    -O2 -g -Wall -Wextra -Wno-unused-parameter \
    -ffreestanding -nostdlib \
    -Itests/bsp -Itests/drivers \
    -T tests/bsp/link.ld \
    tests/bsp/crt0.s tests/bsp/trap_handler.s \
    tests/bsp/isr_dispatch.c tests/bsp/proof_activity.c \
    tests/drivers/uart_driver.c tests/drivers/timer_driver.c \
    tests/drivers/gpio_driver.c tests/drivers/i2c_driver.c \
    tests/drivers/spi_driver.c \
    "tests/suites/$t/main.c" \
    -o "build/$t.elf" 2>&1 | head -40
  if [ -f "build/$t.elf" ]; then
    echo "  -> ELF OK: $(riscv64-unknown-elf-size build/$t.elf | tail -1)"
  else
    echo "  -> BUILD FAILED"
    RC=1
  fi
done
echo "OVERALL_RC=$RC"
