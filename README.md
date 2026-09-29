# RV32IMAC RISC-V Core

A 5-stage pipelined RV32IMAC core in Verilog-2001, targeting FPGA.
Simulated with Icarus Verilog; waveforms viewed in GTKWave.

## Status
Core complete. All unit tests pass. Integration test runs a bare-metal
program correctly. See `docs/progress.md` for the full design report.


## Layout
- `rtl/` — synthesizable RTL
- `sim/` — testbenches and test programs
- `docs/` — design and verification documentation
