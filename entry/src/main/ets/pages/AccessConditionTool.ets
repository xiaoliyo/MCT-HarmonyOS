/**
 * Access Condition Tool (port of
 * de.syss.MifareClassicTool.Activities.AccessConditionTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Decode MIFARE Classic Access Conditions from their hex format to a
 * more human readable format and vice versa. The user chooses the
 * access conditions for the sector trailer (block 3) and for the data
 * blocks (blocks 0-2) from a list of all possible access conditions
 * (each entry shows which operations - read/write/increment/etc. -
 * are possible with which key). Depending on the readability of key B
 * (determined by the access conditions of the sector trailer) the
 * list of valid access conditions for the data blocks is limited.
 * The resulting 3 byte access condition hex string can be encoded
 * (and copied to the clipboard) and a given access condition hex
 * string can be decoded into the human readable format.
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { MctTheme } from '../common/ui/MctTheme';
import { MifareUtils } from '../common/MifareUtils';
import { NfcService } from '../common/NfcService';

/**
 * Access Conditions for a data block
 * (res/values/access_conditions.xml and NXP's MF1S50yyX,
 * Chapter 8.7.1, 8.7.2, 8.7.3, Table 7 and 8).
 */
const AC_DATA_BLOCK: string[] = [
  '读取：A|B\n写入：A|B\n增值：A|B\n减值/传输/恢复：A|B',
  '读取：A|B\n写入：禁止\n增值：禁止\n减值/传输/恢复：禁止',
  '读取：A|B\n写入：B\n增值：禁止\n减值/传输/恢复：禁止',
  '读取：A|B\n写入：B\n增值：B\n减值/传输/恢复：A|B',
  '读取：A|B\n写入：禁止\n增值：禁止\n减值/传输/恢复：A|B',
  '读取：B\n写入：B\n增值：禁止\n减值/传输/恢复：禁止',
  '读取：B\n写入：禁止\n增值：禁止\n减值/传输/恢复：禁止',
  '读取：禁止\n写入：禁止\n增值：禁止\n减值/传输/恢复：禁止'
];

/**
 * Access Conditions for data blocks if key B is readable
 * (res/values/access_conditions.xml).
 */
const AC_DATA_BLOCK_NO_KEY_B: string[] = [
  '读取：A\n写入：A\n增值：A\n减值/传输/恢复：A',
  '读取：A\n写入：禁止\n增值：禁止\n减值/传输/恢复：禁止',
  '读取：A\n写入：禁止\n增值：禁止\n减值/传输/恢复：A',
  '读取：禁止\n写入：禁止\n增值：禁止\n减值/传输/恢复：禁止'
];

/**
 * Access Conditions for a Sector Trailer
 * (res/values/access_conditions.xml and NXP's MF1S50yyX,
 * Chapter 8.7.1, 8.7.2, 8.7.3, Table 7 and 8).
 */
const AC_SECTOR_TRAILER: string[] = [
  '读密钥 A：禁止\n写密钥 A：A\n读访问条件：A\n写访问条件：禁止\n读密钥 B：A\n写密钥 B：A',
  '读密钥 A：禁止\n写密钥 A：禁止\n读访问条件：A\n写访问条件：禁止\n读密钥 B：A\n写密钥 B：禁止',
  '读密钥 A：禁止\n写密钥 A：B\n读访问条件：A|B\n写访问条件：禁止\n读密钥 B：禁止\n写密钥 B：B',
  '读密钥 A：禁止\n写密钥 A：禁止\n读访问条件：A|B\n写访问条件：禁止\n读密钥 B：禁止\n写密钥 B：禁止',
  '读密钥 A：禁止\n写密钥 A：A\n读访问条件：A\n写访问条件：A\n读密钥 B：A\n写密钥 B：A',
  '读密钥 A：禁止\n写密钥 A：B\n读访问条件：A|B\n写访问条件：B\n读密钥 B：禁止\n写密钥 B：B',
  '读密钥 A：禁止\n写密钥 A：禁止\n读访问条件：A|B\n写访问条件：B\n读密钥 B：禁止\n写密钥 B：禁止',
  '读密钥 A：禁止\n写密钥 A：禁止\n读访问条件：A|B\n写访问条件：禁止\n读密钥 B：禁止\n写密钥 B：禁止'
];

/** Create an access bits (C1-C3) array. */
function acBitsOf(c1: number, c2: number, c3: number): number[] {
  const bits: number[] = [c1, c2, c3];
  return bits;
}

