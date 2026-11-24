/**
 * Diff Tool (port of de.syss.MifareClassicTool.Activities.DiffTool and
 * de.syss.MifareClassicTool.MCDiffUtils, GPL-3.0, Gerhard Klostermeier).
 *
 * A tool to show the difference between two dumps. Dump 1 (A) is the
 * dump from the dump editor (passed via the page params, Android:
 * EXTRA_DUMP). Dump 2 (B) is read live from the current tag
 * (adaptation of the Android original, where dump 2 is chosen from a
 * dump file via the file chooser). The diff is displayed per block:
 * For every block the data of dump 1 and dump 2 is shown (monospace)
 * with a diff line in between. Identical blocks are displayed as a
 * green line of 32 "-", differing characters are marked with a red
 * "X". Sectors that exist in only one dump are marked accordingly.
 * Additionally, the difference between both dumps is displayed as a
 * percentage ("Difference between dumps: NN.NN %"). The diff is
 * updated live whenever a new tag is discovered.
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { McReader } from '../common/McReader';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { SectorKeys } from '../common/MctTypes';

/** Params for the diff tool page (dump 1 from the dump editor). */
export class DiffToolParams {
  dump: string[] = [];
}

/** Kind of a diff content row. */
enum DiffRowKind {
  SectorHeader,
  OnlyInOneDump,
  Block
}

/** Render model for one row of the diff output. */
class DiffRowInfo {
  kind: DiffRowKind = DiffRowKind.SectorHeader;
  text: string = '';
  dump1Block: string = '';
  dump2Block: string = '';
  diffText: string = '';
  diffColor: string = '';
}

/** Diff line for identical blocks (32 dashes). */
const DIFF_TOOL_IDENTICAL_LINE: string =
  '--------------------------------';
/** Empty diff line (32 spaces, "X" at the differing positions). */
const DIFF_TOOL_EMPTY_LINE: string =
  '                                ';

/**
 * Convert the format of a dump (headers marked with "+" and block
 * lines) into a map (sector number -> blocks).
 * Port of DiffTool.convertDumpFormat().
 */
function diffToolConvertDump(lines: string[]): Map<number, string[]> {
  const ret: Map<number, string[]> = new Map<number, string[]>();
  let sector: number = 0;
  let i: number = 0;
  for (let l = 0; l < lines.length; l++) {
    const line: string = lines[l];
    if (line.startsWith('+')) {
      // Line is a header.
      const parts: string[] = line.split(': ');
      sector = parseInt(parts[parts.length - 1], 10);
      i = 0;
      if (sector < 32) {
        ret.set(sector, new Array<string>(4).fill(''));
      } else {
        ret.set(sector, new Array<string>(16).fill(''));
      }
    } else {
      // Line is a block.
      const blocks: string[] | undefined = ret.get(sector);
      if (blocks !== undefined && i < blocks.length) {
        blocks[i] = line;
        i++;
      }
    }
  }
  return ret;
}

/**
 * Compare two dumps and get a list of all indices where they differ
 * from each other (sector -> per block list of diff indices).
 * Port of MCDiffUtils.diffIndices(). An empty block list means the
 * sector exists only in dump 1. A list with a single (empty) entry
 * means the sector exists only in dump 2.
 */
function diffToolDiffIndices(dump1: Map<number, string[]>,
  dump2: Map<number, string[]>): Map<number, number[][]> {
  const ret: Map<number, number[][]> = new Map<number, number[][]>();
  // Walk through all sectors of dump 1.
  const sectors1: number[] = Array.from(dump1.keys());
  for (let i = 0; i < sectors1.length; i++) {
    const sectorNr: number = sectors1[i];
    const sector1: string[] | undefined = dump1.get(sectorNr);
    if (sector1 === undefined) {
      continue;
    }
    const sector2: string[] | undefined = dump2.get(sectorNr);
    if (sector2 === undefined) {
      // Sector exists only in dump 1.
      ret.set(sectorNr, []);
      continue;
    }
    // Check the blocks.
    const diffSector: number[][] = [];
    for (let j = 0; j < sector1.length; j++) {
      const diffIndicesArr: number[] = [];
      const block1: string = sector1[j];
      const block2: string = j < sector2.length ? sector2[j] : '';
      // Walk through all symbols.
      for (let k = 0; k < block1.length; k++) {
        if (k >= block2.length || block1.charAt(k) !== block2.charAt(k)) {
          // Found a different symbol at index k.
          diffIndicesArr.push(k);
        }
      }
      diffSector.push(diffIndicesArr);
    }
    ret.set(sectorNr, diffSector);
  }
  // Are there sectors that occur only in dump 2?
  const sectors2: number[] = Array.from(dump2.keys());
  for (let i = 0; i < sectors2.length; i++) {
    const sectorNr: number = sectors2[i];
    if (dump1.get(sectorNr) === undefined) {
      // Sector exists only in dump 2.
      ret.set(sectorNr, [[]]);
    }
  }
  return ret;
}

