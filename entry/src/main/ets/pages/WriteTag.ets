/**
 * Write Tag (port of de.syss.MifareClassicTool.Activities.WriteTag,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Write data to a tag. The user can choose to write a single block of
 * data, to write a dump to a tag providing its keys, to factory format
 * a tag, to write value blocks (via incr./decr./transfer or via
 * transfer & restore) or to clone a UID.
 */

import { tag } from '@kit.ConnectivityKit';
import { Operation, SectorKeys } from '../common/MctTypes';
import { HexUtils } from '../common/HexUtils';
import { MctFiles } from '../common/MctFiles';
import { McReader } from '../common/McReader';
import { MifareUtils } from '../common/MifareUtils';
import { NfcService } from '../common/NfcService';
import { MctDialog } from '../common/ui/MctDialog';
import { MctTheme } from '../common/ui/MctTheme';
import { FileChooserParams } from './FileChooser';
import { KeyMapCreatorParams } from './KeyMapCreator';

/** Params for this page (dump from the Dump Editor). */
export class WriteTagParams {
  dump: string[] | null = null;
}

/** One entry ("position" + "reason") of the write issues dialog list. */
class WriteTagIssue {
  position: string = '';
  reason: string = '';
}

// Pending KeyMapCreator operations (Android request codes CKM_*).
const WT_OP_NONE: number = 0;
const WT_OP_WRITE_DUMP: number = 2;
const WT_OP_WRITE_BLOCK: number = 3;
const WT_OP_FACTORY_FORMAT: number = 4;
const WT_OP_WRITE_NEW_VALUE: number = 5;
const WT_OP_VALUE_TRANSFER_RESTORE: number = 6;

/** Maximum sector count / blocks per sector (KeyMapCreator constants). */
const WT_MAX_SECTOR_COUNT: number = 40;
const WT_MAX_BLOCK_COUNT_PER_SECTOR: number = 16;

/** Sector chooser dialog (dialog_write_sectors.xml). */
@CustomDialog
struct WriteTagSectorChooserDialog {
  controller?: CustomDialogController;
  sectors: number[] = [];
  onConfirm: (unchecked: number[]) => void = (unchecked: number[]): void => {};
  @State checkedStates: boolean[] = [];

  aboutToAppear(): void {
    const states: boolean[] = [];
    for (let i = 0; i < this.sectors.length; i++) {
      states.push(true);
    }
    this.checkedStates = states;
  }

  private setAllStates(checked: boolean): void {
    const states: boolean[] = [];
    for (let i = 0; i < this.sectors.length; i++) {
      states.push(checked);
    }
    this.checkedStates = states;
  }

  build() {
    Column() {
      Text('写入扇区')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text('选择要写入的扇区：')
        .fontSize(15)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 10 })
      Row({ space: 8 }) {
        Button('全选')
          .fontSize(13)
          .height(32)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.setAllStates(true);
          })
        Button('全不选')
          .fontSize(13)
          .height(32)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .layoutWeight(1)
          .onClick(() => {
            this.setAllStates(false);
          })
      }
      .width('100%')
      .margin({ top: 10 })
      Scroll() {
        Column() {
          ForEach(this.sectors, (sector: number, index: number) => {
            Row() {
              Checkbox()
                .select(this.checkedStates[index])
                .selectedColor(MctTheme.accent)
                .width(20)
                .height(20)
                .onChange((value: boolean): void => {
                  this.checkedStates[index] = value;
                })
              Text('扇区 ' + sector.toString())
                .fontSize(15)
                .fontColor(MctTheme.fg)
                .margin({ left: 10 })
                .layoutWeight(1)
                .onClick(() => {
                  const current: boolean = this.checkedStates[index];
                  this.checkedStates[index] = !current;
                })
            }
            .width('100%')
            .padding({ top: 4, bottom: 4 })
          }, (sector: number): string => 'wt_sector_' + sector.toString())
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 280 })
      .margin({ top: 6 })
      Divider()
        .color(MctTheme.buttonBorder)
        .margin({ top: 10 })
      Row() {
        Text('取消')
          .fontSize(16)
          .fontColor(MctTheme.fgSecondary)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
          })
        Text('确定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(MctTheme.accent)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            const unchecked: number[] = [];
            for (let i = 0; i < this.sectors.length; i++) {
              if (!this.checkedStates[i]) {
                unchecked.push(this.sectors[i]);
              }
            }
            this.onConfirm(unchecked);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 4 })
    }
    .padding(20)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('88%')
  }
}

/** Write issues dialog (skip or cancel the whole write process). */
@CustomDialog
struct WriteTagIssuesDialog {
  controller?: CustomDialogController;
  issues: WriteTagIssue[] = [];
  onSkip: () => void = (): void => {};

  build() {
    Column() {
      Text('写入问题')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text('检测到会影响写入标签的问题。请查看下方完整列表！')
        .fontSize(15)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 12 })
        .lineHeight(21)
      Scroll() {
        Column() {
          ForEach(this.issues, (issue: WriteTagIssue, index: number) => {
            Column() {
              Text(issue.position)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
              Text(issue.reason)
                .fontSize(14)
                .fontColor(MctTheme.fgSecondary)
                .width('100%')
                .textAlign(TextAlign.Start)
                .margin({ top: 2 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ top: 6, bottom: 6 })
          }, (issue: WriteTagIssue, index: number): string => 'wt_issue_' + index.toString())
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: 300 })
      .margin({ top: 8 })
      Divider()
        .color(MctTheme.buttonBorder)
        .margin({ top: 12 })
      Row() {
        Text('取消写入')
          .fontSize(16)
          .fontColor(MctTheme.fgSecondary)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
          })
        Text('尽可能多地写入')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(MctTheme.accent)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
            this.onSkip();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 4 })
    }
    .padding(20)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('90%')
  }
}

/** "Don't remove the tag" progress dialog while writing. */
@CustomDialog
struct WriteTagWaitDialog {
  controller?: CustomDialogController;

  build() {
    Column() {
      Text('正在写入…')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      Row() {
        LoadingProgress()
          .width(38)
          .height(38)
          .color(MctTheme.accent)
        Text('正在写入标签…\n（请勿移除标签）')
          .fontSize(17)
          .fontColor(MctTheme.fg)
          .margin({ left: 16 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 18 })
    }
    .padding(24)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('78%')
  }
}

@Component
struct WriteTagPage {
  // Write mode (radio selection).
  @State writeMode: number = 0;
  // Write Block inputs.
  @State sectorInputBlock: string = '';
  @State blockInputBlock: string = '';
  @State dataInput: string = '';
  // Write Dump options.
  @State showDumpOptions: boolean = false;
  @State enableStaticAC: boolean = false;
  @State staticACInput: string = '08778F';
  @State writeManufBlockChecked: boolean = false;
  @State dumpFromEditorActive: boolean = false;
  // Value Block inputs.
  @State sectorInputVB: string = '';
  @State blockInputVB: string = '';
  @State newValueInputVB: string = '';
  @State increaseVB: boolean = true;
  // Transfer & Restore inputs.
  @State vtrStageSectorInput: string = '';
  @State vtrStageBlockInput: string = '';
  @State vtrDestSectorInput: string = '';
  @State vtrDestBlockInput: string = '';
  @State vtrValueInput: string = '';
  @State vtrAddrInput: string = '';

  private pathStack: NavPathStack = new NavPathStack();
  private dumpWithPos: Map<number, Map<number, number[]>> = new Map<number, Map<number, number[]>>();
  private keysFromDump: Set<string> = new Set<string>();
  private dumpFromEditor: string[] | null = null;
  private pendingOp: number = WT_OP_NONE;
  private keyMapBeforePush: Map<number, SectorKeys> | null = null;
  private pendingDumpFile: string | null = null;
  private dialogCtrl: CustomDialogController | null = null;
  private sectorChooserCtrl: CustomDialogController | null = null;
  private issuesCtrl: CustomDialogController | null = null;
  private waitCtrl: CustomDialogController | null = null;

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Small helpers ----------------

  private maxOf(values: number[]): number {
    let max: number = values[0];
    for (let i = 1; i < values.length; i++) {
      if (values[i] > max) {
        max = values[i];
      }
    }
    return max;
  }

  private minOf(values: number[]): number {
    let min: number = values[0];
    for (let i = 1; i < values.length; i++) {
      if (values[i] < min) {
        min = values[i];
      }
    }
    return min;
  }

  private copyBlockMap(src: Map<number, number[]>): Map<number, number[]> {
    const dest: Map<number, number[]> = new Map<number, number[]>();
    const keys: number[] = Array.from(src.keys());
    for (let i = 0; i < keys.length; i++) {
      const blocks: number[] | undefined = src.get(keys[i]);
      if (blocks !== undefined) {
        dest.set(keys[i], blocks);
      }
    }
    return dest;
  }

