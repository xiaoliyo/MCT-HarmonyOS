/**
 * Key file editor (port of de.syss.MifareClassicTool.Activities.KeyEditor,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Shows and edits key files. The editor is initialized with the key file
 * from KeyEditorParams.chosenFile. Menu functions: Save, Share,
 * Export Keys and Remove Duplicates. On leaving the editor with unsaved
 * changes the user is asked whether to save them.
 */

import { MctFiles } from '../common/MctFiles';
import { MctDialog, MctInputDialog } from '../common/ui/MctDialog';
import { MctTheme } from '../common/ui/MctTheme';
import { MifareUtils } from '../common/MifareUtils';
import { NfcService } from '../common/NfcService';
import { ImportExportToolParams } from './ImportExportTool';

/** Input parameters of the key editor (the Intent extras). */
export class KeyEditorParams {
  chosenFile: string = '';
}

@Component
struct KeyEditorPage {
  @State pageTitle: string = '密钥文件编辑器';
  @State keysText: string = '';
  private pathStack: NavPathStack = new NavPathStack();
  private dialogCtrl: CustomDialogController | null = null;
  private fileName: string = '';
  /** All keys and comments (updated with every checkDumpAndUpdateLines()). */
  private lines: string[] = [];
  /** True if the user made changes to the key file (save-before-quitting). */
  private keysChanged: boolean = false;
  /** If true, the editor will close after a successful save. */
  private closeAfterSuccessfulSave: boolean = false;
  /** True once the initial content was set (changes count from then on). */
  private textWatcherActive: boolean = false;
  private initialized: boolean = false;

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Save / close reaction ----------------

  /**
   * Close the editor if mCloseAfterSuccessfulSave is true (due to exiting
   * with unsaved changes) after a successful save process.
   */
  private onSaveSuccessful(): void {
    if (this.closeAfterSuccessfulSave) {
      this.pathStack.pop();
    }
    this.keysChanged = false;
  }

  /**
   * Reset mCloseAfterSuccessfulSave if there was an error (or if the
   * user hit cancel) during the save process.
   */
  private onSaveFailure(): void {
    this.closeAfterSuccessfulSave = false;
  }

  // ---------------- Text handling ----------------

  /** Update the user input field for keys with the given lines. */
  private setKeyArrayAsText(lines: string[]): void {
    this.keysText = lines.join('\n');
    if (this.textWatcherActive) {
      // Text was changed (Android: the TextWatcher fired).
      this.keysChanged = true;
    }
  }

  /**
   * Check if the user input is a valid key file, convert all keys
   * to upper case and update mLines and the input field.
   * Return values are compliant to isValidKeyFileErrorToast():
   * 0 - All O.K.; 1 - There is no key; 2 - At least one key has
   * invalid characters (not hex); 3 - At least one key has not
   * 6 byte (12 chars).
   */
  private checkDumpAndUpdateLines(): number {
    const editorText: string = this.keysText;
    const lines: string[] = editorText.split('\n');
    const ret: number = MifareUtils.isValidKeyFile(lines);
    if (ret !== 0) {
      return ret;
    }

    // Convert keys to uppercase.
    const newLines: string[] = new Array<string>(lines.length);
    for (let i = 0; i < lines.length; i++) {
      let line: string = lines[i].trim();
      if (line.startsWith('#')) {
        newLines[i] = line;
        continue;
      }
      let content: string = line.split('#')[0];
      content = content.trim();
      if (content.length === 0) {
        newLines[i] = line;
        continue;
      }
      // Line is a key. Convert to uppercase.
      content = content.toUpperCase();
      newLines[i] = content + line.substring(12);
    }
    this.lines = newLines;
    this.setKeyArrayAsText(newLines);
    // Checking (and converting them to uppercase) does not count as change.
    this.keysChanged = false;
    return ret;
  }

  /** Show a toast for the given isValidKeyFile() error code. */
  private isValidKeyFileErrorToast(errorCode: number): boolean {
    if (errorCode === 0) {
      return true;
    }
    if (errorCode === 1) {
      NfcService.toast('错误：必须至少有一个密钥', true);
    } else if (errorCode === 2) {
      NfcService.toast('错误：部分密钥包含无效数据（非十六进制）', true);
    } else if (errorCode === 3) {
      NfcService.toast('错误：部分密钥不足 6 字节（12 个字符）', true);
    }
    return false;
  }

  // ---------------- Save ----------------

  /**
   * Check if it is a valid key file, ask user for a save name and then
   * call saveFile().
   */
  private onSave(): void {
    if (!this.isValidKeyFileErrorToast(this.checkDumpAndUpdateLines())) {
      return;
    }
    this.showSaveKeysDialog();
  }

