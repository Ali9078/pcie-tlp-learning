# PCIe TLP Parser/Deparser — Learning Implementation

This repository contains my independent implementation of two core
modules from the GSoC 2026 project "P4-based PCIe TLP Processing
Framework" (p4lang/gsoc Project 2.3).

## Purpose

These are **learning artifacts** built to understand the design
decisions involved in parsing and constructing PCIe Transaction Layer
Packets (TLPs) at the RTL level. They are not intended to replace or
compete with the mentor's reference implementation at
[iHalt10/pcie_subsystem](https://github.com/iHalt10/pcie_subsystem),
which I studied carefully before implementing my own versions.

## What I learned building these

**cq_parser:** The non-obvious challenge is beat-0 payload alignment —
the first AXI-Stream beat contains both the TLP header and the start of
the payload, so the header bytes must be stripped before forwarding to
downstream logic. I also learned why `tready` in TRANSFER_PAYLOAD must
be tied to the downstream consumer's ready signal rather than held high.

**rq_deparser:** The inverse challenge — beat 0 must combine the 16-byte
TLP header in tdata[127:0] with the first 48 bytes of payload in
tdata[511:128] in a single beat. The module cannot output anything until
the first payload beat is available, which requires careful FSM design.

## Modules

| Module | Description |
|---|---|
| `rtl/cq_parser.v` | Decodes 3DW/4DW Memory Read/Write TLP headers from PCIe IP CQ AXI-Stream port |
| `rtl/rq_deparser.v` | Constructs 4DW Memory Write TLPs on PCIe IP RQ AXI-Stream port |

## Known limitations

- cq_parser: PARSE_HEADER state is defined but unused (IDLE transitions
  directly to TRANSFER_PAYLOAD)
- cq_parser testbench: Test 2 has a DW0 encoding bug (being fixed)
- rq_deparser testbench: prints raw DW values for visual inspection;
  automated PASS/FAIL checks to be added
