/**
 * Application-wide context holder.
 * Set once from the EntryAbility, used by file/preferences/NFC helpers.
 */

import { common } from '@kit.AbilityKit';

export class MctApp {
  private static appContext: common.UIAbilityContext | null = null;

  static setContext(context: common.UIAbilityContext): void {
    MctApp.appContext = context;
  }

  static getContext(): common.UIAbilityContext {
    if (MctApp.appContext === null) {
      throw new Error('MctApp context is not initialized.');
    }
    return MctApp.appContext;
  }
}
