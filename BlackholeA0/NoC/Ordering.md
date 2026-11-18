# NoC Ordering

This document is shared with the Wormhole tree; see [`Ordering.md` in the Wormhole tree](../../WormholeB0/NoC/Ordering.md). The functionality is similar, but not identical, between Wormhole and Blackhole.

## Differences on Blackhole

For writes to L1, the receiving NIU decomposes the write into four streams rather than two, one per 16 bytes of its 64-byte flit: byte addresses which are between `16*i mod 64` and `16*i+15 mod 64` (inclusive) go to stream `i`, for `i` between `0` and `3`. Within each stream, the writes from a single packet will happen in ascending address order, and as on Wormhole, nothing orders the streams against each other. In particular, two byte addresses 32 bytes apart are in the same stream on Wormhole but in different streams on Blackhole, so on Blackhole the higher one can be written first.
