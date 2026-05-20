# NoC (Network on Chip)

Each NoC transaction consists of one or more packets. Each packet consists of one or more flits (exactly one header flit, followed by up to 256 data flits). Each flit consists of exactly 512 bits (64 bytes).

Each NoC is a 2D torus of NoC routers and NIUs (NoC interface units). Packets initiate at an NIU, and terminate at an NIU, with routers moving packets between NIUs. The 2D torus is usually visualized as a 2D grid, where the left/right and top/bottom edges are connected to each other. NoC #0 is usually visualized as:

![](../../Diagrams/Out/NoC_BH_0.svg)

NoC #1 connects the same set of tiles, but is physically separate from NoC #0, and flows in the opposite direction. It is usually visualized as:

![](../../Diagrams/Out/NoC_BH_1.svg)

In [Tensix tiles](../TensixTile/README.md) and Ethernet tiles, the NIU's data paths are connected to [the address space](../TensixTile/BabyRISCV/README.md#memory-map) of the tile, and the NIU's control paths are [exposed as MMIO registers](MemoryMap.md) allowing the RISCV cores to initiate and monitor NoC transactions. The NoC overlay in these tiles can also initiate transactions (along with being informed of particular arriving write requests).

In DRAM tiles, the NIU's data paths are primarily connected to 4 GiB of GDDR6. These tiles also contain one baby RISCV core and a little piece of L1 for said core to use (as in Tensix tiles, "L1" is a misnomer here; this a plain RAM rather than any kind of cache). Each DRAM tile has its own RISCV core and L1, whereas the same 4 GiB of GDDR6 is common across groups of three DRAM tiles.

The PCI Express tile provides two-way translation between NoC transactions and PCIe transactions. In the host-to-device direction, a host-initiated PCIe transaction is first translated to an AXI transaction, which is then translated to a NoC transaction. In the device-to-host direction, a NoC transaction is translated to one or more AXI transactions (to satisfy the maximum transaction size constraint of AXI, and to ensure that AXI transaction addresses do not cross a 4K boundary), and then each AXI transaction is translated to one or more PCIe transactions (for example to satisfy the maximum transaction size constraint of PCIe). Software should generally expect that requests larger than 128 bytes are likely to end up as multiple PCIe transactions.

In L2CPU tiles, the NIU setup is similar in nature to that of PCI Express tiles: the x280-to-NoC direction allows chunks of the NoC to be mapped into the address space seen by the RV64 code running on the x280 cores, and the NoC-to-x280 direction allows requests from outside the tile to interact with [the address space](../L2CPUTile/MemoryMap.md) as seen by the x280 cores.

The NIUs in the ARC tile are connected to the ARC processor, and the NIUs in the Security tile are connected to the security processor. Customer software is unlikely to need to communicate with these NIUs.

Some coordinates in the 2D torus are "empty" tiles: these tiles still contain a router and an NIU, but the only things in the address space of the NIU are the control and status registers of the NIU itself. Customer software is unlikely to need to communicate with these NIUs.

There are various types of request packet:
* **Read**: Contiguous span of data from receiver's address space delivered back to (usually) initiator's address space
* **Write**: Data comes from initiator's address space or 32b immediate, is written to receiver's address space
  * When length is 4 bytes and target is an MMIO address in a Tensix or Ethernet tile: data can be 32b immediate
  * When length ≤ 64 bytes: can write any arbitrary subset of the 64 bytes (otherwise needs to be contiguous span)
  * Optionally posted (i.e. receiver does _not_ send an acknowledgement packet in response once the write completes)
    * Optionally with first 128b of data stored to two separate addresses in receiver's L1
  * Optionally broadcast to a rectangle of multiple receivers (though if so, receivers can only be Tensix tiles)
  * Optionally have NoC overlay in receiver tile(s) notified of the write
