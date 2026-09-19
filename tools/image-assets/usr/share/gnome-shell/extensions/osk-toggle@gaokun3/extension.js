// osk-toggle@gaokun3: 快捷设置面板里的虚拟键盘开关
// 绑定 org.gnome.desktop.a11y.applications screen-keyboard-enabled,
// 与 系统设置 -> 无障碍 -> 屏幕键盘 双向同步; 开启时 GNOME 会在无实体
// 键盘(键盘已拆)且文本框获焦时自动弹出虚拟键盘。
import Gio from 'gi://Gio';
import GObject from 'gi://GObject';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {QuickToggle, SystemIndicator} from 'resource:///org/gnome/shell/ui/quickSettings.js';

const OSK_SCHEMA = 'org.gnome.desktop.a11y.applications';

const OskToggle = GObject.registerClass(
class OskToggle extends QuickToggle {
    _init() {
        super._init({
            title: '虚拟键盘',
            icon_name: 'input-keyboard-symbolic',
            toggleMode: true,
        });
        this._settings = new Gio.Settings({schema_id: OSK_SCHEMA});
        this._settings.bind('screen-keyboard-enabled', this, 'checked',
            Gio.SettingsBindFlags.DEFAULT);
    }
});

const Indicator = GObject.registerClass(
class Indicator extends SystemIndicator {
    _init() {
        super._init();
        this._toggle = new OskToggle();
        this.quickSettingsItems.push(this._toggle);
    }

    destroy() {
        this.quickSettingsItems.forEach(item => item.destroy());
        this.quickSettingsItems = [];
        super.destroy();
    }
});

export default class OskToggleExtension extends Extension {
    enable() {
        this._indicator = new Indicator();
        // 不加顶栏指示图标, 只在快捷设置网格里放一枚开关
        this._indicator._indicator.visible = false;
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
