/**
 * Hex to ASCII (port of de.syss.MifareClassicTool.Activities.HexToAscii,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Display a (hex) dump as US-ASCII. This page will be shown from the
 * DumpEditor, if the user clicks the corresponding menu item. Non
 * printable ASCII characters will be displayed as ".". Lines that
 * are not valid hex data are displayed as "--Invalid Data--".
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

/** Route params: the dump (block lines) to display as ASCII. */
export class HexToAsciiParams {
  dump: string[] = [];
}

/** One line of the ASCII output (sector header or converted block data). */
class HexToAsciiLine {
  id: string = '';
  text: string = '';
  isSectorHeader: boolean = false;

  constructor(id: string, text: string, isSectorHeader: boolean) {
    this.id = id;
    this.text = text;
    this.isSectorHeader = isSectorHeader;
  }
}

/**
 * Convert a dump (hex block lines with optional "+Sector: N" headers)
 * into the ASCII display lines (Android: HexToAscii.onCreate).
 */
function buildAsciiLines(dump: string[]): HexToAsciiLine[] {
  const lines: HexToAsciiLine[] = [];
  for (let i = 0; i < dump.length; i++) {
    const line: string = dump[i];
    if (line.startsWith('+')) {
      // Header.
      let sectorNumber: string = '';
      const parts: string[] = line.split(': ');
      if (parts.length === 2) {
        sectorNumber = parts[1];
      }
      lines.push(new HexToAsciiLine(
        'line_' + i.toString(), '扇区：' + sectorNumber, true));
    } else {
      // Data.
      const converted: string | null = HexUtils.hex2Ascii(line);
      if (converted === null) {
        lines.push(new HexToAsciiLine(
          'line_' + i.toString(), '--无效数据--', false));
      } else {
        lines.push(new HexToAsciiLine(
          'line_' + i.toString(), ' ' + converted, false));
      }
    }
  }
  return lines;
}

@Component
struct HexToAsciiPage {
  @State asciiLines: HexToAsciiLine[] = [];
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            ForEach(this.asciiLines, (line: HexToAsciiLine) => {
              if (line.isSectorHeader) {
                // Sector header (accent color, like the Android
                // colorString with the theme accent color).
                Text(line.text)
                  .fontFamily('monospace')
                  .fontSize(18)
                  .fontColor(MctTheme.accent)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              } else {
                // Block data (converted to US-ASCII).
                Text(line.text)
                  .fontFamily('monospace')
                  .fontSize(18)
                  .fontColor(MctTheme.fg)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              }
            }, (line: HexToAsciiLine): string => line.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(5)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('数据（ASCII）')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params: HexToAsciiParams =
        (ctx.pathInfo.param as HexToAsciiParams) ?? new HexToAsciiParams();
      this.asciiLines = buildAsciiLines(params.dump);
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener. If the (new) tag does not
      // support MIFARE Classic, show the tag info tool
      // (Android: BasicActivity.onNewIntent).
      NfcService.setTagListener(
        (tagInfo: tag.TagInfo, supportResult: number): void => {
          if (supportResult === -2) {
            this.pathStack.pushPathByName('tagInfoTool', null);
          }
        });
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function HexToAsciiBuilder() {
  HexToAsciiPage()
}
