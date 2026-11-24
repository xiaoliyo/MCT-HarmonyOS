/*
 * MIFARE Classic Tool - HarmonyOS port.
 * Ported from de.syss.MifareClassicTool (GPL-3.0, Gerhard Klostermeier).
 */

import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { tag } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { MctApp } from '../common/MctApp';
import { MctFiles } from '../common/MctFiles';
import { NfcService } from '../common/NfcService';
import { Prefs } from '../common/Prefs';

const DOMAIN = 0x0000;
const TAG_FOUND_ACTION: string = 'ohos.nfc.tag.action.TAG_FOUND';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'MctApp', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'MctApp', '%{public}s', 'Ability onCreate');
    MctApp.setContext(this.context);
    // Init the app (preferences, folders, standard key files) and
    // then handle a possible NFC tag discovery cold start.
    this.initApp().then((): void => {
      this.handleWant(want);
    }).catch((error: BusinessError): void => {
      hilog.error(DOMAIN, 'MctApp', 'initApp failed: %{public}s', JSON.stringify(error));
    });
  }

  private async initApp(): Promise<void> {
    try {
      await Prefs.init(this.context);
      hilog.info(DOMAIN, 'MctApp', 'initApp: prefs ready');
    } catch (e) {
      hilog.error(DOMAIN, 'MctApp', 'Prefs init failed: %{public}s', JSON.stringify(e));
    }
    try {
      NfcService.init(this.context);
      hilog.info(DOMAIN, 'MctApp', 'initApp: nfc service ready');
    } catch (e) {
      hilog.error(DOMAIN, 'MctApp', 'NfcService init failed: %{public}s', JSON.stringify(e));
    }
    try {
      MctFiles.initFolders();
      hilog.info(DOMAIN, 'MctApp', 'initApp: folders ready (%{public}s)', MctFiles.getKeysDir());
    } catch (e) {
      hilog.error(DOMAIN, 'MctApp', 'initFolders failed: %{public}s', JSON.stringify(e));
    }
    try {
      MctFiles.copyStdKeysFiles();
      hilog.info(DOMAIN, 'MctApp', 'initApp: std key files copied');
    } catch (e) {
      hilog.error(DOMAIN, 'MctApp', 'copyStdKeysFiles failed: %{public}s', JSON.stringify(e));
    }
    // Verify from inside the app sandbox: list the key files.
    const keyFiles: string[] = MctFiles.listFileNames(MctFiles.getKeysDir());
    hilog.info(DOMAIN, 'MctApp', 'verify: keys dir exists=%{public}s files=%{public}s count=%{public}d',
      MctFiles.exists(MctFiles.getKeysDir()).toString(), JSON.stringify(keyFiles), keyFiles.length);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // A tag was discovered while the app was running in the
    // foreground/background.
    this.handleWant(want);
  }

  private handleWant(want: Want): void {
    if (want === null || want === undefined
      || want.action === null || want.action === undefined
      || want.action !== TAG_FOUND_ACTION) {
      return;
    }
    try {
      const tagInfo: tag.TagInfo | null = tag.getTagInfo(want);
      if (tagInfo !== null && tagInfo !== undefined) {
        NfcService.handleTagDiscovered(tagInfo);
      }
    } catch (e) {
      hilog.error(DOMAIN, 'MctApp', 'getTagInfo failed: %{public}s', JSON.stringify(e));
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'MctApp', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'MctApp', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'MctApp', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'MctApp', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'MctApp', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'MctApp', '%{public}s', 'Ability onForeground');
    NfcService.onAppForeground();
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'MctApp', '%{public}s', 'Ability onBackground');
    NfcService.onAppBackground();
  }
}
