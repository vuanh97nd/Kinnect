package app.kinnect.live;
public final class ServerConfigTest {
    private static void check(boolean condition){if(!condition)throw new AssertionError();}
    public static void main(String[] args){
        check(ServerConfig.resolve(null).equals(ServerConfig.DEFAULT_ORIGIN));
        check(ServerConfig.resolve("").equals(ServerConfig.DEFAULT_ORIGIN));
        check(ServerConfig.resolve("not a url").equals(ServerConfig.DEFAULT_ORIGIN));
        check(ServerConfig.resolve("https://custom.example:8443/").equals("https://custom.example:8443"));
        check(ServerConfig.normalize(" HTTPS://CUSTOM.EXAMPLE:443/ ").equals("https://custom.example"));
        for(String value:new String[]{"http://example.com","https://user:pass@example.com","https://example.com/path","https://example.com?q=token","https://example.com#part","https://example.com:0","https://example.com:99999","https://"}){
            boolean rejected=false;try{ServerConfig.normalize(value);}catch(IllegalArgumentException expected){rejected=true;}check(rejected);
        }
        System.out.println("ServerConfig: default, override, fallback and HTTPS validation checks passed.");
    }
}
