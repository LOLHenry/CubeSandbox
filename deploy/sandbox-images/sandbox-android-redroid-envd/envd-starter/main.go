// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 Tencent. All rights reserved.
//
// Minimal Android/bionic starter: launch envd, then exec ReDroid /init.
// Avoids relying on /bin/sh (not present in stock ReDroid images).
package main

import (
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"
)

func main() {
	envdPort := getenv("ENVD_PORT", "49983")
	envdBin := getenv("ENVD_BIN", "/usr/bin/envd")
	envdLog := getenv("ENVD_LOG", "/data/local/tmp/envd.log")

	if err := os.MkdirAll("/data/local/tmp", 0o755); err != nil {
		fmt.Fprintf(os.Stderr, "envd-starter: mkdir log dir: %v\n", err)
	}

	logFile, err := os.OpenFile(envdLog, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "envd-starter: open log %s: %v\n", envdLog, err)
	} else {
		defer logFile.Close()
	}

	for attempt := 1; attempt <= 3; attempt++ {
		cmd := exec.Command(envdBin, "-port", envdPort)
		if logFile != nil {
			cmd.Stdout = logFile
			cmd.Stderr = logFile
		}
		if err := cmd.Start(); err != nil {
			fmt.Fprintf(os.Stderr, "envd-starter: start envd attempt %d: %v\n", attempt, err)
			time.Sleep(time.Second)
			continue
		}
		time.Sleep(time.Second)
		if cmd.Process != nil {
			fmt.Fprintf(os.Stderr, "envd-starter: envd pid=%d port=%s\n", cmd.Process.Pid, envdPort)
			break
		}
	}

	argv := make([]string, 0, len(os.Args))
	argv = append(argv, "/init")
	argv = append(argv, os.Args[1:]...)
	if err := syscall.Exec("/init", argv, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "envd-starter: exec /init: %v\n", err)
		os.Exit(1)
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
