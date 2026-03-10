# Ethernet Tile

Each Ethernet tile contains:
  * [512 KiB of RAM called L1](L1.md)
  * [2x "Baby" RISCV cores](BabyRISCV/README.md)
  * [2x NoC connections](../NoC/README.md) allowing the local RISCV cores to access data in other tiles, and allowing other tiles to access data from this tile
  * [1x NoC overlay](../NoC/Overlay/README.md) - a little coprocessor that can assist with NoC transactions
  * 1x 400 GbE Ethernet link, with Ethernet MAC / PCS / PHY, presented as [3x Ethernet TX queues](EthernetTxRx.md) and [3x Ethernet RX queues](EthernetTxRx.md)

On boards with QSFP-DD ports, a pair of Ethernet tiles are connected to each QSFP-DD port, and then 800 GbE is available at the port level.

> [!TIP]
> Compared to Wormhole, some of the major upgrades to Ethernet tiles in Blackhole are: higher clock speed, larger L1, a 2<sup>nd</sup> RISCV core, and 400 GbE rather than 100 GbE. The Ethernet TX and RX subsystems also received significant upgrades around header insertion and removal.
