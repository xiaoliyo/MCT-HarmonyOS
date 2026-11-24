/**
 * Reusable dialogs (Android AlertDialog equivalents used by all pages).
 * Ported from de.syss.MifareClassicTool (GPL-3.0, Gerhard Klostermeier).
 *
 * MctDialog: title + message + optional checkbox + up to 3 buttons.
 *   button1 = positive, button2 = negative, button3 = neutral.
 *   All buttons close the dialog and then invoke their action with the
 *   current checkbox state. Additionally, dismissAction is invoked from
 *   aboutToDisappear (on ANY close: button, back press, mask) with the
 *   final checkbox state.
 *
 * MctInputDialog: title + message + text input + cancel/confirm buttons.
 */

import { MctTheme } from './MctTheme';

@CustomDialog
export struct MctDialog {
  controller?: CustomDialogController;
  titleText: string = '';
  messageText: string = '';
  showCheckbox: boolean = false;
  checkboxText: string = '';
  button1Text: string = '';
  button2Text: string = '';
  button3Text: string = '';
  @State checkboxChecked: boolean = false;
  button1Action: (checked: boolean) => void = (checked: boolean): void => {};
  button2Action: (checked: boolean) => void = (checked: boolean): void => {};
  button3Action: (checked: boolean) => void = (checked: boolean): void => {};
  dismissAction: (checked: boolean) => void = (checked: boolean): void => {};

  aboutToDisappear(): void {
    this.dismissAction(this.checkboxChecked);
  }

  build() {
    Column() {
      Text(this.titleText)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.messageText.length > 0) {
        Text(this.messageText)
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 14 })
          .lineHeight(23)
      }
      if (this.showCheckbox) {
        Row() {
          Checkbox()
            .select(this.checkboxChecked)
            .selectedColor(MctTheme.accent)
            .width(20)
            .height(20)
            .onChange((value: boolean): void => {
              this.checkboxChecked = value;
            })
          Text(this.checkboxText)
            .fontSize(14)
            .fontColor(MctTheme.fg)
            .margin({ left: 8 })
            .onClick(() => {
              this.checkboxChecked = !this.checkboxChecked;
            })
        }
        .width('100%')
        .margin({ top: 12 })
        .alignItems(VerticalAlign.Center)
      }
      Divider()
        .color(MctTheme.buttonBorder)
        .margin({ top: 16 })
      Row() {
        if (this.button3Text.length > 0) {
          Text(this.button3Text)
            .fontSize(16)
            .fontColor(MctTheme.accent)
            .maxLines(2)
            .padding({ top: 10, bottom: 10, left: 12, right: 12 })
            .onClick(() => {
              this.controller?.close();
              this.button3Action(this.checkboxChecked);
            })
        }
        if (this.button2Text.length > 0) {
          Text(this.button2Text)
            .fontSize(16)
            .fontColor(MctTheme.accent)
            .maxLines(2)
            .padding({ top: 10, bottom: 10, left: 12, right: 12 })
            .onClick(() => {
              this.controller?.close();
              this.button2Action(this.checkboxChecked);
            })
        }
        if (this.button1Text.length > 0) {
          Text(this.button1Text)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(MctTheme.accent)
            .maxLines(2)
            .padding({ top: 10, bottom: 10, left: 12, right: 12 })
            .onClick(() => {
              this.controller?.close();
              this.button1Action(this.checkboxChecked);
            })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 6 })
    }
    .padding(22)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('88%')
  }
}

@CustomDialog
export struct MctInputDialog {
  controller?: CustomDialogController;
  titleText: string = '';
  messageText: string = '';
  inputInitial: string = '';
  inputPlaceholder: string = '';
  cancelButtonText: string = 'Cancel';
  confirmButtonText: string = 'OK';
  onConfirm: (text: string) => void = (text: string): void => {};
  @State inputText: string = '';

  aboutToAppear(): void {
    this.inputText = this.inputInitial;
  }

  build() {
    Column() {
      Text(this.titleText)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(MctTheme.fg)
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.messageText.length > 0) {
        Text(this.messageText)
          .fontSize(16)
          .fontColor(MctTheme.fg)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 14 })
          .lineHeight(23)
      }
      TextInput({ text: this.inputText, placeholder: this.inputPlaceholder })
        .onChange((value: string): void => {
          this.inputText = value;
        })
        .fontSize(16)
        .fontColor(MctTheme.fg)
        .placeholderColor(MctTheme.fgSecondary)
        .placeholderFont({ size: 16 })
        .backgroundColor(MctTheme.inputBg)
        .borderRadius(4)
        .width('100%')
        .margin({ top: 14 })
      Divider()
        .color(MctTheme.buttonBorder)
        .margin({ top: 16 })
      Row() {
        if (this.cancelButtonText.length > 0) {
          Text(this.cancelButtonText)
            .fontSize(16)
            .fontColor(MctTheme.fgSecondary)
            .padding({ top: 10, bottom: 10, left: 12, right: 12 })
            .onClick(() => {
              this.controller?.close();
            })
        }
        Text(this.confirmButtonText)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(MctTheme.accent)
          .padding({ top: 10, bottom: 10, left: 12, right: 12 })
          .onClick(() => {
            const text: string = this.inputText;
            this.controller?.close();
            this.onConfirm(text);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .alignItems(VerticalAlign.Center)
      .margin({ top: 6 })
    }
    .padding(22)
    .backgroundColor(MctTheme.bg)
    .borderRadius(16)
    .width('88%')
  }
}
