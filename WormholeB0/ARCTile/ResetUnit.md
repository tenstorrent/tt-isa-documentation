# ARC Tile Reset Unit

The Reset Unit within the ARC tile is used to bring the ARC CPU out of reset, and then used by the ARC CPU to bring the rest of the ASIC out of reset. It is also home to a few assorted pieces of glue logic that would otherwise be homeless.

## Memory map

|Address&nbsp;range|Size|Name|Purpose|
|---|--:|---|---|
|`0x0000` to `0x005F`|96 Bytes|Reserved|Safe for customers to read, but undocumented|
|`0x0060` to `0x0063`|4 Bytes|`SCRATCH[0]`|The ARC CPU regularly writes a "post code" here|
|`0x0064` to `0x0067`|4 Bytes|Reserved|Safe for customers to read, but undocumented|
|`0x0068` to `0x006B`|4 Bytes|`SCRATCH[2]`|Used as part of protocol for sending messages to the ARC CPU|
|`0x006C` to `0x006F`|4 Bytes|`SCRATCH[3]`|Used as part of protocol for sending messages to the ARC CPU|
|`0x0070` to `0x0073`|4 Bytes|`SCRATCH[4]`|Used as part of protocol for sending messages to the ARC CPU|
|`0x0074` to `0x0077`|4 Bytes|`SCRATCH[5]`|Used as part of protocol for sending messages to the ARC CPU|
|`0x0078` to `0x007B`|4 Bytes|`SCRATCH[6]`|Used by the ARC CPU to issue DBI writes against the PCIe controller's configuration registers|
|`0x007C` to `0x007F`|4 Bytes|`SCRATCH[7]`|Used by the ARC CPU to issue DBI writes against the PCIe controller's configuration registers|
|`0x0080` to `0x00DF`|96 Bytes|Reserved|Safe for customers to read, but undocumented|
|`0x00E0` to `0x00E7`|8 Bytes|`REFCLK_COUNTER_LOW`|64-bit counter running at 27 MHz|
|`0x00E8` to `0x00FF`|24 Bytes|Reserved|Safe for customers to read, but undocumented|
|`0x0100` to `0x0103`|4 Bytes|`ARC_MISC_CNTL`|One bit of this is used to trigger an IRQ on the ARC CPU|
|`0x0104` to `0x01CF`|204&nbsp;Bytes|Reserved|Safe for customers to read, but undocumented|
|`0x01D0` to `0x01D3`|4 Bytes|`NOC_NODEID_X_0`|Address of [BH style telemetry](Telemetry.md#bh-style-telemetry) `telemetry_table`<br/>(since [firmware bundle](https://github.com/tenstorrent/tt-firmware) version 18.4; always zero in prior versions)|
|`0x01D4` to `0x01D7`|4 Bytes|`NOC_NODEID_Y_0`|Address of [BH style telemetry](Telemetry.md#bh-style-telemetry) `telemetry_data`<br/>(since [firmware bundle](https://github.com/tenstorrent/tt-firmware) version 18.4; always zero in prior versions)|
|`0x01D8` to `0x0327`|336&nbsp;Bytes|Reserved|Safe for customers to read, but undocumented|
|`0x0328` to `0x032B`|4 Bytes|Reserved|Not safe to access|
|`0x032C`&nbsp;to&nbsp;`0xFFFF`|63.2 KiB|Reserved|Safe for customers to read, but undocumented|

See tt-umd for [an example of sending messages to the ARC CPU](https://github.com/tenstorrent/tt-umd/blob/2d68f984a203748ade3b22ef56a2b06a32b40856/device/wormhole/wormhole_arc_messenger.cpp).
