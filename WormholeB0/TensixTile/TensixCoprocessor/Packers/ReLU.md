# ReLU

A ReLU operation can optionally be performed on datums coming from `Dst`, shortly after the early format conversion has been performed. Note that the Vector Unit (SFPU) can also be used to perform ReLU operations on datums in `Dst`.

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

float Threshold;
uint4_t IntermediateFormat;
if (ConfigState.ALU_FORMAT_SPEC_REG_Dstacc_override) {
  IntermediateFormat = ConfigState.ALU_FORMAT_SPEC_REG_Dstacc_val;
} else {
  IntermediateFormat = ConfigState.ALU_FORMAT_SPEC_REG2_Dstacc;
}
switch (IntermediateFormat) {
case FP16:
case FP8:
case BFP8a:
case BFP4a:
case BFP2a:
  Threshold = ParseFP16(ConfigState.STACC_RELU_ReluThreshold);
  break;
default:
  Threshold = ParseBF16(ConfigState.STACC_RELU_ReluThreshold);
  break;
}

float ReLUStage(float x) {
  switch (ConfigState.STACC_RELU_ApplyRelu & 3) {
  case 0: // NO_RELU
    // No ReLU
    return x;
  case 1: // ZERO_RELU
    // Simple ReLU
    return x <= 0 ? 0 : x;
  case 2: // MIN_THRESHOLD_RELU
    // ReLU with configurable threshold
    if (signbit(Threshold)) NonContractualBehavior {
      return (signbit(x) || Exponent(x) <= Exponent(Threshold)) ? 0 : x;
    }
    return x <= Threshold ? 0 : x;
  case 3: // MAX_THRESHOLD_RELU
    // ReLU that clamps between 0 and Threshold
    if (signbit(Threshold)) NonContractualBehavior {
      if (signbit(x)) return 0;
      else if (Exponent(x) > Exponent(Threshold)) return Threshold;
      else return x;
    }
    if (x <= 0) return 0;
    else if (x > Threshold) return Threshold;
    else return x;
  }
}
```

A `Threshold` with its sign bit set (-0, a negative denormal, -infinity or a negative NaN included) is a `NonContractualBehavior` in `MIN_THRESHOLD_RELU` and `MAX_THRESHOLD_RELU`. The hardware compares exponents before signs, so such a `Threshold` acts through its exponent alone. `Exponent(v)` is the biased exponent field of the bit pattern `v` in the format `Threshold` is interpreted as (8 bits for BF16, 5 bits for FP16), and `x` is the datum after the early format conversion, as that conversion leaves it (infinities and NaNs included). Datums whose sign bit is set always become zero. In `MIN_THRESHOLD_RELU`, a datum becomes zero unless its exponent field exceeds that of `Threshold`; when `Threshold`'s exponent field is all ones, every datum becomes zero. In `MAX_THRESHOLD_RELU`, a datum whose exponent field exceeds that of `Threshold` (infinities and NaNs included, unless `Threshold`'s exponent field is all ones) becomes `Threshold` itself, sign included, and the late format conversion then encodes it as it would the positive value with the same magnitude, with the sign bit set: -0 stays -0, and a denormal `Threshold` takes the encoding its positive counterpart does, block floating-point formats included. The result does not depend on earlier packs.

Note that `STACC_RELU_ReluThreshold` can be interpreted as either BF16 or FP16. When `IntermediateFormat` is FP32, `STACC_RELU_ReluThreshold` will be interpreted as BF16, which has the same bit layout as the top 16 bits of FP32.

`ReLUStage` is described as operating on floats (FP32). If `IntermediateFormat` is some narrower floating-point format, the values will be losslessly converted up to FP32 before `ReLUStage` and converted back down afterwards. If `IntermediateFormat` is an integer format, `STACC_RELU_ApplyRelu` should be set to zero, which will guarantee the values pass through `ReLUStage` unchanged, or set to one, which will pass through positive integers unchanged and replace negative integers with zero.

On Blackhole, with `IntermediateFormat` FP16 and `PCK_DEST_RD_CTRL_Round_10b_mant` set (the early format conversion from FP32 or BF16 to FP16; see [format conversion](FormatConversion.md)), `ReLUStage` operates on the 8-bit-exponent value before its exponent is narrowed, and `STACC_RELU_ReluThreshold` is interpreted as BF16 rather than FP16.

On Wormhole, with `IntermediateFormat` FP16 and both `PCK_DEST_RD_CTRL_Read_32b_data` and `PCK_DEST_RD_CTRL_Round_10b_mant` clear, `MIN_THRESHOLD_RELU` keeps a datum equal to `Threshold` in columns 0 through 3 and 8 through 11 of `Dst` (rather than replacing it with zero) if the low three bits of `STACC_RELU_ReluThreshold` are not all zero.

On Blackhole, `MIN_THRESHOLD_RELU` does not always replace a datum equal to `Threshold` with zero in columns 0 through 7 of `Dst`:
* With `IntermediateFormat` FP16 and `PCK_DEST_RD_CTRL_Round_10b_mant` clear, such a datum is kept if the low three bits of `STACC_RELU_ReluThreshold` are not all zero.
* With `IntermediateFormat` FP16, `PCK_DEST_RD_CTRL_Round_10b_mant` set and `PCK_DEST_RD_CTRL_Read_32b_data` clear, whether such a datum is kept depends on other contents of `Dst`.

With `PCK_DEST_RD_CTRL_Read_32b_data` set and `IntermediateFormat` FP32, `MAX_THRESHOLD_RELU` compares only the high 16 bits of each datum with `Threshold`: a datum whose high 16 bits equal `Threshold` and whose low 16 bits are not all zero is greater than `Threshold`, but it stays as it is rather than becoming `Threshold` (for example, with `Threshold` 1.0, the FP32 datum `0x3F800001` stays `0x3F800001`).
