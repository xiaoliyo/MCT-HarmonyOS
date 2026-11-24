/**
 * Data Conversion Tool (port of
 * de.syss.MifareClassicTool.Activities.DataConversionTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Convert data from formats like ASCII/hex/bin/dec to each other.
 * Pressing the convert button of an input field converts its content
 * into all the other formats. Additionally, some online converters
 * can be opened (with the hex data as input, if supported).
 */

import { tag } from '@kit.ConnectivityKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { HexUtils } from '../common/HexUtils';
import { MctApp } from '../common/MctApp';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

@Component
struct DataConversionToolPage {
  @State hexText: string = '';
  @State asciiText: string = '';
  @State binText: string = '';
  @State decBEText: string = '';
  @State decLEText: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Convert ----------------

  /**
   * Convert the data from the ASCII input to a hex string and update
   * all other input fields (convertData).
   */
  private onConvertAscii(): void {
    this.convertData(HexUtils.ascii2Hex(this.asciiText));
  }

  /**
   * Convert the data from the hex input to all other formats.
   * Shows an error toast if the data is not hexadecimal.
   */
  private onConvertHex(): void {
    const hex: string = this.hexText;
    if (HexUtils.isHex(hex)) {
      this.convertData(hex);
    } else {
      // Error. Not hex.
      NfcService.toast(
        '错误：数据必须为十六进制（0-9 和 A-F）', true);
    }
  }

  /**
   * Convert the data from the binary input to all other formats.
   * Shows an error toast if the data is not binary.
   */
  private onConvertBin(): void {
    const bin: string = this.binText;
    if (this.isBin(bin)) {
      const hex: string | null = HexUtils.bin2Hex(bin);
      if (hex !== null) {
        this.convertData(hex);
      }
    }
  }

  /**
   * Convert the data from the decimal (big endian) input to all other
   * formats. Shows an error toast if the data is not decimal.
   */
  private onConvertDecBE(): void {
    const dec: string = this.decBEText;
    if (this.isDec(dec)) {
      const hex: string | null = HexUtils.decBE2Hex(dec);
      if (hex !== null) {
        this.convertData(hex);
      }
    }
  }

  /**
   * Convert the data from the decimal (little endian) input to all
   * other formats. Shows an error toast if the data is not decimal.
   */
  private onConvertDecLE(): void {
    const dec: string = this.decLEText;
    if (this.isDec(dec)) {
      const hex: string | null = HexUtils.decLE2Hex(dec);
      if (hex !== null) {
        this.convertData(hex);
      }
    }
  }

  /**
   * Convert the data from a hex string to different output formats
   * and update the corresponding input fields.
   */
  private convertData(hex: string): void {
    if (hex.length === 0) {
      // Error. Could not convert.
      NfcService.toast('错误：无法转换', false);
      return;
    }
    // Hex.
    this.hexText = hex.toUpperCase();
    // ASCII.
    const ascii: string | null = HexUtils.hex2Ascii(hex);
    if (ascii !== null) {
      this.asciiText = ascii;
    } else {
      this.asciiText = '非 ASCII';
    }
    // Bin.
    const bin: string | null = HexUtils.hex2Bin(hex);
    if (bin !== null) {
      this.binText = bin;
    } else {
      this.binText = '';
    }
    // Dec (BE).
    this.decBEText = HexUtils.hex2DecBE(hex);
    // Dec (LE).
    this.decLEText = HexUtils.hex2DecLE(hex);
  }

  /**
   * Check if a string represents binary bytes (0/1, multiple of 8).
   * Shows an error toast if not.
   */
  private isBin(bin: string): boolean {
    if (bin.length % 8 === 0 && /^[0-1]+$/.test(bin)) {
      return true;
    }
    NfcService.toast(
      '错误：数据必须为二进制（0/1，8 的倍数）', true);
    return false;
  }

  /**
   * Check if a string represents a decimal number.
   * Shows an error toast if not.
   */
  private isDec(dec: string): boolean {
    if (dec.length === 0 || !/^\d+$/.test(dec)) {
      NfcService.toast('错误：数据必须为十进制（0-9）', true);
      return false;
    }
    return true;
  }

  // ---------------- Online converter ----------------

  /**
   * Open a generic online type converter with the input from the hex
   * field. https://hexconverter.scadacore.com/
   */
  private onOpenGenericConverter(): void {
    const hex: string = this.hexText;
    if (hex.length > 0 && !HexUtils.isHex(hex)) {
      // Error. Not hex.
      NfcService.toast(
        '错误：数据必须为十六进制（0-9 和 A-F）', true);
      return;
    }
    const url: string = 'https://hexconverter.scadacore.com/?HexString='
      + hex;
    this.openUrl(url);
  }

  /**
   * Open a multi-purpose online format converter.
   * https://cryptii.com/pipes/integer-encoder
   */
  private onOpenMultiPurposeConverter(): void {
    const url: string = 'https://cryptii.com/pipes/integer-encoder';
    this.openUrl(url);
  }

  /**
   * Open the CyberChef website with the input from the hex field.
   * https://github.com/gchq/CyberChef/
   */
  private onOpenCyberChef(): void {
    const hex: string = this.hexText;
    if (hex.length > 0 && !HexUtils.isHex(hex)) {
      // Error. Not hex.
      NfcService.toast(
        '错误：数据必须为十六进制（0-9 和 A-F）', true);
      return;
    }
    // Base64 of the hex string (without padding, like Android).
    const hexBytes: Uint8Array = new Uint8Array(hex.length);
    for (let i = 0; i < hex.length; i++) {
      hexBytes[i] = hex.charCodeAt(i) & 0xFF;
    }
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    let base64: string = base64Helper.encodeToStringSync(hexBytes);
    base64 = base64.trim();
    base64 = base64.split('=').join('');
    const url: string =
      "https://gchq.github.io/CyberChef/#recipe=From_Hex('Auto')&input="
      + base64;
    this.openUrl(url);
  }

