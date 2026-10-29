package app.kinnect.live;
/** Only stable numeric release tags can trigger APK upgrades. */
public final class ReleaseVersion {
 public static int compare(String a,String b){int[] x=parse(a),y=parse(b);for(int i=0;i<3;i++)if(x[i]!=y[i])return Integer.compare(x[i],y[i]);return 0;}
 private static int[] parse(String s){if(s==null||!s.matches("v?[0-9]{1,6}\\.[0-9]{1,6}\\.[0-9]{1,6}"))throw new IllegalArgumentException("Invalid version");String[] parts=s.replaceFirst("^v","").split("\\.");return new int[]{Integer.parseInt(parts[0]),Integer.parseInt(parts[1]),Integer.parseInt(parts[2])};}
}
