# Caches in L2CPU Tiles

Each L2CPU tile contains a variety of hardware caches.

## L1 Instruction Cache

Instruction fetch is always performed through the L1 instruction cache, which is a 32 KiB 2-way virtually-indexed physically-tagged cache with 64-byte lines. The instruction cache can fetch from, and therefore code execution is possible from, any of:
* The L2 or L3 caches (i.e. all data-cacheable addresses are executable, and executing from them will load the cache line into all of L1I and L2 and L3 if not present in L1I). For reference, the data-cacheable physical address ranges are:
  * Zero Device, cached: `0x0000_0A00_0000` to `0x0000_0A1F_FFFF`
  * Contents of local GDDR6 tile, cached: `0x4000_3000_0000` to `0x4001_2FFF_FFFF`
  * [Small TLB windows to NoC](TLBWindows.md), cached: `0x4004_3000_0000` to `0x4004_3DFF_FFFF`
  * [Large TLB windows to NoC](TLBWindows.md), cached: `0x4804_3000_0000` to `0x4C04_2FFF_FFFF`
* The uncached variants of the above (execution from which _will_ be cached in L1I, but not in L2 nor in L3):
  * L3 as uncached scratchpad (LIM): `0x0000_0800_0000` to `0x0000_081F_FFFF`
  * Contents of local GDDR6 tile, uncached: `0x0000_3000_0000` to `0x0001_2FFF_FFFF`
  * [Small TLB windows to NoC](TLBWindows.md), uncached: `0x0004_3000_0000` to `0x0004_3DFF_FFFF`
  * [Large TLB windows to NoC](TLBWindows.md), uncached: `0x0804_3000_0000` to `0x0C04_2FFF_FFFF`
* External peripherals (execution from which _will_ be cached in L1I, but not in L2 nor in L3):
  * General purpose scratch memory: `0x0000_2001_0100` to `0x0000_2001_013F`
  * Anything else spare in the range: `0x0000_2000_0000` to `0x0000_2007_FFFF`

The L1 instruction cache is not coherent with any higher level caches (it can fetch from them, but subsequent changes or flushes in the higher level caches do not impact the contents of the L1 instruction cache). Each hart has its own L1 instruction cache, and the entire contents of its L1 instruction cache will be discarded whenever the hart executes a `fence.i` instruction. Notably, only the hart itself can perform this cache invalidation; nothing else can. Software is encouraged to build a mechanism to allow external actors to perform this invalidation, for example through inter-processor interrupts (IPIs) or resumable non-maskable interrupts (RNMIs).

## L1 Data Cache

Each hart has its own L1 data cache, which is a 32 KiB 4-way virtually-indexed physically-tagged cache with 64-byte lines. The data-cacheable physical address ranges are:
* Zero Device, cached: `0x0000_0A00_0000` to `0x0000_0A1F_FFFF`
* Contents of local GDDR6 tile, cached: `0x4000_3000_0000` to `0x4001_2FFF_FFFF`
* Small TLB windows to NoC, cached: `0x4004_3000_0000` to `0x4004_3DFF_FFFF`
* Large TLB windows to NoC, cached: `0x4804_3000_0000` to `0x4C04_2FFF_FFFF`

The L1 data cache is coherent with the higher level L2 and L3 caches, and also inclusive of them: fetching data to L1D will also populate it in L2 and L3. Evicting modified data from L1D will write it back to L2.

The RISCV `A` Extension for Atomic Instructions (both "Zalrsc" and "Zaamo") is implemented at the L1 data cache. If the address range in question comes from the local GDDR6 tile or TLB windows to the NoC, accesses _not_ performed through the L1 / L2 / L3 caches will only see the consequences of atomic instructions once the entire cache line is evicted out of all the caches.

Each hart's L1 data cache supports only one outstanding cache line fill at a time. In other words, upon suffering an L1 data cache miss, that miss must be fully resolved before another miss can be handled: misses cannot be handled in parallel. This can result in very poor performance for code which suffers lots of L1 data cache misses, especially if resolving the miss requires performing a NoC read-request to populate a cache line.

