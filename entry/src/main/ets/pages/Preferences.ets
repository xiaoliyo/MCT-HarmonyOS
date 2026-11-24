/**
 * Preferences (port of de.syss.MifareClassicTool.Activities.Preferences,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Global settings screen. Lets the user edit the auto reconnect,
 * auto copy UID (incl. UID format), save last used key files, custom
 * sector count, retry authentication and custom app theme
 * preferences. On "Save" the settings are validated and then
 * persisted via Prefs; "Cancel" exits without saving.
 *
 * The language chooser of the Android original was removed: the UI
 * strings are hardcoded Simplified Chinese, so a custom app language
 * (incl. i18n.System.setAppPreferredLanguage) no longer serves a
 * purpose.
 *
 * Omitted from the Android original: the "Autostart the app if a tag
 * is detected" checkbox. On Android it toggles a launcher alias
 * component (PackageManager.setComponentEnabledSetting). There is no
 * HarmonyOS equivalent and NFC tag dispatch is already configured
 * through the app manifest.
 */

import { tag } from '@kit.ConnectivityKit';
import { MctDialog } from '../common/ui/MctDialog';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { PrefKey } from '../common/MctTypes';
import { Prefs } from '../common/Prefs';

/**
 * Static chooser entries (res/values/strings.xml:
 * R.array.action_themes).
 */
class PreferencesEntries {
  /** Themes (R.array.action_themes). 0=dark, 1=light, 2=follow system. */
  static readonly THEMES: string[] = [
    '深色主题',
    '浅色主题',
    '跟随系统'
  ];
}

/** Convert plain display strings into Select options. */
function toSelectOptions(entries: string[]): SelectOption[] {
  const options: SelectOption[] = [];
  for (let i = 0; i < entries.length; i++) {
    options.push({ value: entries[i] });
  }
  return options;
}

@Component
struct PreferencesPage {
  @State autoReconnect: boolean = false;
  @State autoCopyUID: boolean = false;
  @State uidFormat: number = 0; // 0=Hex; 1=Dec (BE); 2=Dec (LE).
  @State saveLastUsedKeyFiles: boolean = true;
  @State useCustomSectorCount: boolean = false;
  @State customSectorCountInput: string = '16';
  @State useRetryAuthentication: boolean = false;
  @State retryAuthenticationCountInput: string = '1';
  @State themeIndex: number = 2;
  @State themeLabel: string = '跟随系统';
  private pathStack: NavPathStack = new NavPathStack();
  private dialogCtrl: CustomDialogController | null = null;
  private themeOptions: SelectOption[] =
    toSelectOptions(PreferencesEntries.THEMES);

  aboutToAppear(): void {
    MctTheme.refresh();
    // Assign the last stored values (Android: onCreate).
    this.autoReconnect = Prefs.getBool(PrefKey.AutoReconnect, false);
    this.autoCopyUID = Prefs.getBool(PrefKey.AutoCopyUID, false);
    this.uidFormat = Prefs.getInt(PrefKey.UIDFormat, 0);
    this.saveLastUsedKeyFiles =
      Prefs.getBool(PrefKey.SaveLastUsedKeyFiles, true);
    this.useCustomSectorCount =
      Prefs.getBool(PrefKey.UseCustomSectorCount, false);
    this.customSectorCountInput =
      Prefs.getInt(PrefKey.CustomSectorCount, 16).toString();
    this.useRetryAuthentication =
      Prefs.getBool(PrefKey.UseRetryAuthentication, false);
    this.retryAuthenticationCountInput =
      Prefs.getInt(PrefKey.RetryAuthenticationCount, 1).toString();
    this.themeIndex = Prefs.getInt(PrefKey.CustomAppTheme, 2);
    if (this.themeIndex < 0
      || this.themeIndex >= PreferencesEntries.THEMES.length) {
      this.themeIndex = 2;
    }
    this.themeLabel = PreferencesEntries.THEMES[this.themeIndex];
  }

  // ---------------- Info dialogs ----------------

