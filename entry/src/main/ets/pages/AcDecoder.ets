/**
 * Access Conditions decoder (port of
 * de.syss.MifareClassicTool.Activities.AccessConditionDecoder,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Display the MIFARE Access Conditions in a way a user can read.
 * NXP has PDFs describing what access conditions are. Google
 * something like "nxp MIFARE classic access conditions", if you want
 * to have a closer look. This page is shown from the dump editor, if
 * the user clicks the corresponding menu item. For every sector the
 * access conditions of the 3 data blocks (Read/Write/Incr./
 * Decr./Trans./Rest.) and of the sector trailer (Key A/AC Bits/
 * Key B, read/write) are displayed as colored key requirements
 * ("Never" (orange), "Key A"/"Key B" (yellow), "Key A|B" (light
 * green), "Error: This configuration is not known" (red)).
 */

import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { HexUtils } from '../common/HexUtils';
import { MifareUtils } from '../common/MifareUtils';
import { Operation } from '../common/MctTypes';

/** Params for the access condition decoder page (ACs from the editor). */
export class AcDecoderParams {
  ac: string = '';
}

/** Kind of an access condition table row. */
enum AcRowKind {
  SectorHeader,
  InvalidAcError,
  DataBlock,
  Trailer
}

/** A colored permission text (getColoredPermissionText of the
 *  Android AccessConditionDecoder). */
class AcPermission {
  text: string = '';
  color: string = '';
}

/** Render model for one row of the access condition table. */
class AcRowInfo {
  kind: AcRowKind = AcRowKind.SectorHeader;
  locationText: string = '';
  read: AcPermission = new AcPermission();
  write: AcPermission = new AcPermission();
  incr: AcPermission = new AcPermission();
  decr: AcPermission = new AcPermission();
}

/** Width of the "Location:" column (aligns all table rows). */
const AC_DECODER_LOCATION_WIDTH: string = '92';
/** Width of the "Read:" column. */
const AC_DECODER_READ_WIDTH: string = '72';
/** Width of the "Write:" column. */
const AC_DECODER_WRITE_WIDTH: string = '72';
/** Width of the "Incr.:" column. */
const AC_DECODER_INCR_WIDTH: string = '60';

/**
 * Create a colored permission text depending on the access
 * conditions and the requested operation
 * (getColoredPermissionText of the Android
 * AccessConditionDecoder). Depending on the return value of
 * MifareUtils.getOperationRequirements() the text is:
 * 0="Never" (orange), 1="Key A" (yellow), 2="Key B" (yellow),
 * 3="Key A|B" (light green), 4="Error: This configuration is not
 * known" (red). On any other value an empty text is returned.
 */
function acColoredPermission(c1: number, c2: number, c3: number,
  op: Operation, isSectorTrailer: boolean,
  isKeyBReadable: boolean): AcPermission {
  const req: number = MifareUtils.getOperationRequirements(
    c1, c2, c3, op, isSectorTrailer, isKeyBReadable);
  const perm = new AcPermission();
  if (req === 0) {
    // Never.
    perm.text = '永不';
    perm.color = MctTheme.ORANGE;
  } else if (req === 1) {
    // Key A.
    perm.text = '密钥 A';
    perm.color = MctTheme.YELLOW;
  } else if (req === 2) {
    // Key B.
    perm.text = '密钥 B';
    perm.color = MctTheme.YELLOW;
  } else if (req === 3) {
    // Key A|B.
    perm.text = '密钥 A|B';
    perm.color = MctTheme.LIGHT_GREEN;
  } else if (req === 4) {
    // Access Condition Error.
    perm.text = '错误：未知配置';
    perm.color = MctTheme.RED;
  }
  // Error (any other value): empty string.
  return perm;
}

@Component
struct AcDecoderPage {
  @State acRows: AcRowInfo[] = [];
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Init ----------------

