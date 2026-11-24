/**
 * Hex/data conversion utilities.
 * Ported from de.syss.MifareClassicTool.Common (GPL-3.0, Gerhard Klostermeier).
 */

export class HexUtils {
  /** Check if a string is pure hex (0-9, A-F, a-f) with even length. */
  static isHex(hex: string): boolean {
    return hex !== null && hex.length % 2 === 0 && /^[0-9A-Fa-f]+$/.test(hex);
  }

  /** Convert a byte array (numbers 0-255) into a hex string. */
  static bytes2Hex(bytes: number[] | null): string {
    let ret = '';
    if (bytes !== null && bytes !== undefined) {
      for (let i = 0; i < bytes.length; i++) {
        const v = bytes[i] & 0xFF;
        ret += (v < 16 ? '0' : '') + v.toString(16).toUpperCase();
      }
    }
    return ret;
  }

  /** Convert a hex string into a byte array. Returns null on error. */
  static hex2Bytes(hex: string): number[] | null {
    if (!HexUtils.isHex(hex)) {
      return null;
    }
    const data: number[] = [];
    for (let i = 0; i < hex.length; i += 2) {
      data.push(parseInt(hex.substring(i, i + 2), 16));
    }
    return data;
  }

  /** Reverse a byte array in place. */
  static reverseByteArrayInPlace(array: number[]): void {
    for (let i = 0; i < array.length / 2; i++) {
      const temp = array[i];
      array[i] = array[array.length - i - 1];
      array[array.length - i - 1] = temp;
    }
  }

  /** Convert bytes to a string of the specified format (0=Hex, 1=DecBE, 2=DecLE). */
  static byte2FmtString(bytes: number[], fmt: number): string {
    if (fmt === 2) {
      const revBytes = bytes.slice();
      HexUtils.reverseByteArrayInPlace(revBytes);
      return HexUtils.hex2DecBE(HexUtils.bytes2Hex(revBytes));
    } else if (fmt === 1) {
      return HexUtils.hex2DecBE(HexUtils.bytes2Hex(bytes));
    }
    return HexUtils.bytes2Hex(bytes);
  }

  /** Convert a hexadecimal string to a decimal (big endian) string. */
  static hex2DecBE(hex: string): string {
    if (!HexUtils.isHex(hex)) {
      return '';
    }
    if (hex.length === 0) {
      return '0';
    }
    return BigInt('0x' + hex).toString(10);
  }

  /** Convert a hexadecimal string to a decimal (little endian) string. */
  static hex2DecLE(hex: string): string {
    if (!HexUtils.isHex(hex)) {
      return '';
    }
    let reversedHex = '';
    for (let i = hex.length - 2; i >= 0; i -= 2) {
      reversedHex += hex.substring(i, i + 2);
    }
    return BigInt('0x' + reversedHex).toString(10);
  }

  /** Convert a hex string to an ASCII string (non printable chars -> "."). */
  static hex2Ascii(hex: string): string | null {
    if (!HexUtils.isHex(hex)) {
      return null;
    }
    const bytes = HexUtils.hex2Bytes(hex);
    if (bytes === null) {
      return null;
    }
    let ret = '';
    for (let i = 0; i < bytes.length; i++) {
      let b = bytes[i];
      if (b < 0x20 || b === 0x7F) {
        b = 0x2E;
      }
      ret += String.fromCharCode(b);
    }
    return ret;
  }

  /** Convert an ASCII string to a hex string. */
  static ascii2Hex(ascii: string): string {
    if (ascii === null || ascii === undefined || ascii.length === 0) {
      return '';
    }
    let hex = '';
    for (let i = 0; i < ascii.length; i++) {
      const c = ascii.charCodeAt(i) & 0xFF;
      hex += (c < 16 ? '0' : '') + c.toString(16).toUpperCase();
    }
    return hex;
  }

  /** Convert a hex string to a binary string (with leading zeros). */
  static hex2Bin(hex: string): string | null {
    if (!HexUtils.isHex(hex)) {
      return null;
    }
    let bin = BigInt('0x' + hex).toString(2);
    if (bin.length < hex.length * 4) {
      const diff = hex.length * 4 - bin.length;
      let pad = '';
      for (let i = 0; i < diff; i++) {
        pad += '0';
      }
      bin = pad + bin;
    }
    return bin;
  }

  /** Convert a binary string to a hex string. */
  static bin2Hex(bin: string): string | null {
    if (bin === null || bin.length % 8 !== 0 || !/^[0-1]+$/.test(bin)) {
      return null;
    }
    let hex = BigInt('0b' + bin).toString(16).toUpperCase();
    if (hex.length % 2 !== 0) {
      hex = '0' + hex;
    }
    return hex;
  }

  /** Convert a decimal (big endian) string to a hex string. */
  static decBE2Hex(dec: string): string | null {
    if (dec === null || dec.length === 0 || !/^\d+$/.test(dec)) {
      return null;
    }
    let hex = BigInt(dec).toString(16).toUpperCase();
    if (hex.length % 2 !== 0) {
      hex = '0' + hex;
    }
    return hex;
  }

  /** Convert a decimal (little endian) string to a hex string. */
  static decLE2Hex(dec: string): string | null {
    if (dec === null || dec.length === 0 || !/^\d+$/.test(dec)) {
      return null;
    }
    let hex = BigInt(dec).toString(16).toUpperCase();
    if (hex.length % 2 !== 0) {
      hex = '0' + hex;
    }
    let reversedHex = '';
    for (let i = hex.length - 2; i >= 0; i -= 2) {
      reversedHex += hex.substring(i, i + 2);
    }
    return reversedHex;
  }

  /** Calculate the BCC of a 4 byte UID (XOR of all 4 bytes). */
  static calcBcc(uid: number[]): number {
    if (uid.length !== 4) {
      throw new Error('UID length is not 4 bytes.');
    }
    let bcc = uid[0];
    for (let i = 1; i < uid.length; i++) {
      bcc = bcc ^ uid[i];
    }
    return bcc;
  }

  /** Check whether the provided BCC is valid for the given UID. */
  static isValidBcc(uid: number[], bcc: number): boolean {
    return HexUtils.calcBcc(uid) === bcc;
  }

  /**
   * Convert a binary (bit) string to a byte array.
   * Bit 0 of the first character is the lowest bit of the last byte.
   */
  static binStringToBytes(bin: string): number[] {
    const bytes: number[] = [];
    let current = 0;
    let bitCount = 0;
    for (let i = bin.length - 1; i >= 0; i--) {
      if (bin.charAt(i) === '1') {
        current |= (1 << bitCount);
      }
      bitCount++;
      if (bitCount === 8) {
        bytes.push(current);
        current = 0;
        bitCount = 0;
      }
    }
    if (bitCount > 0) {
      bytes.push(current);
    }
    return bytes.reverse();
  }
}
