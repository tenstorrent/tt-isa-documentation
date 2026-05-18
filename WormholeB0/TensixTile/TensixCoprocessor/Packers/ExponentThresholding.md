# Exponent Thresholding

Exponent thresholding can optionally be used to replace values which are close to zero with zero.

## Functional model

```c

Datum ApplyExponentThresholding(Datum d) {
  uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
  auto& CurrentPackerConfig = CurrentPacker.Config[StateID];
  if (CurrentPackerConfig.Exp_threshold_en) {
    uint8_t Threshold = CurrentPackerConfig.Exp_threshold;
    uint4_t DataFormat = CurrentPackerConfig.In_data_format;
    switch (DataFormat) {
    case FP32: case TF32: case BF16: case BFP8: case BFP4:
      // In these cases, d.Exponent is an 8-bit value.
      if (d.Exponent < Threshold) {
        return 0;
      }
      break;
    case FP16: case FP8: case BFP8a: case BFP4a:
      // In these cases, d.Exponent is a 5-bit value, and it'll be zero-extended
      // to eight bits before the comparison with Threshold.
      if (d.Exponent < Threshold) {
        return 0;
      }
      break;
    case BFP2a:
      UndefinedBehavior(); // Hardware bug
      break;
    }
  }
  return d;
}

```
