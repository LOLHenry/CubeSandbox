// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 Tencent. All rights reserved.
//
// PID1 for ReDroid+cubebox: daemonize envd (-isnotfc), then exec /init.
// init.rc is a backup if this early start fails; shell entrypoints are unreliable.
//
// Diagnostics (if template probe fails):
//   /data/local/tmp/envd-starter.log  — this binary
//   /data/local/tmp/envd.log          — envd stdout/stderr
//   /tmp/envd-starter.log             — early-boot fallback
package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

const (
	starterLogPrimary = "/data/local/tmp/envd-starter.log"
	starterLogFallback = "/tmp/envd-starter.log"
)

func main() {
	log := newStarterLog()
	log.banner()

	envdPort := getenv("ENVD_PORT", "49983")
	envdBin := getenv("ENVD_BIN", "/usr/bin/envd")
	envdLog := getenv("ENVD_LOG", "/data/local/tmp/envd.log")

	log.info("config ENVD_BIN=%s ENVD_PORT=%s ENVD_LOG=%s", envdBin, envdPort, envdLog)
	log.info("argv=%q", os.Args)
	log.info("pid=%d ppid=%d uid=%d gid=%d", os.Getpid(), os.Getppid(), os.Getuid(), os.Getgid())
	log.info("cwd=%s", mustGetwd())
	log.info("exe=%s", readLink("/proc/self/exe"))

	_ = os.MkdirAll("/tmp", 0o755)
	if err := os.MkdirAll("/data/local/tmp", 0o755); err != nil {
		log.warn("mkdir /data/local/tmp: %v (using /tmp for envd log fallback)", err)
	}

	log.info("envd binary: %s", describePath(envdBin))
	log.info("init candidates: %s", describeInitCandidates())

	startErr := startEnvd(log, envdBin, envdPort, envdLog)
	if startErr != nil {
		log.error("pre-init envd start failed: %v (cube-envd.rc may start envd later)", startErr)
		log.error("envd log tail (%s):\n%s", envdLog, tailFile(envdLog, 40))
	} else {
		log.info("pre-init envd start succeeded")
	}

	initPath := resolveInitPath(log)
	argv := append([]string{initPath}, os.Args[1:]...)
	log.info("exec %s argv=%q", initPath, argv)
	if err := syscall.Exec(initPath, argv, os.Environ()); err != nil {
		log.error("exec %s failed: %v", initPath, err)
		os.Exit(255)
	}
}

func resolveInitPath(log *starterLog) string {
	for _, path := range []string{"/init", "/system/bin/init"} {
		if st, err := os.Stat(path); err == nil {
			log.info("using init path %s (mode=%s size=%d)", path, st.Mode(), st.Size())
			return path
		}
		log.warn("init path missing: %s", path)
	}
	log.warn("no init found; defaulting to /init")
	return "/init"
}

func startEnvd(log *starterLog, bin, port, logPath string) error {
	if err := os.MkdirAll("/data/local/tmp", 0o755); err != nil {
		log.warn("mkdir /data/local/tmp for envd log: %v; fallback /tmp/envd.log", err)
		logPath = "/tmp/envd.log"
	}

	envdOut, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return fmt.Errorf("open envd log %s: %w", logPath, err)
	}
	defer envdOut.Close()

	nullFile, err := os.Open(os.DevNull)
	if err != nil {
		return fmt.Errorf("open %s: %w", os.DevNull, err)
	}
	defer nullFile.Close()

	args := []string{"-isnotfc", "-no-cgroups", "-verbose", "-port", port}
	var lastErr error

	for attempt := 1; attempt <= 5; attempt++ {
		if attempt > 1 {
			delay := time.Duration(attempt) * 300 * time.Millisecond
			log.warn("envd retry %d/5 after %v", attempt, delay)
			time.Sleep(delay)
		}

		cmdLine := strings.Join(append([]string{bin}, args...), " ")
		log.info("envd start attempt %d/5: %s log=%s", attempt, cmdLine, logPath)

		cmd := exec.Command(bin, args...)
		cmd.Stdin = nullFile
		cmd.Stdout = envdOut
		cmd.Stderr = envdOut
		cmd.SysProcAttr = &syscall.SysProcAttr{
			Setsid:  true,
			Setpgid: true,
		}

		if err := cmd.Start(); err != nil {
			lastErr = err
			log.error("envd Start() attempt %d: %v", attempt, err)
			continue
		}

		pid := cmd.Process.Pid
		if err := cmd.Process.Release(); err != nil {
			lastErr = err
			log.error("envd Release() attempt %d pid=%d: %v", attempt, pid, err)
			continue
		}

		log.info("envd spawned pid=%d; waiting for process + :%s/health", pid, port)
		time.Sleep(500 * time.Millisecond)

		if err := syscall.Kill(pid, 0); err != nil {
			lastErr = fmt.Errorf("envd pid=%d exited immediately: %w", pid, err)
			log.error("%v", lastErr)
			log.error("envd log tail after crash:\n%s", tailFile(logPath, 30))
			continue
		}

		ok, probeMsg := probeHealth(log, port, 6, 500*time.Millisecond)
		if ok {
			log.info("envd healthy pid=%d port=%s probe=%s", pid, port, probeMsg)
			return nil
		}

		if err := syscall.Kill(pid, 0); err != nil {
			lastErr = fmt.Errorf("envd pid=%d died during health probe: %w", pid, err)
			log.error("%v", lastErr)
			log.error("envd log tail after probe failure:\n%s", tailFile(logPath, 30))
			continue
		}

		// Process alive but /health not ready yet — accept for template (init.rc backup).
		log.warn("envd pid=%d alive but probe not ready: %s (continuing anyway)", pid, probeMsg)
		return nil
	}

	return fmt.Errorf("envd failed after 5 attempts: %v", lastErr)
}

