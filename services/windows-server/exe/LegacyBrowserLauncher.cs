using System;
using System.IO;
using System.Diagnostics;
using System.Windows.Forms;
class Launcher {
 [STAThread] static int Main(string[] args) {
  try {
   string root=AppDomain.CurrentDomain.BaseDirectory;
   if(!File.Exists(Path.Combine(root,"runtime","node.exe"))||!File.Exists(Path.Combine(root,"Start.ps1")))throw new Exception("Thieu tep chuong trinh. Hay cai dat lai Kinnect Server.");
   if(args.Length>0&&args[0]=="--self-test")return 0;
   ProcessStartInfo p=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"Start.ps1")+"\"");
   p.WorkingDirectory=root;p.UseShellExecute=false;p.CreateNoWindow=true;p.WindowStyle=ProcessWindowStyle.Hidden;
   Process.Start(p);return 0;
  }catch(Exception e){MessageBox.Show(e.Message,"Kinnect Server",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
 }
}
