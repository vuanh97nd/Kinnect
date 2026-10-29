package app.kinnect.live;
import android.content.Context;
import android.security.keystore.*;
import android.util.Base64;
import java.security.*;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
/** Session encrypted with a non-exportable Android Keystore key. Never stores passwords. */
final class SessionStore {
 private final Context context;
 SessionStore(Context context){this.context=context.getApplicationContext();}
 private javax.crypto.SecretKey key() throws Exception {KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);if(store.containsAlias("kinnect_session"))return (javax.crypto.SecretKey)store.getKey("kinnect_session",null);KeyGenerator gen=KeyGenerator.getInstance("AES","AndroidKeyStore");gen.init(new KeyGenParameterSpec.Builder("kinnect_session",KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());return gen.generateKey();}
 synchronized void save(String origin,String cookie){try{if(cookie.isEmpty()){context.getSharedPreferences("native_session",0).edit().clear().apply();return;}Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key());c.updateAAD(origin.getBytes("UTF-8"));String value=Base64.encodeToString(c.getIV(),Base64.NO_WRAP)+":"+Base64.encodeToString(c.doFinal(cookie.getBytes("UTF-8")),Base64.NO_WRAP);context.getSharedPreferences("native_session",0).edit().putString("origin",origin).putString("value",value).apply();}catch(Exception failure){context.getSharedPreferences("native_session",0).edit().clear().apply();}}
 synchronized String load(String origin){try{android.content.SharedPreferences p=context.getSharedPreferences("native_session",0);if(!origin.equals(p.getString("origin","")))return "";String[] parts=p.getString("value","").split(":");Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)));c.updateAAD(origin.getBytes("UTF-8"));return new String(c.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),"UTF-8");}catch(Exception failure){return "";}}
 // Thẻ "nhớ thiết bị" để đăng nhập nhanh: lưu riêng, không bị xoá khi đăng xuất.
 synchronized void saveDevice(String origin,String value){try{Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.ENCRYPT_MODE,key());c.updateAAD(origin.getBytes("UTF-8"));context.getSharedPreferences("native_device",0).edit().putString("origin",origin).putString("value",Base64.encodeToString(c.getIV(),Base64.NO_WRAP)+":"+Base64.encodeToString(c.doFinal(value.getBytes("UTF-8")),Base64.NO_WRAP)).apply();}catch(Exception failure){context.getSharedPreferences("native_device",0).edit().clear().apply();}}
 synchronized String loadDevice(String origin){try{android.content.SharedPreferences p=context.getSharedPreferences("native_device",0);if(!origin.equals(p.getString("origin","")))return "";String[] parts=p.getString("value","").split(":");Cipher c=Cipher.getInstance("AES/GCM/NoPadding");c.init(Cipher.DECRYPT_MODE,key(),new GCMParameterSpec(128,Base64.decode(parts[0],Base64.NO_WRAP)));c.updateAAD(origin.getBytes("UTF-8"));return new String(c.doFinal(Base64.decode(parts[1],Base64.NO_WRAP)),"UTF-8");}catch(Exception failure){return "";}}
}
