// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 Tencent. All rights reserved.
//
// PID1 for ReDroid+cubebox: daemonize envd (-isnotfc), then exec /init.
// init.rc is a backup if this early start fails; shell entrypoints are unreliable.
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

	_ = os.MkdirAll("/tmp", 0o755)
	_ = os.MkdirAll("/data/local/tmp", 0o755)

	if err := startEnvd(envdBin, envdPort, envdLog); err != nil {
		fmt.Fprintf(os.Stderr, "envd-starter: %v (cube-envd.rc may start envd later)\n", err)
	}

	initPath := resolveInitPath()
	argv := append([]string{initPath}, os.Args[1:]...)
	if err := syscall.Exec(initPath, argv, os.Environ()); err != nil {
		fmt.Fprintf(os.Stderr, "envd-starter: exec %s: %v\n", initPath, err)
		os.Exit(255)
	}
}

func resolveInitPath() string {
	for _, path := range []string{"/init", "/system/bin/init"} {
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	return "/init"
}

func startEnvd(bin, port, logPath string) error {
	if err := os.MkdirAll("/data/local/tmp", 0o755); err != nil {
		_ = os.MkdirAll("/tmp", 0o755)
		logPath = "/tmp/envd.log"
	}

	logFile, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("open log %s: %w", logPath, err)
	}
	defer logFile.Close()

	nullFile, err := os.Open(os.DevNull)
	if err != nil {
		return fmt.Errorf("open %s: %w", os.DevNull, err)
	}
	defer nullFile.Close()

	var lastErr error
	for attempt := 1; attempt <= 5; attempt++ {
		if attempt > 1 {
			time.Sleep(time.Duration(attempt) * 300 * time.Millisecond)
		}

		cmd := exec.Command(bin, "-isnotfc", "-port", port)
		cmd.Stdin = nullFile
		cmd.Stdout = logFile
		cmd.Stderr = logFile
		cmd.SysProcAttr = &syscall.SysProcAttr{
			Setsid:  true,
			Setpgid: true,
		}

		if err := cmd.Start(); err != nil {
			lastErr = err
			fmt.Fprintf(os.Stderr, "envd-starter: start attempt %d: %v\n", attempt, err)
			continue
		}

		pid := cmd.Process.Pid
		if err := cmd.Process.Release(); err != nil {
			lastErr = err
			fmt.Fprintf(os.Stderr, "envd-starter: release attempt %d: %v\n", attempt, err)
			continue
		}

		time.Sleep(500 * time.Millisecond)
		if err := syscall.Kill(pid, 0); err != nil {
			lastErr = fmt.Errorf("envd pid=%d exited immediately", pid)
			fmt.Fprintf(os.Stderr, "envd-starter: %v\n", lastErr)
			continue
		}

		fmt.Fprintf(os.Stderr, "envd-starter: envd pid=%d port=%s log=%s\n", pid, port, logPath)
		return nil
	}
	return fmt.Errorf("envd failed after retries: %v", lastErr)
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
