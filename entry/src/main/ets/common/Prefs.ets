/**
 * Preferences wrapper (SharedPreferences equivalent).
 */

import { preferences } from '@kit.ArkData';
import { PrefKey } from './MctTypes';

export class Prefs {
  private static store: preferences.Preferences | null = null;

  static async init(context: Context): Promise<void> {
    if (Prefs.store === null) {
      Prefs.store = await preferences.getPreferences(context, 'mct_prefs');
    }
  }

  static getBool(key: PrefKey | string, def: boolean): boolean {
    if (Prefs.store === null) {
      return def;
    }
    const v = Prefs.store.getSync(key, def);
    return typeof v === 'boolean' ? v : def;
  }

  static getInt(key: PrefKey | string, def: number): number {
    if (Prefs.store === null) {
      return def;
    }
    const v = Prefs.store.getSync(key, def);
    return typeof v === 'number' ? v : def;
  }

  static getString(key: PrefKey | string, def: string): string {
    if (Prefs.store === null) {
      return def;
    }
    const v = Prefs.store.getSync(key, def);
    return typeof v === 'string' ? v : def;
  }

  static putBool(key: PrefKey | string, value: boolean): void {
    if (Prefs.store !== null) {
      Prefs.store.putSync(key, value);
      Prefs.store.flush();
    }
  }

  static putInt(key: PrefKey | string, value: number): void {
    if (Prefs.store !== null) {
      Prefs.store.putSync(key, value);
      Prefs.store.flush();
    }
  }

  static putString(key: PrefKey | string, value: string): void {
    if (Prefs.store !== null) {
      Prefs.store.putSync(key, value);
      Prefs.store.flush();
    }
  }
}
