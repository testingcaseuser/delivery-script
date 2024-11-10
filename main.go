package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
)

func main() {
	scriptPath := flag.String("script", "script.sh", "Path to the bash script file")
	port := flag.String("port", "8080", "Port to serve on")
	flag.Parse()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/x-sh")
		http.ServeFile(w, r, *scriptPath)
	})

	addr := fmt.Sprintf(":%s", *port)
	fmt.Printf("Serving %s at http://localhost%s\n", *scriptPath, addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}
