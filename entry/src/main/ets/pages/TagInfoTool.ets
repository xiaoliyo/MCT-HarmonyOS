/**
 * Tag Info tool (port of de.syss.MifareClassicTool.Activities.TagInfoTool,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * Displays generic info (UID, RF technology, ATQA, SAK, ATS, tag type and
 * manufacturer) and - if the tag supports MIFARE Classic - the MIFARE
 * Classic info (memory size, block size, sector/block count) of the
 * current tag. This is the only thing a user can do with a device that
 * does not support MIFARE Classic.
 */

import { tag } from '@kit.ConnectivityKit';
import { HexUtils } from '../common/HexUtils';
import { MctDialog } from '../common/ui/MctDialog';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

/**
 * Tag type lookup table (res/values/tag_type_list.xml).
 * The key is "tag_" + ATQA + SAK + ATS with hex letters in uppercase.
 * (Names must have at least one char. This is why they start with "tag_".)
 */
class TagInfoToolTagTypes {
  static readonly LOOKUP: Record<string, string> = {
    // With ATS
    'tag_0344207577810280': 'MIFARE DESFire or \nMIFARE DESFire EV1, NXP',
    'tag_0304283877B14A434f503331': 'JCOP31, IBM',
    'tag_0048207877B1024A434F5076323431': 'JCOP31 v2.4.1, IBM',
    'tag_0048203833B14A434F503431563232': 'JCOP41 v2.2, IBM',
    'tag_0004283833B14A434F50343156323331': 'JCOP41 v2.3.1, IBM',
    // Without ATS (ATQA+SAK)
    'tag_000409': 'MIFARE Mini, NXP',
    'tag_000408': 'MIFARE Classic 1k, NXP',
    'tag_000218': 'MIFARE Classic 4k, NXP',
    'tag_004218': 'MIFARE Classic 4k, NXP',
    'tag_004400': 'MIFARE Ultralight, NXP',
    'tag_000488': 'MIFARE Classic 1K, Infineon',
    'tag_000298': 'MPCOS, Gemplus',
    'tag_000238': 'MIFARE Classic 4k - emulated (6212 Classic), Nokia',
    'tag_000838': 'MIFARE Classic 4k - emulated (6131 NFC), Nokia',
    'tag_034420': 'MIFARE DESFire or \nMIFARE DESFire EV1, NXP',
    'tag_030428': 'JCOP31, IBM',
    'tag_004820': 'JCOP, IBM',
    'tag_000428': 'JCOP41, IBM',
    'tag_0F0101': 'TNP3xxx (MFC compatible), NXP',
    // Without SAK+ATS (only ATQA)
    'tag_0C00': 'Jewel, Innovision R&T'
  };
  // Special tag types.
  static readonly TAG_UNKNOWN: string = '未知';
  static readonly TAG_UNKNOWN_MF_CLASSIC: string = 'MIFARE Classic，未知';
}

@Component
struct TagInfoToolPage {
  @State hasTag: boolean = false;
  @State bannerText: string = '';
  @State uidText: string = '';
  @State atqaText: string = '';
  @State sakText: string = '';
  @State atsText: string = '';
  @State tagTypeText: string = '';
  @State showTagTypeGuess: boolean = false;
  @State showMifareInfo: boolean = false;
  @State memSizeText: string = '';
  @State sectorCountText: string = '';
  @State blockCountText: string = '';
  private pathStack: NavPathStack = new NavPathStack();
  private dialogCtrl: CustomDialogController | null = null;
  private mfcSupport: number = 0;

  aboutToAppear(): void {
    MctTheme.refresh();
    this.updateTagInfo(NfcService.getTag());
  }

  // ---------------- Tag info ----------------

