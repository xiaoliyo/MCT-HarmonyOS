/**
 * Import/Export Tool (port of
 * de.syss.MifareClassicTool.Activities.ImportExportTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * A simple tool to import and export dump files in and from different file
 * formats. Supported are .mct (Mifare Classic Tool), .bin/.mfd (Proxmark,
 * libnfc, mfoc), .eml (Proxmark emulator) and .json (Proxmark, Chameleon
 * Mini GUI). Additionally, all dumps and keys can be exported as a ZIP
 * backup (and restored - an addition of this port).
 */

import { picker, fileIo, fileUri } from '@kit.CoreFileKit';
import { zlib, BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';
import { MctApp } from '../common/MctApp';
import { MctFiles } from '../common/MctFiles';
import { HexUtils } from '../common/HexUtils';
import { MifareUtils } from '../common/MifareUtils';
import { NfcService } from '../common/NfcService';
import { MctTheme } from '../common/ui/MctTheme';
import { FileChooserParams } from './FileChooser';

/**
 * Input parameters of this page (the Intent extras of the Android
 * ImportExportTool activity). If filePath is set, the tool is opened
 * by another page to export the given file.
 */
export class ImportExportToolParams {
  filePath: string = '';
  isDumpFile: boolean = false;
}

/** File types/extensions (FileType enum of the Android original). */
class FileType {
  static readonly MCT: string = '.mct';
  static readonly KEYS: string = '.keys';
  static readonly JSON: string = '.json';
  static readonly BIN: string = '.bin';
  static readonly EML: string = '.eml';
}

/** Raw model of a Proxmark/Chameleon Mini GUI .json dump. */
class JsonDumpModel {
  Created?: string;
  FileType?: string;
  blocks?: Record<string, Object>;
}

/** Files bigger than 10 MiB are treated as "too big" (out of memory). */
const IET_MAX_FILE_SIZE: number = 10 * 1024 * 1024;

/** Get the file name of a document URI (Common.getFileName). */
function getFileNameFromUri(uri: string): string {
  try {
    const fu: fileUri.FileUri = new fileUri.FileUri(uri);
    if (fu.name.length > 0) {
      return fu.name;
    }
  } catch (e) {
    // Fall through to manual parsing.
  }
  const cut: number = uri.lastIndexOf('/');
  if (cut !== -1) {
    return uri.substring(cut + 1);
  }
  return uri;
}

/** Check whether a document URI points to a file bigger than maxSize. */
function isUriTooBig(uri: string, maxSize: number): boolean {
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(file.fd);
    return stat.size > maxSize;
  } catch (e) {
    return false;
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (e2) {
        // Ignore.
      }
    }
  }
}

/** Read a document URI as raw bytes (Common.readUriRaw). */
function readUriRaw(uri: string): Uint8Array | null {
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
    const stat: fileIo.Stat = fileIo.statSync(file.fd);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    return new Uint8Array(buf);
  } catch (e) {
    return null;
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (e2) {
        // Ignore.
      }
    }
  }
}

/** Read a document URI as bytes (numbers 0-255). Returns null on error. */
function readUriBytes(uri: string): number[] | null {
  const raw: Uint8Array | null = readUriRaw(uri);
  if (raw === null) {
    return null;
  }
  return MctFiles.uint8ToArray(raw);
}

/**
 * Read a document URI line by line (Common.readUriLineByLine).
 * If readAll is false, comments (#), empty lines and trailing
 * comments are removed.
 */
function readUriLines(uri: string, readAll: boolean): string[] | null {
  const raw: Uint8Array | null = readUriRaw(uri);
  if (raw === null) {
    return null;
  }
  const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
  const content: string = decoder.decodeToString(raw);
  const rawLines: string[] = content.split(/\r\n|\r|\n/);
  const lines: string[] = [];
  for (let i: number = 0; i < rawLines.length; i++) {
    let line: string = rawLines[i].trim();
    if (!readAll) {
      if (line.startsWith('#') || line.length === 0) {
        continue;
      }
      line = line.split('#')[0];
      line = line.trim();
    }
    lines.push(line);
  }
  if (lines.length === 0) {
    lines.push('');
  }
  return lines;
}

