package app.kinnect.live;
import android.content.*;
import android.database.*;
import android.net.Uri;
import android.os.*;
import android.provider.OpenableColumns;
import java.io.*;
/** Grants Android's installer read access to one verified private-cache APK. */
public final class ApkUpdateProvider extends ContentProvider {
 public static File file(Context c){return new File(c.getCacheDir(),"kinnect-update.apk");}
 private void validate(Uri u){if(!u.getAuthority().equals(getContext().getPackageName()+".updates")||!"/update.apk".equals(u.getPath())||u.getQuery()!=null)throw new IllegalArgumentException("Unknown update file");}
 public boolean onCreate(){return true;}
 public String getType(Uri u){validate(u);return "application/vnd.android.package-archive";}
 public ParcelFileDescriptor openFile(Uri u,String mode)throws FileNotFoundException{validate(u);if(!"r".equals(mode))throw new SecurityException("Read only");return ParcelFileDescriptor.open(file(getContext()),ParcelFileDescriptor.MODE_READ_ONLY);}
 public Cursor query(Uri u,String[] projection,String selection,String[] args,String sort){validate(u);String[] cols=projection==null?new String[]{OpenableColumns.DISPLAY_NAME,OpenableColumns.SIZE}:projection;MatrixCursor out=new MatrixCursor(cols);Object[] row=new Object[cols.length];for(int i=0;i<cols.length;i++)row[i]=OpenableColumns.DISPLAY_NAME.equals(cols[i])?"Kinnect-update.apk":OpenableColumns.SIZE.equals(cols[i])?file(getContext()).length():null;out.addRow(row);return out;}
 public Uri insert(Uri u,ContentValues v){throw new UnsupportedOperationException();}public int delete(Uri u,String s,String[] a){throw new UnsupportedOperationException();}public int update(Uri u,ContentValues v,String s,String[] a){throw new UnsupportedOperationException();}
}