@Component
struct DiffToolPage {
  @State diffRows: DiffRowInfo[] = [];
  @State percentageText: string = '';
  @State hideIdentical: boolean = false;
  @State showDiff: boolean = false;
  @State isReading: boolean = false;
  @State statusText: string = '';
  @State dump2Label: string = '当前标签';
  private pathStack: NavPathStack = new NavPathStack();
  /** Dump 1 (from the editor). */
  private dump1: Map<number, string[]> | null = null;
  /** Dump 2 (read from the current tag). */
  private dump2: Map<number, string[]> | null = null;
  private pageAlive: boolean = true;

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
  }

  // ---------------- Tag reading (dump 2) ----------------

  /**
   * Check whether a tag is present, connect to it and read it as
   * dump 2 (adaptation of the Android dump 2 file selection).
   */
  private readTagDump(): void {
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      // There is no tag (checkForTagAndCreateReader already
      // showed an error toast).
      this.dump2 = null;
      this.dump2Label = '当前标签';
      this.statusText = '未找到 MIFARE Classic 标签。\n'
        + '请重新触碰标签以与该转储进行对比。';
      this.runDiff();
      return;
    }
    this.readTagDumpAsync(reader);
  }

  private async readTagDumpAsync(reader: McReader): Promise<void> {
    this.isReading = true;
    // Read as much as possible with the current key map.
    const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
    let rawDump: Map<number, string[]> | null = null;
    if (keyMap !== null) {
      rawDump = await reader.readAsMuchAsPossible(keyMap);
    }
    reader.close();
    if (!this.pageAlive) {
      return;
    }
    this.isReading = false;
    if (keyMap === null) {
      // There is no key map (e.g. the dump was opened from a file
      // and no tag was read before).
      this.dump2 = null;
      this.dump2Label = '当前标签';
      this.statusText = '没有密钥映射。\n'
        + '请先读取标签以生成密钥映射。';
    } else if (rawDump === null) {
      // Tag was removed during reading.
      this.dump2 = null;
      this.dump2Label = '当前标签';
      this.statusText = '错误：读取过程中标签被移除。\n'
        + '请重新触碰标签后重试。';
    } else {
      this.dump2 = rawDump;
      const uid: number[] | null = NfcService.getUID();
      if (uid !== null) {
        this.dump2Label = '标签（UID：' + HexUtils.bytes2Hex(uid) + '）';
      } else {
        this.dump2Label = '当前标签';
      }
      this.statusText = '';
    }
    this.runDiff();
  }

  // ---------------- Diff ----------------

  /**
   * Run the diff if both dumps are there and show the result in the
   * GUI (runDiff of the Android DiffTool).
   */
  private runDiff(): void {
    const rows: DiffRowInfo[] = [];
    this.showDiff = this.dump1 !== null && this.dump2 !== null;
    if (this.dump1 === null || this.dump2 === null) {
      this.diffRows = rows;
      return;
    }
    const dump1: Map<number, string[]> = this.dump1;
    const dump2: Map<number, string[]> = this.dump2;
    const diff: Map<number, number[][]> = diffToolDiffIndices(dump1, dump2);

    // Count the difference between the dumps.
    let totalLength: number = 0;
    let diffLength: number = 0;

    // Walk through all possible sectors (this way the right
    // order will be guaranteed).
    for (let sector = 0; sector < 40; sector++) {
      const blocks: number[][] | undefined = diff.get(sector);
      if (blocks === undefined) {
        // No such sector.
        continue;
      }
      const sector1: string[] | undefined = dump1.get(sector);
      const sector2: string[] | undefined = dump2.get(sector);

      // A sector that exists only in one dump is counted
      // as differences.
      if (blocks.length === 0 || blocks.length === 1) {
        const bs: string[] | undefined =
          blocks.length === 0 ? sector1 : sector2;
        if (bs !== undefined) {
          for (let b = 0; b < bs.length; b++) {
            totalLength += bs[b].length;
            diffLength += bs[b].length;
          }
        }
      }

      // If the "Hide identical sectors" option is checked,
      // do not display identical sectors.
      if (this.hideIdentical && blocks.length > 1) {
        let identical: boolean = true;
        for (let block = 0; block < blocks.length; block++) {
          if (blocks[block].length !== 0) {
            identical = false;
            break;
          }
        }
        if (identical) {
          // Identical sector.
          if (sector1 !== undefined) {
            for (let b = 0; b < sector1.length; b++) {
              totalLength += sector1[b].length;
            }
          }
          continue;
        }
      }

      // Add sector header.
      const headerRow = new DiffRowInfo();
      headerRow.kind = DiffRowKind.SectorHeader;
      headerRow.text = '扇区：' + sector;
      rows.push(headerRow);

      if (blocks.length === 0 || blocks.length === 1) {
        // Sector exists only in one dump.
        const onlyRow = new DiffRowInfo();
        onlyRow.kind = DiffRowKind.OnlyInOneDump;
        if (blocks.length === 0) {
          onlyRow.text = '该扇区仅存在于转储 1 (A) 中';
        } else {
          onlyRow.text = '该扇区仅存在于转储 2 (B) 中';
        }
        rows.push(onlyRow);
        continue;
      }

      // Walk through all blocks.
      if (sector1 === undefined || sector2 === undefined) {
        continue;
      }
      for (let block = 0; block < blocks.length; block++) {
        if (block >= sector1.length || block >= sector2.length) {
          continue;
        }
        const blockRow = new DiffRowInfo();
        blockRow.kind = DiffRowKind.Block;
        blockRow.dump1Block = sector1[block];
        blockRow.dump2Block = sector2[block];
        totalLength += sector1[block].length;
        if (blocks[block].length === 0) {
          // Diff line for identical blocks (green dashes).
          blockRow.diffText = DIFF_TOOL_IDENTICAL_LINE;
          blockRow.diffColor = MctTheme.LIGHT_GREEN;
        } else {
          // Diff line with a red "X" at every position where
          // the dumps differ.
          let diffString: string = DIFF_TOOL_EMPTY_LINE;
          for (let i = 0; i < blocks[block].length; i++) {
            const pos: number = blocks[block][i];
            if (pos >= 0 && pos < diffString.length) {
              diffString = diffString.substring(0, pos) + 'X'
                + diffString.substring(pos + 1);
            }
            // Count the differences.
            diffLength++;
          }
          blockRow.diffText = diffString;
          blockRow.diffColor = MctTheme.RED;
        }
        rows.push(blockRow);
      }
    }

    // Show the difference percentage between the two dumps.
    const percentage: number = totalLength > 0
      ? diffLength / totalLength * 100 : 0;
    this.percentageText = '转储差异：'
      + percentage.toFixed(2) + ' %';
    this.diffRows = rows;
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // Dump 1 source info (label + "Dump from Editor").
        Row() {
          Text('转储 1 (A)')
            .fontSize(18)
            .fontColor(MctTheme.fg)
          Text('来自编辑器的转储')
            .fontSize(14)
            .fontColor(MctTheme.fgSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // Dump 2 source info (label + tag UID).
        Row() {
          Text('转储 2 (B)')
            .fontSize(18)
            .fontColor(MctTheme.fg)
          Text(this.dump2Label)
            .fontSize(14)
            .fontColor(MctTheme.fgSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 4 })

        // Hide identical sectors option.
        Row() {
          Checkbox()
            .select(this.hideIdentical)
            .selectedColor(MctTheme.accent)
            .width(20)
            .height(20)
            .onChange((value: boolean): void => {
              this.hideIdentical = value;
              this.runDiff();
            })
          Text('隐藏相同扇区')
            .fontSize(18)
            .fontColor(MctTheme.fg)
            .margin({ left: 8 })
            .onClick(() => {
              this.hideIdentical = !this.hideIdentical;
              this.runDiff();
            })
        }
        .width('100%')
        .padding({ top: 5, bottom: 5 })
        .alignItems(VerticalAlign.Center)

        // Separator.
        Divider()
          .color(MctTheme.LIGHT_GRAY)
          .strokeWidth(2)
          .margin({ top: 5, bottom: 5 })

        // Diff content.
        Scroll() {
          Column() {
            if (this.showDiff) {
              // Difference between the dumps (percentage).
              Text(this.percentageText)
                .fontSize(14)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding({ top: 10 })
              ForEach(this.diffRows,
                (row: DiffRowInfo, index: number): void => {
                  if (row.kind === DiffRowKind.SectorHeader) {
                    // Sector header.
                    Text(row.text)
                      .fontSize(18)
                      .fontColor(MctTheme.accent)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                      .padding({ top: 20 })
                  } else if (row.kind === DiffRowKind.OnlyInOneDump) {
                    // Sector exists only in one dump.
                    Text(row.text)
                      .fontSize(14)
                      .fontColor(MctTheme.fg)
                      .width('100%')
                      .textAlign(TextAlign.Start)
                  } else {
                    // Block diff entry (list_item_diff_block.xml):
                    // "A:" + dump 1 data, diff line, "B:" + dump 2 data.
                    Column() {
                      Row() {
                        Text('A:')
                          .fontSize(14)
                          .fontColor(MctTheme.fg)
                          .width(22)
                        Text(row.dump1Block)
                          .fontSize(14)
                          .fontColor(MctTheme.fg)
                          .fontFamily('monospace')
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Center)

                      // Diff line ("X" at differing positions or
                      // green dashes for identical blocks).
                      Text(row.diffText)
                        .fontSize(14)
                        .fontColor(row.diffColor)
                        .fontFamily('monospace')
                        .width('100%')
                        .textAlign(TextAlign.Start)
                        .margin({ left: 22 })

                      Row() {
                        Text('B:')
                          .fontSize(14)
                          .fontColor(MctTheme.fg)
                          .width(22)
                        Text(row.dump2Block)
                          .fontSize(14)
                          .fontColor(MctTheme.fg)
                          .fontFamily('monospace')
                      }
                      .width('100%')
                      .alignItems(VerticalAlign.Center)

                      // Separator.
                      Divider()
                        .color(MctTheme.LIGHT_GRAY)
                        .strokeWidth(1)
                        .margin({ top: 3, bottom: 3 })
                    }
                    .width('100%')
                  }
                },
                (row: DiffRowInfo, index: number): string => index.toString())
            } else {
              if (this.isReading) {
                // Reading the tag (dump 2).
                Column() {
                  Text('正在读取标签…\n（请勿移除标签）')
                    .fontSize(16)
                    .fontColor(MctTheme.fg)
                    .textAlign(TextAlign.Center)
                  LoadingProgress()
                    .width(48)
                    .height(48)
                    .color(MctTheme.accent)
                    .margin({ top: 12 })
                }
                .width('100%')
                .padding({ top: 40 })
                .alignItems(HorizontalAlign.Center)
              } else {
                // No diff possible (no tag, no key map, tag lost).
                Text(this.statusText)
                  .fontSize(16)
                  .fontColor(MctTheme.fg)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .padding({ top: 40 })
              }
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
      .padding(5)
    }
    .title('差异对比工具')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: DiffToolParams =
        (ctx.pathInfo.param as DiffToolParams) ?? new DiffToolParams();
      // Dump 1: the dump from the editor (Android EXTRA_DUMP).
      this.dump1 = diffToolConvertDump(p.dump);
      // Read dump 2 from the current tag.
      this.readTagDump();
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener. A newly discovered tag
      // replaces dump 2 (live update of the diff).
      NfcService.setTagListener(
        (tagInfo: tag.TagInfo, supportResult: number): void => {
          if (supportResult !== 0) {
            // Device or tag does not support MIFARE Classic.
            // Run the only thing that is possible: the tag info tool.
            this.pathStack.pushPathByName('tagInfoTool', null);
            return;
          }
          this.readTagDump();
        });
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function DiffToolBuilder() {
  DiffToolPage()
}
