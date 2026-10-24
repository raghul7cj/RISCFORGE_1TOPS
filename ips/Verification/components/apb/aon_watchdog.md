# AON Watchdog Scope Record

## Identity and test basis

- Master-plan reference: Section 15.8.
- IP: aon_timer, an AON watchdog IP with a TL-UL host interface.
- SoC state: specified but not integrated; no APB slot or SoC instance exists in the master plan configuration.

## Retained execution evidence

No qualifying SoC run is applicable or recorded in component-first runs 20261018_run01 and 20261019_run02. The master plan identifies this block as NOT_INTEGRATED and distinguishes its interface and clock domain from the six APB peripherals.

## Status and next evidence

Do not include this IP in the six-slot APB peripheral sign-off. If the standalone IP is in project scope, create a separate TL-UL/AON-clock verification record with a named standalone configuration and source-identified run.
