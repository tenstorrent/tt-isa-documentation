[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/tenstorrent/tt-isa-documentation)

# Tenstorrent ISA Documentation

This repository contains low-level documentation about Tenstorrent AI architectures.

The typical software stack for these architectures, from highest level to lowest level, is:
1. [TT-Forge](https://github.com/tenstorrent/tt-forge/)
2. [TT-NN](https://github.com/tenstorrent/tt-metal/?tab=readme-ov-file#buy-hardware--install--discord--join-us)
3. [TT-Metalium](https://github.com/tenstorrent/tt-metal/?tab=readme-ov-file#user-content-programming-guide--api-reference)
4. [TT-LLK](https://github.com/tenstorrent/tt-metal/tree/main/tt_metal/tt-llk/README.md)

The material in this repository is intended for software developers writing code at, or below, the level of TT-LLK.

At the moment, two architectures are covered in this repository:
* [Wormhole B0](WormholeB0/README.md) - The version of Wormhole shipped to customers (n150s / n150d / n300s / n300d / Wormhole Galaxy).
* [Blackhole A0](BlackholeA0/README.md) - The version of Blackhole shipped to customers (p100 / p150).

> [!NOTE]
> Wormhole B0 and Blackhole A0 share substantial implementation but are not identical. Behavioral assumptions from one architecture's documentation do not transfer automatically to the other.

See also [ttsim](https://github.com/tenstorrent/ttsim), the official simulator and golden reference implementation of the Tenstorrent ISA.

-----

> [!NOTE]
> The contents of this repository should be considered a living document. It is still in the process of being written and edited, but it is made available to customers regardless, as it is believed that it can be useful today, even if it'll potentially be better tomorrow.
