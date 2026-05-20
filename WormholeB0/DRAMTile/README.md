# DRAM Tiles

There are 18 DRAM tiles per Wormhole ASIC, collectively exposing 12x 1 GiB channels of GDDR6. The DRAM tiles primarily exist to be used by software running on Tensix tiles and Ethernet tiles, which can communicate with DRAM by sending read requests or write requests over the [NoC](../NoC/README.md).

## Block Diagram

DRAM tiles occur in groups of three, with two channels of GDDR6 present in each group. The block diagram shows an entire group.

![](../../Diagrams/Out/EdgeTile_GDDR.svg)

Adjacent diagrams: [ARC to DRAM](../ARCTile/README.md#from-noc-and-to-dram)

### Connection types

|Arrow style|Protocol|Physical channels|Multiplexing|
|---|---|---|---|
|Thick colored purple/teal|NoC (256b data)|In direction of arrow: single channel carrying all requests / responses / acknowledgements. Arrows collectively form a torus; requests will use the dark colored arrows, responses / acknowledgements will come back on the light colored arrows.|16 virtual channels multiplexed onto each physical channel (12 for requests, 4 for responses).|
|Thick black|AXI|In direction of arrow: read request channel, write request channel, write data channel. In opposite direction: read response channel, write acknowledgement channel.|Many IDs multiplexed onto each physical channel.|
|Thick colored blue|GDDR6|One unidirectional command channel and one bidirectional data channel (which is 16 bits wide, and typically operating at 12 GT/s)|No|
|Thin black|APB (32b data)|In direction of arrow: combined request channel. In opposite direction: combined response / acknowledgement channel.|No|

### Major components

**NoC NIUs:** Unidirectional bridge between the AXI protocol and the NoC protocol. Each NIU is connected to a [NoC](../NoC/README.md) router, with the NoC routers connected in a 2D torus spanning the entire ASIC. The NIUs in DRAM tiles respond to requests from other tiles; they are not capable of emitting requests of their own.

**GDDR6 Controller and PHY:** Bridge between the AXI protocol and 1 GiB of GDDR6 memory.

### Clock domains

The NoC NIUs straddle the boundary between the AXI clock domain and the AI clock domain. Once in the AI clock domain, there is a single clock domain containing every NoC router and every Tensix tile and the majority of every Ethernet tile.

The GDDR6 controllers straddle the boundary between the AXI clock domain and the GDDR clock domain.

## Address spaces

### NoC to DRAM tile (64 GiB)

|Address range (from NoC)|Size|Contents|
|---|--:|---|
|`0x0_0000_0000` to `0x0_3FFF_FFFF`|1 GiB|GDDR6 Channel 0 data|
|`0x0_4000_0000` to `0x0_7FFF_FFFF`|1 GiB|GDDR6 Channel 1 data|
|`0x0_8000_0000` to `0x0_FFFF_FFFF`|2 GiB|Reserved|
|`0x1_0000_0000` to `0x1_000F_FFFF`|1 MiB|Mapped to [APB peripherals](#apb-peripherals-1-mib)|
|`0x1_0010_0000` to `0xE_FFFF_FFFF`|55.99 GiB|Reserved|
|`0xF_0000_0000` to `0xF_FFFF_FFFF`|4 GiB|[NIU configuration / status](../NoC/MemoryMap.md)|

### APB Peripherals (1 MiB)

The peripherals in this range exist so that firmware on the [ARC CPU](../ARCTile/README.md) can configure them. Customer software is not expected to access the GDDR6 configuration / status, and risks damaging the hardware if it does.

|Address range (APB Peripherals)|Size|Contents|
|---|--:|---|
|`0x0_0000` to `0x3_FFFF`|256 KiB|GDDR6 Channel 0 configuration / status|
|`0x4_0000` to `0x7_FFFF`|256 KiB|GDDR6 Channel 1 configuration / status|
|`0x8_0000` to `0x8_7FFF`|32 KiB|1<sup>st</sup> [NoC #0 NIU configuration / status](../NoC/MemoryMap.md)|
|`0x8_8000` to `0x8_FFFF`|32 KiB|1<sup>st</sup> [NoC #1 NIU configuration / status](../NoC/MemoryMap.md)|
|`0x9_0000` to `0x9_7FFF`|32 KiB|2<sup>nd</sup> [NoC #0 NIU configuration / status](../NoC/MemoryMap.md)|
|`0x9_8000` to `0x9_FFFF`|32 KiB|2<sup>nd</sup> [NoC #1 NIU configuration / status](../NoC/MemoryMap.md)|
|`0xA_0000` to `0xA_7FFF`|32 KiB|3<sup>rd</sup> [NoC #0 NIU configuration / status](../NoC/MemoryMap.md)|
|`0xA_8000` to `0xA_FFFF`|32 KiB|3<sup>rd</sup> [NoC #1 NIU configuration / status](../NoC/MemoryMap.md)|
|`0xB_0000` to `0xC_7FFF`|96 KiB|Additional GDDR6 configuration / status|
|`0xC_8000` to `0xF_FFFF`|224 KiB|Reserved|

## Performance

Running at the typical speed of 12 GT/s (†), each GDDR6 channel is theoretically capable of reading at 24 GB/s or writing at 24 GB/s (or performing a mixture of the two, though the combined bandwidth cannot exceed 24 GB/s). With twelve channels per Wormhole ASIC, this is 288 GB/s in aggregate. Some products have two such ASICs per board, giving 576 GB/s in aggregate across the entire board. Self-refresh and other overheads consume some of the theoretical bandwidth; in practice well-written software can expect to achieve approximately 92% of the theoretical maximum bandwidth.

> (†) Giga-transfers per second. A transfer is either a read of 16 bits or a write of 16 bits.

Each hop in the NoC (between a pair of adjacent routers or between an NIU and a router) can sustain 32 GB/s. If just one GDDR6 channel is in use, then the GDDR6 channel bandwidth limit of 24 GB/s will be hit before the NoC limit of 32 GB/s. The main caveat to this is when writing a large amount of data to DRAM from L1: data can leave L1 at 32 GB/s, but can only be ingested by DRAM at 24 GB/s, so software can easily fill up all the buffers in all the NoC routers along the path. Each router has a 2 KiB buffer per inbound port: each virtual channel has a guaranteed 32 bytes, and then the remaining 1½ KiB is dynamically shared, with each virtual channel able to claim up to 480 bytes from this shared pool. If the shared pool becomes full (or nearly full), then the inbound port to which it is attached will exhibit poor performance (as some virtual channels will only get 32 bytes of buffer space, which is insufficient to fully hide the roundtrip latency of the hop). To avoid the shared pool from becoming full, software is encouraged to use static virtual channel allocation when performing large writes to DRAM - this will result in backpressure to the writer as soon as the chosen virtual channel has claimed as much as it can from the shared pool, rather than backpressure only occurring once the shared pool is exhausted. In the converse direction, when performing large reads, the headers of each read request consume 32 bytes of buffer space, so software is encouraged to limit its number of outstanding read requests to avoid buffers being filled by read request headers. This buffering effect can be seen by having a varying number of Tensix tiles all simultaneously perform a 1 MiB read or write against the same DRAM channel:

|# Tensix Tiles (↔ 1 DRAM channel)|Direction|VC Allocation|NoC|Measured speed|
|---|---|---|---|--:|
|1, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #0|22.2 GB/s (92.5%)|
|1, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #1|22.3 GB/s (92.7%)|
|12, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #0|22.3 GB/s (93.1%)|
|12, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #1|22.3 GB/s (93.1%)|
|48, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #0|22.3 GB/s (93.1%)|
|48, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #1|22.3 GB/s (93.1%)|
|1, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #0|22.2 GB/s (92.6%)|
|1, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #1|22.2 GB/s (92.4%)|
|12, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #0|22.3 GB/s (93.1%)|
|12, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #1|22.3 GB/s (93.1%)|
|48, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #0|22.3 GB/s (93.1%)|
|48, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #1|22.3 GB/s (93.1%)|
|1, randomly chosen|L1 to DRAM (write)|Static|NoC #0|21.9 GB/s (91.2%)|
|1, randomly chosen|L1 to DRAM (write)|Static|NoC #1|21.9 GB/s (91.2%)|
|12, randomly chosen|L1 to DRAM (write)|Static|NoC #0|22.0 GB/s (91.8%)|
|12, randomly chosen|L1 to DRAM (write)|Static|NoC #1|22.0 GB/s (91.5%)|
|48, randomly chosen|L1 to DRAM (write)|Static|NoC #0|22.0 GB/s (91.8%)|
|48, randomly chosen|L1 to DRAM (write)|Static|NoC #1|21.9 GB/s (91.4%)|
|1, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #0|21.8 GB/s (90.7%)|
|1, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #1|21.8 GB/s (90.8%)|
|12, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #0|7.6 GB/s (31.9%)|
|12, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #1|8.0 GB/s (33.3%)|
|48, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #0|7.9 GB/s (32.9%)|
|48, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #1|6.7 GB/s (28.0%)|

> (‡) `NOC_CMD_VC_STATIC` specified on the read _request_, but read _responses_ always use dynamic VC assignment regardless.

Once multiple GDDR6 channels are in use, then care is required, as otherwise it is easy to be bottlenecked by the NoC limit of 32 GB/s (per hop) long before hitting the aggregate DRAM limit of 288 GB/s. This effect can be seen by having a varying number of Tensix tiles all simultaneously perform a 1 MiB read or write against a particular DRAM channel, and either carefully choosing which Tensix tiles communicate with which DRAM channels, or randomly pairing up Tensix tiles with DRAM channels (though doing so in a fair manner, such that each of the 12 DRAM channels has an equal number of Tensix tiles communicating with it). This gives a different set of measurements:

|# Tensix Tiles (↔ 12 DRAM channels)|Direction|VC Allocation|NoC|Measured speed|
|---|---|---|---|--:|
|12, carefully chosen|DRAM to L1 (read)|Static (‡)|NoC #0|265.5 GB/s (92.2%)|
|12, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #0|189.8 GB/s (65.9%)|
|12, carefully chosen|DRAM to L1 (read)|Static (‡)|NoC #1|265.3 GB/s (92.1%)|
|12, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #1|82.1 GB/s (28.5%)|
|48, carefully chosen|DRAM to L1 (read)|Static (‡)|NoC #0|267.5 GB/s (92.9%)|
|48, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #0|200.3 GB/s (69.5%)|
|48, carefully chosen|DRAM to L1 (read)|Static (‡)|NoC #1|267.5 GB/s (92.9%)|
|48, randomly chosen|DRAM to L1 (read)|Static (‡)|NoC #1|78.2 GB/s (27.1%)|
|12, carefully chosen|DRAM to L1 (read)|Dynamic|NoC #0|265.6 GB/s (92.2%)|
|12, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #0|189.8 GB/s (65.9%)|
|12, carefully chosen|DRAM to L1 (read)|Dynamic|NoC #1|265.4 GB/s (92.1%)|
|12, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #1|82.0 GB/s (28.5%)|
|48, carefully chosen|DRAM to L1 (read)|Dynamic|NoC #0|267.6 GB/s (92.9%)|
|48, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #0|197.1 GB/s (68.4%)|
|48, carefully chosen|DRAM to L1 (read)|Dynamic|NoC #1|267.5 GB/s (92.9%)|
|48, randomly chosen|DRAM to L1 (read)|Dynamic|NoC #1|77.5 GB/s (26.9%)|
|12, carefully chosen|L1 to DRAM (write)|Static|NoC #0|261.3 GB/s (90.7%)|
|12, randomly chosen|L1 to DRAM (write)|Static|NoC #0|56.5 GB/s (19.6%)|
|12, carefully chosen|L1 to DRAM (write)|Static|NoC #1|262.0 GB/s (91.0%)|
|12, randomly chosen|L1 to DRAM (write)|Static|NoC #1|154.5 GB/s (53.6%)|
|48, carefully chosen|L1 to DRAM (write)|Static|NoC #0|263.7 GB/s (91.6%)|
|48, randomly chosen|L1 to DRAM (write)|Static|NoC #0|52.3 GB/s (18.2%)|
|48, carefully chosen|L1 to DRAM (write)|Static|NoC #1|256.2 GB/s (89.0%)|
|48, randomly chosen|L1 to DRAM (write)|Static|NoC #1|133.7 GB/s (46.4%)|
|12, carefully chosen|L1 to DRAM (write)|Dynamic|NoC #0|255.1 GB/s (88.6%)|
|12, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #0|77.4 GB/s (26.9%)|
|12, carefully chosen|L1 to DRAM (write)|Dynamic|NoC #1|255.5 GB/s (88.7%)|
|12, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #1|173.2 GB/s (60.1%)|
|48, carefully chosen|L1 to DRAM (write)|Dynamic|NoC #0|81.7 GB/s (28.4%)|
|48, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #0|18.2 GB/s (6.3%)|
|48, carefully chosen|L1 to DRAM (write)|Dynamic|NoC #1|79.3 GB/s (27.5%)|
|48, randomly chosen|L1 to DRAM (write)|Dynamic|NoC #1|54.5 GB/s (18.9%)|

> (‡) `NOC_CMD_VC_STATIC` specified on the read _request_, but read _responses_ always use dynamic VC assignment regardless.

A few effects are visible in the above table:
1. When there is heavy NoC congestion, NoC #1 performs better than NoC #0 for writes, but NoC #0 performs better than NoC #1 for reads. This is fully explained by the different [routing paths used by each NoC](../NoC/RoutingPaths.md), combined with DRAM tiles being arranged in columns: random writes on NoC #0 will have a lot of contention in the columns containing DRAM tiles, and likewise responses to random reads on NoC #1 will have a lot of contention in those same columns.
2. When tile pairings are made carefully, there is generally very little difference between NoC #0 and NoC #1. This is because careful pairings tend to involve minimizing vertical data movement, and once data is only moving in one axis, the routing path differences between NoC #0 and NoC #1 mostly evaporate.
3. Static VC allocation remains important for large writes.

## Ordering

If two requests are sent to different NIUs, there are no ordering guarantees between them.

If two requests are sent to the same NIU, but arrive on different virtual channels, there are no ordering guarantees between them.

If two requests are sent to the same NIU, and arrive on the same virtual channel, then ordering guarantees sometimes exist:
* If both requests are read requests, they will be processed in order of arrival. The read responses can however be re-ordered as they return on the NoC.
* If both requests are writes, they will be processed in order of arrival. The write acknowledgements can however be re-ordered as they return on the NoC.
* If the 1<sup>st</sup> request is a write, and the 2<sup>nd</sup> request is a read, the virtual channel will wait to receive all of its outstanding write-acknowledgements from the GDDR controller(s) before sending the read request to the GDDR controller(s). This is the case even if the write request was a posted write (the NIU receives a write acknowledgement for every write; `NOC_CMD_RESP_MARKED` merely controls whether the NIU drops the acknowledgement or returns it on the NoC).
* If the 1<sup>st</sup> request is a read, and the 2<sup>nd</sup> request is a write, there are no ordering guarantees between them.

Note that [general NoC ordering](../NoC/Ordering.md) applies to packets in transit on the NoC, so requests can re-order on their way _to_ DRAM tile NIUs (with `NOC_CMD_VC_STATIC` and `NOC_CMD_VC_LINKED` being tools to mitigate this), and responses can re-order on their way back.
