// SPDX-License-Identifier: Apache-2.0
// Copyright (C) 2026 Tencent. All rights reserved.
//
// Android/bionic PID1 wrapper: exec ReDroid /init only.
// envd is started by /vendor/etc/init/cube-envd.rc (not here) because
// /system/bin/sh is not usable as a Docker/CubeVM entrypoint on Kunpeng hosts.
package main

import (
	"fmt"
	"os"
	"syscall"
)

func main() {
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