  /**
   * Update and display the tag information.
   * If there is no MIFARE Classic support, a warning will be shown.
   */
  private updateTagInfo(tagInfo: tag.TagInfo | null): void {
    if (tagInfo === null) {
      // There is no tag.
      this.hasTag = false;
      this.bannerText = '';
      this.showMifareInfo = false;
      this.showTagTypeGuess = false;
      this.mfcSupport = 0;
      NfcService.toast(
        '错误：未找到 MIFARE Classic 标签。请重新触碰标签后重试',
        false);
      return;
    }
    this.hasTag = true;
    // Check for MIFARE Classic support.
    this.mfcSupport = NfcService.checkMifareClassicSupport(tagInfo);

    // Get generic info.
    // UID (with "CL2"/"CL3" for 7/10 byte UIDs).
    const uidLen: number = tagInfo.uid.length;
    let uid: string = HexUtils.bytes2Hex(tagInfo.uid)
      + ' (' + uidLen + ' 字节';
    if (uidLen === 7) {
      uid += ', CL2';
    } else if (uidLen === 10) {
      uid += ', CL3';
    }
    uid += ')';
    this.uidText = uid;

    // Swap ATQA to match the common order like shown here:
    // http://nfc-tools.org/index.php?title=ISO14443A
    let atqa: string = '-';
    // SAK in big endian. Print the first SAK byte only if it is not 0.
    let sak: string = '-';
    try {
      const nfca: tag.NfcATag = tag.getNfcA(tagInfo);
      const atqaBytes: number[] = nfca.getAtqa();
      if (atqaBytes !== null && atqaBytes !== undefined
        && atqaBytes.length >= 2) {
        atqa = HexUtils.bytes2Hex([atqaBytes[1], atqaBytes[0]]);
      }
      const sakValue: number = nfca.getSak();
      const sakFirstByte: number = (sakValue >> 8) & 0xFF;
      const sakSecondByte: number = sakValue & 0xFF;
      if (sakFirstByte !== 0) {
        sak = HexUtils.bytes2Hex([sakFirstByte, sakSecondByte]);
      } else {
        sak = HexUtils.bytes2Hex([sakSecondByte]);
      }
    } catch (e) {
      // Tag is not accessible via NFC-A. Keep "-".
    }
    this.atqaText = atqa;
    this.sakText = sak;

    // ATS.
    let ats: string = '-';
    try {
      const isoDep: tag.IsoDepTag = tag.getIsoDep(tagInfo);
      const atsBytes: number[] = isoDep.getHistoricalBytes();
      if (atsBytes !== null && atsBytes !== undefined && atsBytes.length > 0) {
        ats = HexUtils.bytes2Hex(atsBytes);
      }
    } catch (e) {
      // No ISO-DEP technology. Keep "-".
    }
    this.atsText = ats;

    // Identify tag type.
    const tagType: string = this.getTagIdentifier(atqa, sak, ats);
    if (tagType.length === 0 && this.mfcSupport > -2) {
      // Unknown, but MIFARE Classic.
      this.tagTypeText = TagInfoToolTagTypes.TAG_UNKNOWN_MF_CLASSIC;
      this.showTagTypeGuess = false;
    } else if (tagType.length === 0) {
      this.tagTypeText = TagInfoToolTagTypes.TAG_UNKNOWN;
      this.showTagTypeGuess = false;
    } else {
      this.tagTypeText = tagType;
      this.showTagTypeGuess = true;
    }

    // Check for MIFARE Classic support and display
    // the MIFARE Classic info (or the warning banner).
    if (this.mfcSupport === 0) {
      // Display MIFARE Classic info.
      this.showMifareInfo = true;
      this.bannerText = '';
      try {
        const mfc: tag.MifareClassicTag = tag.getMifareClassic(tagInfo);
        const size: number = mfc.getTagSize();
        // Block size is always 16 byte on MIFARE Classic tags.
        this.memSizeText = size.toString();
        this.sectorCountText = mfc.getSectorCount().toString();
        this.blockCountText = Math.floor(size / 16).toString();
      } catch (e) {
        this.memSizeText = '';
        this.sectorCountText = '';
        this.blockCountText = '';
      }
    } else if (this.mfcSupport === -1) {
      // No MIFARE Classic support (due to the device hardware).
      this.showMifareInfo = false;
      this.bannerText = '此设备不支持 MIFARE Classic！';
    } else {
      // The tag does not support MIFARE Classic.
      this.showMifareInfo = false;
      this.bannerText = '不是 MIFARE Classic 标签！';
    }
  }

  /**
   * Get (determine) the tag type from ATQA + SAK + ATS.
   * If no match is found check for the tag type only on ATQA + SAK
   * (and then on ATQA only).
   * Returns the tag type string or "" if no match was found.
   */
  private getTagIdentifier(atqa: string, sak: string, ats: string): string {
    const atsClean: string = ats.split('-').join('');

    // First check on ATQA + SAK + ATS.
    let tagType: string | undefined =
      TagInfoToolTagTypes.LOOKUP['tag_' + atqa + sak + atsClean];

    if (tagType === undefined) {
      // Check on ATQA + SAK.
      tagType = TagInfoToolTagTypes.LOOKUP['tag_' + atqa + sak];
    }

    if (tagType === undefined) {
      // Check on ATQA.
      tagType = TagInfoToolTagTypes.LOOKUP['tag_' + atqa];
    }

    if (tagType === undefined) {
      // No match found.
      return '';
    }
    return tagType;
  }

  // ---------------- Dialogs ----------------

