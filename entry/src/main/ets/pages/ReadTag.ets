/**
 * Create a key map with the key map creator and then read the tag
 * (port of de.syss.MifareClassicTool.Activities.ReadTag,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * This page is pushed via pushPathByName('readTag'). It immediately
 * shows the key map creator and, if the key mapping process was
 * successful, reads the tag and displays the created dump in the
 * dump editor.
 */

import { tag } from '@kit.ConnectivityKit';
import { McReader } from '../common/McReader';
import { MctFiles } from '../common/MctFiles';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { SectorKeys } from '../common/MctTypes';
import { DumpEditorParams } from './DumpEditor';
import { KeyMapCreatorParams } from './KeyMapCreator';

/** AppStorage key used by the key map creator to pass its result code. */
const READ_TAG_KEY_MAP_RESULT_KEY: string = 'mct.keyMapCreatorResult';
/** Sentinel value meaning "no result yet". */
const READ_TAG_NO_RESULT: number = 100;
// Android activity result codes (see KeyMapCreator.ets).
const READ_TAG_RESULT_OK: number = -1;
const READ_TAG_RESULT_NULL_PATH: number = 4;

@Component
struct ReadTagPage {
  private pathStack: NavPathStack = new NavPathStack();
  private rawDump: Map<number, string[]> | null = null;
  private keyMapCreatorLaunched: boolean = false;
  private pageAlive: boolean = true;

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
  }

  // ---------------- Key map creator (Android onCreate) ----------------

  /**
   * Show the key map creator (Android onCreate() with
   * startActivityForResult()).
   */
  private showKeyMapCreator(): void {
    if (this.keyMapCreatorLaunched) {
      return;
    }
    this.keyMapCreatorLaunched = true;
    const params: KeyMapCreatorParams = new KeyMapCreatorParams();
    params.keysDir = MctFiles.getKeysDir();
    params.buttonText = '开始映射密钥并读取标签';
    this.pathStack.pushPathByName('keyMapCreator', params);
  }

  /**
   * Check the result code of the key mapping process. If the process
   * was successful, the tag will be read
   * (Android onActivityResult()).
   */
  private checkKeyMapCreatorResult(): void {
    const result: number =
      AppStorage.get<number>(READ_TAG_KEY_MAP_RESULT_KEY)
      ?? READ_TAG_NO_RESULT;
    if (result === READ_TAG_NO_RESULT) {
      // The key map creator was just launched
      // (or its result was already consumed).
      return;
    }
    // Consume the result.
    AppStorage.setOrCreate(READ_TAG_KEY_MAP_RESULT_KEY, READ_TAG_NO_RESULT);
    if (result === READ_TAG_RESULT_OK) {
      // Read tag.
      this.readTag();
      return;
    }
    if (result === READ_TAG_RESULT_NULL_PATH) {
      // Error. Path from the calling intent was null.
      // (This is really strange and should not occur.)
      NfcService.toast('错误：发生了一个奇怪的错误……我不知道为什么 :('
        + '\n请通过项目页面报告此问题', true);
    }
    if (this.pageAlive) {
      this.pathStack.pop();
    }
  }

  // ---------------- Read tag ----------------

  /**
   * Read as much as possible from the tag and then create the tag
   * dump (Android readTag()).
   */
  private readTag(): void {
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return;
    }
    this.readTagAsync(reader);
  }

  private async readTagAsync(reader: McReader): Promise<void> {
    // Get key map from global variable.
    const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
    this.rawDump = null;
    if (keyMap !== null) {
      this.rawDump = await reader.readAsMuchAsPossible(keyMap);
    }
    reader.close();
    this.createTagDump(this.rawDump);
  }

  /**
   * Create a tag dump in a format the dump editor can read (format:
   * headers (sectors) marked with "+", errors marked with "*"), and
   * then start the dump editor with this dump
   * (Android createTagDump()).
   */
  private createTagDump(rawDump: Map<number, string[]> | null): void {
    if (rawDump !== null) {
      if (rawDump.size !== 0) {
        const tmpDump: string[] = [];
        for (let i = NfcService.getKeyMapRangeFrom();
          i <= NfcService.getKeyMapRangeTo(); i++) {
          const val: string[] | undefined = rawDump.get(i);
          // Mark headers (sectors) with "+".
          tmpDump.push('+Sector: ' + i);
          if (val !== undefined) {
            for (let j = 0; j < val.length; j++) {
              tmpDump.push(val[j]);
            }
          } else {
            // Mark sector as not readable ("*").
            tmpDump.push('*未找到密钥或扇区已损坏');
          }
        }
        // Show dump editor.
        const params: DumpEditorParams = new DumpEditorParams();
        params.dump = tmpDump;
        if (this.pageAlive) {
          this.pathStack.pushPathByName('dumpEditor', params);
          this.pathStack.removeByName('readTag');
        }
        return;
      }
      // Error. Keys from key map are not valid for reading.
      NfcService.toast('错误：没有可用于读取的有效密钥', true);
    } else {
      NfcService.toast('错误：读取过程中标签被移除', true);
    }
    if (this.pageAlive) {
      this.pathStack.pop();
    }
  }

  build() {
    NavDestination() {
      Column() {
        Text('正在读取标签…\n（请勿移除标签）')
          .fontSize(20)
          .fontColor(MctTheme.fg)
          .textAlign(TextAlign.Center)
        LoadingProgress()
          .width(56)
          .height(56)
          .color(MctTheme.accent)
          .margin({ top: 16 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(MctTheme.bg)
    }
    .title('读取标签')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      // Reset the key map creator result and show the key map creator
      // (Android onCreate()).
      AppStorage.setOrCreate(READ_TAG_KEY_MAP_RESULT_KEY, READ_TAG_NO_RESULT);
      this.showKeyMapCreator();
    })
    .onShown(() => {
      // Android onResume (BasicActivity): enable NFC foreground dispatch.
      NfcService.setTagListener((tagInfo: tag.TagInfo, supportResult: number): void => {
        if (supportResult !== 0) {
          // Device or tag does not support MIFARE Classic.
          // Run the only thing that is possible: the tag info tool.
          this.pathStack.pushPathByName('tagInfoTool', null);
        }
      });
      this.checkKeyMapCreatorResult();
    })
    .onHidden(() => {
      // Android onPause (BasicActivity): disable NFC foreground dispatch.
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function ReadTagBuilder() {
  ReadTagPage()
}
