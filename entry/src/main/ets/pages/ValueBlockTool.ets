/**
 * Value Block tool (port of de.syss.MifareClassicTool.Activities.ValueBlockTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Decode MIFARE Classic Value Blocks from their hex format to an
 * integer (and the Addr value) and vice versa. A value block has the
 * format V|~V|V|addr|~addr|addr|~addr (16 bytes). In contrast to
 * Android (where the conversion is triggered by the "Decode"/"Encode"
 * buttons only) the conversion additionally runs live while typing,
 * as soon as the corresponding input is complete.
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { MifareUtils } from '../common/MifareUtils';
import { ValueBlockResult } from '../common/MctTypes';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

@Component
struct ValueBlockToolPage {
  @State vbText: string = '';
  @State vbAsIntText: string = '';
  @State addrText: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Decode / Encode ----------------

  /**
   * Decode a MIFARE Classic Value Block into an integer and the
   * Addr value (Android: onDecode).
   */
  private onDecode(): void {
    const data: string = this.vbText;
    // Common.isHexAnd16Byte (including its error toasts).
    if (!HexUtils.isHex(data)) {
      // Error. Not hex.
      NfcService.toast(
        '错误：数据必须为十六进制（0-9 和 A-F）', true);
      return;
    }
    if (data.length !== 32) {
      // Error. Not 16 bytes.
      NfcService.toast(
        '错误：数据必须为 16 字节（32 个字符）', true);
      return;
    }
    if (!MifareUtils.isValueBlock(data)) {
      // Error. No value block.
      NfcService.toast('错误：不是值块。', true);
      return;
    }
    // Decode (bytes -> int, little endian).
    const result: ValueBlockResult | null =
      MifareUtils.decodeValueBlock(HexUtils.hex2Bytes(data));
    if (result === null) {
      // Error. No value block.
      NfcService.toast('错误：不是值块。', true);
      return;
    }
    this.vbAsIntText = result.value.toString();
    this.addrText = data.substring(24, 26);
  }

  /**
   * Encode an integer (and addr.) into a MIFARE Classic Value Block
   * (Android: onEncode).
   */
  private onEncode(): void {
    const vbText: string = this.vbAsIntText;
    const addrText: string = this.addrText;
    if (vbText.length === 0) {
      // Error. There is no integer to encode.
      NfcService.toast('错误：没有可编码的整数', true);
      return;
    }
    if (!/^[0-9A-Fa-f]{2}$/.test(addrText)) {
      // Error. There is no valid value block addr.
      NfcService.toast(
        '错误：地址不是十六进制字节（0-9、A-F，2 个字符）', true);
      return;
    }
    // String -> Int (like Integer.parseInt, with range check).
    if (!/^[+-]?[0-9]+$/.test(vbText)) {
      // Error. Number was more than Integer.MAX_VALUE
      // or less than Integer.MIN_VALUE.
      this.toastInvalidInt();
      return;
    }
    const vbAsInt: number = parseInt(vbText, 10);
    if (vbAsInt > 2147483647 || vbAsInt < -2147483648) {
      // Error. Number was more than Integer.MAX_VALUE
      // or less than Integer.MIN_VALUE.
      this.toastInvalidInt();
      return;
    }
    // Encode (value + addr -> 16 byte value block as hex string).
    const addr: number = parseInt(addrText, 16);
    this.vbText = MifareUtils.encodeValueBlockToHex(vbAsInt, addr);
  }

  /**
   * Show the "not a valid integer" error toast together with the
   * range of a Java integer.
   */
  private toastInvalidInt(): void {
    NfcService.toast(
      '无效整数（最大：2147483647，最小：-2147483648）', true);
  }

  // ---------------- Clipboard ----------------

  /**
   * Copy the MIFARE Classic Value Block to the clipboard
   * (Android: onCopyToClipboard).
   */
  private onCopyToClipboard(): void {
    NfcService.copyToClipboard(this.vbText, true);
  }

  /**
   * Paste the content of the clipboard (if plain text) to the
   * value block input (Android: onPasteFromClipboard).
   */
  private onPasteFromClipboard(): void {
    const text: string | null = NfcService.getFromClipboard();
    if (text !== null) {
      // The input field is limited to 32 characters
      // (like the Android EditText maxLength).
      this.vbText = text.substring(0, 32);
      if (this.vbText.length === 32) {
        // Live conversion (Android requires the "Decode" button).
        this.onDecode();
      }
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // Value block input (+ copy & paste).
        Row() {
          Text('VB')
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .width(64)
          TextInput({ text: this.vbText, placeholder: '十六进制，16 字节（如 0A4F…）' })
            .maxLength(32)
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .placeholderColor(MctTheme.fgSecondary)
            .placeholderFont({ size: 14 })
            .backgroundColor(MctTheme.inputBg)
            .borderRadius(4)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.vbText = value;
              if (value.length === 32) {
                // Live conversion (Android requires the "Decode" button).
                this.onDecode();
              }
            })
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

        // Decode / Encode.
        Row({ space: 10 }) {
          Button() {
            Column({ space: 2 }) {
              Image($r('app.media.arrow_down'))
                .width(20)
                .height(20)
              Text('解码')
                .fontSize(15)
                .fontColor(MctTheme.fg)
            }
          }
          .height(52)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.onDecode();
          })
          Button() {
            Column({ space: 2 }) {
              Image($r('app.media.arrow_up'))
                .width(20)
                .height(20)
              Text('编码')
                .fontSize(15)
                .fontColor(MctTheme.fg)
            }
          }
          .height(52)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.onEncode();
          })
        }
        .width('100%')
        .padding({ left: 5, right: 5 })
        .margin({ top: 10, bottom: 10 })

        // Value block as integer (+ addr).
        Row() {
          Text('值块转整数')
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .width(84)
          TextInput({ text: this.vbAsIntText, placeholder: '如 423' })
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .placeholderColor(MctTheme.fgSecondary)
            .placeholderFont({ size: 14 })
            .backgroundColor(MctTheme.inputBg)
            .borderRadius(4)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.vbAsIntText = value;
              if (value.length > 0 && this.addrText.length === 2) {
                // Live conversion (Android requires the "Encode" button).
                this.onEncode();
              }
            })
          Text('地址')
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .width(44)
            .margin({ left: 12 })
          TextInput({ text: this.addrText, placeholder: '00' })
            .maxLength(2)
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .placeholderColor(MctTheme.fgSecondary)
            .placeholderFont({ size: 14 })
            .backgroundColor(MctTheme.inputBg)
            .borderRadius(4)
            .width(56)
            .onChange((value: string): void => {
              this.addrText = value;
              if (value.length === 2 && this.vbAsIntText.length > 0) {
                // Live conversion (Android requires the "Encode" button).
                this.onEncode();
              }
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
    .title('值块解码与编码器')
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
export function ValueBlockToolBuilder() {
  ValueBlockToolPage()
}
