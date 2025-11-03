# L2CPU Tile TLB Windows to NoC

There are 256 configurable TLB windows, which exist at particular places in the x280 physical address space. Each window can be pointed at an aligned region of the address space of any tile in the NoC, and once appropriately pointed, can be accessed with either:
* **Uncached semantics:** Every memory load or store against the window becomes a NoC request.
* **Cached semantics:** A memory load or store against the window becomes a 64-byte NoC read request to populate the cache line (if not already present in the [cache hierarchy](Caches.md)), and then at some later point in time (in response to cache pressure or an explicit flush request), a 64-byte NoC write request is used to write back the data. The L2 prefetcher can also speculatively fetch other cache lines within the same aligned 4 KiB region.

The relevant physical addresses are:

|Address range (x280 physical)|Size|Contents|
|---|--:|---|
|`0x0000_2??0_0000` to `0x0000_2??0_0DFF` (†)|224x 16 B|Small TLB window configuration|
|`0x0000_2??0_0E00` to `0x0000_2??0_0F7F` (†)|32x 12 B|Large TLB window configuration|
|`0x0004_3000_0000` to `0x0004_3DFF_FFFF`|224x 2 MiB|Small TLB windows to NoC, uncached|
|`0x0804_3000_0000` to `0x0C04_2FFF_FFFF`|32x 128 GiB|Large TLB windows to NoC, uncached|
|`0x4004_3000_0000` to `0x4004_3DFF_FFFF`|224x 2 MiB|Small TLB windows to NoC, [cached](Caches.md)|
|`0x4804_3000_0000` to `0x4C04_2FFF_FFFF`|32x 128 GiB|Large TLB windows to NoC, [cached](Caches.md)|

> (†) The `??` can be filled in with any 8-bit value. Typically either `0x00` or `0xFF` is used.

## Configuration

Each small TLB window has 16 bytes of configuration, consisting of:
```c
uint64_t local_offset;
uint32_t noc_properties_lo;
uint32_t noc_properties_hi;
```

Each large TLB window has 12 bytes of configuration, consisting of:
```c
uint32_t local_offset;
uint32_t noc_properties_lo;
uint32_t noc_properties_hi;
```

When a TLB is accessed, hardware needs to form a 64-bit address within the target tile(s). For small TLB windows, the low 21 bits come from the accessed offset within the 2 MiB window, and the high 43 bits come from the low 43 bits of `local_offset` (the remaining bits of `local_offset` have no effect). For large TLB windows, the low 37 bits come from the accessed offset within the 128 GiB window, and the high 27 bits come from the low 27 bits of `local_offset` (the remaining bits of `local_offset` have no effect).

The contents of `noc_properties_lo` is identical for both sizes of window:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|6|`x_end`|When <code>mcast</code> is set, the <a href="../NoC/Coordinates.md">X coordinate</a> of the end of the multicast rectangle. Otherwise the X coordinate of the single target tile.|
|6|6|`y_end`|When <code>mcast</code> is set, the <a href="../NoC/Coordinates.md">Y coordinate</a> of the end of the multicast rectangle. Otherwise the Y coordinate of the single target tile.|
|12|6|`x_start`|When <code>mcast</code> is set, the <a href="../NoC/Coordinates.md">X coordinate</a> of the start of the multicast rectangle. Ignored otherwise.|
|18|6|`y_start`|When <code>mcast</code> is set, the <a href="../NoC/Coordinates.md">Y coordinate</a> of the start of the multicast rectangle. Ignored otherwise.|
|24|1|`mcast`|Equivalent to <code>NOC_CMD_BRCST_PACKET</code>; <code>true</code> causes <code>(x_start, y_start)</code> through <code>(x_end, y_end)</code> to specify a rectangle of target Tensix tiles, whereas <code>false</code> causes <code>(x_end, y_end)</code> to specify a single tile target.|
|25|2|`ordering`|Four possible ordering modes:<ul><li><code>0</code> - Default</li><li><code>1</code> - Strict AXI</li><li><code>2</code> - Posted Writes</li><li><code>3</code> - Counted Writes</li></ul>|
|27|1|`linked`|Similar to <a href="../NoC/MemoryMap.md#noc_ctrl"><code>NOC_CMD_VC_LINKED</code></a>. When using cached semantics, it is hard to safely set this to <code>true</code>, as software cannot easily control when NoC requests are made.|
|28|1|`static_vc`|Equivalent to <a href="../NoC/MemoryMap.md#noc_ctrl"><code>NOC_CMD_VC_STATIC</code></a>|
|29|2|Reserved|Software should write as zero.|
|31|1|`noc_sel`|<code>0</code> to select NoC #0, <code>1</code> to select NoC #1.|

