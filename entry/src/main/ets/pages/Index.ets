/**
 * Main menu (port of de.syss.MifareClassicTool.Activities.MainMenu,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Shows the 6 main buttons, the tools menu, the app version footer and
 * runs the startup chain (first use dialog, NFC checks, donate dialog).
 */

import { Want } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { DumpEditorParams } from './DumpEditor';
import { FileChooserParams } from './FileChooser';
import { KeyEditorParams } from './KeyEditor';
import { MctFiles } from '../common/MctFiles';
import { MctApp } from '../common/MctApp';
import { MctDialog } from '../common/ui/MctDialog';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';
import { PrefKey } from '../common/MctTypes';
import { Prefs } from '../common/Prefs';

@Entry
@Component
struct Index {
  @State editorOnly: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private dialogCtrl: CustomDialogController | null = null;
  private donateDialogShown: boolean = false;
  private uiScale: number = 1;

  aboutToAppear(): void {
    MctTheme.refresh();
    NfcService.setUiContext(this.getUIContext());
    NfcService.setNavPathStack(this.pathStack);
    try {
      const disp: display.Display = display.getDefaultDisplaySync();
      const screenVp: number = disp.width / disp.densityPixels;
      this.uiScale = Math.min(1.75, Math.max(1.0, screenVp / 360));
    } catch (error) {
      // Keep the default scale.
    }
  }

  onPageShow(): void {
    MctTheme.refresh();
    this.editorOnly = NfcService.useAsEditorOnly();
    this.runStartupChain();
  }

  // ---------------- Startup chain (runStartUpNode) ----------------

  private runStartupChain(): void {
    if (Prefs.getBool(PrefKey.IsFirstRun, true)) {
      this.showFirstRunDialog();
      return;
    }
    this.checkNfc();
  }

  private checkNfc(): void {
    if (!NfcService.isNfcAvailable()) {
      this.showNoNfcSupportDialog();
      return;
    }
    if (!NfcService.isNfcEnabled()) {
      if (!NfcService.useAsEditorOnly()) {
        this.showNfcEnableDialog();
        return;
      }
      this.showDonateDialogOnce();
      return;
    }
    NfcService.setUseAsEditorOnly(false);
    this.editorOnly = false;
    this.showDonateDialogOnce();
  }

  private useEditorOnly(): void {
    NfcService.setUseAsEditorOnly(true);
    this.editorOnly = true;
    this.showDonateDialogOnce();
  }

  private exitApp(): void {
    MctApp.getContext().terminateSelf().catch((error: BusinessError): void => {
      // Ignore.
    });
  }

  private openNfcSettings(): void {
    const want: Want = {
      bundleName: 'com.huawei.hmos.settings',
      abilityName: 'com.huawei.hmos.settings.MainAbility'
    };
    MctApp.getContext().startAbility(want).catch((error: BusinessError): void => {
      NfcService.toast('错误：无法打开设置应用', false);
    });
  }

  private showDonateDialogOnce(): void {
    if (this.donateDialogShown) {
      return;
    }
    const currentVersion: number = NfcService.getVersionCode();
    const lastVersion: number = Prefs.getInt(PrefKey.MctVersion, currentVersion - 1);
    const showDonateDialog: boolean = Prefs.getBool(PrefKey.ShowDonateDialog, true);
    if (lastVersion < currentVersion || showDonateDialog) {
      if (lastVersion < currentVersion) {
        Prefs.putInt(PrefKey.MctVersion, currentVersion);
        Prefs.putBool(PrefKey.ShowDonateDialog, true);
      }
      this.showDonateDialog();
    }
  }

  // ---------------- Dialogs ----------------

