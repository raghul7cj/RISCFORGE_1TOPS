# Sw - Software Subsystem (Legacy Reference Directory)

> [!NOTE]
> **CANONICAL FIRMWARE REPOSITORY LOCATION:**
> All active BSP files, unified peripheral drivers, linker scripts, and verification test suites have been consolidated under:
> **[`Verification/firmware/`](file:///C:/Users/cj/Desktop/1TOPS%20project/RISCFORGE_1TOPS-main/rtl/ips/Verification/firmware/)**
> 
> The contents of this directory (`Sw/`) are preserved as frozen historical reference material for Phase 0 closeout traceability. Do not add new tests or modify drivers in this directory; all new firmware development and CI builds must use `Verification/firmware/`.

## Architecture Specifications
- BootROM Base: `0x0000_0000` (64 Bytes = 16 words)
- ISRAM Base: `0x0001_0000` (32 KiB)
- DSRAM Base: `0x0002_0000` (32 KiB)
- APB Peripheral Window: `0x4000_0000`
