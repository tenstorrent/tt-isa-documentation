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
    if (signbit(Threshold)) UndefinedBehavior(); // Threshold <= -0 is undefined
    return x <= Threshold ? 0 : x;
  case 3: // MAX_THRESHOLD_RELU
    // ReLU that clamps between 0 and Threshold
    if (signbit(Threshold)) UndefinedBehavior(); // Threshold <= -0 is undefined
    if (x <= 0) return 0;
    else if (x > Threshold) return Threshold;
    else return x;
  }
}
```

Note that `STACC_RELU_ReluThreshold` can be interpreted as either BF16 or FP16. When `IntermediateFormat` is FP32, `STACC_RELU_ReluThreshold` will be interpreted as BF16, which has the same bit layout as the top 16 bits of FP32.

`ReLUStage` is described as operating on floats (FP32). If `IntermediateFormat` is some narrower floating-point format, the values will be losslessly converted up to FP32 before `ReLUStage` and converted back down afterwards. If `IntermediateFormat` is an integer format, `STACC_RELU_ApplyRelu` should be set to zero, which will guarantee the values pass through `ReLUStage` unchanged, or set to one, which will pass through positive integers unchanged and replace negative integers with zero.
