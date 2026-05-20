# "Baby" RISCVs

Each Ethernet tile contains two RISCV cores. Collectively, these are called "baby" cores as they are relatively small 32-bit in-order single-issue cores, optimized for area and power efficiency rather than for high performance. Each RISCV core is intended to execute one RISCV instruction per cycle, running at a clock speed of 1.35 GHz. The two cores are called RISCV E0 and RISCV E1.

The baby RISCV cores in every Ethernet tile are very similar to [the baby RISCV cores in every Tensix tile](../../TensixTile/BabyRISCV/README.md). From the RISCV point of view, the major differences in Ethernet tiles as compared to Tensix tiles are:
* Just two RISCV cores in every Ethernet tile (versus five in every Tensix tile).
* Just 512 KiB of [L1](../L1.md) in every Ethernet tile (versus 1536 KiB in every Tensix tile).
* The RISCV cores are attached to Ethernet transmit and receive subsystems, rather than being attached to a Tensix coprocessor.
* RISCV E0 is cooperatively shared between Tenstorrent code and customer code, rather than exclusively running customer code. Said Tenstorrent code is responsible for:
    * Initial [configuration](../EthernetTxRx.md#associating-tx-queues-with-rx-queues) and training of the Ethernet link.
    * Retraining the Ethernet link in response to link drops.
    * [Calling into customer code](CallingIntoCustomerCode.md).
* Different kind of PIC.
* Local data RAM on Ethernet tiles is not accessible over the NoC, nor are snapshots of RISCV `pc`s.

## Instruction set

The full RV32IM instruction set is implemented, plus all of "Zicsr" / "Zaamo" / "Zba" / "Zbb", plus some (but not all) of "Zicntr" / `F` / "Zfh". See [instruction set](../../TensixTile/BabyRISCV/InstructionSet.md) for details.

## Memory map

The "NoC" column indicates which parts of the address space are made available to the NoC in addition to being available to the RISCV core.

The "Ethernet" column indicates what kind(s) of packets can be used to write to parts of the address space using the [Ethernet transmit and receive subsystems](../EthernetTxRx.md).

<table><thead><tr><th>Name and address range</th><th>RISCV&nbsp;E0</th><th>RISCV&nbsp;E1</th><th>NoC</th><th>Ethernet</th></tr></thead>
<tr><td><code>MEM_ETH_BASE</code><br/><code>0x0000_0000</code> to <code>0x0007_FFFF</code></td><td colspan="3"><a href="../L1.md">L1 scratchpad RAM (512 KiB)</a></td><td>Raw writes<br/>TT-link L1 writes</td></tr>
<tr><td><code>MEM_LOCAL_BASE</code><br/><code>0xFFB0_0000</code> to <code>0xFFB0_1FFF</code></td><td><a href="README.md#local-data-ram">RISCV E0 local data RAM</a></td><td><a href="README.md#local-data-ram">RISCV E1 local data RAM</a></td><td colspan="3">Unmapped</td></tr>
<tr><td><code>RISCV_DEBUG_REGS_START_ADDR</code><br/><code>0xFFB1_2000</code> to <code>0xFFB1_400F</code></td><td colspan="3"><a href="../TileControlDebugStatus.md">Tile control / debug / status registers</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>0xFFB1_4020</code> to <code>0xFFB1_4063</code></td><td colspan="3"><a href="../../TensixTile/PIC.md">PIC configuration registers</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>NOC0_REGS_START_ADDR</code><br/><code>0xFFB2_0000</code> to <code>0xFFB2_FFFF</code></td><td colspan="3"><a href="../../NoC/MemoryMap.md">NoC 0 configuration registers and command interface</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>NOC1_REGS_START_ADDR</code><br/><code>0xFFB3_0000</code> to <code>0xFFB3_FFFF</code></td><td colspan="3"><a href="../../NoC/MemoryMap.md">NoC 1 configuration registers and command interface</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>NOC_OVERLAY_START_ADDR</code><br/><code>0xFFB4_0000</code> to <code>0xFFB7_FFFF</code></td><td colspan="3"><a href="../../NoC/Overlay/README.md">NoC overlay configuration registers and command interface</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>ETH_TXQ0_REGS_START</code><br/><code>0xFFB9_0000</code> to <code>0xFFB9_2FFF</code></td><td colspan="3"><a href="../EthernetTxRx.md">Ethernet TX queues configuration registers and command interface</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>ETH_RXQ0_REGS_START</code><br/><code>0xFFB9_4000</code> to <code>0xFFB9_6FFF</code></td><td colspan="3"><a href="../EthernetTxRx.md">Ethernet RX queues configuration registers</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>ETH_CTRL_REGS_START</code><br/><code>0xFFB9_8000</code> to <code>0xFFB9_81FF</code></td><td colspan="3"><a href="../TileControlDebugStatus.md">Additional tile control / status registers</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>0xFFB9_8200</code> to <code>0xFFB9_86F3</code></td><td colspan="3"><a href="../EthernetTxRx.md">Ethernet TX header table</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>0xFFB9_C000</code> to <code>0xFFB9_EA1F</code></td><td colspan="3"><a href="../EthernetRxClassifier.md">Ethernet RX classifier</a></td><td>TT-link MMIO writes</td></tr>
<tr><td><code>0xFFBA_0000</code> to <code>0xFFBA_FFFF</code></td><td colspan="3">Ethernet MAC / PCS registers</td><td>TT-link MMIO writes</td></tr>
</table>

## Local data RAM

Each of RISCV E0 and RISCV E1 have 8 KiB of local data RAM, starting at address `MEM_LOCAL_BASE`. Each one of these two RAMs is only accessible using load or store instructions from the one RISCV associated with it. Access to this RAM is low latency, and accesses never suffer from contention. A load from local RAM has a latency of two cycles, meaning that so long as the one instruction immediately after the load is independent of the load result, the latency of the load is entirely hidden. In contrast, a load from L1 has a latency of at least seven cycles: six independent instructions are required to fully hide the latency. Software is _strongly_ encouraged to place the call stack in this RAM, along with any thread-local variables and any frequently-used read-only global variables.