  private showFirstRunDialog(): void {
    const onOk = (): void => {
      Prefs.putBool(PrefKey.IsFirstRun, false);
      this.checkNfc();
    };
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: '警告提示',
        messageText: '本应用面向至少对 MIFARE Classic 技术有基本了解的用户。'
          + '其功能较为基础且处于底层，因此几乎所有数据的输入和输出均为十六进制。'
          + '同样重要的是，您必须清楚自己在做什么，例如在向标签写入数据时。'
          + '向某些块写入错误的数据可能会对标签造成无法修复的损坏。\n\n'
          + '如需更多信息与帮助，请查看“帮助与信息”部分。',
        button1Text: '确定',
        button1Action: (checked: boolean): void => {
          onOk();
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        action.dismiss();
        onOk();
      }
    });
    this.dialogCtrl.open();
  }

  private showNoNfcSupportDialog(): void {
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: '不支持 NFC',
        messageText: '您的设备没有 NFC 读卡器，因此无法读取或写入 NFC 标签。\n\n'
          + '如果您的设备支持 USB-OTG，或许可以为设备连接一个外部 NFC 读卡器。\n\n'
          + 'MIFARE Classic Tool 应可与“External NFC”应用配合使用，'
          + '该应用支持多种基于 USB 的 NFC 读卡器，但可能存在一些限制。',
        button3Text: '“离线”模式',
        button3Action: (checked: boolean): void => {
          this.useEditorOnly();
        },
        button2Text: '退出应用',
        button2Action: (checked: boolean): void => {
          this.exitApp();
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        action.dismiss();
        this.exitApp();
      }
    });
    this.dialogCtrl.open();
  }

  private showNfcEnableDialog(): void {
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: 'NFC 未启用',
        messageText: 'NFC 适配器未启用。\n请前往设置并启用它。',
        button1Text: '前往 NFC 设置',
        button1Action: (checked: boolean): void => {
          this.openNfcSettings();
        },
        button3Text: '“离线”模式',
        button3Action: (checked: boolean): void => {
          this.useEditorOnly();
        },
        button2Text: '退出应用',
        button2Action: (checked: boolean): void => {
          this.exitApp();
        }
      }),
      alignment: DialogAlignment.Center,
      autoCancel: false,
      customStyle: true,
      onWillDismiss: (action: DismissDialogAction): void => {
        action.dismiss();
        this.exitApp();
      }
    });
    this.dialogCtrl.open();
  }

  private showDonateDialog(): void {
    this.donateDialogShown = true;
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: '捐赠',
        messageText: 'MIFARE Classic Tool 已更新！\n'
          + '您可以在网上查看完整的更新日志。\n\n'
          + '如果新功能、问题修复或本应用整体让您感到满意，'
          + '请考虑也让开发者开心一下。请他喝杯啤酒吧！;)\n\n'
          + '• 获取捐赠版\n• GitHub 上的 MCT / 捐赠链接',
        showCheckbox: true,
        checkboxText: '不再显示此消息',
        button1Text: '确定',
        dismissAction: (checked: boolean): void => {
          if (checked) {
            // Do not show the donate dialog again.
            Prefs.putBool(PrefKey.ShowDonateDialog, false);
          }
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

  private showAboutDialog(): void {
    const message: string = 'MIFARE Classic Tool (MCT)\n\n'
      + '• 版本：' + NfcService.getVersionName() + '\n'
      + '• 许可证：GPLv3\n'
      + '• 项目主页：GitHub 上的 MCT\n'
      + '• 为应用评分：通过 Google Play\n'
      + '• 捐赠：Google Play\n\n'
      + '实用信息：\n'
      + '• 错误跟踪器\n'
      + '• 更新日志 / 版本历史\n'
      + '• 文档、APK 等\n'
      + '• Proxmark 论坛讨论帖\n\n'
      + 'MIFARE® 是 NXP Semiconductors 的注册商标。';
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: '关于 MCT',
        messageText: message,
        button1Text: '确定'
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

  // ---------------- Navigation ----------------

  private pushRoute(name: string): void {
    this.pathStack.pushPathByName(name, null);
  }

  private openDumpEditor(): void {
    const dumpsDir: string = MctFiles.getDumpsDir();
    if (MctFiles.listFileNames(dumpsDir).length === 0) {
      NfcService.toast('暂无转储文件。请先读取标签并保存转储', true);
    }
    this.pathStack.pushPathByName('fileChooser', new FileChooserParams(
      dumpsDir,
      '打开标签转储',
      '',
      '打开转储文件',
      false,
      (file: string | null): void => {
        if (file !== null) {
          const params: DumpEditorParams = new DumpEditorParams();
          params.chosenFile = file;
          this.pathStack.pushPathByName('dumpEditor', params);
        }
      }));
  }

  private openKeyEditor(): void {
    this.pathStack.pushPathByName('fileChooser', new FileChooserParams(
      MctFiles.getKeysDir(),
      '打开或创建密钥文件',
      '',
      '打开密钥文件',
      true,
      (file: string | null): void => {
        if (file !== null) {
          const params: KeyEditorParams = new KeyEditorParams();
          params.chosenFile = file;
          this.pathStack.pushPathByName('keyEditor', params);
        }
      }));
  }

  // ---------------- Menus ----------------

  @Builder
  optionsMenuBuilder() {
    Menu() {
      MenuItem({ content: '关于' })
        .onClick(() => {
          this.showAboutDialog();
        })
    }
  }

  @Builder
  toolsMenuBuilder() {
    Menu() {
      MenuItem({ content: '可用工具' })
        .enabled(false)
        .contentFontColor(MctTheme.fgSecondary)
        .contentFont({ size: 14 })
      MenuItem({ content: '显示标签信息' })
        .enabled(!this.editorOnly)
        .onClick(() => {
          this.pushRoute('tagInfoTool');
        })
      MenuItem({ content: '克隆 UID' })
        .enabled(!this.editorOnly)
        .onClick(() => {
          this.pushRoute('cloneUidTool');
        })
      MenuItem({ content: '差异比对工具（比较转储）' })
        .onClick(() => {
          this.pushRoute('diffTool');
        })
      MenuItem({ content: '访问条件编/解码器' })
        .onClick(() => {
          this.pushRoute('acTool');
        })
      MenuItem({ content: '值块编/解码器' })
        .onClick(() => {
          this.pushRoute('valueBlockTool');
        })
      MenuItem({ content: 'BCC 计算器' })
        .onClick(() => {
          this.pushRoute('bccTool');
        })
      MenuItem({ content: '数据转换' })
        .onClick(() => {
          this.pushRoute('dataConversionTool');
        })
      MenuItem({ content: 'UID 日志' })
        .onClick(() => {
          this.pushRoute('uidLogTool');
        })
      MenuItem({ content: '导入/导出/转换文件' })
        .onClick(() => {
          this.pushRoute('importExportTool');
        })
    }
  }

  // ---------------- UI ----------------

  build() {
    Navigation(this.pathStack) {
      Column() {
        Row() {
          Text('MIFARE Classic Tool')
            .fontSize(20 * this.uiScale)
            .fontWeight(FontWeight.Bold)
            .fontColor(MctTheme.fg)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.ic_menu_preferences'))
            .width(26 * this.uiScale)
            .height(19 * this.uiScale)
            .fillColor(MctTheme.fg)
            .margin({ right: 51 * this.uiScale })
            .onClick(() => {
              this.pushRoute('preferences');
            })
          Image($r('app.media.ic_overflow'))
            .width(24 * this.uiScale)
            .height(24 * this.uiScale)
            .fillColor(MctTheme.fg)
            .margin({ right: 10 * this.uiScale })
            .bindMenu(this.optionsMenuBuilder)
        }
        .width('100%')
        .height(56 * this.uiScale)
        .padding({ left: 16 * this.uiScale })
        .alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            Row({ space: 8 * this.uiScale }) {
              Button() {
                Column({ space: 2 * this.uiScale }) {
                  Image($r('app.media.read_tag'))
                    .width(96 * this.uiScale)
                    .height(96 * this.uiScale)
                  Text('读标签')
                    .fontSize(14 * this.uiScale)
                    .fontColor(MctTheme.fg)
                    .maxLines(1)
                }
                .padding({ top: 4 * this.uiScale })
                .alignItems(HorizontalAlign.Center)
              }
              .layoutWeight(1)
              .height(123 * this.uiScale)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4 * this.uiScale)
              .enabled(!this.editorOnly)
              .opacity(this.editorOnly ? 0.4 : 1)
              .onClick(() => {
                this.pushRoute('readTag');
              })
              Button() {
                Column({ space: 2 * this.uiScale }) {
                  Image($r('app.media.write_tag'))
                    .width(96 * this.uiScale)
                    .height(96 * this.uiScale)
                  Text('写标签')
                    .fontSize(14 * this.uiScale)
                    .fontColor(MctTheme.fg)
                    .maxLines(1)
                }
                .padding({ top: 4 * this.uiScale })
                .alignItems(HorizontalAlign.Center)
              }
              .layoutWeight(1)
              .height(123 * this.uiScale)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4 * this.uiScale)
              .enabled(!this.editorOnly)
              .opacity(this.editorOnly ? 0.4 : 1)
              .onClick(() => {
                this.pushRoute('writeTag');
              })
            }
            .width('100%')
            .margin({ bottom: 12 * this.uiScale })

            Row({ space: 8 * this.uiScale }) {
              Button() {
                Column({ space: 2 * this.uiScale }) {
                  Image($r('app.media.edit_dump'))
                    .width(96 * this.uiScale)
                    .height(96 * this.uiScale)
                  Text('编辑 / 分析转储文件')
                    .fontSize(14 * this.uiScale)
                    .fontColor(MctTheme.fg)
                    .maxLines(1)
                }
                .padding({ top: 4 * this.uiScale })
                .alignItems(HorizontalAlign.Center)
              }
              .layoutWeight(1)
              .height(123 * this.uiScale)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4 * this.uiScale)
              .onClick(() => {
                this.openDumpEditor();
              })
              Button() {
                Column({ space: 2 * this.uiScale }) {
                  Image($r('app.media.edit_keys'))
                    .width(96 * this.uiScale)
                    .height(96 * this.uiScale)
                  Text('编辑 / 新建密钥文件')
                    .fontSize(14 * this.uiScale)
                    .fontColor(MctTheme.fg)
                    .maxLines(1)
                }
                .padding({ top: 4 * this.uiScale })
                .alignItems(HorizontalAlign.Center)
              }
              .layoutWeight(1)
              .height(123 * this.uiScale)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4 * this.uiScale)
              .onClick(() => {
                this.openKeyEditor();
              })
            }
            .width('100%')
            .margin({ bottom: 12 * this.uiScale })

            Row({ space: 8 * this.uiScale }) {
              Button() {
                Column({ space: 2 * this.uiScale }) {
                  Image($r('app.media.tools'))
                    .width(96 * this.uiScale)
                    .height(96 * this.uiScale)
                  Text('工具')
                    .fontSize(14 * this.uiScale)
                    .fontColor(MctTheme.fg)
                    .maxLines(1)
                }
                .padding({ top: 4 * this.uiScale })
                .alignItems(HorizontalAlign.Center)
              }
              .layoutWeight(1)
              .height(123 * this.uiScale)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4 * this.uiScale)
              .bindMenu(this.toolsMenuBuilder)
              Button() {
                Column({ space: 2 * this.uiScale }) {
                  Image($r('app.media.help_and_info'))
                    .width(96 * this.uiScale)
                    .height(96 * this.uiScale)
                  Text('帮助信息')
                    .fontSize(14 * this.uiScale)
                    .fontColor(MctTheme.fg)
                    .maxLines(1)
                }
                .padding({ top: 4 * this.uiScale })
                .alignItems(HorizontalAlign.Center)
              }
              .layoutWeight(1)
              .height(123 * this.uiScale)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4 * this.uiScale)
              .onClick(() => {
                this.pushRoute('help');
              })
            }
            .width('100%')
            .margin({ bottom: 12 * this.uiScale })
          }
          .padding({
            left: 14 * this.uiScale,
            right: 14 * this.uiScale,
            top: 14 * this.uiScale
          })
          .width('100%')
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)

        Text('App 版本: ' + NfcService.getVersionName())
          .fontSize(14 * this.uiScale)
          .fontColor(MctTheme.fgSecondary)
          .width('100%')
          .textAlign(TextAlign.End)
          .margin({ right: 14 * this.uiScale, bottom: 1 * this.uiScale })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }
}