* [**Atomic**](Atomics.md): Data is 32b immediate or two 4b immediates, acting on 128b in receiver's [L1](../TensixTile/L1.md#atomics), 32b result delivered back to (usually) initiator's L1
  * Optionally posted (i.e. receiver does _not_ send a response packet containing acknowledgement and 32b of data)
  * Optionally broadcast to a rectangle of multiple receivers (though if so, receivers can only be Tensix tiles)

NoC hardware ensures deadlock freedom for most common types of transaction; however, software becomes partially responsible for this when certain advanced features are used:
  * Transactions containing more than one request packet (c.f. `NOC_CMD_VC_LINKED`)
  * Broadcast _without_ path reservations (c.f. `NOC_CMD_PATH_RESERVE`)
  * Arbitration priorities other than `0` (c.f. `NOC_CMD_ARB_PRIORITY`)

> [!TIP]
> Compared to Wormhole, some of the major upgrades to the NoC in Blackhole are: higher clock speed (1 GHz → 1.35 GHz), doubling of bandwidth per clock cycle (256 bits per flit → 512 bits per flit), and widening of addresses (36 bits → 64 bits). An unfortunate regression means that `NOC_CMD_WR_INLINE` can no longer safely be used to write to L1 addresses.

## Virtual channels

When a packet traverses between two routers (or between a router and an NIU), it is assigned a four-bit number called the virtual channel number. Once a packet has fully traversed the link in question, the virtual channel number is released and becomes available for a different packet to use (†). The four-bit number consists of one dateline bit, two class bits, and one buddy bit. A packet will traverse multiple hops as it gradually transits from the initiating NIU to the receiving NIU, and the virtual channel number can be different on each hop: the dateline bit always flips at certain statically predetermined points along the packet's route, the class bits always remain the same, and the buddy bit can change at each hop in response to network congestion (though for request packets, software can instead choose to have the buddy bit remain static, which gives stronger ordering guarantees at the cost of possibly increased latency). The two class bits have a statically determined purpose which is enforced by hardware:
* `0b00`: Unicast request packets (can use either class)
* `0b01`: Unicast request packets (can use either class)
* `0b10`: Broadcast request packets
* `0b11`: Response packets (always unicast, even when responding to a broadcast)

(†) Transactions containing more than one request packet are slightly special in this regard: the various request packets will each be assigned the same virtual channel number (per hop), and until all request packets have traversed the link in question, the virtual channel number (at that hop) remains reserved for exclusive use by subsequent request packets of the same transaction.

## Ordering

NoC transactions are fairly weakly ordered by default, but can be made stronger - see [NoC Ordering](Ordering.md) for details. If a NoC transaction is initiated by a baby RISCV core (using the [MMIO interface](MemoryMap.md)), then the transaction proceeds asynchronously to RISCV execution; RISCV code can inspect [counters](Counters.md) to determine when the transaction has completed, or use [interrupts](Interrupts.md) to be informed of completion.

## Performance

|Hop type|Throughput (per NoC)|Latency|
|---|---|--:|
|NIU to directly connected router|One flit (512 bits) per cycle|~5 cycles|
|Router to neighbouring router|One flit (512 bits) per cycle per axis|9 cycles|
|Router to directly connected NIU|One flit (512 bits) per cycle|~5 cycles|

[Congestion](RoutingPaths.md#congestion) can negatively impact latency. If software uses the [`NOC_CMD_VC_LINKED` and/or `NOC_CMD_VC_STATIC`](MemoryMap.md#noc_ctrl) flags to enforce particular ordering, then throughput and latency can be negatively impacted: bandwidth might be available, but go unused, because the ordering flags are forcing packets to wait. If software uses the `NOC_CMD_PATH_RESERVE` flag on broadcasts, then the latency of broadcasts is increased, as all routers in the broadcast tree must inform the initiating tile that they're ready to receive the broadcast before any data can leave the initiating tile (if this reservation process fails, then the initiating tile will automatically try again, using randomized exponential backoff).

The amount of _useful_ throughput depends on the ratio of header flits to data flits; very short packets can use just a single header flit to transport 4 bytes of data, whereas very long packets use one header flit and 256 data flits to transport 16384 bytes of data.
