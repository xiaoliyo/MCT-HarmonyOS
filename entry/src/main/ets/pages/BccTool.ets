/**
 * BCC tool (port of de.syss.MifareClassicTool.Activities.BccTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Calculate the BCC value of a given UID (part). The BCC is the XOR
 * of all 4 UID bytes. In contrast to Android (where the calculation
 * is triggered by the "Calculate BCC" button only) the BCC is
 * additionally calculated live while typing, as soon as the UID
 * input is complete (8 hex characters).
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

@Component
struct BccToolPage {
  @State uidText: string = '';
  @State bccText: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Calculate ----------------

  /**
   * Calculate the BCC value of the given UID (part). This is done
   * via HexUtils.calcBcc after some input checks (is the length of
   * the given UID valid; are there only hex symbols)
   * (Android: onCalculate).
   */
  private onCalculate(): void {
    const data: string = this.uidText;
    if (data.length !== 8) {
      // Error. UID (parts) are 4 bytes long.
      NfcService.toast('错误：UID 长度无效', true);
      return;
    }
    if (!/^[0-9A-Fa-f]+$/.test(data)) {
      // Error. Not hex.
      NfcService.toast(
        '错误：数据必须为十六进制（0-9 和 A-F）', true);
      return;
    }
    // Calculate the BCC.
    const uid: number[] | null = HexUtils.hex2Bytes(data);
    if (uid === null) {
      // Error. Not hex.
      NfcService.toast(
        '错误：数据必须为十六进制（0-9 和 A-F）', true);
      return;
    }
    const bcc: number = HexUtils.calcBcc(uid);
    let hex: string = bcc.toString(16).toUpperCase();
    if (hex.length < 2) {
      hex = '0' + hex;
    }
    this.bccText = hex;
  }

  // ---------------- Clipboard ----------------

  /**
   * Copy the calculated BCC to the clipboard
   * (Android: onCopyToClipboard).
   */
  private onCopyToClipboard(): void {
    NfcService.copyToClipboard(this.bccText, true);
  }

  /**
   * Paste the content of the clipboard (if plain text) to the
   * UID input (Android: onPasteFromClipboard).
   */
  private onPasteFromClipboard(): void {
    const text: string | null = NfcService.getFromClipboard();
    if (text !== null) {
      // The input field is limited to 8 characters
      // (like the Android EditText maxLength).
      this.uidText = text.substring(0, 8);
      if (this.uidText.length === 8) {
        // Live calculation (Android requires the
        // "Calculate BCC" button).
        this.onCalculate();
      }
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // UID (part) input (+ paste).
        Row() {
          Text('UID（部分）')
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .width(96)
          TextInput({ text: this.uidText, placeholder: '十六进制，4 字节' })
            .maxLength(8)
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .placeholderColor(MctTheme.fgSecondary)
            .placeholderFont({ size: 14 })
            .backgroundColor(MctTheme.inputBg)
            .borderRadius(4)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.uidText = value;
              if (value.length === 8) {
                // Live calculation (Android requires the
                // "Calculate BCC" button).
                this.onCalculate();
              }
            })
          Button() {
            Image($r('app.media.paste'))
              .width(20)
              .height(20)
          }
          .width(40)
          .height(36)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ left: 4 })
          .onClick(() => {
            this.onPasteFromClipboard();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding(5)

        Button() {
          Column({ space: 2 }) {
            Image($r('app.media.arrow_down'))
              .width(22)
              .height(22)
            Text('计算 BCC')
              .fontSize(15)
              .fontColor(MctTheme.fg)
          }
        }
          .width('100%')
          .height(56)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ top: 5, bottom: 5 })
          .onClick(() => {
            this.onCalculate();
          })

        // BCC output (+ copy).
        Row() {
          Text('BCC')
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .width(96)
          Text(this.bccText)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.inputBg)
            .borderRadius(4)
            .padding({ left: 8, right: 8, top: 12, bottom: 12 })
            .layoutWeight(1)
            .copyOption(CopyOptions.LocalDevice)
          Button() {
            Image($r('app.media.copy'))
              .width(20)
              .height(20)
          }
          .width(40)
          .height(36)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ left: 4 })
          .onClick(() => {
            this.onCopyToClipboard();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding(5)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('BCC 计算器')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
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
export function BccToolBuilder() {
  BccToolPage()
}