/** Write raw bytes to a document URI (Common.saveFile(Uri, byte[], ...)). */
function writeBytesToUri(uri: string, bytes: number[]): boolean {
  if (uri.length === 0 || bytes.length === 0) {
    return false;
  }
  let file: fileIo.File | null = null;
  try {
    file = fileIo.openSync(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    const buf: ArrayBuffer = new ArrayBuffer(bytes.length);
    const u8: Uint8Array = new Uint8Array(buf);
    for (let i: number = 0; i < bytes.length; i++) {
      u8[i] = bytes[i] & 0xFF;
    }
    fileIo.writeSync(file.fd, buf);
    return true;
  } catch (e) {
    return false;
  } finally {
    if (file !== null) {
      try {
        fileIo.closeSync(file);
      } catch (e2) {
        // Ignore.
      }
    }
  }
}

/** Write text lines (joined with \n) to a document URI. */
function writeTextToUri(uri: string, text: string): boolean {
  const encoder: util.TextEncoder = new util.TextEncoder();
  return writeBytesToUri(uri, MctFiles.uint8ToArray(encoder.encodeInto(text)));
}

/**
 * Parse a .json dump (Proxmark/Chameleon Mini GUI format) and extract
 * its blocks (block number -> block data). Returns null on error.
 */
function parseJsonBlocks(jsonText: string): Map<number, string> | null {
  let parsed: JsonDumpModel;
  try {
    parsed = JSON.parse(jsonText) as JsonDumpModel;
  } catch (e) {
    return null;
  }
  if (parsed === null || parsed === undefined) {
    return null;
  }
  if (parsed.blocks === null || parsed.blocks === undefined) {
    return null;
  }
  const blocks: Map<number, string> = new Map<number, string>();
  for (let i: number = 0; i < 256; i++) {
    const key: string = i.toString();
    const value: Object | undefined = parsed.blocks[key];
    if (value !== undefined && typeof value === 'string') {
      blocks.set(i, value as string);
    }
  }
  if (blocks.size < 1) {
    return null;
  }
  return blocks;
}

/** Remove a directory and all of its content (recursively). */
function removeDirRecursive(dir: string): void {
  if (!MctFiles.exists(dir)) {
    return;
  }
  try {
    const names: string[] = MctFiles.listFileNames(dir, true);
    for (let i: number = 0; i < names.length; i++) {
      const full: string = dir + '/' + names[i];
      if (MctFiles.isDir(full)) {
        removeDirRecursive(full);
      } else {
        MctFiles.deleteFile(full);
      }
    }
    fileIo.rmdirSync(dir);
  } catch (e) {
    // Ignore.
  }
}

@Component
struct ImportExportToolPage {
  private pathStack: NavPathStack = new NavPathStack();
  // Was this tool opened by another page to export a file?
  private isCalledWithExportFile: boolean = false;
  private isExport: boolean = false;
  private isDumpFile: boolean = false;
  private file: string = '';
  private convertedContent: string[] | null = null;
  private fileType: string = FileType.MCT;
  // File to export, passed by another page via ImportExportToolParams.
  private pendingIntentFile: string = '';
  private pendingIntentIsDumpFile: boolean = false;
  // File chosen by the FileChooser (EXPORT_FILE_CHOSEN result).
  private pendingExportFile: string = '';

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  // ---------------- Small helpers ----------------

  /** Common.isValidDumpErrorToast equivalent. */
  private isValidDumpErrorToast(errorCode: number): void {
    if (errorCode === 1) {
      NfcService.toast('错误：某些扇区不是 4 或 16 个块（行）', true);
    } else if (errorCode === 2) {
      NfcService.toast('错误：某些块包含无效数据（非十六进制）', true);
    } else if (errorCode === 3) {
      NfcService.toast('错误：某些块不足 16 字节（32 个字符）', true);
    } else if (errorCode === 4) {
      NfcService.toast('错误：扇区超出范围（< 0 或 > 39）', true);
    } else if (errorCode === 5) {
      NfcService.toast('错误：同一扇区编号出现多次', true);
    } else if (errorCode === 6) {
      NfcService.toast('错误：转储为空', true);
    }
  }

  /** Common.isValidKeyFileErrorToast equivalent. */
  private isValidKeyFileErrorToast(errorCode: number): boolean {
    if (errorCode === 0) {
      return true;
    }
    if (errorCode === 1) {
      NfcService.toast('错误：至少需要一个密钥', true);
    } else if (errorCode === 2) {
      NfcService.toast('错误：某些密钥包含无效数据（非十六进制）', true);
    } else if (errorCode === 3) {
      NfcService.toast('错误：某些密钥不足 6 字节（12 个字符）', true);
    }
    return false;
  }

  // ---------------- File type chooser menus (context menus) ----------------

  /** Show the dump file type chooser menu (menu/dump_file_types.xml). */
  private showDumpFileTypeChooserMenu(): void {
    const options: promptAction.ActionMenuOptions = {
      buttons: [
        { text: '.json（Proxmark、Chameleon Mini GUI）', color: MctTheme.fg },
        { text: '.bin/.mfd/.dump（Proxmark、libnfc、mfoc 等）', color: MctTheme.fg },
        { text: '.eml（Proxmark 模拟器）', color: MctTheme.fg },
        { text: '.mct（MIFARE Classic Tool）', color: MctTheme.fg }
      ]
    };
    this.getUIContext().getPromptAction().showActionMenu(options)
      .then((response: promptAction.ActionMenuSuccessResponse): void => {
        if (response.index === 0) {
          this.onFileTypeSelected(FileType.JSON);
        } else if (response.index === 1) {
          this.onFileTypeSelected(FileType.BIN);
        } else if (response.index === 2) {
          this.onFileTypeSelected(FileType.EML);
        } else if (response.index === 3) {
          this.onFileTypeSelected(FileType.MCT);
        }
      })
      .catch((error: BusinessError): void => {
        // Menu was canceled.
      });
  }

  /** Show the keys file type chooser menu (menu/keys_file_types.xml). */
  private showKeysFileTypeChooserMenu(): void {
    const options: promptAction.ActionMenuOptions = {
      buttons: [
        { text: '.bin（Proxmark、Chameleon Mini GUI）', color: MctTheme.fg },
        { text: '.keys/.dic/.txt（MIFARE Classic Tool、Proxmark）', color: MctTheme.fg }
      ]
    };
    this.getUIContext().getPromptAction().showActionMenu(options)
      .then((response: promptAction.ActionMenuSuccessResponse): void => {
        if (response.index === 0) {
          this.onFileTypeSelected(FileType.BIN);
        } else if (response.index === 1) {
          this.onFileTypeSelected(FileType.KEYS);
        }
      })
      .catch((error: BusinessError): void => {
        // Menu was canceled.
      });
  }

  /**
   * Save the selected file type and continue with the import or
   * export process (onContextItemSelected).
   */
  private onFileTypeSelected(fileType: string): void {
    this.fileType = fileType;
    if (this.isExport) {
      // Convert file and export.
      this.readAndConvertExportData(this.file);
    } else {
      // Let the user pick the file to import.
      this.showImportFileChooser();
    }
  }

  // ---------------- Import / Export buttons ----------------

  /** Start the dump import process (onImportDump). */
  private onImportDump(): void {
    this.isExport = false;
    this.isDumpFile = true;
    this.showDumpFileTypeChooserMenu();
  }

  /** Start the dump export process (onExportDump). */
  private onExportDump(): void {
    this.isExport = true;
    this.isDumpFile = true;
    this.pathStack.pushPathByName('fileChooser', new FileChooserParams(
      MctFiles.getDumpsDir(), '选择转储文件', '', '导出转储', false,
      (file: string | null): void => {
        if (file !== null) {
          this.pendingExportFile = file;
        }
      }));
  }

  /** Start the keys import process (onImportKeys). */
  private onImportKeys(): void {
    this.isExport = false;
    this.isDumpFile = false;
    this.showKeysFileTypeChooserMenu();
  }

  /** Start the keys export process (onExportKeys). */
  private onExportKeys(): void {
    this.isExport = true;
    this.isDumpFile = false;
    this.pathStack.pushPathByName('fileChooser', new FileChooserParams(
      MctFiles.getKeysDir(), '选择密钥文件', '', '导出密钥', false,
      (file: string | null): void => {
        if (file !== null) {
          this.pendingExportFile = file;
        }
      }));
  }

  // ---------------- Backup / Restore ----------------

  /** Create a full backup of all dump and key files (onBackupAll). */
  private onBackupAll(): void {
    const now: Date = new Date();
    const pad = (n: number): string => (n < 10 ? '0' : '') + n.toString();
    const dateFormatted: string = now.getFullYear() + '-'
      + pad(now.getMonth() + 1) + '-' + pad(now.getDate());
    this.showSaveFileChooser('MCT-Backup_' + dateFormatted + '.zip',
      (uri: string): void => {
        this.backupDumpsAndKeys(uri);
      });
  }

  /** Restore a backup ZIP created by onBackupAll (addition of this port). */
  private onRestoreBackup(): void {
    const selectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    selectOptions.fileSuffixFilters = ['.zip'];
    selectOptions.maxSelectNumber = 1;
    const docPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(MctApp.getContext());
    docPicker.select(selectOptions)
      .then((uris: Array<string>): void => {
        if (uris.length > 0 && uris[0].length > 0) {
          this.restoreBackup(uris[0]);
        }
      })
      .catch((error: BusinessError): void => {
        // Selection was canceled.
      });
  }

  /**
   * Create a ZIP file containing all keys and dumps and save it to
   * the destination URI (backupDumpsAndKeys).
   */
  private async backupDumpsAndKeys(destUri: string): Promise<void> {
    const tmpDir: string = MctFiles.getTmpDir();
    const stagingDir: string = tmpDir + '/backup';
    const stagingHome: string = stagingDir + '/MifareClassicTool';
    const backupZip: string = tmpDir + '/MCT-Backup.zip';
    removeDirRecursive(stagingDir);
    MctFiles.deleteFile(backupZip);
    try {
      // Stage all key and dump files (keys first, like the Android
      // original which writes the keys directory first).
      const dirs: string[] = [MctFiles.getKeysDir(), MctFiles.getDumpsDir()];
      const dirNames: string[] = [MctFiles.KEYS_DIR, MctFiles.DUMPS_DIR];
      let stagedCount: number = 0;
      for (let d: number = 0; d < dirs.length; d++) {
        const files: string[] = MctFiles.listFileNames(dirs[d]);
        if (files.length === 0) {
          continue;
        }
        fileIo.mkdirSync(stagingHome + '/' + dirNames[d], true);
        for (let i: number = 0; i < files.length; i++) {
          const bytes: number[] = MctFiles.readBytes(dirs[d] + '/' + files[i]);
          if (!MctFiles.writeBytes(stagingHome + '/' + dirNames[d] + '/' + files[i], bytes)) {
            throw new Error('Error while staging backup files.');
          }
          stagedCount++;
        }
      }
      if (stagedCount === 0) {
        // No files to backup. Create an empty ZIP (end of central
        // directory record only), like the Android original (which
        // writes a ZIP without entries).
        const emptyZip: number[] = [0x50, 0x4B, 0x05, 0x06, 0, 0, 0, 0, 0, 0,
          0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        if (!writeBytesToUri(destUri, emptyZip)) {
          throw new Error('Error while saving backup.');
        }
      } else {
        // Compress the staged files (keep the "MifareClassicTool"
        // folder as the top level folder, like the Android original).
        const options: zlib.Options = {
          level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
          keepTopLevelFolder: true
        };
        await zlib.compressFile(stagingHome, backupZip, options);
        // Save the ZIP to the chosen destination.
        if (!writeBytesToUri(destUri, MctFiles.readBytes(backupZip))) {
          throw new Error('Error while saving backup.');
        }
      }
      NfcService.toast('备份已创建', true);
    } catch (e) {
      NfcService.toast('创建完整备份时出错', true);
    } finally {
      removeDirRecursive(stagingDir);
      MctFiles.deleteFile(backupZip);
    }
  }

  /**
   * Extract a backup ZIP and restore all key and dump files
   * (counterpart of backupDumpsAndKeys).
   */
  private async restoreBackup(zipUri: string): Promise<void> {
    const tmpDir: string = MctFiles.getTmpDir();
    const tmpZip: string = tmpDir + '/restore.zip';
    const extractDir: string = tmpDir + '/restore';
    removeDirRecursive(extractDir);
    MctFiles.deleteFile(tmpZip);
    try {
      // Copy the ZIP into the app sandbox (zlib works on sandbox paths).
      await fileIo.copy(zipUri, tmpZip);
      fileIo.mkdirSync(extractDir, true);
      await zlib.decompressFile(tmpZip, extractDir);
      const count: number = this.restoreFilesFromDir(extractDir);
      if (count > 0) {
        NfcService.toast('备份已恢复', true);
      } else {
        NfcService.toast('恢复备份时出错', true);
      }
    } catch (e) {
      NfcService.toast('恢复备份时出错', true);
    } finally {
      MctFiles.deleteFile(tmpZip);
      removeDirRecursive(extractDir);
    }
  }

  /**
   * Restore all key and dump files from an extracted backup directory
   * (recursively). Files are routed by their parent directory name
   * (key-files/dump-files) or, if unknown, by their file extension.
   * Returns the number of restored files.
   */
  private restoreFilesFromDir(dir: string): number {
    let count: number = 0;
    const names: string[] = MctFiles.listFileNames(dir, true);
    for (let i: number = 0; i < names.length; i++) {
      const name: string = names[i];
      const full: string = dir + '/' + name;
      if (MctFiles.isDir(full)) {
        count += this.restoreFilesFromDir(full);
        continue;
      }
      // Route by parent directory name or file extension.
      const parentName: string = dir.substring(dir.lastIndexOf('/') + 1);
      let destDir: string = '';
      if (parentName === MctFiles.KEYS_DIR) {
        destDir = MctFiles.getKeysDir();
      } else if (parentName === MctFiles.DUMPS_DIR) {
        destDir = MctFiles.getDumpsDir();
      } else {
        const dot: number = name.lastIndexOf('.');
        const ext: string = dot !== -1 ? name.substring(dot).toLowerCase() : '';
        if (ext === '.mct' || ext === '.bin' || ext === '.eml' || ext === '.json') {
          destDir = MctFiles.getDumpsDir();
        } else if (ext === '.keys' || ext === '.dic' || ext === '.txt') {
          destDir = MctFiles.getKeysDir();
        }
      }
      if (destDir.length === 0) {
        continue;
      }
      if (MctFiles.writeBytes(destDir + '/' + name, MctFiles.readBytes(full))) {
        count++;
      }
    }
    return count;
  }

  // ---------------- File choosers ----------------

  /** Show the system file chooser and let the user pick file(s) to import. */
  private showImportFileChooser(): void {
    const selectOptions: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
    selectOptions.maxSelectNumber = 10;
    const docPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(MctApp.getContext());
    docPicker.select(selectOptions)
      .then((uris: Array<string>): void => {
        this.readConvertAndSaveImportData(uris);
      })
      .catch((error: BusinessError): void => {
        // Selection was canceled.
      });
  }

  /**
   * Show the "save-as" dialog as provided by the system to let the user
   * choose a destination for exported files (showExportFileChooser).
   */
  private showSaveFileChooser(fileName: string, onResult: (uri: string) => void): void {
    const saveOptions: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
    saveOptions.newFileNames = [fileName];
    const docPicker: picker.DocumentViewPicker =
      new picker.DocumentViewPicker(MctApp.getContext());
    docPicker.save(saveOptions)
      .then((uris: Array<string>): void => {
        if (uris.length > 0 && uris[0].length > 0) {
          onResult(uris[0]);
        }
      })
      .catch((error: BusinessError): void => {
        // Saving was canceled.
      });
  }

  // ---------------- Import ----------------

  /**
   * Import the file(s) by reading, converting and saving them
   * (readConvertAndSaveImportData).
   */
  private readConvertAndSaveImportData(uris: Array<string>): void {
    for (let u: number = 0; u < uris.length; u++) {
      const uri: string = uris[u];
      // Basic protection against out of memory (the Android original
      // catches OutOfMemoryError).
      if (isUriTooBig(uri, IET_MAX_FILE_SIZE)) {
        NfcService.toast('错误：文件过大（内存不足）', true);
        continue;
      }
      // Read file.
      let content: string[] | null = null;
      if (this.fileType !== FileType.BIN) {
        // Read text file (including comments, if it is a key file).
        content = readUriLines(uri, !this.isDumpFile);
      } else {
        // Read binary file and convert it to a string (since convert()
        // works only on strings).
        const bytes: number[] | null = readUriBytes(uri);
        if (bytes !== null) {
          let binary: string = '';
          for (let i: number = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i] & 0xFF);
          }
          content = [binary];
        }
      }
      if (content === null) {
        NfcService.toast('错误：无法读取文件', true);
        continue;
      }

      // Prepare file names and paths.
      let fileName: string = getFileNameFromUri(uri);
      if (fileName.indexOf('.') !== -1) {
        fileName = fileName.substring(0, fileName.lastIndexOf('.'));
      }
      let destFileName: string = fileName;
      let destPath: string = '';

      // Convert key or dump file.
      let convertedContent: string[] | null = null;
      if (this.isDumpFile) {
        convertedContent = this.convertDump(content, this.fileType, FileType.MCT);
        destFileName += FileType.MCT;
        destPath = MctFiles.DUMPS_DIR;
      } else {
        convertedContent = this.convertKeys(content, this.fileType, FileType.KEYS);
        destFileName += FileType.KEYS;
        destPath = MctFiles.KEYS_DIR;
      }
      if (convertedContent === null) {
        // Error during conversion.
        continue;
      }

      // Save converted file.
      const destination: string = MctFiles.getFile(destPath + '/' + destFileName);
      if (MctFiles.writeLines(destination, convertedContent)) {
        NfcService.toast('文件已导入', false);
      } else {
        NfcService.toast('错误：保存数据时出错', true);
      }
    }
  }

  // ---------------- Export ----------------

  /**
   * Export the file by reading, converting and showing the save-to
   * dialog (readAndConvertExportData).
   */
  private readAndConvertExportData(path: string): void {
    // Include comments in key files that are exported as .keys/.txt/.dic.
    const includeComments: boolean = !this.isDumpFile && this.fileType === FileType.KEYS;
    const content: string[] | null = MctFiles.readFileLines(path, includeComments);
    if (content === null) {
      return;
    }

    // Prepare file names and paths.
    let fileName: string = path.substring(path.lastIndexOf('/') + 1);
    if (fileName.indexOf('.') !== -1) {
      fileName = fileName.substring(0, fileName.lastIndexOf('.'));
    }
    const destFileName: string = fileName + this.fileType;

    // Convert key or dump file.
    let convertedContent: string[] | null = null;
    if (this.isDumpFile) {
      convertedContent = this.convertDump(content, FileType.MCT, this.fileType);
    } else {
      convertedContent = this.convertKeys(content, FileType.KEYS, this.fileType);
    }
    if (convertedContent === null) {
      // Error during conversion.
      return;
    }

    // Save converted content and show destination chooser.
    this.convertedContent = convertedContent;
    this.showSaveFileChooser(destFileName,
      (uri: string): void => {
        this.saveConvertedDataToContent(uri);
      });
  }

  /**
   * Save the converted content with respect to the file type to a
   * destination URI and leave this tool if it was called by another
   * page with a file to export (saveConvertedDataToContent).
   */
  private saveConvertedDataToContent(destUri: string): void {
    const convertedContent: string[] | null = this.convertedContent;
    if (convertedContent === null || convertedContent.length === 0 || destUri.length === 0) {
      NfcService.toast('错误：无法转换', true);
      return;
    }
    let success: boolean = false;
    if (this.fileType !== FileType.BIN) {
      success = writeTextToUri(destUri, convertedContent.join('\n'));
    } else {
      const binary: string = convertedContent[0];
      const bytes: number[] = [];
      for (let i: number = 0; i < binary.length; i++) {
        bytes.push(binary.charCodeAt(i) & 0xFF);
      }
      success = writeBytesToUri(destUri, bytes);
    }
    if (success) {
      NfcService.toast('文件已导出', true);
    } else {
      NfcService.toast('错误：保存数据时出错', true);
    }

    if (this.isCalledWithExportFile) {
      // Exit this tool if it was called by another page with
      // a file to export.
      this.pathStack.pop();
    }
  }

  // ---------------- Conversion ----------------

  /**
   * Convert dump source from srcType to destType. The formats .mct,
   * .json, .eml and .bin are supported. The intermediate is always
   * JSON. If the srcType or the destType is BIN, the source/return
   * value must be a string array with only one string with each char
   * representing one byte (MSB=0). Returns the converted data or
   * null on error (convertDump).
   */
  private convertDump(source: string[] | null, srcType: string, destType: string): string[] | null {
    if (source === null || source.length === 0 || srcType.length === 0 || destType.length === 0) {
      return null;
    }
    // Convert source to json.
    let json: string[] = [];
    let block: string = '';
    if (srcType !== FileType.JSON) {
      json.push('{');
      json.push('  "Created": "MifareClassicTool",');
      json.push('  "FileType": "mfcard",');
      json.push('  "blocks": {');
    }
    if (srcType === FileType.JSON) {
      json = source.slice();
    } else if (srcType === FileType.MCT) {
      const err: number = MifareUtils.isValidDump(source, true);
      if (err !== 0) {
        this.isValidDumpErrorToast(err);
        return null;
      }
      let blockNumber: number = 0;
      for (let i: number = 0; i < source.length; i++) {
        const line: string = source[i];
        if (line.startsWith('+')) {
          const sectorNumber: number = Number.parseInt(line.split(': ')[1], 10);
          if (sectorNumber < 32) {
            blockNumber = sectorNumber * 4;
          } else {
            blockNumber = 32 * 4 + (sectorNumber - 32) * 16;
          }
          continue;
        }
        block = '    "' + blockNumber + '": "' + line + '",';
        json.push(block);
        blockNumber += 1;
      }
    } else if (srcType === FileType.BIN) {
      const binary: string = source[0];
      if (binary.length !== 320 && binary.length !== 1024
        && binary.length !== 2048 && binary.length !== 4096) {
        // Error. Not a complete dump (MIFARE mini, 1k, 2k, 4k).
        NfcService.toast('错误：转储不完整或过大', true);
        return null;
      }
      // In this case: chars = bytes. Get 16 bytes and convert.
      for (let i: number = 0; i < binary.length; i += 16) {
        const blockBytes: number[] = [];
        for (let j: number = 0; j < 16; j++) {
          blockBytes.push(binary.charCodeAt(i + j) & 0xFF);
        }
        block = '    "' + (i / 16) + '": "' + HexUtils.bytes2Hex(blockBytes) + '",';
        json.push(block);
      }
    } else if (srcType === FileType.EML) {
      if (source.length !== 20 && source.length !== 64
        && source.length !== 128 && source.length !== 256) {
        // Error. Not a complete dump (MIFARE mini, 1k, 2k, 4k).
        NfcService.toast('错误：转储不完整或过大', true);
        return null;
      }
      for (let i: number = 0; i < source.length; i++) {
        if (source[i].length === 0) {
          // Error. Empty line in .eml file.
          NfcService.toast('错误：转储不完整或过大', true);
          return null;
        }
        block = '    "' + i + '": "' + source[i] + '",';
        json.push(block);
      }
    }
    if (srcType !== FileType.JSON) {
      // Remove the trailing comma from the last block.
      block = block.replace(/,/g, '');
      json.splice(json.length - 1, 1);
      json.push(block);
      json.push('  }');
      json.push('}');
    }

    // Check source conversion.
    if (json.length <= 6) {
      // Error converting source file.
      NfcService.toast('错误：无法转换', true);
      return null;
    }
    const blocks: Map<number, string> | null = parseJsonBlocks(json.join(''));
    if (blocks === null) {
      // Error parsing json file.
      NfcService.toast('错误：无法转换', true);
      return null;
    }

    // Convert json to destType.
    let dest: string[] | null = null;
    if (destType === FileType.JSON) {
      dest = json;
    } else if (destType === FileType.MCT) {
      const exportLines: string[] = [];
      let lastKnownSector: number = -1;
      // Go through all possible blocks in a sorted order.
      for (let blockNr: number = 0; blockNr < 256; blockNr++) {
        const blockData: string | undefined = blocks.get(blockNr);
        if (blockData === undefined) {
          // Block does not exist. Skip.
          continue;
        }
        const sector: number = MifareUtils.blockToSector(blockNr);
        if (lastKnownSector !== sector) {
          lastKnownSector = sector;
          exportLines.push('+Sector: ' + sector);
        }
        exportLines.push(blockData);
      }
      dest = exportLines;
    } else if (destType === FileType.BIN) {
      if (blocks.size !== 20 && blocks.size !== 64
        && blocks.size !== 128 && blocks.size !== 256) {
        // Error. Not a complete dump (MIFARE mini, 1k, 2k, 4k).
        NfcService.toast('错误：转储不完整或过大', true);
        return null;
      }
      let binary: string = '';
      for (let i: number = 0; i < blocks.size; i++) {
        const blockData: string | undefined = blocks.get(i);
        if (blockData === undefined) {
          // Error. Not a complete dump (MIFARE mini, 1k, 2k, 4k).
          NfcService.toast('错误：转储不完整或过大', true);
          return null;
        }
        const bytes: number[] | null = HexUtils.hex2Bytes(blockData);
        if (bytes === null) {
          // Error. Invalid block.
          NfcService.toast('错误：无法转换', true);
          return null;
        }
        for (let j: number = 0; j < bytes.length; j++) {
          binary += String.fromCharCode(bytes[j] & 0xFF);
        }
      }
      dest = [binary];
    } else if (destType === FileType.EML) {
      if (blocks.size !== 20 && blocks.size !== 64
        && blocks.size !== 128 && blocks.size !== 256) {
        // Error. Not a complete dump (MIFARE mini, 1k, 2k, 4k).
        NfcService.toast('错误：转储不完整或过大', true);
        return null;
      }
      dest = [];
      for (let i: number = 0; i < blocks.size; i++) {
        const blockData: string | undefined = blocks.get(i);
        if (blockData === undefined) {
          // Error. Not a complete dump (MIFARE mini, 1k, 2k, 4k).
          NfcService.toast('错误：转储不完整或过大', true);
          return null;
        }
        dest.push(blockData);
      }
    }
    return dest;
  }

  /**
   * Convert keys source from srcType to destType. The formats .keys
   * and .bin are supported. If the srcType or the destType is BIN,
   * the source/return value must be a string array with only one
   * string with each char representing one byte (MSB=0). Returns the
   * converted data or null on error (convertKeys).
   */
  private convertKeys(source: string[] | null, srcType: string, destType: string): string[] | null {
    if (source === null || source.length === 0 || srcType.length === 0 || destType.length === 0) {
      return null;
    }
    // Convert source to strings.
    let keys: string[] | null = null;
    if (srcType === FileType.KEYS) {
      const err: number = MifareUtils.isValidKeyFile(source);
      if (err !== 0) {
        this.isValidKeyFileErrorToast(err);
        return null;
      }
      keys = source;
    } else if (srcType === FileType.BIN) {
      const binary: string = source[0];
      const len: number = binary.length;
      if (len > 0 && len % 6 !== 0) {
        // Error. Not a multiple of 6 bytes.
        NfcService.toast('错误：不是有效的密钥文件', true);
        return null;
      }
      keys = [];
      // In this case: chars = bytes. Get 6 bytes and convert.
      for (let i: number = 0; i < len; i += 6) {
        const keyBytes: number[] = [];
        for (let j: number = 0; j < 6; j++) {
          keyBytes.push(binary.charCodeAt(i + j) & 0xFF);
        }
        keys.push(HexUtils.bytes2Hex(keyBytes));
      }
    }

    if (keys === null) {
      // Error converting source file.
      NfcService.toast('错误：无法转换', true);
      return null;
    }

    let dest: string[] | null = null;
    if (destType === FileType.KEYS) {
      dest = keys;
    } else if (destType === FileType.BIN) {
      let binary: string = '';
      for (let i: number = 0; i < keys.length; i++) {
        const bytes: number[] | null = HexUtils.hex2Bytes(keys[i]);
        if (bytes === null) {
          // Error. Invalid key.
          NfcService.toast('错误：无法转换', true);
          return null;
        }
        for (let j: number = 0; j < bytes.length; j++) {
          binary += String.fromCharCode(bytes[j] & 0xFF);
        }
      }
      dest = [binary];
    }
    return dest;
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Scroll() {
        Column() {
          Button() {
            Row({ space: 8 }) {
              Image($r('app.media.arrow_up'))
                .width(20)
                .height(20)
              Text('导入转储')
                .fontSize(16)
                .fontColor(MctTheme.fg)
            }
          }
          .width('100%')
          .height(48)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ top: 6 })
          .onClick(() => {
            this.onImportDump();
          })
          Button() {
            Row({ space: 8 }) {
              Image($r('app.media.arrow_down'))
                .width(20)
                .height(20)
              Text('导出转储')
                .fontSize(16)
                .fontColor(MctTheme.fg)
            }
          }
          .width('100%')
          .height(48)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ top: 6 })
          .onClick(() => {
            this.onExportDump();
          })

          // Separator.
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin({ left: 5, right: 5, top: 18, bottom: 18 })

          Button() {
            Row({ space: 8 }) {
              Image($r('app.media.arrow_up'))
                .width(20)
                .height(20)
              Text('导入密钥')
                .fontSize(16)
                .fontColor(MctTheme.fg)
            }
          }
          .width('100%')
          .height(48)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ top: 6 })
          .onClick(() => {
            this.onImportKeys();
          })
          Button() {
            Row({ space: 8 }) {
              Image($r('app.media.arrow_down'))
                .width(20)
                .height(20)
              Text('导出密钥')
                .fontSize(16)
                .fontColor(MctTheme.fg)
            }
          }
          .width('100%')
          .height(48)
          .backgroundColor(MctTheme.buttonBg)
          .borderRadius(4)
          .margin({ top: 6 })
          .onClick(() => {
            this.onExportKeys();
          })

          // Separator.
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin({ left: 5, right: 5, top: 18, bottom: 13 })

          Button('备份 / 导出全部')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .margin({ top: 6 })
            .onClick(() => {
              this.onBackupAll();
            })
          Button('恢复备份')
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .margin({ top: 6 })
            .onClick(() => {
              this.onRestoreBackup();
            })

          // Separator.
          Divider()
            .color(MctTheme.LIGHT_GRAY)
            .strokeWidth(2)
            .margin({ left: 5, right: 5, top: 18, bottom: 13 })

          Text('导入时如果存在同名文件，该文件将被覆盖。')
            .fontSize(15)
            .fontColor(MctTheme.fg)
            .width('100%')
            .padding(5)
            .textAlign(TextAlign.Start)
        }
        .width('100%')
        .padding(5)
      }
      .align(Alignment.Top)
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('导入/导出工具')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const p: ImportExportToolParams =
        (ctx.pathInfo.param as ImportExportToolParams) ?? new ImportExportToolParams();
      if (p.filePath.length > 0) {
        // This tool was opened by another page to export a file.
        this.pendingIntentFile = p.filePath;
        this.pendingIntentIsDumpFile = p.isDumpFile;
      }
    })
    .onShown(() => {
      MctTheme.refresh();
      // Was this tool opened by another page to export a file?
      // (Android onResume)
      if (this.pendingIntentFile.length > 0) {
        const path: string = this.pendingIntentFile;
        if (MctFiles.exists(path) && !MctFiles.isDir(path)) {
          // File to export is known. Trigger the export process.
          this.pendingIntentFile = '';
          this.isCalledWithExportFile = true;
          this.isExport = true;
          this.isDumpFile = this.pendingIntentIsDumpFile;
          this.file = path;
          if (this.isDumpFile) {
            this.showDumpFileTypeChooserMenu();
          } else {
            this.showKeysFileTypeChooserMenu();
          }
        }
      }
      // Handle the result of the FileChooser (EXPORT_FILE_CHOSEN).
      if (this.pendingExportFile.length > 0) {
        this.file = this.pendingExportFile;
        this.pendingExportFile = '';
        if (this.isDumpFile) {
          this.showDumpFileTypeChooserMenu();
        } else {
          this.showKeysFileTypeChooserMenu();
        }
      }
    })
  }
}

@Builder
export function ImportExportToolBuilder() {
  ImportExportToolPage()
}
