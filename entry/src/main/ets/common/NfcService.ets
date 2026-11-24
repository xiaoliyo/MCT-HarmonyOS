/**
 * NFC service and global app state.
 * Ported from de.syss.MifareClassicTool.Common (GPL-3.0, Gerhard Klostermeier).
 */

import { tag, nfcController } from '@kit.ConnectivityKit';
import { promptAction } from '@kit.ArkUI';
import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HexUtils } from './HexUtils';
import { MctApp } from './MctApp';
import { MctFiles } from './MctFiles';
import { McReader } from './McReader';
import { PrefKey, SectorKeys } from './MctTypes';
import { Prefs } from './Prefs';

/** Listener invoked when a new tag is discovered. */
export type TagListener = (tagInfo: tag.TagInfo, supportResult: number) => void;

export class NfcService {
  private static tagInfo: tag.TagInfo | null = null;
  private static keyMap: Map<number, SectorKeys> | null = null;
  private static keyMapRangeFrom: number = 0;
  private static keyMapRangeTo: number = 0;
  private static tagListener: TagListener | null = null;
  private static editorOnly: boolean = false;
  private static pathStack: NavPathStack | null = null;
  private static uiContext: UIContext | null = null;
  private static isForeground: boolean = false;
  private static foregroundRegistered: boolean = false;

  // ---------------- App init ----------------

  static init(context: common.UIAbilityContext): void {
    MctApp.setContext(context);
    NfcService.editorOnly = Prefs.getBool(PrefKey.UseAsEditorOnly, false);
    try {
      nfcController.on('nfcStateChange', (state: nfcController.NfcState): void => {
        if (state === nfcController.NfcState.STATE_ON) {
          NfcService.registerForegroundDispatch();
        } else {
          NfcService.foregroundRegistered = false;
        }
      });
    } catch (e) {
      hilog.error(0x0000, 'MctApp', 'nfcStateChange listener failed: %{public}s', JSON.stringify(e));
    }
  }

  static setUiContext(uiContext: UIContext): void {
    NfcService.uiContext = uiContext;
  }

  static setNavPathStack(pathStack: NavPathStack): void {
    NfcService.pathStack = pathStack;
  }

  static getNavPathStack(): NavPathStack | null {
    return NfcService.pathStack;
  }

  // ---------------- NFC availability ----------------

  /** Device has NFC hardware. */
  static isNfcAvailable(): boolean {
    try {
      return canIUse('SystemCapability.Communication.NFC.Core');
    } catch (e) {
      return false;
    }
  }

  /** NFC is turned on. */
  static isNfcEnabled(): boolean {
    try {
      return nfcController.getNfcState() === nfcController.NfcState.STATE_ON;
    } catch (e) {
      return false;
    }
  }

  // ---------------- Foreground dispatch ----------------

