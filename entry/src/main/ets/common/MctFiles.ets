/**
 * App file storage: key files, dump files, tmp dir, UID log.
 * Ported from de.syss.MifareClassicTool.Common (GPL-3.0).
 */

import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { HexUtils } from './HexUtils';
import { MctApp } from './MctApp';

export class MctFiles {
  /** Directory names. */
  static readonly HOME_DIR: string = '/MifareClassicTool';
  static readonly KEYS_DIR: string = 'key-files';
  static readonly DUMPS_DIR: string = 'dump-files';
  static readonly TMP_DIR: string = 'tmp';

  /** Standard key file names. */
  static readonly STD_KEYS: string = 'std.keys';
  static readonly STD_KEYS_EXTENDED: string = 'extended-std.keys';
  static readonly STD_HOTEL_KEYS: string = 'hotel-std.keys';

  /** Log file with UIDs which have been discovered in the past. */
  static readonly UID_LOG_FILE: string = 'uid-log-file.txt';

  /** Build absolute path: <filesDir>/MifareClassicTool/<relativePath>. */
  static getFile(relativePath: string): string {
    return MctApp.getContext().filesDir + MctFiles.HOME_DIR + '/' + relativePath;
  }

  static getKeysDir(): string {
    return MctFiles.getFile(MctFiles.KEYS_DIR);
  }

  static getDumpsDir(): string {
    return MctFiles.getFile(MctFiles.DUMPS_DIR);
  }

  static getTmpDir(): string {
    return MctFiles.getFile(MctFiles.TMP_DIR);
  }

  /** Create home directories and clean out the tmp folder. */
  static initFolders(): void {
    const dirs = [MctFiles.getKeysDir(), MctFiles.getDumpsDir(), MctFiles.getTmpDir()];
    for (let i = 0; i < dirs.length; i++) {
      if (!MctFiles.exists(dirs[i])) {
        fileIo.mkdirSync(dirs[i], true);
      }
    }
    // Clean up tmp directory.
    const tmpDir = MctFiles.getTmpDir();
    const names = MctFiles.listFileNames(tmpDir);
    for (let i = 0; i < names.length; i++) {
      try {
        fileIo.unlinkSync(tmpDir + '/' + names[i]);
      } catch (e) {
        // Ignore.
      }
    }
  }

  /** Copy standard key files from rawfile to the keys dir (overwrite). */
  static copyStdKeysFiles(): void {
    const resMgr = MctApp.getContext().resourceManager;
    const stdFiles = [MctFiles.STD_KEYS, MctFiles.STD_KEYS_EXTENDED, MctFiles.STD_HOTEL_KEYS];
    for (let i = 0; i < stdFiles.length; i++) {
      try {
        const content: Uint8Array = resMgr.getRawFileContentSync('key-files/' + stdFiles[i]);
        const target = MctFiles.getFile(MctFiles.KEYS_DIR + '/' + stdFiles[i]);
        MctFiles.writeBytes(target, MctFiles.uint8ToArray(content));
      } catch (e) {
        // Asset missing - ignore.
      }
    }
  }

  static uint8ToArray(u: Uint8Array): number[] {
    const arr: number[] = [];
    for (let i = 0; i < u.length; i++) {
      arr.push(u[i]);
    }
    return arr;
  }

