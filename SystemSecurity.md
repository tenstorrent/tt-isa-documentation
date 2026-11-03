# Security and Isolation at the System Level

Wormhole and Blackhole do not confine the code that runs on them. Every RISCV core in a Tensix, Ethernet or DRAM tile has full access to its own tile and can send [NoC](WormholeB0/NoC/README.md) requests to any tile on the ASIC, and the NoC also carries requests out to the host and, over Ethernet, to other ASICs. Containment therefore has to come from the system around the device: the host's IOMMU, the kernel driver's mappings, who is allowed to run device code, and how devices are reset and cabled.

This page describes what device code can reach on Wormhole and Blackhole, and recommends how to build systems on them so that a buggy or malicious kernel (or a process that has the device open) can't reach further than intended. It is written for system builders, and for the authors of kernel drivers, runtimes and serving stacks. Kernel authors mostly need two rules from it: always use the initiating NIU's own coordinates for responses, and never address a tile whose clock is disabled (fused off, or turned off for power).

## What device code can reach

### One protection domain per core

The Baby RISCV cores have no privilege levels, no memory protection and no address translation. On Wormhole they have no CSRs at all; on Blackhole `mstatus` is a constant and there is no PMP and no `satp`. Firmware and kernels running on a core therefore share one protection domain, and nothing on the core restricts which addresses it can load from, store to, or name in a NoC request.

### Every tile on the ASIC

