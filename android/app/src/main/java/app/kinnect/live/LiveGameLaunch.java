package app.kinnect.live;
import android.content.*;import android.content.pm.*;import java.util.*;

/** Resolves only launchable games, locally. Never uploads the installed-app list. */
final class LiveGameLaunch {
 static Intent intent(Context context,String title){
  String wanted=LiveGamePicker.normalized(title);if(wanted.isEmpty())return null;
  String[] aliases={};for(String[] g:LiveGamePicker.GAMES)if(g[0].equals(title))aliases=(g.length>3?g[3]:g[0]).split(";");
  PackageManager pm=context.getPackageManager();Intent launcher=new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER);
  for(ResolveInfo app:pm.queryIntentActivities(launcher,0)){
   if(app.activityInfo==null||app.activityInfo.packageName.equals(context.getPackageName()))continue;
   String label=LiveGamePicker.normalized(app.loadLabel(pm).toString());boolean match=label.equals(wanted);
   for(String alias:aliases)if(label.equals(LiveGamePicker.normalized(alias)))match=true;
   if(match)return new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER).setComponent(new ComponentName(app.activityInfo.packageName,app.activityInfo.name)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK|Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
  }return null;
 }
}