func probeHealth(log *starterLog, port string, attempts int, interval time.Duration) (bool, string) {
	url := fmt.Sprintf("http://127.0.0.1:%s/health", port)
	client := &http.Client{Timeout: 2 * time.Second}

	var lastMsg string
	for i := 1; i <= attempts; i++ {
		resp, err := client.Get(url)
		if err != nil {
			lastMsg = fmt.Sprintf("attempt %d GET %s: %v", i, url, err)
			log.warn("health %s", lastMsg)
			time.Sleep(interval)
			continue
		}
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 256))
		_ = resp.Body.Close()
		lastMsg = fmt.Sprintf("attempt %d GET %s => HTTP %d body=%q", i, url, resp.StatusCode, strings.TrimSpace(string(body)))
		log.info("health %s", lastMsg)
		if resp.StatusCode == http.StatusNoContent || resp.StatusCode == http.StatusOK {
			return true, lastMsg
		}
		time.Sleep(interval)
	}
	return false, lastMsg
}

type starterLog struct {
	paths []string
}

func newStarterLog() *starterLog {
	_ = os.MkdirAll("/tmp", 0o755)
	_ = os.MkdirAll("/data/local/tmp", 0o755)
	return &starterLog{paths: []string{starterLogPrimary, starterLogFallback}}
}

func (l *starterLog) banner() {
	l.info("=== envd-starter boot %s ===", time.Now().Format(time.RFC3339Nano))
	l.info("log files: %s, %s", starterLogPrimary, starterLogFallback)
}

func (l *starterLog) info(format string, args ...any)  { l.write("INFO", format, args...) }
func (l *starterLog) warn(format string, args ...any)  { l.write("WARN", format, args...) }
func (l *starterLog) error(format string, args ...any) { l.write("ERROR", format, args...) }

func (l *starterLog) write(level, format string, args ...any) {
	line := fmt.Sprintf("%s [%s] %s\n",
		time.Now().Format(time.RFC3339Nano), level,
		fmt.Sprintf(format, args...))
	_, _ = os.Stderr.WriteString("envd-starter: " + strings.TrimSpace(line) + "\n")
	for _, path := range l.paths {
		f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			continue
		}
		_, _ = f.WriteString(line)
		_ = f.Close()
	}
}

func describePath(path string) string {
	st, err := os.Stat(path)
	if err != nil {
		return fmt.Sprintf("%s: stat error: %v", path, err)
	}
	return fmt.Sprintf("%s exists mode=%s size=%d", path, st.Mode(), st.Size())
}

func describeInitCandidates() string {
	var parts []string
	for _, path := range []string{"/init", "/system/bin/init"} {
		if st, err := os.Stat(path); err == nil {
			parts = append(parts, fmt.Sprintf("%s(ok size=%d)", path, st.Size()))
		} else {
			parts = append(parts, fmt.Sprintf("%s(missing)", path))
		}
	}
	return strings.Join(parts, ", ")
}

func tailFile(path string, maxLines int) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Sprintf("(cannot read %s: %v)", path, err)
	}
	lines := strings.Split(strings.TrimRight(string(data), "\n"), "\n")
	if len(lines) > maxLines {
		lines = lines[len(lines)-maxLines:]
	}
	if len(lines) == 0 {
		return "(empty)"
	}
	return strings.Join(lines, "\n")
}

func mustGetwd() string {
	cwd, err := os.Getwd()
	if err != nil {
		return fmt.Sprintf("(error: %v)", err)
	}
	return cwd
}

func readLink(path string) string {
	target, err := os.Readlink(path)
	if err != nil {
		return fmt.Sprintf("(error: %v)", err)
	}
	return target
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
