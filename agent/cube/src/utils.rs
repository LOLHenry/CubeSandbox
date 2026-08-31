// Copyright (c) 2024 Tencent Inc.
// SPDX-License-Identifier: Apache-2.0
//

use std::path::PathBuf;

pub const ANNO_APP_SNAPSHOT_CONTAINER_ID: &str = "cube.appsnapshot.container.id";

/// Annotation injected by the shim into OCI spec annotations to opt-in to
/// container log forwarding.  When the value is "true" the agent creates
/// stdout/stderr pipes in open_io(); when absent (old shim) the pipes are
/// not created and the original behaviour is preserved.
pub const ANNO_CONTAINER_LOG_FORWARDING: &str = "cube.container.log_forwarding";

/// True when OCI process args indicate an Android/ReDroid init workload.
/// Used to disable log forwarding and sanitize inherited fds before exec.
pub fn is_android_workload(args: &[String]) -> bool {
    if args.iter().any(|a| a.starts_with("androidboot.")) {
        return true;
    }

    let Some(entry) = args.first() else {
        return false;
    };

    let is_init = entry.ends_with("/init") || entry == "init";
    is_init
        && args.iter().any(|a| {
            a.contains("redroid") || a.contains("androidboot.hardware=redroid")
        })
}

#[derive(Debug)]
pub struct CPath {
    pub path: PathBuf,
}

impl CPath {
    pub fn new(p: &str) -> Self {
        CPath {
            path: PathBuf::from(p),
        }
    }

    pub fn join(&mut self, p: &str) -> &mut Self {
        if let Some(stripped) = p.strip_prefix('/') {
            self.path.push(stripped);
        } else {
            self.path.push(p);
        }
        self
    }

    pub fn to_str(&self) -> Option<&str> {
        self.path.to_str()
    }

    pub fn to_path_buf(&self) -> PathBuf {
        self.path.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn android_workload_detection() {
        assert!(is_android_workload(&[
            "androidboot.redroid_width=1080".to_string(),
            "androidboot.redroid_height=1920".to_string(),
        ]));
        assert!(is_android_workload(&[
            "/init".to_string(),
            "androidboot.hardware=redroid".to_string(),
        ]));
        assert!(!is_android_workload(&["/bin/sh".to_string(), "-c".to_string(), "true".to_string()]));
        assert!(!is_android_workload(&["/init".to_string()]));
    }

    #[test]
    fn cpath() {
        let mut cp = CPath::new("/a/b/c");
        cp.join("/d/e");

        //to_str
        let strp = cp.to_str();
        assert!(strp.is_some());
        let p = strp.unwrap();
        assert_eq!(p, "/a/b/c/d/e");

        //to_path_buf
        let p = cp.to_path_buf();
        let strp = p.to_str();
        assert!(strp.is_some());
        let p = strp.unwrap().to_string();
        assert_eq!(p, "/a/b/c/d/e");
    }
}