/**
 * A dialog which allows the user to choose between all possible
 * Access Conditions for a data block or a Sector Trailer
 * (Android: AlertDialog with a ListView of
 * res/values/access_conditions.xml entries).
 */
@CustomDialog
struct AcChooserDialog {
  controller?: CustomDialogController;
  titleText: string = '';
  options: string[] = [];
  onSelect: (index: number) => void = (index: number): void => {};

  build() {
    Column() {
      Text(this.titleText)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      Scroll() {
        Column() {
          ForEach(this.options, (option: string, index: number) => {
            Text(option)
              .fontSize(14)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
              .lineHeight(19)
              .padding({ top: 10, bottom: 10 })
              .borderRadius(4)
              .onClick(() => {
                this.controller?.close();
                this.onSelect(index);
              })
            if (index < this.options.length - 1) {
              Divider()
                .color(MctTheme.buttonBorder)
            }
          }, (option: string, index: number) => index.toString())
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .margin({ top: 10 })
    }
    .padding(22)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('90%')
  }
}

@Component
struct AccessConditionToolPage {
  @State acText: string = '';
  @State block0Text: string = AC_DATA_BLOCK_NO_KEY_B[0];
  @State block1Text: string = AC_DATA_BLOCK_NO_KEY_B[0];
  @State block2Text: string = AC_DATA_BLOCK_NO_KEY_B[0];
  @State block3Text: string = AC_SECTOR_TRAILER[4];
  private pathStack: NavPathStack = new NavPathStack();
  /**
   * Matrix of access conditions bits (C1-C3) where the first
   * dimension is the "C" parameter (C1-C3, index 0-2) and the second
   * dimension is the block number (index 0-3).
   * This matrix will be updated each time a user chooses access
   * conditions via one of the chooser dialogs or decodes an access
   * condition hex string.
   */
  private acMatrix: number[][] = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 1]];
  /**
   * True if the access conditions of the sector trailer state that
   * key B is readable. Many methods rely on this member variable
   * (getResourceForDataBlocksByRowNr, acRowNrToACBits,
   * acBitsToACRowNr, buildDataBlockOptions).
   */
  private isKeyBReadable: boolean = true;
  private wasKeyBReadable: boolean = false;
  private sectorTrailerDialogCtrl: CustomDialogController | null = null;
  private dataBlockDialogCtrl: CustomDialogController | null = null;
  /** The last clicked "choose access conditions for data block" block. */
  private selectedBlock: number = 0;

