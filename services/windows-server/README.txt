KINNECT SERVER — KHO ANH/VIDEO — WINDOWS x64

1. Giai nen toan bo ZIP, bam Cai-dat.cmd (khong can quyen Administrator).
2. Mo Kinnect Server tren Desktop. Node.js da kem san.
3. Chon o/thu muc luu. Co the chon D:\KinnectData, E:\KinnectData...
4. Tren may A, nhap duong dan kinnect.sqlite nguon (neu co).
5. Bat cong dong bo tren may nguon, hien ma ghep noi.
6. Tren may B, nhap dia chi may A + ma cua A, bam Ghep noi.
7. Bat dong bo. Neu ca hai may nhan noi dung moi, ghep noi ca hai chieu.

Cung LAN: http://IP-NOI-BO:3129. Khac mang: can HTTPS hoac VPN rieng;
bo cai khong tu mo router, firewall hoac cap ten mien. Cong quan ly 3128
chi tren loopback, khong cong khai ra Internet. Ma ghep noi cap quyen
doc ca tep rieng tu: chi dung cho cac may chu thuoc quyen quan ly cua ban.

Dong bo tung thay doi, kiem tra SHA-256, luu moc tren dia, tai tiep file
bi gian doan. Co che tombstone giu dau xoa, khong xoa vat ly ngay. Khong
chon cung mot thu muc cho hai phien may chu dong thoi. Doi thu muc mo
kho moi, KHONG tu di chuyen kho cu. Hai may phai cung online de truyen.

DAY LA BO QUAN LY KHO MEDIA: chua tu thay duong dan anh/video trong app
Kinnect production, chua thay API, cloud database, Live/SFU/TURN.
Anh/video duoc tach tu SQLite theo che do chi doc, khong sao chep
tai khoan/mat khau. Kho ban sao chua phuc vu cho nguoi dung app qua API.
Chua thu tren PC thu hai/ket noi Internet thuc te; da thu hai kho doc lap.

Cau hinh rieng: %LOCALAPPDATA%\KinnectServer\settings.json
Chi muc + file: thu muc luu da chon. Khong dua settings.json vao ma nguon.
Node.js kem theo: xem runtime\LICENSE va runtime\VERSION.txt.