The custom [`cflush.d.l1`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/src/cache.c#L176) / [`cdiscard.d.l1`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/src/cache.c#L215) instructions are available in M mode to allow a hart to flush / discard its own L1 data cache. Alternatively, as the cache is inclusive, software can flush data out of L1 by flushing it out of L2 or L3.

## L2 Cache

Each hart has its own L2 cache, which is a 128 KiB 8-way cache with 64-byte lines.

The L2 cache is coherent with the higher level L3 cache, and also inclusive of it: fetching an address to L2 will also populate it in L3. Evicting modified data from L2 will write it back to L3.

A few memory-mapped registers are present in the x280 physical address space for performing L2 management operations, where `BASE` is `0x0000_1010_4000 + HART_ID * 0x4000`:

|Address|Name|Size|Purpose|
|---|---|--:|---|
|`BASE + 0x0000`|`PL2CACHE0_CONFIG`|4x 8 bits|Read-only description of L2 cache topology|
|`BASE + 0x0200`|`PL2CACHE0_CFLUSH64`|64 bits|Write-only to enqueue a flush command|
|`BASE + 0x0208`|`PL2CACHE0_FLUSHCOUNT`|8 bits|Read-only number of enqueued flush commands still pending|
|`BASE + 0x1008`|`PL2CACHE0_CONFIGBITS`|32x 1 bit|Various configurable behavior bits|

See [`sifive_pl2cache0.h`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/metal/drivers/sifive_pl2cache0.h) and [`sifive_pl2cache0.c`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/src/drivers/sifive_pl2cache0.c) for examples of using these registers.

The L2 cache includes a prefetcher. A pair of memory-mapped registers are present in the x280 physical address space for configuring the L2 prefetcher, where `BASE` is `0x0000_0203_0000 + HART_ID * 0x2000`:

|Address|Name|Size|
|---|---|--:|
|`BASE + 0x0000`|`L2PF1_BASIC_CONTROL`|32 bits|
|`BASE + 0x0004`|`L2PF1_USER_CONTROL`|32 bits|

See [`sifive_l2pf1.h`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/metal/drivers/sifive_l2pf1.h) and [`sifive_l2pf1.c`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/src/drivers/sifive_l2pf1.c) for examples of using these registers. In particular, the [recommended initialization sequence](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/src/drivers/sifive_l2pf1.c#L152) is to write `0x15811` to `L2PF1_BASIC_CONTROL` and `0x38c84e` to `L2PF1_USER_CONTROL`.

## L3 Cache

Each L2CPU tile contains a shared L3 cache. This cache is built from 16x 128 KiB pieces (for a total capacity of 2 MiB), where each piece can be individually configured as one of:
* **Regular cache way:** The 64-byte cache lines can be populated from any data-cacheable physical address, and then subsequently flushed in response to cache pressure or explicit flush commands.
* **Pinned cache way:** The 64-byte cache lines can be populated from any data-cacheable physical address, but once populated and pinned are never flushed in response to cache pressure - only in response to explicit flush commands.
* **Uncached scratchpad (LIM):** The 128 KiB of storage is used as uncached scratchpad memory, accessed through particular physical addresses in the range `0x0000_0800_0000` to `0x0000_081F_FFFF`.

When coming out of reset, one 128 KiB piece is configured as a regular cache way, and the other 15x 128 KiB are configured as uncached scratchpad (LIM). Software can write to the `CCACHE0_WAYENABLE` MMIO register to increase the number of pieces used as cache ways (and correspondingly decrease the number of pieces used as uncached scratchpad), up to a maximum of all 16 pieces used as cache ways. Once a piece has been configured for use as a cache way, it cannot be changed back to uncached scratchpad other than by resetting the entire Blackhole ASIC (e.g. with `tt-smi -r`), however it can be freely changed back and forth between being a regular cache way and a pinned cache way.

Pinned cache ways are particularly useful in combination with the Zero Device. The Zero Device discards all writes, and reads always return zero, but the cache (intentionally) does not know this: it caches the Zero Device in the same way as it caches regular memory. As such, a pinned cache way which has been populated from the Zero Device behaves like a cached scratchpad, and will retain its contents until explicitly flushed (at which point the contents will be written back to the Zero Device, which will discard the write). Lines from a pinned way can be fetched into the per-hart L1 and L2 caches, and if those caches subsequently flush such a line, it'll be written back to the higher level cache (L1D → L2, L2 → L3).

The L3 cache is coherent with, and inclusive of, the L2 and L1D caches underneath it. If the NoC performs an access to a data-cacheable physical address, that access will be performed through the L3 cache, and therefore also be coherent with the caches. Note that cache coherence does not extend beyond the bounds of an individual L2CPU tile, and in particular there is no coherence between caches of different L2CPU tiles.

A few memory-mapped registers are present in the x280 physical address space for performing L3 management operations:

|Address|Name|Size|Purpose|
|---|---|--:|---|
|`0x0000_0201_0000`|`CCACHE0_CONFIG`|4x 8 bits|Read-only description of L3 cache topology|
|`0x0000_0201_0008`|`CCACHE0_WAYENABLE`|4 bits|Increase-only number of pieces used as cache ways|
|`0x0000_0201_0200`|`CCACHE0_FLUSH64`|64 bits|Write-only to flush a particular line (using a 64-bit physical address)|
|`0x0000_0201_0240`|`CCACHE0_FLUSH32`|32 bits|Write-only to flush a particular line (using a 36-bit physical address, low four bits implied zero)|
|`0x0000_0201_0800`|`CCACHE0_WAYMASK0`|38x&nbsp;64&nbsp;bits|Per-master cache way masking|

Writing the value `N` to `CCACHE0_WAYENABLE` (where `0 ≤ N ≤ 15`) will cause:
* No effect if the written value is smaller than the previously stored value. Otherwise:
* The L3 cache to have `N + 1` ways, and therefore cache capacity `(N + 1) * 128 KiB`.
* L3 as uncached scratchpad (LIM) to have capacity `(15 - N) * 128 KiB`, starting at physical address `0x0000_0800_0000`, and continuing up until its capacity is reached.
* The low `N + 1` bits of each `CCACHE0_WAYMASK0` entry to be relevant.

The array at `CCACHE0_WAYMASK0` is used to configure pinning (and partial pinning). Each array element is 64 bits, though only the low 16 bits of each entry are used, and said low bits correspond 1:1 with cache ways. When an L3 cache master needs to evict a cache line to make space for a new line, this 16-bit mask controls which cache ways it can evict from. A cache way will be pinned if it is cleared from every master's mask. Meanwhile, pinning with particular contents can be performed via careful mask manipulation:
1. Clear the cache way from every master's mask, except for the master which will perform the population.
2. The master which will perform the population should set its mask to _just_ the cache way intended to be populated.
3. The master which will perform the population can then populate the cache way by performing appropriate loads / stores.
4. Clear the cache way from every master's mask.

The 38 array elements at `CCACHE0_WAYMASK0` correspond exactly to the 38 different L3 master IDs:

|Master&nbsp;ID|Master Name|
|--:|---|
|0|Debug Device|
|1<br/>to 32|NoC or DMA Engine (each request will use one of the IDs in this range, but it is not specified exactly which, and software should assume that any request could use any ID)|
|33|Trace sink|
|34|Hart 0 L2 cache|
|35|Hart 1 L2 cache|
|36|Hart 2 L2 cache|
|37|Hart 3 L2 cache|

See [`sifive_ccache0.h`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/metal/drivers/sifive_ccache0.h) and [`sifive_ccache0.c`](https://github.com/sifive/freedom-metal/blob/fa026d2ee08e5ba49e8ae703fb4cbcbb710a6a69/src/drivers/sifive_ccache0.c) for examples of using these registers. In particular, the recommended initialization sequence is to write `15` to `CCACHE0_WAYENABLE` and `0xFFFF` to every `CCACHE0_WAYMASK0` entry, thereby allocating all 2 MiB to regular cache ways, and nothing at all to L3 as uncached scratchpad (LIM). If coming directly out of reset, the writes to `CCACHE0_WAYMASK0` can be skipped, as `0xFFFF` is the default value for every entry.

## MMU TLBs

If the MMUs are in use, each MMU will make use of a TLB cache contained within it. Despite the similar name, this mechanism is totally distinct from TLB windows to the NoC: the MMU TLBs are for _caching_ virtual-to-physical address translations, whereas the TLB windows to the NoC are for _defining_ the physical-to-NoC address mapping.

Each MMU has:
* 64 entry fully-associative L1I TLB cache
* 64 entry fully-associative L1D TLB cache
* 1024 entry direct-mapped L2 TLB cache

If an address translation misses both the L1I/L1D and L2 TLB caches, hardware will initiate a page table walk to populate the caches, starting from the root pointer in the `satp` CSR. This walker can snoop page table data from L1D, and otherwise will fetch page table data to the L2 and L3 caches (for page tables existing in data-cacheable addresses).

The MMU TLB caches are not coherent. Software needs to make use of the `sfence.vma` instruction to maintain the illusion of coherency. As with `fence.i`, `sfence.vma` only affects the hart on which it is executed, so software is encouraged to build a mechanism to allow external actors to perform this invalidation, for example through inter-processor interrupts (IPIs) or resumable non-maskable interrupts (RNMIs).
