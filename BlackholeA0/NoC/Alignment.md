# NoC Address Alignment

This document is shared with the Wormhole tree; see [`Alignment.md` in the Wormhole tree](../../WormholeB0/NoC/Alignment.md). The functionality is similar, but not identical, between Wormhole and Blackhole.

## Differences on Blackhole

Blackhole's NoC flits are 512 bits (64 bytes) rather than Wormhole's 256 bits (32 bytes), and data read from an "other address" (as the Wormhole page defines it, e.g. DRAM) is carried in the flit at its source address's offset within 64 bytes rather than 32. Hence in the table for when `NOC_AT_LEN_BE` contains a length, the two **C32** cells (data from other address, to L1 address or to other address) are instead **C64** on Blackhole:

* **C64:** The two addresses must be congruent mod 64, i.e. `SrcAddress % 64 == DstAddress % 64`.

For example, a read from DRAM into L1 needs the DRAM address and the L1 address congruent mod 64. Writes from L1 to DRAM are unchanged (**C16**).
