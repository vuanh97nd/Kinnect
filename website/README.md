# Website Kinnect

Website giới thiệu tại https://kinnect.io.vn và https://www.kinnect.io.vn; ứng dụng web tại https://app.kinnect.io.vn.

## Nội dung và build

- Sửa trang ở `src/pages/*.html`, bố cục dùng chung ở `src/layout.html`.
- CSS, JavaScript và ảnh tĩnh nằm trong `dist/`; build không ghi đè các tệp này.
- Chạy `python build.py` để sinh 5 trang và sitemap. Build tự gắn mã nội dung vào URL CSS, JS và ảnh xem trước để trình duyệt nhận tài nguyên mới.
- Xuất bản toàn bộ `dist/` bằng Cloudflare Workers Static Assets, project `odd-disk-3093`. Gói ZIP cần có index.html ngay cấp gốc.

## Hành vi hiện tại

Android, iPhone/iPad và máy tính đều dùng nút **Dùng ngay trên web**. Nút **Tải app** ghi rõ **Chỉ hỗ trợ Android**, dẫn tới trang phát hành APK chính thức. Hướng dẫn thêm vào màn hình chính nằm ở liên kết phụ. Thiết bị Android tự được nhận diện trên trình duyệt; nút tải app có nhãn Gợi ý cho máy bạn. iOS và máy tính không hiện nhãn này, vẫn dùng web bình thường. Hộp hướng dẫn màn hình chính có ba mục thiết bị; bàn phím hỗ trợ phím mũi tên, Home và End.

Giao diện tự theo `prefers-color-scheme` của thiết bị, cập nhật ngay khi thiết bị đổi sáng/tối. Không lưu chế độ ghi đè trong localStorage.

Nút đầu trang kiểm tra phiên bằng iframe thuộc ứng dụng. Chỉ chấp nhận thông điệp từ đúng origin, đúng cửa sổ và kiểu dữ liệu; không đưa cookie/token vào website giới thiệu. Phiên còn hiệu lực: trang chủ tự chuyển tới app bằng location.replace; các trang chính sách vẫn cho xem và hiện Mở Kinnect. Chưa đăng nhập: ở lại trang giới thiệu và hiện Đăng nhập. Iframe không mở kết nối Live.

## Kiểm tra và xuất bản

- `node tests/session.mjs`: kiểm tra đăng nhập/đăng xuất với ứng dụng dữ liệu tạm.
- Đã kiểm tra 10 cấu hình kích thước/thiết bị và sáng/tối; đổi theme động, hướng dẫn cài lối tắt và nút vào web.
- Sau xuất bản đã đối chiếu hash tài nguyên, kiểm tra mobile/PC sáng/tối và phiên đăng nhập thật. Không có lỗi JavaScript hoặc tràn ngang trong lượt kiểm tra.
- Bản xuất bản ngày 24/10/2026: `abe17fc8`, Ready 100%.

Video Live giữa các mạng và thông báo khi đã đóng trình duyệt vẫn có các giới hạn riêng của ứng dụng. Kiểm tra responsive sử dụng Chrome và mô phỏng thiết bị, chưa thay thế thử trên iPhone vật lý.