  /**
   * Show the dialog in which the user can enter a file name for the
   * key file (Android: dialog_save_file).
   */
  private showSaveKeysDialog(): void {
    // If the user cancels the dialog, the editor must not be closed
    // after a later successful save (Android: the negative button sets
    // mCloseAfterSuccessfulSave to false). Therefore the flag is
    // captured here, reset and restored on confirm.
    const closeAfterSave: boolean = this.closeAfterSuccessfulSave;
    this.closeAfterSuccessfulSave = false;
    this.dialogCtrl = new CustomDialogController({
      builder: MctInputDialog({
        titleText: '保存密钥文件',
        messageText: '输入密钥文件的文件名：',
        inputInitial: this.fileName,
        cancelButtonText: '取消',
        confirmButtonText: '确定',
        onConfirm: (name: string): void => {
          this.closeAfterSuccessfulSave = closeAfterSave;
          this.saveFile(name, MctFiles.getKeysDir());
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

  /**
   * Save mLines to a file. Also makes sure not to overwrite a
   * standard key file.
   */
  private saveFile(fileName: string, path: string): void {
    if (fileName.length === 0 || fileName.indexOf('/') !== -1) {
      NfcService.toast('错误：文件名无效', true);
      return;
    }
    if (fileName === MctFiles.STD_KEYS || fileName === MctFiles.STD_KEYS_EXTENDED
      || fileName === MctFiles.STD_HOTEL_KEYS) {
      NfcService.toast('错误：无法覆盖标准密钥文件', true);
      return;
    }
    const file: string = path + '/' + fileName;
    this.checkFileExistenceAndSave(file, this.lines, false);
  }

  /**
   * Check if the file already exists. If so, present a dialog to the
   * user with the options: "Replace", "Append" and "Cancel"
   * (Android: Common.checkFileExistenceAndSave).
   */
  private checkFileExistenceAndSave(file: string, lines: string[], isDump: boolean): void {
    if (MctFiles.exists(file)) {
      // File already exists. Replace? Append? Cancel?
      this.dialogCtrl = new CustomDialogController({
        builder: MctDialog({
          titleText: '文件已存在',
          messageText: '该文件已存在。您想如何处理？',
          button1Text: '替换',
          button1Action: (checked: boolean): void => {
            // Replace.
            this.writeAndReact(file, lines, false, false);
          },
          button3Text: '追加',
          button3Action: (checked: boolean): void => {
            // Append.
            this.writeAndReact(file, lines, true, isDump);
          },
          button2Text: '取消',
          button2Action: (checked: boolean): void => {
            // Cancel.
            this.onSaveFailure();
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
    } else {
      this.writeAndReact(file, lines, false, false);
    }
  }

  /** Write the lines (append/replace) and react with toast + callbacks. */
  private writeAndReact(file: string, lines: string[], append: boolean, comment: boolean): void {
    let ok: boolean;
    if (append) {
      ok = MctFiles.appendLines(file, lines, comment);
    } else {
      ok = MctFiles.writeLines(file, lines);
    }
    if (ok) {
      NfcService.toast('数据保存成功', true);
      this.onSaveSuccessful();
    } else {
      NfcService.toast('错误：保存数据时出错', true);
      this.onSaveFailure();
    }
  }

  // ---------------- Share / Export ----------------

  /**
   * The keys will be checked and stored in the tmp directory.
   * Returns the temporary key file (or null on error).
   */
  private saveKeysToTemp(): string | null {
    if (!this.isValidKeyFileErrorToast(this.checkDumpAndUpdateLines())) {
      return null;
    }
    let fileName: string = this.fileName;
    if (fileName.length === 0) {
      // The key file has no name. Use date and time as name.
      const now: Date = new Date();
      const month: number = now.getMonth() + 1;
      const day: number = now.getDate();
      const hour: number = now.getHours();
      const minute: number = now.getMinutes();
      const second: number = now.getSeconds();
      fileName = now.getFullYear()
        + '-' + (month < 10 ? '0' : '') + month
        + '-' + (day < 10 ? '0' : '') + day
        + '_' + (hour < 10 ? '0' : '') + hour
        + '-' + (minute < 10 ? '0' : '') + minute
        + '-' + (second < 10 ? '0' : '') + second;
    }
    // Save key file to a temporary file which will be
    // attached for sharing (and stored in the tmp folder).
    const file: string = MctFiles.getFile(MctFiles.TMP_DIR + '/' + fileName);
    if (!MctFiles.writeLines(file, this.lines)) {
      NfcService.toast('错误：保存数据时出错', true);
      return null;
    }
    return file;
  }

  /**
   * Share a key file as "file://" stream resource (e.g. as e-mail
   * attachment). A dialog will be displayed in which the user can
   * choose between apps that are willing to handle the file.
   */
  private shareKeyFile(): void {
    const file: string | null = this.saveKeysToTemp();
    if (file === null) {
      return;
    }
    // Share file.
    NfcService.shareTextFile(file);
  }

  /**
   * Export the keys using the ImportExportTool. For exporting, the
   * key file will be saved as temporary file.
   */
  private exportKeys(): void {
    const file: string | null = this.saveKeysToTemp();
    if (file === null) {
      return;
    }
    const params: ImportExportToolParams = new ImportExportToolParams();
    params.filePath = file;
    params.isDumpFile = false;
    this.pathStack.pushPathByName('importExportTool', params);
  }

  // ---------------- Remove duplicates ----------------

  /** Remove duplicates (keys) from the key file. */
  private removeDuplicates(): void {
    if (this.isValidKeyFileErrorToast(this.checkDumpAndUpdateLines())) {
      const newLines: string[] = [];
      for (let i = 0; i < this.lines.length; i++) {
        const line: string = this.lines[i].trim();
        if (line.length === 0 || line.startsWith('#')) {
          // Add comments for sure.
          newLines.push(line);
          continue;
        }
        if (newLines.indexOf(line) === -1) {
          // Add key if it is not already added.
          newLines.push(line);
        }
      }
      this.lines = newLines;
      this.setKeyArrayAsText(newLines);
    }
  }

  // ---------------- Back handling ----------------

  /**
   * Show a dialog in which the user can chose between "save",
   * "don't save" and "cancel", if there are unsaved changes.
   */
  private onBackFromEditor(): boolean {
    if (!this.initialized) {
      return false;
    }
    if (this.keysChanged) {
      this.dialogCtrl = new CustomDialogController({
        builder: MctDialog({
          titleText: '未保存的更改',
          messageText: '存在未保存的更改！'
            + '\n您要保存这些更改吗？',
          button1Text: '保存',
          button1Action: (checked: boolean): void => {
            // Save.
            this.closeAfterSuccessfulSave = true;
            this.onSave();
          },
          button3Text: '取消',
          button3Action: (checked: boolean): void => {
            // Cancel. Do nothing.
          },
          button2Text: '不保存',
          button2Action: (checked: boolean): void => {
            // Don't save.
            this.pathStack.pop();
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
      return true;
    }
    return false;
  }

  // ---------------- Menu ----------------

  @Builder
  editorMenuBuilder() {
    Menu() {
      MenuItem({ content: '保存' })
        .onClick(() => {
          this.onSave();
        })
      MenuItem({ content: '分享' })
        .onClick(() => {
          this.shareKeyFile();
        })
      MenuItem({ content: '导出密钥' })
        .onClick(() => {
          this.exportKeys();
        })
      MenuItem({ content: '移除重复项' })
        .onClick(() => {
          this.removeDuplicates();
        })
    }
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('⋮')
            .fontSize(22)
            .fontColor(MctTheme.fg)
            .padding({ left: 12, right: 10, top: 2, bottom: 2 })
            .bindMenu(this.editorMenuBuilder)
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ top: 2 })

        TextArea({ text: this.keysText, placeholder: 'HEX，每行 6 字节' })
          .onChange((value: string): void => {
            this.keysText = value;
            if (this.textWatcherActive) {
              // Text was changed.
              this.keysChanged = true;
            }
          })
          .layoutWeight(1)
          .width('100%')
          .fontSize(14)
          .fontColor(MctTheme.fg)
          .fontFamily('monospace')
          .placeholderColor(MctTheme.fgSecondary)
          .placeholderFont({ size: 14 })
          .backgroundColor(MctTheme.bg)
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title(this.pageTitle)
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: KeyEditorParams = (ctx.pathInfo.param as KeyEditorParams) ?? new KeyEditorParams();
      if (p.chosenFile.length === 0) {
        // No key file chosen. Error. Exit.
        this.pathStack.pop();
        return;
      }
      const segIdx: number = p.chosenFile.lastIndexOf('/');
      this.fileName = segIdx !== -1 ? p.chosenFile.substring(segIdx + 1) : p.chosenFile;
      this.pageTitle = '密钥文件编辑器（' + this.fileName + '）';
      if (MctFiles.exists(p.chosenFile)) {
        const keyDump: string[] | null = MctFiles.readFileLines(p.chosenFile, true);
        if (keyDump === null) {
          // Error. Exit.
          this.pathStack.pop();
          return;
        }
        this.setKeyArrayAsText(keyDump);
      }
      // From now on, changes to the text count as changes
      // (Android: the TextWatcher becomes active here).
      this.textWatcherActive = true;
      this.initialized = true;
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
    .onBackPressed((): boolean => {
      return this.onBackFromEditor();
    })
  }
}

@Builder
export function KeyEditorBuilder() {
  KeyEditorPage()
}