Any NoC request initiator can read and write the L1, the memory-mapped registers and (through the DRAM tiles) the DRAM of every tile on the ASIC. That includes registers which control other tiles:
* [`RISCV_DEBUG_REG_SOFT_RESET_0`](WormholeB0/TensixTile/SoftReset.md) of any tile, so device code can halt or restart any other tile's cores.
* [`NIU_CFG_0`](WormholeB0/NoC/MemoryMap.md#niu_cfg_0) of any NIU, including the tile clock disable (bit 12) and coordinate translation enable (bit 14), along with the coordinate translation tables and the router configuration (including the row and column masks that multicasts use to skip tiles).
* The [NIU request initiators](WormholeB0/NoC/MemoryMap.md#niu-request-initiators) of any other tile, so device code can make another tile issue NoC requests on its behalf.
* On Wormhole, the ARC tile's CSM and its APB peripherals, including the [Reset Unit](WormholeB0/ARCTile/ResetUnit.md), through the [NoC to ARC tile](WormholeB0/ARCTile/README.md#noc-to-arc-tile-64-gib) address range.

### Responses go wherever the request says

A read's response goes to the X/Y coordinates and address in [`NOC_RET_ADDR`](WormholeB0/NoC/MemoryMap.md#noc_targ_addr-and-noc_ret_addr), and a write's acknowledgement goes to the X/Y coordinates in `NOC_TARG_ADDR`. The NIU that receives a response does not check that it asked for it: it writes read data into its L1 at the address the response carries, and counts acknowledgements as it counts its own. So a read whose `NOC_RET_ADDR` names another tile writes the data into that tile's L1, and a write whose `NOC_TARG_ADDR` names another tile advances that tile's acknowledgement counter, which can let that tile's write barrier pass before its own writes have landed. Software must always use the initiating NIU's own coordinates for the response; anything else is UnsupportedFunctionality.

### On-chip fences are not an isolation boundary

Wormhole has no NoC security fence. Blackhole's NIUs have one (`NIU_BASE + 0x400`), but it is not an isolation mechanism: it ranks requests by a level rather than separating requesters from one another, and it does not check responses, so even with it configured, device code can still write any tile's L1 through a read with another tile's return coordinates. Coordinate translation, harvesting masks and multicast exclusion masks are likewise configuration that any NoC request initiator can rewrite, not protection.

### Tiles with their clock disabled hang whatever touches them

Firmware sets the tile clock disable bit of [`NIU_CFG_0`](WormholeB0/NoC/MemoryMap.md#niu_cfg_0) for fused-off tiles, and software may also turn tiles' clocks off and back on at run time to save power (for example, every tile on for a compute-bound phase and most of them off for a memory-bound one). The NIU and router of such a tile keep working, so traffic passing through it and accesses to its NIU registers are fine, but any other access to it (its L1, or its RISCV registers) is never answered. The initiating NIU waits forever, later requests through the same NIU hang, a stalled write can block other traffic on its virtual channel into that tile, and turning the clock back on doesn't recover any of it: only a reset does. A multicast whose rectangle includes such a tile never completes, and its other destinations receive only part of the data. All of this is UndefinedBehavior. Because any device code can set the bit on any tile, a kernel can also switch off a live tile, with the same consequences for everything that later addresses it.

### Host memory

**Blackhole:** the [NoC to Host](BlackholeA0/PCIExpressTile/README.md#address-spaces) address space has windows that go straight to the host IOMMU, without passing through the outbound iATU (the first four 2<sup>58</sup>-byte windows, as configured by the ARC firmware). Any device code can therefore name any 64-bit host bus address. Without an IOMMU, that is all of host physical memory: device code can read and write the kernel, other processes, and the memory of every other device. The same address space also contains the PCI Express controller's own configuration (DBI) and the configuration of the NoC to Host windows themselves, so device code can also reconfigure the PCI Express tile; the outbound iATU is not a protection mechanism.

**Wormhole:** device requests to the host go through the [outbound iATU](WormholeB0/PCIExpressTile/README.md#major-components), which passes addresses outside its programmed regions through unchanged. Without an IOMMU, device code can therefore reach at least the low 4 GiB of host physical memory, as well as whatever the programmed regions point at.

With an IOMMU enabled, device code reaches only what the kernel driver has mapped for that device. The IOMMU tells devices apart, not processes: everything mapped for a device is reachable by any code running on that device, whichever process the mapping was made for.

### Other ASICs, over Ethernet

An Ethernet tile in [TT-link mode](WormholeB0/EthernetTile/EthernetTxRx.md) sends packets that the peer's RX queue acts on directly, with no involvement from the peer's software:
* An L1 write packet writes any address in the peer Ethernet tile's L1, which is also where that tile's firmware and code live.
* An MMIO write packet writes any of the peer Ethernet tile's registers, the same registers its own RISCV core can write. Those include its NIU request initiators, so a sequence of MMIO write packets can make the peer issue any NoC request on the peer ASIC (any tile's L1, registers or DRAM there), and they include the peer's soft reset.

In raw mode an Ethernet tile sends arbitrary frames. The TX and RX queue configuration and the MAC addresses are ordinary tile registers: code on either ASIC, or any NoC request initiator on it, can change them, and nothing locks them. The Ethernet firmware's [baseline data movement service](WormholeB0/EthernetTile/BaselineDataMovementService.md) performs NoC reads and writes on remote ASICs for the host by design. So from one ASIC, device code can reach every ASIC connected to it by device Ethernet, directly or through other ASICs, with no host in the path.

### State that survives

Soft reset doesn't clear L1, DRAM, or most Tensix state. On Blackhole, thread configuration, configuration registers, address counters, the replay buffers, semaphores, mutexes, pending waits and the instruction buffers all survive every bit of [`RISCV_DEBUG_REG_SOFT_RESET_0`](BlackholeA0/TensixTile/SoftReset.md). NIU configuration (including `NIU_CFG_0`) lasts until the ASIC is reset. A job that is killed can leave all of this behind for the next one, along with whatever it wrote into host memory that is still mapped for the device.

## Recommendations

### Always

1. **Enable the IOMMU.** On Blackhole it is essentially mandatory in any real deployment: without it, any device code (or any process that can open the device and run device code) can read and write all of host physical memory. On Wormhole it is strongly recommended, for the same reason within the low 4 GiB and the iATU's regions.
2. **Map only what the device needs, for as long as it needs it.** Every page mapped for a device is readable and writable by all device code running on it, at any time, until it is unmapped. Unmap buffers when the job that needed them ends, including when it is killed.
3. **Treat access to the device as control of the device.** A process that can open the device can reach every NoC address, and so everything on this page. Grant device access only to the users and services meant to have it, and don't share one device between parties that don't trust each other.
4. **Never trust what the device writes to host memory.** Pointers, lengths, indices, return addresses and completion records written by the device are input, to be validated before the host uses them, as any data from an untrusted peer would be. A device can also rewrite any mapped buffer after the host has checked it.
5. **Don't rely on on-chip fences, coordinate translation or masks for isolation.** Containment is the IOMMU, the kernel driver's mappings, and the cabling, not anything device code can reconfigure.
6. **Keep every tile whose clock is disabled out of every access and every multicast rectangle.** Turning clocks off and on at run time for power is fine, but treat it like a change of partition: one owner (the runtime or firmware, never a kernel) changes the bit, only after the tile is quiet (no requests to or from it in flight) and out of every rectangle, and a tile coming back is initialized like a newly assigned one before use.
7. **Start every job on a clean device.** Between jobs of different owners, reset the ASIC (or at least every tile the previous job used, through the firmware's reset services), clear L1 and DRAM, and reclaim every host mapping the previous job had.

### By who can run device code

The layers that matter depend on who can get code onto the device. The deployments below are examples, not product requirements.

**Only the operator's own, vetted software stack runs device code.** For example, a production inference service on a multi-ASIC server, where external users send requests to a server process and never submit device code themselves. The layered story here is the IOMMU first and the server second: the IOMMU and minimal mappings bound what a bug anywhere in the device software can do to the host, and the server, as the only external interface, keeps outside parties from choosing what runs on the device. Reset between jobs still matters for reliability, as a hung or crashed job otherwise leaves state behind for the next one.

**Local users run their own kernels.** For example, a workstation used both for development and for local inference. Anyone who runs a kernel can read and write everything on the device, including what the previous job left in L1 and DRAM and everything currently mapped for the device. Give a device to one user, or one job, at a time; reset and clear it between users; and keep the IOMMU on, so that a kernel can reach only that device's own mappings rather than the rest of the host.

**Mutually untrusted tenants.** Wormhole and Blackhole can't be partitioned on chip: any tenant with code on an ASIC can reach all of it. Isolate at device granularity instead: give each tenant whole devices, together with every device connected to them by device Ethernet, behind the IOMMU (for example, by passing the devices through to the tenant's virtual machine); share nothing on the device between tenants; and reset and clear every device before it is reassigned.

### Ethernet-connected systems

* **Everything reachable over device Ethernet without a host in between is one trust domain** (and one failure domain). In a single-host system this is usually all the host's devices. In a multi-host system, such as two multi-ASIC servers cabled to each other, some links go to the other host's devices with no host in the path, so neither host's IOMMU bounds what crosses them.
* **Software on both sides of such a link must be trusted to the same level.** If the two sides run different software stacks (for example, different stages of a disaggregated serving pipeline), either trust both stacks equally, or disable the links between them, or carry that traffic through something that checks it (such as the hosts).
* **The Ethernet firmware is part of the trusted base of every ASIC on the link,** as is any device code that runs on Ethernet tiles.
* **Coordinate reset and teardown across hosts.** Resetting or reassigning the devices of one host is not enough if another host's devices are still connected to them by device Ethernet: reset, clear and reassign the whole trust domain together.

### For kernel and runtime authors

* Use the initiating NIU's own coordinates for every read's `NOC_RET_ADDR` and every acknowledged write's `NOC_TARG_ADDR` (UnsupportedFunctionality otherwise).
* Never address a tile whose clock is disabled (fused off, or turned off for power), or include one in a multicast rectangle (UndefinedBehavior).
* Don't write other tiles' `NIU_CFG_0`, translation tables, router configuration or soft reset registers from device code unless the runtime is designed around it.
* Don't depend on state left by a previous job, and don't leave state for the next one that it could depend on: restate configuration at start-up.
