/**
 * Configure key map process and create key map
 * (port of de.syss.MifareClassicTool.Activities.KeyMapCreator,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * This page is pushed via pushPathByName('keyMapCreator', new KeyMapCreatorParams()).
 * The result codes (identical to the Android activity results) are:
 * -1 = RESULT_OK (the key map can be retrieved via NfcService.getKeyMap()),
 *  0 = canceled,
 *  1 = keys directory does not exist,
 *  2 = no keys directory specified,
 *  4 = keys directory path was null.
 */

import { tag } from '@kit.ConnectivityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { MctApp } from '../common/MctApp';
import { McReader } from '../common/McReader';
import { MctFiles } from '../common/MctFiles';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { PagePrefKey, PrefKey } from '../common/MctTypes';
import { Prefs } from '../common/Prefs';

/** AppStorage key used to pass the result code to the calling page. */
const KEY_MAP_CREATOR_RESULT_KEY: string = 'mct.keyMapCreatorResult';
/** Sentinel value meaning "no result yet". */
const KEY_MAP_CREATOR_NO_RESULT: number = 100;
// Android activity result codes.
const KEY_MAP_CREATOR_RESULT_OK: number = -1;
const KEY_MAP_CREATOR_RESULT_CANCELED: number = 0;
const KEY_MAP_CREATOR_RESULT_DIR_MISSING: number = 1;
const KEY_MAP_CREATOR_RESULT_NO_DIR: number = 2;
const KEY_MAP_CREATOR_RESULT_NULL_PATH: number = 4;
/** Sector count of the biggest MIFARE Classic tag (4K tag). */
const KEY_MAP_CREATOR_MAX_SECTOR_COUNT: number = 40;

/** Params for the key map creator page (Android intent extras). */
export class KeyMapCreatorParams {
  /** Path to a directory with key files (Android EXTRA_KEYS_DIR). */
  keysDir: string = '';
  /** Text of the start key mapping button (Android EXTRA_BUTTON_TEXT). */
  buttonText: string = '';
  /** Enable/disable the possibility to change the key mapping range
   *  (Android EXTRA_SECTOR_CHOOSER). */
  useSectorChooser: boolean = true;
  /** First sector for the key mapping process. -1 = range "all"
   *  (Android EXTRA_SECTOR_CHOOSER_FROM). */
  sectorFrom: number = -1;
  /** Last sector for the key mapping process
   *  (Android EXTRA_SECTOR_CHOOSER_TO). */
  sectorTo: number = -1;
  /** True if the keys from the dump should be used
   *  (stored at tmp/keys_from_dump.keys, Android EXTRA_USE_KEYS_FROM_DUMP). */
  useKeysFromDump: boolean = false;
}

/**
 * Dialog which lets the user choose the key mapping range
 * (port of KeyMapCreator.onChangeSectorRange()).
 */
@CustomDialog
struct KeyMapCreatorRangeDialog {
  controller?: CustomDialogController;
  onOk: (from: string, to: string, saveAsDefault: boolean) => void =
    (from: string, to: string, saveAsDefault: boolean): void => {};
  onReadAll: (saveAsDefault: boolean) => void =
    (saveAsDefault: boolean): void => {};
  @State fromText: string = '';
  @State toText: string = '';
  @State saveChecked: boolean = false;

