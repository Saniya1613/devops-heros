import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

/** Minimal Hello World HTTP server using only the JDK's built-in HttpServer. */
public class Main {

    public static void main(String[] args) throws IOException {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "7000"));

        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", port), 0);
        server.createContext("/", (HttpExchange exchange) -> {
            String body = "<!DOCTYPE html><html>"
                    + "<head><title>Hello World - Java</title></head>"
                    + "<body><h1>Hello World from Java</h1>"
                    + "<p>JDK " + System.getProperty("java.version")
                    + " on port " + port + ", path " + exchange.getRequestURI().getPath()
                    + "</p></body></html>";

            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "text/html; charset=utf-8");
            exchange.sendResponseHeaders(200, bytes.length);
            try (OutputStream out = exchange.getResponseBody()) {
                out.write(bytes);
            }
            System.out.println("[java-app] GET " + exchange.getRequestURI().getPath());
        });

        server.setExecutor(null);
        System.out.println("[java-app] listening on 0.0.0.0:" + port);
        server.start();
    }
}
