/**
 * App theme (dark/light/follow system) and the MCT color palette
 * (res/values/colors.xml of de.syss.MifareClassicTool, GPL-3.0).
 */

import { ConfigurationConstant } from '@kit.AbilityKit';
import { MctApp } from '../MctApp';
import { PrefKey } from '../MctTypes';
import { Prefs } from '../Prefs';

export class MctTheme {
  // ---- MCT color palette (colors.xml) ----
  static readonly LIGHT_GREEN: string = '#66FF66';
  static readonly DARK_GREEN: string = '#338800';
  static readonly ORANGE: string = '#FF6600';
  static readonly PURPLE: string = '#9933FF';
  static readonly YELLOW: string = '#CCCC00';
  static readonly RED: string = '#FF0000';
  static readonly LIGHT_GRAY: string = '#DDDDDD';
  static readonly MIDDLE_GRAY: string = '#444444';
  static readonly DARK_GRAY: string = '#222222';
  static readonly WHITE: string = '#FFFFFF';
  static readonly GRAY: string = '#888888';

  // ---- Current theme colors (updated by refresh()) ----
  static bg: string = '#303030';
  static fg: string = '#FFFFFF';
  static fgSecondary: string = '#AAAAAA';
  static buttonBg: string = '#424242';
  static buttonBorder: string = '#6E6E6E';
  static inputBg: string = '#3A3A3A';
  static accent: string = '#4DB6AC';

  /** Refresh the theme colors from the app theme preference. */
  static refresh(): void {
    let light: boolean = false;
    const themeId: number = Prefs.getInt(PrefKey.CustomAppTheme, 2);
    if (themeId === 0) {
      light = false;
    } else if (themeId === 1) {
      light = true;
    } else {
      // Follow the system theme.
      try {
        const config = MctApp.getContext().config;
        if (config !== undefined && config !== null) {
          light = config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
        }
      } catch (e) {
        light = false;
      }
    }
    if (light) {
      MctTheme.bg = '#FAFAFA';
      MctTheme.fg = '#222222';
      MctTheme.fgSecondary = '#666666';
      MctTheme.buttonBg = '#E3E3E3';
      MctTheme.buttonBorder = '#BDBDBD';
      MctTheme.inputBg = '#F1F1F1';
      MctTheme.accent = '#00796B';
    } else {
      MctTheme.bg = '#303030';
      MctTheme.fg = '#FFFFFF';
      MctTheme.fgSecondary = '#AAAAAA';
      MctTheme.buttonBg = '#5A595E';
      MctTheme.buttonBorder = '#6E6E6E';
      MctTheme.inputBg = '#3A3A3A';
      MctTheme.accent = '#4DB6AC';
    }
  }
}