  aboutToAppear(): void {
    MctTheme.refresh();
    // Init. member vars.
    // Init AC matrix with factory setting/transport configuration.
    this.acMatrix = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 1]];
    // Build the dialog with access conditions for the Sector Trailer
    // (this dialog is created on demand, see showSectorTrailerDialog()).
    // Build the dialog with access conditions for data blocks.
    // Key B is readable in the default configuration.
    this.isKeyBReadable = true;
    this.buildDataBlockOptions(false);
  }

  // ---------------- Convert (decode/encode) ----------------

  /**
   * Convert the 3 access condition bytes into a more human readable
   * format using MifareUtils.acBytesToACMatrix, acBitsToACRowNr and
   * the access condition string tables.
   */
  private onDecode(): void {
    const ac: string = this.acText;
    if (ac.length !== 6) {
      // Error. Access conditions are not 3 byte (6 characters) long.
      NfcService.toast(
        '错误：访问条件必须为 3 字节（6 个字符）',
        true);
      return;
    }
    if (!/^[0-9A-Fa-f]+$/.test(ac)) {
      // Error. Not hex.
      NfcService.toast(
        '错误：访问条件不是十六进制（0-9、A-F）', true);
      return;
    }

    const acMatrix: number[][] | null =
      MifareUtils.acBytesToACMatrix(HexUtils.hex2Bytes(ac));
    let error: boolean = false;
    if (acMatrix !== null) {
      // First check & set sector trailer.
      let acBits: number[] =
        acBitsOf(acMatrix[0][3], acMatrix[1][3], acMatrix[2][3]);
      let rowNr: number = this.acBitsToACRowNr(acBits, true);
      if (rowNr !== -1) {
        // Check if key B is readable.
        this.isKeyBReadable = rowNr < 2 || rowNr === 4;
        this.block3Text = AC_SECTOR_TRAILER[rowNr];

        // Now check & set data blocks.
        for (let i = 0; i < 3; i++) {
          acBits = acBitsOf(acMatrix[0][i], acMatrix[1][i], acMatrix[2][i]);
          rowNr = this.acBitsToACRowNr(acBits, false);
          if (rowNr === -1) {
            // Error.
            error = true;
            break;
          }
          this.setDataBlockButtonText(i,
            this.getResourceForDataBlocksByRowNr(rowNr));
        }
      } else {
        // Error.
        error = true;
      }
    } else {
      // Error.
      error = true;
    }

    // Were there some errors during this process?
    if (error) {
      // Display an error message.
      NfcService.toast('错误：访问条件无效', true);
      return;
    }
    if (acMatrix !== null) {
      this.acMatrix = acMatrix;
    }
    this.buildDataBlockOptions(false);
  }

  /**
   * Convert the AC matrix to 3 access condition bytes using
   * MifareUtils.acMatrixToACBytes and display them.
   */
  private onEncode(): void {
    const acBytes: number[] | null =
      MifareUtils.acMatrixToACBytes(this.acMatrix);
    if (acBytes === null) {
      // Error. (Should not happen.)
      return;
    }
    this.acText = HexUtils.bytes2Hex(acBytes);
  }

  // ---------------- Access condition tables ----------------

  /**
   * Return the access condition string for data blocks based on its
   * position in the table (res/values/access_conditions.xml and NXP's
   * MF1S50yyX, Chapter 8.7.1, 8.7.2, 8.7.3, Table 7 and 8).
   */
  private getResourceForDataBlocksByRowNr(rowNr: number): string {
    if (this.isKeyBReadable) {
      // Key B is readable. Only a limited set of access conditions.
      if (rowNr >= 0 && rowNr < AC_DATA_BLOCK_NO_KEY_B.length) {
        return AC_DATA_BLOCK_NO_KEY_B[rowNr];
      }
      return '';
    }
    if (rowNr >= 0 && rowNr < AC_DATA_BLOCK.length) {
      return AC_DATA_BLOCK[rowNr];
    }
    return '';
  }

  /**
   * Convert the row number of the access condition table to its
   * corresponding access bits C1, C2 and C3 (see:
   * res/values/access_conditions.xml and NXP's MF1S50yyX,
   * Chapter 8.7.1, 8.7.2, 8.7.3, Table 7 and 8).
   * Returns null on error.
   */
  private acRowNrToACBits(rowNr: number,
    isSectorTrailer: boolean): number[] | null {
    if (!isSectorTrailer && this.isKeyBReadable && rowNr > 1) {
      // Key B is readable. Only a limited set of access conditions.
      switch (rowNr) {
        case 2:
          return acBitsOf(0, 0, 1);
        case 3:
          return acBitsOf(1, 1, 1);
        default:
          // Error.
          return null;
      }
    }

    switch (rowNr) {
      case 0:
        return acBitsOf(0, 0, 0);
      case 1:
        return acBitsOf(0, 1, 0);
      case 2:
        return acBitsOf(1, 0, 0);
      case 3:
        return acBitsOf(1, 1, 0);
      case 4:
        return acBitsOf(0, 0, 1);
      case 5:
        return acBitsOf(0, 1, 1);
      case 6:
        return acBitsOf(1, 0, 1);
      case 7:
        return acBitsOf(1, 1, 1);
      default:
        // Error.
        return null;
    }
  }

  /**
   * Convert the access bits C1, C2 and C3 to its corresponding row
   * number in the access condition table (see:
   * res/values/access_conditions.xml and NXP's MF1S50yyX,
   * Chapter 8.7.1, 8.7.2, 8.7.3, Table 7 and 8).
   * Returns -1 on error.
   */
  private acBitsToACRowNr(acBits: number[], isSectorTrailer: boolean): number {
    if (acBits.length !== 3) {
      return -1;
    }
    const c1: number = acBits[0];
    const c2: number = acBits[1];
    const c3: number = acBits[2];

    if (!isSectorTrailer && this.isKeyBReadable) {
      // Key B is readable. Only a limited set of access conditions.
      if (c1 === 0 && c2 === 0 && c3 === 0) {
        return 0;
      } else if (c1 === 0 && c2 === 1 && c3 === 0) {
        return 1;
      } else if (c1 === 0 && c2 === 0 && c3 === 1) {
        return 2;
      } else if (c1 === 1 && c2 === 1 && c3 === 1) {
        return 3;
      }
    } else {
      if (c1 === 0 && c2 === 0 && c3 === 0) {
        return 0;
      } else if (c1 === 0 && c2 === 1 && c3 === 0) {
        return 1;
      } else if (c1 === 1 && c2 === 0 && c3 === 0) {
        return 2;
      } else if (c1 === 1 && c2 === 1 && c3 === 0) {
        return 3;
      } else if (c1 === 0 && c2 === 0 && c3 === 1) {
        return 4;
      } else if (c1 === 0 && c2 === 1 && c3 === 1) {
        return 5;
      } else if (c1 === 1 && c2 === 0 && c3 === 1) {
        return 6;
      } else if (c1 === 1 && c2 === 1 && c3 === 1) {
        return 7;
      }
    }

    // Error.
    return -1;
  }

  // ---------------- Chooser dialogs ----------------

  /**
   * Rebuild the data block options based on isKeyBReadable. If key B
   * is readable due to the access conditions of a sector trailer, the
   * access conditions for a normal data block are limited to
   * conditions that don't use key B.
   * If resetBlockACs is true, the access conditions of all data
   * blocks will be reset (C1=0, C2=0, C3=0).
   * (In this port the data block chooser dialog itself is created
   * when the user opens it, using the current key B readability.)
   */
  private buildDataBlockOptions(resetBlockACs: boolean): void {
    let items: string[] = [];
    if (this.isKeyBReadable && !this.wasKeyBReadable) {
      // Rebuild options (because key B is now readable).
      for (let i = 0; i < 4; i++) {
        items.push(this.getResourceForDataBlocksByRowNr(i));
      }
      this.wasKeyBReadable = true;
    } else if (!this.isKeyBReadable && this.wasKeyBReadable) {
      // Rebuild options (because key B is no longer readable).
      for (let i = 0; i < 8; i++) {
        items.push(this.getResourceForDataBlocksByRowNr(i));
      }
      this.wasKeyBReadable = false;
    } else {
      // No build is needed.
      return;
    }

    if (resetBlockACs && items.length > 0) {
      // Reset AC matrix and update button texts.
      for (let i = 0; i < 3; i++) {
        this.setDataBlockButtonText(i, items[0]);
        this.acMatrix[0][i] = 0;
        this.acMatrix[1][i] = 0;
        this.acMatrix[2][i] = 0;
      }
      if (this.isKeyBReadable) {
        NfcService.toast(
          '密钥 B 可读。\n数据块的访问条件已更新。', true);
      } else {
        NfcService.toast(
          '密钥 B 不可读。\n数据块的访问条件已更新。',
          true);
      }
    }
  }

  /**
   * Show the access condition chooser dialog for the Sector Trailer
   * (Android: onChooseACforSectorTrailer).
   */
  private showSectorTrailerDialog(): void {
    this.sectorTrailerDialogCtrl = new CustomDialogController({
      builder: AcChooserDialog({
        titleText: '选择访问条件',
        options: AC_SECTOR_TRAILER,
        onSelect: (index: number): void => {
          this.onChooseACForSectorTrailer(index);
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true
    });
    this.sectorTrailerDialogCtrl?.open();
  }

  /**
   * Apply the chosen access conditions to the sector trailer and
   * rebuild the data block options based on the readability of key B.
   */
  private onChooseACForSectorTrailer(position: number): void {
    // Change button text to selected access conditions.
    if (position >= 0 && position < AC_SECTOR_TRAILER.length) {
      this.block3Text = AC_SECTOR_TRAILER[position];
    }
    // Set access condition bits for sector trailer.
    const acBits: number[] | null =
      this.acRowNrToACBits(position, true);
    if (acBits !== null) {
      this.acMatrix[0][3] = acBits[0];
      this.acMatrix[1][3] = acBits[1];
      this.acMatrix[2][3] = acBits[2];
    }
    // Rebuild the data block options based on the readability of key B.
    this.isKeyBReadable = position < 2 || position === 4;
    this.buildDataBlockOptions(true);
  }

  /**
   * Show the access condition chooser dialog for a data block
   * (Android: onChooseACforDataBock).
   */
  private showDataBlockDialog(blockNr: number): void {
    // Backup the clicked block to change its button text later.
    this.selectedBlock = blockNr;
    // The options depend on the readability of key B
    // (4 options if key B is readable, 8 if not).
    const optionCount: number = this.isKeyBReadable
      ? AC_DATA_BLOCK_NO_KEY_B.length : AC_DATA_BLOCK.length;
    const items: string[] = [];
    for (let i = 0; i < optionCount; i++) {
      items.push(this.getResourceForDataBlocksByRowNr(i));
    }
    this.dataBlockDialogCtrl = new CustomDialogController({
      builder: AcChooserDialog({
        titleText: '选择访问条件',
        options: items,
        onSelect: (index: number): void => {
          this.onChooseACForDataBlock(index);
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true
    });
    this.dataBlockDialogCtrl?.open();
  }

  /**
   * Apply the chosen access conditions to the selected data block.
   */
  private onChooseACForDataBlock(rowNr: number): void {
    // Change button text to selected access conditions.
    this.setDataBlockButtonText(this.selectedBlock,
      this.getResourceForDataBlocksByRowNr(rowNr));
    // Set access condition bits for this block.
    const acBits: number[] | null =
      this.acRowNrToACBits(rowNr, false);
    if (acBits !== null) {
      this.acMatrix[0][this.selectedBlock] = acBits[0];
      this.acMatrix[1][this.selectedBlock] = acBits[1];
      this.acMatrix[2][this.selectedBlock] = acBits[2];
    }
  }

  // ---------------- Clipboard ----------------

  /**
   * Copy the access conditions hex string to the clipboard.
   */
  private onCopyToClipboard(): void {
    NfcService.copyToClipboard(this.acText, true);
  }

  /**
   * Paste the content of the clipboard (if plain text) to the
   * access conditions input (truncated to the max. length of 6
   * characters, like the Android EditText with maxLength=6).
   */
  private onPasteFromClipboard(): void {
    const text: string | null = NfcService.getFromClipboard();
    if (text !== null) {
      if (text.length > 6) {
        this.acText = text.substring(0, 6);
      } else {
        this.acText = text;
      }
    }
  }

  // ---------------- Helper ----------------

  /** Set the button text of the data block with the given number. */
  private setDataBlockButtonText(blockNr: number, text: string): void {
    if (blockNr === 0) {
      this.block0Text = text;
    } else if (blockNr === 1) {
      this.block1Text = text;
    } else if (blockNr === 2) {
      this.block2Text = text;
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // Access conditions hex string ("ACs") + copy/paste.
        Row() {
          Text('访问条件')
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .margin({ right: 5 })
          TextInput({ text: this.acText, placeholder: '十六进制，3 字节' })
            .maxLength(6)
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .placeholderColor(MctTheme.fgSecondary)
            .placeholderFont({ size: 14 })
            .caretColor(MctTheme.accent)
            .backgroundColor(MctTheme.inputBg)
            .borderRadius(4)
            .layoutWeight(1)
            .onChange((value: string): void => {
              this.acText = value;
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
        .padding(5)
        .alignItems(VerticalAlign.Center)

        // Decode/Encode.
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
        .padding({ left: 5, right: 5, top: 10, bottom: 10 })

        // Blocks.
        Scroll() {
          Column() {
            // Step 1: Sector Trailer.
            Text('步骤 1：为扇区尾块选择访问条件')
              .fontSize(12)
              .fontColor(MctTheme.fgSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .margin({ bottom: 2 })
            Text('块 3（15）- 扇区尾块：')
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
            Button() {
              Text(this.block3Text)
                .fontSize(13)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .lineHeight(18)
            }
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .width('100%')
            .margin({ top: 2, bottom: 8 })
            .onClick(() => {
              this.showSectorTrailerDialog();
            })

            // Step 2: Data blocks.
            Text('步骤 2：为数据块选择访问条件')
              .fontSize(12)
              .fontColor(MctTheme.fgSecondary)
              .width('100%')
              .textAlign(TextAlign.Start)
              .margin({ top: 2, bottom: 2 })
            Text('块 0（0-4）：')
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
            Button() {
              Text(this.block0Text)
                .fontSize(13)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .lineHeight(18)
            }
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .width('100%')
            .margin({ top: 2, bottom: 8 })
            .onClick(() => {
              this.showDataBlockDialog(0);
            })
            Text('块 1（5-9）：')
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
            Button() {
              Text(this.block1Text)
                .fontSize(13)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .lineHeight(18)
            }
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .width('100%')
            .margin({ top: 2, bottom: 8 })
            .onClick(() => {
              this.showDataBlockDialog(1);
            })
            Text('块 2（10-14）：')
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
            Button() {
              Text(this.block2Text)
                .fontSize(13)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .lineHeight(18)
            }
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .width('100%')
            .margin({ top: 2, bottom: 8 })
            .onClick(() => {
              this.showDataBlockDialog(2);
            })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(10)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('访问条件工具')
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
export function AccessConditionToolBuilder() {
  AccessConditionToolPage()
}
