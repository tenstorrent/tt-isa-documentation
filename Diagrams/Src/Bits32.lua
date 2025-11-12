#!/usr/bin/env luajit
-- SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
--
-- SPDX-License-Identifier: Apache-2.0

local buffer = require"string.buffer"
local data_color = "#f4d7e3"
local xu_color = "#d4aa00"
local fe_color = "#87deaa"
local insn_color = "#aaaaff"

local own_dir = debug.getinfo(1, "S").source:match"@?(.*/)" or ""
package.path = own_dir .."?.lua;".. package.path
local Drawing = require"Drawing"

local function Bits32(fields)
  local nbits = fields.nbits or 32
  local cells_x = 5.5
  local cells_y = 21.5
  local cell_w = 19
  local cell_h = 31

  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 10 + cell_w * nbits + (fields.extra_w or 0), h = 55}
  for _, field in ipairs(fields) do
    if field.y then
      dims.h = math.max(dims.h, 65 + field.y * 20)
    end
  end
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="5" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  out:putf([[<rect x="%g" y="%g" width="%g" height="%g" stroke="black" fill="transparent" stroke-width="1"/>]],
    cells_x - 1, cells_y, cell_w * nbits, cell_h)
  local function label_bit(b)
    out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="auto">%d</text>]],
      cells_x + (cell_w * ((nbits - 1 - b) + 0.5)), cells_y - 3, b)
  end
  local vbar_on_right = {}
  for _, field in ipairs(fields) do
    local b0 = field[1]
    local bw = field[2]
    vbar_on_right[b0] = true
    vbar_on_right[b0 + bw] = true
    local field_text = field[3]
    if field_text ~= "" then
      label_bit(b0)
      if bw > 1 then
        label_bit(b0 + bw - 1)
      end
      field_text = '<tspan font-family="monospace">'.. field_text ..'</tspan>'
    end
    local text_b = b0 + bw * 0.5
    local text_x = cells_x + cell_w * (nbits - text_b)
    local text_y = cells_y + cell_h / 2
    if field.y then
      local new_y = text_y + 15 + (20 * field.y)
      out:putf([[<path d="M %g %g L %g %g" stroke="black" fill="transparent" stroke-width="1"/>]], text_x, text_y, text_x, new_y - 10)
      text_y = new_y
    end
    local anchor = "middle"
    if field.edge == "right" then
      text_x = cells_x + cell_w * (nbits - b0)
      anchor = "end"
    elseif field.edge == "left" then
      text_x = cells_x + cell_w * (nbits - (b0 + bw))
      anchor = "start"
    end
    out:putf([[<text x="%d" y="%d" text-anchor="%s" dominant-baseline="middle">%s</text>]],
      text_x, text_y, anchor, field_text)
  end
  for b = 1, nbits-1 do
    local x = cells_x + (cell_w * (nbits - b))
    if vbar_on_right[b] then
      out:putf([[<path d="M %g %g L %g %g" stroke="black" fill="transparent" stroke-width="1"/>]], x, cells_y + 0.5, x, cells_y + cell_h - 0.5)
    else
      out:putf([[<path d="M %g %g L %g %g" stroke="black" fill="transparent" stroke-width="1"/>]], x, cells_y + 0.5, x, cells_y + 3)
      out:putf([[<path d="M %g %g L %g %g" stroke="black" fill="transparent" stroke-width="1"/>]], x, cells_y + cell_h - 3, x, cells_y + cell_h - 0.5)
    end
  end

  out:putf"</svg>"

  return tostring(out)
end