  /**
   * Register the foreground tag dispatch so tag discoveries are
   * delivered to this app while it is in the foreground
   * (tag.registerForegroundDispatch).
   */
  static registerForegroundDispatch(): void {
    if (!NfcService.isForeground || NfcService.foregroundRegistered) {
      return;
    }
    if (!NfcService.isNfcEnabled()) {
      // Retry happens once NFC gets enabled (nfcStateChange).
      return;
    }
    try {
      const context: common.UIAbilityContext = MctApp.getContext();
      const elementName: bundleManager.ElementName = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      };
      tag.registerForegroundDispatch(elementName,
        [tag.NFC_A, tag.MIFARE_CLASSIC, tag.MIFARE_ULTRALIGHT],
        (error: BusinessError, tagInfo: tag.TagInfo): void => {
          if ((error === undefined || error === null)
            && tagInfo !== null && tagInfo !== undefined) {
            NfcService.handleTagDiscovered(tagInfo);
          }
        });
      NfcService.foregroundRegistered = true;
      hilog.info(0x0000, 'MctApp', 'foreground dispatch registered');
    } catch (e) {
      hilog.error(0x0000, 'MctApp', 'registerForegroundDispatch failed: %{public}s', JSON.stringify(e));
    }
  }

  /** Unregister the foreground tag dispatch. */
  static unregisterForegroundDispatch(): void {
    if (!NfcService.foregroundRegistered) {
      return;
    }
    try {
      const context: common.UIAbilityContext = MctApp.getContext();
      const elementName: bundleManager.ElementName = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: context.abilityInfo.name
      };
      tag.unregisterForegroundDispatch(elementName);
    } catch (e) {
      hilog.error(0x0000, 'MctApp', 'unregisterForegroundDispatch failed: %{public}s', JSON.stringify(e));
    }
    NfcService.foregroundRegistered = false;
  }

  /** App moved to the foreground (EntryAbility.onForeground). */
  static onAppForeground(): void {
    NfcService.isForeground = true;
    NfcService.registerForegroundDispatch();
  }

  /** App moved to the background (EntryAbility.onBackground). */
  static onAppBackground(): void {
    NfcService.isForeground = false;
    NfcService.unregisterForegroundDispatch();
  }

  // ---------------- Editor only mode ----------------

  static useAsEditorOnly(): boolean {
    return NfcService.editorOnly;
  }

  static setUseAsEditorOnly(editorOnly: boolean): void {
    NfcService.editorOnly = editorOnly;
    Prefs.putBool(PrefKey.UseAsEditorOnly, editorOnly);
  }

  // ---------------- Tag state ----------------

  static getTag(): tag.TagInfo | null {
    return NfcService.tagInfo;
  }

  static getUID(): number[] | null {
    if (NfcService.tagInfo !== null) {
      return NfcService.tagInfo.uid;
    }
    return null;
  }

  static setTagListener(listener: TagListener | null): void {
    NfcService.tagListener = listener;
  }

  /**
   * Check whether tag and device support MIFARE Classic.
   * 0 = supported; -2 = tag not MIFARE Classic; -3 = error.
   * (-1 device check is not applicable on HarmonyOS.)
   */
  static checkMifareClassicSupport(tagInfo: tag.TagInfo | null): number {
    if (tagInfo === null) {
      return -3;
    }
    try {
      const mfc = tag.getMifareClassic(tagInfo);
      if (mfc !== null && mfc !== undefined) {
        return 0;
      }
    } catch (e) {
      return -2;
    }
    return -2;
  }

  /**
   * Handle a newly discovered tag (Common.treatAsNewTag equivalent).
   * Logs the UID, shows the "new tag found"/auto-copy toast and
   * dispatches to the registered listener (or pushes the tag info
   * tool if the tag does not support MIFARE Classic).
   */
  static handleTagDiscovered(newTagInfo: tag.TagInfo): void {
    NfcService.tagInfo = newTagInfo;
    const uid = HexUtils.bytes2Hex(newTagInfo.uid);
    MctFiles.logUid(uid);
    const support = NfcService.checkMifareClassicSupport(newTagInfo);
    if (Prefs.getBool(PrefKey.AutoCopyUID, false)) {
      const fmt = Prefs.getInt(PrefKey.UIDFormat, 0);
      const fmtUid = HexUtils.byte2FmtString(newTagInfo.uid, fmt);
      NfcService.toast('UID 已复制到剪贴板 (' + fmtUid + ')', false);
      NfcService.copyToClipboard(fmtUid, false);
    } else {
      NfcService.toast('发现新标签 (UID: ' + uid + ')', true);
    }
    if (NfcService.tagListener !== null) {
      const listener = NfcService.tagListener;
      listener(newTagInfo, support);
    } else if (support === -2 && NfcService.pathStack !== null) {
      NfcService.pathStack.pushPathByName('tagInfoTool', null);
    }
  }

  /**
   * Check whether a tag is present and connect to it.
   * Returns a connected reader or null (with toast).
   */
  static checkForTagAndCreateReader(): McReader | null {
    if (NfcService.tagInfo !== null) {
      const reader = McReader.get(NfcService.tagInfo);
      if (reader !== null) {
        let tagLost = false;
        try {
          reader.connect();
        } catch (e) {
          tagLost = true;
        }
        if (!tagLost && !reader.isConnected()) {
          reader.close();
          tagLost = true;
        }
        if (!tagLost) {
          return reader;
        }
      }
    }
    NfcService.toast('错误：未找到 MIFARE Classic 标签。请重新贴近标签并重试', true);
    return null;
  }

  // ---------------- Key map ----------------

  static setKeyMap(keyMap: Map<number, SectorKeys> | null): void {
    NfcService.keyMap = keyMap;
  }

  static getKeyMap(): Map<number, SectorKeys> | null {
    return NfcService.keyMap;
  }

  static setKeyMapRange(from: number, to: number): void {
    NfcService.keyMapRangeFrom = from;
    NfcService.keyMapRangeTo = to;
  }

  static getKeyMapRangeFrom(): number {
    return NfcService.keyMapRangeFrom;
  }

  static getKeyMapRangeTo(): number {
    return NfcService.keyMapRangeTo;
  }

  // ---------------- UI helpers ----------------

  static toast(message: string, long: boolean): void {
    const duration = long ? 3500 : 1500;
    if (NfcService.uiContext !== null) {
      NfcService.uiContext.getPromptAction().showToast({ message: message, duration: duration });
    } else {
      promptAction.showToast({ message: message, duration: duration });
    }
  }

  static copyToClipboard(text: string, showMsg: boolean): void {
    if (text === null || text.length === 0) {
      return;
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).catch((error: BusinessError) => {
      // Ignore clipboard errors.
    });
    if (showMsg) {
      NfcService.toast('已复制到剪贴板', false);
    }
  }

  static getFromClipboard(): string | null {
    try {
      const data: pasteboard.PasteData =
        pasteboard.getSystemPasteboard().getDataSync();
      if (data !== null && data !== undefined) {
        const text: string = data.getPrimaryText();
        if (text !== null && text !== undefined && text.length > 0) {
          return text;
        }
      }
    } catch (e) {
      // Ignore.
    }
    return null;
  }

  // ---------------- Misc ----------------

  static getVersionName(): string {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionName;
    } catch (e) {
      return '';
    }
  }

  static getVersionCode(): number {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      return info.versionCode;
    } catch (e) {
      return 0;
    }
  }

  /** Share a text file via the system share panel. */
  static shareTextFile(path: string): void {
    try {
      const uri: string = fileUri.getUriFromPath(path);
      const extIdx: number = path.lastIndexOf('.');
      let utdType: string = uniformTypeDescriptor.UniformDataType.PLAIN_TEXT;
      if (extIdx !== -1) {
        try {
          const precise: string = uniformTypeDescriptor.getUniformDataTypeByFilenameExtension(
            path.substring(extIdx), uniformTypeDescriptor.UniformDataType.TEXT);
          if (precise !== null && precise !== undefined && precise.length > 0) {
            utdType = precise;
          }
        } catch (e2) {
          // Unknown extension: keep the plain text type.
        }
      }
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utdType,
        uri: uri,
        title: path.substring(path.lastIndexOf('/') + 1)
      });
      const controller: systemShare.ShareController =
        new systemShare.ShareController(data);
      controller.show(MctApp.getContext(), {})
        .catch((error: BusinessError): void => {
          NfcService.toast('错误：分享文件失败', false);
        });
    } catch (e) {
      NfcService.toast('错误：分享文件失败', false);
    }
  }
}
