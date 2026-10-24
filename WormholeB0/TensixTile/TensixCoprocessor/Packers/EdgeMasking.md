# Edge Masking

Edge masking is performed on datums coming from `Dst`, which can selectively replace datums with 0 or with -∞, based on their _position_ within `Dst`. This can be useful when manipulating tiles smaller than 16x16 which have been padded up to 16x16: that padding can be forced back to 0 or to -∞ as part of a pack operation.

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

Datum FetchFromDst(uint32_t PackerIndex, uint32_t addr) {
  auto& TPG = Packers[PackerIndex].TilePositionGenerator;
  uint2_t b;
  if (ConfigState.PCK_EDGE_TILE_FACE_SET_SELECT_enable) {
    unsigned Z = Config.DEST_TARGET_REG_CFG_PACK[PackerIndex].ZOffset + TPG.Z;
    uint2_t a = (ConfigState.PCK_EDGE_TILE_FACE_SET_SELECT_select >> (2 * PackerIndex)) & 3;
    b = ConfigState.TILE_FACE_SET_MAPPING[a].face_set_mapping[Z & 0xf];
  } else {
    b = (ConfigState.PCK_EDGE_TILE_ROW_SET_SELECT_select >> (2 * PackerIndex)) & 3;
  }
  uint2_t c = ConfigState.TILE_ROW_SET_MAPPING[b].row_set_mapping[TPG.Y & 0xf];
  uint16_t EdgeMask = ConfigState.PCK_EDGE_OFFSET_SEC[c].mask;
  TPG.Advance();

  uint10_t Row = addr >> 4;
  uint4_t Column = addr & 0xf;
  if (EdgeMask.Bit[Column]) {
    if (ConfigState.PCK_DEST_RD_CTRL_Read_32b_data) {
      // NB: Row will be reduced from 10 bits to 9
      return EarlyFormatConversion(Dst32b[Row][Column]);
    } else {
      return EarlyFormatConversion(Dst16b[Row][Column]);
    }
  } else if (ConfigState.PCK_EDGE_MODE_mode) {
    return -INFINITY;
  } else {
    return 0;
  }
}
```

The tile position generator referenced in the above is:
```c
struct TilePositionGenerator {
  unsigned X = 0;
  unsigned Y = 0;
  unsigned Z = 0;

  void Advance() {
    uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
    auto& ConfigState = Config[StateID];

    X += 1;
    if (X == 16) {
      X = 0;
      if (ConfigState.PACK_COUNTERS_SEC[PackerIndex].pack_yz_transposed) {
        Z += 1;
        if (Z == ConfigState.PACK_COUNTERS_SEC[PackerIndex].pack_reads_per_xy_plane) {
          Z = 0;
          Y += 1;
        }
      } else {
        Y += 1;
        if (Y == ConfigState.PACK_COUNTERS_SEC[PackerIndex].pack_reads_per_xy_plane) {
          Y = 0;
          Z += 1;
        }
      }
    }
  }
};
```

On Wormhole, the tile position generator counts the 16-byte words of `In_data_format` that the packer reads from `Dst`, not datums: `Advance` runs once per word, and `X` reaches the end of a row after 4 words for FP32, TF32 and INT32, 2 words for FP16 and BF16, and 1 word for every other format, INT16 included. So an INT16 pack moves on to the next `Y` every 8 datums, and a word the packer reads only part of (a run of datums that starts or ends inside a word) counts as a whole word. Every datum of a word gets the `EdgeMask` in effect when the word is read, at the datum's column in `Dst`.

On Wormhole, a pack instruction with `Last` set does not reset the tile position generator: `X`, `Y` and `Z` run on from one tile to the next, `Y` wrapping to 0 at `pack_reads_per_xy_plane` as above. A tile whose number of rows is not a multiple of `pack_reads_per_xy_plane` therefore leaves the next tile starting partway through `TILE_ROW_SET_MAPPING`. On Blackhole, the first pack instruction after one with `Last` set starts the tile position generator again from position 0.

To use the same `EdgeMask` for all rows of `Dst`, regardless of the tile position generator, set all four of `PCK_EDGE_OFFSET_SEC[c].mask` to the same value.