  build() {
    Column() {
      Text('选择范围')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      Text('选择密钥映射过程的扇区范围\n（0 为第一个扇区）：')
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ top: 14 })
        .lineHeight(23)
      Row() {
        Text('从：')
          .fontSize(16)
          .fontColor(MctTheme.fg)
        TextInput({ text: this.fromText, placeholder: '' })
          .type(InputType.Number)
          .maxLength(2)
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .textAlign(TextAlign.Center)
          .width(56)
          .margin({ left: 6 })
          .onChange((value: string): void => {
            this.fromText = value;
          })
        Text('到：')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .margin({ left: 6 })
        TextInput({ text: this.toText, placeholder: '' })
          .type(InputType.Number)
          .maxLength(2)
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.inputBg)
          .borderRadius(4)
          .textAlign(TextAlign.Center)
          .width(56)
          .margin({ left: 6 })
          .onChange((value: string): void => {
            this.toText = value;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)
      Row() {
        Checkbox()
          .select(this.saveChecked)
          .selectedColor(MctTheme.accent)
          .width(20)
          .height(20)
          .onChange((value: boolean): void => {
            this.saveChecked = value;
          })
        Text('保存为默认')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .margin({ left: 8 })
          .onClick(() => {
            this.saveChecked = !this.saveChecked;
          })
      }
      .width('100%')
      .margin({ top: 16 })
      .alignItems(VerticalAlign.Center)
      Divider()
        .color(MctTheme.buttonBorder)
        .margin({ top: 16 })
      Row() {
        Text('读取所有扇区')
          .fontSize(16)
          .fontColor(MctTheme.accent)
          .maxLines(2)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
            this.onReadAll(this.saveChecked);
          })
        Text('取消')
          .fontSize(16)
          .fontColor(MctTheme.fgSecondary)
          .maxLines(2)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
          })
        Text('确定')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(MctTheme.accent)
          .maxLines(2)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            this.controller?.close();
            this.onOk(this.fromText, this.toText, this.saveChecked);
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
struct KeyMapCreatorPage {
  @State keyFileNames: string[] = [];
  @State checkedArr: boolean[] = [];
  @State sectorRangeText: string = '全部';
  @State createBtnText: string = '映射密钥到扇区';
  @State createBtnEnabled: boolean = true;
  @State cancelBtnEnabled: boolean = true;
  @State changeRangeEnabled: boolean = true;
  @State progressValue: number = 0;
  @State progressTotal: number = 100;
  @State progressText: string = '';

  private pathStack: NavPathStack = new NavPathStack();
  private rangeDialogCtrl: CustomDialogController | null = null;
  private keysDir: string = '';
  private useKeysFromDump: boolean = false;
  private firstSector: number = 0;
  private lastSector: number = 0;
  private progressStatus: number = -1;
  private isCreatingKeyMap: boolean = false;
  private currentReader: McReader | null = null;
  private pageAlive: boolean = true;

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  aboutToDisappear(): void {
    this.pageAlive = false;
  }

  // ---------------- Init (onCreate/onStart) ----------------

  private applyParams(params: KeyMapCreatorParams): void {
    // Android onStart: is there a key directory in the intent?
    if (params.keysDir === '') {
      // No directory specified.
      this.finishWithResult(KEY_MAP_CREATOR_RESULT_NO_DIR);
      return;
    }
    this.keysDir = params.keysDir;

    // Android onCreate: enable/disable the sector range chooser.
    this.changeRangeEnabled = params.useSectorChooser;

    // Android onCreate: init sector range.
    let custom: boolean = false;
    let from: string = Prefs.getString(PagePrefKey.DefaultMappingRangeFrom, '');
    let to: string = Prefs.getString(PagePrefKey.DefaultMappingRangeTo, '');
    // Are there default values?
    if (from !== '') {
      custom = true;
    }
    if (to !== '') {
      custom = true;
    }
    // Are there given values?
    if (params.sectorFrom !== -1) {
      from = '' + params.sectorFrom;
      custom = true;
    }
    if (params.sectorTo !== -1) {
      to = '' + params.sectorTo;
      custom = true;
    }
    if (custom) {
      if (from === '-1') {
        // "from" being "-1" means that the range should be set to "all".
        this.sectorRangeText = '全部';
      } else {
        this.sectorRangeText = from + ' - ' + to;
      }
    }

    // Android onCreate: init button text.
    if (params.buttonText !== '') {
      this.createBtnText = params.buttonText;
    }

    // Android onCreate: use keys from dump?
    this.useKeysFromDump = params.useKeysFromDump;

    // Android onStart: does the directory exist?
    if (!MctFiles.exists(this.keysDir)) {
      this.finishWithResult(KEY_MAP_CREATOR_RESULT_DIR_MISSING);
      return;
    }
    this.loadKeyFiles();
  }

  /**
   * List files from the keys dir and select the last used ones
   * if "save_last_used_key_files" is enabled (Android onStart).
   */
  private loadKeyFiles(): void {
    const selectLastUsedKeyFiles: boolean =
      Prefs.getBool(PrefKey.SaveLastUsedKeyFiles, true);
    let selectedFiles: string[] | null = null;
    if (selectLastUsedKeyFiles) {
      // All previously selected key files are stored in one string
      // separated by "/".
      const selectedFilesChain: string =
        Prefs.getString(PagePrefKey.LastUsedKeyFiles, '');
      if (selectedFilesChain !== '') {
        selectedFiles = selectedFilesChain.split('/');
      }
    }
    const names: string[] = MctFiles.listFileNames(this.keysDir);
    const checked: boolean[] = [];
    for (let i = 0; i < names.length; i++) {
      checked.push(selectLastUsedKeyFiles && selectedFiles !== null
        && selectedFiles.indexOf(names[i]) !== -1);
    }
    this.keyFileNames = names;
    this.checkedArr = checked;
  }

