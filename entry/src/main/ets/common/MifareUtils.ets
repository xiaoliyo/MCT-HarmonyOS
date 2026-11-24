/**
 * MIFARE Classic domain logic: access conditions, value blocks,
 * dump/key validation and block/sector math.
 * Ported from de.syss.MifareClassicTool.Common (GPL-3.0, Gerhard Klostermeier).
 */

import { HexUtils } from './HexUtils';
import { Operation, TAG_SIZE_1K, TAG_SIZE_2K, TAG_SIZE_4K, TAG_SIZE_MINI, ValueBlockResult } from './MctTypes';

export class MifareUtils {
  /** Placeholder for not found keys. */
  static readonly NO_KEY: string = '------------';
  /** Placeholder for unreadable blocks. */
  static readonly NO_DATA: string = '--------------------------------';
  /** Default key of MIFARE Classic tags. */
  static readonly DEFAULT_KEY: string = 'FFFFFFFFFFFF';

  /** Absolute block index of the first block of a sector. */
  static sectorToBlock(sectorIndex: number): number {
    if (sectorIndex < 32) {
      return sectorIndex * 4;
    }
    return 128 + (sectorIndex - 32) * 16;
  }

  /** Sector index that contains a given absolute block. */
  static blockToSector(blockIndex: number): number {
    if (blockIndex < 128) {
      return Math.floor(blockIndex / 4);
    }
    return 32 + Math.floor((blockIndex - 128) / 16);
  }

  /** Block count of a given sector (4 for sectors 0-31, 16 for 32-39). */
  static blockCountInSector(sectorIndex: number): number {
    return sectorIndex < 32 ? 4 : 16;
  }

  /** Total block count of a tag from its sector count. */
  static blockCountFromSectorCount(sectorCount: number): number {
    let blocks = 0;
    for (let s = 0; s < sectorCount; s++) {
      blocks += MifareUtils.blockCountInSector(s);
    }
    return blocks;
  }

  /** Tag size in bytes from its sector count. */
  static sizeFromSectorCount(sectorCount: number): number {
    return MifareUtils.blockCountFromSectorCount(sectorCount) * 16;
  }

