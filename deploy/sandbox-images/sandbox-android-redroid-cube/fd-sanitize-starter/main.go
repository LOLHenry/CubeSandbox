// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 Tencent. All rights reserved.
//
// OCI ENTRYPOINT for ReDroid on CubeVM: drop cube-agent/shim inherited FIFO fds,
// then exec Android /init. Must run before ReDroid init — not replaceable by init.rc.
//
// Diagnostics (cube-runtime login, Android mount namespace):
//   /data/local/tmp/fd-sanitize-starter.log
//   /tmp/fd-sanitize-starter.log
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"syscall"
	"time"
)

const (
	logPrimary   = "/data/local/tmp/fd-sanitize-starter.log"
	logFallback  = "/tmp/fd-sanitize-starter.log"
)

func main() {
	log := newStarterLog()
	log.banner()
	log.info("argv=%q ppid=%d uid=%d gid=%d", os.Args, os.Getppid(), os.Getuid(), os.Getgid())
	log.info("exe=%s", readLink("/proc/self/exe"))

	if err := sanitizeInheritedFDs(log); err != nil {
		log.error("sanitize failed: %v", err)
		os.Exit(1)
	}

	initPath := resolveInitPath(log)
	argv := append([]string{initPath}, os.Args[1:]...)
	log.info("exec %q", argv)

	if err := syscall.Exec(initPath, argv, os.Environ()); err != nil {
		log.error("exec %s failed: %v", initPath, err)
		os.Exit(255)
	}
}

func sanitizeInheritedFDs(log *starterLog) error {
	null, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open /dev/null: %w", err)
	}
	defer null.Close()

	// log_forwarding attaches FIFO pipes to stdio; redirect before exec /init.
	for fd := 0; fd <= 2; fd++ {
		if err := syscall.Dup2(int(null.Fd()), fd); err != nil {
			return fmt.Errorf("dup2 stdio fd %d: %w", fd, err)
		}
	}
	log.info("stdio redirected to /dev/null")

	closed := 0
	entries, err := os.ReadDir("/proc/self/fd")
	if err != nil {
		return fmt.Errorf("read /proc/self/fd: %w", err)
	}
	for _, e := range entries {
		n, err := strconv.Atoi(e.Name())
		if err != nil || n <= 2 {
			continue
		}
		if err := syscall.Close(n); err != nil {
			log.warn("close fd %d: %v", n, err)
			continue
		}
		closed++
	}
	log.info("closed %d inherited fd(s) >= 3", closed)
	return nil
}

func resolveInitPath(log *starterLog) string {
	for _, path := range []string{"/init", "/system/bin/init"} {
		if st, err := os.Stat(path); err == nil && !st.IsDir() {
			log.info("using init path %s (mode=%s size=%d)", path, st.Mode(), st.Size())
			return path
		}
		log.warn("init path missing: %s", path)
	}
	log.warn("defaulting to /init")
	return "/init"
}

type starterLog struct {
	paths []string
}

func newStarterLog() *starterLog {
	_ = os.MkdirAll("/tmp", 0o755)
	_ = os.MkdirAll(filepath.Dir(logPrimary), 0o755)
	return &starterLog{paths: []string{logPrimary, logFallback}}
}

func (l *starterLog) banner() {
	l.info("=== fd-sanitize-starter boot %s ===", time.Now().Format(time.RFC3339Nano))
}

func (l *starterLog) info(format string, args ...any)  { l.write("INFO", format, args...) }
func (l *starterLog) warn(format string, args ...any)  { l.write("WARN", format, args...) }
func (l *starterLog) error(format string, args ...any) { l.write("ERROR", format, args...) }

func (l *starterLog) write(level, format string, args ...any) {
	line := fmt.Sprintf("%s [%s] %s\n",
		time.Now().Format(time.RFC3339Nano), level,
		fmt.Sprintf(format, args...))
	_, _ = os.Stderr.WriteString("fd-sanitize-starter: " + line)
	for _, path := range l.paths {
		f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
		if err != nil {
			continue
		}
		_, _ = f.WriteString(line)
		_ = f.Close()
	}
}

func readLink(path string) string {
	target, err := os.Readlink(path)
	if err != nil {
		return fmt.Sprintf("(error: %v)", err)
	}
	return target
}
