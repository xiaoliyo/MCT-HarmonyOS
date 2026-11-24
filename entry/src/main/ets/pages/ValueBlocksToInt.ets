/**
 * Value Blocks as Integers (port of
 * de.syss.MifareClassicTool.Activities.ValueBlocksToInt,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Display value blocks in a way a user can read easily (as integer).
 * NXP has PDFs describing what value blocks are. Google something
 * like "nxp MIFARE classic value blocks", if you want to have a
 * closer look. This page is shown from the dump editor, if the user
 * clicks the corresponding menu item. For every value block the
 * location (sector, block), the original data (first 4 bytes, the
 * value, in yellow) and the value resolved to an integer (in light
 * green) is displayed.
 */

import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { HexUtils } from '../common/HexUtils';

/** Params for the value blocks page (value blocks from the editor). */
export class ValueBlocksToIntParams {
  vb: string[] = [];
}

/** Kind of a value block table row. */
enum VbRowKind {
  PosInfo,
  BlockData
}

/** Render model for one row of the value block table. */
class VbRowInfo {
  kind: VbRowKind = VbRowKind.PosInfo;
  posText: string = '';
  labelText: string = '';
  valueText: string = '';
  valueColor: string = '';
}

/**
 * Create the "Original:" and "As Integer:" rows for one value block
 * (addValueBlock of the Android ValueBlocksToInt). The integer value
 * is the first 4 bytes of the value block read in little endian
 * order (like the ByteBuffer.getInt() after reversing the byte array
 * in the Android code). For valid value blocks this matches
 * MifareUtils.decodeValueBlock(bytes).value.
 */
function vbToIntRows(hexValueBlock: string): VbRowInfo[] {
  const rows: VbRowInfo[] = [];
  // Original (first 4 bytes as hex, yellow).
  const origRow = new VbRowInfo();
  origRow.kind = VbRowKind.BlockData;
  origRow.labelText = '原始数据：';
  origRow.valueText = hexValueBlock.substring(0, 8);
  origRow.valueColor = MctTheme.YELLOW;
  rows.push(origRow);
  // Resolved to int (light green).
  let asInt: number = 0;
  const asBytes: number[] | null =
    HexUtils.hex2Bytes(hexValueBlock.substring(0, 8));
  if (asBytes !== null && asBytes.length === 4) {
    HexUtils.reverseByteArrayInPlace(asBytes);
    asInt = (asBytes[0] << 24) | (asBytes[1] << 16)
      | (asBytes[2] << 8) | asBytes[3];
  }
  const intRow = new VbRowInfo();
  intRow.kind = VbRowKind.BlockData;
  intRow.labelText = '整数值：';
  intRow.valueText = asInt.toString();
  intRow.valueColor = MctTheme.LIGHT_GREEN;
  rows.push(intRow);
  return rows;
}

@Component
struct ValueBlocksToIntPage {
  @State vbRows: VbRowInfo[] = [];
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Init ----------------

  /**
   * Get the value blocks from the params and initialize the page to
   * displaying them (onCreate of the Android ValueBlocksToInt). The
   * value block array alternates between position header lines
   * ("+Sector: N, Block: M") and 32 hex char value block lines. If
   * there are no value blocks, the page exits (Android: finish()).
   */
  private initValueBlocks(valueBlocks: string[]): void {
    if (valueBlocks.length === 0) {
      // There were no value blocks.
      NfcService.toast('该转储中没有值块', true);
      this.pathStack.pop();
      return;
    }
    const rows: VbRowInfo[] = [];
    for (let i = 0; i + 1 < valueBlocks.length; i = i + 2) {
      // Position header ("Sector: N, Block: M").
      const sectorAndBlock: string[] = valueBlocks[i].split(', ');
      let sectorNumber: string = '';
      let blockNumber: string = '';
      if (sectorAndBlock.length >= 2) {
        const sectorParts: string[] = sectorAndBlock[0].split(': ');
        const blockParts: string[] = sectorAndBlock[1].split(': ');
        if (sectorParts.length >= 2) {
          sectorNumber = sectorParts[1];
        }
        if (blockParts.length >= 2) {
          blockNumber = blockParts[1];
        }
      }
      const posRow = new VbRowInfo();
      posRow.kind = VbRowKind.PosInfo;
      posRow.posText = '扇区：' + sectorNumber + '，'
        + '块：' + blockNumber;
      rows.push(posRow);
      // Value block (original + resolved to int).
      const blockRows: VbRowInfo[] = vbToIntRows(valueBlocks[i + 1]);
      rows.push(blockRows[0]);
      rows.push(blockRows[1]);
    }
    this.vbRows = rows;
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // Fixed table header (activity_value_blocks_to_int.xml).
        Row() {
          Text('位置：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .width(130)
          Text('值：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .layoutWeight(1)
        }
        .width('100%')
        .backgroundColor(MctTheme.DARK_GRAY)
        .padding(3)
        .alignItems(VerticalAlign.Center)

        // Value block table.
        Scroll() {
          Column() {
            if (this.vbRows.length > 0) {
              ForEach(this.vbRows,
                (row: VbRowInfo, index: number): void => {
                  if (row.kind === VbRowKind.PosInfo) {
                    // Position info row (where the value block is
                    // located, accent colored).
                    Text(row.posText)
                      .fontSize(16)
                      .fontColor(MctTheme.accent)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .padding({ top: 10, bottom: 2 })
                  } else {
                    // "Original:"/"As Integer:" row (label + value).
                    Row() {
                      Text(row.labelText)
                        .fontSize(16)
                        .fontColor(MctTheme.fg)
                        .width(130)
                      Text(row.valueText)
                        .fontSize(16)
                        .fontColor(row.valueColor)
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }
                },
                (row: VbRowInfo, index: number): string => index.toString())
            } else {
              // There were no value blocks (the page is about to
              // exit, this is a graceful fallback).
              Text('该转储中没有值块')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding(10)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('值块转整数')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: ValueBlocksToIntParams =
        (ctx.pathInfo.param as ValueBlocksToIntParams)
        ?? new ValueBlocksToIntParams();
      this.initValueBlocks(p.vb);
    })
    .onShown(() => {
      // The Android ValueBlocksToInt does not register a tag
      // listener (pure display page).
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function ValueBlocksToIntBuilder() {
  ValueBlocksToIntPage()
}