  /**
   * Depending on the access conditions, return which key is required
   * to achieve the given operation.
   * Returns: 0=Never, 1=KeyA, 2=KeyB, 3=KeyA|B, -1=Error (and 4 for
   * a sector trailer with a non-trailer operation).
   */
  static getOperationRequirements(c1: number, c2: number, c3: number,
    op: Operation, isSectorTrailer: boolean, isKeyBReadable: boolean): number {
    if (isSectorTrailer) {
      if (op !== Operation.ReadKeyA && op !== Operation.ReadKeyB
        && op !== Operation.ReadAC && op !== Operation.WriteKeyA
        && op !== Operation.WriteKeyB && op !== Operation.WriteAC) {
        return 4;
      }
      if (c1 === 0 && c2 === 0 && c3 === 0) {
        if (op === Operation.WriteKeyA || op === Operation.WriteKeyB
          || op === Operation.ReadKeyB || op === Operation.ReadAC) {
          return 1;
        }
        return 0;
      } else if (c1 === 0 && c2 === 1 && c3 === 0) {
        if (op === Operation.ReadKeyB || op === Operation.ReadAC) {
          return 1;
        }
        return 0;
      } else if (c1 === 1 && c2 === 0 && c3 === 0) {
        if (op === Operation.WriteKeyA || op === Operation.WriteKeyB) {
          return 2;
        }
        if (op === Operation.ReadAC) {
          return 3;
        }
        return 0;
      } else if (c1 === 1 && c2 === 1 && c3 === 0) {
        if (op === Operation.ReadAC) {
          return 3;
        }
        return 0;
      } else if (c1 === 0 && c2 === 0 && c3 === 1) {
        if (op === Operation.ReadKeyA) {
          return 0;
        }
        return 1;
      } else if (c1 === 0 && c2 === 1 && c3 === 1) {
        if (op === Operation.ReadAC) {
          return 3;
        }
        if (op === Operation.ReadKeyA || op === Operation.ReadKeyB) {
          return 0;
        }
        return 2;
      } else if (c1 === 1 && c2 === 0 && c3 === 1) {
        if (op === Operation.ReadAC) {
          return 3;
        }
        if (op === Operation.WriteAC) {
          return 2;
        }
        return 0;
      } else if (c1 === 1 && c2 === 1 && c3 === 1) {
        if (op === Operation.ReadAC) {
          return 3;
        }
        return 0;
      } else {
        return -1;
      }
    } else {
      if (op !== Operation.Read && op !== Operation.Write
        && op !== Operation.Increment && op !== Operation.DecTransRest) {
        return -1;
      }
      if (c1 === 0 && c2 === 0 && c3 === 0) {
        return isKeyBReadable ? 1 : 3;
      } else if (c1 === 0 && c2 === 1 && c3 === 0) {
        if (op === Operation.Read) {
          return isKeyBReadable ? 1 : 3;
        }
        return 0;
      } else if (c1 === 1 && c2 === 0 && c3 === 0) {
        if (op === Operation.Read) {
          return isKeyBReadable ? 1 : 3;
        }
        if (op === Operation.Write) {
          return 2;
        }
        return 0;
      } else if (c1 === 1 && c2 === 1 && c3 === 0) {
        if (op === Operation.Read || op === Operation.DecTransRest) {
          return isKeyBReadable ? 1 : 3;
        }
        return 2;
      } else if (c1 === 0 && c2 === 0 && c3 === 1) {
        if (op === Operation.Read || op === Operation.DecTransRest) {
          return isKeyBReadable ? 1 : 3;
        }
        return 0;
      } else if (c1 === 0 && c2 === 1 && c3 === 1) {
        if (op === Operation.Read || op === Operation.Write) {
          return 2;
        }
        return 0;
      } else if (c1 === 1 && c2 === 0 && c3 === 1) {
        if (op === Operation.Read) {
          return 2;
        }
        return 0;
      } else if (c1 === 1 && c2 === 1 && c3 === 1) {
        return 0;
      } else {
        return -1;
      }
    }
  }

  /** Check if key B is readable for the given sector trailer AC bits. */
  static isKeyBReadable(c1: number, c2: number, c3: number): boolean {
    return c1 === 0
      && ((c2 === 0 && c3 === 0)
        || (c2 === 1 && c3 === 0)
        || (c2 === 0 && c3 === 1));
  }