  // ---------------- Key file selection ----------------

  private selectKeyFiles(allOrNone: boolean): void {
    for (let i = 0; i < this.checkedArr.length; i++) {
      this.checkedArr[i] = allOrNone;
    }
  }

  private setCheckedAt(index: number, value: boolean): void {
    this.checkedArr[index] = value;
  }

  // ---------------- Key map creation ----------------

  private onCreateKeyMap(): void {
    const saveLastUsedKeyFiles: boolean =
      Prefs.getBool(PrefKey.SaveLastUsedKeyFiles, true);
    let lastSelectedKeyFiles: string = '';
    // Check for checked check boxes.
    const fileNames: string[] = [];
    for (let i = 0; i < this.keyFileNames.length; i++) {
      if (this.checkedArr[i]) {
        fileNames.push(this.keyFileNames[i]);
      }
    }
    if (fileNames.length === 0) {
      NfcService.toast('错误：未选择密钥文件', true);
      return;
    }
    // Check if key files still exist.
    const keyFiles: string[] = [];
    for (let i = 0; i < fileNames.length; i++) {
      const keyFile: string = this.keysDir + '/' + fileNames[i];
      if (MctFiles.exists(keyFile)) {
        // Add key file.
        keyFiles.push(keyFile);
        if (saveLastUsedKeyFiles) {
          lastSelectedKeyFiles += fileNames[i] + '/';
        }
      }
    }
    if (keyFiles.length === 0) {
      NfcService.toast('错误：未找到密钥文件', true);
      return;
    }
    // Save last selected key files as "/"-separated string
    // (if the corresponding setting is active).
    if (saveLastUsedKeyFiles) {
      Prefs.putString(PagePrefKey.LastUsedKeyFiles,
        lastSelectedKeyFiles.substring(0, lastSelectedKeyFiles.length - 1));
    }
    // Create reader.
    const reader: McReader | null = NfcService.checkForTagAndCreateReader();
    this.currentReader = reader;
    if (reader === null) {
      return;
    }
    // Set key files.
    if (this.useKeysFromDump) {
      // Add keys from dump to be written at the beginning because it
      // is likely that the dump is written back to the same tag.
      const tmpKeysFromDump: string =
        MctFiles.getTmpDir() + '/keys_from_dump.keys';
      keyFiles.splice(0, 0, tmpKeysFromDump);
    }
    const numberOfLoadedKeys: number = reader.setKeyFile(keyFiles);
    if (numberOfLoadedKeys < 1) {
      // Error.
      reader.close();
      return;
    }
    // Live key mapping progress (so slow key files don't look frozen).
    reader.keyProgressListener =
      (sector: number, tried: number, total: number): void => {
        this.progressText = '扇区 ' + sector + '：正在尝试第 '
          + tried + '/' + total + ' 把密钥';
      };
    // Don't turn screen off while mapping.
    this.setKeepScreenOn(true);
    // Get key map range.
    if (this.sectorRangeText === '全部') {
      // Read all.
      this.firstSector = 0;
      this.lastSector = reader.getSectorCount() - 1;
    } else {
      const fromAndTo: string[] = this.sectorRangeText.split(' ');
      this.firstSector = parseInt(fromAndTo[0], 10);
      this.lastSector = parseInt(fromAndTo[2], 10);
    }
    // Set map creation range.
    if (!reader.setMappingRange(this.firstSector, this.lastSector)) {
      // Error.
      NfcService.toast('映射范围错误：扇区超出范围。', true);
      reader.close();
      return;
    }
    NfcService.setKeyMapRange(this.firstSector, this.lastSector);
    // Init GUI elements.
    this.progressStatus = -1;
    this.progressTotal = (this.lastSector - this.firstSector) + 1;
    this.progressValue = 0;
    this.createBtnEnabled = false;
    this.isCreatingKeyMap = true;
    NfcService.toast(numberOfLoadedKeys
      + ' 个密钥已加载。正在创建密钥映射…这可能需要一段时间…', false);
    // Create key map (worker thread on Android).
    this.runKeyMapLoop(reader);
  }

