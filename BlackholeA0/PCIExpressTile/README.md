# PCI Express Tile

The PCI Express tiles exist for PCI Express 5.0 x16 connectivity with a host system. Every Blackhole ASIC contains two PCI Express tiles, called PCIe 0 and PCIe 1. These two PCI Express tiles are physically identical, with the differences arising from what they are connected to:
* On current products, only one of the two is connected to the host (p150 boards use PCIe 0 for the host connection, whereas p100 boards use PCIe 1), with the other left idle
* Only PCIe 1 has a direct connection to the ARC tile (so the NoC needs to be used to bridge between PCIe 0 and the ARC tile)
* There are six serdeses per Blackhole ASIC, with configuration wires for three of them attached to each PCI Express tile

The PCIe tile connected to the host is the primary conduit through which customer code is uploaded to the device, and through which customer data is uploaded to and downloaded from the device. It allows the host to perform reads and writes against the address space of any tile on the [NoC](../NoC/README.md) (albeit some tiles do not expose their entire address space to the NoC), and allows any tile on the NoC to perform reads and writes against the address space of the host (or at least whatever the host's IOMMU makes available).

> [!TIP]
> Compared to Wormhole, some of the major upgrades to PCI Express tiles in Blackhole are: PCI Express 5.0 rather than PCI Express 4.0, an additional 32 GiB region of host-to-device address space in bar 4, and device-to-host address space increased from 32 bits to 64 bits.

## Block Diagrams

This tile is too complex to show on a single diagram, though some components are shown on both diagrams.

### Host to device

![](../../Diagrams/Out/EdgeTile_BH_PCIe_H2D.svg)

### Device to host

![](../../Diagrams/Out/EdgeTile_BH_PCIe_D2H.svg)

### Connection types

|Arrow style|Protocol|Physical channels|Multiplexing|
|---|---|---|---|
|Thick colored purple/teal|NoC (512b data)|In direction of arrow: single channel carrying all requests / responses / acknowledgements. Arrows collectively form a torus; requests will use the dark colored arrows, responses / acknowledgements will come back on the light colored arrows.|16 virtual channels multiplexed onto each physical channel (12 for requests, 4 for responses).|
|Thick black|AXI|In direction of arrow: read request channel, write request channel, write data channel. In opposite direction: read response channel, write acknowledgement channel.|Many IDs multiplexed onto each physical channel.|
|Thick colored blue|PCI Express 5.0 x16|In direction of arrow: single channel carrying all requests / responses / flow control updates. Arrows always come in pairs; requests will use the dark colored arrows, responses will come back on the light colored arrows.|In theory, 8 virtual channels multiplexed onto each physical channel, though only 1 of these is typically used.|
|Thin black|APB (32b data)|In direction of arrow: combined request channel. In opposite direction: combined response / acknowledgement channel.|No|

### Major components

**Host MMU:** Maps the device's bar 0 (512 MiB), bar 2 (1 MiB), and bar 4 (32 GiB) into the address space of various processes on the host.

**PCI Express Controller and PHY:** Bidirectional bridge between the [PCI Express wire protocol](https://xillybus.com/tutorials/pci-express-tlp-pcie-primer-tutorial-guide-1) and the AXI protocol. Amongst other things, contains an iATU in each direction for address remapping, and some DMA engines.

**Inbound iATU:** Standard component of a PCI Express Controller, which could be configured to remap addresses in the host-to-device direction, but does not currently do so. Up to 16 separate contiguous remapping regions can be defined, along with an identity mapping for addresses outside these regions.

**[Configurable TLBs, H→N](HostToDeviceTLBs.md):** Configure how host read / write requests (from PCI Express) get turned into NoC read / write transactions. Each TLB can specify the [X/Y coordinates](../NoC/Coordinates.md) of a tile on either [NoC](../NoC/README.md), or a rectangle of coordinates for broadcast writes to Tensix tiles. Some of these TLBs also support non-rectangular broadcast.

**NoC NIUs:** Bidirectional bridge between the AXI protocol and the NoC protocol. Each NIU is connected to a [NoC](../NoC/README.md) router, with the NoC routers connected in a 2D torus spanning the entire ASIC.

**Configurable TLBs, H←N:** Maps a 64-bit address space (from the NoC) to another 64-bit address space (towards the Host), potentially applying PCI Express transaction attributes in the process.

**Configurable TLBs, H←A:** Maps a 36-bit address space (from ARC) to a 64-bit address space (towards the Host), potentially applying PCI Express transaction attributes in the process.

**Outbound iATU:** Standard component of a PCI Express Controller, which can be configured to remap addresses in the device-to-host direction. Up to 16 separate contiguous remapping regions can be defined, along with an identity mapping for addresses outside these regions. Various use-cases will employ a combination of remapping at Configurable TLBs, the Outbound iATU, and the Host IOMMU.

**DMA Engines:** Fixed-function hardware for efficiently copying data between the host and the device (in either direction). Supports full 64-bit addressing on the host side.

**Host IOMMU:** If present and enabled, maps a 64-bit address space (from the Outbound iATU and the DMA Engines) to the host's physical address space. Otherwise, the 64-bit address space is exactly the host's physical address space. See [Security and Isolation at the System Level](../../SystemSecurity.md) for why the IOMMU should be enabled.

**Interrupt Receiver:** The PCI Express Controller is capable of operating as a "Root Port (RP)", although in current products it is instead configured to operate as an "Endpoint (EP)". When it is operating as a Root Port (RP), the Interrupt Receiver translates PCI Express interrupts into small NoC transactions, allowing a tile on the NoC to be notified of interrupts and subsequently service them.

**Serdes Configuration:** Every Blackhole ASIC contains six serdeses, with each serdes supporting 8 lanes of ~100 Gb/s. Each serdes serves dual purpose for PCIe and Ethernet, although not both at once. Each PCI Express tile contains some low-bandwidth wires going to three serdeses, allowing them to be configured (a _connected_ PCI Express x16 tile also contains some high-bandwidth wires going to two of these three serdeses). Firmware uses these wires to configure the serdeses, but customers should never need to worry about it, so a description is provided only in so far as it aids in comprehending the high-level structure of the open-source firmware.

### Clock domains

The PCI Express Controller straddles the boundary between the PCI Express clock domain and the AXI clock domain.

The NoC NIUs straddle the boundary between the AXI clock domain and the AI clock domain. Once in the AI clock domain, there is a single clock domain containing every NoC router and every Tensix tile and the majority of every Ethernet tile.

All other components of the PCI Express tile are in the AXI clock domain.

## Address spaces

### Host to device, bar 0 (512 MiB)

|Address range (bar 0)|Size|Contents|
|---|--:|---|
|`0x0000_0000` to `0x03FF_FFFF`|32x 2 MiB|[TLB windows to NoC (with extra support for non-rectangular multicast)](HostToDeviceTLBs.md)|
|`0x0400_0000` to `0x191F_FFFF`|169x 2 MiB|[TLB windows to NoC](HostToDeviceTLBs.md)|
|`0x1920_0000` to `0x193F_FFFF`|2 MiB|[TLB window to NoC (reserved for kernel driver)](HostToDeviceTLBs.md)|
|`0x1940_0000` to `0x1FBF_FFFF`|104 MiB|Reserved|
|`0x1FC0_0000` to `0x1FC0_0A57`|2.58 KiB|[TLB window configuration](HostToDeviceTLBs.md#configuration)|
|`0x1FC0_0A58` to `0x1FD0_3FFF`|1.01 MiB|Reserved|
|`0x1FD0_4000` to `0x1FD0_5FFF`|8 KiB|[NIU #0 configuration / status](../NoC/MemoryMap.md)|
|`0x1FD0_6000` to `0x1FD1_3FFF`|56 KiB|Reserved|
|`0x1FD1_4000` to `0x1FD1_5FFF`|8 KiB|[NIU #1 configuration / status](../NoC/MemoryMap.md)|
|`0x1FD1_6000` to `0x1FDF_FFFF`|936 KiB|Reserved|
|`0x1FE0_0000` to `0x1FFF_FFFF`|2 MiB|PCIe 0: Reserved</br>PCIe 1: Mapped to ARC|

### Host to device, bar 4 (32 GiB)

|Address range (bar 4)|Size|Contents|
|---|--:|---|
|`0x0_0000_0000` to `0x7_FFFF_FFFF`|8x 4 GiB|[TLB windows to NoC](HostToDeviceTLBs.md)|

### NoC to Host (2<sup>64</sup> bytes)

This 64-bit address space is constructed from 64 TLB windows, each one 2<sup>58</sup> bytes in size, with the first 63 windows configurable and the final window fixed. The below table reflects what the 64-bit address space looks like following the TLB window configuration performed by the ARC firmware. The maximum physical address space size on x86 hosts is 2<sup>52</sup> bytes, and the maximum virtual address space size is 2<sup>57</sup> bytes, so _any_ TLB window should be sufficient to address the entire host address space. As such, most of the TLB windows are configured to provide different PCIe transaction attributes for accessing the same underlying range of 2<sup>58</sup> host addresses.

|Address range (from NoC)|Size|Contents|
|---|--:|---|
|`0x0000_0000_0000_0000`&nbsp;to&nbsp;`0x03FF_FFFF_FFFF_FFFF`|2<sup>58</sup>&nbsp;bytes|To Host IOMMU|
|`0x0400_0000_0000_0000` to `0x07FF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Host IOMMU, with PCIe relaxed ordering|
|`0x0800_0000_0000_0000` to `0x0BFF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Host IOMMU, with PCIe no-snoop|
|`0x0C00_0000_0000_0000` to `0x0FFF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Host IOMMU, with PCIe relaxed ordering and PCIe no-snoop|
|`0x1000_0000_0000_0000` to `0x13FF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Outbound iATU, then onwards to Host IOMMU|
|`0x1400_0000_0000_0000` to `0x17FF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Outbound iATU, then onwards to Host IOMMU, with PCIe relaxed ordering|
|`0x1800_0000_0000_0000` to `0x1BFF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Outbound iATU, then onwards to Host IOMMU, with PCIe no-snoop|
|`0x1C00_0000_0000_0000` to `0x1FFF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|To Outbound iATU, then onwards to Host IOMMU, with PCIe relaxed ordering and PCIe no-snoop|
|`0x2000_0000_0000_0000` to `0xF7FF_FFFF_FFFF_FFFF`|54x&nbsp;2<sup>58</sup>&nbsp;bytes|Currently unused TLB windows|
|`0xF800_0000_0000_0000` to `0xFBFF_FFFF_FFFF_FFFF`|2<sup>58</sup> bytes|PCI Express Controller and PHY, similar contents to bar 2 (DBI)|
|`0xFC00_0000_0000_0000` to `0xFFFF_FFFF_DFFF_FFFF`|2<sup>57.999</sup> bytes|Reserved|
|`0xFFFF_FFFF_E000_0000` to `0xFFFF_FFFF_E3FF_FFFF`|64 MiB|1<sup>st</sup> Serdes Configuration|
|`0xFFFF_FFFF_E400_0000` to `0xFFFF_FFFF_E7FF_FFFF`|64 MiB|2<sup>nd</sup> Serdes Configuration|
|`0xFFFF_FFFF_E800_0000` to `0xFFFF_FFFF_EBFF_FFFF`|64 MiB|3<sup>rd</sup> Serdes Configuration|
|`0xFFFF_FFFF_EC00_0000` to `0xFFFF_FFFF_EFFF_FFFF`|64 MiB|Reserved|
|`0xFFFF_FFFF_F000_0000` to `0xFFFF_FFFF_FEFF_FFFF`|240 MiB|PCI Express Controller and PHY, assorted extremely low-level configuration (SII). Includes configuration for the H←N and H←A Configurable TLBs|
|`0xFFFF_FFFF_FF00_0000` to `0xFFFF_FFFF_FFFF_FFFF`|16 MiB|[NIU configuration / status](../NoC/MemoryMap.md)|