  /**
   * Show a dialog with further information
   * (triggered by the "Read More" button of the warning banner).
   */
  private onReadMore(): void {
    let dialogTitle: string = '';
    let dialogMessage: string = '';
    if (this.mfcSupport === -1) {
      // Device does not support MIFARE Classic.
      dialogTitle = '不支持 MIFARE Classic';
      dialogMessage = '您的设备（受硬件限制）不支持 '
        + 'MIFARE Classic！目前只能显示 UID '
        + '及一些其他常规信息，无法进行进一步的 I/O 操作。'
        + '\n\n您可以在 GitHub 上查看已知不支持 '
        + 'MIFARE Classic 的设备列表。如果您的设备不在该列表中，'
        + '请给开发者发送电子邮件。\n\n如果您的设备 '
        + '支持 USB-OTG，您可以尝试将外部 NFC '
        + '读卡器连接到您的设备。MIFARE Classic Tool 可以 '
        + '与“External NFC”应用配合使用，该应用支持多种基于 USB '
        + '的 NFC 读卡器，但可能存在一些限制。';
    } else if (this.mfcSupport === -2) {
      // Tag does not support MIFARE Classic.
      dialogTitle = '不是 MIFARE Classic 标签';
      dialogMessage = '此标签与 MIFARE Classic '
        + '技术不兼容！请注意，本应用仅为 MIFARE Classic '
        + '标签设计！\n\n请使用其他标签。\n\n（注意：在极少数情况下，'
        + '此消息可能是由读卡区域内存在多个标签或异常的 '
        + 'ATQA+SAK 值导致的误报。）';
    }
    if (dialogMessage.length === 0) {
      // Error.
      return;
    }
    this.dialogCtrl = new CustomDialogController({
      builder: MctDialog({
        titleText: dialogTitle,
        messageText: dialogMessage,
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

  // ---------------- UI ----------------

  build() {
    NavDestination() {
      Column() {
        // Warning banner (device/tag does not support MIFARE Classic).
        if (this.bannerText.length > 0) {
          Row() {
            Image($r('app.media.warning'))
              .width(28)
              .height(28)
              .margin({ left: 8 })
            Text(this.bannerText)
              .fontSize(18)
              .fontColor(MctTheme.RED)
              .layoutWeight(1)
              .padding(5)
            Button('了解更多…')
              .fontSize(14)
              .height(36)
              .fontColor(MctTheme.fg)
              .backgroundColor(MctTheme.buttonBg)
              .borderRadius(4)
              .margin({ left: 4, right: 8 })
              .onClick(() => {
                this.onReadMore();
              })
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
          .padding(2)
          .margin(5)
          .borderRadius(5)
          .border({ width: 1, color: MctTheme.MIDDLE_GRAY })
        }

        Scroll() {
          Column() {
            if (this.hasTag) {
              // Generic info.
              Text('常规信息')
                .fontSize(22)
                .fontColor(MctTheme.accent)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding(5)
              Text() {
                Span('UID：')
                  .fontColor(MctTheme.accent)
                Span('\n' + this.uidText)
                Span('\n' + '射频技术：')
                  .fontColor(MctTheme.accent)
                Span('\n' + 'ISO/IEC 14443, Type A')
                Span('\n' + 'ATQA：')
                  .fontColor(MctTheme.accent)
                Span('\n' + this.atqaText)
                Span('\n' + 'SAK：')
                  .fontColor(MctTheme.accent)
                Span('\n' + this.sakText)
                Span('\n' + 'ATS：')
                  .fontColor(MctTheme.accent)
                Span('\n' + this.atsText)
                Span('\n' + '标签类型与制造商：')
                  .fontColor(MctTheme.accent)
                Span('\n' + this.tagTypeText)
              }
              .fontSize(18)
              .fontColor(MctTheme.fg)
              .width('100%')
              .textAlign(TextAlign.Start)
              .padding(5)

              // Message that the tag type might be wrong.
              if (this.showTagTypeGuess) {
                Text('（“标签类型与制造商”可能有误。\n'
                  + '详情请查看“帮助与信息”。）')
                  .fontSize(14)
                  .fontColor(MctTheme.fg)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .padding({ left: 5, right: 5, bottom: 5 })
              }

              // MIFARE Classic info.
              if (this.showMifareInfo) {
                Text('MIFARE Classic 信息')
                  .fontSize(22)
                  .fontColor(MctTheme.accent)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 10, bottom: 5, left: 5, right: 5 })
                Text() {
                  Span('存储大小：')
                    .fontColor(MctTheme.accent)
                  Span('\n' + this.memSizeText + ' 字节')
                  Span('\n' + '块大小：')
                    .fontColor(MctTheme.accent)
                  Span('\n' + '16 字节')
                  Span('\n' + '扇区数量：')
                    .fontColor(MctTheme.accent)
                  Span('\n' + this.sectorCountText)
                  Span('\n' + '块数量：')
                    .fontColor(MctTheme.accent)
                  Span('\n' + this.blockCountText)
                }
                .fontSize(18)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding(5)
              }
            } else {
              // There is no tag.
              Text('未检测到 MIFARE Classic 标签。')
                .fontSize(18)
                .fontColor(MctTheme.fg)
                .width('100%')
                .textAlign(TextAlign.Start)
                .padding(5)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('标签信息')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .onShown(() => {
      MctTheme.refresh();
      // (Re)register the tag listener. A newly discovered tag
      // replaces the displayed tag info (Android: onNewIntent).
      NfcService.setTagListener(
        (tagInfo: tag.TagInfo, supportResult: number): void => {
          this.updateTagInfo(tagInfo);
        });
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function TagInfoToolBuilder() {
  TagInfoToolPage()
}
