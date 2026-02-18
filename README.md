# RISCFORGE_1TOPS
rtl to gds git common repo , please have a branch yourself andupdate main branch weekly or when needed

# Maintain/ Create structure like this
```text
├── docs/               # Architecture specs, memory maps, and sign-off reports
├── rtl/                # Verilog/SystemVerilog source files
│   ├── core/           # Main logic
│   └── common/         # Standard cells, clock headers, etc.
├── dv/                 # Design Verification (Testbenches, UVM, etc.)
├── constraints/        # SDC files (timing), UPF (power), and I/O placement
├── scripts/            # Automation scripts (Makefile, Python, Tcl)
├── flows/              # Tool-specific configurations (OpenLane, Genus, Innovus)
│   ├── synthesis/
│   └── pnr/
├── lib/                # PDK-specific files (LEF, LIB, GDS - often gitignored)
├── results/            # Final outputs (GDSII, OASIS, Netlists)
└── README.md           # Instructions on how to run the flow```
