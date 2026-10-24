package app.kinnect.live;
public final class ReleaseVersionTest {
 private static void check(boolean condition){if(!condition)throw new AssertionError();}
 public static void main(String[] args){check(ReleaseVersion.compare("v0.4.0","0.3.1")>0);check(ReleaseVersion.compare("v0.10.0","0.9.9")>0);check(ReleaseVersion.compare("0.4.0","v0.4.0")==0);check(ReleaseVersion.compare("0.3.9","0.4.0")<0);for(String s:new String[]{"",null,"0.4","v0.4.0-beta","0.4.0/anything","999999999999.0.0"}){boolean rejected=false;try{ReleaseVersion.compare(s,"0.4.0");}catch(IllegalArgumentException expected){rejected=true;}check(rejected);}System.out.println("ReleaseVersion: numeric versions, upgrades, downgrades and invalid tags passed.");}
}
