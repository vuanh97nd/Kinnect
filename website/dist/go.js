if(/(?:^|;\s*)kinnect_signed_in=1(?:;|$)/.test(document.cookie)&&!/[?&]home=1/.test(location.search))location.replace("https://app.kinnect.io.vn/?s=feed");
