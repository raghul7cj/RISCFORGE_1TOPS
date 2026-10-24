## 2026-10-01T21:00:09Z
You are spec_miner_survey_2.
Working directory: c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\spec_miner_survey_2
Read your task in DISPATCH.md in your working directory.
MANDATORY: Read ORIGINAL_REQUEST.md at c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\.agents\teamwork\ORIGINAL_REQUEST.md.
Also inspect c:\Users\cj\Desktop\1TOPS project\RISCFORGE_1TOPS-main\rtl\ips\AGENTS.md for the fast routing map.
Inspect documentation/ (e.g. RISCFORGE SoC Architecture.html, RISCFORGE IRQ Architecture.html), Sw/soc_spec.md, and key peripheral RTLs.
Mine and extract exact register specifications, memory maps, peripheral registers (RW, RO, W1C, atomic SET/CLEAR/TOGGLE semantics), and interrupt architecture for RISCFORGE SoC.
Investigate:
1. Peripheral register maps: APB[0] I2C, APB[1] Timer 0, APB[2] UART, APB[3] GPIO, APB[4] SPI Master, APB[5] Timer 1, plus AON Timer and CLIC/Interrupt controller.
2. Register access semantics: RW, RO, W1C, atomic alias offsets (SET, CLEAR, TOGGLE) if supported.
3. Interrupt specification: 2-level priority class interrupt arbitration, interrupt lines, preemption rules, vector/direct mode, shadow stack / nested trap expectations.
4. Reference model architecture: requirements for peripheral register predictor and interrupt predictor.
Deliver your full findings in handoff.md in your working directory, update progress.md, and send a completion message back.
