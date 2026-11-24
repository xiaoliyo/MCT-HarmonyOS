/**
 * MIFARE Classic Tool - shared types.
 * Ported from de.syss.MifareClassicTool (GPL-3.0, Gerhard Klostermeier).
 */

/** Possible operations on a MIFARE Classic tag. */
export enum Operation {
  Read,
  Write,
  Increment,
  DecTransRest,
  ReadKeyA,
  ReadKeyB,
  ReadAC,
  WriteKeyA,
  WriteKeyB,
  WriteAC
}

/** Preference keys (identical to the Android SharedPreferences keys). */
export enum PrefKey {
  AutoReconnect = 'auto_reconnect',
  AutoCopyUID = 'auto_copy_uid',
  UIDFormat = 'uid_format',
  SaveLastUsedKeyFiles = 'save_last_used_key_files',
  UseCustomSectorCount = 'use_custom_sector_count',
  CustomSectorCount = 'custom_sector_count',
  UseRetryAuthentication = 'use_retry_authentication',
  RetryAuthenticationCount = 'retry_authentication_count',
  CustomAppLanguage = 'custom_app_language',
  CustomAppTheme = 'custom_app_theme',
  UseAsEditorOnly = 'use_as_editor_only',
  ShowDonateDialog = 'show_donate_dialog',
  MctVersion = 'mct_version',
  IsFirstRun = 'is_first_run'
}

/** Keys of the per-"activity" (page) preferences. */
export enum PagePrefKey {
  DefaultMappingRangeFrom = 'default_mapping_range_from',
  DefaultMappingRangeTo = 'default_mapping_range_to',
  LastUsedKeyFiles = 'last_used_key_files'
}

/** Tag sizes in bytes (like android.nfc.tech.MifareClassic.SIZE_*). */
export const TAG_SIZE_MINI: number = 320;
export const TAG_SIZE_1K: number = 1024;
export const TAG_SIZE_2K: number = 2048;
export const TAG_SIZE_4K: number = 4096;

/** Keys (A/B) that were found for one sector. */
export class SectorKeys {
  keyA: number[] | null = null;
  keyB: number[] | null = null;

  constructor(keyA: number[] | null, keyB: number[] | null) {
    this.keyA = keyA;
    this.keyB = keyB;
  }
}

/** Result of decoding a value block. */
export class ValueBlockResult {
  value: number = 0;
  addr: number = 0;

  constructor(value: number, addr: number) {
    this.value = value;
    this.addr = addr;
  }
}