  /**
   * Get the access conditions from the params and initialize the
   * page to displaying them (onCreate of the Android
   * AccessConditionDecoder). The lines alternate between sector
   * headers ("+Sector: N") and access condition lines (8 hex chars,
   * "*"-prefixed for sectors with more than 4 blocks). If there are
   * no access conditions, the page exits (Android: finish()).
   */
  private initAccessConditions(acLines: string[]): void {
    if (acLines.length === 0) {
      // There were no access conditions.
      this.pathStack.pop();
      return;
    }
    const rows: AcRowInfo[] = [];
    for (let j = 0; j + 1 < acLines.length; j = j + 2) {
      let acHex: string = acLines[j + 1];
      let hasMoreThan4Blocks: boolean = false;
      if (acHex.startsWith('*')) {
        // Access Conditions of a sector with more than 4 blocks.
        hasMoreThan4Blocks = true;
        acHex = acHex.substring(1);
      }

      // b6 = bAC[0], b7 = bAC[1], ...
      const bAC: number[] | null = HexUtils.hex2Bytes(acHex);

      // acMatrix[C1-C3][Block0-Block2 + Sector Trailer]
      const acMatrix: number[][] | null = bAC !== null
        ? MifareUtils.acBytesToACMatrix(bAC) : null;

      // Add sector header.
      const headerParts: string[] = acLines[j].split(': ');
      const sectorNumber: string = headerParts.length >= 2
        ? headerParts[1] : '';
      const headerRow = new AcRowInfo();
      headerRow.kind = AcRowKind.SectorHeader;
      headerRow.locationText = '扇区：' + sectorNumber;
      rows.push(headerRow);

      if (acMatrix === null) {
        // Invalid access conditions.
        const errorRow = new AcRowInfo();
        errorRow.kind = AcRowKind.InvalidAcError;
        rows.push(errorRow);
      } else {
        // Add Block 0-2 and the sector trailer.
        this.addBlockAC(rows, acMatrix, hasMoreThan4Blocks);
        this.addSectorTrailerAC(rows, acMatrix);
      }
    }
    this.acRows = rows;
  }

  /**
   * Add full access condition information of the 3 data blocks to
   * the table (addBlockAC of the Android AccessConditionDecoder).
   * @param rows The table rows to append to.
   * @param acMatrix Matrix of access condition bits (C1-C3) where
   * the first dimension is the "C" parameter (C1-C3, index 0-2) and
   * the second dimension is the block number (block 0-2 + sector
   * trailer, index 0-3).
   * @param hasMoreThan4Blocks True for the last 8 sectors of a
   * MIFARE Classic 4K tag.
   */
  private addBlockAC(rows: AcRowInfo[], acMatrix: number[][],
    hasMoreThan4Blocks: boolean): void {
    const isKeyBReadable: boolean = MifareUtils.isKeyBReadable(
      acMatrix[0][3], acMatrix[1][3], acMatrix[2][3]);

    for (let i = 0; i < 3; i++) {
      const c1: number = acMatrix[0][i];
      const c2: number = acMatrix[1][i];
      const c3: number = acMatrix[2][i];
      const row = new AcRowInfo();
      row.kind = AcRowKind.DataBlock;
      if (hasMoreThan4Blocks) {
        row.locationText = '块：' + (i * 4 + i) + '-' + (i * 4 + 4 + i);
      } else {
        row.locationText = '块：' + i;
      }
      // Set cell texts to colored permissions.
      row.read = acColoredPermission(c1, c2, c3,
        Operation.Read, false, isKeyBReadable);
      row.write = acColoredPermission(c1, c2, c3,
        Operation.Write, false, isKeyBReadable);
      row.incr = acColoredPermission(c1, c2, c3,
        Operation.Increment, false, isKeyBReadable);
      row.decr = acColoredPermission(c1, c2, c3,
        Operation.DecTransRest, false, isKeyBReadable);
      rows.push(row);
    }
  }

