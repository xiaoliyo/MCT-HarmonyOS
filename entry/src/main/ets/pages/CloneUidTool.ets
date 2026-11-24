/**
 * Clone UID to Magic Tag (port of
 * de.syss.MifareClassicTool.Activities.CloneUidTool,
 * GPL-3.0, Gerhard Klostermeier, Slawomir Jasek).
 *
 * Clone a UID to a "magic tag gen2". The gen2 magic tags allow direct
 * write to block 0 without the need for special "backdoor" commands.
 * The user enters (or scans) the UID to clone, block 0 is generated
 * and written to the magic tag. A status log informs about the
 * current state of the clone process.
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { McReader } from '../common/McReader';
import { MifareUtils } from '../common/MifareUtils';
import { NfcService } from '../common/NfcService';
import { TAG_SIZE_MINI, TAG_SIZE_1K, TAG_SIZE_2K, TAG_SIZE_4K } from '../common/MctTypes';
import { MctDialog } from '../common/ui/MctDialog';
import { MctTheme } from '../common/ui/MctTheme';

/** Clone process status (Status enum of the Android original). */
class CloneStatus {
  static readonly INIT: number = 0;
  static readonly BLOCK0_CALCULATED: number = 1;
  static readonly CLONED: number = 2;
}

/**
 * Warning dialog shown before writing possibly invalid data to
 * block 0. On "I know what I'm doing" continue with writing, on
 * cancel reset the clone process (showBlock0Warning of the
 * Android original).
 */
@CustomDialog
struct CloneUidBlock0WarningDialog {
  controller?: CustomDialogController;
  onPositive: () => void = (): void => {};
  onCancel: () => void = (): void => {};

  build() {
    Column() {
      Text('块 0 数据检查')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text('您即将向块 0 写入数据。但是，您的数据似乎可能无效。 \n\n在某些第二代标签上，SAK 和 ATQA 等值可能由块 0 中的字节控制。如果设置了错误的值，标签可能会（软）变砖。但也有一些标签会忽略错误的值。无论如何，UID 都应遵循 ISO 14443 规范。 \n\n此项块 0 检查试图确保您写入的数据符合 NXP 的规范。 \n\n继续操作的风险由您自行承担！')
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 14 })
        .lineHeight(23)
      Divider()
        .color(MctTheme.buttonBorder)
        .margin({ top: 16 })
      Row() {
        Text('取消')
          .fontSize(16)
          .fontColor(MctTheme.fgSecondary)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
            this.onCancel();
          })
        Text('我知道我在做什么')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(MctTheme.accent)
          .maxLines(2)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
            this.onPositive();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 6 })
    }
    .padding(22)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('88%')
  }
}

