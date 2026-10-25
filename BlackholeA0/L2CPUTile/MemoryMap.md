# L2CPU Tile Memory Map

## NoC address space

Requests coming over the NoC see a 64-bit address space:

|Address range (NoC)|Size|Contents|
|---|--:|---|
|`0x0000_0000_0000_0000`&nbsp;to&nbsp;`0x0000_7FFF_FFFF_FFFF`|2<sup>47</sup>&nbsp;bytes|Passthrough to [x280 physical address space](#x280-physical-address-space)|
|`0x0000_8000_0000_0000` to `0xFFFF_F7FE_FFEF_FFFF`|Very&nbsp;large|Reserved, though in practice 131,071 copies of previous 2<sup>47</sup> bytes (albeit final copy isn't quite complete)|
|`0xFFFF_F7FE_FFF0_0000` to `0xFFFF_F7FE_FFF7_FFFF`|512 KiB|[External peripherals](#external-peripherals), notably including TLB window configuration|
|`0xFFFF_F7FE_FFF8_0000` to `0xFFFF_FFFF_FEFF_FFFF`|~8 TiB|Reserved|
|`0xFFFF_FFFF_FF00_0000` to `0xFFFF_FFFF_FFFF_FFFF`|16 MiB|[NIU configuration / status](../NoC/MemoryMap.md) (of whichever NoC is used for the request)|

## x280 physical address space

All four x280 cores see the same 47-bit physical address space:

|Address range (x280 physical)|Size|Contents|
|---|--:|---|
|`0x0000_0000_0000` to `0x0000_1FFF_FFFF`|512 MiB|[Internal devices](#internal-devices), notably including L2 and L3 cache configuration|
|`0x0000_2000_0000` to `0x0000_2007_FFFF`|512 KiB|[External peripherals](#external-peripherals), notably including TLB window configuration|
|`0x0000_2008_0000` to `0x0000_2008_0FFF`|4 KiB|DMA engine configuration and command|
|`0x0000_2008_1000` to `0x0000_200F_FFFF`|127x 4 KiB|Reserved, though in practice 127 copies of previous 4 KiB|
|`0x0000_2010_0000` to `0x0000_2FFF_FFFF`|255x 1 MiB|Reserved, though in practice 255 copies of previous (512 KiB + 4 KiB + 127x 4 KiB)|
|`0x0000_3000_0000` to `0x0001_2FFF_FFFF`|4 GiB|Contents of local GDDR6 tile, uncached|
|`0x0001_3000_0000` to `0x0004_2FFF_FFFF`|3x 4 GiB|Reserved, though in practice 3 copies of previous 4 GiB|
|`0x0004_3000_0000` to `0x0004_4BFF_FFFF`|224x 2 MiB|[Small TLB windows to NoC](TLBWindows.md), uncached|
|`0x0004_4C00_0000` to `0x0004_4FFF_FFFF`|32x 2 MiB|Undefined|
|`0x0004_5000_0000` to `0x0804_2FFF_FFFF`|16383x&nbsp;512&nbsp;MiB|Reserved, though in practice 16,383 copies of previous (224x 2 MiB + 32x 2 MiB)|
|`0x0804_3000_0000` to `0x0C04_2FFF_FFFF`|32x 128 GiB|[Large TLB windows to NoC](TLBWindows.md), uncached|
|`0x0C04_3000_0000` to `0x1004_2FFF_FFFF`|32x 128 GiB|Reserved, though in practice copy of previous 32x 128 GiB|
|`0x1004_3000_0000` to `0x4000_2FFF_FFFF`|~3x 16 TiB|Reserved, though in practice 3 copies of previous 16 TiB (albeit final copy is 16 GiB short)|
|`0x4000_3000_0000` to `0x4001_2FFF_FFFF`|4 GiB|Contents of local GDDR6 tile, [cached](Caches.md)|
|`0x4001_3000_0000` to `0x4004_2FFF_FFFF`|3x 4 GiB|Reserved, though in practice 3 copies of previous 4 GiB|
|`0x4004_3000_0000` to `0x4004_4BFF_FFFF`|224x 2 MiB|[Small TLB windows to NoC](TLBWindows.md), [cached](Caches.md)|
|`0x4004_4C00_0000` to `0x4004_4FFF_FFFF`|32x 2 MiB|Undefined|
|`0x4004_5000_0000` to `0x4804_2FFF_FFFF`|16383x 512 MiB|Reserved, though in practice 16,383 copies of previous (224x 2 MiB + 32x 2 MiB)|
|`0x4804_3000_0000` to `0x4C04_2FFF_FFFF`|32x 128 GiB|[Large TLB windows to NoC](TLBWindows.md), [cached](Caches.md)|
|`0x4C04_3000_0000` to `0x5004_2FFF_FFFF`|32x 128 GiB|Reserved, though in practice copy of previous 32x 128 GiB|
|`0x5004_3000_0000`&nbsp;to&nbsp;`0x7FFF_FFFF_FFFF`|~3x 16 TiB|Reserved, though in practice 3 copies of previous 16 TiB (albeit final copy is 16¾ GiB short)|

Where the same TLB window (or GDDR) exists multiple times in the physical address space, the cache subsystem is unaware that they alias. As such, if caching is desired, each 64-byte cache line should be consistently accessed through exactly one cached address. If caching is not desired, any mixture of uncached addresses can be used, although appropriate memory ordering will be easier to enforce if the same address is used for all accesses.

## x280 virtual address space

If the MMU is enabled, software can define an arbitrary 39-bit or 48-bit address space for code executing in user mode / supervisor mode, subject to:
* The 39-bit or 48-bit address space is formed from two equal-size pieces; one piece starting at the low end of the 64-bit address range, and the other ending at the high end of the 64-bit address range. Addresses outside either of these pieces are considered non-canonical, and will cause page faults.
* The address space is defined at page granularity, where each page can be 4 KiB, 2 MiB, 1 GiB, or ½ TiB. Pages must be aligned to their size, both virtually and physically.

Software typically defines a separate virtual address space per process. Hardware supports 16-bit ASID values to aid with this.

Eight PMP regions can be defined in addition to page tables. Physical addresses which fall outside of any PMP region are given default permissions based on the execution mode:
* User mode: default is no permissions.
* Supervisor mode: default is no permissions.
* Machine mode: default is all permissions (subject to the physical memory attributes of the address being accessed).

## Internal devices

Part of the x280 physical address space is used for various internal devices. For the most part, these devices behave similarly to those of other SiFive cores of a similar vintage in products from other vendors.

|Address range (x280 physical)|Size|Contents|
|---|--:|---|
|`0x0000_0000_0000` to `0x0000_0000_0FFF`|4 KiB|Usually unmapped, but when accessed by a hart operating in debug mode, is instead the Debug Device|
|`0x0000_0000_1000` to `0x0000_0000_2FFF`|8 KiB|Unmapped|
|`0x0000_0000_3000` to `0x0000_0000_3FFF`|4 KiB|Error Device (all accesses return an error)|
|`0x0000_0000_4000` to `0x0000_0000_4FFF`|4 KiB|Test Indicator Device (4 mutable bytes, then 4092 reserved bytes)|
|`0x0000_0000_5000` to `0x0000_016F_FFFF`|22.98 MiB|Unmapped|
|`0x0000_0170_0000` to `0x0000_0170_0FFF`|4 KiB|Hart 0 Bus-Error Unit|
|`0x0000_0170_1000` to `0x0000_0170_1FFF`|4 KiB|Hart 1 Bus-Error Unit|
|`0x0000_0170_2000` to `0x0000_0170_2FFF`|4 KiB|Hart 2 Bus-Error Unit|
|`0x0000_0170_3000` to `0x0000_0170_3FFF`|4 KiB|Hart 3 Bus-Error Unit|
|`0x0000_0170_4000` to `0x0000_01FF_FFFF`|8.98 MiB|Unmapped|
|`0x0000_0200_0000` to `0x0000_0200_FFFF`|64 KiB|Core-local interruptor (CLINT)|
|`0x0000_0201_0000` to `0x0000_0201_3FFF`|16 KiB|[L3 cache configuration and explicit flush](Caches.md#l3-cache)|
|`0x0000_0201_4000` to `0x0000_0202_FFFF`|112 KiB|Unmapped|
|`0x0000_0203_0000` to `0x0000_0203_1FFF`|8 KiB|[Hart 0 L2 prefetcher configuration](Caches.md#l2-cache)|
|`0x0000_0203_2000` to `0x0000_0203_3FFF`|8 KiB|[Hart 1 L2 prefetcher configuration](Caches.md#l2-cache)|
|`0x0000_0203_4000` to `0x0000_0203_5FFF`|8 KiB|[Hart 2 L2 prefetcher configuration](Caches.md#l2-cache)|
|`0x0000_0203_6000` to `0x0000_0203_7FFF`|8 KiB|[Hart 3 L2 prefetcher configuration](Caches.md#l2-cache)|
|`0x0000_0203_8000` to `0x0000_0300_7FFF`|15.81 MiB|Unmapped|
|`0x0000_0300_8000` to `0x0000_0300_8FFF`|4 KiB|All harts `wfi` / `cease` status (SLPC)|
|`0x0000_0300_9000` to `0x0000_07FF_FFFF`|79.96 MiB|Unmapped|
|`0x0000_0800_0000` to `0x0000_081F_FFFF`|2 MiB|[L3 as uncached scratchpad (LIM)](Caches.md#l3-cache)|
|`0x0000_0820_0000` to `0x0000_09FF_FFFF`|30 MiB|Unmapped|
|`0x0000_0A00_0000` to `0x0000_0A1F_FFFF`|2 MiB|[Zero Device, cached](Caches.md#l3-cache)|
|`0x0000_0A20_0000` to `0x0000_0BFF_FFFF`|30 MiB|Unmapped|
|`0x0000_0C00_0000` to `0x0000_0FFF_FFFF`|64 MiB|Platform-level interrupt controller (PLIC)|
|`0x0000_1000_0000` to `0x0000_1000_0FFF`|4 KiB|Hart 0 trace encoder configuration|
|`0x0000_1000_1000` to `0x0000_1000_1FFF`|4 KiB|Hart 1 trace encoder configuration|
|`0x0000_1000_2000` to `0x0000_1000_2FFF`|4 KiB|Hart 2 trace encoder configuration|
|`0x0000_1000_3000` to `0x0000_1000_3FFF`|4 KiB|Hart 3 trace encoder configuration|
|`0x0000_1000_4000` to `0x0000_1001_7FFF`|80 KiB|Unmapped|
|`0x0000_1001_8000` to `0x0000_1001_8FFF`|4 KiB|Trace funnel configuration|
|`0x0000_1001_9000` to `0x0000_1010_3FFF`|940 KiB|Unmapped|
|`0x0000_1010_4000` to `0x0000_1010_7FFF`|16 KiB|[Hart 0 L2 cache configuration and explicit flush](Caches.md#l2-cache)|
|`0x0000_1010_8000` to `0x0000_1010_BFFF`|16 KiB|[Hart 1 L2 cache configuration and explicit flush](Caches.md#l2-cache)|
|`0x0000_1010_C000` to `0x0000_1010_FFFF`|16 KiB|[Hart 2 L2 cache configuration and explicit flush](Caches.md#l2-cache)|
|`0x0000_1011_0000` to `0x0000_1011_3FFF`|16 KiB|[Hart 3 L2 cache configuration and explicit flush](Caches.md#l2-cache)|
|`0x0000_1011_4000`&nbsp;to&nbsp;`0x0000_1FFF_FFFF`|254.92&nbsp;MiB|Unmapped|

## External peripherals

When coming from the NoC, external peripherals can be accessed either through the x280 physical address space (where they start at `0x0000_2000_0000`), or through an alternative high address which bypasses the x280 cores. In the latter case, external peripherals start at `0xFFFF_F7FE_FFF0_0000`; an offset of `0xFFFF_F7FE_DFF0_0000` should be added to all addresses in the below table to get the equivalent high addresses.

|Address range (x280 physical)|Size|Contents|
|---|--:|---|
|`0x0000_2000_0000` to `0x0000_2000_0DFF`|224x 16 B|[Small TLB window configuration](TLBWindows.md#configuration)|
|`0x0000_2000_0E00` to `0x0000_2000_0F7F`|32x 12 B|[Large TLB window configuration](TLBWindows.md#configuration)|
|`0x0000_2000_0F80` to `0x0000_2000_FFFF`|60.1 KiB|Reserved|
|`0x0000_2001_0000` to `0x0000_2001_001F`|4x 8 B|Per-hart reset handler address (initial `pc` when coming out of reset)|
|`0x0000_2001_0020` to `0x0000_2001_00FF`|224 B|Reserved|
|`0x0000_2001_0100` to `0x0000_2001_013F`|64 B|General purpose scratch memory|
|`0x0000_2001_0140` to `0x0000_2001_03FF`|704 B|Reserved|
|`0x0000_2001_0400` to `0x0000_2001_0401`|2 B|All harts `cease` / `halt` / `wfi` / `debug` status|
|`0x0000_2001_0402` to `0x0000_2001_0403`|2 B|All harts suppress instruction fetch flags (1 bit per hart, then 12 reserved bits, only applicable when coming out of reset)|
|`0x0000_2001_0404` to `0x0000_2001_0413`|16 B|Global interrupt signals (connected to the PLIC)|
|`0x0000_2001_0414` to `0x0000_2001_0417`|4 B|All harts [RNMI](RNMIs.md) interrupt signals (1 bit per hart, then 28 reserved bits)|
|`0x0000_2001_0418` to `0x0000_2001_0457`|4x 16 B|Per-hart [RNMI](RNMIs.md) trap handler address and RNMI exception trap handler address|
|`0x0000_2001_0458` to `0x0000_2005_5FFF`|278.9 KiB|Reserved|
|`0x0000_2005_6000` to `0x0000_2005_6FFF`|4 KiB|[NIU #0 configuration / status](../NoC/MemoryMap.md)|
|`0x0000_2005_7000` to `0x0000_2005_7FFF`|4 KiB|[NIU #1 configuration / status](../NoC/MemoryMap.md)|
|`0x0000_2006_0000` to `0x0000_2006_000F`|16 B|[MSI catcher](MSICatcher.md) (memory-mapped FIFO with an interrupt wire to the PLIC)|
|`0x0000_2006_0010`&nbsp;to&nbsp;`0x0000_2007_FFFF`|127.98&nbsp;KiB|Reserved|
