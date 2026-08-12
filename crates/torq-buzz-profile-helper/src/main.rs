//! Identity-map helper for TORQ Buzz permanent profile cleanup.
//!
//! C1 scope: dry-run / plan-only. Never prints secret values.
//! Does not access OS keyring unless future C2+ auth enables a backend.

use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use serde::{Deserialize, Serialize};

#[derive(Parser, Debug)]
#[command(name = "torq-buzz-profile-helper")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Plan identity-only removal from a JSON identity map file (dry-run by default).
    PlanRemoveIdentity {
        #[arg(long)]
        map_path: PathBuf,
        #[arg(long)]
        identity_pubkey: String,
        #[arg(long)]
        output: PathBuf,
        /// When set, write the cleaned map (still no secrets; map is public keys only).
        #[arg(long)]
        apply: bool,
    },
}

#[derive(Debug, Serialize, Deserialize, Default)]
struct IdentityMap {
    #[serde(default)]
    identities: Vec<IdentityEntry>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
struct IdentityEntry {
    pub pubkey: String,
    #[serde(default)]
    pub label: Option<String>,
}

#[derive(Debug, Serialize)]
struct PlanOutput {
    schema_version: u32,
    ok: bool,
    dry_run: bool,
    target_pubkey: String,
    found: bool,
    remaining_count: usize,
    removed_count: usize,
    errors: Vec<String>,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.command {
        Command::PlanRemoveIdentity {
            map_path,
            identity_pubkey,
            output,
            apply,
        } => match plan_remove(&map_path, &identity_pubkey, &output, apply) {
            Ok(code) => ExitCode::from(code),
            Err(e) => {
                eprintln!("error: {e}");
                ExitCode::from(32)
            }
        },
    }
}

fn plan_remove(
    map_path: &PathBuf,
    identity_pubkey: &str,
    output: &PathBuf,
    apply: bool,
) -> Result<u8, String> {
    if identity_pubkey.len() != 64 || !identity_pubkey.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(31); // malformed identity
    }
    if !map_path.exists() {
        // Absent map: success no-op (architecture: absent identity exits 0)
        let plan = PlanOutput {
            schema_version: 1,
            ok: true,
            dry_run: !apply,
            target_pubkey: identity_pubkey.to_string(),
            found: false,
            remaining_count: 0,
            removed_count: 0,
            errors: vec![],
        };
        write_json(output, &plan)?;
        return Ok(0);
    }
    let raw = fs::read_to_string(map_path).map_err(|e| e.to_string())?;
    // Refuse if file appears to contain secrets
    let lower = raw.to_lowercase();
    for bad in ["nsec1", "private_key", "secret_key", "seed phrase"] {
        if lower.contains(bad) {
            return Err(format!("refusing map that appears to contain '{bad}'"));
        }
    }
    let mut map: IdentityMap = serde_json::from_str(&raw).map_err(|e| e.to_string())?;
    let before = map.identities.len();
    map.identities
        .retain(|e| e.pubkey.to_lowercase() != identity_pubkey.to_lowercase());
    let removed = before - map.identities.len();
    let plan = PlanOutput {
        schema_version: 1,
        ok: true,
        dry_run: !apply,
        target_pubkey: identity_pubkey.to_string(),
        found: removed > 0,
        remaining_count: map.identities.len(),
        removed_count: removed,
        errors: vec![],
    };
    write_json(output, &plan)?;
    if apply && removed > 0 {
        write_json(map_path, &map)?;
    }
    Ok(0)
}

fn write_json<T: Serialize>(path: &PathBuf, value: &T) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let body = serde_json::to_string_pretty(value).map_err(|e| e.to_string())?;
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, body.as_bytes()).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())?;
    Ok(())
}