@Component
struct CloneUidToolPage {
  @State uidInput: string = '';
  @State block0RestInput: string = '080400475955D141103607';
  @State block0KeyInput: string = MifareUtils.DEFAULT_KEY;
  @State showOptions: boolean = false;
  @State calcSakAtqa: boolean = true;
  @State useKeyB: boolean = false;
  @State statusLog: string = '';
  private pathStack: NavPathStack = new NavPathStack();
  private uidLen: number = 0;
  private block0Complete: string = '';
  private ignoreIncorrectBlock0: boolean = false;
  private status: number = CloneStatus.INIT;
  private block0WarningCtrl: CustomDialogController | null = null;
  private infoDialogCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    MctTheme.refresh();
    // If a tag was scanned before, fill the UID.
    if (NfcService.getTag() !== null) {
      const uid: string = HexUtils.bytes2Hex(NfcService.getUID());
      this.uidInput = uid;
      this.appendToLog('使用已扫描标签的 UID' + ' (' + uid + ')');
    }
  }

  // ---------------- Status log ----------------

  /**
   * Append a text to the status log
   * (Android: appendToLog).
   */
  private appendToLog(text: string): void {
    const newline: string = this.statusLog.length === 0 ? '' : '\n';
    this.statusLog = this.statusLog + newline + '• ' + text;
  }

  // ---------------- Tag handling ----------------

  /**
   * Handle a newly discovered tag according to the current status
   * of the clone process (Android: onNewIntent).
   */
  private onTagDiscovered(): void {
    const uid: string = HexUtils.bytes2Hex(NfcService.getUID());
    if (this.status === CloneStatus.INIT) {
      // Original tag scanned.
      this.uidInput = uid;
      this.appendToLog('使用已扫描标签的 UID' + ' (' + uid + ')');
    } else if (this.status === CloneStatus.BLOCK0_CALCULATED) {
      // UID is present, block 0 calculated.
      // Write to magic tag gen2.
      this.writeManufacturerBlock();
    } else if (this.status === CloneStatus.CLONED) {
      // Confirm the UID is cloned.
      // Read it again from current tag.
      this.appendToLog('正在检查克隆');
      const uidOriginal: string = this.uidInput;
      if (uid === uidOriginal) {
        this.appendToLog('UID 克隆成功');
        this.appendToLog('正在重置克隆过程');
        this.status = CloneStatus.INIT;
        this.ignoreIncorrectBlock0 = false;
      } else {
        this.appendToLog('UID 不匹配'
          + ' (' + uidOriginal + ' <-> ' + uid + ')');
        this.appendToLog('错误：您确定您使用的是魔术标签（第二代）吗？');
        this.status = CloneStatus.BLOCK0_CALCULATED;
      }
    }
  }

  // ---------------- Block 0 generation ----------------

  /**
   * Calculate the BCC of the UID and create block 0 (manufacturer
   * block) by concatenating UID, BCC and the rest of block 0
   * (Android: onCalculateBlock0).
   */
  private onCalculateBlock0(): void {
    const uid: string = this.uidInput;
    this.uidLen = uid.length;
    const block0Rest: string = this.block0RestInput;
    const block0Key: string = this.block0KeyInput;

    // Check if all data is HEX.
    if (!/^[0-9A-Fa-f]+$/.test(block0Rest)
      || !/^[0-9A-Fa-f]+$/.test(uid)
      || !/^[0-9A-Fa-f]+$/.test(block0Key)) {
      // Error, not hex.
      NfcService.toast('错误：数据必须为十六进制（0-9 和 A-F）', true);
      return;
    }

    // Check key field.
    if (block0Key.length !== 12) {
      NfcService.toast('错误：某些密钥不足 6 字节（12 个字符）', true);
      return;
    }

    // Check the UID length.
    if (this.uidLen !== 8 && this.uidLen !== 14 && this.uidLen !== 20) {
      // Error. No 4, 7 or 10 bytes UID.
      NfcService.toast('错误：UID 长度无效', true);
      return;
    }
    this.uidLen = this.uidLen / 2; // Change from char length to byte length.

    // Check rest of block 0.
    const block0RestLen: number = (this.uidLen === 4) ? 22 : 32 - this.uidLen * 2;
    if (block0Rest.length < block0RestLen) {
      NfcService.toast('错误：块 0 其余部分的长度不正确', true);
      return;
    }

    // Calculate BCC for 4-byte UIDs and construct full block 0.
    if (this.uidLen === 4) {
      const uidBytes: number[] | null = HexUtils.hex2Bytes(uid);
      const bcc: number = HexUtils.calcBcc(uidBytes !== null ? uidBytes : []);
      // The Android original uses String.format("%02X", bcc) with a
      // signed byte, which produces malformed output for values >=
      // 0x80 (sign extension). This port deliberately pads the
      // unsigned value to 2 hex characters instead.
      let bccHex: string = bcc.toString(16).toUpperCase();
      if (bccHex.length < 2) {
        bccHex = '0' + bccHex;
      }
      this.block0Complete = uid + bccHex + block0Rest;
    } else {
      this.block0Complete = uid
        + block0Rest.substring(block0Rest.length - block0RestLen);
    }
    this.status = CloneStatus.BLOCK0_CALCULATED;
    this.appendToLog('块 0 已生成');
    this.appendToLog('等待魔术标签（第二代）');
    // Hide options.
    this.showOptions = false;
  }

  // ---------------- Write block 0 ----------------

  /**
   * Check and write block 0 (manufacturer block) with the
   * previously generated block 0 data containing the cloned UID
   * (Android: writeManufacturerBlock).
   */
  private async writeManufacturerBlock(): Promise<void> {
    const keyB: boolean = this.useKeyB;
    const key: number[] | null = HexUtils.hex2Bytes(this.block0KeyInput);

    // Create reader.
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return;
    }

    // Check for UID length mismatch between user input and detected card.
    const uid: number[] | null = NfcService.getUID();
    const uidLen: number = uid !== null ? uid.length : 0;
    if (uidLen !== this.uidLen) {
      // Error. UID length does not match the source.
      this.appendToLog('错误：UID 长度不匹配（4、7 或 10 字节）');
      reader.close();
      return;
    }

    // Automatically calculate the SAK and ATQA value?
    if (this.calcSakAtqa) {
      const sakAndAtqa: string | null = this.calcSakAtqaForTag(uidLen, reader.getSize());
      if (sakAndAtqa === null) {
        // Error.
        this.appendToLog('警告：无法计算 SAK/ATQA，将使用默认值');
      } else {
        // Replace SAK & ATQA.
        const sakStart: number = (uidLen === 4) ? uidLen * 2 + 2 : uidLen * 2;
        this.block0Complete = this.block0Complete.substring(0, sakStart)
          + sakAndAtqa
          + this.block0Complete.substring(sakStart + sakAndAtqa.length);
      }
    }
    this.appendToLog('要写入的数据：' + ' ' + this.block0Complete);

    // Check for block 0 issues (BCC, SAK, ATQA, UID0, ...).
    if (!this.ignoreIncorrectBlock0
      && !MifareUtils.isValidBlock0(this.block0Complete, uidLen, reader.getSize(), false)) {
      this.appendToLog('警告：块 0 可能包含无效数据（BCC/SAK/ATQA/UID0）');
      this.showBlock0Warning();
      reader.close();
      return;
    }

    // Write to block 0.
    this.appendToLog('正在写入块 0');
    const result: number = await reader.writeBlock(0, 0,
      HexUtils.hex2Bytes(this.block0Complete), key !== null ? key : [], keyB);

    // Error handling.
    if (result === 4) {
      this.appendToLog('错误：密钥不正确');
      // (The Android original does not close the reader here. This
      // port closes it to release the tag connection.)
      reader.close();
      return;
    }
    if (result === -1) {
      NfcService.toast('错误：写入时发生错误。（情况可能不妙。）', true);
      this.appendToLog('错误：您确定您使用的是魔术标签（第二代）吗？');
      // (The Android original does not close the reader here. This
      // port closes it to release the tag connection.)
      reader.close();
      return;
    }

    this.appendToLog('写入过程没有错误');
    this.appendToLog('重新扫描克隆以验证是否成功');
    this.status = CloneStatus.CLONED;
    reader.close();
  }

  /**
   * Calculate a SAK and ATQA value according to NXP's specifications
   * (https://www.nxp.com/docs/en/application-note/AN10833.pdf).
   * Returns a hex string representing 1 byte SAK and 2 byte ATQA,
   * or null on error (Android: calcSakAtqa).
   */
  private calcSakAtqaForTag(uidLen: number, tagSize: number): string | null {
    if ((uidLen !== 4 && uidLen !== 7) || (
      tagSize !== TAG_SIZE_MINI && tagSize !== TAG_SIZE_1K
      && tagSize !== TAG_SIZE_2K && tagSize !== TAG_SIZE_4K)) {
      return null;
    }

    // ATQA.
    let atqa: string | null = null;
    if (uidLen === 4 && (tagSize === TAG_SIZE_1K || tagSize === TAG_SIZE_2K
      || tagSize === TAG_SIZE_MINI)) {
      atqa = '0400';
    } else if (uidLen === 4 && tagSize === TAG_SIZE_4K) {
      atqa = '0200';
    } else if (uidLen === 7 && (tagSize === TAG_SIZE_1K || tagSize === TAG_SIZE_2K
      || tagSize === TAG_SIZE_MINI)) {
      atqa = '4400';
    } else if (uidLen === 7 && tagSize === TAG_SIZE_4K) {
      atqa = '4200';
    }

    // SAK.
    // NOTE: Tags might not appear to be genuine/valid NXP/Infinion tags.
    // For a 4b UID/1k MFC tag the SAK should be 0x08 but the
    // "corresponding" byte in block 0 (byte nr. 5) must be 0x88.
    // This is not possible with some gen2 tags, because they use
    // byte nr. 5 as SAK value.
    let sak: string | null = null;
    if (tagSize === TAG_SIZE_MINI) {
      sak = '09';
    } else if (tagSize === TAG_SIZE_1K || tagSize === TAG_SIZE_2K) {
      sak = '08';
    } else if (tagSize === TAG_SIZE_4K) {
      sak = '18';
    }

    if (sak === null || atqa === null) {
      return null;
    }
    return sak + atqa;
  }

  // ---------------- Dialogs ----------------

  /**
   * Show a warning dialog to inform the user that he is about to
   * write what may be invalid data to block 0. On ignore, continue
   * with writing. On cancel, reset the clone process
   * (Android: showBlock0Warning).
   */
  private showBlock0Warning(): void {
    this.block0WarningCtrl = new CustomDialogController({
      builder: CloneUidBlock0WarningDialog({
        onPositive: (): void => {
          // Write.
          this.ignoreIncorrectBlock0 = true;
          this.writeManufacturerBlock();
        },
        onCancel: (): void => {
          this.onCancelBlock0Warning();
        }
      }),
      autoCancel: true,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        // Cancel via back button or mask tap
        // (Android: setOnCancelListener).
        action.dismiss();
        this.onCancelBlock0Warning();
      }
    });
    this.block0WarningCtrl.open();
  }

  /**
   * Cancel the block 0 warning dialog. Reset the clone process.
   */
  private onCancelBlock0Warning(): void {
    // Cancel.
    this.status = CloneStatus.INIT;
    this.appendToLog('正在重置克隆过程');
  }

  /**
   * Show a simple info dialog with title, message and an OK button.
   */
  private showInfoDialog(title: string, message: string): void {
    this.infoDialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: title,
        messageText: message,
        button1Text: '确定'
      }),
      autoCancel: true,
      customStyle: true
    });
    this.infoDialogCtrl.open();
  }

  /**
   * Show general information about this tool and cloning UIDs of
   * MIFARE Classic tags (Android: onShowInfo).
   */
  private onShowInfo(): void {
    this.showInfoDialog('克隆 UID',
      'MIFARE Classic 标签第一个扇区的第一个块包含 UID，并且是只读的，即不可写入。但存在特殊的 MIFARE Classic 标签（“第二代魔术标签”，又称“块 0 直接写入标签”），支持通过简单的写入命令写入第一个块（包括 UID）。本应用能够写入此类标签，因此可以克隆 UID。但是，某些特殊标签（“第一代魔术标签”）需要特殊的命令序列才能进入可写入制造商块的状态。这些标签无法使用。');
  }

  /**
   * Show information about how the rest of the block 0 is used
   * during the UID cloning process (Android: onShowBlock0RestInfo).
   */
  private onShowBlock0RestInfo(): void {
    this.showInfoDialog('块 0 的其余部分',
      'MIFARE Classic 标签通常只能按块写入。UID 由块 0 的前几个字节表示。要更改 UID，必须写入完整的块 0。“块 0 的其余部分”数据是指将附加到 UID 之后、用于构成完整块的字节。');
  }

  /**
   * Show information about the key which is needed to write to
   * block 0 (Android: onShowWriteKeyInfo).
   */
  private onShowWriteKeyInfo(): void {
    this.showInfoDialog('块 0 的密钥',
      '要写入块 0（包含 UID 的块），您需要具有写入权限的相应密钥。对于空白或恢复出厂格式的标签，此密钥是密钥 A，其值为“FFFFFFFFFFFF”。');
  }

  /**
   * Show information about SAK and ATQA being part of block 0
   * (or at least might be) (Android: onShowSakAtqaInfo).
   */
  private onShowSakAtqaInfo(): void {
    this.showInfoDialog('计算 SAK 和 ATQA',
      '对于某些第二代魔术标签，块 0 中 UID（以及可能的 BCC）后面的值表示 SAK 和 ATQA。 \n\n如果使用此选项，这些值将被自动生成。如果不使用，将使用编码在“块 0 的其余部分”中的值。');
  }

  // ---------------- UID input helpers ----------------

  /**
   * Paste the content of the clipboard (if plain text) to the UID
   * input (Android: onPasteUidFromClipboard).
   */
  private onPasteUidFromClipboard(): void {
    const text: string | null = NfcService.getFromClipboard();
    if (text !== null) {
      // The input field is limited to 20 characters
      // (like the Android EditText maxLength).
      this.uidInput = text.substring(0, 20);
    }
  }

  /**
   * Generate a random 4 byte UID to be written to the tag.
   * UID 00000000 will be ignored because it may cause errors on
   * some readers (Android: onRandomUid).
   */
  private onRandomUid(): void {
    let uid: string = '00000000';
    while (uid === '00000000') {
      const bytesUid: number[] = [];
      for (let i: number = 0; i < 4; i++) {
        bytesUid.push(Math.floor(Math.random() * 256));
      }
      uid = HexUtils.bytes2Hex(bytesUid);
    }
    this.uidInput = uid;
    NfcService.toast('已生成随机 UID', false);
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // Info box.
          Row() {
            Text('此工具可以将标签的 UID 克隆到“魔术标签”（第二代、兼容 Android、支持直接写入、块 0 可写）。点击信息按钮以获取更多信息。')
              .fontSize(15)
              .fontColor(MctTheme.fg)
              .layoutWeight(1)
              .padding(5)
            Text('ⓘ')
              .fontSize(18)
              .fontColor(MctTheme.accent)
              .padding({ left: 6, right: 4, top: 4, bottom: 4 })
              .onClick(() => {
                this.onShowInfo();
              })
          }
          .width('100%')
          .padding(2)
          .borderRadius(5)
          .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
          .alignItems(VerticalAlign.Top)
          .margin({ bottom: 5 })

          // UID to clone (+ paste + random UID).
          Row() {
            Text('要克隆的 UID')
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .margin({ right: 5 })
            TextInput({ text: this.uidInput, placeholder: 'HEX，4/7/10 字节' })
              .maxLength(20)
              .fontSize(15)
              .fontColor(MctTheme.fg)
              .fontFamily('monospace')
              .placeholderColor(MctTheme.fgSecondary)
              .placeholderFont({ size: 14 })
              .backgroundColor(MctTheme.inputBg)
              .borderRadius(4)
              .layoutWeight(1)
              .onChange((value: string): void => {
                this.uidInput = value;
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
              this.onPasteUidFromClipboard();
            })
            Button() {
              Image($r('app.media.random'))
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
              this.onRandomUid();
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 10 })

          // Show options.
          Row() {
            Checkbox()
              .select(this.showOptions)
              .selectedColor(MctTheme.accent)
              .width(20)
              .height(20)
              .onChange((value: boolean): void => {
                this.showOptions = value;
              })
            Text('显示选项')
              .fontSize(15)
              .fontColor(MctTheme.fg)
              .margin({ left: 8 })
              .onClick(() => {
                this.showOptions = !this.showOptions;
              })
          }
          .width('100%')
          .margin({ top: 8 })

          if (this.showOptions) {
            // Options.
            Column() {
              // Rest of block 0.
              Column() {
                Row() {
                  Text('块 0 的其余部分')
                    .fontSize(15)
                    .fontColor(MctTheme.fg)
                    .layoutWeight(1)
                  Text('ⓘ')
                    .fontSize(18)
                    .fontColor(MctTheme.accent)
                    .padding({ left: 6, right: 2, top: 2, bottom: 2 })
                    .onClick(() => {
                      this.onShowBlock0RestInfo();
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                TextInput({ text: this.block0RestInput })
                  .maxLength(22)
                  .width('100%')
                  .fontSize(15)
                  .fontColor(MctTheme.fg)
                  .fontFamily('monospace')
                  .backgroundColor(MctTheme.inputBg)
                  .borderRadius(4)
                  .margin({ top: 4 })
                  .onChange((value: string): void => {
                    this.block0RestInput = value;
                  })
              }
              .width('100%')
              .padding(5)
              .borderRadius(5)
              .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
              .margin({ bottom: 5 })

              // Key to write block 0.
              Column() {
                Row() {
                  Text('写入块 0 所用的密钥')
                    .fontSize(15)
                    .fontColor(MctTheme.fg)
                    .layoutWeight(1)
                  Text('ⓘ')
                    .fontSize(18)
                    .fontColor(MctTheme.accent)
                    .padding({ left: 6, right: 2, top: 2, bottom: 2 })
                    .onClick(() => {
                      this.onShowWriteKeyInfo();
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                TextInput({ text: this.block0KeyInput })
                  .maxLength(22)
                  .width('100%')
                  .fontSize(15)
                  .fontColor(MctTheme.fg)
                  .fontFamily('monospace')
                  .backgroundColor(MctTheme.inputBg)
                  .borderRadius(4)
                  .margin({ top: 4 })
                  .onChange((value: string): void => {
                    this.block0KeyInput = value;
                  })
                Row() {
                  Radio({ value: 'keyA', group: 'cloneUidKey' })
                    .checked(!this.useKeyB)
                    .radioStyle({ checkedBackgroundColor: MctTheme.accent })
                    .onChange((isChecked: boolean): void => {
                      if (isChecked) {
                        this.useKeyB = false;
                      }
                    })
                  Text('密钥 A')
                    .fontSize(14)
                    .fontColor(MctTheme.fg)
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.useKeyB = false;
                    })
                  Radio({ value: 'keyB', group: 'cloneUidKey' })
                    .checked(this.useKeyB)
                    .radioStyle({ checkedBackgroundColor: MctTheme.accent })
                    .margin({ left: 16 })
                    .onChange((isChecked: boolean): void => {
                      if (isChecked) {
                        this.useKeyB = true;
                      }
                    })
                  Text('密钥 B')
                    .fontSize(14)
                    .fontColor(MctTheme.fg)
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.useKeyB = true;
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .margin({ top: 8 })
              }
              .width('100%')
              .padding(5)
              .borderRadius(5)
              .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
              .margin({ bottom: 5 })

              // Automatically calculate SAK and ATQA.
              Column() {
                Row() {
                  Checkbox()
                    .select(this.calcSakAtqa)
                    .selectedColor(MctTheme.accent)
                    .width(20)
                    .height(20)
                    .onChange((value: boolean): void => {
                      this.calcSakAtqa = value;
                    })
                  Text('自动计算 SAK 和 ATQA 值')
                    .fontSize(14)
                    .fontColor(MctTheme.fg)
                    .margin({ left: 6 })
                    .layoutWeight(1)
                    .onClick(() => {
                      this.calcSakAtqa = !this.calcSakAtqa;
                    })
                  Text('ⓘ')
                    .fontSize(18)
                    .fontColor(MctTheme.accent)
                    .padding({ left: 6, right: 2, top: 2, bottom: 2 })
                    .onClick(() => {
                      this.onShowSakAtqaInfo();
                    })
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .padding(5)
              .borderRadius(5)
              .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
            }
            .width('100%')
            .padding({ left: 35 })
            .margin({ top: 4 })
          }

          // Generate block 0 and clone UID.
          Button('生成块 0 并克隆 UID')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .margin({ top: 5, bottom: 15 })
            .onClick(() => {
              this.onCalculateBlock0();
            })

          // Status log.
          Text('状态日志')
            .fontSize(16)
            .fontColor(MctTheme.accent)
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ bottom: 5 })
          Text(this.statusLog)
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .width('100%')
            .padding(5)
            .textAlign(TextAlign.Start)
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
        }
        .width('100%')
        .padding(5)
      }
      .align(Alignment.Top)
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('克隆 UID 到魔术标签（第二代）')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener (Android: onNewIntent).
      NfcService.setTagListener((tagInfo: tag.TagInfo, supportResult: number): void => {
        if (supportResult === -2) {
          // Device or tag does not support MIFARE Classic.
          // Run the only thing that is possible: The tag info tool.
          this.pathStack.pushPathByName('tagInfoTool', null);
        }
        // Handle the new tag according to the current status
        // of the clone process.
        this.onTagDiscovered();
      });
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function CloneUidToolBuilder() {
  CloneUidToolPage()
}
