const image=document.getElementById('install-icon'),status=document.getElementById('icon-status');
if(matchMedia('(display-mode: standalone)').matches||navigator.standalone)location.replace('/?source=homescreen');
image.decode().then(()=>{status.textContent='Logo đã tải được trên máy này.';}).catch(()=>{status.textContent='Máy này chưa tải được logo. Hãy báo lại dòng này.';});
document.getElementById('diagnostics').textContent=navigator.userAgent+' · Icon 180×180 · Bản kiểm tra iOS 8';