  private async runKeyMapLoop(reader: McReader): Promise<void> {
    // Build key map parts and update the progress bar.
    while (this.progressStatus < this.lastSector) {
      this.progressStatus = await reader.buildNextKeyMapPart();
      if (this.progressStatus === -1 || !this.isCreatingKeyMap) {
        // Error while building the next key map part
        // (or key map creation was canceled).
        break;
      }
      this.progressValue = (this.progressStatus - this.firstSector) + 1;
    }
    reader.keyProgressListener = null;
    this.progressText = '';
    this.setKeepScreenOn(false);
    this.progressValue = 0;
    this.createBtnEnabled = true;
    reader.close();
    if (this.isCreatingKeyMap && this.progressStatus !== -1) {
      // Finished creating the key map.
      this.keyMapCreated(reader);
    } else if (this.isCreatingKeyMap && this.progressStatus === -1) {
      // Error during key map creation.
      NfcService.setKeyMap(null);
      NfcService.setKeyMapRange(-1, -1);
      this.cancelBtnEnabled = true;
      NfcService.toast('错误：与标签的连接已丢失', true);
    } else {
      // Key map creation was canceled by the user.
      NfcService.setKeyMap(null);
      NfcService.setKeyMapRange(-1, -1);
      this.cancelBtnEnabled = true;
    }
    this.isCreatingKeyMap = false;
  }

  /**
   * Set the result code to RESULT_OK, save the created key map to
   * the NFC service and finish this page (Android keyMapCreated()).
   */
  private keyMapCreated(reader: McReader): void {
    if (reader.getKeyMap().size === 0) {
      NfcService.setKeyMap(null);
      // Error. No valid key found.
      NfcService.toast('在所选密钥文件中未找到有效密钥', true);
    } else {
      NfcService.setKeyMap(reader.getKeyMap());
      this.finishWithResult(KEY_MAP_CREATOR_RESULT_OK);
    }
  }

  /**
   * Inform the worker loop to stop creating the key map. If it is
   * already informed or does not exist, this button will finish the
   * page (Android onCancelCreateKeyMap()).
   */
  private onCancelCreateKeyMap(): void {
    if (this.isCreatingKeyMap) {
      this.isCreatingKeyMap = false;
      if (this.currentReader !== null) {
        this.currentReader.cancelCreateKeyMap();
      }
      this.cancelBtnEnabled = false;
    } else {
      this.finishWithResult(KEY_MAP_CREATOR_RESULT_CANCELED);
    }
  }

  // ---------------- Mapping range dialog ----------------