  static exists(path: string): boolean {
    try {
      fileIo.statSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  static isDir(path: string): boolean {
    try {
      return fileIo.statSync(path).isDirectory();
    } catch (e) {
      return false;
    }
  }

  /** List file names (files only, no directories) in a directory, sorted. */
  static listFileNames(dir: string, includeDirs: boolean = false): string[] {
    const names: string[] = [];
    if (!MctFiles.exists(dir)) {
      return names;
    }
    try {
      const dirents = fileIo.listFileSync(dir);
      for (let i = 0; i < dirents.length; i++) {
        const name = dirents[i];
        const full = dir + '/' + name;
        if (includeDirs || !MctFiles.isDir(full)) {
          names.push(name);
        }
      }
    } catch (e) {
      // Ignore.
    }
    names.sort((a: string, b: string): number => a.localeCompare(b));
    return names;
  }

  /**
   * Read a file line by line. If readAll is false, comments (#) and
   * empty lines are skipped and trailing comments removed.
   * Returns null on error.
   */
  static readFileLines(path: string, readAll: boolean): string[] | null {
    if (!MctFiles.exists(path) || MctFiles.isDir(path)) {
      return null;
    }
    let content: string;
    try {
      content = MctFiles.readText(path);
    } catch (e) {
      return null;
    }
    const rawLines = content.split(/\r\n|\r|\n/);
    const lines: string[] = [];
    for (let i = 0; i < rawLines.length; i++) {
      let line = rawLines[i].trim();
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

  /** Read a whole file as text. */
  static readText(path: string): string {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } finally {
      fileIo.closeSync(file);
    }
  }

  /** Read a whole file as bytes (numbers 0-255). */
  static readBytes(path: string): number[] {
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = fileIo.statSync(path);
      const buf = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      return MctFiles.uint8ToArray(new Uint8Array(buf));
    } finally {
      fileIo.closeSync(file);
    }
  }

  /** Write a text file (join of lines with \n). */
  static writeLines(path: string, lines: string[]): boolean {
    if (lines === null || lines.length === 0) {
      return false;
    }
    return MctFiles.writeText(path, lines.join('\n'));
  }

  static writeText(path: string, text: string): boolean {
    try {
      const encoder = new util.TextEncoder();
      const bytes = encoder.encodeInto(text);
      return MctFiles.writeBytes(path, MctFiles.uint8ToArray(bytes));
    } catch (e) {
      return false;
    }
  }

  /** Write bytes to a file (overwrite). */
  static writeBytes(path: string, bytes: number[]): boolean {
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        const buf = new ArrayBuffer(bytes.length);
        const u8 = new Uint8Array(buf);
        for (let i = 0; i < bytes.length; i++) {
          u8[i] = bytes[i] & 0xFF;
        }
        fileIo.writeSync(file.fd, buf);
      } finally {
        fileIo.closeSync(file);
      }
      return true;
    } catch (e) {
      hilog.error(0x0000, 'MctFiles', 'writeBytes failed (%{public}s): %{public}s', path, JSON.stringify(e));
      return false;
    }
  }

  /** Append lines to a file. If comment is true, add a comment header first. */
  static appendLines(path: string, lines: string[], comment: boolean): boolean {
    let toAppend = lines;
    if (comment) {
      toAppend = ['', '# Append #######################', ''].concat(lines);
    }
    if (!MctFiles.exists(path)) {
      return MctFiles.writeLines(path, toAppend);
    }
    try {
      const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.APPEND);
      try {
        const text = '\n' + toAppend.join('\n');
        const encoder = new util.TextEncoder();
        const bytes = encoder.encodeInto(text);
        const buf = new ArrayBuffer(bytes.length);
        const u8 = new Uint8Array(buf);
        for (let i = 0; i < bytes.length; i++) {
          u8[i] = bytes[i];
        }
        fileIo.writeSync(file.fd, buf);
      } finally {
        fileIo.closeSync(file);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Delete a file. */
  static deleteFile(path: string): boolean {
    try {
      fileIo.unlinkSync(path);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Log the UID with timestamp to the UID log file. */
  static logUid(uid: string): void {
    const log = MctApp.getContext().filesDir + MctFiles.HOME_DIR + '/' + MctFiles.UID_LOG_FILE;
    const now = new Date();
    const pad = (n: number): string => (n < 10 ? '0' : '') + n.toString();
    const dateFormatted = now.getFullYear() + '-' + pad(now.getMonth() + 1) + '-' + pad(now.getDate())
      + '_' + pad(now.getHours()) + '-' + pad(now.getMinutes()) + '-' + pad(now.getSeconds());
    MctFiles.appendLines(log, [dateFormatted + ': ' + uid], false);
  }

  /** Read the UID log file (all lines incl. comments). */
  static readUidLog(): string[] | null {
    return MctFiles.readFileLines(MctApp.getContext().filesDir + MctFiles.HOME_DIR + '/' + MctFiles.UID_LOG_FILE, true);
  }

  /** Clear the UID log file. */
  static clearUidLog(): void {
    const log = MctApp.getContext().filesDir + MctFiles.HOME_DIR + '/' + MctFiles.UID_LOG_FILE;
    if (MctFiles.exists(log)) {
      MctFiles.deleteFile(log);
    }
  }
}