  /**
   * Convert the access condition bytes (3 bytes, numbers 0-255) to a
   * matrix of resolved C1-C3 bits per block: acMatrix[c][block].
   * Returns null if the ACs are incorrect.
   */
  static acBytesToACMatrix(acBytes: number[] | null): number[][] | null {
    if (acBytes === null || acBytes.length < 3) {
      return null;
    }
    const b0 = acBytes[0] & 0xFF;
    const b1 = acBytes[1] & 0xFF;
    const b2 = acBytes[2] & 0xFF;
    if (((b1 >>> 4) & 0x0F) === ((b0 ^ 0xFF) & 0x0F)
      && (b2 & 0x0F) === (((b0 ^ 0xFF) >>> 4) & 0x0F)
      && ((b2 >>> 4) & 0x0F) === ((b1 ^ 0xFF) & 0x0F)) {
      const acMatrix: number[][] = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]];
      for (let i = 0; i < 4; i++) {
        acMatrix[0][i] = ((b1 >>> (4 + i)) & 0x01);
      }
      for (let i = 0; i < 4; i++) {
        acMatrix[1][i] = ((b2 >>> i) & 0x01);
      }
      for (let i = 0; i < 4; i++) {
        acMatrix[2][i] = ((b2 >>> (4 + i)) & 0x01);
      }
      return acMatrix;
    }
    return null;
  }

  /**
   * Convert an AC bit matrix (acMatrix[c][block], 3x4) back into the
   * 3 access condition bytes.
   */
  static acMatrixToACBytes(acMatrix: number[][] | null): number[] | null {
    if (acMatrix === null || acMatrix.length !== 3) {
      return null;
    }
    for (let i = 0; i < 3; i++) {
      if (acMatrix[i].length !== 4) {
        return null;
      }
    }
    const acBytes = [0, 0, 0];
    // Byte 1 (block index 6), bit 0-3: ~C1.
    let b0 = 0;
    for (let i = 0; i < 4; i++) {
      b0 |= ((acMatrix[0][i] ^ 1) << i) & (1 << i);
    }
    // Byte 1, bit 4-7: ~C2.
    for (let i = 0; i < 4; i++) {
      b0 |= ((acMatrix[1][i] ^ 1) << (4 + i)) & (1 << (4 + i));
    }
    acBytes[0] = b0 & 0xFF;
    // Byte 2 (block index 7), bit 0-3: ~C3.
    let b1 = 0;
    for (let i = 0; i < 4; i++) {
      b1 |= ((acMatrix[2][i] ^ 1) << i) & (1 << i);
    }
    // Byte 2, bit 4-7: C1.
    for (let i = 0; i < 4; i++) {
      b1 |= (acMatrix[0][i] << (4 + i)) & (1 << (4 + i));
    }
    acBytes[1] = b1 & 0xFF;
    // Byte 3 (block index 8), bit 0-3: C2.
    let b2 = 0;
    for (let i = 0; i < 4; i++) {
      b2 |= (acMatrix[1][i] << i) & (1 << i);
    }
    // Byte 3, bit 4-7: C3.
    for (let i = 0; i < 4; i++) {
      b2 |= (acMatrix[2][i] << (4 + i)) & (1 << (4 + i));
    }
    acBytes[2] = b2 & 0xFF;
    return acBytes;
  }

  /** Check if the given block (hex string) is a value block. */
  static isValueBlock(hexString: string): boolean {
    const b = HexUtils.hex2Bytes(hexString);
    if (b !== null && b.length === 16) {
      return (b[0] === b[8] && ((b[0] ^ 0xFF) & 0xFF) === b[4])
        && (b[1] === b[9] && ((b[1] ^ 0xFF) & 0xFF) === b[5])
        && (b[2] === b[10] && ((b[2] ^ 0xFF) & 0xFF) === b[6])
        && (b[3] === b[11] && ((b[3] ^ 0xFF) & 0xFF) === b[7])
        && (b[12] === b[14] && b[13] === b[15]
          && ((b[12] ^ 0xFF) & 0xFF) === b[13]);
    }
    return false;
  }

  /** Encode a value block (value + address) into 16 bytes. */
  static encodeValueBlock(value: number, addr: number): number[] {
    const vb = new Array<number>(16).fill(0);
    const valueBytes = [value & 0xFF, (value >>> 8) & 0xFF, (value >>> 16) & 0xFF, (value >>> 24) & 0xFF];
    for (let i = 0; i < 4; i++) {
      vb[i] = valueBytes[i];
      vb[4 + i] = (valueBytes[i] ^ 0xFF) & 0xFF;
      vb[8 + i] = valueBytes[i];
    }
    vb[12] = addr & 0xFF;
    vb[13] = (addr ^ 0xFF) & 0xFF;
    vb[14] = addr & 0xFF;
    vb[15] = (addr ^ 0xFF) & 0xFF;
    return vb;
  }

  /** Encode a value block into a 32 char hex string. */
  static encodeValueBlockToHex(value: number, addr: number): string {
    return HexUtils.bytes2Hex(MifareUtils.encodeValueBlock(value, addr));
  }

  /** Decode a value block (16 bytes) into value + address. Returns null if not a VB. */
  static decodeValueBlock(vb: number[] | null): ValueBlockResult | null {
    if (vb === null || vb.length !== 16) {
      return null;
    }
    const value = (vb[0] & 0xFF) | ((vb[1] & 0xFF) << 8)
      | ((vb[2] & 0xFF) << 16) | ((vb[3] & 0xFF) << 24);
    const valueInv = (vb[4] & 0xFF) | ((vb[5] & 0xFF) << 8)
      | ((vb[6] & 0xFF) << 16) | ((vb[7] & 0xFF) << 24);
    const valueRep = (vb[8] & 0xFF) | ((vb[9] & 0xFF) << 8)
      | ((vb[10] & 0xFF) << 16) | ((vb[11] & 0xFF) << 24);
    const addr = vb[12] & 0xFF;
    const addrInv = vb[13] & 0xFF;
    const addrRep = vb[14] & 0xFF;
    const addrInvRep = vb[15] & 0xFF;
    if (value === valueRep && ((value ^ 0xFFFFFFFF) >>> 0) === (valueInv >>> 0)
      && addr === addrRep && ((addr ^ 0xFF) & 0xFF) === addrInv
      && ((addr ^ 0xFF) & 0xFF) === addrInvRep) {
      return new ValueBlockResult(value, addr);
    }
    return null;
  }

  /**
   * Check if all blocks (lines) contain valid dump data.
   * Returns 0=OK, 1=invalid sector length/header, 2=invalid chars,
   * 3=not 32 chars, 4=sector out of range, 5=double sector, 6=no lines.
   */
  static isValidDump(lines: string[] | null, ignoreAsterisk: boolean): number {
    const knownSectors: number[] = [];
    let blocksSinceLastSectorHeader = 4;
    let is16BlockSector = false;
    if (lines === null || lines.length === 0) {
      return 6;
    }
    for (let idx = 0; idx < lines.length; idx++) {
      const line = lines[idx];
      if ((!is16BlockSector && blocksSinceLastSectorHeader === 4)
        || (is16BlockSector && blocksSinceLastSectorHeader === 16)) {
        if (!/^\+Sector: [0-9]{1,2}$/.test(line)) {
          return 1;
        }
        let sector = -1;
        const parts = line.split(': ');
        if (parts.length === 2) {
          sector = parseInt(parts[1], 10);
        }
        if (sector < 0 || sector > 39) {
          return 4;
        }
        if (knownSectors.indexOf(sector) !== -1) {
          return 5;
        }
        knownSectors.push(sector);
        is16BlockSector = sector >= 32;
        blocksSinceLastSectorHeader = 0;
        continue;
      }
      if (line.startsWith('*') && ignoreAsterisk) {
        is16BlockSector = false;
        blocksSinceLastSectorHeader = 4;
        continue;
      }
      if (!/^[0-9A-Fa-f-]+$/.test(line)) {
        return 2;
      }
      if (line.length !== 32) {
        return 3;
      }
      blocksSinceLastSectorHeader++;
    }
    return 0;
  }

  /**
   * Check if the user input is a valid key file.
   * Returns 0=OK, 1=no key, 2=invalid chars, 3=not 6 byte.
   */
  static isValidKeyFile(lines: string[] | null): number {
    let keyFound = false;
    if (lines === null || lines.length === 0) {
      return 1;
    }
    for (let idx = 0; idx < lines.length; idx++) {
      let line = lines[idx];
      if (line.startsWith('#')) {
        continue;
      }
      line = line.split('#')[0];
      line = line.trim();
      if (line.length === 0) {
        continue;
      }
      if (!/^[0-9A-Fa-f]+$/.test(line)) {
        return 2;
      }
      if (line.length !== 12) {
        return 3;
      }
      keyFound = true;
    }
    if (!keyFound) {
      return 1;
    }
    return 0;
  }

  /**
   * Check if block 0 contains valid data (UID, BCC, ATQA, SAK).
   * Ported from Common.isValidBlock0.
   */
  static isValidBlock0(block0: string, uidLen: number, tagSize: number, skipBccCheck: boolean): boolean {
    if (block0 === null || block0.length !== 32
      || (uidLen !== 4 && uidLen !== 7 && uidLen !== 10)) {
      return false;
    }
    block0 = block0.toUpperCase();
    const byte0 = block0.substring(0, 2);
    const bcc = block0.substring(8, 10);
    const sakStart = uidLen === 4 ? uidLen * 2 + 2 : uidLen * 2;
    const sak = block0.substring(sakStart, sakStart + 2);
    const atqa = block0.substring(sakStart + 2, sakStart + 6);
    let valid = true;
    if (!skipBccCheck && valid && uidLen === 4) {
      const byteBcc = HexUtils.hex2Bytes(bcc);
      const uid = HexUtils.hex2Bytes(block0.substring(0, 8));
      valid = byteBcc !== null && uid !== null && HexUtils.isValidBcc(uid, byteBcc[0]);
    }
    if (valid && uidLen === 4) {
      valid = byte0 !== '88';
    }
    if (valid && uidLen === 4) {
      valid = byte0 !== 'F8';
    }
    if (valid && (uidLen === 7 || uidLen === 10)) {
      const fb = HexUtils.hex2Bytes(byte0);
      valid = fb !== null && (fb[0] < 0x81 || fb[0] > 0xFE);
    }
    if (valid && (uidLen === 7 || uidLen === 10)) {
      valid = byte0 !== '00';
    }
    if (valid && (uidLen === 7 || uidLen === 10)) {
      valid = !block0.startsWith('88', 4);
    }
    if (valid && (/^040[1-9A-F]$/.test(atqa) || /^020[1-9A-F]$/.test(atqa)
      || /^480.$/.test(atqa) || atqa === '010F')) {
      // Special ATQA (SmartMX / TNP3xxx). Valid.
    } else if (valid) {
      if (valid && uidLen === 4 && (tagSize === TAG_SIZE_1K
        || tagSize === TAG_SIZE_2K || tagSize === TAG_SIZE_MINI)) {
        valid = atqa === '0400';
      } else if (valid && uidLen === 4 && tagSize === TAG_SIZE_4K) {
        valid = atqa === '0200';
      } else if (valid && uidLen === 7 && (tagSize === TAG_SIZE_1K
        || tagSize === TAG_SIZE_2K || tagSize === TAG_SIZE_MINI)) {
        valid = atqa === '4400';
      } else if (valid && uidLen === 7 && tagSize === TAG_SIZE_4K) {
        valid = atqa === '4200';
      }
    }
    const sakBytes = HexUtils.hex2Bytes(sak);
    let validSak = false;
    if (valid && sakBytes !== null) {
      const byteSak = sakBytes[0] & 0xFF;
      if (((byteSak >> 1) & 1) === 0) {
        if (((byteSak >> 3) & 1) === 1) {
          if (((byteSak >> 4) & 1) === 1) {
            validSak = tagSize === TAG_SIZE_2K || tagSize === TAG_SIZE_4K;
          } else {
            if ((byteSak & 1) === 1) {
              validSak = tagSize === TAG_SIZE_MINI;
            } else {
              validSak = tagSize === TAG_SIZE_2K || tagSize === TAG_SIZE_1K;
            }
          }
        }
      }
    }
    return validSak;
  }

  /**
   * The list of valid access conditions for data blocks and the sector
   * trailer (C1-C3 as string "C1C2C3"). Used by the Access Condition Tool.
   */
  static readonly VALID_AC_DATA_BLOCKS: string[] = [
    '000', '010', '100', '110', '001', '011', '101', '111'
  ];

  static readonly VALID_AC_SECTOR_TRAILER: string[] = [
    '000', '010', '100', '001', '011', '101', '111'
  ];
}
