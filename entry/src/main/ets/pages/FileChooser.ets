/**
 * Generic file chooser (port of de.syss.MifareClassicTool.Activities.FileChooser,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Lets the user choose a file from a given directory. Optionally files can
 * be deleted, new ones can be created and the ImportExportTool can be
 * opened (all via the menu). The chosen file is reported back through
 * FileChooserParams.onResult (the Android startActivityForResult/setResult
 * equivalent):
 *   - onResult(<full path>)  ... chosen file (RESULT_OK)
 *   - onResult(null)         ... finished without RESULT_OK (result 1/2/4,
 *                                back press, destruction)
 */

import { MctFiles } from '../common/MctFiles';
import { MctTheme } from '../common/ui/MctTheme';
import { MctInputDialog } from '../common/ui/MctDialog';
import { NfcService } from '../common/NfcService';
import { PrefKey } from '../common/MctTypes';
import { Prefs } from '../common/Prefs';
import { ImportExportToolParams } from './ImportExportTool';

/** Input/output parameters of the file chooser (the Intent extras). */
export class FileChooserParams {
  dir: string = '';
  title: string = '';
  chooserText: string = '';
  buttonText: string = '';
  allowNewFile: boolean = false;
  onResult: (file: string | null) => void = (file: string | null): void => {};

  constructor(dir: string, title: string, chooserText: string, buttonText: string,
    allowNewFile: boolean, onResult: (file: string | null) => void) {
    this.dir = dir;
    this.title = title;
    this.chooserText = chooserText;
    this.buttonText = buttonText;
    this.allowNewFile = allowNewFile;
    this.onResult = onResult;
  }
}

@Component
struct FileChooserPage {
  @State pageTitle: string = '文件选择器';
  @State fileNames: string[] = [];
  @State selectedFile: string = '';
  @State chooserTextDisplay: string = '选择文件：';
  @State chooseButtonLabel: string = '选择该文件';
  @State chooseButtonEnabled: boolean = false;
  @State menuAllowNewFile: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private dialogCtrl: CustomDialogController | null = null;
  private chooserParams: FileChooserParams | null = null;
  private dirPath: string = '';
  private resultDelivered: boolean = false;

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  aboutToDisappear(): void {
    // The "activity" got destroyed without delivering a result
    // (Android: finish() without setResult(RESULT_OK)).
    this.deliverResult(null);
  }

  // ---------------- Result handling ----------------

  /** Deliver the result exactly once (setResult + finish equivalent). */
  private deliverResult(file: string | null): void {
    if (this.resultDelivered) {
      return;
    }
    this.resultDelivered = true;
    if (this.chooserParams !== null) {
      this.chooserParams.onResult(file);
    }
  }

  /** Finish without a result (Android: setResult(<code>) + finish()). */
  private finishWithoutResult(): void {
    this.pathStack.pop();
    this.deliverResult(null);
  }

  // ---------------- File list ----------------

  /**
   * Update the file list and the components that depend on it
   * (e.g. disable the choose file button if there is no file).
   * Returns true if the directory is empty (mIsDirEmpty).
   */
  private updateFileIndex(): boolean {
    // Refresh file list (files only, sorted alphabetically).
    const names: string[] = MctFiles.listFileNames(this.dirPath);
    this.fileNames = names;
    const isEmpty: boolean = names.length === 0;

    // Update chooser text.
    // Add storage model update info, if MCT was updated and there are no
    // or only standard files.
    let text: string = '';
    const notFirstInstall: boolean = !Prefs.getBool(PrefKey.IsFirstRun, true);
    const allEntries: string[] = MctFiles.listFileNames(this.dirPath, true);
    const onlyStdFiles: boolean = allEntries.length === 3
      && allEntries[0] === MctFiles.STD_KEYS_EXTENDED
      && allEntries[1] === MctFiles.STD_HOTEL_KEYS
      && allEntries[2] === MctFiles.STD_KEYS;
    if ((notFirstInstall && isEmpty) || (notFirstInstall && onlyStdFiles)) {
      text += '从 4.0.0 之前的版本更新后丢失了文件？'
        + '请阅读“帮助与信息”中的“1.2 数据存储”章节。'
        + '\n\n';
    }
    if (this.chooserParams !== null && this.chooserParams.chooserText.length > 0) {
      text += this.chooserParams.chooserText;
    } else {
      text += '选择文件：';
    }
    if (isEmpty) {
      text += '\n\n   --- 未找到文件 ---';
    }
    this.chooserTextDisplay = text;

    // Preselect the first file.
    this.chooseButtonEnabled = !isEmpty;
    if (!isEmpty) {
      this.selectedFile = names[0];
    } else {
      this.selectedFile = '';
    }
    return isEmpty;
  }

  // ---------------- Choose / New / Delete / Import-Export ----------------

  /**
   * Finish with an intent containing the chosen file
   * (Android: onFileChosen, RESULT_OK).
   */
  private onFileChosen(): void {
    if (this.selectedFile.length === 0) {
      return;
    }
    const file: string = this.dirPath + '/' + this.selectedFile;
    this.pathStack.pop();
    this.deliverResult(file);
  }

