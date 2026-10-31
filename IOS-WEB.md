# Bản web iOS / PWA

Đã thêm Apple metadata, manifest standalone, icon, thanh điều hướng di động, safe-area và biểu mẫu font 16px.
Mở HTTPS bằng Safari > Chia sẻ > Thêm vào MH chính > Thêm.
Service worker chỉ lưu CSS/JS/icon và trang offline; không lưu API hoặc nội dung riêng tư vào Cache Storage.
11 kiểm thử backend đạt trên Windows. Đã kiểm tra các tài nguyên qua HTTPS.
Chưa thử iPhone thật, camera/micro Safari, push notification và video Internet.
Các tệp thêm: public/ios.css, public/ios.js, public/sw.js, public/manifest.webmanifest, public/offline.html.
Các tệp sửa: public/index.html, server.js.
