// Kinnect website: nhận diện thiết bị, menu, ảnh màn hình xoay vòng, hiệu ứng khi cuộn.
document.documentElement.classList.add("js");

const ua = navigator.userAgent;
const isIOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
const isAndroid = /Android/i.test(ua);
const platform = isIOS ? "ios" : isAndroid ? "android" : "desktop";
document.documentElement.dataset.platform = platform;

// Universal web entry; optional home-screen instructions for each platform.
const sheet = document.getElementById("ios-sheet");
const installTabs = [...document.querySelectorAll("[data-install-tab]")];
function selectInstallTab(value) {
  for (const tab of installTabs) { const active = tab.dataset.installTab === value; tab.setAttribute("aria-selected", String(active)); tab.tabIndex = active ? 0 : -1; document.getElementById(tab.getAttribute("aria-controls")).hidden = !active; }
}
selectInstallTab(platform);
const openSheet = () => { selectInstallTab(platform); sheet?.showModal(); };
document.querySelectorAll("[data-open-install]").forEach(button => button.addEventListener("click", openSheet));
installTabs.forEach((tab, index) => {
  tab.addEventListener("click", () => selectInstallTab(tab.dataset.installTab));
  tab.addEventListener("keydown", event => {
    const next = event.key === "ArrowRight" ? (index + 1) % installTabs.length : event.key === "ArrowLeft" ? (index + installTabs.length - 1) % installTabs.length : event.key === "Home" ? 0 : event.key === "End" ? installTabs.length - 1 : null;
    if (next !== null) { event.preventDefault(); selectInstallTab(installTabs[next].dataset.installTab); installTabs[next].focus(); }
  });
});
sheet?.querySelector(".close").addEventListener("click", () => sheet.close());
sheet?.addEventListener("click", event => { if (event.target === sheet) { const rect = sheet.getBoundingClientRect(); if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) sheet.close(); } });
const bar = document.querySelector(".sticky-get");
const getBlock = document.querySelector(".web-actions");
if (bar && getBlock) {
  const button = bar.querySelector(".btn");
  new IntersectionObserver(([entry]) => { const show = !entry.isIntersecting && entry.boundingClientRect.top < 0; bar.classList.toggle("show", show); bar.setAttribute("aria-hidden", String(!show)); button.tabIndex = show ? 0 : -1; }).observe(getBlock);
}

// Menu trên điện thoại
const menuBtn = document.querySelector(".menu-btn");
const menu = document.getElementById("menu");
menuBtn?.addEventListener("click", () => {
  const open = menu.classList.toggle("open");
  menuBtn.setAttribute("aria-expanded", String(open));
  menuBtn.setAttribute("aria-label", open ? "Đóng menu" : "Mở menu");
});
menu?.addEventListener("click", (e) => {
  if (e.target.closest("a")) {
    menu.classList.remove("open");
    menuBtn?.setAttribute("aria-expanded", "false");
  }
});

// Viền thanh trên khi cuộn
const header = document.querySelector(".site-header");
const onScroll = () => header?.classList.toggle("scrolled", window.scrollY > 8);
window.addEventListener("scroll", onScroll, { passive: true });
onScroll();

// Ảnh màn hình app xoay vòng trong khung điện thoại
const slides = document.querySelector("[data-slides]");
const dots = document.querySelector(".hero-art .dots");
if (slides && dots) {
  const imgs = [...slides.querySelectorAll("img")];
  let i = 0;
  let timer;
  const show = (n) => {
    i = (n + imgs.length) % imgs.length;
    imgs.forEach((img, k) => img.classList.toggle("on", k === i));
    [...dots.children].forEach((d, k) => d.setAttribute("aria-selected", String(k === i)));
  };
  imgs.forEach((img, k) => {
    const d = document.createElement("button");
    d.type = "button";
    d.setAttribute("role", "tab");
    d.setAttribute("aria-label", img.alt);
    d.addEventListener("click", () => {
      show(k);
      clearInterval(timer);
    });
    dots.append(d);
  });
  show(0);
  if (!matchMedia("(prefers-reduced-motion: reduce)").matches) timer = setInterval(() => show(i + 1), 3500);
}

// Hiệu ứng xuất hiện khi cuộn tới
const reveals = document.querySelectorAll(".reveal");
if ("IntersectionObserver" in window) {
  const io = new IntersectionObserver(
    (entries) =>
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      }),
    { threshold: 0, rootMargin: "0px 0px -8% 0px" },
  );
  reveals.forEach((el) => io.observe(el));
} else {
  reveals.forEach((el) => el.classList.add("in"));
}

// Hỏi đáp: chỉ mở một câu một lúc
const faqs = document.querySelectorAll(".faq details");
faqs.forEach((d) =>
  d.addEventListener("toggle", () => {
    if (d.open) faqs.forEach((o) => o !== d && (o.open = false));
  }),
);

// The app validates its own HttpOnly cookie in a first-party hidden frame.
const sessionLink = document.querySelector("[data-session-link]");
if (sessionLink) {
  const appOrigin = "https://app.kinnect.io.vn";
  const sessionFrame = document.createElement("iframe");
  sessionFrame.hidden = true;
  sessionFrame.title = "Kiểm tra phiên Kinnect";
  sessionFrame.src = appOrigin + "/?website-session=1";
  window.addEventListener("message", (event) => {
    if (event.origin !== appOrigin || event.source !== sessionFrame.contentWindow || event.data?.type !== "kinnect:session-status" || typeof event.data.authenticated !== "boolean") return;
    sessionLink.textContent = event.data.authenticated ? "Mở Kinnect" : "Đăng nhập";
    if (event.data.authenticated && ["/", "/index.html"].includes(window.location.pathname)) window.location.replace(appOrigin + "/");
  });
  const check = () => sessionFrame.contentWindow?.postMessage({ type: "kinnect:check-session" }, appOrigin);
  sessionFrame.addEventListener("load", check);
  window.addEventListener("pageshow", check);
  window.addEventListener("focus", check);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) check(); });
  document.body.append(sessionFrame);
}