local diagrams = {
  ATCAS = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {12, 2, "Ofs"},
      {14, 4, "CmpVal"},
      {18, 4, "SetVal"},
      {24, 8, "0x64"},
    }
  end,
  ATSWAP = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "DataReg"},
      {14, 8, "Mask"},
      {22, 1, "SingleDataReg", y = 1},
      {24, 8, "0x63"},
    }
  end,
  RMWCIB = function()
    return Bits32{
      {0, 8, "Index4"},
      {8, 8, "NewValue"},
      {16, 8, "Mask"},
      {24, 8, "0xB3 + Index1"},
    }
  end,
  SETDMAREG_Immediate = function()
    return Bits32{
      {0, 7, "ResultHalfReg"},
      {7, 1, "0"},
      {8, 16, "NewValue"},
      {24, 8, "0x45"},
    }
  end,
  SETDMAREG_Special = function()
    return Bits32{
      {0, 7, "ResultHalfReg"},
      {7, 1, "1"},
      {8, 3, "InputHalfReg", y = 1},
      {11, 4, "InputSource", y = 2},
      {15, 4, "WhichPackers", y = 1},
      {22, 2, "ResultSize", y = 1},
      {24, 8, "0x45"},
    }
  end,
  STALLWAIT = function()
    return Bits32{
      {0, 15, "ConditionMask"},
      {15, 9, "BlockMask"},
      {24, 8, "0xA2"},
    }
  end,
  STALLWAIT_BH = function()
    return Bits32{
      {0, 13, "ConditionMask"},
      {15, 9, "BlockMask"},
      {24, 8, "0xA2"},
    }
  end,
  SEMWAIT = function()
    return Bits32{
      {0, 2, "ConditionMask", y = 1, edge = "right"},
      {2, 8, "SemaphoreMask"},
      {15, 9, "BlockMask"},
      {24, 8, "0xA6"},
    }
  end,
  STREAMWAIT = function()
    return Bits32{
      {0, 2, "StreamSelect", y = 2, edge = "right"},
      {3, 1, "ConditionIndex", y = 1, edge = "right"},
      {4, 10, "TargetValueLo"},
      {15, 9, "BlockMask"},
      {24, 8, "0xA7"},
    }
  end,
  SEMINIT = function()
    return Bits32{
      {2, 8, "SemaphoreMask"},
      {16, 4, "NewValue"},
      {20, 4, "NewMax"},
      {24, 8, "0xA3"},
    }
  end,
  REPLAY = function()
    return Bits32{
      {0, 1, "Load", y = 2, edge = "right"},
      {1, 1, "Exec", y = 1},
      {4, 6, "Count"},
      {14, 5, "Index"},
      {24, 8, "0x04"},
    }
  end,
  PACR = function()
    return Bits32{
      {0, 1, "Last", y = 2, edge = "right"},
      {1, 1, "Flush", y = 1},
      {4, 1, "Concat", y = 1},
      {7, 1, "OvrdThreadId", y = 2},
      {8, 4, "PackerMask", y = 1},
      {12, 1, "ZeroWrite", y = 2},
      {15, 2, "AddrMod", y = 1},
      {23, 1, "0"},
      {24, 8, "0x41"},
    }
  end,
  PACR_SETREG = function()
    return Bits32{
      {1, 1, "1"},
      {2, 6, "AddrMid"},
      {8, 4, "0xF"},
      {12, 10, "Value10"},
      {22, 1, "AddrSel", y = 1},
      {23, 1, "1"},
      {24, 8, "0x4A"},
    }
  end,
  SFPSHFT2 = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {24, 8, "0x94"},
    }
  end,
  SFPSHFT2b = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {12, 12, "Imm12 (signed)"},
      {24, 8, "0x94"},
    }
  end,
  SFPLUTFP32 = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {24, 8, "0x95"},
    }
  end,
  SFPLUTFP32_BH = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {16, 4, "Mod1Mirror", y=1},
      {24, 8, "0x95"},
    }
  end,
  REG2FLOP_Configuration = function()
    return Bits32{
      {0, 6, "InputReg"},
      {6, 7, "ThConCfgIndex"},
      {20, 2, "0"},
      {22, 2, "SizeSel", y = 1},
      {24, 8, "0x48"},
    }
  end,
  REG2FLOP_ADC = function()
    return Bits32{
      {0, 6, "InputReg"},
      {6, 2, "XYZW"},
      {8, 1, "Cr"},
      {9, 2, "ADCSel", y = 1},
      {11, 1, "Channel", y = 2},
      {16, 2, "ThreadSel", y = 3},
      {18, 2, "Shift8", y = 1},
      {20, 1, "OverrideThread", y = 2},
      {21, 1, "1"},
      {22, 2, "SizeSel", y = 1},
      {24, 8, "0x48"},
    }
  end,
  XMOV = function()
    return Bits32{
      {23, 1, "0"},
      {24, 8, "0x40"},
    }
  end,
  WRCFG = function()
    return Bits32{
      {0, 11, "CfgIndex"},
      {15, 1, "Is128Bit", y = 1},
      {16, 6, "InputReg"},
      {24, 8, "0xB0"},
    }
  end,
  RDCFG = function()
    return Bits32{
      {0, 11, "CfgIndex"},
      {16, 6, "ResultReg"},
      {24, 8, "0xB1"},
    }
  end,
  SETC16 = function()
    return Bits32{
      {0, 16, "NewValue"},
      {16, 8, "CfgIndex"},
      {24, 8, "0xB2"},
    }
  end,
  STREAMWRCFG = function()
    return Bits32{
      {0, 11, "CfgIndex"},
      {11, 10, "RegIndex"},
      {21, 2, "StreamSelect", y = 1},
      {24, 8, "0xB7"},
    }
  end,
  CFGSHIFTMASK = function()
    return Bits32{
      {0, 8, "CfgIndex"},
      {8, 2, "ScratchIndex", y = 1},
      {10, 5, "RotateAmt"},
      {15, 5, "MaskWidth"},
      {20, 3, "AluMode", y = 2},
      {23, 1, "MaskMode", y = 1},
      {24, 8, "0xB8"},
    }
  end,
  SETADC = function()
    return Bits32{
      {0, 18, "NewValue"},
      {18, 2, "XYZW"},
      {20, 1, "Channel", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x50"},
    }
  end,
  SETADCXY = function()
    return Bits32{
      {0, 1, "X0"},
      {1, 1, "Y0"},
      {2, 1, "X1"},
      {3, 1, "Y1"},
      {6, 3, "X0Val"},
      {9, 3, "Y0Val"},
      {12, 3, "X1Val"},
      {15, 3, "Y1Val"},
      {18, 2, "ThreadOverride", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x51"},
    }
  end,
  INCADCXY = function()
    return Bits32{
      {6, 3, "X0Inc"},
      {9, 3, "Y0Inc"},
      {12, 3, "X1Inc"},
      {15, 3, "Y1Inc"},
      {18, 2, "ThreadOverride", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x52"},
    }
  end,
  ADDRCRXY = function()
    return Bits32{
      {0, 1, "X0"},
      {1, 1, "Y0"},
      {2, 1, "X1"},
      {3, 1, "Y1"},
      {6, 3, "X0Inc"},
      {9, 3, "Y0Inc"},
      {12, 3, "X1Inc"},
      {15, 3, "Y1Inc"},
      {18, 2, "ThreadOverride", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x53"},
    }
  end,
  SETADCZW = function()
    return Bits32{
      {0, 1, "Z0"},
      {1, 1, "W0"},
      {2, 1, "Z1"},
      {3, 1, "W1"},
      {6, 3, "Z0Val"},
      {9, 3, "W0Val"},
      {12, 3, "Z1Val"},
      {15, 3, "W1Val"},
      {18, 2, "ThreadOverride", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x54"},
    }
  end,
  INCADCZW = function()
    return Bits32{
      {6, 3, "Z0Inc"},
      {9, 3, "W0Inc"},
      {12, 3, "Z1Inc"},
      {15, 3, "W1Inc"},
      {18, 2, "ThreadOverride", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x55"},
    }
  end,
  ADDRCRZW = function()
    return Bits32{
      {0, 1, "Z0"},
      {1, 1, "W0"},
      {2, 1, "Z1"},
      {3, 1, "W1"},
      {6, 3, "Z0Inc"},
      {9, 3, "W0Inc"},
      {12, 3, "Z1Inc"},
      {15, 3, "W1Inc"},
      {18, 2, "ThreadOverride", y=1},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x56"},
    }
  end,
  SETADCXX = function()
    return Bits32{
      {0, 10, "X0Val"},
      {10, 10, "X1Val"},
      {21, 1, "U0"},
      {22, 1, "U1"},
      {23, 1, "PK"},
      {24, 8, "0x5E"},
    }
  end,
  NOP = function()
    return Bits32{
      {24, 8, "0x02"},
    }
  end,
  SEMINIT = function()
    return Bits32{
      {2, 8, "SemaphoreMask"},
      {16, 4, "NewValue"},
      {20, 4, "NewMax"},
      {24, 8, "0xA3"},
    }
  end,
  SEMPOST = function()
    return Bits32{
      {2, 8, "SemaphoreMask"},
      {24, 8, "0xA4"},
    }
  end,
  SEMGET = function()
    return Bits32{
      {2, 8, "SemaphoreMask"},
      {24, 8, "0xA5"},
    }
  end,
  SETDVALID = function()
    return Bits32{
      {0, 1, "FlipSrcA", y = 2, edge = "right"},
      {1, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x57"},
    }
  end,
  GATESRCRST = function()
    return Bits32{
      {1, 1, "InvalidateSrcBCache", y = 1, edge = "right"},
      {24, 8, "0x35"},
    }
  end,
  MOVD2A = function()
    return Bits32{
      {0, 10, "DstRow"},
      {13, 1, "Move4Rows", y = 2},
      {15, 2, "AddrMod", y = 1},
      {17, 6, "SrcRow"},
      {23, 1, "UseDst32bLo", y = 1},
      {24, 8, "0x08"},
    }
  end,
  MOVD2B = function()
    return Bits32{
      {0, 10, "DstRow"},
      {13, 1, "Move4Rows", y = 2},
      {15, 2, "AddrMod", y = 1},
      {17, 6, "SrcRow"},
      {23, 1, "UseDst32bLo", y = 1},
      {24, 8, "0x0A"},
    }
  end,
  MOVB2A = function()
    return Bits32{
      {0, 6, "SrcBRow"},
      {13, 1, "Move4Rows", y = 2},
      {15, 2, "AddrMod", y = 1},
      {17, 6, "SrcARow"},
      {24, 8, "0x0B"},
    }
  end,
  MOVDBGA2D = function()
    return Bits32{
      {0, 10, "DstRow"},
      {13, 1, "Move8Rows", y = 2},
      {15, 2, "AddrMod", y = 1},
      {17, 6, "SrcRow"},
      {23, 1, "UseDst32bLo", y = 1},
      {24, 8, "0x09"},
    }
  end,
  ZEROSRC = function()
    return Bits32{
      {0, 1, "ClearSrcA", y = 5, edge = "right"},
      {1, 1, "ClearSrcB", y = 4, edge = "right"},
      {2, 1, "BothBanks", y = 3, edge = "right"},
      {3, 1, "SingleBankMatrixUnit", y = 2, edge = "right"},
      {4, 1, "NegativeInfSrcA", y = 1, edge = "right"},
      {24, 8, "0x11"},
    }
  end,
  MOVA2D = function()
    return Bits32{
      {0, 10, "DstRow"},
      {13, 1, "Move8Rows", y = 2},
      {15, 2, "AddrMod", y = 1},
      {17, 6, "SrcRow"},
      {23, 1, "UseDst32bLo", y = 1},
      {24, 8, "0x12"},
    }
  end,
  MOVB2D = function()
    return Bits32{
      {0, 10, "DstRow"},
      {12, 1, "BroadcastCol0", y = 1, edge = "left"},
      {13, 1, "Broadcast1RowTo8", y = 3},
      {14, 1, "Move4Rows", y = 2, edge = "right"},
      {15, 2, "AddrMod", y = 1, edge = "right"},
      {17, 6, "SrcRow"},
      {23, 1, "UseDst32bLo", y = 1},
      {24, 8, "0x13"},
    }
  end,
  ELWMUL = function()
    return Bits32{
      {0, 10, "DstRow"},
      {15, 2, "AddrMod", y = 1},
      {19, 1, "BroadcastSrcBCol0", y = 2, edge = "left"},
      {20, 1, "BroadcastSrcBRow", y = 3},
      {22, 1, "FlipSrcA", y = 2},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x27"},
    }
  end,
  ELWADD = function()
    return Bits32{
      {0, 10, "DstRow"},
      {15, 2, "AddrMod", y = 1},
      {19, 1, "BroadcastSrcBCol0", y = 2, edge = "left"},
      {20, 1, "BroadcastSrcBRow", y = 3, edge = "left"},
      {21, 1, "AddDst", y = 4},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x28"},
    }
  end,
  ELWSUB = function()
    return Bits32{
      {0, 10, "DstRow"},
      {15, 2, "AddrMod", y = 1},
      {19, 1, "BroadcastSrcBCol0", y = 2, edge = "left"},
      {20, 1, "BroadcastSrcBRow", y = 3, edge = "left"},
      {21, 1, "AddDst", y = 4},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x30"},
    }
  end,
  GMPOOL = function()
    return Bits32{
      {0, 10, "DstRow"},
      {14, 1, "ArgMax", y = 1, edge = "left"},
      {15, 2, "AddrMod", y = 2},
      {22, 1, "FlipSrcA", y = 2},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x33"},
    }
  end,
  ZEROACC = function()
    return Bits32{
      {0, 10, "Imm10"},
      {15, 2, "AddrMod", y = 1},
      {18, 1, "Revert", y = 2},
      {19, 2, "Mode"},
      {21, 1, "UseDst32b", y = 1},
      {24, 8, "0x10"},
    }
  end,
  TRNSPSRCB = function()
    return Bits32{
      {24, 8, "0x16"},
    }
  end,
  SHIFTXA = function()
    return Bits32{
      {0, 2, "Direction", y = 1, edge = "right"},
      {24, 8, "0x17"},
    }
  end,
  SHIFTXB = function()
    return Bits32{
      {0, 6, "SrcRow"},
      {10, 1, "ShiftInZero", y=1},
      {15, 2, "AddrMod", y = 1},
      {24, 8, "0x18"},
    }
  end,
  CLREXPHIST = function()
    return Bits32{
      {24, 8, "0x21"},
    }
  end,
  MVMUL = function()
    return Bits32{
      {0, 10, "DstRow"},
      {15, 2, "AddrMod", y = 1},
      {19, 1, "BroadcastSrcBRow", y = 2, edge = "left"},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x26"},
    }
  end,
  DOTPV = function()
    return Bits32{
      {0, 10, "DstRow"},
      {15, 2, "AddrMod", y = 1},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x29"},
    }
  end,
  GAPOOL = function()
    return Bits32{
      {0, 10, "DstRow"},
      {15, 2, "AddrMod", y = 1},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x34"},
    }
  end,
  CLEARDVALID = function()
    return Bits32{
      {0, 1, "Reset", y = 2, edge = "right"},
      {1, 1, "KeepReadingSameSrc", y = 1, edge = "right"},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x36"},
    }
  end,
  SETRWC = function()
    return Bits32{
      {0, 1, "SrcA", y = 4, edge = "right"},
      {1, 1, "SrcB", y = 3, edge = "right"},
      {2, 1, "Dst", y = 2, edge = "right"},
      {3, 1, "Fidelity", y = 1, edge = "right"},
      {6, 4, "SrcAVal"},
      {10, 4, "SrcBVal"},
      {14, 4, "DstVal"},
      {18, 1, "SrcACr", y = 1, edge = "left"},
      {19, 1, "SrcBCr", y = 2, edge = "left"},
      {20, 1, "DstCr", y = 4},
      {21, 1, "DstCtoCr", y = 3, edge = "right"},
      {22, 1, "FlipSrcA", y = 2, edge = "right"},
      {23, 1, "FlipSrcB", y = 1, edge = "right"},
      {24, 8, "0x37"},
    }
  end,
  INCRWC = function()
    return Bits32{
      {6, 4, "SrcAInc"},
      {10, 4, "SrcBInc"},
      {14, 4, "DstInc"},
      {18, 1, "SrcACr", y = 1, edge = "left"},
      {19, 1, "SrcBCr", y = 2},
      {20, 1, "DstCr", y = 1, edge = "right"},
      {24, 8, "0x38"},
    }
  end,
  LOADIND = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "ResultReg"},
      {12, 2, "OffsetIncrement", y = 1},
      {14, 7, "OffsetHalfReg"},
      {22, 2, "Size"},
      {24, 8, "0x49"},
    }
  end,
  STOREIND_L1 = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "DataReg"},
      {12, 2, "OffsetIncrement", y = 1},
      {14, 7, "OffsetHalfReg"},
      {21, 2, "Size"},
      {23, 1, "1"},
      {24, 8, "0x66"},
    }
  end,
  STOREIND_MMIO = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "DataReg"},
      {12, 2, "OffsetIncrement", y = 1},
      {14, 7, "OffsetHalfReg"},
      {22, 1, "1"},
      {23, 1, "0"},
      {24, 8, "0x66"},
    }
  end,
  STOREIND_Src = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "DataReg"},
      {12, 2, "OffsetIncrement", y = 1},
      {14, 7, "OffsetHalfReg"},
      {21, 1, "StoreToSrcB", y = 1},
      {22, 1, "0"},
      {23, 1, "0"},
      {24, 8, "0x66"},
    }
  end,
  LOADREG = function()
    return Bits32{
      {0, 18, "AddrLo"},
      {18, 6, "ResultReg"},
      {24, 8, "0x68"},
    }
  end,
  STOREREG = function()
    return Bits32{
      {0, 18, "AddrLo"},
      {18, 6, "DataReg"},
      {24, 8, "0x67"},
    }
  end,
  FLUSHDMA = function()
    return Bits32{
      {0, 4, "ConditionMask", y = 1, edge = "right"},
      {24, 8, "0x46"},
    }
  end,
  DMANOP = function()
    return Bits32{
      {24, 8, "0x60"},
    }
  end,
  ADDDMAREG = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightReg"},
      {12, 6, "ResultReg"},
      {23, 1, "0"},
      {24, 8, "0x58"},
    }
  end,
  ADDDMAREGi = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightImm6"},
      {12, 6, "ResultReg"},
      {23, 1, "1"},
      {24, 8, "0x58"},
    }
  end,
  SUBDMAREG = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightReg"},
      {12, 6, "ResultReg"},
      {23, 1, "0"},
      {24, 8, "0x59"},
    }
  end,
  SUBDMAREGi = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightImm6"},
      {12, 6, "ResultReg"},
      {23, 1, "1"},
      {24, 8, "0x59"},
    }
  end,
  MULDMAREG = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightReg"},
      {12, 6, "ResultReg"},
      {23, 1, "0"},
      {24, 8, "0x5A"},
    }
  end,
  MULDMAREGi = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightImm6"},
      {12, 6, "ResultReg"},
      {23, 1, "1"},
      {24, 8, "0x5A"},
    }
  end,
  BITWOPDMAREG = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightReg"},
      {12, 6, "ResultReg"},
      {18, 3, "Mode"},
      {23, 1, "0"},
      {24, 8, "0x5B"},
    }
  end,
  BITWOPDMAREGi = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightImm6"},
      {12, 6, "ResultReg"},
      {18, 3, "Mode"},
      {23, 1, "1"},
      {24, 8, "0x5B"},
    }
  end,
  SHIFTDMAREG = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightReg"},
      {12, 6, "ResultReg"},
      {18, 3, "Mode"},
      {23, 1, "0"},
      {24, 8, "0x5C"},
    }
  end,
  SHIFTDMAREGi = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 5, "RightImm5"},
      {12, 6, "ResultReg"},
      {18, 3, "Mode"},
      {23, 1, "1"},
      {24, 8, "0x5C"},
    }
  end,
  CMPDMAREG = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightReg"},
      {12, 6, "ResultReg"},
      {18, 3, "Mode"},
      {23, 1, "0"},
      {24, 8, "0x5D"},
    }
  end,
  CMPDMAREGi = function()
    return Bits32{
      {0, 6, "LeftReg"},
      {6, 6, "RightImm6"},
      {12, 6, "ResultReg"},
      {18, 3, "Mode"},
      {23, 1, "1"},
      {24, 8, "0x5D"},
    }
  end,
  ATGETM = function()
    return Bits32{
      {0, 16, "Index"},
      {24, 8, "0xA0"},
    }
  end,
  ATRELM = function()
    return Bits32{
      {0, 16, "Index"},
      {24, 8, "0xA1"},
    }
  end,
  ATINCGET = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "InOutReg"},
      {12, 2, "Ofs"},
      {14, 5, "IntWidth"},
      {24, 8, "0x61"},
    }
  end,
  ATINCGETPTR = function()
    return Bits32{
      {0, 6, "AddrReg"},
      {6, 6, "ResultReg"},
      {12, 2, "Ofs"},
      {14, 4, "IntWidth"},
      {18, 4, "IncrLog2"},
      {22, 1, "NoIncr", y=1},
      {24, 8, "0x62"},
    }
  end,
  SFPLOAD = function()
    return Bits32{
      {0, 10, "Imm10"},
      {14, 2, "AddrMod", y=1},
      {16, 4, "Mod0"},
      {20, 4, "VD"},
      {24, 8, "0x70"},
    }
  end,
  SFPLOAD_BH = function()
    return Bits32{
      {0, 10, "Imm10"},
      {13, 3, "AddrMod", y=1},
      {16, 4, "Mod0"},
      {20, 4, "VD"},
      {24, 8, "0x70"},
    }
  end,
  SFPLOADMACRO = function()
    return Bits32{
      {0, 1, "VDHi", y=1, edge="right"},
      {1, 9, "Imm9"},
      {14, 2, "AddrMod", y=1},
      {16, 4, "Mod0"},
      {20, 2, "VDLo"},
      {22, 2, "MacroIndex", y=1},
      {24, 8, "0x93"},
    }
  end,
  SFPLOADMACRO_BH = function()
    return Bits32{
      {0, 1, "VDHi", y=1, edge="right"},
      {1, 9, "Imm9"},
      {13, 3, "AddrMod", y=1},
      {16, 4, "Mod0"},
      {20, 2, "VDLo"},
      {22, 2, "MacroIndex", y=1},
      {24, 8, "0x93"},
    }
  end,
  SFPSTORE = function()
    return Bits32{
      {0, 10, "Imm10"},
      {14, 2, "AddrMod", y=1},
      {16, 4, "Mod0"},
      {20, 4, "VD"},
      {24, 8, "0x72"},
    }
  end,
  SFPSTORE_BH = function()
    return Bits32{
      {0, 10, "Imm10"},
      {13, 3, "AddrMod", y=1},
      {16, 4, "Mod0"},
      {20, 4, "VD"},
      {24, 8, "0x72"},
    }
  end,
  MOP = function()
    return Bits32{
      {0, 16, "MaskLo"},
      {16, 7, "Count1"},
      {23, 1, "Template", y=1},
      {24, 8, "0x01"},
    }
  end,
  MOP_CFG = function()
    return Bits32{
      {0, 16, "MaskHi"},
      {24, 8, "0x03"},
    }
  end,
  SFPLOADI = function()
    return Bits32{
      {0, 16, "Imm16"},
      {16, 4, "Mod0"},
      {20, 4, "VD"},
      {24, 8, "0x71"},
    }
  end,
  SFPIADD = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 12, "Imm12 (signed)"},
      {24, 8, "0x79"},
    }
  end,
  SFPSWAP = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x92"},
    }
  end,
  SFPCONFIG = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 16, "Imm16"},
      {24, 8, "0x91"},
    }
  end,
  SFPMAD = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {16, 4, "VA"},
      {24, 8, "0x84"},
    }
  end,
  SFPADD = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {16, 4, "VA"},
      {24, 8, "0x85"},
    }
  end,
  SFPMUL = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {16, 4, "VA"},
      {24, 8, "0x86"},
    }
  end,
  SFPLUT = function()
    return Bits32{
      {16, 4, "Mod0"},
      {20, 4, "VD"},
      {24, 8, "0x73"},
    }
  end,
  SFPMULI = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 16, "Imm16"},
      {24, 8, "0x74"},
    }
  end,
  SFPADDI = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 16, "Imm16"},
      {24, 8, "0x75"},
    }
  end,
  SFPDIVP2 = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 8, "Imm8"},
      {24, 8, "0x76"},
    }
  end,
  SFPEXEXP = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x77"},
    }
  end,
  SFPEXMAN = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x78"},
    }
  end,
  SFPSHFT = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 12, "Imm12 (signed)"},
      {24, 8, "0x7A"},
    }
  end,
  SFPSETCC = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 1, "Imm1", y=1},
      {24, 8, "0x7B"},
    }
  end,
  SFPMOV = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x7C"},
    }
  end,
  SFPABS = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x7D"},
    }
  end,
  SFPAND = function()
    return Bits32{
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x7E"},
    }
  end,
  SFPAND_BH = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {24, 8, "0x7E"},
    }
  end,
  SFPOR = function()
    return Bits32{
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x7F"},
    }
  end,
  SFPOR_BH = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {24, 8, "0x7F"},
    }
  end,
  SFPNOT = function()
    return Bits32{
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x80"},
    }
  end,
  SFPLZ = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x81"},
    }
  end,
  SFPSETEXP = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 8, "Imm8"},
      {24, 8, "0x82"},
    }
  end,
  SFPSETMAN = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 12, "Imm12"},
      {24, 8, "0x83"},
    }
  end,
  SFPPUSHC = function()
    return Bits32{
      {0, 4, "0"},
      {4, 4, "VD"},
      {24, 8, "0x87"},
    }
  end,
  SFPPUSHC_BH = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {24, 8, "0x87"},
    }
  end,
  SFPPOPC = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {24, 8, "0x88"},
    }
  end,
  SFPSETSGN = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 1, "Imm1", y = 1},
      {24, 8, "0x89"},
    }
  end,
  SFPENCC = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {12, 2, "Imm2"},
      {24, 8, "0x8A"},
    }
  end,
  SFPCOMPC = function()
    return Bits32{
      {4, 4, "VD"},
      {24, 8, "0x8B"},
    }
  end,
  SFPTRANSP = function()
    return Bits32{
      {4, 4, "VD"},
      {24, 8, "0x8C"},
    }
  end,
  SFPXOR = function()
    return Bits32{
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x8D"},
    }
  end,
  SFPSTOCHRND = function()
    return Bits32{
      {0, 3, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {21, 1, "StochasticRounding", y=1},
      {24, 8, "0x8E"},
    }
  end,
  SFPSTOCHRNDi = function()
    return Bits32{
      {0, 3, "Mod1"},
      {3, 1, "UseImm5", y=1},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {16, 5, "Imm5"},
      {21, 1, "StochasticRounding", y=1},
      {24, 8, "0x8E"},
    }
  end,
  SFPSTOCHRND_BH = function()
    return Bits32{
      {0, 3, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {21, 2, "RoundingMode", y=1},
      {24, 8, "0x8E"},
    }
  end,
  SFPSTOCHRNDi_BH = function()
    return Bits32{
      {0, 3, "Mod1"},
      {3, 1, "UseImm5", y=1},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {16, 5, "Imm5"},
      {21, 2, "RoundingMode", y=1},
      {24, 8, "0x8E"},
    }
  end,
  SFPNOP = function()
    return Bits32{
      {7, 1, "0"},
      {24, 8, "0x8F"},
    }
  end,
  SFPCAST = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x90"},
    }
  end,
  SFPLE = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x96"},
    }
  end,
  SFPGT = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {24, 8, "0x97"},
    }
  end,
  SFPMUL24 = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {16, 4, "VA"},
      {24, 8, "0x98"},
    }
  end,
  SFPARECIP = function()
    return Bits32{
      {0, 4, "Mod1"},
      {4, 4, "VD"},
      {8, 4, "VC"},
      {12, 4, "VB"},
      {24, 8, "0x99"},
    }
  end,
  UNPACR_Regular = function()
    return Bits32{extra_w = 70,
      {1, 1, "0"},
      {2, 1, "RowSearch", y = 1, edge = "left"},
      {3, 1, "UseContextCounter", y = 2, edge = "left"},
      {4, 1, "AllDatumsAreZero", y = 3, edge = "left"},
      {6, 1, "FlipSrc", y = 4},
      {7, 1, "MultiContextMode", y = 3, edge = "right"},
      {8, 2, "ContextADC", y = 2, edge = "right"},
      {10, 3, "ContextNumber", y = 1, edge = "right"},
      {13, 1, "0"},
      {15, 2, "Ch0ZInc", y = 3},
      {17, 2, "Ch0YInc", y = 2},
      {19, 2, "Ch1ZInc", y = 1},
      {21, 2, "Ch1YInc", y = 2},
      {23, 1, "WhichUnpacker", y = 1, edge = "right"},
      {24, 8, "0x42"},
    }
  end,
  UNPACR_IncrementContextCounter = function()
    return Bits32{
      {1, 1, "0"},
      {13, 1, "1"},
      {23, 1, "WhichUnpacker", y = 1},
      {24, 8, "0x42"},
    }
  end,
  UNPACR_FlushCache = function()
    return Bits32{
      {1, 1, "1"},
      {7, 1, "MultiContextMode", y = 1},
      {23, 1, "WhichUnpacker", y = 1},
      {24, 8, "0x42"},
    }
  end,
  UNPACR_NOP_OverlayClear0 = function()
    return Bits32{
      {0, 3, "0x0"},
      {23, 1, "WhichUnpacker", y = 2},
      {24, 8, "0x43"},
    }
  end,
  UNPACR_NOP_OverlayClear3 = function()
    return Bits32{
      {0, 3, "0x3"},
      {4, 11, "ClearCount"},
      {16, 6, "WhichStream"},
      {23, 1, "WhichUnpacker", y = 2},
      {24, 8, "0x43"},
    }
  end,
  UNPACR_NOP_ZEROSRC = function()
    return Bits32{
      {0, 2, "0x1"},
      {2, 1, "NegativeInfSrcA", y = 3, edge = "right"},
      {3, 1, "BothBanks", y = 2, edge = "right"},
      {4, 1, "WaitLikeUnpacr", y = 1, edge = "right"},
      {6, 1, "0"},
      {23, 1, "WhichUnpacker", y = 1},
      {24, 8, "0x43"},
    }
  end,
  UNPACR_NOP_Nop = function()
    return Bits32{
      {0, 3, "0x2"},
      {23, 1, "WhichUnpacker", y = 1},
      {24, 8, "0x43"},
    }
  end,
  UNPACR_NOP_SETREG = function()
    return Bits32{
      {0, 3, "0x4"},
      {3, 1, "Accumulate", y = 1},
      {4, 11, "Value11"},
      {16, 6, "AddrMid"},
      {22, 1, "AddrSel", y = 1, edge = "left"},
      {23, 1, "WhichUnpacker", y = 2},
      {24, 8, "0x43"},
    }
  end,
  UNPACR_NOP_SETDVALID = function()
    return Bits32{
      {0, 3, "0x7"},
      {23, 1, "WhichUnpacker", y = 1},
      {24, 8, "0x43"},
    }
  end,
  Src_TF32 = function()
    return Bits32{nbits = 19,
      {0, 8, "Exponent"},
      {8, 10, "Mantissa"},
      {18, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Src_BF16 = function()
    return Bits32{nbits = 19,
      {0, 8, "Exponent"},
      {8, 3, "0"},
      {11, 7, "Mantissa"},
      {18, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Src_FP16 = function()
    return Bits32{nbits = 19,
      {0, 5, "Exponent"},
      {5, 3, "0"},
      {8, 10, "Mantissa"},
      {18, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Src_INT8 = function()
    return Bits32{nbits = 19,
      {0, 5, "16 or 0"},
      {5, 3, "0"},
      {8, 10, "Magnitude"},
      {18, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Src_INT16 = function()
    return Bits32{nbits = 19,
      {0, 8, "Magnitude (low)"},
      {8, 3, "0"},
      {11, 7, "Magnitude (high)"},
      {18, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Dst16_BF16 = function()
    return Bits32{nbits = 16,
      {0, 8, "Exponent"},
      {8, 7, "Mantissa"},
      {15, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Dst16_FP16 = function()
    return Bits32{nbits = 16,
      {0, 5, "Exponent"},
      {5, 10, "Mantissa"},
      {15, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Dst16_INT8 = function()
    return Bits32{nbits = 16,
      {0, 5, "16 or 0"},
      {5, 10, "Magnitude"},
      {15, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Dst16_INT16 = function()
    return Bits32{nbits = 16,
      {0, 15, "Magnitude"},
      {15, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Dst32_FP32 = function()
    return Bits32{
      {0, 16, "Mantissa (low)"},
      {16, 8, "Exponent"},
      {24, 7, "Mantissa (high)"},
      {31, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  Dst32_INT32 = function()
    return Bits32{
      {0, 16, "Magnitude (low)"},
      {16, 8, "Magnitude (high)"},
      {24, 7, "Magnitude (middle)", y = 2},
      {31, 1, "Sign", y = 1, edge = "left"},
    }
  end,
  NOC_AT_LEN_BE_Increment = function()
    return Bits32{
      {0, 2, "Ofs"},
      {2, 5, "IntWidth"},
      {12, 4, "1"},
    }
  end,
  NOC_AT_LEN_BE_CAS = function()
    return Bits32{
      {0, 2, "Ofs"},
      {2, 4, "CmpVal"},
      {6, 4, "SetVal"},
      {12, 4, "4"},
    }
  end,
  NOC_AT_LEN_BE_SwapMask = function()
    return Bits32{
      {2, 8, "Mask"},
      {12, 4, "3"},
    }
  end,
  NOC_AT_LEN_BE_SwapIndex6 = function()
    return Bits32{
      {0, 2, "Ofs"},
      {2, 1, "1"},
      {12, 4, "6"},
    }
  end,
  NOC_AT_LEN_BE_SwapIndex7 = function()
    return Bits32{
      {2, 2, "Ofs"},
      {12, 4, "7"},
    }
  end,
  NOC_AT_LEN_BE_SwapIndex10 = function()
    return Bits32{
      {0, 2, "Ofs"},
      {8, 4, "3"},
      {12, 4, "0xA"},
    }
  end,
  NOC_AT_LEN_BE_Zaamo = function()
    return Bits32{
      {0, 2, "Ofs"},
      {8, 3, "Op"},
      {11, 1, "1"},
      {12, 4, "0xA"},
    }
  end,
  NOC_AT_LEN_BE_Acc = function()
    return Bits32{
      {0, 4, "Fmt"},
      {12, 4, "9"},
    }
  end,
}
local function do_diagram(which)
  local fn = diagrams[which] or error("Unknown diagram ".. which)
  local output = fn()
  assert(io.open(own_dir .."../Out/Bits32_".. which ..".svg", "w")):write(output)
end

local which = ...
if which == nil then
  for k in pairs(diagrams) do
    do_diagram(k)
  end
elseif which then
  do_diagram(which)
end