The contents of `noc_properties_hi` is also identical for both sizes of window:

|First&nbsp;bit|#&nbsp;Bits|Name|Purpose|
|--:|--:|---|---|
|0|1|`static_vc_buddy`|When <code>static_vc</code> is set, the buddy bit. Ignored otherwise.|
|1|2|`static_vc_class`|When <code>static_vc</code> is set, the class bits (which must be either <code>0b00</code> or <code>0b01</code> for unicast requests, and must be <code>0b10</code> for multicast requests). Ignored otherwise.|
|3|2|`x_keep`|If both `x_keep` and `x_skip` are non-zero, the X axis of the multicast rectangle will be masked: starting at `x_start`, `x_keep` tiles will receive the multicast, then `x_skip` tiles will be skipped, then `x_keep` tiles will receive the multicast, then `x_skip` tiles will be skipped, and so forth. If `x_keep + x_skip` is not a power of two, then `x_start` needs to be less than or equal to `x_end`. Note that the keep/skip pattern is applied to raw NoC #0 or NoC #1 coordinates.|
|5|2|`x_skip`|See `x_keep`.|
|7|2|`y_keep`|If both `y_keep` and `y_skip` are non-zero, the Y axis of the multicast rectangle will be masked: starting at `y_start`, `y_keep` tiles will receive the multicast, then `y_skip` tiles will be skipped, then `y_keep` tiles will receive the multicast, then `y_skip` tiles will be skipped, and so forth. If `y_keep + y_skip` is not a power of two, then `y_start` needs to be less than or equal to `y_end`. Note that the keep/skip pattern is applied to raw NoC #0 or NoC #1 coordinates.|
|9|2|`y_skip`|See `y_keep`.|
|11|5|`x_exclude_coord`|When `apply_exclusion` is `true`, an [X coordinate](../NoC/Coordinates.md). Note that coordinate translation is not applied to this; it is a raw NoC #0 or NoC #1 coordinate. Interpretation depends on `x_exclude_direction`.|
|16|4|`y_exclude_coord`|When `apply_exclusion` is `true`, a [Y coordinate](../NoC/Coordinates.md). Note that coordinate translation is not applied to this; it is a raw NoC #0 or NoC #1 coordinate. Interpretation depends on `y_exclude_direction`.|
|20|1|`x_exclude_direction`|When `apply_exclusion` is `true`, `x_exclude_direction` being `true` means that `x >= x_exclude_coord` are excluded, whereas `x_exclude_direction` being `false` means that `x <= x_exclude_coord` are excluded (the exact formulation is more complex when `x_start > x_end`).|
|21|1|`y_exclude_direction`|When `apply_exclusion` is `true`, `y_exclude_direction` being `true` means that `y >= y_exclude_coord` are excluded, whereas `y_exclude_direction` being `false` means that `y <= y_exclude_coord` are excluded (the exact formulation is more complex when `y_start > y_end`).|
|22|1|`apply_exclusion`|Whether to exclude a quadrant from the multicast rectangle.|
|23|1|`optimize_routing_for_exclusion`||
|24|8|`num_destinations_override`|Software must set this to the number of tiles which will receive the multicast. If there is no skipping and `apply_exclusion` is `false`, software can set this to zero, in which case hardware will substitute the correct value.|

> [!TIP]
> `noc_properties_lo` and `noc_properties_hi` are functionally identical to the configuration bits used for [PCI Express tile host-to-device TLBs](../PCIExpressTile/HostToDeviceTLBs.md#configuration), but some fields have been reordered.
