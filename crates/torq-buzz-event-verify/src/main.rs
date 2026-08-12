//! CLI for TORQ Buzz migration verification.
//!
//! Never accepts private keys via argument, environment, or file input.

use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

use clap::{Parser, Subcommand};
use torq_buzz_event_verify::verify_selected::{verify_selected_message, VerifySelectedInput};
use torq_buzz_event_verify::{
    filter_semantic_copies, parse_event_array, SemanticCopyExpectation, EXIT_IO,
};

#[derive(Parser, Debug)]
#[command(
    name = "torq-buzz-event-verify",
    about = "Narrow TORQ Buzz migration verifier (no private keys)"
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand, Debug)]
enum Command {
    /// Verify the selected migration destination message (kind 9 copy).
    VerifySelectedMessage {
        #[arg(long)]
        input: PathBuf,
        #[arg(long)]
        output: PathBuf,
    },
    /// Filter events to valid semantic copies (test / orchestrator helper).
    FilterSemanticCopies {
        #[arg(long)]
        input: PathBuf,
        #[arg(long)]
        output: PathBuf,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.command {
        Command::VerifySelectedMessage { input, output } => {
            match run_verify_selected(&input, &output) {
                Ok(code) => exit_from_i32(code),
                Err(e) => {
                    eprintln!("error: {e}");
                    exit_from_i32(EXIT_IO)
                }
            }
        }
        Command::FilterSemanticCopies { input, output } => {
            match run_filter(&input, &output) {
                Ok(()) => ExitCode::SUCCESS,
                Err(e) => {
                    eprintln!("error: {e}");
                    exit_from_i32(EXIT_IO)
                }
            }
        }
    }
}

fn run_verify_selected(input_path: &PathBuf, output_path: &PathBuf) -> Result<i32, String> {
    let raw = fs::read_to_string(input_path).map_err(|e| format!("read input: {e}"))?;
    let mut input: VerifySelectedInput =
        serde_json::from_str(&raw).map_err(|e| format!("parse input: {e}"))?;

    // Allow events_json to be a path to a JSON array file.
    if !input.events_json.trim_start().starts_with('[') {
        let events_path = input.events_json.clone();
        input.events_json =
            fs::read_to_string(&events_path).map_err(|e| format!("read events file: {e}"))?;
    }

    let result = verify_selected_message(&input);
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent).map_err(|e| format!("create output dir: {e}"))?;
    }
    let out = serde_json::to_string_pretty(&result.output)
        .map_err(|e| format!("serialize output: {e}"))?;
    atomic_write(output_path, out.as_bytes())?;
    Ok(result.exit_code)
}

#[derive(serde::Deserialize)]
struct FilterInput {
    permanent_human_pubkey: String,
    destination_channel_id: String,
    content: String,
    #[serde(default = "default_kind")]
    kind: u16,
    events_json: String,
}

fn default_kind() -> u16 {
    9
}

fn run_filter(input_path: &PathBuf, output_path: &PathBuf) -> Result<(), String> {
    let raw = fs::read_to_string(input_path).map_err(|e| format!("read input: {e}"))?;
    let mut input: FilterInput =
        serde_json::from_str(&raw).map_err(|e| format!("parse input: {e}"))?;
    if !input.events_json.trim_start().starts_with('[') {
        input.events_json = fs::read_to_string(&input.events_json)
            .map_err(|e| format!("read events file: {e}"))?;
    }
    let events = parse_event_array(&input.events_json)?;
    let mut expected = SemanticCopyExpectation::new(
        input.permanent_human_pubkey,
        input.destination_channel_id,
        input.content,
    );
    expected.kind = input.kind;
    let matches = filter_semantic_copies(&events, &expected);
    let body = serde_json::json!({
        "schema_version": 1,
        "count": matches.len(),
        "matches": matches,
    });
    let out = serde_json::to_string_pretty(&body).map_err(|e| e.to_string())?;
    if let Some(parent) = output_path.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    atomic_write(output_path, out.as_bytes())?;
    Ok(())
}

fn atomic_write(path: &PathBuf, bytes: &[u8]) -> Result<(), String> {
    let parent = path.parent().map(|p| p.to_path_buf()).unwrap_or_default();
    let tmp = parent.join(format!(
        ".{}.tmp",
        path.file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("out.json")
    ));
    fs::write(&tmp, bytes).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())?;
    Ok(())
}

fn exit_from_i32(code: i32) -> ExitCode {
    if code == 0 {
        ExitCode::SUCCESS
    } else if (1..=255).contains(&code) {
        ExitCode::from(code as u8)
    } else {
        ExitCode::from(1)
    }
}
