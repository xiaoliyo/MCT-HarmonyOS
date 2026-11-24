/**
 * Help and Info (port of de.syss.MifareClassicTool.Activities.HelpAndInfo,
 * GPL-3.0, Gerhard Klostermeier).
 *
 * In-app (offline) help and info. Displays the local help website
 * (resources/rawfile/help/help.html) in a web component
 * (Android: WebView with "file:///android_asset/help/help.html").
 */

import { webview } from '@kit.ArkWeb';
import { MctTheme } from '../common/ui/MctTheme';
import { NfcService } from '../common/NfcService';

@Component
struct HelpPage {
  private pathStack: NavPathStack = new NavPathStack();
  private webController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    MctTheme.refresh();
  }

  build() {
    NavDestination() {
      Column() {
        // Init. help from local website.
        Web({ src: 'resource://rawfile/help/help.html', controller: this.webController })
          .width('100%')
          .height('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(MctTheme.bg)
    }
    .title('帮助与信息')
    .backgroundColor(MctTheme.bg)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
    .onShown(() => {
      MctTheme.refresh();
    })
    .onHidden(() => {
      NfcService.setTagListener(null);
    })
  }
}

@Builder
export function HelpBuilder() {
  HelpPage()
}
