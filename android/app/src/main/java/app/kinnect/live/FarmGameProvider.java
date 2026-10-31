package app.kinnect.live;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;

import java.io.File;
import java.io.FileNotFoundException;

/** Grants Android's installer read access to the verified farm game module APK. */
public final class FarmGameProvider extends ContentProvider {
  public static File file(Context context) {
    return new File(context.getCacheDir(), "farm-game.apk");
  }

  private void validate(Uri uri) {
    if (!uri.getAuthority().equals(getContext().getPackageName() + ".farmgame")
      || !"/farm-game.apk".equals(uri.getPath()) || uri.getQuery() != null) {
      throw new IllegalArgumentException("Unknown farm module file");
    }
  }

  @Override public boolean onCreate() { return true; }

  @Override public String getType(Uri uri) {
    validate(uri);
    return "application/vnd.android.package-archive";
  }

  @Override public ParcelFileDescriptor openFile(Uri uri, String mode) throws FileNotFoundException {
    validate(uri);
    if (!"r".equals(mode)) throw new SecurityException("Read only");
    return ParcelFileDescriptor.open(file(getContext()), ParcelFileDescriptor.MODE_READ_ONLY);
  }

  @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String sort) {
    validate(uri);
    String[] columns = projection == null ? new String[]{OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE} : projection;
    MatrixCursor out = new MatrixCursor(columns);
    Object[] row = new Object[columns.length];
    for (int i = 0; i < columns.length; i++) {
      row[i] = OpenableColumns.DISPLAY_NAME.equals(columns[i]) ? "FarmGame.apk"
        : OpenableColumns.SIZE.equals(columns[i]) ? file(getContext()).length() : null;
    }
    out.addRow(row);
    return out;
  }

  @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException(); }
  @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException(); }
  @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException(); }
}
