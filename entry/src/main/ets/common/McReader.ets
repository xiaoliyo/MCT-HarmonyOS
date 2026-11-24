/**
 * MIFARE Classic reader/writer.
 * Ported from de.syss.MifareClassicTool.MCReader (GPL-3.0, Gerhard Klostermeier).
 */

import { tag } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { HexUtils } from './HexUtils';
import { MctFiles } from './MctFiles';
import { MifareUtils } from './MifareUtils';
import { Operation, PrefKey, SectorKeys, TAG_SIZE_1K, TAG_SIZE_4K } from './MctTypes';
import { Prefs } from './Prefs';

/** Thrown when the tag is removed during an operation (BusinessError 3100201). */
export class TagLostError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TagLostError';
  }
}

export class McReader {
  private mfc: tag.MifareClassicTag;
  private keysWithOrder: string[] | null = null;
  private hasAllZeroKey: boolean = false;
  private firstSector: number = 0;
  private lastSector: number = -1;
  private keyMapStatus: number = 0;
  private keyMap: Map<number, SectorKeys> = new Map<number, SectorKeys>();
  private cancelCreateKeyMapFlag: boolean = false;
  /** Listener for live key mapping progress (sector, tried, total). */
  keyProgressListener: ((sector: number, tried: number,
    total: number) => void) | null = null;

  private constructor(mfc: tag.MifareClassicTag) {
    this.mfc = mfc;
  }

  /** Create a reader for the given tag info. Returns null if the tag
   *  is not a MIFARE Classic tag. */
  static get(tagInfo: tag.TagInfo): McReader | null {
    try {
      const mfc: tag.MifareClassicTag = tag.getMifareClassic(tagInfo);
      if (mfc === null || mfc === undefined) {
        return null;
      }
      return new McReader(mfc);
    } catch (e) {
      return null;
    }
  }

  // ---------------- Connection ----------------

  connect(): void {
    this.mfc.connect();
  }

  close(): void {
    try {
      this.mfc.resetConnection();
    } catch (e) {
      // Ignore.
    }
  }

  isConnected(): boolean {
    try {
      return this.mfc.isConnected();
    } catch (e) {
      return false;
    }
  }

