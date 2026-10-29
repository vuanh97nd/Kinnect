package app.kinnect.live;

import android.content.Context;
import android.content.res.Configuration;
import android.content.res.Resources;
import java.util.*;
import org.json.JSONObject;

/** UI translations only. Never translate a user's post, message or editable text. */
final class I18n {
  private static volatile Map<String,String> english=Collections.emptyMap();
  private static volatile String language="vi";
  private I18n() {}
  static synchronized void initialize(Context context) {
    if(english.isEmpty())try(java.io.InputStream in=context.getAssets().open("i18n-en.json")){
      java.io.ByteArrayOutputStream out=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;
      while((n=in.read(buffer))!=-1)out.write(buffer,0,n);
      JSONObject data=new JSONObject(out.toString("UTF-8"));Map<String,String> map=new HashMap<>();
      java.util.Iterator<String> keys=data.keys();while(keys.hasNext()){String key=keys.next();map.put(key,data.getString(key));}
      english=Collections.unmodifiableMap(map);
    }catch(Exception error){android.util.Log.e("Kinnect","Unable to load language catalog",error);}
    String saved=context.getSharedPreferences("app_language",0).getString("language","system");
    language=resolve(saved,Resources.getSystem().getConfiguration().getLocales().get(0).getLanguage());
  }
  static String resolve(String saved,String device){return "en".equals(saved)?"en":"vi".equals(saved)?"vi":"vi".equals(device)?"vi":"en";}
  static String current(){return language;}
  static String preference(Context c){return c.getSharedPreferences("app_language",0).getString("language","system");}
  static void select(Context c,String value){
    if(!value.equals("vi")&&!value.equals("en")&&!value.equals("system"))throw new IllegalArgumentException("Unsupported language");
    c.getSharedPreferences("app_language",0).edit().putString("language",value).apply();initialize(c);
  }
  static Context localized(Context base){
    initialize(base);Configuration config=new Configuration(base.getResources().getConfiguration());
    config.setLocale(Locale.forLanguageTag(language));return base.createConfigurationContext(config);
  }
  static String t(String source){if(source==null||!language.equals("en"))return source;String value=english.get(source);return value==null?source:value;}
  static CharSequence ui(CharSequence source){return source instanceof String?t((String)source):source;}
  static String[] items(String[] source){String[] result=source.clone();for(int i=0;i<result.length;i++)result[i]=t(result[i]);return result;}
}