  /** Prefill for the new file name (".keys" in the keys directory). */
  private newFilePrefill(): string {
    const segIdx: number = this.dirPath.lastIndexOf('/');
    const dirName: string = segIdx !== -1 ? this.dirPath.substring(segIdx + 1) : this.dirPath;
    if (dirName === MctFiles.KEYS_DIR) {
      return '.keys';
    }
    return '';
  }

  /**
   * Ask the user for a file name and choose this new file
   * (Android: onNewFile).
   */
  private onNewFile(initialName: string): void {
    this.dialogCtrl = new CustomDialogController({
      builder: MctInputDialog({
        titleText: '新建文件',
        messageText: '输入新文件的文件名：',
        inputInitial: initialName,
        cancelButtonText: '取消',
        confirmButtonText: '确定',
        onConfirm: (name: string): void => {
          if (name.length > 0 && name.indexOf('/') === -1) {
            const file: string = this.dirPath + '/' + name;
            if (MctFiles.exists(file)) {
              NfcService.toast('错误：文件已存在', true);
              // Keep the dialog open (like the Android original).
              this.onNewFile(name);
              return;
            }
            this.pathStack.pop();
            this.deliverResult(file);
          } else {
            // Invalid file name.
            NfcService.toast('错误：文件名无效', true);
            // Keep the dialog open (like the Android original).
            this.onNewFile(name);
          }
        }
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

  /** Delete the selected file and update the file list (Android: onDeleteFile). */
  private onDeleteFile(): void {
    if (this.selectedFile.length === 0) {
      return;
    }
    const file: string = this.dirPath + '/' + this.selectedFile;
    MctFiles.deleteFile(file);
    this.updateFileIndex();
  }

  /** Open the ImportExportTool (Android: onImportExportFiles, no extras). */
  private onImportExportFiles(): void {
    const params: ImportExportToolParams = new ImportExportToolParams();
    this.pathStack.pushPathByName('importExportTool', params);
  }

  // ---------------- Menu ----------------

  @Builder
  functionsMenuBuilder() {
    Menu() {
      if (this.menuAllowNewFile) {
        MenuItem({ content: '新建文件' })
          .onClick(() => {
            this.onNewFile(this.newFilePrefill());
          })
      }
        MenuItem({ content: '删除文件' })
        .enabled(this.fileNames.length > 0)
        .onClick(() => {
          this.onDeleteFile();
        })
        MenuItem({ content: '导入/导出文件' })
        .onClick(() => {
          this.onImportExportFiles();
        })
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text(this.chooserTextDisplay)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .layoutWeight(1)
            .padding(5)
            .textAlign(TextAlign.Start)
          Text('⋮')
            .fontSize(22)
            .fontColor(MctTheme.fg)
            .padding({ left: 8, right: 10, top: 2, bottom: 2 })
            .bindMenu(this.functionsMenuBuilder)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        List() {
          ForEach(this.fileNames, (fileName: string) => {
            ListItem() {
              Row() {
                Radio({ value: fileName, group: 'mctFileChooserFiles' })
                  .checked(this.selectedFile === fileName)
                  .onChange((isChecked: boolean): void => {
                    if (isChecked) {
                      this.selectedFile = fileName;
                    }
                  })
                Text(fileName)
                  .fontSize(16)
                  .fontColor(MctTheme.fg)
                  .margin({ left: 10 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.selectedFile = fileName;
              })
            }
          }, (fileName: string): string => fileName)
        }
        .layoutWeight(1)
        .width('100%')

        Button(this.chooseButtonLabel)
          .width('100%')
          .height(48)
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .enabled(this.chooseButtonEnabled)
          .opacity(this.chooseButtonEnabled ? 1 : 0.4)
          .onClick(() => {
            this.onFileChosen();
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title(this.pageTitle)
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: FileChooserParams = (ctx.pathInfo.param as FileChooserParams)
        ?? new FileChooserParams('', '', '', '', false, (file: string | null): void => {});
      this.chooserParams = p;
      this.menuAllowNewFile = p.allowNewFile;
      if (p.title.length > 0) {
        this.pageTitle = p.title;
      }
      if (p.buttonText.length > 0) {
        this.chooseButtonLabel = p.buttonText;
      }
      if (p.dir.length === 0) {
        // No directory specified in intent.
        this.finishWithoutResult();
        return;
      }
      if (!MctFiles.exists(p.dir)) {
        // Path does not exist.
        this.finishWithoutResult();
        return;
      }
      if (!MctFiles.isDir(p.dir)) {
        // Path is not a directory.
        this.finishWithoutResult();
        return;
      }
      this.dirPath = p.dir;
      this.updateFileIndex();
    })
    .onShown(() => {
      // Refresh the file list (Android onStart, e.g. after returning
      // from the ImportExportTool).
      if (this.dirPath.length > 0) {
        this.updateFileIndex();
      }
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
    .onBackPressed((): boolean => {
      // Finish without RESULT_OK (back was pressed).
      this.deliverResult(null);
      return false;
    })
  }
}

@Builder
export function FileChooserBuilder() {
  FileChooserPage()
}