  private reconnect(): boolean {
    try {
      this.connect();
    } catch (e) {
      return false;
    }
    return this.isConnected();
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, ms);
    });
  }

  // ---------------- Tag info ----------------

  getSectorCount(): number {
    if (Prefs.getBool(PrefKey.UseCustomSectorCount, false)) {
      return Prefs.getInt(PrefKey.CustomSectorCount, 16);
    }
    try {
      return this.mfc.getSectorCount();
    } catch (e) {
      return 16;
    }
  }

  getSize(): number {
    try {
      return this.mfc.getTagSize();
    } catch (e) {
      return TAG_SIZE_1K;
    }
  }

  getType(): tag.MifareClassicType {
    try {
      return this.mfc.getType();
    } catch (e) {
      return tag.MifareClassicType.TYPE_UNKNOWN;
    }
  }

  isEmulatedTag(): boolean {
    try {
      return this.mfc.isEmulatedTag();
    } catch (e) {
      return false;
    }
  }

  getBlockCount(): number {
    let count: number = 0;
    const sectors: number = this.getSectorCount();
    for (let i = 0; i < sectors; i++) {
      count += this.getBlockCountInSectorSafe(i);
    }
    return count;
  }

  private getBlockIndexOfSector(sectorIndex: number): number {
    try {
      return this.mfc.getBlockIndex(sectorIndex);
    } catch (e) {
      return MifareUtils.sectorToBlock(sectorIndex);
    }
  }

  private getBlockCountInSectorSafe(sectorIndex: number): number {
    try {
      return this.mfc.getBlockCountInSector(sectorIndex);
    } catch (e) {
      return MifareUtils.blockCountInSector(sectorIndex);
    }
  }

  // ---------------- Key mapping ----------------

  /**
   * Load keys from key files (all valid, deduplicated) and set them
   * as the key source for the key mapping.
   * Returns: -1 if the array is empty, 0 if no valid keys were found,
   * otherwise the number of unique keys.
   */
  setKeyFile(keyFilePaths: string[]): number {
    if (keyFilePaths.length === 0) {
      return -1;
    }
    const keySet: Set<string> = new Set<string>();
    for (let i = 0; i < keyFilePaths.length; i++) {
      const lines: string[] | null = MctFiles.readFileLines(keyFilePaths[i], false);
      if (lines === null) {
        continue;
      }
      for (let j = 0; j < lines.length; j++) {
        const line: string = lines[j];
        if (line.length === 12 && /^[0-9A-Fa-f]+$/.test(line)) {
          keySet.add(line.toUpperCase());
        }
      }
    }
    if (keySet.size === 0) {
      return 0;
    }
    this.hasAllZeroKey = keySet.has('000000000000');
    const keys: string[] = Array.from(keySet);
    // Due to the set, FFFFFFFFFFFF is somewhere in the middle.
    // Move it to the top (it is the most common key).
    const idx: number = keys.indexOf('FFFFFFFFFFFF');
    if (idx > 0) {
      const tmp: string = keys[0];
      keys[0] = keys[idx];
      keys[idx] = tmp;
    }
    this.keysWithOrder = keys;
    return keys.length;
  }

  /**
   * Set the mapping range (first and last sector to map).
   * Returns false if the range is invalid.
   */
  setMappingRange(firstSector: number, lastSector: number): boolean {
    if (firstSector >= 0 && lastSector < this.getSectorCount()
      && firstSector <= lastSector) {
      this.firstSector = firstSector;
      this.lastSector = lastSector;
      // Init status (the next buildNextKeyMapPart() call will reset
      // the map and start with the first sector).
      this.keyMapStatus = this.lastSector + 1;
      return true;
    }
    return false;
  }

  cancelCreateKeyMap(): void {
    this.cancelCreateKeyMapFlag = true;
  }

  getKeyMap(): Map<number, SectorKeys> {
    return this.keyMap;
  }

  /**
   * Build the next part of the key map (authenticate against one sector
   * with all keys). Returns the sector index that was just checked, or
   * -1 on error.
   */
  async buildNextKeyMapPart(): Promise<number> {
    this.cancelCreateKeyMapFlag = false;
    let error: boolean = false;
    if (this.keysWithOrder !== null && this.lastSector !== -1) {
      if (this.keyMapStatus === this.lastSector + 1) {
        // Restart the key map.
        this.keyMapStatus = this.firstSector;
        this.keyMap = new Map<number, SectorKeys>();
      }
      const autoReconnect: boolean = Prefs.getBool(PrefKey.AutoReconnect, false);
      const useRetry: boolean = Prefs.getBool(PrefKey.UseRetryAuthentication, false);
      const retryCount: number = Prefs.getInt(PrefKey.RetryAuthenticationCount, 1);
      const keys: string[] = this.keysWithOrder;
      let keyA: string | null = null;
      let keyB: string | null = null;
      for (let k = 0; k < keys.length && !error; k++) {
        const listener = this.keyProgressListener;
        if (listener !== null) {
          listener(this.keyMapStatus, k + 1, keys.length);
        }
        const keyBytes: number[] | null = HexUtils.hex2Bytes(keys[k]);
        if (keyBytes === null || keyBytes.length !== 6) {
          continue;
        }
        let attempt: number = 0;
        let keepTrying: boolean = true;
        while (keepTrying && attempt <= retryCount && !error) {
          keepTrying = false;
          try {
            if (this.cancelCreateKeyMapFlag) {
              return -1;
            }
            if (keyA === null) {
              const okA: boolean = await this.authenticateForMapping(
                this.keyMapStatus, keyBytes, true);
              if (okA) {
                keyA = keys[k];
              }
            }
            if (keyB === null) {
              const okB: boolean = await this.authenticateForMapping(
                this.keyMapStatus, keyBytes, false);
              if (okB) {
                keyB = keys[k];
              }
            }
          } catch (e) {
            if (e instanceof TagLostError && autoReconnect
              && !this.cancelCreateKeyMapFlag) {
              this.close();
              let connected: boolean = false;
              while (!connected) {
                if (this.cancelCreateKeyMapFlag) {
                  break;
                }
                await McReader.sleep(500);
                connected = this.reconnect();
              }
              if (connected) {
                // Repeat the same authentication.
                keepTrying = true;
                continue;
              }
            }
            error = true;
            break;
          }
          if (!useRetry) {
            break;
          }
          attempt++;
          if (keyA === null || keyB === null) {
            keepTrying = true;
          }
        }
        if (!error && keyA !== null && keyB !== null) {
          break;
        }
      }
      if (!error && (keyA !== null || keyB !== null)) {
        this.keyMap.set(this.keyMapStatus, new SectorKeys(
          keyA !== null ? HexUtils.hex2Bytes(keyA) : null,
          keyB !== null ? HexUtils.hex2Bytes(keyB) : null));
        // Move the found keys to the front of the key list
        // (key reuse optimization).
        if (this.keysWithOrder !== null && this.keysWithOrder.length > 2) {
          if (keyA !== null) {
            this.moveKeyToFront(keyA);
          }
          if (keyB !== null && keyB !== keyA) {
            this.moveKeyToFront(keyB);
          }
        }
      }
      this.keyMapStatus++;
    } else {
      error = true;
    }
    if (error) {
      this.keyMapStatus = this.firstSector;
      this.keyMap = new Map<number, SectorKeys>();
      return -1;
    }
    return this.keyMapStatus - 1;
  }

  private moveKeyToFront(key: string): void {
    if (this.keysWithOrder === null) {
      return;
    }
    const idx: number = this.keysWithOrder.indexOf(key);
    if (idx !== -1) {
      this.keysWithOrder.splice(idx, 1);
    }
    if (this.hasAllZeroKey && key !== 'FFFFFFFFFFFF') {
      this.keysWithOrder.splice(1, 0, key);
    } else {
      this.keysWithOrder.splice(0, 0, key);
    }
  }

  // ---------------- Authentication ----------------

  /**
   * Authenticate on a sector with a key (respecting the retry
   * preference). All errors are swallowed and result in false.
   */
  async authenticate(sectorIndex: number, key: number[] | null,
    useAsKeyB: boolean): Promise<boolean> {
    if (key === null || key === undefined || key.length !== 6) {
      return false;
    }
    const useRetry: boolean = Prefs.getBool(PrefKey.UseRetryAuthentication, false);
    const retryCount: number = Prefs.getInt(PrefKey.RetryAuthenticationCount, 1);
    try {
      for (let i = 0; i <= retryCount; i++) {
        const ok: boolean = await this.authenticateOnce(
          sectorIndex, key, !useAsKeyB);
        if (ok) {
          return true;
        }
        if (!useRetry) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  private async authenticateOnce(sectorIndex: number, key: number[],
    useAsKeyA: boolean): Promise<boolean> {
    try {
      await this.mfc.authenticateSector(sectorIndex, key, useAsKeyA);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** Authentication for key mapping: throws TagLostError on tag loss,
   *  returns false on authentication failure. */
  private async authenticateForMapping(sectorIndex: number, key: number[],
    useAsKeyA: boolean): Promise<boolean> {
    try {
      await this.mfc.authenticateSector(sectorIndex, key, useAsKeyA);
      return true;
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === 3100201) {
        throw new TagLostError('Tag lost during authentication.');
      }
      return false;
    }
  }

  // ---------------- Reading ----------------

  /**
   * Read as much as possible of a sector with the given key.
   * Returns null if authentication failed or no data could be read.
   * Throws TagLostError if the tag was removed during the operation.
   */
  async readSector(sectorIndex: number, key: number[],
    useAsKeyB: boolean): Promise<string[] | null> {
    const auth: boolean = await this.authenticate(sectorIndex, key, useAsKeyB);
    if (!auth) {
      return null;
    }
    const firstBlock: number = this.getBlockIndexOfSector(sectorIndex);
    let lastBlock: number = firstBlock + 3;
    if (this.getSize() === TAG_SIZE_4K && sectorIndex > 31) {
      lastBlock = firstBlock + 15;
    }
    const ret: string[] = [];
    let gotData: boolean = false;
    for (let i = firstBlock; i <= lastBlock; i++) {
      let blockStr: string;
      try {
        const block: number[] = await this.readBlock(i);
        blockStr = HexUtils.bytes2Hex(block);
        gotData = true;
      } catch (e) {
        if (e instanceof TagLostError) {
          throw e;
        }
        blockStr = MifareUtils.NO_DATA;
        // Re-authenticate (an I/O error resets the authentication).
        await this.authenticate(sectorIndex, key, useAsKeyB);
      }
      ret.push(blockStr);
    }
    if (!gotData) {
      return null;
    }
    // Merge the key(s) into the sector trailer.
    const lastIndex: number = ret.length - 1;
    const trailer: string = ret[lastIndex];
    if (!useAsKeyB) {
      let keyBReadable: boolean = false;
      const acBytes: number[] | null = HexUtils.hex2Bytes(trailer.substring(12, 20));
      if (acBytes !== null && acBytes.length >= 3) {
        const matrix: number[][] | null = MifareUtils.acBytesToACMatrix(acBytes);
        if (matrix !== null) {
          keyBReadable = MifareUtils.isKeyBReadable(
            matrix[0][3], matrix[1][3], matrix[2][3]);
        }
      }
      if (keyBReadable) {
        ret[lastIndex] = HexUtils.bytes2Hex(key) + trailer.substring(12);
      } else {
        ret[lastIndex] = HexUtils.bytes2Hex(key)
          + trailer.substring(12, 20) + MifareUtils.NO_KEY;
      }
    } else {
      ret[lastIndex] = MifareUtils.NO_KEY
        + trailer.substring(12, 20) + HexUtils.bytes2Hex(key);
    }
    return ret;
  }

  /** Read a single block (raw). Throws TagLostError on tag loss and
   *  an Error on any other read failure. */
  private async readBlock(blockIndex: number): Promise<number[]> {
    let data: number[];
    try {
      data = await this.mfc.readSingleBlock(blockIndex);
    } catch (e) {
      const err = e as BusinessError;
      if (err.code === 3100201) {
        throw new TagLostError('Tag lost while reading block.');
      }
      throw new Error('Block read failed.');
    }
    if (data === null || data === undefined || data.length < 16) {
      throw new Error('Invalid block data.');
    }
    if (data.length > 16) {
      return data.slice(0, 16);
    }
    return data;
  }

  /**
   * Read as much as possible of all sectors in the key map.
   * Returns null if the tag was lost during the operation.
   */
  async readAsMuchAsPossible(keyMap: Map<number, SectorKeys>):
    Promise<Map<number, string[]> | null> {
    if (keyMap === null || keyMap.size === 0) {
      return null;
    }
    const result: Map<number, string[]> = new Map<number, string[]>();
    const sectors: number[] = Array.from(keyMap.keys());
    try {
      for (let i = 0; i < sectors.length; i++) {
        const sector: number = sectors[i];
        const keys: SectorKeys | undefined = keyMap.get(sector);
        if (keys === undefined) {
          continue;
        }
        let resA: string[] | null = null;
        let resB: string[] | null = null;
        if (keys.keyA !== null) {
          resA = await this.readSector(sector, keys.keyA, false);
        }
        if (keys.keyB !== null) {
          resB = await this.readSector(sector, keys.keyB, true);
        }
        if (resA !== null || resB !== null) {
          result.set(sector, McReader.mergeSectorData(resA, resB));
        }
      }
    } catch (e) {
      // Tag lost (or any other read error) -> return null.
      return null;
    }
    return result;
  }

  /**
   * Merge the data of two reads of the same sector (with key A and
   * key B).
   */
  static mergeSectorData(first: string[] | null, second: string[] | null):
    string[] {
    if (first === null && second === null) {
      return [MifareUtils.NO_DATA];
    }
    const lenA: number = first !== null ? first.length : 0;
    const lenB: number = second !== null ? second.length : 0;
    if (first !== null && second !== null && lenA !== lenB) {
      return [MifareUtils.NO_DATA];
    }
    const len: number = Math.max(lenA, lenB);
    const ret: string[] = [];
    for (let i = 0; i < len; i++) {
      const blockA: string | null =
        first !== null && i < first.length ? first[i] : null;
      const blockB: string | null =
        second !== null && i < second.length ? second[i] : null;
      if (i === len - 1) {
        // Sector trailer.
        if (blockA !== null && blockA !== MifareUtils.NO_DATA) {
          if (blockB !== null && blockB !== MifareUtils.NO_DATA) {
            ret.push(blockA.substring(0, 20) + blockB.substring(20));
          } else {
            ret.push(blockA);
          }
        } else if (blockB !== null && blockB !== MifareUtils.NO_DATA) {
          ret.push(blockB);
        } else {
          ret.push(MifareUtils.NO_DATA);
        }
      } else {
        if (blockA !== null && blockA !== MifareUtils.NO_DATA) {
          ret.push(blockA);
        } else if (blockB !== null && blockB !== MifareUtils.NO_DATA) {
          ret.push(blockB);
        } else {
          ret.push(MifareUtils.NO_DATA);
        }
      }
    }
    return ret;
  }

  // ---------------- Writing ----------------

  /**
   * Write a block to a tag.
   * Returns: 0=OK, 1=sector out of range, 2=block out of range,
   * 3=data invalid (null or not 16 bytes), 4=authentication failed,
   * -1=I/O error.
   */
  async writeBlock(sectorIndex: number, blockIndex: number,
    data: number[] | null, key: number[], useAsKeyB: boolean): Promise<number> {
    if (this.getSectorCount() - 1 < sectorIndex) {
      return 1;
    }
    if (this.getBlockCountInSectorSafe(sectorIndex) - 1 < blockIndex) {
      return 2;
    }
    if (data === null || data === undefined || data.length !== 16) {
      return 3;
    }
    const auth: boolean = await this.authenticate(sectorIndex, key, useAsKeyB);
    if (!auth) {
      return 4;
    }
    const absBlock: number =
      this.getBlockIndexOfSector(sectorIndex) + blockIndex;
    try {
      await this.mfc.writeSingleBlock(absBlock, data);
      return 0;
    } catch (e) {
      return -1;
    }
  }

  /**
   * Write a value to a value block using increment/decrement + transfer.
   * Returns: 0=OK, 1=sector out of range, 2=block out of range,
   * 3=authentication failed, -1=I/O error.
   */
  async writeValueBlock(sectorIndex: number, blockIndex: number,
    value: number, increment: boolean, key: number[],
    useAsKeyB: boolean): Promise<number> {
    if (this.getSectorCount() - 1 < sectorIndex) {
      return 1;
    }
    if (this.getBlockCountInSectorSafe(sectorIndex) - 1 < blockIndex) {
      return 2;
    }
    const auth: boolean = await this.authenticate(sectorIndex, key, useAsKeyB);
    if (!auth) {
      return 3;
    }
    const absBlock: number =
      this.getBlockIndexOfSector(sectorIndex) + blockIndex;
    try {
      if (increment) {
        await this.mfc.incrementBlock(absBlock, value);
      } else {
        await this.mfc.decrementBlock(absBlock, value);
      }
      await this.mfc.transferToBlock(absBlock);
      return 0;
    } catch (e) {
      return -1;
    }
  }

  /**
   * Check whether the given blocks (sector -> blocks) are writable.
   * Returns a map (sector -> (block -> access requirement)), where a
   * sector maps to null if its access conditions could not be read.
   * Returns null if authentication failed on a sector.
   * Access requirements: 0=Never, 1=KeyA, 2=KeyB, 3=KeyA|B,
   * 4=only ACs are writable with KeyA, 5=only ACs are writable with
   * KeyB, 6=only KeyB is writable.
   */
  async isWritableOnPositions(pos: Map<number, number[]>,
    keyMap: Map<number, SectorKeys>):
    Promise<Map<number, Map<number, number> | null> | null> {
    const ret: Map<number, Map<number, number> | null> =
      new Map<number, Map<number, number> | null>();
    const sectors: number[] = Array.from(pos.keys());
    for (let i = 0; i < sectors.length; i++) {
      const sector: number = sectors[i];
      const keys: SectorKeys | undefined = keyMap.get(sector);
      const blocks: number[] | undefined = pos.get(sector);
      if (keys === undefined || blocks === undefined) {
        continue;
      }
      // Authenticate with key A first, then key B.
      let authOk: boolean = false;
      if (keys.keyA !== null) {
        authOk = await this.authenticate(sector, keys.keyA, false);
      }
      if (!authOk && keys.keyB !== null) {
        authOk = await this.authenticate(sector, keys.keyB, true);
      }
      if (!authOk) {
        return null;
      }
      // Read the sector trailer.
      const blockCount: number = this.getBlockCountInSectorSafe(sector);
      const trailerBlock: number =
        this.getBlockIndexOfSector(sector) + blockCount - 1;
      let trailer: number[];
      try {
        trailer = await this.readBlock(trailerBlock);
      } catch (e) {
        ret.set(sector, null);
        continue;
      }
      const matrix: number[][] | null =
        MifareUtils.acBytesToACMatrix(trailer.slice(6, 9));
      if (matrix === null) {
        ret.set(sector, null);
        continue;
      }
      const keyBReadable: boolean = MifareUtils.isKeyBReadable(
        matrix[0][3], matrix[1][3], matrix[2][3]);
      const blockMap: Map<number, number> = new Map<number, number>();
      const isLargeSector: boolean = sector >= 32;
      for (let j = 0; j < blocks.length; j++) {
        const block: number = blocks[j];
        let result: number;
        if (block === blockCount - 1) {
          // Sector trailer.
          const acValue: number = MifareUtils.getOperationRequirements(
            matrix[0][3], matrix[1][3], matrix[2][3],
            Operation.WriteAC, true, keyBReadable);
          const keyABValue: number = MifareUtils.getOperationRequirements(
            matrix[0][3], matrix[1][3], matrix[2][3],
            Operation.WriteKeyA, true, keyBReadable);
          if (acValue === 0 && keyABValue !== 0) {
            result = keyABValue + 3;
          } else if (acValue === 2 && keyABValue === 0) {
            result = 6;
          } else {
            result = keyABValue;
          }
        } else {
          let acBitsIndex: number = block;
          if (isLargeSector) {
            if (block >= 0 && block <= 4) {
              acBitsIndex = 0;
            } else if (block >= 5 && block <= 9) {
              acBitsIndex = 1;
            } else if (block >= 10 && block <= 14) {
              acBitsIndex = 2;
            }
          }
          result = MifareUtils.getOperationRequirements(
            matrix[0][acBitsIndex], matrix[1][acBitsIndex],
            matrix[2][acBitsIndex], Operation.Write, false, keyBReadable);
        }
        blockMap.set(block, result);
      }
      ret.set(sector, blockMap);
    }
    return ret;
  }

  /**
   * Check whether the Decrement/Transfer/Restore operation is allowed
   * on a block. Returns the access requirement
   * (0=Never, 1=KeyA, 2=KeyB, 3=KeyA|B) or -1 on error.
   */
  async hasDecTransRestPermission(sectorIndex: number, blockIndex: number,
    key: number[], useAsKeyB: boolean): Promise<number> {
    const blockCount: number = this.getBlockCountInSectorSafe(sectorIndex);
    if (blockIndex === blockCount - 1) {
      // Sector trailer: no Dec/Trans/Rest permission.
      return 0;
    }
    const auth: boolean = await this.authenticate(sectorIndex, key, useAsKeyB);
    if (!auth) {
      return -1;
    }
    const trailerBlock: number =
      this.getBlockIndexOfSector(sectorIndex) + blockCount - 1;
    let trailer: number[];
    try {
      trailer = await this.readBlock(trailerBlock);
    } catch (e) {
      return -1;
    }
    const matrix: number[][] | null =
      MifareUtils.acBytesToACMatrix(trailer.slice(6, 9));
    if (matrix === null) {
      return -1;
    }
    const keyBReadable: boolean = MifareUtils.isKeyBReadable(
      matrix[0][3], matrix[1][3], matrix[2][3]);
    let acBitsIndex: number = blockIndex;
    if (sectorIndex >= 32) {
      if (blockIndex >= 0 && blockIndex <= 4) {
        acBitsIndex = 0;
      } else if (blockIndex >= 5 && blockIndex <= 9) {
        acBitsIndex = 1;
      } else if (blockIndex >= 10 && blockIndex <= 14) {
        acBitsIndex = 2;
      }
    }
    return MifareUtils.getOperationRequirements(
      matrix[0][acBitsIndex], matrix[1][acBitsIndex],
      matrix[2][acBitsIndex], Operation.DecTransRest, false, keyBReadable);
  }

  /**
   * Copy a value block to another position using the
   * backup/restore/transfer mechanism (without changing the source).
   * Returns: 0=OK, 1=stage or destination is a sector trailer or the
   * manufacturer block, 2=block index out of range, -1=authentication
   * failed or I/O error.
   */
  async valueTransferRestore(stageSector: number, stageBlock: number,
    destSector: number, destBlock: number, valueBlock: number[],
    keyStage: number[], useKeyBStage: boolean,
    keyDest: number[], useKeyBDest: boolean): Promise<number> {
    const stageBlockCount: number = this.getBlockCountInSectorSafe(stageSector);
    const destBlockCount: number = this.getBlockCountInSectorSafe(destSector);
    if (stageBlock < 0 || stageBlock >= stageBlockCount
      || destBlock < 0 || destBlock >= destBlockCount) {
      return 2;
    }
    if (stageBlock === stageBlockCount - 1
      || destBlock === destBlockCount - 1
      || (stageSector === 0 && stageBlock === 0)
      || (destSector === 0 && destBlock === 0)) {
      return 1;
    }
    const stageAbs: number =
      this.getBlockIndexOfSector(stageSector) + stageBlock;
    const destAbs: number =
      this.getBlockIndexOfSector(destSector) + destBlock;
    try {
      // Backup the original data of the staging position.
      if (!(await this.authenticate(stageSector, keyStage, useKeyBStage))) {
        return -1;
      }
      const original: number[] = await this.readBlock(stageAbs);
      // Write the value block to the staging position.
      await this.mfc.writeSingleBlock(stageAbs, valueBlock);
      // Copy the staging block into the internal buffer.
      await this.mfc.restoreFromBlock(stageAbs);
      // Transfer the value to the destination block.
      if (!(await this.authenticate(destSector, keyDest, useKeyBDest))) {
        return -1;
      }
      await this.mfc.transferToBlock(destAbs);
      // Restore the original data at the staging position.
      if (stageSector !== destSector) {
        if (!(await this.authenticate(stageSector, keyStage, useKeyBStage))) {
          return -1;
        }
      }
      await this.mfc.writeSingleBlock(stageAbs, original);
      return 0;
    } catch (e) {
      return -1;
    }
  }
}
