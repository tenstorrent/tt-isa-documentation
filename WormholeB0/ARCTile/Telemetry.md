# ARC Telemetry

The ARC CPU presents two flavours of telemetry for consumption by host software:
* BH style telemetry (since [firmware bundle](https://github.com/tenstorrent/tt-firmware) version 18.4)
* Legacy style telemetry

## BH Style Telemetry

> [!IMPORTANT]
> BH style telemetry is only present since [firmware bundle](https://github.com/tenstorrent/tt-firmware) version 18.4; older firmware versions only present legacy telemetry (newer firmware presents both).

BH style telemetry consists of a mutable array of 32-bit values (`telemetry_data`), along with an immutable metadata array (`telemetry_table.tag_table`) describing its contents:

```c
struct telemetry_table {
  uint32_t version; // Expected to equal TELEMETRY_VERSION from telemetry.h
  uint32_t entry_count;
  struct telemetry_entry {
    uint16_t tag; // TAG_ value from telemetry.h
    uint16_t index; // Index of tag's data in telemetry_data.
  } tag_table[entry_count];
} telemetry_table;

uint32_t telemetry_data[];
```

The various `TAG_` values can be found in [`telemetry.h`](https://github.com/tenstorrent/tt-zephyr-platforms/blob/bc5612bf57a5abd5b0d5b616b3088f5e9531e9c5/lib/tenstorrent/bh_arc/telemetry.h).

The runtime address of `telemetry_table` is published to `NOC_NODEID_X_0` in the [reset unit](ResetUnit.md), and the runtime address of `telemetry_data` is published to `NOC_NODEID_Y_0` in the [reset unit](ResetUnit.md). In both cases, the addresses are as seen by the [ARC CPU](README.md#arc-cpu-4-gib), but will always point to the CSM region of its address space, so software can remap the addresses to bar 0 address space or bar 4 address space or NoC address space, and then access the data through one of those address spaces.

Example contents of `telemetry_table` and `telemetry_data` is:

|Tag|Example value|Interpretation of example value|
|---|---|---|
|`TAG_BOARD_ID_HIGH` (1)|`0x01000145`|Board ID `01000145117320ed` (combine `_HIGH` and `_LO`)<br/>(also encodes product type; see decoding logic [in Python](https://github.com/tenstorrent/tt-smi/blob/7e9f287a192b5590d8f294c9183cd6081a44ccec/tt_smi/tt_smi_backend.py#L616) or [in Rust](https://github.com/tenstorrent/luwen/blob/f4ab6771ca8f9b0da815b2d27f467bf6a918c63b/crates/luwen-if/src/chip/mod.rs#L179))|
|`TAG_BOARD_ID_LO` (2)|`0x117320ed`|Board ID `01000145117320ed` (combine `_HIGH` and `_LO`)|
|`TAG_UPDATE_TELEM_SPEED` (5)|`0x00000064`|Telemetry update interval 100ms|
|`TAG_VCORE` (6)|`0x0000031b`|Core voltage 0.795 V (value in mV)|
|`TAG_VDD_LIMITS` (9)|`0x03e80320`|VDD limits 0.8 volts and 1.0 volts (two 16-bit fields, each in mV)|
|`TAG_TDP` (7)|`0x0000000f`|Core power 15 W|
|`TAG_TDP_LIMIT_MAX` (64)|`0x00000055`|Upper limit on core power is 85 W|
|`TAG_TDC` (8)|`0x00000013`|Core current 19 A|
|`TAG_TDC_LIMIT_MAX` (55)|`0x000000a0`|Upper limit on core current is 160 A|
|`TAG_BOARD_TEMPERATURE` (13)|`0x002c0000`|Board outlet temperature 44 °C (format is s16.16)|
|`TAG_ASIC_TEMPERATURE` (11)|`0x00358000`|Core temperature 53.5 °C (format is s16.16)|
|`TAG_THM_LIMIT_THROTTLE` (56)|`0x0000004b`|Forced throttling if temperature exceeds 75 °C|
|`TAG_THM_LIMIT_SHUTDOWN`&nbsp;(10)|`0x00000053`|Forced board shutdown if temperature exceeds 83 °C|
|`TAG_FAN_SPEED` (31)|`0xffffffff`|Fans not present on board, or not under control of firmware|
|`TAG_AICLK` (14)|`0x000001f4`|AI clock running at 500 MHz|
|`TAG_AICLK_LIMIT_MAX` (63)|`0x000003e8`|Maximum allowed AI clock is 1000 MHz|
|`TAG_AXICLK` (25)|`0x00000384`|AXI clock running at 900 MHz|
|`TAG_ARCCLK` (16)|`0x0000021c`|ARC clock running at 540 MHz|
|`TAG_GDDR_STATUS` (22)|`0x00000555`|All six DRAM tiles completed training successfully<br/>(format is two bits per tile; training success bit followed by error bit)|
|`TAG_GDDR_SPEED` (23)|`0x00002ee0`|DRAM running at 12 GT/s (value in MT/s)|
|`TAG_ETH_LIVE_STATUS` (21)|`0x0000ffff`|All sixteen Ethernet tiles live (format is one bit per tile)|
|`TAG_FLASH_BUNDLE_VERSION`&nbsp;(28)|`0x12050000`|[Firmware bundle](https://github.com/tenstorrent/tt-firmware) version 18.5.0.0 (format is `0xAABBCCDD`)|
|`TAG_ETH_FW_VERSION` (24)|`0x0006f000`|Ethernet firmware version 6.15.0 (format is `0x00AABCCC`)|
|`TAG_CM_FW_VERSION` (29)|`0x02210100`|CMFW version 2.33.1.0 (format is `0xAABBCCDD`)|
|`TAG_FW_BUILD_DATE` (57)|`0x56020d27`|CMFW built at 2025-06-02 13:39:00<br/>(format is `0xYMDDHHMM`, add 2020 to the year)|
|`TAG_DM_BL_FW_VERSION` (27)|`0x81020000`|BM BL firmware version 129.2.0.0 (format is `0xAABBCCDD`)|
|`TAG_DM_APP_FW_VERSION` (26)|`0x05090000`|BM APP firmware version 5.9.0.0 (format is `0xAABBCCDD`)|
|`TAG_TT_FLASH_VERSION` (58)|`0x00030303`|[tt-flash](https://github.com/tenstorrent/tt-flash) version 0.3.3.3 (format is `0xAABBCCDD`)|
|`TAG_NOC_TRANSLATION` (40)|`0x00000001`|[NoC coordinate translation](../NoC/Coordinates.md#coordinate-translation) enabled|
|`TAG_ASIC_LOCATION` (52)|`0x00000000`|n300 "left" (i.e. PCIe connected) ASIC <br/>(the n300 "right" ASIC would be denoted by `0x00000001`)|

## Legacy Style Telemetry

Legacy style telemetry has two major downsides compared to BH style telemetry:
1. Legacy style telemetry consists only of a mutable array of 32-bit values; there is no metadata array describing its contents (so software has to rely on fixed array indices).
2. Host software needs to send a `ARC_GET_TELEMETRY_OFFSET` message to the ARC CPU, and it will respond with the address of the data array, rather than just being able to read the address out of the reset unit.

A mapping from legacy style array indices to BH style tags is:

|Array index|Example value|Corresponding tag(s) in BH style telemetry|
|--:|---|---|
|0|`0xba5e0001`|None; is a fixed marker value denoting start of legacy array|
|4|`0x01000145`|`TAG_BOARD_ID_HIGH`|
|5|`0x117320ed`|`TAG_BOARD_ID_LO`|
|6|`0x02210100`|`TAG_CM_FW_VERSION`|
|11|`0x0006f000`|`TAG_ETH_FW_VERSION`|
|12|`0x81020000`|`TAG_DM_BL_FW_VERSION`|
|13|`0x05090000`|`TAG_DM_APP_FW_VERSION`|
|14|`0x02222222`|Same purpose as `TAG_GDDR_STATUS` and `TAG_GDDR_SPEED`, but different encoding: low 24 bits are four bits per DRAM tile, with the value `0b0010` representing training success, then next four bits are the value `Y`, with the speed being `16 - 2*Y` GT/s|
|23|`0xffffffff`|`TAG_FAN_SPEED`|
|24|`0x03e801f4`|`TAG_AICLK` in low 16 bits, `TAG_AICLK_LIMIT_MAX` in high 16 bits|
|25|`0x00000384`|`TAG_AXICLK`|
|26|`0x0000021c`|`TAG_ARCCLK`|
|28|`0x0000031b`|`TAG_VCORE`|
|29|`0x03660358`|Low 16 bits are same purpose as `TAG_ASIC_TEMPERATURE`, but in s12.4 format|
|31|`0x00262d2c`|Low 8 bits are same purpose as `TAG_BOARD_TEMPERATURE`, but in s8.0 format|
|32|`0x0055000f`|`TAG_TDP` in low 16 bits, `TAG_TDP_LIMIT_MAX` in high 16 bits|
|33|`0x00a00013`|`TAG_TDC` in low 16 bits, `TAG_TDC_LIMIT_MAX` in high 16 bits|
|34|`0x03e80320`|`TAG_VDD_LIMITS`|
|35|`0x0053004b`|`TAG_THM_LIMIT_THROTTLE` in low 16 bits, `TAG_THM_LIMIT_SHUTDOWN` in high 16 bits|
|36|`0x56020d27`|`TAG_FW_BUILD_DATE`|
|46|`0x00030303`|`TAG_TT_FLASH_VERSION`|
|49|`0x12050000`|`TAG_FLASH_BUNDLE_VERSION`<br/>(only present in the legacy array when the value of `TAG_CM_FW_VERSION` is at least `0x02190000`)|

> [!WARNING]
> On [some galaxy systems](https://github.com/tenstorrent/tt-smi/blob/7e9f287a192b5590d8f294c9183cd6081a44ccec/tt_smi/tt_smi_backend.py#L571-L595), a flashing bug can cause legacy array indices 46 and 49 to be confused.