  private showRangeDialog(): void {
    this.rangeDialogCtrl = new CustomDialogController({
      builder: KeyMapCreatorRangeDialog({
        onOk: (from: string, to: string, saveAsDefault: boolean): void => {
          // Read from x to y.
          let txtFrom: string = '0';
          let txtTo: string = '15';
          let noFrom: boolean = false;
          if (from.length > 0) {
            txtFrom = from;
          } else {
            noFrom = true;
          }
          if (to.length > 0) {
            txtTo = to;
          } else if (noFrom) {
            // No values provided. Read all sectors.
            this.sectorRangeText = '全部';
            if (saveAsDefault) {
              this.saveMappingRange('', '');
            }
            return;
          }
          const intFrom: number = parseInt(txtFrom, 10);
          const intTo: number = parseInt(txtTo, 10);
          if (intFrom > intTo || intFrom < 0
            || intTo > KEY_MAP_CREATOR_MAX_SECTOR_COUNT - 1) {
            // Error.
            NfcService.toast('映射范围错误', true);
          } else {
            this.sectorRangeText = txtFrom + ' - ' + txtTo;
            if (saveAsDefault) {
              // Save as default.
              this.saveMappingRange(txtFrom, txtTo);
            }
          }
        },
        onReadAll: (saveAsDefault: boolean): void => {
          // Read all sectors.
          this.sectorRangeText = '全部';
          if (saveAsDefault) {
            // Save as default.
            this.saveMappingRange('', '');
          }
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: true,
      customStyle: true
    });
    this.rangeDialogCtrl.open();
  }

  /** Helper method to save the mapping range as default. */
  private saveMappingRange(from: string, to: string): void {
    Prefs.putString(PagePrefKey.DefaultMappingRangeFrom, from);
    Prefs.putString(PagePrefKey.DefaultMappingRangeTo, to);
  }

  // ---------------- Misc ----------------

  private setRawResult(code: number): void {
    AppStorage.setOrCreate(KEY_MAP_CREATOR_RESULT_KEY, code);
  }

  private finishWithResult(code: number): void {
    this.setRawResult(code);
    if (this.pageAlive) {
      this.pathStack.pop();
    }
  }

  /** Don't turn the screen off while mapping (Android FLAG_KEEP_SCREEN_ON). */
  private setKeepScreenOn(enable: boolean): void {
    window.getLastWindow(MctApp.getContext())
      .then((win: window.Window): void => {
        win.setWindowKeepScreenOn(enable)
          .catch((error: BusinessError): void => {
            // Ignore.
          });
      })
      .catch((error: BusinessError): void => {
        // Ignore.
      });
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('为以下扇区创建映射：')
            .fontSize(16)
            .fontColor(MctTheme.fg)
          Text(this.sectorRangeText)
            .fontSize(16)
            .fontColor(MctTheme.accent)
            .margin({ left: 6 })
          Button('更改')
            .height(34)
            .fontSize(14)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .enabled(this.changeRangeEnabled)
            .opacity(this.changeRangeEnabled ? 1 : 0.4)
            .margin({ left: 8 })
            .onClick(() => {
              this.showRangeDialog();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 10, top: 10 })

        Text('选择一些密钥文件：')
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: 10, right: 10, top: 8 })

        Row({ space: 8 }) {
          Button('全选')
            .height(34)
            .fontSize(14)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .onClick(() => {
              this.selectKeyFiles(true);
            })
          Button('全不选')
            .height(34)
            .fontSize(14)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .onClick(() => {
              this.selectKeyFiles(false);
            })
        }
        .width('100%')
        .padding({ left: 10, right: 10, top: 4 })

        Scroll() {
          Column() {
            ForEach(this.keyFileNames, (name: string, index: number): void => {
              Row() {
                Checkbox()
                  .select(this.checkedArr[index])
                  .selectedColor(MctTheme.accent)
                  .width(22)
                  .height(22)
                  .onChange((value: boolean): void => {
                    this.setCheckedAt(index, value);
                  })
                Text(name)
                  .fontSize(15)
                  .fontColor(MctTheme.fg)
                  .maxLines(1)
                  .margin({ left: 10 })
              }
              .width('100%')
              .height(44)
              .alignItems(VerticalAlign.Center)
              .padding({ left: 10, right: 10 })
            }, (name: string): string => name)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 4 })

        Row() {
          Text('密钥映射进度：')
            .fontSize(12)
            .fontColor(MctTheme.fgSecondary)
            .margin({ right: 8 })
          Progress({ value: this.progressValue, total: this.progressTotal, type: ProgressType.Linear })
            .color(MctTheme.accent)
            .backgroundColor(MctTheme.inputBg)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 10, top: 4 })

        if (this.progressText !== '') {
          Text(this.progressText)
            .fontSize(12)
            .fontColor(MctTheme.fgSecondary)
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ left: 10, right: 10, top: 2 })
        }

        Row() {
          Button('取消')
            .height(44)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .enabled(this.cancelBtnEnabled)
            .opacity(this.cancelBtnEnabled ? 1 : 0.4)
            .onClick(() => {
              this.onCancelCreateKeyMap();
            })
          Blank()
            .layoutWeight(1)
          Button() {
            Text(this.createBtnText)
              .fontSize(16)
              .fontColor(MctTheme.fg)
              .maxLines(2)
              .textAlign(TextAlign.Center)
          }
          .height(44)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .padding({ left: 14, right: 14 })
          .enabled(this.createBtnEnabled)
          .opacity(this.createBtnEnabled ? 1 : 0.4)
          .onClick(() => {
            this.onCreateKeyMap();
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 10, top: 8, bottom: 10 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('映射密钥到扇区')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const params: KeyMapCreatorParams =
        (ctx.pathInfo.param as KeyMapCreatorParams) ?? new KeyMapCreatorParams();
      this.applyParams(params);
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
    })
    .onHidden(() => {
      // Android onPause (BasicActivity): disable NFC foreground dispatch.
      NfcService.setTagListener(null);
      const autoReconnect: boolean = Prefs.getBool(PrefKey.AutoReconnect, false);
      // Don't stop key map building if the auto reconnect option is enabled.
      if (!autoReconnect) {
        this.isCreatingKeyMap = false;
      }
    })
    .onBackPressed(() => {
      // Back press finishes the page (Android finish(),
      // result code "canceled").
      this.setRawResult(KEY_MAP_CREATOR_RESULT_CANCELED);
      return false;
    })
  }
}

@Builder
export function KeyMapCreatorBuilder() {
  KeyMapCreatorPage()
}
