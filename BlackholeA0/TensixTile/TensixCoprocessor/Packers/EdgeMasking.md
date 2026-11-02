# Edge Masking

Edge masking is performed on datums coming from `Dst`, which can selectively replace datums with 0 or with -∞, based on their _position_ within the tile being packed. This can be useful when manipulating tiles smaller than 16x16 which have been padded up to 16x16, or for keeping only the row, column or datum of a tile that holds a reduction's result: everything else can be forced back to 0 or to -∞ as part of a pack operation.

The mechanism is the same as [on Wormhole](../../../../WormholeB0/TensixTile/TensixCoprocessor/Packers/EdgeMasking.md), except that Blackhole has a single packer: the 2-bit selectors are indexed by the `PACR` instruction's [configuration context](../PACR.md#configuration-contexts) (usually its `CfgContext`) rather than by packer index, the tile position advances once per `Dst` row read rather than once per datum, and the tile row at which each `PACR` starts depends on the packer's `Dst` offset.

## Functional model

Every enabled `Dst` read interface of a `PACR` reads one row of 16 datums (see [`PACR`](../PACR.md)). For the `k`'th enabled read interface (counting only enabled interfaces, starting at zero), the row's edge mask is:

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

uint16_t RowEdgeMask(unsigned k) {
  uint2_t Ctx = PacrConfigContext(); // CfgContext, or the context counter (see PACR)
  auto& TPG = Packer.TilePositionGenerator;
  uint4_t Y = TPG.Y + TPG.YStart + k;
  uint4_t Z = Config.DEST_TARGET_REG_CFG_PACK_SEC[Ctx].ZOffset + TPG.Z;
  uint2_t b;
  if (ConfigState.PCK_EDGE_TILE_FACE_SET_SELECT_enable) {
    uint2_t a = (ConfigState.PCK_EDGE_TILE_FACE_SET_SELECT_select >> (2 * Ctx)) & 3;
    b = ConfigState.TILE_FACE_SET_MAPPING[a].face_set_mapping[Z];
  } else {
    b = (ConfigState.PCK_EDGE_TILE_ROW_SET_SELECT_select >> (2 * Ctx)) & 3;
  }
  uint2_t c = ConfigState.TILE_ROW_SET_MAPPING[b].row_set_mapping[Y];
  return ConfigState.PCK_EDGE_OFFSET_SEC[c].mask;
}
```

Then each datum of the row is kept if its bit of `RowEdgeMask(k)` is set, and otherwise replaced:

```c
if (EdgeMask.Bit[Column]) {
  return Datum; // read from Dst as usual
} else if (ConfigState.PCK_EDGE_MODE_mode) {
  return -INFINITY;
} else {
  return 0;
}
```

When `PCK_EDGE_TILE_FACE_SET_SELECT_enable` is set, `PCK_EDGE_TILE_ROW_SET_SELECT_select` is ignored: the face's entry in the selected `TILE_FACE_SET_MAPPING` chooses which `TILE_ROW_SET_MAPPING` applies to every row of that face. For example, packing a 32x32 tile as four faces of 16 rows with `pack_reads_per_xy_plane = 16`, `Z` is the face index, so `TILE_FACE_SET_MAPPING[a]` can give each face its own row mapping.

The tile position generator referenced in the above is:

```c
struct TilePositionGenerator {
  uint8_t Y = 0;
  uint6_t Z = 0;
  uint4_t YStart;

  // At the start of each PACR instruction:
  void Start() {
    uint2_t Ctx = PacrConfigContext(); // CfgContext, or the context counter (see PACR)
    if (ConfigState.THCON_SEC0_REG1_pack_dis_y_pos_start_offset) {
      YStart = 0;
    } else {
      uint4_t InFormat = ConfigState.THCON_SEC0_REG1_In_data_format;
      uint9_t YStrideRows = ConfigState.PCK0_ADDR_CTRL_XY_REG_0_Ystride >> ((InFormat & 3) == 0 ? 6 : (InFormat & 3) == 1 ? 5 : 4);
      unsigned Shift = YStrideRows ? CountTrailingZeros(YStrideRows) : 0;
      uint2_t RowOffset = Config.DEST_TARGET_REG_CFG_PACK_SEC[Ctx].Offset >> Shift;
      YStart = (RowOffset << 2) | ConfigState.THCON_SEC0_REG1_pack_start_intf_pos;
    }
  }

  // After each group of Dst rows a PACR reads, NumEnabled being its number of enabled read interfaces:
  void Advance(unsigned NumEnabled) {
    uint2_t Ctx = PacrConfigContext(); // CfgContext, or the context counter (see PACR)
    if (Y == (uint8_t)(ConfigState.PACK_COUNTERS_SEC[Ctx].pack_reads_per_xy_plane - NumEnabled)) {
      Y = 0;
      Z += 1;
    } else {
      Y += NumEnabled;
    }
  }

  // In place of the final Advance of a PACR with Last set:
  void Reset() {
    Y = 0;
    Z = 0;
  }
};
```

The `THCON_SEC0_REG1` fields shown are those of configuration context 0; context `Ctx` reads its own `pack_dis_y_pos_start_offset` and `In_data_format`, and the `pack_start_intf_pos` of its register section (see [`PACR`](../PACR.md#configuration-contexts)). `Ystride` is in bytes of the packer's input format, so `YStrideRows` is the Y stride in `Dst` rows for the usual formats. With a Y stride of one row and a `Dst` offset that is a multiple of four rows, `YStart` is `pack_start_intf_pos`, normally zero.

`Y` returns to zero only when advancing it lands exactly on `pack_reads_per_xy_plane`: if `NumEnabled` does not divide `pack_reads_per_xy_plane`, `Y` steps over it and `Z` never advances. When `Dst` is read as 32 bits per datum, each row takes two reads, and the position still advances once per row. This model assumes `pack_yz_transposed` is false and no downsampling.

To use the same edge mask for all rows of `Dst`, regardless of the tile position generator, set all four of `PCK_EDGE_OFFSET_SEC[c].mask` to the same value.
