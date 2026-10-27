// Bộ icon nét 24×24 (phong cách Lucide) dùng cho giao diện Kinnect mới.
// Vẽ sẵn tại chỗ vì CSP chỉ cho phép script cùng nguồn.
window.KN_ICONS = {
  "message-square-plus": '<path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/><path d="M12 7v6M9 10h6"/>',
  "camera-off": '<path d="M2 2l20 20M7 7H4a2 2 0 00-2 2v9a2 2 0 002 2h16M9.5 4h5L17 7h3a2 2 0 012 2v7.5M14.12 15.12A3 3 0 119.88 10.88"/>',
  "rotate-ccw": '<path d="M3 12a9 9 0 109-9 9.75 9.75 0 00-6.74 2.74L3 8"/><path d="M3 3v5h5"/>',
  "bell": '<path d="M6 8a6 6 0 0112 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 003.4 0"/>',
  "users-round": '<path d="M18 21a8 8 0 00-16 0"/><circle cx="10" cy="8" r="5"/><path d="M22 20c0-3.37-2-6.5-4-8a5 5 0 00-.45-8.3"/>',
  "message-square": '<path d="M21 15a2 2 0 01-2 2H7l-4 4V5a2 2 0 012-2h14a2 2 0 012 2z"/>',
  "message-circle": '<path d="M7.9 20A9 9 0 104 16.1L2 22z"/>',
  "house": '<path d="M15 21v-8a1 1 0 00-1-1h-4a1 1 0 00-1 1v8"/><path d="M3 10a2 2 0 01.7-1.5l7-6a2 2 0 012.6 0l7 6A2 2 0 0121 10v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>',
  "compass": '<circle cx="12" cy="12" r="10"/><path d="M16.2 7.8l-2 6.4-6.4 2 2-6.4z"/>',
  "plus": '<path d="M5 12h14M12 5v14"/>',
  "clapperboard": '<path d="M20.2 6L3 11l-.9-2.4c-.3-1.1.3-2.2 1.3-2.5l13.5-4c1.1-.3 2.2.3 2.5 1.3z"/><path d="M6.2 5.3l3.1 3.9M12.4 3.4l3.1 4M3 11h18v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>',
  "radio": '<path d="M4.9 19.1C1 15.2 1 8.8 4.9 4.9M7.8 16.2c-2.3-2.3-2.3-6.1 0-8.5"/><circle cx="12" cy="12" r="2"/><path d="M16.2 7.8c2.3 2.3 2.3 6.1 0 8.5M19.1 4.9C23 8.8 23 15.1 19.1 19"/>',
  "settings": '<path d="M12.22 2h-.44a2 2 0 00-2 2v.18a2 2 0 01-1 1.73l-.43.25a2 2 0 01-2 0l-.15-.08a2 2 0 00-2.73.73l-.22.38a2 2 0 00.73 2.73l.15.1a2 2 0 011 1.72v.51a2 2 0 01-1 1.74l-.15.09a2 2 0 00-.73 2.73l.22.38a2 2 0 002.73.73l.15-.08a2 2 0 012 0l.43.25a2 2 0 011 1.73V20a2 2 0 002 2h.44a2 2 0 002-2v-.18a2 2 0 011-1.73l.43-.25a2 2 0 012 0l.15.08a2 2 0 002.73-.73l.22-.39a2 2 0 00-.73-2.73l-.15-.08a2 2 0 01-1-1.74v-.5a2 2 0 011-1.74l.15-.09a2 2 0 00.73-2.73l-.22-.38a2 2 0 00-2.73-.73l-.15.08a2 2 0 01-2 0l-.43-.25a2 2 0 01-1-1.73V4a2 2 0 00-2-2z"/><circle cx="12" cy="12" r="3"/>',
  "user-round": '<circle cx="12" cy="8" r="5"/><path d="M20 21a8 8 0 00-16 0"/>',
  "user-plus": '<path d="M16 21v-2a4 4 0 00-4-4H6a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6M22 11h-6"/>',
  "user-check": '<path d="M16 21v-2a4 4 0 00-4-4H6a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M16 11l2 2 4-4"/>',
  "shield-check": '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 01-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 011-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 011.52 0C14.51 3.81 17 5 19 5a1 1 0 011 1z"/><path d="M9 12l2 2 4-4"/>',
  "chevron-right": '<path d="M9 18l6-6-6-6"/>',
  "chevron-down": '<path d="M6 9l6 6 6-6"/>',
  "key-round": '<path d="M2.6 18.4A2 2 0 002 19.8V21a1 1 0 001 1h3a1 1 0 001-1v-1a1 1 0 011-1h1a1 1 0 001-1v-1a1 1 0 011-1h.2a2 2 0 001.4-.6l.8-.8a6.5 6.5 0 10-4-4z"/><circle cx="16.5" cy="7.5" r=".5"/>',
  "log-out": '<path d="M9 21H5a2 2 0 01-2-2V5a2 2 0 012-2h4M16 17l5-5-5-5M21 12H9"/>',
  "log-in": '<path d="M15 3h4a2 2 0 012 2v14a2 2 0 01-2 2h-4M10 17l5-5-5-5M15 12H3"/>',
  "moon": '<path d="M12 3a6 6 0 009 9 9 9 0 11-9-9z"/>',
  "circle-help": '<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 015.83 1c0 2-3 3-3 3M12 17h.01"/>',
  "heart": '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0016.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 002 8.5c0 2.3 1.5 4.05 3 5.5l7 7z"/>',
  "send": '<path d="M14.5 21.7a.5.5 0 00.9 0L22 2.7a.5.5 0 00-.6-.6L2.3 8.6a.5.5 0 000 .9l7.9 3.2a2 2 0 011.1 1.1z"/><path d="M21.9 2.1L10.9 13.1"/>',
  "ellipsis": '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
  "image": '<rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="M21 15l-3.1-3.1a2 2 0 00-2.8 0L6 21"/>',
  "image-plus": '<path d="M16 5h6M19 2v6M21 11.5V19a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h7.5"/><path d="M21 15l-3.1-3.1a2 2 0 00-2.8 0L6 21"/><circle cx="9" cy="9" r="2"/>',
  "video": '<path d="M16 13l5.2 3.5a.5.5 0 00.8-.4V7.9a.5.5 0 00-.8-.4L16 11"/><rect x="2" y="6" width="14" height="12" rx="2"/>',
  "arrow-left": '<path d="M12 19l-7-7 7-7M19 12H5"/>',
  "arrow-right": '<path d="M5 12h14M12 5l7 7-7 7"/>',
  "arrow-up-right": '<path d="M7 7h10v10M7 17L17 7"/>',
  "x": '<path d="M18 6L6 18M6 6l12 12"/>',
  "pencil": '<path d="M21.2 6.8a1 1 0 00-4-4L3.8 16.2a2 2 0 00-.5.8l-1.3 4.4a.5.5 0 00.6.6l4.4-1.3a2 2 0 00.8-.5z"/><path d="M15 5l4 4"/>',
  "pen-line": '<path d="M12 20h9"/><path d="M16.4 3.6a2.1 2.1 0 013 3L7 19l-4 1 1-4z"/>',
  "lock-keyhole": '<circle cx="12" cy="16" r="1"/><rect x="3" y="10" width="18" height="12" rx="2"/><path d="M7 10V7a5 5 0 0110 0v3"/>',
  "calendar-days": '<path d="M8 2v4M16 2v4"/><rect width="18" height="18" x="3" y="4" rx="2"/><path d="M3 10h18"/>',
  "globe": '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 000 20 14.5 14.5 0 000-20M2 12h20"/>',
  "list-plus": '<path d="M11 12H3M16 6H3M16 18H3M18 9v6M21 12h-6"/>',
  "play": '<path d="M6 3l14 9-14 9z"/>',
  "eye": '<path d="M2.06 12.35a1 1 0 010-.7 10.75 10.75 0 0119.88 0 1 1 0 010 .7 10.75 10.75 0 01-19.88 0"/><circle cx="12" cy="12" r="3"/>',
  "eye-off": '<path d="M10.73 5.08A10.43 10.43 0 0112 5c7 0 10 7 10 7a13.16 13.16 0 01-1.67 2.68M6.61 6.61A13.53 13.53 0 002 12s3 7 10 7a9.74 9.74 0 005.39-1.61M2 2l20 20M9.88 9.88a3 3 0 104.24 4.24"/>',
  "at-sign": '<circle cx="12" cy="12" r="4"/><path d="M16 8v5a3 3 0 006 0v-1a10 10 0 10-4 8"/>',
  "mail": '<rect width="20" height="16" x="2" y="4" rx="2"/><path d="M22 7l-8.97 5.7a1.94 1.94 0 01-2.06 0L2 7"/>',
  "check": '<path d="M20 6L9 17l-5-5"/>',
  "circle-check": '<circle cx="12" cy="12" r="10"/><path d="M9 12l2 2 4-4"/>',
  "newspaper": '<path d="M4 22h16a2 2 0 002-2V4a2 2 0 00-2-2H8a2 2 0 00-2 2v16a2 2 0 01-2 2zm0 0a2 2 0 01-2-2v-9c0-1.1.9-2 2-2h2"/><path d="M18 14h-8M15 18h-5M10 6h8v4h-8z"/>',
  "map-pin": '<path d="M20 10c0 5-5.5 10.2-7.4 11.8a1 1 0 01-1.2 0C9.5 20.2 4 15 4 10a8 8 0 0116 0"/><circle cx="12" cy="10" r="3"/>',
  "search": '<circle cx="11" cy="11" r="8"/><path d="M21 21l-4.3-4.3"/>',
  "trash-2": '<path d="M3 6h18M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2M10 11v6M14 11v6"/>',
  "send-horizontal": '<path d="M3.7 3.1a.5.5 0 00-.7.6l2.6 7.6a1 1 0 010 .6L3 19.5a.5.5 0 00.7.6l18-8a.5.5 0 000-.9z"/><path d="M6 12h16"/>',
  "key": '<path d="M2.6 18.4A2 2 0 002 19.8V21a1 1 0 001 1h3a1 1 0 001-1v-1a1 1 0 011-1h1a1 1 0 001-1v-1a1 1 0 011-1h.2a2 2 0 001.4-.6l.8-.8a6.5 6.5 0 10-4-4z"/>',
  "sparkles": '<path d="M9.94 15.5A2 2 0 008.5 14.06l-6.13-1.58a.5.5 0 010-.96L8.5 9.94A2 2 0 009.94 8.5l1.58-6.13a.5.5 0 01.96 0L14.06 8.5A2 2 0 0015.5 9.94l6.13 1.58a.5.5 0 010 .96L15.5 14.06a2 2 0 00-1.44 1.44l-1.58 6.13a.5.5 0 01-.96 0z"/>',
  "hammer": '<path d="M15 12l-8.4 8.4a2.1 2.1 0 01-3-3L12 9M17.6 15L22 10.6M20.9 11.7l-1.3-1.3c-.6-.6-.9-1.4-.9-2.2v-.9l-2.3-2.3a5.5 5.5 0 00-3.9-1.6H9l.9.8A6.2 6.2 0 0112 8.4V10l2 2h2.5c.5 0 1 .2 1.4.6l1.3 1.3"/>',
  "camera": '<path d="M14.5 4h-5L7 7H4a2 2 0 00-2 2v9a2 2 0 002 2h16a2 2 0 002-2V9a2 2 0 00-2-2h-3z"/><circle cx="12" cy="13" r="3"/>',
  "refresh-cw": '<path d="M3 12a9 9 0 019-9 9.75 9.75 0 016.74 2.74L21 8M21 3v5h-5M21 12a9 9 0 01-9 9 9.75 9.75 0 01-6.74-2.74L3 16M8 16H3v5"/>'
};
Object.assign(window.KN_ICONS, {
  'phone':'<path d="M22 16.9v3a2 2 0 0 1-2.2 2A19.8 19.8 0 0 1 3.1 5.2 2 2 0 0 1 5.1 3h3a2 2 0 0 1 2 1.7l.5 2.6a2 2 0 0 1-.6 1.7L8.7 10.3a16 16 0 0 0 5 5l1.3-1.3a2 2 0 0 1 1.7-.6l2.6.5a2 2 0 0 1 1.7 2Z"/>',
  'phone-off':'<path d="m3 3 18 18M9 3H5a2 2 0 0 0-2 2c0 10 6 16 16 16a2 2 0 0 0 2-2v-4l-5-2-2 2M9 9l2-2-2-4"/>',
  'mic':'<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8"/>',
  'switch-camera':'<path d="m5 7 2-3h10l2 3h2v13H3V7h2M9 11l-2 2 2 2m6-4 2 2-2 2M7 13h10"/>',
  'sliders-horizontal':'<path d="M3 6h4m4 0h10M3 12h10m4 0h4M3 18h4m4 0h10M7 3v6m10 0v6M7 15v6"/>',
  'timer':'<circle cx="12" cy="14" r="8"/><path d="M10 2h4m-2 8v4m6-8 2-2"/>',
  'wand-sparkles':'<path d="m3 21 14-14 4 4L7 25M15 3v4m-2-2h4M4 7v4m-2-2h4M19 16v4m-2-2h4"/>',
  'chevron-up':'<path d="m6 15 6-6 6 6"/>',
  'chevron-down':'<path d="m6 9 6 6 6-6"/>',
  'locate-fixed':'<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>',
  'map-pin-off':'<path d="m3 3 18 18M9 9a4 4 0 0 0 6 6M7 4a9 9 0 0 1 12 12M5 6C0 12 12 22 12 22s2-2 4-5"/>',
  'rotate-ccw':'<path d="M3 10a9 9 0 1 1 2 8M3 3v7h7"/>',
  'paperclip':'<path d="m21 11-9 9a6 6 0 0 1-8-8L15 2a4 4 0 0 1 6 6L10 18a2 2 0 0 1-3-3l10-9"/>'
});

