#!/bin/bash
# Simple wrapper script to run individual simulations and dump waveforms

python3 "$(dirname "$0")/run_debug_sim.py" "$@"
