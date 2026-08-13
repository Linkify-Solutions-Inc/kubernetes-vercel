package main

import (
	"fmt"
	"net/http"
	"os"
	"strconv"
	"time"
)

func work(w http.ResponseWriter, r *http.Request) {
	ms, _ := strconv.Atoi(r.URL.Query().Get("ms"))
	if ms == 0 {
		ms = 2000
	}
	if ms > 10000 {
		ms = 10000
	}
	// Busy loop — burns a core so the CPU metric is real (autoscaling demo).
	end := time.Now().Add(time.Duration(ms) * time.Millisecond)
	for time.Now().Before(end) {
	}
	fmt.Fprintf(w, `{"app":"go-api","burned":%d,"pid":%d}`+"\n", ms, os.Getpid())
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "3000"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `{"app":"go-api","message":"Mini-PaaS demo API (Go)"}`+"\n")
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, `{"status":"ok"}`+"\n")
	})
	http.HandleFunc("/work", work)

	fmt.Printf("go-api listening on :%s\n", port)
	http.ListenAndServe(":"+port, nil)
}
