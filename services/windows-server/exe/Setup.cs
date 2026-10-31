using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
class Setup {
 static string Extract(string target) {
  Directory.CreateDirectory(target);
  using(Stream input=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
  using(ZipArchive zip=new ZipArchive(input,ZipArchiveMode.Read)) {
   foreach(ZipArchiveEntry item in zip.Entries) {
    if(item.Name.Length==0)continue;
    string full=Path.GetFullPath(Path.Combine(target,item.FullName));
    if(!full.StartsWith(Path.GetFullPath(target)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Goi cai khong hop le.");
    Directory.CreateDirectory(Path.GetDirectoryName(full));using(Stream source=item.Open())using(FileStream dest=new FileStream(full,FileMode.CreateNew))source.CopyTo(dest);
   }
  }
  string root=Path.Combine(target,"Kinnect-Server-Windows-0.2.0");
  if(!File.Exists(Path.Combine(root,"Kinnect Server.exe")))throw new Exception("Thieu launcher.");
  return root;
 }
 [STAThread] static int Main(string[] args) {
  Application.EnableVisualStyles();
  if(args.Length>0&&args[0]=="--verify-payload") {try{string p=Extract(Path.Combine(Path.GetTempPath(),"KinnectSetupTest-"+Guid.NewGuid().ToString("N")));ProcessStartInfo info=new ProcessStartInfo(Path.Combine(p,"runtime","node.exe"),"--version");info.UseShellExecute=false;info.CreateNoWindow=true;using(Process n=Process.Start(info)){n.WaitForExit();return n.ExitCode;}}catch{return 1;}}
  Form f=new Form();f.Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);f.Text="Kinnect Server · Cài đặt";f.ClientSize=new Size(560,360);f.StartPosition=FormStartPosition.CenterScreen;f.FormBorderStyle=FormBorderStyle.FixedDialog;f.MaximizeBox=false;f.BackColor=Color.FromArgb(247,245,253);f.Font=new Font("Segoe UI",10);
  Label title=new Label();title.Text="Kinnect Server";title.Font=new Font("Segoe UI",23,FontStyle.Bold);title.ForeColor=Color.FromArgb(105,63,219);title.SetBounds(30,24,500,48);f.Controls.Add(title);
  Label desc=new Label();desc.Text="Kho ảnh/video · Đồng bộ giữa các máy\nCó sẵn Node.js — không cần cài riêng.";desc.SetBounds(32,88,490,55);f.Controls.Add(desc);
  Label note=new Label();note.Text="Sau khi cài, bạn chọn ổ/thư mục lưu trong phần mềm.\nĐây là bản quản lý kho media, chưa thay API/Live của app.\nKhác mạng cần cấu hình HTTPS hoặc VPN.";note.ForeColor=Color.DimGray;note.SetBounds(32,158,490,82);f.Controls.Add(note);
  Label status=new Label();status.SetBounds(32,245,490,30);f.Controls.Add(status);
  Button install=new Button();install.Text="Cài đặt";install.SetBounds(352,290,170,44);install.FlatStyle=FlatStyle.Flat;install.BackColor=title.ForeColor;install.ForeColor=Color.White;f.Controls.Add(install);
  install.Click+=delegate {
   if(install.Tag is string){Process.Start(Path.Combine((string)install.Tag,"Kinnect Server.exe"));f.Close();return;}
   install.Enabled=false;status.Text="Đang cài đặt…";f.Refresh();
   try {
    string parent=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"KinnectServerApp","0.2.0-"+Guid.NewGuid().ToString("N"));
    string root=Extract(parent);
    // Create the shortcut via Windows Shell; no administrator rights or firewall change.
    Type shellType=Type.GetTypeFromProgID("WScript.Shell");object shell=Activator.CreateInstance(shellType);
    object shortcut=shellType.InvokeMember("CreateShortcut",BindingFlags.InvokeMethod,null,shell,new object[]{Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),"Kinnect Server.lnk")});
    Type t=shortcut.GetType();t.InvokeMember("TargetPath",BindingFlags.SetProperty,null,shortcut,new object[]{Path.Combine(root,"Kinnect Server.exe")});t.InvokeMember("WorkingDirectory",BindingFlags.SetProperty,null,shortcut,new object[]{root});t.InvokeMember("Save",BindingFlags.InvokeMethod,null,shortcut,null);
    status.Text="Đã cài đặt. Lối tắt đã có trên Desktop.";install.Text="Mở Kinnect Server";install.Enabled=true;
    // Replace installation handler so a second click only launches.
    install.Tag=root;
   }catch(Exception e){status.Text="Chưa cài được.";MessageBox.Show(e.Message,"Kinnect Server",MessageBoxButtons.OK,MessageBoxIcon.Error);install.Enabled=true;}
  };
  Application.Run(f);return 0;
 }
}
