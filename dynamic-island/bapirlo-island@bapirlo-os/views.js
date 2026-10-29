// Bapirlo Island — what the pill shows. Each builder returns a spec for Island.push():
// {kind, key, width, height, timeout, build() -> actor, update?(spec), onClick?, onDismiss?}
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Pango from 'gi://Pango';
import St from 'gi://St';

const scale = () => St.ThemeContext.get_for_stage(global.stage).scale_factor;

function label(text, style_class, opts = {}) {
    const l = new St.Label({text: text ?? '', style_class, y_align: Clutter.ActorAlign.CENTER, ...opts});
    l.clutter_text.ellipsize = Pango.EllipsizeMode.END;
    return l;
}

function cssUrl(path) {
    return `url("file://${path.replace(/"/g, '\\"')}")`;
}

// ---------- volume / brightness / generic OSD ----------
export function levelView(params) {
    const {icon, label: text, level, maxLevel} = params;
    const s = scale();
    let fill, pct, iconActor, track;
    const TRACK = 190;
    const apply = (spec) => {
        if (spec.icon)
            iconActor.gicon = spec.icon;
        if (spec.level === null || spec.level === undefined) {
            track.hide();
            pct.text = spec.label ?? '';
            return;
        }
        const max = spec.maxLevel > 0 ? spec.maxLevel : 1;
        const frac = Math.max(0, Math.min(1, spec.level / max));
        track.show();
        fill.ease({width: Math.round(TRACK * s * frac), duration: 120, mode: Clutter.AnimationMode.EASE_OUT_QUAD});
        // >100 % (over-amplified volume) shows in ember
        fill.style_class = spec.level > 1 ? 'island-fill over' : 'island-fill';
        pct.text = `${Math.round(spec.level * 100)}`;
    };
    const textOnly = level === null || level === undefined;
    return {
        kind: 'level', key: 'level', params,
        width: Math.round((textOnly ? 300 : 340) * s), height: Math.round(44 * s), timeout: 1600,
        build() {
            const box = new St.BoxLayout({style_class: 'island-row island-level'});
            iconActor = new St.Icon({gicon: icon, style_class: 'island-level-icon'});
            // fixed layout: the fill sits at x = 0 and only its width animates
            track = new St.Widget({style_class: 'island-track', y_align: Clutter.ActorAlign.CENTER,
                width: TRACK * s});
            fill = new St.Widget({style_class: 'island-fill', width: 0});
            track.add_child(fill);
            pct = label('', 'island-pct', {x_expand: textOnly});
            box.add_child(iconActor);
            box.add_child(track);
            box.add_child(pct);
            apply({icon, label: text, level, maxLevel});
            return box;
        },
        update(spec) {
            apply(spec.params);
        },
    };
}

// ---------- notification ----------
export function notificationView(n, {onClick, onDismiss}) {
    const s = scale();
    const hasBody = !!n.body;
    const actions = (n.actions ?? []).slice(0, 2);
    const h = (hasBody ? 84 : 62) + (actions.length ? 40 : 0);
    return {
        kind: 'notification', key: `n-${n.source?.title}-${n.title}`,
        width: Math.round(460 * s), height: Math.round(h * s), timeout: 5000, fit: true,
        onClick, onDismiss,
        build() {
            const outer = new St.BoxLayout({style_class: 'island-notif', orientation: Clutter.Orientation.VERTICAL});
            const row = new St.BoxLayout({style_class: 'island-row', x_expand: true});
            const gicon = n.gicon ?? n.source?.icon ?? new Gio.ThemedIcon({name: 'dialog-information-symbolic'});
            row.add_child(new St.Icon({gicon, style_class: 'island-app-icon', y_align: Clutter.ActorAlign.CENTER}));
            const text = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true,
                y_align: Clutter.ActorAlign.CENTER, style_class: 'island-text'});
            const head = new St.BoxLayout({x_expand: true});
            head.add_child(label(n.title || n.source?.title || '', 'island-title', {x_expand: true}));
            head.add_child(label(n.source?.title ?? '', 'island-source'));
            text.add_child(head);
            if (hasBody) {
                const body = label(n.body.replace(/\s+/g, ' ').trim(), 'island-body');
                body.clutter_text.line_wrap = true;
                body.clutter_text.line_wrap_mode = Pango.WrapMode.WORD_CHAR;
                body.clutter_text.ellipsize = Pango.EllipsizeMode.END;
                body.clutter_text.set_lines?.(2);
                text.add_child(body);
            }
            row.add_child(text);
            outer.add_child(row);
            if (actions.length) {
                const bar = new St.BoxLayout({style_class: 'island-actions', x_expand: true});
                for (const [i, a] of actions.entries()) {
                    // the first action is the one the app wants you to take: filled crimson
                    const b = new St.Button({label: a.label, style_class: i === 0 ? 'island-action primary' : 'island-action',
                        x_expand: true, can_focus: true});
                    b.connect('clicked', () => {
                        a.activate();
                        // the island closes from its own release handler
                    });
                    bar.add_child(b);
                }
                outer.add_child(bar);
            }
            return outer;
        },
    };
}