  /**
   * Open an URL with the browser (Android: Intent.ACTION_VIEW).
   */
  private openUrl(url: string): void {
    MctApp.getContext().openLink(url)
      .catch((error: BusinessError): void => {
        NfcService.toast('错误：无法打开链接', false);
      });
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // Hex.
            Row() {
              Text('Hex')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width(96)
                .textAlign(TextAlign.End)
                .margin({ right: 5 })
              TextInput({ text: this.hexText })
                .fontSize(14)
                .fontFamily('monospace')
                .fontColor(MctTheme.fg)
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .layoutWeight(1)
                .onChange((value: string): void => {
                  this.hexText = value;
                })
              Button('转换')
                .fontSize(12)
                .height(34)
                .padding({ left: 10, right: 10 })
                .fontColor(MctTheme.fg)
                .backgroundColor(MctTheme.buttonBg)
                .borderRadius(4)
                .margin({ left: 4 })
                .onClick(() => {
                  this.onConvertHex();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })

            // ASCII.
            Row() {
              Text('ASCII')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width(96)
                .textAlign(TextAlign.End)
                .margin({ right: 5 })
              TextInput({ text: this.asciiText })
                .fontSize(14)
                .fontFamily('monospace')
                .fontColor(MctTheme.fg)
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .layoutWeight(1)
                .onChange((value: string): void => {
                  this.asciiText = value;
                })
              Button('转换')
                .fontSize(12)
                .height(34)
                .padding({ left: 10, right: 10 })
                .fontColor(MctTheme.fg)
                .backgroundColor(MctTheme.buttonBg)
                .borderRadius(4)
                .margin({ left: 4 })
                .onClick(() => {
                  this.onConvertAscii();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })

            // Bin.
            Row() {
              Text('Bin')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width(96)
                .textAlign(TextAlign.End)
                .margin({ right: 5 })
              TextInput({ text: this.binText })
                .type(InputType.Number)
                .fontSize(14)
                .fontFamily('monospace')
                .fontColor(MctTheme.fg)
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .layoutWeight(1)
                .onChange((value: string): void => {
                  this.binText = value;
                })
              Button('转换')
                .fontSize(12)
                .height(34)
                .padding({ left: 10, right: 10 })
                .fontColor(MctTheme.fg)
                .backgroundColor(MctTheme.buttonBg)
                .borderRadius(4)
                .margin({ left: 4 })
                .onClick(() => {
                  this.onConvertBin();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })

            // Dec (BE).
            Row() {
              Text('Dec (BE)')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width(96)
                .textAlign(TextAlign.End)
                .margin({ right: 5 })
              TextInput({ text: this.decBEText })
                .type(InputType.Number)
                .fontSize(14)
                .fontFamily('monospace')
                .fontColor(MctTheme.fg)
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .layoutWeight(1)
                .onChange((value: string): void => {
                  this.decBEText = value;
                })
              Button('转换')
                .fontSize(12)
                .height(34)
                .padding({ left: 10, right: 10 })
                .fontColor(MctTheme.fg)
                .backgroundColor(MctTheme.buttonBg)
                .borderRadius(4)
                .margin({ left: 4 })
                .onClick(() => {
                  this.onConvertDecBE();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })

            // Dec (LE).
            Row() {
              Text('Dec (LE)')
                .fontSize(16)
                .fontColor(MctTheme.fg)
                .width(96)
                .textAlign(TextAlign.End)
                .margin({ right: 5 })
              TextInput({ text: this.decLEText })
                .type(InputType.Number)
                .fontSize(14)
                .fontFamily('monospace')
                .fontColor(MctTheme.fg)
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .layoutWeight(1)
                .onChange((value: string): void => {
                  this.decLEText = value;
                })
              Button('转换')
                .fontSize(12)
                .height(34)
                .padding({ left: 10, right: 10 })
                .fontColor(MctTheme.fg)
                .backgroundColor(MctTheme.buttonBg)
                .borderRadius(4)
                .margin({ left: 4 })
                .onClick(() => {
                  this.onConvertDecLE();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 4 })

            // More converter (online).
            Text('更多在线转换器')
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
              .margin({ top: 20, left: 4 })
            Button('通用类型转换器')
              .width('100%')
              .height(44)
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4)
              .margin({ top: 8 })
              .onClick(() => {
                this.onOpenGenericConverter();
              })
            Button('多用途转换器')
              .width('100%')
              .height(44)
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4)
              .margin({ top: 8 })
              .onClick(() => {
                this.onOpenMultiPurposeConverter();
              })
            Button('Cyber Chef')
              .width('100%')
              .height(44)
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4)
              .margin({ top: 8, bottom: 8 })
              .onClick(() => {
                this.onOpenCyberChef();
              })
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
    .title('数据转换工具')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener (Android: BasicActivity
      // NFC foreground dispatch). If a newly discovered tag does not
      // support MIFARE Classic, run the only thing that is possible:
      // the tag info tool.
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
export function DataConversionToolBuilder() {
  DataConversionToolPage()
}