  private showMessageDialog(titleText: string, messageText: string,
    button1Text: string, button1Action: () => void, button2Text: string): void {
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: titleText,
        messageText: messageText,
        button1Text: button1Text,
        button1Action: (checked: boolean): void => {
          button1Action();
        },
        button2Text: button2Text
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        action.dismiss();
      }
    });
    this.dialogCtrl.open();
  }

  /** Common.isHexAnd16Byte equivalent (with error toasts). */
  private isHexAnd16Byte(hexString: string): boolean {
    if (!HexUtils.isHex(hexString)) {
      NfcService.toast('错误：数据必须为十六进制（0-9 和 A-F）', true);
      return false;
    }
    if (hexString.length !== 32) {
      NfcService.toast('错误：数据长度必须为 16 字节（32 个字符）', true);
      return false;
    }
    return true;
  }

  /** Common.isValidDumpErrorToast equivalent. */
  private isValidDumpErrorToast(errorCode: number): void {
    if (errorCode === 1) {
      NfcService.toast('错误：部分扇区的块数（行数）不是 4 或 16', true);
    } else if (errorCode === 2) {
      NfcService.toast('错误：部分块包含无效数据（非十六进制）', true);
    } else if (errorCode === 3) {
      NfcService.toast('错误：部分块的长度不是 16 字节（32 个字符）', true);
    } else if (errorCode === 4) {
      NfcService.toast('错误：扇区超出范围（< 0 或 > 39）', true);
    } else if (errorCode === 5) {
      NfcService.toast('错误：存在重复的扇区编号', true);
    } else if (errorCode === 6) {
      NfcService.toast('错误：转储为空', true);
    }
  }

  /** Check the user input of a sector and a block field. */
  private checkSectorAndBlock(sectorText: string, blockText: string): boolean {
    if (sectorText.length === 0 || blockText.length === 0) {
      // Error, location not fully set.
      NfcService.toast('错误：未指定块或扇区', true);
      return false;
    }
    const sectorNr: number = Number.parseInt(sectorText, 10);
    const blockNr: number = Number.parseInt(blockText, 10);
    if (sectorNr > WT_MAX_SECTOR_COUNT - 1 || sectorNr < 0) {
      // Error, sector is out of range for any MIFARE tag.
      NfcService.toast('错误：扇区超出范围', true);
      return false;
    }
    if (blockNr > WT_MAX_BLOCK_COUNT_PER_SECTOR - 1 || blockNr < 0) {
      // Error, block is out of range for any MIFARE tag.
      NfcService.toast('错误：块超出范围', true);
      return false;
    }
    return true;
  }

  // ---------------- Write Block ----------------

  private onWriteBlock(): void {
    // Check input.
    if (!this.checkSectorAndBlock(this.sectorInputBlock, this.blockInputBlock)) {
      return;
    }
    const data: string = this.dataInput;
    if (!this.isHexAnd16Byte(data)) {
      return;
    }
    const sector: number = Number.parseInt(this.sectorInputBlock, 10);
    const block: number = Number.parseInt(this.blockInputBlock, 10);
    if (!this.isSectorInRange(true)) {
      return;
    }
    if (block === 3 || block === 15) {
      // Sector Trailer.
      const acCheck: number = this.checkAccessConditions(data, true);
      if (acCheck === 1) {
        // Invalid Access Conditions. Abort.
        return;
      }
      // Warning. This is a sector trailer.
      this.showMessageDialog('写入扇区块尾',
        '您即将写入扇区块尾。如果访问条件本身被标记为只读，'
        + '更改将无法撤销。'
        + '写入错误数据可能会对标签造成不可修复的损坏。',
        '我知道我在做什么',
        (): void => {
          this.createKeyMapForBlock(sector, false);
        },
        '取消');
    } else if (sector === 0 && block === 0) {
      // Manufacturer block. Is block 0 valid? Display warning.
      const block0Check: number = this.checkBlock0(data, true);
      if (block0Check === 1 || block0Check === 2) {
        // BCC not valid. Abort.
        return;
      }
      // Warning. Writing to manufacturer block.
      this.showWriteManufInfo(true);
    } else {
      // Normal data block.
      this.createKeyMapForBlock(sector, false);
    }
  }

  /** Check if block 0 data is valid. 0=OK, 1=no tag, 2=BCC invalid, 3=SAK/ATQA invalid. */
  private checkBlock0(block0: string, showToasts: boolean): number {
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      // Error. There is no tag.
      return 1;
    }
    const tagSize: number = reader.getSize();
    reader.close();
    const uid: number[] | null = NfcService.getUID();
    const uidLen: number = uid !== null ? uid.length : 0;

    // BCC.
    if (uidLen === 4) {
      const bccBytes: number[] | null = HexUtils.hex2Bytes(block0.substring(8, 10));
      const uidBytes: number[] | null = HexUtils.hex2Bytes(block0.substring(0, 8));
      if (bccBytes !== null && uidBytes !== null && uidBytes.length === 4
        && !HexUtils.isValidBcc(uidBytes, bccBytes[0])) {
        // Error. BCC is not valid. Show error message.
        if (showToasts) {
          NfcService.toast('错误：块 0 的 BCC 无效', true);
        }
        return 2;
      }
    }

    // SAK & ATQA.
    if (!MifareUtils.isValidBlock0(block0, uidLen, tagSize, true)) {
      if (showToasts) {
        NfcService.toast('警告：块 0 可能包含无效数据 (BCC/SAK/ATQA/UID0)', true);
      }
      return 3;
    }
    // Everything was O.K.
    return 0;
  }

  /** Check the ACs of a Sector Trailer. 0=OK, 1=invalid, 2=irreversible. */
  private checkAccessConditions(sectorTrailer: string, showToasts: boolean): number {
    // Check if Access Conditions are valid.
    const acBytes: number[] | null = HexUtils.hex2Bytes(sectorTrailer.substring(12, 18));
    const acMatrix: number[][] | null = MifareUtils.acBytesToACMatrix(acBytes);
    if (acMatrix === null) {
      // Error. Invalid ACs.
      if (showToasts) {
        NfcService.toast('错误：访问条件无效', true);
      }
      return 1;
    }
    // Check if Access Conditions are irreversible.
    const keyBReadable: boolean = MifareUtils.isKeyBReadable(
      acMatrix[0][3], acMatrix[1][3], acMatrix[2][3]);
    const writeAC: number = MifareUtils.getOperationRequirements(
      acMatrix[0][3], acMatrix[1][3], acMatrix[2][3],
      Operation.WriteAC, true, keyBReadable);
    if (writeAC === 0) {
      // Warning. Access Conditions can not be changed after writing.
      if (showToasts) {
        NfcService.toast('警告：访问条件将不可逆', true);
      }
      return 2;
    }
    return 0;
  }

  /** Display information about writing to the manufacturer block. */
  private showWriteManufInfo(createKeyMap: boolean): void {
    const message: string = '在原版 MIFARE Classic 标签上无法写入扇区 0 的第一个'
      + '块。\n\n'
      + '请确保您使用的是支持写入制造商块的“魔法标签”'
      + '(2nd gen/gen2)。\n\n'
      + '在某些标签上，块 0 中 UID 之后的数据代表 '
      + 'BCC、SAK 和 ATQA。请确保这些值正确无误。向块 0 写入错误'
      + '数据可能会损坏标签。\n\n'
      + '更多信息请查看“帮助和信息”中的“写入标签”'
      + '部分。';
    const button1Text: string = createKeyMap ? '我知道我在做什么' : '确定';
    const button2Text: string = createKeyMap ? '取消' : '';
    this.showMessageDialog('写入制造商块', message, button1Text,
      (): void => {
        if (createKeyMap) {
          this.createKeyMapForBlock(0, false);
        }
      }, button2Text);
  }

  /** Show the KeyMapCreator for a single sector (block or value block write). */
  private createKeyMapForBlock(sector: number, isValueBlock: boolean): void {
    const params: KeyMapCreatorParams = new KeyMapCreatorParams();
    params.keysDir = MctFiles.getKeysDir();
    params.useSectorChooser = false;
    params.sectorFrom = sector;
    params.sectorTo = sector;
    if (isValueBlock) {
      params.buttonText = '开始映射密钥并写入值块';
      this.keyMapBeforePush = NfcService.getKeyMap();
      this.pendingOp = WT_OP_WRITE_NEW_VALUE;
    } else {
      params.buttonText = '开始映射密钥并写入块';
      this.keyMapBeforePush = NfcService.getKeyMap();
      this.pendingOp = WT_OP_WRITE_BLOCK;
    }
    this.pathStack.pushPathByName('keyMapCreator', params);
  }

  /** Start the KeyMapCreator with a predefined range of sectors. */
  private createKeyMapForRange(fromSector: number, toSector: number,
    pendingCode: number, buttonText: string): void {
    const params: KeyMapCreatorParams = new KeyMapCreatorParams();
    params.keysDir = MctFiles.getKeysDir();
    params.useSectorChooser = false;
    params.sectorFrom = Math.min(fromSector, toSector);
    params.sectorTo = Math.max(fromSector, toSector);
    params.buttonText = buttonText;
    this.keyMapBeforePush = NfcService.getKeyMap();
    this.pendingOp = pendingCode;
    this.pathStack.pushPathByName('keyMapCreator', params);
  }

  /** Write the block (after a key map was created). */
  private async writeBlock(): Promise<void> {
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return;
    }
    const sector: number = Number.parseInt(this.sectorInputBlock, 10);
    const block: number = Number.parseInt(this.blockInputBlock, 10);
    const data: number[] | null = HexUtils.hex2Bytes(this.dataInput);
    const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
    if (keyMap === null || !keyMap.has(sector)) {
      reader.close();
      return;
    }
    const keys: SectorKeys | undefined = keyMap.get(sector);
    if (keys === undefined) {
      reader.close();
      return;
    }
    let resultKeyA: number = -1;
    let resultKeyB: number = -1;

    // Write. There are some tags which report a successful write, although
    // the write was not successful. Therefore, we try to write it using
    // both keys. Try key B first.
    if (keys.keyB !== null) {
      resultKeyB = await reader.writeBlock(sector, block, data, keys.keyB, true);
    }
    // Try to write with key A (if there is one).
    if (keys.keyA !== null) {
      resultKeyA = await reader.writeBlock(sector, block, data, keys.keyA, false);
    }

    reader.close();
    let result: number = -1;
    if (resultKeyA === 0 || resultKeyB === 0) {
      result = 0;
    } else if (resultKeyA === 2 || resultKeyB === 2) {
      result = 2;
    } else if (resultKeyA === -1 || resultKeyB === -1) {
      result = -1;
    }

    // Error handling.
    if (result === 2) {
      NfcService.toast('错误：该扇区不包含指定编号的块。', true);
      return;
    }
    if (result === -1) {
      NfcService.toast('错误：块为只读，或无法使用密钥文件中的密钥写入', true);
      return;
    }
    NfcService.toast('数据写入成功', true);
    this.pathStack.pop();
  }

  // ---------------- Write Dump ----------------

  private onWriteDump(): void {
    // Check the static Access Condition option.
    if (this.enableStaticAC) {
      const ac: string = this.staticACInput;
      if (!/^[0-9A-Fa-f]+$/.test(ac)) {
        // Error, not hex.
        NfcService.toast('错误：访问条件不是十六进制 (0-9, A-F)', true);
        return;
      }
      if (ac.length !== 6) {
        // Error, not 3 byte (6 chars).
        NfcService.toast('错误：访问条件长度必须为 3 字节（6 个字符）', true);
        return;
      }
    }

    if (this.dumpFromEditorActive) {
      // Write dump directly from the dump editor.
      // (Dump has already been chosen.)
      this.checkDumpAndShowSectorChooserDialog(this.dumpFromEditor);
    } else {
      // Show file chooser (chose dump).
      this.pathStack.pushPathByName('fileChooser', new FileChooserParams(
        MctFiles.getDumpsDir(),
        '打开标签转储',
        '选择要写入的转储：',
        '选择转储',
        false,
        (file: string | null): void => {
          if (file !== null) {
            this.pendingDumpFile = file;
          }
        }));
    }
  }

  /** Read the dump and check it (show sector chooser dialog). */
  private readDumpFromFile(pathToDump: string): void {
    const dump: string[] | null = MctFiles.readFileLines(pathToDump, false);
    this.checkDumpAndShowSectorChooserDialog(dump);
  }

  /** Check dump, apply options and show the sector chooser dialog. */
  private checkDumpAndShowSectorChooserDialog(dump: string[] | null): void {
    const err: number = MifareUtils.isValidDump(dump, false);
    if (err !== 0) {
      // Error.
      this.isValidDumpErrorToast(err);
      return;
    }
    if (dump === null) {
      return;
    }
    this.initDumpWithPosAndKeysFromDump(dump);

    // Create and show sector chooser dialog
    // (let the user select the sectors which will be written).
    const sectors: number[] = Array.from(this.dumpWithPos.keys());
    sectors.sort((a: number, b: number): number => a - b);
    this.sectorChooserCtrl = new CustomDialogController({
      builder: WriteTagSectorChooserDialog({
        sectors: sectors,
        onConfirm: (unchecked: number[]): void => {
          this.onSectorChooserConfirm(dump, unchecked);
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        action.dismiss();
      }
    });
    this.sectorChooserCtrl.open();
  }

  /** Positive button of the sector chooser dialog (Android overrides it). */
  private onSectorChooserConfirm(dump: string[], unchecked: number[]): void {
    // Re-Init dumpWithPos in order to remove unwanted sectors.
    this.initDumpWithPosAndKeysFromDump(dump);
    for (let i = 0; i < unchecked.length; i++) {
      this.dumpWithPos.delete(unchecked[i]);
    }
    if (this.dumpWithPos.size === 0) {
      // Error. There is nothing to write.
      NfcService.toast('没有剩余可写入的内容', true);
      return;
    }
    // Check if last sector is out of range.
    if (!this.isSectorInRange(false)) {
      return;
    }
    // Create key map.
    this.createKeyMapForDump();
    this.sectorChooserCtrl?.close();
  }

  /** Check if the chosen sector or last sector of a dump is in range. */
  private isSectorInRange(isWriteBlock: boolean): boolean {
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return false;
    }
    const lastValidSector: number = reader.getSectorCount() - 1;
    reader.close();
    // Initialize last sector.
    let lastSector: number;
    if (isWriteBlock) {
      lastSector = Number.parseInt(this.sectorInputBlock, 10);
    } else {
      lastSector = this.maxOf(Array.from(this.dumpWithPos.keys()));
    }
    // Is last sector in range?
    if (lastSector > lastValidSector) {
      // Error. Tag too small for dump.
      NfcService.toast('错误：标签容量过小（扇区超出范围）', true);
      return false;
    }
    return true;
  }

  /** Initialize dumpWithPos and keysFromDump with the data from a dump. */
  private initDumpWithPosAndKeysFromDump(dump: string[]): void {
    this.dumpWithPos = new Map<number, Map<number, number[]>>();
    this.keysFromDump = new Set<string>();
    let sector: number = 0;
    let block: number = 0;
    // Transform the simple dump array into a structure (dumpWithPos)
    // where the sector and block information are known additionally.
    // Blocks containing unknown data ("-") are dropped.
    for (let i = 0; i < dump.length; i++) {
      if (dump[i].startsWith('+')) {
        const tmp: string[] = dump[i].split(': ');
        sector = Number.parseInt(tmp[tmp.length - 1], 10);
        block = 0;
        this.dumpWithPos.set(sector, new Map<number, number[]>());
      } else {
        if (i + 1 === dump.length || dump[i + 1].startsWith('+')) {
          // Is sector trailer. Get keys.
          const keyA: string = dump[i].substring(0, 12);
          const keyB: string = dump[i].substring(20);
          if (!keyA.includes('-')) {
            this.keysFromDump.add(keyA);
          }
          if (!keyB.includes('-')) {
            this.keysFromDump.add(keyB);
          }
        }
        if (!dump[i].includes('-')) {
          // Use static Access Conditions for all sectors?
          if (this.enableStaticAC
            && (i + 1 === dump.length || dump[i + 1].startsWith('+'))) {
            // This is a Sector Trailer. Replace its ACs
            // with the static ones.
            dump[i] = dump[i].substring(0, 12)
              + this.staticACInput
              + dump[i].substring(18);
          }
          const blockBytes: number[] | null = HexUtils.hex2Bytes(dump[i]);
          const sectorBlocks: Map<number, number[]> | undefined =
            this.dumpWithPos.get(sector);
          if (blockBytes !== null && sectorBlocks !== undefined) {
            sectorBlocks.set(block, blockBytes);
          }
          block++;
        } else {
          block++;
        }
      }
    }
  }

  /** Create a key map for the dump (dumpWithPos). */
  private createKeyMapForDump(): void {
    const sectors: number[] = Array.from(this.dumpWithPos.keys());
    const params: KeyMapCreatorParams = new KeyMapCreatorParams();
    params.keysDir = MctFiles.getKeysDir();
    params.useSectorChooser = false;
    params.sectorFrom = this.minOf(sectors);
    params.sectorTo = this.maxOf(sectors);
    params.buttonText = '开始映射密钥并写入转储';
    this.saveKeysFromDumpToTempKeyFile();
    params.useKeysFromDump = true;
    this.keyMapBeforePush = NfcService.getKeyMap();
    this.pendingOp = WT_OP_WRITE_DUMP;
    this.pathStack.pushPathByName('keyMapCreator', params);
  }

  /** Save keys from dump to a temporary key file for the KeyMapCreator. */
  private saveKeysFromDumpToTempKeyFile(): void {
    if (this.keysFromDump.size === 0) {
      return;
    }
    const keys: string[] = Array.from(this.keysFromDump);
    const ok: boolean = MctFiles.writeLines(
      MctFiles.getFile(MctFiles.TMP_DIR + '/keys_from_dump.keys'), keys);
    if (!ok) {
      NfcService.toast('错误：保存数据时出错', true);
    }
  }

  /** Check if the tag is suitable for the dump (4-step check). */
  private async checkDumpAgainstTag(): Promise<void> {
    // Create reader.
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      NfcService.toast('错误：检查转储时标签丢失', true);
      return;
    }

    // Check if tag is correct size for dump.
    const dumpSectors: number[] = Array.from(this.dumpWithPos.keys());
    if (reader.getSectorCount() - 1 < this.maxOf(dumpSectors)) {
      // Error. Tag too small for dump.
      NfcService.toast('错误：标签容量过小（扇区超出范围）', true);
      reader.close();
      return;
    }

    // Check if tag is writable on needed blocks.
    // Reformat for reader.isWritableOnPositions(...).
    const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
    if (keyMap === null) {
      reader.close();
      return;
    }
    const dataPos: Map<number, number[]> = new Map<number, number[]>();
    for (let i = 0; i < dumpSectors.length; i++) {
      const sector: number = dumpSectors[i];
      const blocksMap: Map<number, number[]> | undefined =
        this.dumpWithPos.get(sector);
      if (blocksMap === undefined) {
        continue;
      }
      dataPos.set(sector, Array.from(blocksMap.keys()));
    }
    const writeOnPos: Map<number, Map<number, number> | null> | null =
      await reader.isWritableOnPositions(dataPos, keyMap);
    reader.close();

    if (writeOnPos === null) {
      // Error while checking for keys with write privileges.
      NfcService.toast('错误：检查转储时标签丢失', true);
      return;
    }

    // Skip dialog:
    // Build a dialog showing all sectors and blocks containing data
    // that can not be overwritten with the reason why they are not
    // writable. The user can chose to skip all these blocks/sectors
    // or to cancel the whole write procedure.
    const list: WriteTagIssue[] = [];
    const writeOnPosSafe: Map<number, Map<number, number>> =
      new Map<number, Map<number, number>>();

    // Check for keys that are missing completely (dumpWithPos vs. keyMap).
    const sectors: number[] = [];
    for (let i = 0; i < dumpSectors.length; i++) {
      const sector: number = dumpSectors[i];
      if (!keyMap.has(sector)) {
        // Problem. Keys for sector not found.
        this.addToList(list, '扇区：' + sector.toString(), '密钥 A 和密钥 B 均未知');
      } else {
        sectors.push(sector);
      }
    }

    // Check for keys with write privileges that are missing (writeOnPos
    // vs. keyMap). Check for blocks (block-parts) that are read-only.
    // Check for issues of block 0 of the dump about to be written.
    // Check the Access Conditions of the dump about to be written.
    for (let s = 0; s < sectors.length; s++) {
      const sector: number = sectors[s];
      const sectorWriteInfo: Map<number, number> | null | undefined =
        writeOnPos.get(sector);
      if (sectorWriteInfo === null || sectorWriteInfo === undefined) {
        // Error. Sector is dead (IO Error) or ACs are invalid.
        this.addToList(list, '扇区：' + sector.toString(),
          '访问条件无效或扇区已损坏 :(');
        continue;
      }
      const keys: SectorKeys | undefined = keyMap.get(sector);
      if (keys === undefined) {
        continue;
      }
      const blocksMap: Map<number, number[]> | undefined =
        this.dumpWithPos.get(sector);
      if (blocksMap === undefined) {
        continue;
      }
      const blocks: number[] = Array.from(blocksMap.keys());
      for (let b = 0; b < blocks.length; b++) {
        const block: number = blocks[b];
        let isSafeForWriting: boolean = true;
        const position: string = '扇区：' + sector.toString()
          + '，块：' + block.toString();

        // Special block 0 checks.
        if (!this.writeManufBlockChecked && sector === 0 && block === 0) {
          // Block 0 is read-only. This is normal. Skip.
          continue;
        } else if (this.writeManufBlockChecked && sector === 0 && block === 0) {
          // Block 0 should be written. Check it.
          const block0Bytes: number[] | undefined =
            this.dumpWithPos.get(0)?.get(0);
          const block0: string = HexUtils.bytes2Hex(block0Bytes ?? null);
          const block0Check: number = this.checkBlock0(block0, false);
          if (block0Check === 1) {
            NfcService.toast('错误：检查转储时标签丢失', true);
            return;
          }
          if (block0Check === 2) {
            // BCC not valid. Abort.
            NfcService.toast('错误：块 0 的 BCC 无效', true);
            return;
          }
          if (block0Check === 3) {
            this.addToList(list, position,
              '警告：块 0 可能包含无效数据 (BCC/SAK/ATQA/UID0)');
          }
        }

        // Special Access Conditions checks.
        if ((sector < 31 && block === 3) || (sector >= 31 && block === 15)) {
          const trailerBytes: number[] | undefined =
            this.dumpWithPos.get(sector)?.get(block);
          const sectorTrailer: string = HexUtils.bytes2Hex(trailerBytes ?? null);
          const acCheck: number = this.checkAccessConditions(sectorTrailer, false);
          if (acCheck === 1) {
            // Access Conditions not valid. Abort.
            NfcService.toast('错误：访问条件无效', true);
            return;
          }
          if (acCheck === 2) {
            this.addToList(list, position,
              '警告：访问条件将不可逆');
          }
        }

        // Normal write privileges checks.
        const writeInfoValue: number | undefined = sectorWriteInfo.get(block);
        if (writeInfoValue === undefined) {
          continue;
        }
        let writeInfo: number = writeInfoValue;
        if (writeInfo === 0) {
          // Problem. Block is read-only.
          this.addToList(list, position, '块为只读');
          isSafeForWriting = false;
        } else if (writeInfo === 1) {
          if (keys.keyA === null) {
            // Problem. Key with write privileges (A) not known.
            this.addToList(list, position, '具有写入权限的密钥 (A) 未知');
            isSafeForWriting = false;
          }
        } else if (writeInfo === 2) {
          if (keys.keyB === null) {
            // Problem. Key with write privileges (B) not known.
            this.addToList(list, position, '具有写入权限的密钥 (B) 未知');
            isSafeForWriting = false;
          }
        } else if (writeInfo === 3) {
          // No Problem. Both keys have write privileges.
          // Set to key A or B depending on which one is available.
          writeInfo = keys.keyA !== null ? 1 : 2;
        } else if (writeInfo === 4) {
          if (keys.keyA === null) {
            // Problem. Key with write privileges (A) not known.
            this.addToList(list, position, '具有写入权限的密钥 (A) 未知');
            isSafeForWriting = false;
          } else {
            // Problem. ACs are read-only.
            this.addToList(list, position, '访问条件为只读');
          }
        } else if (writeInfo === 5) {
          if (keys.keyB === null) {
            // Problem. Key with write privileges (B) not known.
            this.addToList(list, position, '具有写入权限的密钥 (B) 未知');
            isSafeForWriting = false;
          } else {
            // Problem. ACs are read-only.
            this.addToList(list, position, '访问条件为只读');
          }
        } else if (writeInfo === 6) {
          if (keys.keyB === null) {
            // Problem. Key with write privileges (B) not known.
            this.addToList(list, position, '具有写入权限的密钥 (B) 未知');
            isSafeForWriting = false;
          } else {
            // Problem. Keys are read-only.
            this.addToList(list, position, '密钥 A 和密钥 B 均为只读');
          }
        } else if (writeInfo === -1) {
          // Error. Some strange error occurred. Maybe due to some
          // corrupted ACs...
          this.addToList(list, position, '发生了一些奇怪的错误 :(');
          isSafeForWriting = false;
        }
        // Add if safe for writing.
        if (isSafeForWriting) {
          const safeSector: Map<number, number> | undefined =
            writeOnPosSafe.get(sector);
          if (safeSector === undefined) {
            // Create sector.
            const blockInfo: Map<number, number> = new Map<number, number>();
            blockInfo.set(block, writeInfo);
            writeOnPosSafe.set(sector, blockInfo);
          } else {
            // Add to sector.
            safeSector.set(block, writeInfo);
          }
        }
      }
    }

    // Show skip/cancel dialog (if needed).
    if (list.length > 0) {
      // If the user skips all sectors/blocks that are not writable,
      // the writeDump() method will be called.
      this.issuesCtrl = new CustomDialogController({
        builder: WriteTagIssuesDialog({
          issues: list,
          onSkip: (): void => {
            this.writeDump(writeOnPosSafe, keyMap);
          }
        }),
        alignment: DialogAlignment.Center,
        autoCancel: false,
        customStyle: true,
        onWillDismiss: (action: DismissDialogAction): void => {
          action.dismiss();
        }
      });
      this.issuesCtrl.open();
    } else {
      // Write.
      this.writeDump(writeOnPosSafe, keyMap);
    }
  }

  /** Add an item to the list of all blocks with write issues. */
  private addToList(list: WriteTagIssue[], position: string, reason: string): void {
    const item: WriteTagIssue = new WriteTagIssue();
    item.position = position;
    item.reason = reason;
    list.push(item);
  }

  /** Write the dump to the tag (with a 2-attempt retry per block). */
  private async writeDump(writeOnPos: Map<number, Map<number, number>>,
    keyMap: Map<number, SectorKeys>): Promise<void> {
    // Check for write data.
    if (writeOnPos.size === 0) {
      // Nothing to write. Exit.
      NfcService.toast('没有剩余可写入的内容', true);
      return;
    }

    // Create reader.
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return;
    }

    // Display "don't remove" warning.
    this.waitCtrl = new CustomDialogController({
      builder: WriteTagWaitDialog(),
      alignment: DialogAlignment.Center,
      customStyle: true
    });
    this.waitCtrl.open();

    // Write dump to tag.
    const sectors: number[] = Array.from(writeOnPos.keys());
    for (let s = 0; s < sectors.length; s++) {
      const sector: number = sectors[s];
      const keys: SectorKeys | undefined = keyMap.get(sector);
      if (keys === undefined) {
        continue;
      }
      const blockMap: Map<number, number> | undefined = writeOnPos.get(sector);
      if (blockMap === undefined) {
        continue;
      }
      const blocks: number[] = Array.from(blockMap.keys());
      for (let b = 0; b < blocks.length; b++) {
        const block: number = blocks[b];
        // Select key with write privileges.
        const wi: number = blockMap.get(block) ?? 0;
        let writeKey: number[] | null = null;
        let useAsKeyB: boolean = true;
        if (wi === 1 || wi === 4) {
          writeKey = keys.keyA; // Write with key A.
          useAsKeyB = false;
        } else if (wi === 2 || wi === 5 || wi === 6) {
          writeKey = keys.keyB; // Write with key B.
        }
        const blockData: number[] | null =
          this.dumpWithPos.get(sector)?.get(block) ?? null;

        // Write block.
        // Writing multiple blocks consecutively sometimes fails.
        // Retrying to write also works. This why the ugly workaround
        // of trying to write at least two times was added.
        let result: number = 0;
        for (let attempt = 0; attempt < 2; attempt++) {
          result = await reader.writeBlock(sector, block, blockData,
            writeKey ?? [], useAsKeyB);
          if (result === 0) {
            break;
          }
        }

        if (result !== 0) {
          // Error. Some error while writing.
          NfcService.toast('错误：写入时发生错误。（情况可能不妙。）', true);
          reader.close();
          this.waitCtrl?.close();
          return;
        }
      }
    }
    // Finished writing.
    reader.close();
    this.waitCtrl?.close();
    NfcService.toast('数据写入成功', true);
    this.pathStack.pop();
  }

  // ---------------- Clone UID ----------------

  private onCloneUid(): void {
    // Show the clone UID tool.
    this.pathStack.pushPathByName('cloneUidTool', null);
  }

  // ---------------- Factory Format ----------------

  private onFactoryFormat(): void {
    // Show key map creator.
    const params: KeyMapCreatorParams = new KeyMapCreatorParams();
    params.keysDir = MctFiles.getKeysDir();
    params.useSectorChooser = false;
    params.sectorFrom = -1;
    params.sectorTo = -1;
    params.buttonText = '开始映射密钥并格式化标签';
    this.keyMapBeforePush = NfcService.getKeyMap();
    this.pendingOp = WT_OP_FACTORY_FORMAT;
    this.pathStack.pushPathByName('keyMapCreator', params);
  }

  /** Create a factory formatted, empty dump matching the current tag size. */
  private createFactoryFormattedDump(): void {
    // This function is directly called after a key map was created.
    // So NfcService.getTag() will return the current present tag
    // (and its size/sector count).
    this.dumpWithPos = new Map<number, Map<number, number[]>>();
    const tagInfo: tag.TagInfo | null = NfcService.getTag();
    let sectors: number = 0;
    if (tagInfo !== null) {
      try {
        const mfc: tag.MifareClassicTag = tag.getMifareClassic(tagInfo);
        if (mfc !== null && mfc !== undefined) {
          sectors = mfc.getSectorCount();
        }
      } catch (e) {
        sectors = 0;
      }
    }
    if (sectors <= 0) {
      return;
    }
    const emptyBlock: number[] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    // Factory (default) MIFARE Classic Access Conditions are: 0xFF0780XX
    // XX = General purpose byte (GPB): Most of the time 0x69. At the end
    // of an tag XX = 0xBC.
    const normalSectorTrailer: number[] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0x07, 0x80, 0x69, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
    const lastSectorTrailer: number[] = [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
      0x07, 0x80, 0xBC, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF];
    // Empty 4 block sector.
    const empty4BlockSector: Map<number, number[]> = new Map<number, number[]>();
    for (let i = 0; i < 3; i++) {
      empty4BlockSector.set(i, emptyBlock);
    }
    empty4BlockSector.set(3, normalSectorTrailer);
    // Empty 16 block sector.
    const empty16BlockSector: Map<number, number[]> = new Map<number, number[]>();
    for (let i = 0; i < 15; i++) {
      empty16BlockSector.set(i, emptyBlock);
    }
    empty16BlockSector.set(15, normalSectorTrailer);
    // Last sector.
    let lastSector: Map<number, number[]>;

    // Sector 0.
    const firstSector: Map<number, number[]> = new Map<number, number[]>();
    firstSector.set(1, emptyBlock);
    firstSector.set(2, emptyBlock);
    firstSector.set(3, normalSectorTrailer);
    this.dumpWithPos.set(0, firstSector);
    // Sector 1 - (max.) 31.
    for (let i = 1; i < sectors && i < 32; i++) {
      this.dumpWithPos.set(i, empty4BlockSector);
    }
    // Sector 32 - 39.
    if (sectors === 40) {
      // Add the large sectors (containing 16 blocks)
      // of a MIFARE Classic 4k tag.
      for (let i = 32; i < sectors && i < 39; i++) {
        this.dumpWithPos.set(i, empty16BlockSector);
      }
      // In the last sector the Sector Trailer is different.
      lastSector = this.copyBlockMap(empty16BlockSector);
      lastSector.set(15, lastSectorTrailer);
    } else {
      // In the last sector the Sector Trailer is different.
      lastSector = this.copyBlockMap(empty4BlockSector);
      lastSector.set(3, lastSectorTrailer);
    }
    this.dumpWithPos.set(sectors - 1, lastSector);
    this.checkDumpAgainstTag();
  }

  // ---------------- Value Block (Incr./Decr.) ----------------

  private onWriteValue(): void {
    // Check input.
    if (!this.checkSectorAndBlock(this.sectorInputVB, this.blockInputVB)) {
      return;
    }
    const sector: number = Number.parseInt(this.sectorInputVB, 10);
    const block: number = Number.parseInt(this.blockInputVB, 10);
    if (block === 3 || block === 15 || (sector === 0 && block === 0)) {
      // Error. Block can't be a Value Block.
      NfcService.toast('错误：所选块不是值块', true);
      return;
    }
    // Integer.parseInt(...) equivalent: a value that is no integer
    // (NaN) or out of int range is "too big".
    const value: number = Number.parseInt(this.newValueInputVB, 10);
    if (isNaN(value) || value > 2147483647 || value < -2147483648) {
      // Error. Value is too big.
      NfcService.toast('错误：值过大', true);
      return;
    }
    this.createKeyMapForBlock(sector, true);
  }

  /** Increment or decrement the Value Block (after a key map was created). */
  private async writeValueBlock(): Promise<void> {
    // Write the new value (incr./decr. + transfer).
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return;
    }
    const value: number = Number.parseInt(this.newValueInputVB, 10);
    const sector: number = Number.parseInt(this.sectorInputVB, 10);
    const block: number = Number.parseInt(this.blockInputVB, 10);
    const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
    if (keyMap === null || !keyMap.has(sector)) {
      reader.close();
      return;
    }
    const keys: SectorKeys | undefined = keyMap.get(sector);
    if (keys === undefined) {
      reader.close();
      return;
    }
    let result: number = -1;

    if (keys.keyB !== null) {
      result = await reader.writeValueBlock(sector, block, value,
        this.increaseVB, keys.keyB, true);
    }
    // Error while writing? Maybe tag has default factory settings ->
    // try to write with key A (if there is one).
    if (result === -1 && keys.keyA !== null) {
      result = await reader.writeValueBlock(sector, block, value,
        this.increaseVB, keys.keyA, false);
    }
    reader.close();

    // Error handling.
    if (result === 2) {
      NfcService.toast('错误：该扇区不包含指定编号的块。', true);
      return;
    }
    if (result === -1) {
      NfcService.toast('错误：不是值块、权限不足或值不正确', true);
      return;
    }
    NfcService.toast('数据写入成功', true);
    this.pathStack.pop();
  }

  // ---------------- Value Block (Transfer & Restore) ----------------

  private onWriteValueBlockTransferRestore(): void {
    // Validate staging.
    if (!this.checkSectorAndBlock(this.vtrStageSectorInput, this.vtrStageBlockInput)) {
      return;
    }
    const stagingSector: number = Number.parseInt(this.vtrStageSectorInput, 10);
    const stagingBlock: number = Number.parseInt(this.vtrStageBlockInput, 10);

    // Validate destination.
    if (!this.checkSectorAndBlock(this.vtrDestSectorInput, this.vtrDestBlockInput)) {
      return;
    }
    const destinationSector: number = Number.parseInt(this.vtrDestSectorInput, 10);
    const destinationBlock: number = Number.parseInt(this.vtrDestBlockInput, 10);

    // Prevent stage block = destination block.
    if (stagingSector === destinationSector && stagingBlock === destinationBlock) {
      NfcService.toast('错误：中转块与目标块不能相同', true);
      return;
    }

    // Prevent trailers and manufacturer block.
    if (stagingBlock === 3 || stagingBlock === 15
      || (stagingSector === 0 && stagingBlock === 0)) {
      NfcService.toast('错误：中转块不能是扇区块尾或制造商块', true);
      return;
    }
    if (destinationBlock === 3 || destinationBlock === 15
      || (destinationSector === 0 && destinationBlock === 0)) {
      NfcService.toast('错误：目标块不能是扇区块尾或制造商块', true);
      return;
    }

    // Validate value (int32).
    if (this.vtrValueInput.length === 0) {
      NfcService.toast('错误：没有可编码的整数', true);
      return;
    }
    const value: number = Number.parseInt(this.vtrValueInput, 10);
    if (isNaN(value)) {
      NfcService.toast('错误：没有可编码的整数', true);
      return;
    }
    if (value > 2147483647) {
      NfcService.toast('错误：值过大', true);
      return;
    }
    if (value < -2147483648) {
      NfcService.toast('错误：值过小', true);
      return;
    }

    // Validate address.
    const addrText: string = this.vtrAddrInput;
    if (!/^[0-9A-Fa-f]{2}$/.test(addrText)) {
      NfcService.toast('错误：地址不是十六进制字节（0-9、A-F，2 个字符）', false);
      return;
    }

    if (stagingSector < destinationSector) {
      this.createKeyMapForRange(stagingSector, destinationSector,
        WT_OP_VALUE_TRANSFER_RESTORE, '开始映射密钥并写入值块');
    } else {
      this.createKeyMapForRange(destinationSector, stagingSector,
        WT_OP_VALUE_TRANSFER_RESTORE, '开始映射密钥并写入值块');
    }
  }

  /** Perform the Value Block transfer/restore operation. */
  private async runValueTransferRestore(): Promise<void> {
    const stagingSector: number = Number.parseInt(this.vtrStageSectorInput, 10);
    const stagingBlock: number = Number.parseInt(this.vtrStageBlockInput, 10);
    const destinationSector: number = Number.parseInt(this.vtrDestSectorInput, 10);
    const destinationBlock: number = Number.parseInt(this.vtrDestBlockInput, 10);
    const value: number = Number.parseInt(this.vtrValueInput, 10);
    const address: number = Number.parseInt(this.vtrAddrInput, 16);
    const vb: number[] = MifareUtils.encodeValueBlock(value, address);

    // Do we have a key for the staging and the destination block?
    const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
    if (keyMap === null) {
      return;
    }
    const stagingKeys: SectorKeys | undefined = keyMap.get(stagingSector);
    const destinationKeys: SectorKeys | undefined = keyMap.get(destinationSector);
    if (stagingKeys === undefined
      || (stagingKeys.keyA === null && stagingKeys.keyB === null)) {
      // No key found for staging block.
      NfcService.toast('错误：未找到中转块的密钥', true);
      return;
    }
    if (destinationKeys === undefined
      || (destinationKeys.keyA === null && destinationKeys.keyB === null)) {
      // No key found for destination block.
      NfcService.toast('错误：未找到目标块的密钥', true);
      return;
    }

    // Do we have write permissions to the staging block?
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    if (reader === null) {
      return;
    }
    const pos: Map<number, number[]> = new Map<number, number[]>();
    if (stagingSector === destinationSector) {
      pos.set(stagingSector, [stagingBlock, destinationBlock]);
    } else {
      pos.set(stagingSector, [stagingBlock]);
      pos.set(destinationSector, [destinationBlock]);
    }
    const writable: Map<number, Map<number, number> | null> | null =
      await reader.isWritableOnPositions(pos, keyMap);
    const stagingInfo: Map<number, number> | null | undefined =
      writable?.get(stagingSector);
    const stagingBlockInfo: number | undefined =
      stagingInfo?.get(stagingBlock);
    if (writable === null || stagingInfo === null || stagingInfo === undefined
      || stagingBlockInfo === undefined) {
      // Authentication error. Should not happen. Exit.
      NfcService.toast('发生了一些奇怪的错误 :(', true);
      return;
    }
    let stagingKey: number[] | null = null;
    let useAsKeyB: boolean = false;
    if (stagingBlockInfo === 1) {
      // Writable with key A.
      if (stagingKeys.keyA === null) {
        NfcService.toast('错误：未找到具有写入权限的中转块密钥', true);
        return;
      }
      stagingKey = stagingKeys.keyA;
    } else if (stagingBlockInfo === 2) {
      // Writable with key B.
      if (stagingKeys.keyB === null) {
        NfcService.toast('错误：未找到具有写入权限的中转块密钥', true);
        return;
      }
      stagingKey = stagingKeys.keyB;
      useAsKeyB = true;
    } else if (stagingBlockInfo === 3) {
      // Writable with key A or B.
      if (stagingKeys.keyB !== null) {
        // Prefer key B for writing.
        stagingKey = stagingKeys.keyB;
        useAsKeyB = true;
      } else {
        stagingKey = stagingKeys.keyA;
      }
    } else {
      // Error. Should never be any other value.
      NfcService.toast('错误：发生了一个奇怪的错误……我不知道为什么 :(\n'
        + '请通过项目页面报告此问题', true);
      return;
    }

    // Do we have restore permissions of the staging block?
    const hasRestorePermission: number =
      await reader.hasDecTransRestPermission(stagingSector, stagingBlock,
        stagingKey ?? [], useAsKeyB);
    if (hasRestorePermission === 0 || hasRestorePermission === -1) {
      // Block has no restore permissions (or an unexpected error happened).
      NfcService.toast('错误：中转块没有恢复权限', true);
      return;
    }

    // Write (try both keys for destination block).
    let result: number = -1;
    const destKeyA: number[] | null = destinationKeys.keyA;
    const destKeyB: number[] | null = destinationKeys.keyB;
    if (destKeyA !== null) {
      result = await reader.valueTransferRestore(stagingSector, stagingBlock,
        destinationSector, destinationBlock, vb, stagingKey ?? [], useAsKeyB,
        destKeyA, false);
    }
    if (result !== 0 && destKeyB !== null) {
      result = await reader.valueTransferRestore(stagingSector, stagingBlock,
        destinationSector, destinationBlock, vb, stagingKey ?? [], useAsKeyB,
        destKeyB, true);
    }
    reader.close();

    // Check write result.
    if (result === 2) {
      NfcService.toast('错误：该扇区不包含指定编号的块。', true);
      return;
    }
    if (result === -1) {
      NfcService.toast('错误：不是值块、权限不足或值不正确', true);
      return;
    }
    NfcService.toast('数据写入成功', true);
    this.pathStack.pop();
  }

  // ---------------- Info dialogs ----------------

  private showStaticACInfo(): void {
    this.showMessageDialog('使用静态访问条件',
      '将转储中的所有访问条件替换为所选的访问条件。\n\n'
      + '如果转储中包含会对标签永久生效的访问条件，此功能非常有用。'
      + '在读卡器不检查这些条件的情况下，'
      + '您可以轻松使用自定义条件，使标签可以重复使用。\n\n'
      + '警告：写入错误数据可能会对标签造成不可修复的损坏。',
      '确定',
      (): void => {
      },
      '');
  }

  // ---------------- UI ----------------

  @Builder
  writeBlockSection() {
    Column() {
      Row() {
        Text('扇区')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(64)
        TextInput({ text: this.sectorInputBlock })
          .type(InputType.Number)
          .maxLength(2)
          .width(76)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.sectorInputBlock = value;
          })
        Text('（从 0 开始）')
          .fontSize(12)
          .fontColor(MctTheme.fgSecondary)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 4 })
      Row() {
        Text('块')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(64)
        TextInput({ text: this.blockInputBlock })
          .type(InputType.Number)
          .maxLength(2)
          .width(76)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.blockInputBlock = value;
          })
        Text('（从 0 开始）')
          .fontSize(12)
          .fontColor(MctTheme.fgSecondary)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })
      Row() {
        Text('数据')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(64)
        TextInput({ text: this.dataInput, placeholder: 'HEX，16 字节（例如 0A4F…）' })
          .maxLength(32)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 14 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .layoutWeight(1)
          .onChange((value: string): void => {
            this.dataInput = value;
          })
      }
      .width('100%')
      .margin({ top: 8 })
      Button('写入块')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .backgroundColor(MctTheme.buttonBg)
        .borderRadius(4)
        .margin({ top: 12 })
        .onClick(() => {
          this.onWriteBlock();
        })
    }
    .width('100%')
    .padding({ left: 5, right: 5, top: 4, bottom: 4 })
  }

  @Builder
  writeDumpSection() {
    Column() {
      Text('将转储（或其中的部分扇区）写入标签。包含未知数据 (---) 的块将被跳过！')
        .fontSize(15)
        .fontColor(MctTheme.fg)
        .width('100%')
        .padding(5)
      Button(this.dumpFromEditorActive ? '写入转储' : '选择转储')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .backgroundColor(MctTheme.buttonBg)
        .borderRadius(4)
        .margin({ top: 4 })
        .onClick(() => {
          this.onWriteDump();
        })
      Row() {
        Checkbox()
          .select(this.showDumpOptions)
          .selectedColor(MctTheme.accent)
          .width(20)
          .height(20)
          .onChange((value: boolean): void => {
            this.showDumpOptions = value;
          })
        Text('显示选项')
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .margin({ left: 8 })
          .onClick(() => {
            this.showDumpOptions = !this.showDumpOptions;
          })
      }
      .width('100%')
      .margin({ top: 8 })
      if (this.showDumpOptions) {
        Column() {
          Column() {
            Row() {
              Checkbox()
                .select(this.enableStaticAC)
                .selectedColor(MctTheme.accent)
                .width(20)
                .height(20)
                .onChange((value: boolean): void => {
                  this.enableStaticAC = value;
                })
              Text('对所有扇区使用以下访问条件：')
                .fontSize(14)
                .fontColor(MctTheme.fg)
                .margin({ left: 6 })
                .layoutWeight(1)
                .onClick(() => {
                  this.enableStaticAC = !this.enableStaticAC;
                })
              Text('ⓘ')
                .fontSize(18)
                .fontColor(MctTheme.accent)
                .padding({ left: 6, right: 2, top: 2, bottom: 2 })
                .onClick(() => {
                  this.showStaticACInfo();
                })
            }
            .width('100%')
            TextInput({ text: this.staticACInput })
              .maxLength(6)
              .width(130)
              .fontSize(15)
              .fontColor(MctTheme.fg)
              .backgroundColor(MctTheme.inputBg)
              .borderRadius(4)
              .margin({ top: 6 })
              .onChange((value: string): void => {
                this.staticACInput = value;
              })
          }
          .width('100%')
          .padding(4)
          .borderRadius(4)
          .border({ width: 1, color: MctTheme.buttonBorder })
          .margin({ bottom: 6 })
          Column() {
            Row() {
              Checkbox()
                .select(this.writeManufBlockChecked)
                .selectedColor(MctTheme.accent)
                .width(20)
                .height(20)
                .onChange((value: boolean): void => {
                  this.writeManufBlockChecked = value;
                })
              Text('高级：启用写入制造商块')
                .fontSize(14)
                .fontColor(MctTheme.fg)
                .margin({ left: 6 })
                .layoutWeight(1)
                .onClick(() => {
                  this.writeManufBlockChecked = !this.writeManufBlockChecked;
                })
              Text('ⓘ')
                .fontSize(18)
                .fontColor(MctTheme.accent)
                .padding({ left: 6, right: 2, top: 2, bottom: 2 })
                .onClick(() => {
                  this.showWriteManufInfo(false);
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(4)
          .borderRadius(4)
          .border({ width: 1, color: MctTheme.buttonBorder })
        }
        .width('100%')
        .padding({ left: 35 })
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 5, right: 5, top: 4, bottom: 4 })
  }

  @Builder
  cloneUidSection() {
    Column() {
      Button('打开 UID 克隆工具')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .backgroundColor(MctTheme.buttonBg)
        .borderRadius(4)
        .onClick(() => {
          this.onCloneUid();
        })
    }
    .width('100%')
    .padding({ left: 5, right: 5, top: 4, bottom: 4 })
  }

  @Builder
  factoryFormatSection() {
    Column() {
      Text('尝试将标签格式化为出厂/交付状态。')
        .fontSize(15)
        .fontColor(MctTheme.fg)
        .width('100%')
        .padding(5)
      Button('恢复出厂格式')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .backgroundColor(MctTheme.buttonBg)
        .borderRadius(4)
        .margin({ top: 4 })
        .onClick(() => {
          this.onFactoryFormat();
        })
    }
    .width('100%')
    .padding({ left: 5, right: 5, top: 4, bottom: 4 })
  }

  @Builder
  valueBlockSection() {
    Column() {
      Text('递增或递减值块，然后进行传送。'
        + '（如果您不知道什么是值块，请查看“帮助和信息”。）')
        .fontSize(15)
        .fontColor(MctTheme.fg)
        .width('100%')
        .padding(5)
      Row() {
        Text('扇区')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(64)
        TextInput({ text: this.sectorInputVB })
          .type(InputType.Number)
          .maxLength(2)
          .width(76)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.sectorInputVB = value;
          })
        Text('（从 0 开始）')
          .fontSize(12)
          .fontColor(MctTheme.fgSecondary)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 4 })
      Row() {
        Text('块')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(64)
        TextInput({ text: this.blockInputVB })
          .type(InputType.Number)
          .maxLength(2)
          .width(76)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.blockInputVB = value;
          })
        Text('（从 0 开始）')
          .fontSize(12)
          .fontColor(MctTheme.fgSecondary)
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })
      Row() {
        Text('值')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(64)
        TextInput({ text: this.newValueInputVB })
          .type(InputType.Number)
          .maxLength(10)
          .width(120)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.newValueInputVB = value;
          })
      }
      .width('100%')
      .margin({ top: 8 })
      Row({ space: 20 }) {
        Row() {
          Radio({ value: 'wt_increment', group: 'wt_vb_incr' })
            .checked(this.increaseVB)
            .width(20)
            .height(20)
            .onChange((isChecked: boolean): void => {
              if (isChecked) {
                this.increaseVB = true;
              }
            })
          Text('递增')
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .margin({ left: 6 })
            .onClick(() => {
              this.increaseVB = true;
            })
        }
        Row() {
          Radio({ value: 'wt_decrement', group: 'wt_vb_decr' })
            .checked(!this.increaseVB)
            .width(20)
            .height(20)
            .onChange((isChecked: boolean): void => {
              if (isChecked) {
                this.increaseVB = false;
              }
            })
          Text('递减')
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .margin({ left: 6 })
            .onClick(() => {
              this.increaseVB = false;
            })
        }
      }
      .width('100%')
      .margin({ top: 10 })
      Button('写入值块')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .backgroundColor(MctTheme.buttonBg)
        .borderRadius(4)
        .margin({ top: 12 })
        .onClick(() => {
          this.onWriteValue();
        })
    }
    .width('100%')
    .padding({ left: 5, right: 5, top: 4, bottom: 4 })
  }

  @Builder
  transferRestoreSection() {
    Column() {
      Text('即使仅有递减/传送/恢复权限，也可以设置值块的值')
        .fontSize(15)
        .fontColor(MctTheme.fg)
        .width('100%')
        .padding(5)
      Row() {
        Text('中转')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(90)
        TextInput({ text: this.vtrStageSectorInput, placeholder: '扇区' })
          .type(InputType.Number)
          .maxLength(2)
          .width(70)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 13 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.vtrStageSectorInput = value;
          })
        TextInput({ text: this.vtrStageBlockInput, placeholder: '块' })
          .type(InputType.Number)
          .maxLength(2)
          .width(70)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 13 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .margin({ left: 6 })
          .onChange((value: string): void => {
            this.vtrStageBlockInput = value;
          })
      }
      .width('100%')
      .margin({ top: 4 })
      Row() {
        Text('目标')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(90)
        TextInput({ text: this.vtrDestSectorInput, placeholder: '扇区' })
          .type(InputType.Number)
          .maxLength(2)
          .width(70)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 13 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.vtrDestSectorInput = value;
          })
        TextInput({ text: this.vtrDestBlockInput, placeholder: '块' })
          .type(InputType.Number)
          .maxLength(2)
          .width(70)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 13 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .margin({ left: 6 })
          .onChange((value: string): void => {
            this.vtrDestBlockInput = value;
          })
      }
      .width('100%')
      .margin({ top: 8 })
      Text('（从 0 开始）')
        .fontSize(12)
        .fontColor(MctTheme.fgSecondary)
        .width('100%')
        .textAlign(TextAlign.End)
      Row() {
        Text('值与地址')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width(120)
        TextInput({ text: this.vtrValueInput, placeholder: '如 423' })
          .maxLength(10)
          .width(100)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 13 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .onChange((value: string): void => {
            this.vtrValueInput = value;
          })
        TextInput({ text: this.vtrAddrInput, placeholder: '00' })
          .maxLength(2)
          .width(64)
          .fontSize(15)
          .fontColor(MctTheme.fg)
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 13 })
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .margin({ left: 6 })
          .onChange((value: string): void => {
            this.vtrAddrInput = value;
          })
      }
      .width('100%')
      .margin({ top: 8 })
      Button('通过传送和恢复写入值块')
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .backgroundColor(MctTheme.buttonBg)
        .borderRadius(4)
        .margin({ top: 12 })
        .onClick(() => {
          this.onWriteValueBlockTransferRestore();
        })
    }
    .width('100%')
    .padding({ left: 5, right: 5, top: 4, bottom: 4 })
  }

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          // === Write Block ===
          Row() {
            Radio({ value: 'wt_write_block', group: 'wt_mode_0' })
              .checked(this.writeMode === 0)
              .enabled(!this.dumpFromEditorActive)
              .width(20)
              .height(20)
              .onChange((isChecked: boolean): void => {
                if (isChecked) {
                  this.writeMode = 0;
                }
              })
            Text('写入块')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dumpFromEditorActive ? MctTheme.fgSecondary : MctTheme.accent)
              .margin({ left: 8 })
              .onClick(() => {
                if (!this.dumpFromEditorActive) {
                  this.writeMode = 0;
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 8, bottom: 4 })
          if (this.writeMode === 0) {
            this.writeBlockSection()
          }
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin(10)
          // === Write Dump ===
          Row() {
            Radio({ value: 'wt_write_dump', group: 'wt_mode_1' })
              .checked(this.writeMode === 1)
              .width(20)
              .height(20)
              .onChange((isChecked: boolean): void => {
                if (isChecked) {
                  this.writeMode = 1;
                }
              })
            Text('写入转储（克隆）')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(MctTheme.accent)
              .margin({ left: 8 })
              .onClick(() => {
                this.writeMode = 1;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 4 })
          if (this.writeMode === 1) {
            this.writeDumpSection()
          }
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin(10)
          // === Clone UID ===
          Row() {
            Radio({ value: 'wt_clone_uid', group: 'wt_mode_2' })
              .checked(this.writeMode === 2)
              .width(20)
              .height(20)
              .onChange((isChecked: boolean): void => {
                if (isChecked) {
                  this.writeMode = 2;
                }
              })
            Text('克隆 UID')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(MctTheme.accent)
              .margin({ left: 8 })
              .onClick(() => {
                this.writeMode = 2;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 4 })
          if (this.writeMode === 2) {
            this.cloneUidSection()
          }
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin(10)
          // === Factory Format ===
          Row() {
            Radio({ value: 'wt_factory_format', group: 'wt_mode_3' })
              .checked(this.writeMode === 3)
              .enabled(!this.dumpFromEditorActive)
              .width(20)
              .height(20)
              .onChange((isChecked: boolean): void => {
                if (isChecked) {
                  this.writeMode = 3;
                }
              })
            Text('恢复出厂格式')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.dumpFromEditorActive ? MctTheme.fgSecondary : MctTheme.accent)
              .margin({ left: 8 })
              .onClick(() => {
                if (!this.dumpFromEditorActive) {
                  this.writeMode = 3;
                }
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 4 })
          if (this.writeMode === 3) {
            this.factoryFormatSection()
          }
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin(10)
          // === Incr./Decr. Value Block ===
          Row() {
            Radio({ value: 'wt_value_block', group: 'wt_mode_4' })
              .checked(this.writeMode === 4)
              .width(20)
              .height(20)
              .onChange((isChecked: boolean): void => {
                if (isChecked) {
                  this.writeMode = 4;
                }
              })
            Text('递增/递减值块')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(MctTheme.accent)
              .margin({ left: 8 })
              .onClick(() => {
                this.writeMode = 4;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 4 })
          if (this.writeMode === 4) {
            this.valueBlockSection()
          }
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin(10)
          // === Transfer & Restore Value Block ===
          Row() {
            Radio({ value: 'wt_transfer_restore', group: 'wt_mode_5' })
              .checked(this.writeMode === 5)
              .width(20)
              .height(20)
              .onChange((isChecked: boolean): void => {
                if (isChecked) {
                  this.writeMode = 5;
                }
              })
            Text('传送和恢复值块')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(MctTheme.accent)
              .margin({ left: 8 })
              .onClick(() => {
                this.writeMode = 5;
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .padding({ top: 4, bottom: 4 })
          if (this.writeMode === 5) {
            this.transferRestoreSection()
          }
        }
        .width('100%')
        .padding(10)
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .backgroundColor(MctTheme.bg)
    }
    .title('写入标签')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: WriteTagParams = (ctx.pathInfo.param as WriteTagParams) ?? new WriteTagParams();
      if (p.dump !== null) {
        // Write dump directly from editor.
        this.dumpFromEditor = p.dump;
        this.dumpFromEditorActive = true;
        // Show "Write Dump" option and disable other write options.
        this.writeMode = 1;
      }
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener (BasicActivity.onResume equivalent).
      NfcService.setTagListener((tagInfo: tag.TagInfo, supportResult: number): void => {
        if (supportResult === -2) {
          this.pathStack.pushPathByName('tagInfoTool', null);
        }
      });
      // Handle the result of the FileChooser (FC_WRITE_DUMP).
      if (this.pendingDumpFile !== null) {
        const path: string = this.pendingDumpFile;
        this.pendingDumpFile = null;
        this.readDumpFromFile(path);
      }
      // Handle the result of the KeyMapCreator (onActivityResult equivalent).
      if (this.pendingOp !== WT_OP_NONE) {
        const op: number = this.pendingOp;
        this.pendingOp = WT_OP_NONE;
        const keyMap: Map<number, SectorKeys> | null = NfcService.getKeyMap();
        if (keyMap !== null && keyMap !== this.keyMapBeforePush) {
          if (op === WT_OP_WRITE_DUMP) {
            this.checkDumpAgainstTag();
          } else if (op === WT_OP_FACTORY_FORMAT) {
            this.createFactoryFormattedDump();
          } else if (op === WT_OP_WRITE_BLOCK) {
            this.writeBlock();
          } else if (op === WT_OP_WRITE_NEW_VALUE) {
            this.writeValueBlock();
          } else if (op === WT_OP_VALUE_TRANSFER_RESTORE) {
            this.runValueTransferRestore();
          }
        }
      }
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function WriteTagBuilder() {
  WriteTagPage()
}