Object.assign(window.KN_ICONS,{'smile':'<circle cx="12" cy="12" r="9"/><path d="M8 14s1 3 4 3 4-3 4-3M8 9h.01M16 9h.01"/>','music-2':'<path d="M9 18V5l12-3v13M9 9l12-3"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="15" r="3"/>','square':'<rect x="4" y="4" width="16" height="16" rx="3"/>','chevron-left':'<path d="m15 18-6-6 6-6"/>'});

Object.assign(window.KN_ICONS,{'pin':'<path d="m16 3 5 5-4 1-4 4v4l-2 2-6-6 2-2h4l4-4 1-4ZM2 22l6-6"/>','bell-off':'<path d="m3 3 18 18M9 5a6 6 0 0 1 9 5v4l3 3H7M5 9v5l-2 3m7 3h4"/>','monitor':'<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M12 17v4m-4 0h8"/>','volume-2':'<path d="M11 5 6 9H3v6h3l5 4V5ZM15 8a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>','copy':'<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>'});
Object.assign(window.KN_ICONS,{'maximize':'<path d="M8 3H3v5m13-5h5v5M3 16v5h5m13-5v5h-5"/>'});
Object.assign(window.KN_ICONS,{download:'<path d="M12 3v12m-5-5 5 5 5-5M4 16v4a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-4"/>'});

window.KN_ICONS["forward"] = '<path d="m15 17 5-5-5-5"/><path d="M4 18v-2a4 4 0 0 1 4-4h12"/>';

Object.assign(window.KN_ICONS,{
"users":window.KN_ICONS["users-round"],
"bookmark":'<path d="M6 3h12v18l-6-4-6 4z"/>',
"headphones":'<path d="M3 14v-3a9 9 0 0118 0v3M3 13h4v8H3zM17 13h4v8h-4z"/>',
"undo-2":'<path d="M3 7h10a7 7 0 010 14M3 7l5-5M3 7l5 5"/>'
});
