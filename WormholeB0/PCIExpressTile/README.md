# PCI Express Tile

The PCI Express tile exists for PCI Express 4.0 x16 connectivity with a host system. It is the primary conduit through which customer code is uploaded to the device, and through which customer data is uploaded to and downloaded from the device. It allows the host to perform reads and writes against the address space of any tile on the [NoC](../NoC/README.md) (albeit some tiles do not expose their entire address space to the NoC), and allows any tile on the NoC to perform reads and writes against the address space of the host (or at least whatever the host's IOMMU makes available).

The n300 products feature two ASICs on a single board, and both ASICs _have_ a PCI Express tile, but only one of the ASICs is wired up to the PCI Express edge connector on the board: the PCI Express tile in the other ASIC is effectively useless. The primary conduit for accessing that other ASIC is ethernet, and there are dedicated ethernet links printed onto the circuit board between the two ASICs for this purpose.

## Block Diagrams

This tile is too complex to show on a single diagram, though some components are shown on both diagrams.

### Host to device

![](../../Diagrams/Out/EdgeTile_PCIe_H2D.svg)

Adjacent diagrams: [ARC from PCI Express](../ARCTile/README.md#tofrom-pci-express-and-to-noc)

### Device to host

![](../../Diagrams/Out/EdgeTile_PCIe_D2H.svg)

Adjacent diagrams: [ARC to PCI Express](../ARCTile/README.md#tofrom-pci-express-and-to-noc)

### Connection types

|Arrow style|Protocol|Physical channels|Multiplexing|
|---|---|---|---|
|Thick colored purple/teal|NoC (256b data)|In direction of arrow: single channel carrying all requests / responses / acknowledgements. Arrows collectively form a torus; requests will use the dark colored arrows, responses / acknowledgements will come back on the light colored arrows.|16 virtual channels multiplexed onto each physical channel (12 for requests, 4 for responses).|
|Thick black|AXI|In direction of arrow: read request channel, write request channel, write data channel. In opposite direction: read response channel, write acknowledgement channel.|Many IDs multiplexed onto each physical channel.|
|Thick colored blue|PCI Express 4.0 x16|In direction of arrow: single channel carrying all requests / responses / flow control updates. Arrows always come in pairs; requests will use the dark colored arrows, responses will come back on the light colored arrows.|In theory, 8 virtual channels multiplexed onto each physical channel, though only 1 of these is typically used.|
|Thin black|APB (32b data)|In direction of arrow: combined request channel. In opposite direction: combined response / acknowledgement channel.|No|

### Major components

**Host MMU:** Maps the device's bar 0 (512 MiB), bar 2 (1 MiB), and bar 4 (32 MiB) into the address space of various processes on the host.

**PCI Express Controller and PHY:** Bidirectional bridge between the [PCI Express wire protocol](https://xillybus.com/tutorials/pci-express-tlp-pcie-primer-tutorial-guide-1) and the AXI protocol. Amongst other things, contains an iATU in each direction for address remapping, and some DMA engines.

**Inbound iATU:** Configured by the kernel driver such that bar 4 address space aliases the top 32 MiB of bar 0 address space. No other major use.

**[Configurable TLBs](TLBs.md):** Configure how host read / write requests (from PCI Express) get turned into NoC read / write transactions. Each TLB can specify the [X/Y coordinates](../NoC/Coordinates.md) of a tile on either [NoC](../NoC/README.md), or a rectangle of coordinates for broadcast writes to Tensix tiles.

**NoC NIUs:** Bidirectional bridge between the AXI protocol and the NoC protocol. Each NIU is connected to a [NoC](../NoC/README.md) router, with the NoC routers connected in a 2D torus spanning the entire ASIC.

**Outbound iATU:** Maps a 4 GiB minus 128 KiB address space (read / write requests from the NoC or from ARC) to a 64-bit address space (to the host). Up to 16 separate contiguous remapping regions can be defined, along with an identity mapping for addresses outside these regions.

**DMA Engines:** Fixed-function hardware for efficiently copying data between the host and the device (in either direction). Supports full 64-bit addressing on the host side.

**Host IOMMU:** If present and enabled, maps a 64-bit address space (from the Outbound iATU and the DMA Engines) to the host's physical address space. Otherwise, the 64-bit address space is exactly the host's physical address space.

### Clock domains

The PCI Express Controller straddles the boundary between the PCI Express clock domain and the AXI clock domain.

The NoC NIUs straddle the boundary between the AXI clock domain and the AI clock domain. Once in the AI clock domain, there is a single clock domain containing every NoC router and every Tensix tile and the majority of every Ethernet tile.

All other components of the PCI Express tile are in the AXI clock domain.

## Address spaces

### Host to device, bar 0 (512 MiB)

|Address range (bar 0)|Size|Contents|
|---|--:|---|
|`0x0000_0000` to `0x09BF_FFFF`|156x 1 MiB|[TLB windows to NoC](TLBs.md)|
|`0x09C0_0000` to `0x0AFF_FFFF`|10x 2 MiB|[TLB windows to NoC](TLBs.md)|
|`0x0B00_0000` to `0x1DFF_FFFF`|19x 16 MiB|[TLB windows to NoC](TLBs.md)|
|`0x1E00_0000` to `0x1EFF_FFFF`|16 MiB|[TLB window to NoC (reserved for kernel driver)](TLBs.md)|
|`0x1F00_0000` to `0x1FBF_FFFF`|12 MiB|Reserved|
|`0x1FC0_0000` to `0x1FC0_05CF`|1.45 KiB|[TLB window configuration](TLBs.md#configuration)|
|`0x1FC0_05D0` to `0x1FD1_FFFF`|1.1 MiB|Reserved|
|`0x1FD2_0000` to `0x1FD2_0FFF`|4 KiB|[NIU #0 configuration / status](../NoC/MemoryMap.md)|
|`0x1FD2_1000` to `0x1FD9_FFFF`|508 KiB|Reserved|
|`0x1FDA_0000` to `0x1FDA_0FFF`|4 KiB|[NIU #1 configuration / status](../NoC/MemoryMap.md)|
|`0x1FDA_1000` to `0x1FDF_FFFF`|380 KiB|Reserved|
|`0x1FE0_0000` to `0x1FFF_FFFF`|2 MiB|Mapped to [ARC](../ARCTile/README.md#host-to-device-bar-0--bar-4)|

### Host to device, bar 2 (1 MiB)

> [!CAUTION]
> Bar 2 only supports aligned 32-bit accesses. Host software cannot use 64-bit reads or writes (nor even wider reads or writes).

|Address range (bar 2)|Size|Contents|
|---|--:|---|
|`0x0_0000` to `0x0_01FF`|½ KiB|DMA Engines general configuration / status|
|`0x0_0200` to `0x0_11FF`|8x ½ KiB|DMA Engines channel-specific configuration / status|
|`0x0_1200` to `0x0_31FF`|8 KiB|Inbound iATU and Outbound iATU configuration|
|`0x0_3200` to `0xF_FFFF`|1011½ KiB|Reserved for other PCI Express Controller and PHY functionality|

See tt-kmd for [an example of Outbound iATU configuration](https://github.com/tenstorrent/tt-kmd/blob/6dee5f1b7040ac0c1706eceae660f41649ba6f4f/wormhole.c#L518-L544). See tt-umd for [an example of DMA Engine configuration](https://github.com/tenstorrent/tt-umd/blob/28891ae934e349e9cd40e437188b321c0f729dea/device/tt_device/wormhole_tt_device.cpp#L181-L329).

### Host to device, bar 4 (32 MiB)

The kernel driver configures the inbound iATU such that bar 4 aliases the top 32 MiB of bar 0 address space. Consequently, the contents of bar 4 is identical to the top 32 MiB of bar 0:

|Address range (bar 4)|Size|Contents|
|---|--:|---|
|`0x0000_0000` to `0x00FF_FFFF`|16 MiB|[TLB window to NoC (reserved for kernel driver)](TLBs.md)|
|`0x0100_0000` to `0x01BF_FFFF`|12 MiB|Reserved|
|`0x01C0_0000` to `0x01C0_05CF`|1.45 KiB|[TLB window configuration](TLBs.md)|
|`0x01C0_05D0` to `0x01D1_FFFF`|1.1 MiB|Reserved|
|`0x01D2_0000` to `0x01D2_0FFF`|4 KiB|[NIU #0 configuration / status](../NoC/MemoryMap.md)|
|`0x01D2_1000` to `0x01D9_FFFF`|508 KiB|Reserved|
|`0x01DA_0000` to `0x01DA_0FFF`|4 KiB|[NIU #1 configuration / status](../NoC/MemoryMap.md)|
|`0x01DA_1000` to `0x01DF_FFFF`|380 KiB|Reserved|
|`0x01E0_0000` to `0x01FF_FFFF`|2 MiB|Mapped to [ARC](../ARCTile/README.md#host-to-device-bar-0--bar-4)|

Bar 4 can be ignored when the full 512 MiB of bar 0 is available; usage of bar 4 is only _necessary_ when the host system is forced to reduce the size of bar 0.

### NoC to Host (64 GiB)

|Address range (from NoC)|Size|Contents|
|---|--:|---|
|`0x0_0000_0000` to `0x7_FFFF_FFFF`|32 GiB|Reserved|
|`0x8_0000_0000`|3.999 GiB|Mapped to Outbound iATU, then onwards to Host IOMMU|
|`0x8_FFFE_0000`|128 KiB|PCI Express Controller and PHY, assorted extremely low-level configuration|
|`0x9_0000_0000` to `0xE_FFFF_FFFF`|24 GiB|Reserved|
|`0xF_0000_0000` to `0xF_FFFF_FFFF`|4 GiB|[NIU configuration / status](../NoC/MemoryMap.md)|

## Performance

> [!IMPORTANT]
> Customer performance will depend on the host CPU, host motherboard, host memory, and a variety of other factors. The numbers presented here are from one particular desktop Zen 5 system (Ryzen 9 9950X CPU, DDR5 DIMMs operating at 5600 MHz), and should be considered as informative rather than authoritative.
>
> Host software also needs to be careful to avoid unnecessary memory copies - if it uses bounce buffers to work around pinning requirements, then this puts additional load on the host's memory subsystem.

PCI Express 4.0 x16 has a theoretical maximum bandwidth of 32 GB/s in each direction simultaneously, but various overheads eat into this. In practice, well-written software can expect to achieve somewhere between 70% and 85% of the theoretical maximum bandwidth.

### Host-initiated reads and writes

Customer software running on the host can initiate reads or writes against device memory. This requires that some device memory be pinned into the host address space using one of the TLB windows in the PCI Express tile, and software can choose the [ordering mode of that TLB](TLBs.md#ordering-modes), along with choosing to map it as either WC or UC. To explore the TLB configuration options, transfers between host memory and the L1 of a Tensix tile in the same row as the PCI Express tile can be performed:

|Operation|Memory Type|TLB Ordering|Measured Throughput|Measured Latency|
|---|---|---|--:|--:|
|DMA to device|WC or UC|Posted writes|24.04 GB/s|≥ 1342 ns|
|DMA to device|WC or UC|Default|24.42 GB/s|≥ 1453 ns|
|DMA to device|WC or UC|Strict AXI|3.93 GB/s|≥ 1453 ns|
|`memcpy` to device|WC|Posted writes|22.65 GB/s|≥ 180 ns (†)|
|`memcpy` to device|WC|Default|14.35 GB/s|≥ 180 ns (†)|
|`memcpy` to device|WC|Strict AXI|9.50 GB/s|≥ 180 ns (†)|
|`memcpy` to device|UC|Posted writes|7.05 GB/s|≥ 170 ns (†)|
|`memcpy` to device|UC|Default|7.17 GB/s|≥ 170 ns (†)|
|`memcpy` to device|UC|Strict AXI|4.88 GB/s|≥ 170 ns (†)|
|DMA from device|WC or UC|Posted writes|11.34 GB/s|≥ 1052 ns|
|DMA from device|WC or UC|Default|11.34 GB/s|≥ 1052 ns|
|DMA from device|WC or UC|Strict AXI|1.07 GB/s|≥ 1052 ns|
|`_mm_stream_load_si128` from device|WC|Posted writes|1.59 GB/s|≥ 671 ns|
|`_mm_stream_load_si128` from device|WC|Default|1.59 GB/s|≥ 671 ns|
|`_mm_stream_load_si128` from device|WC|Strict AXI|1.59 GB/s|≥ 671 ns|
|`_mm_stream_load_si128` from device|UC|Posted writes|0.03 GB/s|≥ 671 ns|
|`_mm_stream_load_si128` from device|UC|Default|0.03 GB/s|≥ 671 ns|
|`_mm_stream_load_si128` from device|UC|Strict AXI|0.03 GB/s|≥ 671 ns|
|`memcpy` from device|WC|Posted writes|0.10 GB/s|≥ 671 ns|
|`memcpy` from device|WC|Default|0.10 GB/s|≥ 671 ns|
|`memcpy` from device|WC|Strict AXI|0.10 GB/s|≥ 671 ns|
|`memcpy` from device|UC|Posted writes|0.10 GB/s|≥ 671 ns|
|`memcpy` from device|UC|Default|0.10 GB/s|≥ 671 ns|
|`memcpy` from device|UC|Strict AXI|0.10 GB/s|≥ 671 ns|

> (†) The translation to PCI Express turns all writes into posted writes, so this latency is based on an `mfence` instruction, which merely guarantees that the write has been sent on its way to PCI Express.

A few conclusions can be drawn from the above table:
* WC memory gives much better performance than UC memory; the tradeoff being that software needs to occasionally insert `sfence` instructions when it needs guaranteed ordering.
* "Posted writes" are better than "Default" when performing `memcpy` to device, and equivalent to "Default" for all operations in the other direction. As such, software is encouraged to use "Posted writes" whenever it does not need the ordering guarantees of "Default". Note that there is never a need to use "Strict AXI", as "Default" can maintain all the ordering properties of PCI Express.
* For sending data to the device, DMA is 6% faster than the best `memcpy` to device, but for most software, the 6% improvement might not be worth the complexity of DMA. If software _does_ need maximum performance, then device-initiated operations can perform even better than DMA.
* For retrieving data from the device, none of the host-initiated operations are particularly good for throughput. Software is encouraged to use device-initiated operations instead.

Performance of host-initiated operations also depends on the kind of device memory being accessed. To explore the device memory type axis, WC memory and "Posted writes" TLBs are used:

|Operation|Device Memory Type|Measured Throughput|Measured Latency|
|---|---|--:|--:|
|DMA to device|Tensix tile L1 (same row)|24.04 GB/s|≥ 1342 ns|
|DMA to device|Tensix/Ethernet tile L1|24.88 GB/s|≥ 1342 ns|
|DMA to device|DRAM tile (same row)|21.21 GB/s|≥ 1342 ns|
|DMA to device|DRAM tile (same column)|21.21 GB/s|≥ 1342 ns|
|DMA to device|DRAM tile|21.23 GB/s|≥ 1342 ns|
|`memcpy` to device|Tensix tile L1 (same row)|22.65 GB/s|≥ 180 ns (†)|
|`memcpy` to device|Tensix/Ethernet tile L1|22.44 GB/s|≥ 180 ns (†)|
|`memcpy` to device|DRAM tile (same row)|20.98 GB/s|≥ 180 ns (†)|
|`memcpy` to device|DRAM tile (same column)|20.69 GB/s|≥ 180 ns (†)|
|`memcpy` to device|DRAM tile|20.69 GB/s|≥ 180 ns (†)|
|DMA from device|Tensix tile L1 (same row)|11.34 GB/s|≥ 1052 ns|
|DMA from device|Tensix/Ethernet tile L1|8.22 GB/s|≥ 1162 ns|
|DMA from device|DRAM tile (same row)|8.47 GB/s|≥ 1142 ns|
|DMA from device|DRAM tile (same column)|7.86 GB/s|≥ 1162 ns|
|DMA from device|DRAM tile|5.84 GB/s|≥ 1252 ns|
|`_mm_stream_load_si128` from device|Tensix tile L1 (same row)|1.59 GB/s|≥ 671 ns|
|`_mm_stream_load_si128` from device|Tensix/Ethernet tile L1|1.34 GB/s|≥ 781 ns|
|`_mm_stream_load_si128` from device|DRAM tile (same row)|1.33 GB/s|≥ 761 ns|
|`_mm_stream_load_si128` from device|DRAM tile (same column)|1.32 GB/s|≥ 771 ns|
|`_mm_stream_load_si128` from device|DRAM tile|1.17 GB/s|≥ 871 ns|
|`memcpy` from device|Tensix tile L1 (same row)|0.10 GB/s|≥ 671 ns|
|`memcpy` from device|Tensix/Ethernet tile L1|0.09 GB/s|≥ 781 ns|
|`memcpy` from device|DRAM tile (same row)|0.09 GB/s|≥ 752 ns|
|`memcpy` from device|DRAM tile (same column)|0.09 GB/s|≥ 771 ns|
|`memcpy` from device|DRAM tile|0.08 GB/s|≥ 862 ns|

> (†) The translation to PCI Express turns all writes into posted writes, so this latency is based on an `mfence` instruction, which merely guarantees that the write has been sent on its way to PCI Express.

### Device-initiated reads and writes

Customer software running on Tensix tiles or Ethernet tiles can use the NoC to initiate reads and writes against pinned host memory: the request is made against a 3.999 GiB address range of the PCI Express tile, which the Outbound iATU expands to a 64-bit range, and then the host IOMMU interprets.

Using a Tensix tile in the same row as the PCI Express tile:
* Read throughput (host to L1) is 24.5 GB/s, roundtrip latency is ≥ 690ns:
    * ~110ns for tile L1 ↔ NIU in the PCI Express tile
    * ~150ns for NIU in the PCI Express tile ↔ middle of the PCI Express Controller
    * ~430ns for middle of the PCI Express Controller ↔ host memory
* Write throughput (L1 to host) is 26.4 GB/s, roundtrip latency is ≥ 260ns (†)

Using a Tensix or Ethernet tile in a different row to the PCI Express tile:
* Read throughput (host to L1) is 24.5 GB/s, roundtrip latency is ≥ 800ns:
    * ~220ns for tile L1 ↔ NIU in the PCI Express tile
    * ~150ns for NIU in the PCI Express tile ↔ middle of the PCI Express Controller
    * ~430ns for middle of the PCI Express Controller ↔ host memory
* Write throughput (L1 to host) is 26.4 GB/s, roundtrip latency is ≥ 370ns (†)

> (†) The translation to PCI Express turns all writes into posted writes, so this latency is based on the "fake" write acknowledgement provided by the middle of the PCI Express Controller.