// ---------- now playing ----------
export function mediaView(player, artPath, {onClick}) {
    const s = scale();
    let playBtn;
    const syncIcon = () => {
        if (playBtn)
            playBtn.child.icon_name = player.playing ? 'media-playback-pause-symbolic' : 'media-playback-start-symbolic';
    };
    return {
        kind: 'media', key: 'media',
        width: Math.round(440 * s), height: Math.round(76 * s), timeout: 4500,
        onClick,
        build() {
            const row = new St.BoxLayout({style_class: 'island-row island-media'});
            const art = new St.Widget({style_class: 'island-art', y_align: Clutter.ActorAlign.CENTER});
            if (artPath)
                art.style = `background-image: ${cssUrl(artPath)};`;
            else
                art.add_style_class_name('empty');
            row.add_child(art);
            const text = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true,
                y_align: Clutter.ActorAlign.CENTER, style_class: 'island-text'});
            text.add_child(label(player.title || 'Unknown track', 'island-title'));
            text.add_child(label(player.artists?.join(', ') || player.identity, 'island-body'));
            row.add_child(text);
            playBtn = new St.Button({style_class: 'island-ctl', child: new St.Icon({icon_name: 'media-playback-pause-symbolic'}),
                y_align: Clutter.ActorAlign.CENTER});
            playBtn.connect('clicked', () => {
                player.playPause();
                return Clutter.EVENT_STOP;
            });
            const next = new St.Button({style_class: 'island-ctl', child: new St.Icon({icon_name: 'media-skip-forward-symbolic'}),
                y_align: Clutter.ActorAlign.CENTER});
            next.connect('clicked', () => player.next());
            playBtn._islandKeepOpen = next._islandKeepOpen = true;
            row.add_child(playBtn);
            row.add_child(next);
            syncIcon();
            return row;
        },
        update() {
            syncIcon();
        },
    };
}

// ---------- power ----------
export function powerView({title, percent, icon, tone}) {
    const s = scale();
    return {
        kind: 'power', key: 'power',
        width: Math.round(320 * s), height: Math.round(44 * s), timeout: 3000,
        build() {
            const row = new St.BoxLayout({style_class: `island-row island-power ${tone ?? ''}`});
            row.add_child(new St.Icon({icon_name: icon, style_class: 'island-level-icon'}));
            row.add_child(label(title, 'island-title', {x_expand: true}));
            row.add_child(label(`${Math.round(percent)}%`, 'island-pct'));
            return row;
        },
    };
}

// ---------- screenshot ----------
export function screenshotView(file, {onClick}) {
    const s = scale();
    return {
        kind: 'screenshot', key: `shot-${file.get_path()}`,
        width: Math.round(420 * s), height: Math.round(88 * s), timeout: 4500,
        onClick,
        build() {
            const row = new St.BoxLayout({style_class: 'island-row island-shot'});
            const thumb = new St.Widget({style_class: 'island-thumb', y_align: Clutter.ActorAlign.CENTER,
                style: `background-image: ${cssUrl(file.get_path())};`});
            row.add_child(thumb);
            const text = new St.BoxLayout({orientation: Clutter.Orientation.VERTICAL, x_expand: true,
                y_align: Clutter.ActorAlign.CENTER, style_class: 'island-text'});
            text.add_child(label('Screenshot saved', 'island-title'));
            text.add_child(label(GLib.path_get_basename(file.get_path()), 'island-body'));
            row.add_child(text);
            row.add_child(new St.Icon({icon_name: 'camera-photo-symbolic', style_class: 'island-level-icon dim',
                y_align: Clutter.ActorAlign.CENTER}));
            return row;
        },
    };
}
