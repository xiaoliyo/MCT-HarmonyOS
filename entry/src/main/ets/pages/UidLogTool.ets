/**
 * UID Log tool (port of de.syss.MifareClassicTool.Activities.UidLogTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Tool to display and share the UIDs of previously detected tags.
 * The log is displayed in reverse order (newest first) and can be
 * shared or cleared via the menu.
 */

import { tag } from '@kit.ConnectivityKit';
import { MctFiles } from '../common/MctFiles';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

@Component
struct UidLogToolPage {
  @State uidLogText: string = 'UID 日志为空';
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
    this.updateUidLog();
  }

  // ---------------- UID log ----------------

  /**
   * Read the UID log file and display its content.
   */
  private updateUidLog(): void {
    const logEntries: string[] | null = MctFiles.readUidLog();
    if (logEntries !== null) {
      // Reverse order (newest top).
      const reversedEntries: string[] = logEntries.slice().reverse();
      this.uidLogText = reversedEntries.join('\n');
    } else {
      // No log yet.
      this.uidLogText = 'UID 日志为空';
    }
  }

  /**
   * Delete the UID log file and update the UI (call updateUidLog()).
   */
  private clearUidLog(): void {
    MctFiles.clearUidLog();
    this.updateUidLog();
  }

  /**
   * Share the UID log file as text file.
   */
  private shareUidLog(): void {
    const logPath: string = MctFiles.getFile(MctFiles.UID_LOG_FILE);
    if (MctFiles.exists(logPath)) {
      NfcService.shareTextFile(logPath);
    }
  }

  // ---------------- Menus ----------------

  @Builder
  uidLogMenuTrigger() {
    Text('⋮')
      .fontSize(22)
      .fontColor(MctTheme.fg)
      .padding({ left: 12, right: 6, top: 6, bottom: 6 })
      .bindMenu(this.uidLogMenuBuilder)
  }

  @Builder
  uidLogMenuBuilder() {
    Menu() {
      MenuItem({ content: '分享' })
        .onClick(() => {
          this.shareUidLog();
        })
      MenuItem({ content: '清空日志' })
        .onClick(() => {
          this.clearUidLog();
        })
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Text(this.uidLogText)
            .fontFamily('monospace')
            .fontSize(14)
            .fontColor(MctTheme.fg)
            .width('100%')
            .textAlign(TextAlign.Start)
            .copyOption(CopyOptions.LocalDevice)
        }
        .width('100%')
        .layoutWeight(1)
        .padding(5)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('UID 日志')
    .backgroundColor(MctTheme.bg)
    .menus(this.uidLogMenuTrigger)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .onShown(() => {
      MctTheme.refresh();
      this.updateUidLog();
      // (Re)register the tag listener. A newly discovered tag
      // adds a new UID to the log (Android: onNewIntent).
      NfcService.setTagListener(
        (tagInfo: tag.TagInfo, supportResult: number): void => {
          this.updateUidLog();
        });
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function UidLogToolBuilder() {
  UidLogToolPage()
}
