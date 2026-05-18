# Compression

If compression is enabled, every datum is augmented with a four-bit counter specifying how many zeroes appear _after_ that datum. Datums which are zero can then be compressed away by representing them purely via _previous_ datum's counter.

To enable efficient seeking to various points within the compressed stream, if compression is enabled, pack instructions have a concept of "rows": the first and last datums in each row will _not_ be compressed away, and extra metadata is emitted to specify where each row starts and ends in the compressed stream. By default, each `PACR` instruction starts a new "row", but this behavior can be changed: if the `Concat` bit is set on a `PACR` instruction, then the _next_ `PACR` is a continuation of the same row, rather than starting a new row.

## In-memory / on-disk format

1. An array of 16-bit row start indices. `RSI[i+1] - RSI[i]` gives the number of augmented datums in row `i`, so `RSI[i]` can be used to determine where row `i` starts in the compressed stream, and `RSI[i+1]` can be used to determine where it ends. It is expected that `RSI[0]` will be zero. The length of this array will be one plus the number of rows, and each element is 16 bits (2 bytes).
2. Padding up to the next 128-bit (16-byte) boundary.
3. If the augmented datums are a BFP format:
   1. An array of 8-bit exponents, containing one exponent for every 16 augmented datums. The length of this array will be `ceil(original_datum_count / 16)`, but only the first `ceil(augmented_datum_count / 16)` entries are used.
   2. Padding up to the next 128-bit (16-byte) boundary.
4. First 32 augmented datums:
   1. 32 datums, where each datum will be 4/8/16/32 bits. This will occupy some multiple of 128 bits.
   2. 32 four-bit counters, one per datum. This will occupy exactly 128 bits. The least significant four bits are the counter for the first datum, the next four bits are the counter for the second datum, and so forth.
5. Next 32 augmented datums:
   1. 32 datums, where each datum will be 4/8/16/32 bits. This will occupy some multiple of 128 bits.
   2. 32 four-bit counters, one per datum. This will occupy exactly 128 bits. The least significant four bits are the counter for the first datum, the next four bits are the counter for the second datum, and so forth.
6. ... repeat for every 32 augmented datums ...
7. Final `N` augmented datums, `N ≤ 32`:
   1. `N` datums, where each datum will be 4/8/16/32 bits.
   2. Padding consisting of `32 - N` datums.
   3. `N` four-bit counters, one per datum.
   4. Padding up to the next 128-bit (16-byte) boundary.

As augmented datums are stored in groups of 32, `RSI[i] >> 5` identifies a group, and `RSI[i] & 0x1f` identifies an augmented datum within that group. If the augmented datums are a BFP format, there will be one exponent for every 16 augmented datums, i.e. two exponents per group, one for the first half of the group, and one for the second half. Note that each exponent applies to 16 augmented datums, and those augmented datums could come from multiple different rows.

## Compressing during packing

Compression can be performed during packing; see `PerformingCompression` and `Row_start_section_size` as part of the [output address generator](OutputAddressGenerator.md) description. The _exact_ compression logic isn't specified, but it'll generate output in the format described on this page.

## Decompressing during unpacking

Unpackers can consume the format described on this page; see [unpacker decompression](../Unpackers/README.md#decompression) for details.