  /** Show an info dialog with a single OK button. */
  private showInfoDialog(title: string, message: string): void {
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: title,
        messageText: message,
        button1Text: '确定',
        button1Action: (checked: boolean): void => {
          // Do nothing.
        },
        dismissAction: (checked: boolean): void => {
          // Do nothing.
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        action.dismiss();
      }
    });
    this.dialogCtrl?.open();
  }

  /**
   * Show information on the "auto reconnect" preference
   * (Android: onShowAutoReconnectInfo).
   */
  private onShowAutoReconnectInfo(): void {
    this.showInfoDialog('自动重连',
      '如果标签在密钥映射过程中丢失（由于天线问题、超时等），'
      + '应用将尝试重新连接它（延迟 500ms），直到某次尝试成功。\n\n'
      + '如果您在密钥映射过程中遇到问题，这可能会有所帮助。'
      + '但它也可能导致 MCT 出现异常行为。\n\n'
      + '已知此设置可能有帮助的问题：\n• 特殊标签（如 smartMX）');
  }

  /**
   * Show information on the "use custom sector count" preference
   * (Android: onShowCustomSectorCountInfo).
   */
  private onShowCustomSectorCountInfo(): void {
    this.showInfoDialog('自定义扇区数',
      '强制使用自定义扇区数，并忽略系统检测到的扇区数。'
      + '这对于具有 2K 内存的标签可能很有用。');
  }

  /**
   * Show information on the "use retry authentication" preference
   * (Android: onShowRetryAuthenticationInfo).
   */
  private onShowRetryAuthenticationInfo(): void {
    this.showInfoDialog('重试认证',
      '认证（访问某个扇区/块）失败时重试 X 次。\n\n'
      + '某些标签需要此功能才能正常工作'
      + '（例如某些块 0 可写且 UID 为 7 字节的标签）。'
      + '此外，这可能有助于某些设备更稳定地工作'
      + '（例如 Google Nexus 5X 或华为 P10）。\n\n'
      + '请注意，这可能会降低读取、写入甚至密钥映射的速度。'
      + '在大多数情况下，建议保持此选项处于禁用状态。');
  }

  // ---------------- Save / Cancel ----------------

  /**
   * Check the settings, save all preferences, update the theme,
   * and exit the view (Android: onSave).
   */
  private onSave(): void {
    // Check if the settings are valid (custom sector count).
    let customSectorCount: number = 16;
    if (this.useCustomSectorCount) {
      let error: boolean = false;
      if (/^[0-9]+$/.test(this.customSectorCountInput)) {
        customSectorCount = parseInt(this.customSectorCountInput, 10);
        if (customSectorCount > 40 || customSectorCount <= 0) {
          error = true;
        }
      } else {
        // Error, not a number.
        error = true;
      }
      if (error) {
        NfcService.toast(
          '错误：扇区数必须在 1 到 40 之间', true);
        return;
      }
    }

    // Check if the settings are valid (retry authentication count).
    let retryAuthenticationCount: number = 1;
    if (this.useRetryAuthentication) {
      let error: boolean = false;
      if (/^[0-9]+$/.test(this.retryAuthenticationCountInput)) {
        retryAuthenticationCount =
          parseInt(this.retryAuthenticationCountInput, 10);
        if (retryAuthenticationCount > 1000
          || retryAuthenticationCount <= 0) {
          error = true;
        }
      } else {
        // Error, not a number.
        error = true;
      }
      if (error) {
        NfcService.toast(
          '错误：重试次数必须在 1 到 1000 之间', true);
        return;
      }
    }

    // Save the preferences.
    Prefs.putBool(PrefKey.AutoReconnect, this.autoReconnect);
    Prefs.putBool(PrefKey.AutoCopyUID, this.autoCopyUID);
    Prefs.putInt(PrefKey.UIDFormat, this.uidFormat);
    Prefs.putBool(PrefKey.SaveLastUsedKeyFiles,
      this.saveLastUsedKeyFiles);
    Prefs.putBool(PrefKey.UseCustomSectorCount,
      this.useCustomSectorCount);
    Prefs.putInt(PrefKey.CustomSectorCount, customSectorCount);
    Prefs.putBool(PrefKey.UseRetryAuthentication,
      this.useRetryAuthentication);
    Prefs.putInt(PrefKey.RetryAuthenticationCount,
      retryAuthenticationCount);
    Prefs.putInt(PrefKey.CustomAppTheme, this.themeIndex);

    // Update the theme (re-reads the preference).
    MctTheme.refresh();

    // Exit the preferences view.
    this.pathStack.pop();
  }

  /**
   * Exit the preferences view without saving anything
   * (Android: onCancel).
   */
  private onCancel(): void {
    this.pathStack.pop();
  }

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        Scroll() {
          Column() {
            // === Auto reconnect ===
            Row() {
              Checkbox()
                .select(this.autoReconnect)
                .selectedColor(MctTheme.accent)
                .width(20)
                .height(20)
                .onChange((value: boolean): void => {
                  this.autoReconnect = value;
                })
              Text('高级：密钥映射过程中标签丢失时自动重连')
                .fontSize(14)
                .fontColor(MctTheme.fg)
                .layoutWeight(1)
                .margin({ left: 8 })
                .onClick(() => {
                  this.autoReconnect = !this.autoReconnect;
                })
              Text('ⓘ')
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(MctTheme.accent)
                .padding({ left: 8, right: 2 })
                .onClick(() => {
                  this.onShowAutoReconnectInfo();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding(5)
            .margin({ bottom: 5 })
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })

            // === Auto copy UID ===
            Column() {
              Row() {
                Checkbox()
                  .select(this.autoCopyUID)
                  .selectedColor(MctTheme.accent)
                  .width(20)
                  .height(20)
                  .onChange((value: boolean): void => {
                    this.autoCopyUID = value;
                  })
                Text('自动将新标签的 UID 复制到剪贴板')
                  .fontSize(14)
                  .fontColor(MctTheme.fg)
                  .layoutWeight(1)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.autoCopyUID = !this.autoCopyUID;
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              // UID format options (only enabled while the
              // auto copy UID checkbox is checked).
              Row({ space: 16 }) {
                Row() {
                  Radio({ value: 'prefUidHex', group: 'prefUidFormat' })
                    .checked(this.uidFormat === 0)
                    .enabled(this.autoCopyUID)
                    .width(20)
                    .height(20)
                    .onChange((isChecked: boolean): void => {
                      if (isChecked) {
                        this.uidFormat = 0;
                      }
                    })
                  Text('Hex')
                    .fontSize(14)
                    .fontColor(MctTheme.fg)
                    .margin({ left: 6 })
                    .onClick(() => {
                      if (this.autoCopyUID) {
                        this.uidFormat = 0;
                      }
                    })
                }
                .alignItems(VerticalAlign.Center)
                Row() {
                  Radio({ value: 'prefUidDecBE', group: 'prefUidFormat' })
                    .checked(this.uidFormat === 1)
                    .enabled(this.autoCopyUID)
                    .width(20)
                    .height(20)
                    .onChange((isChecked: boolean): void => {
                      if (isChecked) {
                        this.uidFormat = 1;
                      }
                    })
                  Text('Dec (BE)')
                    .fontSize(14)
                    .fontColor(MctTheme.fg)
                    .margin({ left: 6 })
                    .onClick(() => {
                      if (this.autoCopyUID) {
                        this.uidFormat = 1;
                      }
                    })
                }
                .alignItems(VerticalAlign.Center)
                Row() {
                  Radio({ value: 'prefUidDecLE', group: 'prefUidFormat' })
                    .checked(this.uidFormat === 2)
                    .enabled(this.autoCopyUID)
                    .width(20)
                    .height(20)
                    .onChange((isChecked: boolean): void => {
                      if (isChecked) {
                        this.uidFormat = 2;
                      }
                    })
                  Text('Dec (LE)')
                    .fontSize(14)
                    .fontColor(MctTheme.fg)
                    .margin({ left: 6 })
                    .onClick(() => {
                      if (this.autoCopyUID) {
                        this.uidFormat = 2;
                      }
                    })
                }
                .alignItems(VerticalAlign.Center)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ left: 30, top: 2 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(5)
            .margin({ bottom: 5 })
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })

            // === Save last used key files ===
            Row() {
              Checkbox()
                .select(this.saveLastUsedKeyFiles)
                .selectedColor(MctTheme.accent)
                .width(20)
                .height(20)
                .onChange((value: boolean): void => {
                  this.saveLastUsedKeyFiles = value;
                })
              Text('记住上次选择的密钥文件（密钥映射对话框）')
                .fontSize(14)
                .fontColor(MctTheme.fg)
                .layoutWeight(1)
                .margin({ left: 8 })
                .onClick(() => {
                  this.saveLastUsedKeyFiles = !this.saveLastUsedKeyFiles;
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .padding(5)
            .margin({ bottom: 5 })
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })

            // === Use custom sector count ===
            Column() {
              Row() {
                Checkbox()
                  .select(this.useCustomSectorCount)
                  .selectedColor(MctTheme.accent)
                  .width(20)
                  .height(20)
                  .onChange((value: boolean): void => {
                    this.useCustomSectorCount = value;
                  })
                Text('使用自定义扇区数')
                  .fontSize(14)
                  .fontColor(MctTheme.fg)
                  .layoutWeight(1)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.useCustomSectorCount = !this.useCustomSectorCount;
                  })
                Text('ⓘ')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(MctTheme.accent)
                  .padding({ left: 8, right: 2 })
                  .onClick(() => {
                    this.onShowCustomSectorCountInfo();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              TextInput({ text: this.customSectorCountInput,
                placeholder: '例如 1K 为 16' })
                .enabled(this.useCustomSectorCount)
                .type(InputType.Number)
                .width(150)
                .height(40)
                .fontSize(15)
                .fontColor(MctTheme.fg)
                .placeholderColor(MctTheme.fgSecondary)
                .placeholderFont({ size: 15 })
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .margin({ left: 30, top: 4 })
                .onChange((value: string): void => {
                  this.customSectorCountInput = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(5)
            .margin({ bottom: 5 })
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })

            // === Use retry authentication ===
            Column() {
              Row() {
                Checkbox()
                  .select(this.useRetryAuthentication)
                  .selectedColor(MctTheme.accent)
                  .width(20)
                  .height(20)
                  .onChange((value: boolean): void => {
                    this.useRetryAuthentication = value;
                  })
                Text('认证失败时重试')
                  .fontSize(14)
                  .fontColor(MctTheme.fg)
                  .layoutWeight(1)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.useRetryAuthentication = !this.useRetryAuthentication;
                  })
                Text('ⓘ')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(MctTheme.accent)
                  .padding({ left: 8, right: 2 })
                  .onClick(() => {
                    this.onShowRetryAuthenticationInfo();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              TextInput({ text: this.retryAuthenticationCountInput,
                placeholder: '重试次数' })
                .enabled(this.useRetryAuthentication)
                .type(InputType.Number)
                .width(150)
                .height(40)
                .fontSize(15)
                .fontColor(MctTheme.fg)
                .placeholderColor(MctTheme.fgSecondary)
                .placeholderFont({ size: 15 })
                .caretColor(MctTheme.accent)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .margin({ left: 30, top: 4 })
                .onChange((value: string): void => {
                  this.retryAuthenticationCountInput = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(5)
            .margin({ bottom: 5 })
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })

            // === Custom theme ===
            Column() {
              Text('选择自定义主题')
                .fontSize(14)
                .fontColor(MctTheme.fg)
                .width('100%')
              Select(this.themeOptions)
                .selected(this.themeIndex)
                .value(this.themeLabel)
                .font({ size: 15 })
                .fontColor(MctTheme.fg)
                .backgroundColor(MctTheme.inputBg)
                .borderRadius(4)
                .height(40)
                .width('100%')
                .margin({ top: 4 })
                .onSelect((index: number, value: string): void => {
                  this.themeIndex = index;
                  this.themeLabel = value;
                })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(5)
            .margin({ bottom: 5 })
            .borderRadius(5)
            .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(5)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)

        // Separator (Android: separatorPreferences).
        Divider()
          .strokeWidth(2)
          .color(MctTheme.LIGHT_GRAY)
          .width('100%')
          .margin({ top: 2, bottom: 2 })

        // Save and cancel buttons.
        Row({ space: 8 }) {
          Button('取消')
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .onClick(() => {
              this.onCancel();
            })
          Button('保存')
            .layoutWeight(1)
            .height(44)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(MctTheme.fg)
            .backgroundColor(MctTheme.buttonBg)
            .borderRadius(4)
            .onClick(() => {
              this.onSave();
            })
        }
        .width('100%')
        .padding(5)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('首选项')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener. A tag that does not support
      // MIFARE Classic opens the tag info tool (BasicActivity
      // onResume equivalent).
      NfcService.setTagListener(
        (tagInfo: tag.TagInfo, supportResult: number): void => {
          if (supportResult === -2) {
            this.pathStack.pushPathByName('tagInfoTool', null);
          }
        });
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function PreferencesBuilder() {
  PreferencesPage()
}
