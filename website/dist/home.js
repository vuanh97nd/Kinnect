document.getElementById('kinnect-boot')?.remove();

// 1. Theme Switcher (persists user choice while respecting system default)
(function initTheme() {
  const root = document.documentElement;
  const toggle = document.getElementById('theme-toggle');
  try {
    const saved = localStorage.getItem('kinnect-theme');
    if (saved === 'light' || saved === 'dark') {
      root.setAttribute('data-theme', saved);
    }
  } catch {}

  if (toggle) {
    toggle.addEventListener('click', () => {
      const current = root.getAttribute('data-theme');
      const systemDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
      const isDarkNow = current ? current === 'dark' : systemDark;
      const next = isDarkNow ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try {
        localStorage.setItem('kinnect-theme', next);
      } catch {}
    });
  }
})();

// 2. Sticky Header Elevation
(function initHeaderScroll() {
  const header = document.querySelector('.site-header');
  if (!header) return;
  const update = () => {
    header.classList.toggle('is-scrolled', window.scrollY > 12);
  };
  update();
  window.addEventListener('scroll', update, { passive: true });
})();

// 3. Mobile Navigation Drawer
(function initMobileMenu() {
  const menuBtn = document.querySelector('.home-menu-btn');
  const homeMenu = document.getElementById('home-menu');
  if (!menuBtn || !homeMenu) return;

  function closeHomeMenu() {
    homeMenu.classList.remove('open');
    menuBtn.setAttribute('aria-expanded', 'false');
    menuBtn.setAttribute('aria-label', 'Mở menu');
  }

  menuBtn.addEventListener('click', () => {
    const open = homeMenu.classList.toggle('open');
    menuBtn.setAttribute('aria-expanded', String(open));
    menuBtn.setAttribute('aria-label', open ? 'Đóng menu' : 'Mở menu');
  });

  homeMenu.addEventListener('click', (e) => {
    if (e.target.closest('a')) closeHomeMenu();
  });

  document.addEventListener('click', (e) => {
    if (!e.target.closest('header')) closeHomeMenu();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && menuBtn.getAttribute('aria-expanded') === 'true') {
      closeHomeMenu();
      menuBtn.focus();
    }
  });
})();

// 4. Interactive Hero App Screen Switcher (Accessible Tabs + Gentle Auto-Preview)
(function initDeviceShowcase() {
  const tabs = Array.from(document.querySelectorAll('.stage-tab[data-screen]'));
  const screens = Array.from(document.querySelectorAll('.device-screen[id^="panel-"]'));
  const navDots = Array.from(document.querySelectorAll('[data-nav-dot]'));
  if (!tabs.length || !screens.length) return;

  let activeIdx = 0;
  let userInteracted = false;
  let timer = null;

  function activateScreen(index, focusTab) {
    activeIdx = (index + tabs.length) % tabs.length;
    const key = tabs[activeIdx].getAttribute('data-screen');
    tabs.forEach((tab, idx) => {
      const selected = idx === activeIdx;
      tab.classList.toggle('is-active', selected);
      tab.setAttribute('aria-selected', String(selected));
      tab.setAttribute('tabindex', selected ? '0' : '-1');
      if (selected && focusTab) tab.focus();
    });
    screens.forEach((panel) => {
      const match = panel.id === 'panel-' + key;
      panel.classList.toggle('is-active', match);
      panel.hidden = !match;
    });
    navDots.forEach((dot) => {
      dot.classList.toggle('active', dot.getAttribute('data-nav-dot') === key);
    });
  }

  tabs.forEach((tab, idx) => {
    tab.addEventListener('click', () => {
      userInteracted = true;
      if (timer) clearInterval(timer);
      activateScreen(idx, false);
    });
    tab.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        e.preventDefault();
        userInteracted = true;
        if (timer) clearInterval(timer);
        activateScreen(idx + (e.key === 'ArrowRight' ? 1 : -1), true);
      }
    });
  });

  const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!reduceMotion) {
    timer = setInterval(() => {
      if (!userInteracted && !document.hidden) {
        activateScreen(activeIdx + 1, false);
      }
    }, 4800);
  }
})();

// 5. iOS & Store Launch Modal
(function initIosDialog() {
  const iosDialog = document.getElementById('ios-dialog');
  if (!iosDialog) return;

  document.querySelectorAll('#ios-open,[data-open-ios]').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (typeof iosDialog.showModal === 'function') iosDialog.showModal();
    });
  });

  const closeBtn = document.getElementById('ios-close');
  if (closeBtn) closeBtn.addEventListener('click', () => iosDialog.close());

  iosDialog.addEventListener('click', (e) => {
    if (e.target === iosDialog) {
      const r = iosDialog.getBoundingClientRect();
      if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) {
        iosDialog.close();
      }
    }
  });
})();