  /**
   * Add full access condition information of the sector trailer
   * (last block) to the table (addSectorTrailerAC of the Android
   * AccessConditionDecoder).
   * @param rows The table rows to append to.
   * @param acMatrix Matrix of access condition bits as generated by
   * MifareUtils.acBytesToACMatrix().
   */
  private addSectorTrailerAC(rows: AcRowInfo[], acMatrix: number[][]): void {
    const c1: number = acMatrix[0][3];
    const c2: number = acMatrix[1][3];
    const c3: number = acMatrix[2][3];
    // Row headers and operations (read/write) of the
    // "Key A:", "AC Bits:" and "Key B:" rows.
    const headers: string[] = ['密钥 A：', '访问控制位：', '密钥 B：'];
    const readOps: Operation[] =
      [Operation.ReadKeyA, Operation.ReadAC, Operation.ReadKeyB];
    const writeOps: Operation[] =
      [Operation.WriteKeyA, Operation.WriteAC, Operation.WriteKeyB];
    for (let i = 0; i < 3; i++) {
      const row = new AcRowInfo();
      row.kind = AcRowKind.Trailer;
      row.locationText = headers[i];
      row.read = acColoredPermission(c1, c2, c3,
        readOps[i], true, false);
      row.write = acColoredPermission(c1, c2, c3,
        writeOps[i], true, false);
      rows.push(row);
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // Fixed table header
        // (activity_access_condition_decoder.xml).
        Row() {
          Text('位置：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .width(AC_DECODER_LOCATION_WIDTH)
          Text('读取：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .width(AC_DECODER_READ_WIDTH)
          Text('写入：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .width(AC_DECODER_WRITE_WIDTH)
          Text('增值：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .width(AC_DECODER_INCR_WIDTH)
          Text('减值/传输/恢复：')
            .fontSize(14)
            .fontColor(MctTheme.LIGHT_GRAY)
            .layoutWeight(1)
        }
        .width('100%')
        .backgroundColor(MctTheme.DARK_GRAY)
        .padding(3)
        .alignItems(VerticalAlign.Center)

        // Access condition table.
        Scroll() {
          Column() {
            if (this.acRows.length > 0) {
              ForEach(this.acRows,
                (row: AcRowInfo, index: number): void => {
                  if (row.kind === AcRowKind.SectorHeader) {
                    // Sector header (accent colored).
                    Text(row.locationText)
                      .fontSize(16)
                      .fontColor(MctTheme.accent)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .padding({ top: 10, bottom: 2 })
                  } else if (row.kind === AcRowKind.InvalidAcError) {
                    // Invalid access conditions (red).
                    Text('访问条件无效')
                      .fontSize(14)
                      .fontColor(MctTheme.RED)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                  } else if (row.kind === AcRowKind.DataBlock) {
                    // Data block row: Location | Read | Write |
                    // Incr. | Decr./Trans./Rest.
                    Row() {
                      Text(row.locationText)
                        .fontSize(14)
                        .fontColor(MctTheme.fg)
                        .width(AC_DECODER_LOCATION_WIDTH)
                      Text(row.read.text)
                        .fontSize(14)
                        .fontColor(row.read.color)
                        .width(AC_DECODER_READ_WIDTH)
                      Text(row.write.text)
                        .fontSize(14)
                        .fontColor(row.write.color)
                        .width(AC_DECODER_WRITE_WIDTH)
                      Text(row.incr.text)
                        .fontSize(14)
                        .fontColor(row.incr.color)
                        .width(AC_DECODER_INCR_WIDTH)
                      Text(row.decr.text)
                        .fontSize(14)
                        .fontColor(row.decr.color)
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)
                  } else {
                    // Sector trailer row: Location | Read | Write.
                    Row() {
                      Text(row.locationText)
                        .fontSize(14)
                        .fontColor(MctTheme.fg)
                        .width(AC_DECODER_LOCATION_WIDTH)
                      Text(row.read.text)
                        .fontSize(14)
                        .fontColor(row.read.color)
                        .width(AC_DECODER_READ_WIDTH)
                      Text(row.write.text)
                        .fontSize(14)
                        .fontColor(row.write.color)
                        .width(AC_DECODER_WRITE_WIDTH)
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Top)
                  }
                },
                (row: AcRowInfo, index: number): string => index.toString())
            } else {
              // There were no access conditions (the page is about
              // to exit, this is a graceful fallback).
              Text('没有可显示的访问条件')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding(10)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(3)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('访问条件')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: AcDecoderParams =
        (ctx.pathInfo.param as AcDecoderParams) ?? new AcDecoderParams();
      this.initAccessConditions(p.ac.split('\n'));
    })
    .onShown(() => {
      // The Android AccessConditionDecoder does not register a tag
      // listener (pure display page).
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function AcDecoderBuilder() {
  AcDecoderPage()
}
