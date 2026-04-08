# NoC Address Alignment

NoC requests have various address alignment requirements, with the exact requirements depending on:
* The type of request
* The kind of source address (or more generally, where the data comes from)
* The kind of destination address (or more generally, where the data goes to)

Violations of the alignment requirements result in UndefinedBehavior.

## When `NOC_AT_LEN_BE` contains a length

This applies to all kinds of read request, and also to write requests which have both of `NOC_CMD_WR_BE=false` and `NOC_CMD_WR_INLINE=false`.

||Data to<br/>MMIO address|Data to<br/>L1 address|Data to<br/>other address|Data to<br/>host via PCIe|
|---|---|---|---|---|
|**Data from MMIO address**|AL=4|AL≤4 and C4|AL≤4 and C4|AL≤4|
|**Data from L1 address**|AL=4 and C16|C16|C16|Any|
|**Data from other address**|AL=4 and C16|C32|C32|Any|
|**Data from host via PCIe**|AL=4|Any|Any|N/A|

Meaning of table cells:
* **Any:** No restrictions (at least for x86 / x86-64 hosts).
* **AL=4:** Addresses (where present) must be 4-byte aligned. Length must be 4.
* **AL≤4:** Combination of address and length must not cross an aligned 4-byte boundary, i.e. `Length ≤ 4 - (Address % 4)`.
* **C4:** The two addresses must be congruent mod 4, i.e. `SrcAddress % 4 == DstAddress % 4`.
* **C16:** The two addresses must be congruent mod 16, i.e. `SrcAddress % 16 == DstAddress % 16`.
* **C32:** The two addresses must be congruent mod 32, i.e. `SrcAddress % 32 == DstAddress % 32`.
* **N/A:** Not possible.

In Tensix tiles and Ethernet tiles, addresses are a mixture of MMIO and L1. L1 addresses are those `< 0xFF00_0000`, and MMIO addresses are those `≥ 0xFF00_0000`.

In other types of tile, all addresses are other addresses. If an AXI/APB bridge is crossed in order to get to the address, then the address must be 4-byte aligned.

## When `NOC_AT_LEN_BE` contains a byte enable mask

This applies to write requests with `NOC_CMD_WR_BE=true` or `NOC_CMD_WR_INLINE=true` (or both).

||Data to<br/>MMIO address|Data to<br/>L1 address|Data to<br/>other address|
|---|---|---|---|
|**Data from MMIO address**|DA4 and SA4|DA32 and SA4|DA32 and SA4|
|**Data from L1 address**|DA4 and C16|DA32 and SA32|DA32 and SA32|
|**Inline data from `NOC_AT_DATA`**|DA4|DA16|N/A|

Meaning of table cells:
* **C16:** The two addresses must be congruent mod 16, i.e. `SrcAddress % 16 == DstAddress % 16`.
* **DA4:** Destination address must be 4-byte aligned. Byte-enable mask is ignored; a 4-byte write is always performed.
* **DA16:** Destination address must be 16-byte aligned. If not, it'll be rounded down to 16. Up to two writes are performed to the same aligned 16-byte range using the same data: one write using the low 16 bits of the byte enable mask, another using the high 16 bits.
* **DA32:** Destination address must be 32-byte aligned. All 32 bits of the byte enable mask are used to select the written bytes.
* **SA4:** Source address must be 4-byte aligned. A 4-byte read will be performed, and then the value broadcasted.
* **SA32:** Source address must be 32-byte aligned.
* **N/A:** Not possible.

In Tensix tiles and Ethernet tiles, addresses are a mixture of MMIO and L1. L1 addresses are those `< 0xFF00_0000`, and MMIO addresses are those `≥ 0xFF00_0000`.

In other types of tile, all addresses are other addresses. Note that `NOC_CMD_WR_INLINE` cannot be used when writing to these types of tile. If an AXI/APB bridge is crossed in order to get to the address, then the byte enable mask must select either all or none of each aligned 4-byte group.

## When `NOC_AT_LEN_BE` contains atomic opcode and operands

This applies to atomic requests.

The data must be going to an L1 address. The atomic operation happens within an aligned 16-byte region of L1. See [individual atomic opcodes for details](Atomics.md).

If `NOC_CMD_RESP_MARKED` is specified, the response address must be a 4-byte aligned L1 address.

As only Tensix tiles and Ethernet tiles have L1, this type of request is limited to these types of tile.
