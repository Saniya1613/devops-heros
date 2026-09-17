// A small static web service used to demonstrate multi-stage builds.
// Go compiles to a single static binary, which makes the size difference dramatic.
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"runtime"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprintf(w,
			"<!DOCTYPE html><html><head><title>Multi-stage build demo</title></head>"+
				"<body><h1>Hello from a multi-stage Go build</h1>"+
				"<p>Compiled with %s, running on %s/%s, port %s</p>"+
				"<p>This binary ships in a scratch image with no OS underneath it.</p>"+
				"</body></html>",
			runtime.Version(), runtime.GOOS, runtime.GOARCH, port)
		log.Printf("served %s %s", r.Method, r.URL.Path)
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "ok")
	})

	log.Printf("listening on 0.0.0.0:%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
