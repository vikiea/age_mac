use anyhow::{bail, Context, Result};
use clap::{Args, Parser, Subcommand, ValueEnum};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::env;
use std::ffi::OsStr;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

const APP_NAME: &str = "AgeMac";
const CONFIG_DIR: &str = ".age-mac";
const CONFIG_FILE: &str = "config.toml";
const DEFAULT_BUILD_SCRIPT: &str = "script/build_and_run.sh";
const DEFAULT_RELEASE_SCRIPT: &str = "scripts/release/build_dmg_release.sh";
const DEFAULT_RELEASE_DIR: &str = "pages/releases";
const DEFAULT_APP_BUNDLE: &str = "dist/AgeMac.app";
const DEFAULT_BASE_BRANCH: &str = "main";
const DEFAULT_REMOTE: &str = "origin";
static VERBOSE: AtomicBool = AtomicBool::new(false);

#[derive(Parser, Debug)]
#[command(name = "age-mac")]
#[command(about = "Build, debug, package, and release the Age Mac app")]
struct Cli {
    #[arg(long, global = true, help = "Emit stable JSON to stdout")]
    json: bool,

    #[arg(
        long,
        global = true,
        help = "Print step progress, commands, working directories, and timings to stderr"
    )]
    verbose: bool,

    #[arg(
        long,
        global = true,
        value_name = "PATH",
        help = "Age Mac repository root"
    )]
    repo: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    #[command(about = "Verify local tools, repository path, app version, and GitHub auth")]
    Doctor,
    #[command(about = "Store the default Age Mac repository path in ~/.age-mac/config.toml")]
    Init(InitArgs),
    #[command(about = "Local build, run, debug, verification, and packaging commands")]
    Dev {
        #[command(subcommand)]
        command: DevCommands,
    },
    #[command(about = "Git and GitHub PR/release commands")]
    Repo {
        #[command(subcommand)]
        command: RepoCommands,
    },
    #[command(
        about = "Raw gh escape hatch; use -- before gh args, for example: age-mac request -- release view v1.3.1"
    )]
    Request(RequestArgs),
}

#[derive(Args, Debug)]
struct InitArgs {
    #[arg(long, value_name = "PATH", help = "Repository path to store")]
    repo: Option<PathBuf>,
}

#[derive(Subcommand, Debug)]
enum DevCommands {
    #[command(about = "Build the Go engine and Swift app")]
    Build(BuildArgs),
    #[command(about = "Run the full project verification checklist")]
    Verify,
    #[command(about = "Build, stage, and launch dist/AgeMac.app")]
    Run,
    #[command(about = "Build, stage, and launch the app under lldb")]
    Debug,
    #[command(about = "Build, stage, launch, and stream process logs")]
    Logs,
    #[command(about = "Build, stage, launch, and stream subsystem telemetry logs")]
    Telemetry,
    #[command(about = "Build DMGs and Sparkle appcasts")]
    Package(PackageArgs),
    #[command(about = "Run a real engine encrypt/decrypt roundtrip")]
    Roundtrip(RoundtripArgs),
}

#[derive(Args, Debug)]
struct BuildArgs {
    #[arg(long, help = "Build Swift in release configuration")]
    release: bool,
}

#[derive(Args, Debug, Clone)]
struct PackageArgs {
    #[arg(long, value_enum, default_value_t = PackageArch::All)]
    arch: PackageArch,
    #[arg(
        long,
        value_name = "VERSION",
        help = "Override BUNDLE_VERSION for release assets"
    )]
    version: Option<String>,
}

#[derive(ValueEnum, Debug, Clone, Copy)]
enum PackageArch {
    #[value(name = "all")]
    All,
    #[value(name = "arm64")]
    Arm64,
    #[value(name = "x86_64")]
    X86_64,
    #[value(name = "universal")]
    Universal,
}

impl PackageArch {
    fn as_script_arg(self) -> &'static str {
        match self {
            PackageArch::All => "all",
            PackageArch::Arm64 => "arm64",
            PackageArch::X86_64 => "x86_64",
            PackageArch::Universal => "universal",
        }
    }
}

#[derive(Args, Debug)]
struct RoundtripArgs {
    #[arg(long, help = "Keep the temporary roundtrip directory")]
    keep_temp: bool,
}

#[derive(Subcommand, Debug)]
enum RepoCommands {
    #[command(about = "Show local branch/status and GitHub repository details")]
    Status,
    #[command(about = "Show GitHub repository metadata")]
    Info,
    #[command(about = "Commit staged, selected, or all local changes")]
    Commit(CommitArgs),
    #[command(about = "Push the current branch")]
    Push(PushArgs),
    #[command(about = "Pull request commands")]
    Pr {
        #[command(subcommand)]
        command: PrCommands,
    },
    #[command(about = "GitHub release commands")]
    Release {
        #[command(subcommand)]
        command: ReleaseCommands,
    },
    #[command(about = "Git tag commands")]
    Tag {
        #[command(subcommand)]
        command: TagCommands,
    },
}

#[derive(Args, Debug)]
struct CommitArgs {
    #[arg(short, long, value_name = "MESSAGE")]
    message: String,
    #[arg(long, help = "Stage all changes with git add -A before committing")]
    all: bool,
    #[arg(
        long = "path",
        value_name = "PATH",
        help = "Stage specific paths before committing"
    )]
    paths: Vec<PathBuf>,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Args, Debug)]
struct PushArgs {
    #[arg(
        long,
        help = "Override the push remote from config repo.default_remote"
    )]
    remote: Option<String>,
    #[arg(long, value_name = "BRANCH")]
    branch: Option<String>,
    #[arg(long, help = "Pass --set-upstream when pushing")]
    set_upstream: bool,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Subcommand, Debug)]
enum PrCommands {
    #[command(about = "Create a pull request with gh pr create")]
    Create(PrCreateArgs),
    #[command(about = "View the current or selected pull request")]
    View(PrViewArgs),
    #[command(about = "List pull requests")]
    List(PrListArgs),
}

#[derive(Args, Debug)]
struct PrCreateArgs {
    #[arg(long, value_name = "TITLE")]
    title: Option<String>,
    #[arg(long, value_name = "BODY")]
    body: Option<String>,
    #[arg(long, value_name = "PATH")]
    body_file: Option<PathBuf>,
    #[arg(long, help = "Override the base branch from config repo.default_base")]
    base: Option<String>,
    #[arg(long)]
    draft: bool,
    #[arg(long, help = "Let gh fill title/body from commits")]
    fill: bool,
    #[arg(long, help = "Open the browser after creating the PR")]
    web: bool,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Args, Debug)]
struct PrViewArgs {
    #[arg(value_name = "PR")]
    pr: Option<String>,
}

#[derive(Args, Debug)]
struct PrListArgs {
    #[arg(long, default_value_t = 20)]
    limit: u32,
}

#[derive(Subcommand, Debug)]
enum ReleaseCommands {
    #[command(about = "List GitHub releases")]
    List(ReleaseListArgs),
    #[command(about = "View a GitHub release")]
    View(ReleaseVersionArgs),
    #[command(about = "Create a GitHub release; drafts by default, use --live to publish")]
    Create(ReleaseCreateArgs),
    #[command(about = "Upload local DMG assets to an existing GitHub release")]
    Upload(ReleaseUploadArgs),
    #[command(about = "Verify local appcasts, DMGs, and GitHub release assets")]
    Verify(ReleaseVerifyArgs),
    #[command(about = "Build DMGs and create a GitHub release with assets")]
    Publish(ReleasePublishArgs),
}

#[derive(Args, Debug)]
struct ReleaseListArgs {
    #[arg(long, default_value_t = 20)]
    limit: u32,
}

#[derive(Args, Debug)]
struct ReleaseVersionArgs {
    #[arg(long, value_name = "VERSION")]
    version: String,
}

#[derive(Args, Debug)]
struct ReleaseCreateArgs {
    #[arg(long, value_name = "VERSION")]
    version: String,
    #[arg(long, value_name = "TITLE")]
    title: Option<String>,
    #[arg(long, value_name = "NOTES")]
    notes: Option<String>,
    #[arg(long, value_name = "PATH")]
    notes_file: Option<PathBuf>,
    #[arg(long = "asset", value_name = "PATH")]
    assets: Vec<PathBuf>,
    #[arg(long, help = "Create a public release instead of a draft")]
    live: bool,
    #[arg(long)]
    prerelease: bool,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Args, Debug)]
struct ReleaseVerifyArgs {
    #[arg(long, value_name = "VERSION")]
    version: String,
}

#[derive(Args, Debug)]
struct ReleaseUploadArgs {
    #[arg(long, value_name = "VERSION")]
    version: String,
    #[arg(long = "asset", value_name = "PATH")]
    assets: Vec<PathBuf>,
    #[arg(long, help = "Replace assets with the same names")]
    clobber: bool,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Args, Debug)]
struct ReleasePublishArgs {
    #[arg(long, value_name = "VERSION")]
    version: String,
    #[arg(long, value_name = "TITLE")]
    title: Option<String>,
    #[arg(long, value_name = "NOTES")]
    notes: Option<String>,
    #[arg(long, value_name = "PATH")]
    notes_file: Option<PathBuf>,
    #[arg(long, help = "Create a public release instead of a draft")]
    live: bool,
    #[arg(long)]
    prerelease: bool,
    #[arg(
        long,
        help = "Use existing pages/releases assets instead of rebuilding DMGs"
    )]
    skip_package: bool,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Subcommand, Debug)]
enum TagCommands {
    #[command(about = "Create an annotated version tag")]
    Create(TagCreateArgs),
}

#[derive(Args, Debug)]
struct TagCreateArgs {
    #[arg(long, value_name = "VERSION")]
    version: String,
    #[arg(long, value_name = "MESSAGE")]
    message: Option<String>,
    #[arg(long)]
    dry_run: bool,
}

#[derive(Args, Debug)]
struct RequestArgs {
    #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
    args: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct Config {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    default_repo: Option<String>,
    #[serde(default)]
    repo: RepoConfig,
    #[serde(default)]
    paths: PathConfig,
    #[serde(default)]
    tools: ToolConfig,
    #[serde(default)]
    release: ReleaseConfig,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct RepoConfig {
    default_repo: Option<String>,
    default_base: Option<String>,
    default_remote: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct PathConfig {
    build_script: Option<String>,
    release_script: Option<String>,
    release_dir: Option<String>,
    app_bundle: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct ToolConfig {
    swift: Option<String>,
    go: Option<String>,
    git: Option<String>,
    gh: Option<String>,
    hdiutil: Option<String>,
    codesign: Option<String>,
    lldb: Option<String>,
    xmllint: Option<String>,
    lipo: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct ReleaseConfig {
    asset_name: Option<String>,
    display_name: Option<String>,
}

#[derive(Debug)]
struct RepoContext {
    root: PathBuf,
    config: Config,
}

#[derive(Debug)]
struct CmdSpec {
    name: String,
    program: String,
    args: Vec<String>,
    cwd: PathBuf,
    envs: Vec<(String, String)>,
    env_remove: Vec<String>,
}

#[derive(Debug, Serialize)]
struct StepReport {
    name: String,
    command: Vec<String>,
    cwd: String,
    status: i32,
    ok: bool,
    stdout: String,
    stderr: String,
}

impl Config {
    fn default_repo_path(&self) -> Option<&str> {
        self.repo
            .default_repo
            .as_deref()
            .or(self.default_repo.as_deref())
    }

    fn default_base(&self) -> &str {
        self.repo
            .default_base
            .as_deref()
            .unwrap_or(DEFAULT_BASE_BRANCH)
    }

    fn default_remote(&self) -> &str {
        self.repo
            .default_remote
            .as_deref()
            .unwrap_or(DEFAULT_REMOTE)
    }

    fn fill_missing_defaults(&mut self) {
        self.default_repo = None;
        self.repo
            .default_base
            .get_or_insert_with(|| DEFAULT_BASE_BRANCH.to_string());
        self.repo
            .default_remote
            .get_or_insert_with(|| DEFAULT_REMOTE.to_string());
        self.paths
            .build_script
            .get_or_insert_with(|| DEFAULT_BUILD_SCRIPT.to_string());
        self.paths
            .release_script
            .get_or_insert_with(|| DEFAULT_RELEASE_SCRIPT.to_string());
        self.paths
            .release_dir
            .get_or_insert_with(|| DEFAULT_RELEASE_DIR.to_string());
        self.paths
            .app_bundle
            .get_or_insert_with(|| DEFAULT_APP_BUNDLE.to_string());
        self.tools.swift.get_or_insert_with(|| "swift".to_string());
        self.tools.go.get_or_insert_with(|| "go".to_string());
        self.tools.git.get_or_insert_with(|| "git".to_string());
        self.tools.gh.get_or_insert_with(|| "gh".to_string());
        self.tools
            .hdiutil
            .get_or_insert_with(|| "hdiutil".to_string());
        self.tools
            .codesign
            .get_or_insert_with(|| "codesign".to_string());
        self.tools.lldb.get_or_insert_with(|| "lldb".to_string());
        self.tools
            .xmllint
            .get_or_insert_with(|| "xmllint".to_string());
        self.tools.lipo.get_or_insert_with(|| "lipo".to_string());
        self.release
            .asset_name
            .get_or_insert_with(|| APP_NAME.to_string());
        self.release
            .display_name
            .get_or_insert_with(|| "Age Mac".to_string());
    }
}

impl PathConfig {
    fn build_script(&self) -> &str {
        self.build_script.as_deref().unwrap_or(DEFAULT_BUILD_SCRIPT)
    }

    fn release_script(&self) -> &str {
        self.release_script
            .as_deref()
            .unwrap_or(DEFAULT_RELEASE_SCRIPT)
    }

    fn release_dir(&self) -> &str {
        self.release_dir.as_deref().unwrap_or(DEFAULT_RELEASE_DIR)
    }

    fn app_bundle(&self) -> &str {
        self.app_bundle.as_deref().unwrap_or(DEFAULT_APP_BUNDLE)
    }
}

impl ToolConfig {
    fn swift(&self) -> &str {
        self.swift.as_deref().unwrap_or("swift")
    }

    fn go(&self) -> &str {
        self.go.as_deref().unwrap_or("go")
    }

    fn git(&self) -> &str {
        self.git.as_deref().unwrap_or("git")
    }

    fn gh(&self) -> &str {
        self.gh.as_deref().unwrap_or("gh")
    }

    fn hdiutil(&self) -> &str {
        self.hdiutil.as_deref().unwrap_or("hdiutil")
    }

    fn codesign(&self) -> &str {
        self.codesign.as_deref().unwrap_or("codesign")
    }

    fn lldb(&self) -> &str {
        self.lldb.as_deref().unwrap_or("lldb")
    }

    fn xmllint(&self) -> &str {
        self.xmllint.as_deref().unwrap_or("xmllint")
    }

    fn lipo(&self) -> &str {
        self.lipo.as_deref().unwrap_or("lipo")
    }

    fn entries(&self) -> [(&'static str, &str); 9] {
        [
            ("swift", self.swift()),
            ("go", self.go()),
            ("git", self.git()),
            ("gh", self.gh()),
            ("hdiutil", self.hdiutil()),
            ("codesign", self.codesign()),
            ("lldb", self.lldb()),
            ("xmllint", self.xmllint()),
            ("lipo", self.lipo()),
        ]
    }
}

impl ReleaseConfig {
    fn asset_name(&self) -> &str {
        self.asset_name.as_deref().unwrap_or(APP_NAME)
    }

    fn display_name(&self) -> &str {
        self.display_name.as_deref().unwrap_or("Age Mac")
    }
}

fn main() {
    let cli = Cli::parse();
    let action = cli.action_name();
    let json_mode = cli.json;

    match run(cli) {
        Ok(value) => {
            if json_mode {
                print_json(&value);
            }
        }
        Err(error) => {
            if json_mode {
                print_json(&json!({
                    "ok": false,
                    "action": action,
                    "error": format!("{:#}", error),
                }));
            } else {
                eprintln!("error: {:#}", error);
            }
            std::process::exit(1);
        }
    }
}

impl Cli {
    fn action_name(&self) -> String {
        match &self.command {
            Commands::Doctor => "doctor".to_string(),
            Commands::Init(_) => "init".to_string(),
            Commands::Dev { command } => format!("dev {}", command.name()),
            Commands::Repo { command } => format!("repo {}", command.name()),
            Commands::Request(_) => "request".to_string(),
        }
    }
}

impl DevCommands {
    fn name(&self) -> &'static str {
        match self {
            DevCommands::Build(_) => "build",
            DevCommands::Verify => "verify",
            DevCommands::Run => "run",
            DevCommands::Debug => "debug",
            DevCommands::Logs => "logs",
            DevCommands::Telemetry => "telemetry",
            DevCommands::Package(_) => "package",
            DevCommands::Roundtrip(_) => "roundtrip",
        }
    }
}

impl RepoCommands {
    fn name(&self) -> &'static str {
        match self {
            RepoCommands::Status => "status",
            RepoCommands::Info => "info",
            RepoCommands::Commit(_) => "commit",
            RepoCommands::Push(_) => "push",
            RepoCommands::Pr { .. } => "pr",
            RepoCommands::Release { .. } => "release",
            RepoCommands::Tag { .. } => "tag",
        }
    }
}

fn run(cli: Cli) -> Result<Value> {
    VERBOSE.store(cli.verbose, Ordering::Relaxed);
    match &cli.command {
        Commands::Doctor => doctor(&cli),
        Commands::Init(args) => init(&cli, args),
        Commands::Dev { command } => {
            let repo = RepoContext::resolve(&cli)?;
            run_dev_command(&repo, command, cli.json)
        }
        Commands::Repo { command } => {
            let repo = RepoContext::resolve(&cli)?;
            run_repo_command(&repo, command, cli.json)
        }
        Commands::Request(args) => {
            let repo = RepoContext::resolve(&cli)?;
            run_request(&repo, args, cli.json)
        }
    }
}

fn doctor(cli: &Cli) -> Result<Value> {
    let repo_result = RepoContext::resolve(cli);
    let config = repo_result
        .as_ref()
        .map(|ctx| ctx.config.clone())
        .unwrap_or_else(|_| read_config().unwrap_or_default());
    let version = repo_result.as_ref().ok().and_then(read_bundle_version);

    let tool_names = config.tools.entries();
    let checks: Vec<Value> = tool_names
        .iter()
        .map(|(name, tool)| {
            let path = command_path(tool);
            json!({
                "name": name,
                "command": tool,
                "ok": path.is_some(),
                "path": path,
            })
        })
        .collect();

    let github_auth = github_auth_status(config.tools.gh());
    let repo_check = match &repo_result {
        Ok(ctx) => json!({
            "ok": true,
            "path": ctx.root,
            "source": "resolved",
        }),
        Err(error) => json!({
            "ok": false,
            "error": format!("{:#}", error),
        }),
    };

    let gh_repo = if let Ok(ctx) = &repo_result {
        capture_json(
            CmdSpec::new("gh repo view", ctx.config.tools.gh(), &ctx.root).args([
                "repo",
                "view",
                "--json",
                "nameWithOwner,url,defaultBranchRef,isPrivate",
            ]),
        )
        .ok()
    } else {
        None
    };

    let ok = repo_result.is_ok()
        && checks
            .iter()
            .all(|check| check["ok"].as_bool().unwrap_or(false))
        && github_auth["available"].as_bool().unwrap_or(false);

    let value = json!({
        "ok": ok,
        "action": "doctor",
        "repo": repo_check,
        "bundle_version": version,
        "github_auth": github_auth,
        "github_repo": gh_repo,
        "checks": checks,
        "config_path": config_path(),
        "config": config_summary(&config),
    });

    if !cli.json {
        print_doctor_human(&value);
    }

    Ok(value)
}

fn init(cli: &Cli, args: &InitArgs) -> Result<Value> {
    let mut config = read_config().unwrap_or_default();
    let repo = match &args.repo {
        Some(path) => validate_repo_root(path.clone(), &config)?,
        None => RepoContext::resolve(cli)?.root,
    };

    let path = config_path();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create config directory {}", parent.display()))?;
    }

    config.default_repo = None;
    config.repo.default_repo = Some(repo.to_string_lossy().to_string());
    config.fill_missing_defaults();
    let text = toml::to_string_pretty(&config)?;
    fs::write(&path, text).with_context(|| format!("failed to write {}", path.display()))?;

    if !cli.json {
        println!(
            "Stored default repo {} in {}",
            repo.display(),
            path.display()
        );
    }

    Ok(json!({
        "ok": true,
        "action": "init",
        "repo": repo,
        "config_path": path,
    }))
}

fn run_dev_command(repo: &RepoContext, command: &DevCommands, json_mode: bool) -> Result<Value> {
    match command {
        DevCommands::Build(args) => dev_build(repo, args, json_mode),
        DevCommands::Verify => dev_verify(repo, json_mode),
        DevCommands::Run => run_build_script(repo, "run", "dev run", json_mode),
        DevCommands::Debug => {
            ensure_not_json_stream(json_mode, "dev debug")?;
            run_build_script(repo, "debug", "dev debug", json_mode)
        }
        DevCommands::Logs => {
            ensure_not_json_stream(json_mode, "dev logs")?;
            run_build_script(repo, "logs", "dev logs", json_mode)
        }
        DevCommands::Telemetry => {
            ensure_not_json_stream(json_mode, "dev telemetry")?;
            run_build_script(repo, "telemetry", "dev telemetry", json_mode)
        }
        DevCommands::Package(args) => dev_package(repo, args, json_mode),
        DevCommands::Roundtrip(args) => dev_roundtrip(repo, args, json_mode),
    }
}

fn dev_build(repo: &RepoContext, args: &BuildArgs, json_mode: bool) -> Result<Value> {
    let mut steps = Vec::new();
    steps.push(run_step(
        CmdSpec::new(
            "go build engine",
            repo.config.tools.go(),
            repo.root.join("Engine"),
        )
        .args(["build", "-o", "age-engine", "."])
        .env_remove("GOROOT"),
        json_mode,
    )?);

    let mut swift_args = vec!["build".to_string()];
    if args.release {
        swift_args.extend(["-c".to_string(), "release".to_string()]);
    }
    steps.push(run_step(
        CmdSpec::new("swift build", repo.config.tools.swift(), &repo.root).args(swift_args),
        json_mode,
    )?);

    if !json_mode {
        println!("Build complete.");
    }

    Ok(json!({
        "ok": true,
        "action": "dev build",
        "repo": repo.root,
        "steps": steps,
    }))
}

fn dev_verify(repo: &RepoContext, json_mode: bool) -> Result<Value> {
    let mut steps = Vec::new();
    steps.push(run_step(
        CmdSpec::new("swift build", repo.config.tools.swift(), &repo.root).args(["build"]),
        json_mode,
    )?);
    steps.push(run_step(
        CmdSpec::new(
            "go test engine",
            repo.config.tools.go(),
            repo.root.join("Engine"),
        )
        .args(["test", "./..."])
        .env_remove("GOROOT"),
        json_mode,
    )?);
    steps.push(run_step(
        CmdSpec::new("build and launch verify", script_path(repo), &repo.root).args(["--verify"]),
        json_mode,
    )?);
    steps.push(run_step(
        CmdSpec::new("git diff check", repo.config.tools.git(), &repo.root)
            .args(["diff", "--check"]),
        json_mode,
    )?);
    steps.push(run_step(
        CmdSpec::new("codesign verify", repo.config.tools.codesign(), &repo.root).args([
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            path_string(app_bundle_path(repo)).as_str(),
        ]),
        json_mode,
    )?);

    if !json_mode {
        println!("Verification complete.");
    }

    Ok(json!({
        "ok": true,
        "action": "dev verify",
        "repo": repo.root,
        "steps": steps,
    }))
}

fn run_build_script(
    repo: &RepoContext,
    mode: &str,
    action: &str,
    json_mode: bool,
) -> Result<Value> {
    let step = run_step(
        CmdSpec::new(action, script_path(repo), &repo.root).args([mode]),
        json_mode,
    )?;
    Ok(json!({
        "ok": true,
        "action": action,
        "repo": repo.root,
        "steps": [step],
    }))
}

fn dev_package(repo: &RepoContext, args: &PackageArgs, json_mode: bool) -> Result<Value> {
    let mut spec = CmdSpec::new(
        "build release assets",
        release_script_path(repo),
        &repo.root,
    )
    .args([args.arch.as_script_arg()]);
    if let Some(version) = &args.version {
        spec = spec.env("BUNDLE_VERSION", normalize_version_plain(version));
    }
    let step = run_step(spec, json_mode)?;
    let version = args
        .version
        .as_ref()
        .map(|value| normalize_version_plain(value))
        .or_else(|| read_bundle_version(repo))
        .unwrap_or_else(|| "unknown".to_string());
    let assets = find_release_assets(repo, &version).unwrap_or_default();

    if !json_mode {
        println!("Release assets ready for version {}.", version);
    }

    Ok(json!({
        "ok": true,
        "action": "dev package",
        "repo": repo.root,
        "version": version,
        "assets": assets,
        "steps": [step],
    }))
}

fn dev_roundtrip(repo: &RepoContext, args: &RoundtripArgs, json_mode: bool) -> Result<Value> {
    let mut steps = Vec::new();
    steps.push(run_step(
        CmdSpec::new(
            "go build engine",
            repo.config.tools.go(),
            repo.root.join("Engine"),
        )
        .args(["build", "-o", "age-engine", "."])
        .env_remove("GOROOT"),
        json_mode,
    )?);

    let temp = create_temp_dir("age-mac-roundtrip")?;
    let input = temp.join("in");
    let output = temp.join("out");
    fs::create_dir_all(&input)?;
    fs::create_dir_all(&output)?;
    fs::write(input.join("a.txt"), "hello age mac\n")?;
    fs::write(input.join("b.txt"), "second file\n")?;

    let files_json = temp.join("files.json");
    let secret_file = temp.join("secret.txt");
    let enc_files_json = temp.join("enc-files.json");
    let file_list = json!([
        {"path": input.join("a.txt"), "name": "a.txt"},
        {"path": input.join("b.txt"), "name": "b.txt"}
    ]);
    fs::write(&files_json, serde_json::to_vec(&file_list)?)?;
    fs::write(&secret_file, "test-passphrase")?;

    let engine = repo.root.join("Engine/age-engine");
    steps.push(run_step(
        CmdSpec::new("engine encrypt batch", &engine, &repo.root).args([
            "encrypt-batch",
            "--files-json",
            path_string(&files_json).as_str(),
            "--output-dir",
            path_string(&output).as_str(),
            "--output-name",
            "sample.tar.gz.age",
            "--compress=true",
            "--auth",
            "passphrase",
            "--secret-file",
            path_string(&secret_file).as_str(),
            "--duplicate",
            "overwrite",
        ]),
        json_mode,
    )?);

    let encrypted = output.join("encrypted/sample.tar.gz.age");
    let enc_list = json!([{"path": encrypted, "name": "sample.tar.gz.age"}]);
    fs::write(&enc_files_json, serde_json::to_vec(&enc_list)?)?;

    steps.push(run_step(
        CmdSpec::new("engine decrypt", &engine, &repo.root).args([
            "decrypt",
            "--files-json",
            path_string(&enc_files_json).as_str(),
            "--output-dir",
            path_string(&output).as_str(),
            "--auth",
            "passphrase",
            "--secret-file",
            path_string(&secret_file).as_str(),
            "--duplicate",
            "overwrite",
        ]),
        json_mode,
    )?);

    compare_files(&input.join("a.txt"), &output.join("decrypted/a.txt"))?;
    compare_files(&input.join("b.txt"), &output.join("decrypted/b.txt"))?;

    let temp_path = temp.clone();
    if !args.keep_temp {
        fs::remove_dir_all(&temp)?;
    }

    if !json_mode {
        println!("Engine roundtrip complete.");
    }

    Ok(json!({
        "ok": true,
        "action": "dev roundtrip",
        "repo": repo.root,
        "temp_dir": temp_path,
        "kept_temp": args.keep_temp,
        "steps": steps,
    }))
}

fn run_repo_command(repo: &RepoContext, command: &RepoCommands, json_mode: bool) -> Result<Value> {
    match command {
        RepoCommands::Status => repo_status(repo, json_mode),
        RepoCommands::Info => repo_info(repo, json_mode),
        RepoCommands::Commit(args) => repo_commit(repo, args, json_mode),
        RepoCommands::Push(args) => repo_push(repo, args, json_mode),
        RepoCommands::Pr { command } => run_pr_command(repo, command, json_mode),
        RepoCommands::Release { command } => run_release_command(repo, command, json_mode),
        RepoCommands::Tag { command } => run_tag_command(repo, command, json_mode),
    }
}

fn repo_status(repo: &RepoContext, json_mode: bool) -> Result<Value> {
    let status = capture_text(
        CmdSpec::new("git status", repo.config.tools.git(), &repo.root)
            .args(["status", "--short", "--branch"]),
    )?;
    let branch = capture_text(
        CmdSpec::new("git branch", repo.config.tools.git(), &repo.root).args([
            "rev-parse",
            "--abbrev-ref",
            "HEAD",
        ]),
    )?
    .trim()
    .to_string();
    let gh_repo = capture_json(
        CmdSpec::new("gh repo view", repo.config.tools.gh(), &repo.root).args([
            "repo",
            "view",
            "--json",
            "nameWithOwner,url,defaultBranchRef,isPrivate",
        ]),
    )
    .ok();
    let value = json!({
        "ok": true,
        "action": "repo status",
        "repo": repo.root,
        "branch": branch,
        "status": status,
        "github_repo": gh_repo,
    });
    if !json_mode {
        println!("{}", value["status"].as_str().unwrap_or_default());
        if let Some(url) = value["github_repo"]["url"].as_str() {
            println!("GitHub: {}", url);
        }
    }
    Ok(value)
}

fn repo_info(repo: &RepoContext, json_mode: bool) -> Result<Value> {
    let info = capture_json(
        CmdSpec::new("gh repo view", repo.config.tools.gh(), &repo.root).args([
            "repo",
            "view",
            "--json",
            "nameWithOwner,url,defaultBranchRef,isPrivate",
        ]),
    )?;
    let value = json!({
        "ok": true,
        "action": "repo info",
        "repo": repo.root,
        "github_repo": info,
    });
    if !json_mode {
        println!("{}", serde_json::to_string_pretty(&value["github_repo"])?);
    }
    Ok(value)
}

fn repo_commit(repo: &RepoContext, args: &CommitArgs, json_mode: bool) -> Result<Value> {
    if args.all && !args.paths.is_empty() {
        bail!("use either --all or --path, not both");
    }
    if args.message.trim().is_empty() {
        bail!("commit message cannot be empty");
    }

    let mut commands = Vec::new();
    if args.all {
        commands.push(vec![
            repo.config.tools.git().to_string(),
            "add".to_string(),
            "-A".to_string(),
        ]);
    } else if !args.paths.is_empty() {
        let mut add = vec![
            repo.config.tools.git().to_string(),
            "add".to_string(),
            "--".to_string(),
        ];
        add.extend(args.paths.iter().map(path_string));
        commands.push(add);
    }
    commands.push(vec![
        repo.config.tools.git().to_string(),
        "commit".to_string(),
        "-m".to_string(),
        args.message.clone(),
    ]);

    if args.dry_run {
        return dry_run_value("repo commit", repo, commands, json_mode);
    }

    let mut steps = Vec::new();
    if args.all {
        steps.push(run_step(
            CmdSpec::new("git add all", repo.config.tools.git(), &repo.root).args(["add", "-A"]),
            json_mode,
        )?);
    } else if !args.paths.is_empty() {
        let mut add_args = vec!["add".to_string(), "--".to_string()];
        add_args.extend(args.paths.iter().map(path_string));
        steps.push(run_step(
            CmdSpec::new("git add paths", repo.config.tools.git(), &repo.root).args(add_args),
            json_mode,
        )?);
    }
    steps.push(run_step(
        CmdSpec::new("git commit", repo.config.tools.git(), &repo.root).args([
            "commit",
            "-m",
            &args.message,
        ]),
        json_mode,
    )?);

    Ok(json!({
        "ok": true,
        "action": "repo commit",
        "repo": repo.root,
        "steps": steps,
    }))
}

fn repo_push(repo: &RepoContext, args: &PushArgs, json_mode: bool) -> Result<Value> {
    let branch = match &args.branch {
        Some(branch) => branch.clone(),
        None => capture_text(
            CmdSpec::new("git branch", repo.config.tools.git(), &repo.root).args([
                "rev-parse",
                "--abbrev-ref",
                "HEAD",
            ]),
        )?
        .trim()
        .to_string(),
    };

    let mut push_args = vec!["push".to_string()];
    if args.set_upstream {
        push_args.push("--set-upstream".to_string());
    }
    push_args.push(
        args.remote
            .clone()
            .unwrap_or_else(|| repo.config.default_remote().to_string()),
    );
    if branch != "HEAD" {
        push_args.push(branch.clone());
    }

    let command = command_vec(repo.config.tools.git(), &push_args);
    if args.dry_run {
        return dry_run_value("repo push", repo, vec![command], json_mode);
    }

    let step = run_step(
        CmdSpec::new("git push", repo.config.tools.git(), &repo.root).args(push_args),
        json_mode,
    )?;

    Ok(json!({
        "ok": true,
        "action": "repo push",
        "repo": repo.root,
        "branch": branch,
        "steps": [step],
    }))
}

fn run_pr_command(repo: &RepoContext, command: &PrCommands, json_mode: bool) -> Result<Value> {
    match command {
        PrCommands::Create(args) => pr_create(repo, args, json_mode),
        PrCommands::View(args) => pr_view(repo, args, json_mode),
        PrCommands::List(args) => pr_list(repo, args, json_mode),
    }
}

fn pr_create(repo: &RepoContext, args: &PrCreateArgs, json_mode: bool) -> Result<Value> {
    if !args.fill && args.title.is_none() {
        bail!("provide --title or use --fill");
    }
    if args.body.is_some() && args.body_file.is_some() {
        bail!("use either --body or --body-file, not both");
    }

    let mut gh_args = vec![
        "pr".to_string(),
        "create".to_string(),
        "--base".to_string(),
        args.base
            .clone()
            .unwrap_or_else(|| repo.config.default_base().to_string()),
    ];
    if args.fill {
        gh_args.push("--fill".to_string());
    }
    if let Some(title) = &args.title {
        gh_args.extend(["--title".to_string(), title.clone()]);
    }
    if let Some(body) = &args.body {
        gh_args.extend(["--body".to_string(), body.clone()]);
    }
    if let Some(file) = &args.body_file {
        ensure_file_exists(file)?;
        gh_args.extend(["--body-file".to_string(), path_string(file)]);
    }
    if args.draft {
        gh_args.push("--draft".to_string());
    }
    if args.web {
        gh_args.push("--web".to_string());
    }

    let command = command_vec(repo.config.tools.gh(), &gh_args);
    if args.dry_run {
        return dry_run_value("repo pr create", repo, vec![command], json_mode);
    }

    let step = run_step(
        CmdSpec::new("gh pr create", repo.config.tools.gh(), &repo.root).args(gh_args),
        json_mode,
    )?;
    Ok(json!({
        "ok": true,
        "action": "repo pr create",
        "repo": repo.root,
        "steps": [step],
    }))
}

fn pr_view(repo: &RepoContext, args: &PrViewArgs, json_mode: bool) -> Result<Value> {
    let mut gh_args = vec![
        "pr".to_string(),
        "view".to_string(),
        "--json".to_string(),
        "number,title,state,url,headRefName,baseRefName,isDraft,mergeable".to_string(),
    ];
    if let Some(pr) = &args.pr {
        gh_args.insert(2, pr.clone());
    }
    let value =
        capture_json(CmdSpec::new("gh pr view", repo.config.tools.gh(), &repo.root).args(gh_args))?;
    let out = json!({
        "ok": true,
        "action": "repo pr view",
        "repo": repo.root,
        "pull_request": value,
    });
    if !json_mode {
        println!("{}", serde_json::to_string_pretty(&out["pull_request"])?);
    }
    Ok(out)
}

fn pr_list(repo: &RepoContext, args: &PrListArgs, json_mode: bool) -> Result<Value> {
    let value = capture_json(
        CmdSpec::new("gh pr list", repo.config.tools.gh(), &repo.root).args([
            "pr",
            "list",
            "--limit",
            &args.limit.to_string(),
            "--json",
            "number,title,state,url,headRefName,baseRefName,isDraft",
        ]),
    )?;
    let out = json!({
        "ok": true,
        "action": "repo pr list",
        "repo": repo.root,
        "pull_requests": value,
    });
    if !json_mode {
        println!("{}", serde_json::to_string_pretty(&out["pull_requests"])?);
    }
    Ok(out)
}

fn run_release_command(
    repo: &RepoContext,
    command: &ReleaseCommands,
    json_mode: bool,
) -> Result<Value> {
    match command {
        ReleaseCommands::List(args) => release_list(repo, args, json_mode),
        ReleaseCommands::View(args) => release_view(repo, &args.version, json_mode),
        ReleaseCommands::Create(args) => release_create(repo, args, json_mode),
        ReleaseCommands::Upload(args) => release_upload(repo, args, json_mode),
        ReleaseCommands::Verify(args) => release_verify(repo, args, json_mode),
        ReleaseCommands::Publish(args) => release_publish(repo, args, json_mode),
    }
}

fn release_list(repo: &RepoContext, args: &ReleaseListArgs, json_mode: bool) -> Result<Value> {
    let value = capture_json(
        CmdSpec::new("gh release list", repo.config.tools.gh(), &repo.root).args([
            "release",
            "list",
            "--limit",
            &args.limit.to_string(),
            "--json",
            "tagName,name,isDraft,isPrerelease,publishedAt,url",
        ]),
    )?;
    let out = json!({
        "ok": true,
        "action": "repo release list",
        "repo": repo.root,
        "releases": value,
    });
    if !json_mode {
        println!("{}", serde_json::to_string_pretty(&out["releases"])?);
    }
    Ok(out)
}

fn release_view(repo: &RepoContext, version: &str, json_mode: bool) -> Result<Value> {
    let tag = normalize_tag(version);
    let value = capture_json(
        CmdSpec::new("gh release view", repo.config.tools.gh(), &repo.root).args([
            "release",
            "view",
            &tag,
            "--json",
            "tagName,name,isDraft,isPrerelease,url,assets",
        ]),
    )?;
    let out = json!({
        "ok": true,
        "action": "repo release view",
        "repo": repo.root,
        "release": value,
    });
    if !json_mode {
        println!("{}", serde_json::to_string_pretty(&out["release"])?);
    }
    Ok(out)
}

fn release_create(repo: &RepoContext, args: &ReleaseCreateArgs, json_mode: bool) -> Result<Value> {
    ensure_assets_exist(&args.assets)?;
    let gh_args = release_create_args(
        &repo.config,
        &args.version,
        args.title.as_deref(),
        args.notes.as_deref(),
        args.notes_file.as_ref(),
        args.live,
        args.prerelease,
        &args.assets,
    )?;
    let command = command_vec(repo.config.tools.gh(), &gh_args);
    if args.dry_run {
        return dry_run_value("repo release create", repo, vec![command], json_mode);
    }
    let step = run_step(
        CmdSpec::new("gh release create", repo.config.tools.gh(), &repo.root).args(gh_args),
        json_mode,
    )?;
    Ok(json!({
        "ok": true,
        "action": "repo release create",
        "repo": repo.root,
        "tag": normalize_tag(&args.version),
        "draft": !args.live,
        "steps": [step],
    }))
}

fn release_verify(repo: &RepoContext, args: &ReleaseVerifyArgs, json_mode: bool) -> Result<Value> {
    let version = normalize_version_plain(&args.version);
    let tag = normalize_tag(&version);
    let assets = find_release_assets(repo, &version)?;
    ensure_assets_exist(&assets)?;

    let appcasts = appcast_paths(repo);
    for appcast in &appcasts {
        ensure_file_exists(appcast)?;
    }

    let mut steps = Vec::new();
    let mut xmllint_args = vec!["--noout".to_string()];
    xmllint_args.extend(appcasts.iter().map(path_string));
    steps.push(run_step(
        CmdSpec::new("verify appcasts", repo.config.tools.xmllint(), &repo.root).args(xmllint_args),
        json_mode,
    )?);

    for asset in &assets {
        steps.push(run_step(
            CmdSpec::new("verify dmg", repo.config.tools.hdiutil(), &repo.root)
                .args(["verify".to_string(), path_string(asset)]),
            json_mode,
        )?);
    }

    let gh_args = vec![
        "release".to_string(),
        "view".to_string(),
        tag.clone(),
        "--json".to_string(),
        "tagName,name,isDraft,isPrerelease,url,assets".to_string(),
    ];
    let release_step = run_step_captured(
        CmdSpec::new("gh release view", repo.config.tools.gh(), &repo.root).args(gh_args),
    )?;
    let release = serde_json::from_str::<Value>(&release_step.stdout)
        .context("failed to parse release JSON")?;
    steps.push(release_step);

    if release["tagName"].as_str() != Some(tag.as_str()) {
        bail!(
            "GitHub release tag mismatch: expected {}, got {}",
            tag,
            release["tagName"].as_str().unwrap_or("<missing>")
        );
    }

    let asset_checks = verify_release_asset_metadata(&assets, &release)?;

    if !json_mode {
        println!("Release {} verified.", tag);
    }

    Ok(json!({
        "ok": true,
        "action": "repo release verify",
        "repo": repo.root,
        "tag": tag,
        "appcasts": appcasts,
        "assets": asset_checks,
        "release": release,
        "steps": steps,
    }))
}

fn release_upload(repo: &RepoContext, args: &ReleaseUploadArgs, json_mode: bool) -> Result<Value> {
    let version = normalize_version_plain(&args.version);
    let assets = if args.assets.is_empty() {
        find_release_assets(repo, &version)?
    } else {
        args.assets.clone()
    };
    ensure_assets_exist(&assets)?;

    let mut gh_args = vec![
        "release".to_string(),
        "upload".to_string(),
        normalize_tag(&version),
    ];
    gh_args.extend(assets.iter().map(path_string));
    if args.clobber {
        gh_args.push("--clobber".to_string());
    }

    let command = command_vec(repo.config.tools.gh(), &gh_args);
    if args.dry_run {
        return dry_run_value("repo release upload", repo, vec![command], json_mode);
    }
    let step = run_step(
        CmdSpec::new("gh release upload", repo.config.tools.gh(), &repo.root).args(gh_args),
        json_mode,
    )?;
    Ok(json!({
        "ok": true,
        "action": "repo release upload",
        "repo": repo.root,
        "tag": normalize_tag(&version),
        "assets": assets,
        "steps": [step],
    }))
}

fn release_publish(
    repo: &RepoContext,
    args: &ReleasePublishArgs,
    json_mode: bool,
) -> Result<Value> {
    let version = normalize_version_plain(&args.version);
    let mut commands = Vec::new();
    if !args.skip_package {
        commands.push(vec![
            "env".to_string(),
            format!("BUNDLE_VERSION={}", version),
            path_string(&release_script_path(repo)),
            "all".to_string(),
        ]);
    }
    let existing_assets = if args.skip_package {
        find_release_assets(repo, &version)?
    } else {
        find_release_assets(repo, &version).unwrap_or_default()
    };
    let create_args = release_create_args(
        &repo.config,
        &version,
        args.title.as_deref(),
        args.notes.as_deref(),
        args.notes_file.as_ref(),
        args.live,
        args.prerelease,
        &existing_assets,
    )?;
    commands.push(command_vec(repo.config.tools.gh(), &create_args));

    if args.dry_run {
        return dry_run_value("repo release publish", repo, commands, json_mode);
    }

    let mut steps = Vec::new();
    if !args.skip_package {
        steps.push(run_step(
            CmdSpec::new(
                "build release assets",
                release_script_path(repo),
                &repo.root,
            )
            .args(["all"])
            .env("BUNDLE_VERSION", &version),
            json_mode,
        )?);
    }
    let assets = find_release_assets(repo, &version)?;
    let gh_args = release_create_args(
        &repo.config,
        &version,
        args.title.as_deref(),
        args.notes.as_deref(),
        args.notes_file.as_ref(),
        args.live,
        args.prerelease,
        &assets,
    )?;
    steps.push(run_step(
        CmdSpec::new("gh release create", repo.config.tools.gh(), &repo.root).args(gh_args),
        json_mode,
    )?);

    Ok(json!({
        "ok": true,
        "action": "repo release publish",
        "repo": repo.root,
        "tag": normalize_tag(&version),
        "draft": !args.live,
        "assets": assets,
        "steps": steps,
    }))
}

fn run_tag_command(repo: &RepoContext, command: &TagCommands, json_mode: bool) -> Result<Value> {
    match command {
        TagCommands::Create(args) => tag_create(repo, args, json_mode),
    }
}

fn tag_create(repo: &RepoContext, args: &TagCreateArgs, json_mode: bool) -> Result<Value> {
    let tag = normalize_tag(&args.version);
    let message = args.message.clone().unwrap_or_else(|| {
        format!(
            "{} {}",
            repo.config.release.display_name(),
            normalize_version_plain(&args.version)
        )
    });
    let git_args = vec![
        "tag".to_string(),
        "-a".to_string(),
        tag.clone(),
        "-m".to_string(),
        message,
    ];
    let command = command_vec(repo.config.tools.git(), &git_args);
    if args.dry_run {
        return dry_run_value("repo tag create", repo, vec![command], json_mode);
    }
    let step = run_step(
        CmdSpec::new("git tag create", repo.config.tools.git(), &repo.root).args(git_args),
        json_mode,
    )?;
    Ok(json!({
        "ok": true,
        "action": "repo tag create",
        "repo": repo.root,
        "tag": tag,
        "steps": [step],
    }))
}

fn run_request(repo: &RepoContext, args: &RequestArgs, json_mode: bool) -> Result<Value> {
    if args.args.is_empty() {
        bail!("provide gh arguments after --, for example: age-mac request -- release view v1.3.1");
    }
    let gh_args = if args.args.first().map(String::as_str) == Some("gh") {
        args.args[1..].to_vec()
    } else {
        args.args.clone()
    };
    if gh_args.is_empty() {
        bail!("provide gh arguments after the optional gh prefix");
    }

    let step = run_step(
        CmdSpec::new("gh request", repo.config.tools.gh(), &repo.root).args(gh_args),
        json_mode,
    )?;
    let provider_json = serde_json::from_str::<Value>(&step.stdout).ok();
    Ok(json!({
        "ok": true,
        "action": "request",
        "repo": repo.root,
        "provider_json": provider_json,
        "steps": [step],
    }))
}

impl RepoContext {
    fn resolve(cli: &Cli) -> Result<Self> {
        let config = read_config()?;
        if let Some(path) = &cli.repo {
            return Ok(Self {
                root: validate_repo_root(path.clone(), &config)?,
                config,
            });
        }
        if let Ok(path) = env::var("AGE_MAC_REPO") {
            return Ok(Self {
                root: validate_repo_root(PathBuf::from(path), &config)?,
                config,
            });
        }
        if let Some(path) = config.default_repo_path() {
            return Ok(Self {
                root: validate_repo_root(PathBuf::from(path), &config)?,
                config,
            });
        }
        if let Some(path) = find_repo_from_cwd(&config)? {
            return Ok(Self { root: path, config });
        }
        if let Some(path) = compiled_repo_root() {
            return Ok(Self {
                root: validate_repo_root(path, &config)?,
                config,
            });
        }
        bail!("could not locate the Age Mac repository; run age-mac init --repo /path/to/age_mac")
    }
}

impl CmdSpec {
    fn new<P, C>(name: &str, program: P, cwd: C) -> Self
    where
        P: AsRef<OsStr>,
        C: AsRef<Path>,
    {
        Self {
            name: name.to_string(),
            program: program.as_ref().to_string_lossy().to_string(),
            args: Vec::new(),
            cwd: cwd.as_ref().to_path_buf(),
            envs: Vec::new(),
            env_remove: Vec::new(),
        }
    }

    fn args<I, S>(mut self, args: I) -> Self
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        self.args.extend(
            args.into_iter()
                .map(|arg| arg.as_ref().to_string_lossy().to_string()),
        );
        self
    }

    fn env<K, V>(mut self, key: K, value: V) -> Self
    where
        K: Into<String>,
        V: Into<String>,
    {
        self.envs.push((key.into(), value.into()));
        self
    }

    fn env_remove<K>(mut self, key: K) -> Self
    where
        K: Into<String>,
    {
        self.env_remove.push(key.into());
        self
    }

    fn command_vec(&self) -> Vec<String> {
        let mut command = vec![self.program.clone()];
        command.extend(self.args.clone());
        command
    }

    fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command.args(&self.args).current_dir(&self.cwd);
        for (key, value) in &self.envs {
            command.env(key, value);
        }
        for key in &self.env_remove {
            command.env_remove(key);
        }
        command
    }
}

fn run_step(spec: CmdSpec, json_mode: bool) -> Result<StepReport> {
    let verbose = VERBOSE.load(Ordering::Relaxed);
    let command = spec.command_vec();
    if verbose {
        eprintln!("[age-mac] start: {}", spec.name);
        eprintln!("[age-mac] cwd: {}", spec.cwd.display());
        eprintln!("[age-mac] cmd: {}", shell_join(&command));
    }
    let started = Instant::now();

    if json_mode {
        let output = spec
            .command()
            .output()
            .with_context(|| format!("failed to run {}", spec.name))?;
        let status = output.status.code().unwrap_or(-1);
        let ok = output.status.success();
        if verbose {
            print_step_finish(&spec.name, ok, status, started.elapsed().as_secs_f64());
        }
        let report = StepReport {
            name: spec.name.clone(),
            command,
            cwd: path_string(&spec.cwd),
            status,
            ok,
            stdout: truncate_output(String::from_utf8_lossy(&output.stdout).to_string()),
            stderr: truncate_output(String::from_utf8_lossy(&output.stderr).to_string()),
        };
        if !report.ok {
            bail!("{} failed with status {}", spec.name, status);
        }
        Ok(report)
    } else {
        let status = spec
            .command()
            .status()
            .with_context(|| format!("failed to run {}", spec.name))?;
        let code = status.code().unwrap_or(-1);
        let ok = status.success();
        if verbose {
            print_step_finish(&spec.name, ok, code, started.elapsed().as_secs_f64());
        }
        if !ok {
            bail!("{} failed with status {}", spec.name, code);
        }
        Ok(StepReport {
            name: spec.name,
            command,
            cwd: path_string(&spec.cwd),
            status: code,
            ok: true,
            stdout: String::new(),
            stderr: String::new(),
        })
    }
}

fn run_step_captured(spec: CmdSpec) -> Result<StepReport> {
    let verbose = VERBOSE.load(Ordering::Relaxed);
    let command = spec.command_vec();
    if verbose {
        eprintln!("[age-mac] start: {}", spec.name);
        eprintln!("[age-mac] cwd: {}", spec.cwd.display());
        eprintln!("[age-mac] cmd: {}", shell_join(&command));
    }
    let started = Instant::now();
    let output = spec
        .command()
        .output()
        .with_context(|| format!("failed to run {}", spec.name))?;
    let status = output.status.code().unwrap_or(-1);
    let ok = output.status.success();
    if verbose {
        print_step_finish(&spec.name, ok, status, started.elapsed().as_secs_f64());
    }
    let report = StepReport {
        name: spec.name.clone(),
        command,
        cwd: path_string(&spec.cwd),
        status,
        ok,
        stdout: truncate_output(String::from_utf8_lossy(&output.stdout).to_string()),
        stderr: truncate_output(String::from_utf8_lossy(&output.stderr).to_string()),
    };
    if !report.ok {
        bail!("{} failed with status {}", spec.name, status);
    }
    Ok(report)
}

fn print_step_finish(name: &str, ok: bool, status: i32, elapsed_secs: f64) {
    let state = if ok { "ok" } else { "failed" };
    eprintln!(
        "[age-mac] finish: {} ({}, status {}, {:.1}s)",
        name, state, status, elapsed_secs
    );
}

fn capture_text(spec: CmdSpec) -> Result<String> {
    let output = spec
        .command()
        .output()
        .with_context(|| format!("failed to run {}", spec.name))?;
    if !output.status.success() {
        bail!(
            "{} failed with status {}: {}",
            spec.name,
            output.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn capture_json(spec: CmdSpec) -> Result<Value> {
    let text = capture_text(spec)?;
    serde_json::from_str(&text).context("failed to parse provider JSON")
}

fn command_path(name: &str) -> Option<String> {
    let output = Command::new("/bin/sh")
        .args(["-lc", &format!("command -v {}", shell_quote(name))])
        .output()
        .ok()?;
    if output.status.success() {
        Some(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        None
    }
}

fn github_auth_status(gh_program: &str) -> Value {
    let env_source = if env::var_os("GH_TOKEN").is_some() {
        Some("GH_TOKEN")
    } else if env::var_os("GITHUB_TOKEN").is_some() {
        Some("GITHUB_TOKEN")
    } else {
        None
    };

    if let Some(source) = env_source {
        return json!({
            "available": true,
            "source": "env",
            "env_name": source,
        });
    }

    let available = Command::new(gh_program)
        .args(["auth", "status"])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false);

    json!({
        "available": available,
        "source": if available { "provider" } else { "missing" },
        "setup": if available { Value::Null } else { json!("run gh auth login") },
    })
}

fn read_bundle_version(repo: &RepoContext) -> Option<String> {
    let candidates = [script_path(repo), release_script_path(repo)];
    for candidate in candidates {
        let text = fs::read_to_string(candidate).ok()?;
        for line in text.lines() {
            if let Some(value) = line.strip_prefix("BUNDLE_VERSION=") {
                let value = value
                    .trim()
                    .trim_matches('"')
                    .trim_matches('\'')
                    .trim_start_matches("${BUNDLE_VERSION:-")
                    .trim_end_matches('}');
                if !value.is_empty() {
                    return Some(value.to_string());
                }
            }
        }
    }
    None
}

fn validate_repo_root(path: PathBuf, config: &Config) -> Result<PathBuf> {
    let root = path
        .canonicalize()
        .with_context(|| format!("failed to resolve {}", path.display()))?;
    let required = [
        root.join("Package.swift"),
        root.join("Engine/main.go"),
        resolve_repo_path(&root, config.paths.build_script()),
        resolve_repo_path(&root, config.paths.release_script()),
    ];
    for path in required {
        if !path.exists() {
            bail!(
                "{} does not look like the Age Mac repository",
                root.display()
            );
        }
    }
    Ok(root)
}

fn find_repo_from_cwd(config: &Config) -> Result<Option<PathBuf>> {
    let mut dir = env::current_dir()?;
    loop {
        if dir.join("Package.swift").exists()
            && dir.join("Engine/main.go").exists()
            && resolve_repo_path(&dir, config.paths.build_script()).exists()
        {
            return Ok(Some(validate_repo_root(dir, config)?));
        }
        if !dir.pop() {
            return Ok(None);
        }
    }
}

fn compiled_repo_root() -> Option<PathBuf> {
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest_dir.parent()?.parent().map(Path::to_path_buf)
}

fn read_config() -> Result<Config> {
    let path = config_path();
    if !path.exists() {
        return Ok(Config::default());
    }
    let text = fs::read_to_string(&path)
        .with_context(|| format!("failed to read config {}", path.display()))?;
    toml::from_str(&text).with_context(|| format!("failed to parse config {}", path.display()))
}

fn config_path() -> PathBuf {
    home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(CONFIG_DIR)
        .join(CONFIG_FILE)
}

fn config_summary(config: &Config) -> Value {
    json!({
        "repo": {
            "default_repo": config.default_repo_path(),
            "default_base": config.default_base(),
            "default_remote": config.default_remote(),
        },
        "paths": {
            "build_script": config.paths.build_script(),
            "release_script": config.paths.release_script(),
            "release_dir": config.paths.release_dir(),
            "app_bundle": config.paths.app_bundle(),
        },
        "tools": config
            .tools
            .entries()
            .into_iter()
            .map(|(name, command)| json!({
                "name": name,
                "command": command,
            }))
            .collect::<Vec<_>>(),
        "release": {
            "asset_name": config.release.asset_name(),
            "display_name": config.release.display_name(),
        },
    })
}

fn home_dir() -> Option<PathBuf> {
    env::var_os("HOME").map(PathBuf::from)
}

fn script_path(repo: &RepoContext) -> PathBuf {
    resolve_repo_path(&repo.root, repo.config.paths.build_script())
}

fn release_script_path(repo: &RepoContext) -> PathBuf {
    resolve_repo_path(&repo.root, repo.config.paths.release_script())
}

fn release_dir_path(repo: &RepoContext) -> PathBuf {
    resolve_repo_path(&repo.root, repo.config.paths.release_dir())
}

fn appcast_paths(repo: &RepoContext) -> [PathBuf; 3] {
    [
        repo.root.join("pages/appcast.xml"),
        repo.root.join("pages/appcast-arm64.xml"),
        repo.root.join("pages/appcast-x86_64.xml"),
    ]
}

fn app_bundle_path(repo: &RepoContext) -> PathBuf {
    resolve_repo_path(&repo.root, repo.config.paths.app_bundle())
}

fn resolve_repo_path(repo: &Path, value: &str) -> PathBuf {
    let path = PathBuf::from(value);
    if path.is_absolute() {
        path
    } else {
        repo.join(path)
    }
}

fn normalize_version_plain(version: &str) -> String {
    version.trim().trim_start_matches('v').to_string()
}

fn normalize_tag(version: &str) -> String {
    let plain = normalize_version_plain(version);
    format!("v{}", plain)
}

fn find_release_assets(repo: &RepoContext, version: &str) -> Result<Vec<PathBuf>> {
    let version = normalize_version_plain(version);
    let release_dir = release_dir_path(repo);
    let prefix = format!("{}-{}-", repo.config.release.asset_name(), version);
    if !release_dir.exists() {
        bail!(
            "release directory does not exist: {}",
            release_dir.display()
        );
    }
    let mut assets = Vec::new();
    for entry in fs::read_dir(&release_dir)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(OsStr::to_str) != Some("dmg") {
            continue;
        }
        let Some(file_name) = path.file_name().and_then(OsStr::to_str) else {
            continue;
        };
        if file_name.starts_with(&prefix) {
            assets.push(path);
        }
    }
    assets.sort();
    if assets.is_empty() {
        bail!(
            "no DMG assets found for version {} in {}",
            version,
            release_dir.display()
        );
    }
    Ok(assets)
}

fn ensure_assets_exist(assets: &[PathBuf]) -> Result<()> {
    for asset in assets {
        ensure_file_exists(asset)?;
    }
    Ok(())
}

fn ensure_file_exists(path: &Path) -> Result<()> {
    if !path.exists() {
        bail!("file does not exist: {}", path.display());
    }
    if !path.is_file() {
        bail!("path is not a file: {}", path.display());
    }
    Ok(())
}

fn release_create_args(
    config: &Config,
    version: &str,
    title: Option<&str>,
    notes: Option<&str>,
    notes_file: Option<&PathBuf>,
    live: bool,
    prerelease: bool,
    assets: &[PathBuf],
) -> Result<Vec<String>> {
    if notes.is_some() && notes_file.is_some() {
        bail!("use either --notes or --notes-file, not both");
    }
    if let Some(path) = notes_file {
        ensure_file_exists(path)?;
    }

    let version_plain = normalize_version_plain(version);
    let tag = normalize_tag(&version_plain);
    let mut args = vec!["release".to_string(), "create".to_string(), tag];
    args.extend(assets.iter().map(path_string));
    args.extend([
        "--title".to_string(),
        title
            .map(ToString::to_string)
            .unwrap_or_else(|| format!("{} {}", config.release.display_name(), version_plain)),
    ]);
    if let Some(notes) = notes {
        args.extend(["--notes".to_string(), notes.to_string()]);
    } else if let Some(path) = notes_file {
        args.extend(["--notes-file".to_string(), path_string(path)]);
    } else {
        args.extend([
            "--notes".to_string(),
            format!(
                "{} {} release.",
                config.release.display_name(),
                version_plain
            ),
        ]);
    }
    if !live {
        args.push("--draft".to_string());
    }
    if prerelease {
        args.push("--prerelease".to_string());
    }
    Ok(args)
}

fn verify_release_asset_metadata(local_assets: &[PathBuf], release: &Value) -> Result<Vec<Value>> {
    let remote_assets = release["assets"]
        .as_array()
        .context("release JSON is missing assets array")?;
    let mut checks = Vec::new();

    for local_asset in local_assets {
        let name = local_asset
            .file_name()
            .and_then(OsStr::to_str)
            .context("release asset path is missing a file name")?;
        let local_size = fs::metadata(local_asset)
            .with_context(|| format!("failed to read metadata for {}", local_asset.display()))?
            .len();
        let remote = remote_assets
            .iter()
            .find(|asset| asset["name"].as_str() == Some(name))
            .with_context(|| format!("GitHub release asset is missing: {}", name))?;
        let remote_size = remote["size"]
            .as_u64()
            .with_context(|| format!("GitHub release asset {} is missing size", name))?;
        let state = remote["state"].as_str().unwrap_or("unknown");

        if state != "uploaded" {
            bail!("GitHub release asset {} is not uploaded: {}", name, state);
        }
        if remote_size != local_size {
            bail!(
                "GitHub release asset {} size mismatch: local {}, remote {}",
                name,
                local_size,
                remote_size
            );
        }

        checks.push(json!({
            "ok": true,
            "name": name,
            "local_path": local_asset,
            "local_size": local_size,
            "remote_size": remote_size,
            "state": state,
            "url": remote["url"],
            "digest": remote["digest"],
        }));
    }

    Ok(checks)
}

fn dry_run_value(
    action: &str,
    repo: &RepoContext,
    commands: Vec<Vec<String>>,
    json_mode: bool,
) -> Result<Value> {
    if VERBOSE.load(Ordering::Relaxed) {
        eprintln!("[age-mac] dry-run: {}", action);
        for command in &commands {
            eprintln!("[age-mac] cmd: {}", shell_join(command));
        }
    }
    if !json_mode {
        for command in &commands {
            println!("{}", shell_join(command));
        }
    }
    Ok(json!({
        "ok": true,
        "action": action,
        "dry_run": true,
        "repo": repo.root,
        "commands": commands,
    }))
}

fn command_vec(program: &str, args: &[String]) -> Vec<String> {
    let mut command = vec![program.to_string()];
    command.extend(args.iter().cloned());
    command
}

fn ensure_not_json_stream(json_mode: bool, action: &str) -> Result<()> {
    if json_mode {
        bail!("{} is interactive or streaming; omit --json", action);
    }
    Ok(())
}

fn create_temp_dir(prefix: &str) -> Result<PathBuf> {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let path = env::temp_dir().join(format!("{}-{}-{}", prefix, std::process::id(), nanos));
    fs::create_dir_all(&path)?;
    Ok(path)
}

fn compare_files(left: &Path, right: &Path) -> Result<()> {
    let left_bytes =
        fs::read(left).with_context(|| format!("failed to read {}", left.display()))?;
    let right_bytes =
        fs::read(right).with_context(|| format!("failed to read {}", right.display()))?;
    if left_bytes != right_bytes {
        bail!(
            "roundtrip mismatch: {} != {}",
            left.display(),
            right.display()
        );
    }
    Ok(())
}

fn path_string<P: AsRef<Path>>(path: P) -> String {
    path.as_ref().to_string_lossy().to_string()
}

fn truncate_output(text: String) -> String {
    const MAX: usize = 24_000;
    if text.len() <= MAX {
        text
    } else {
        format!("{}...[truncated {} bytes]", &text[..MAX], text.len() - MAX)
    }
}

fn shell_quote(value: &str) -> String {
    if value
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '_' | '-' | '/' | '.' | ':'))
    {
        value.to_string()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

fn shell_join(command: &[String]) -> String {
    command
        .iter()
        .map(|part| shell_quote(part))
        .collect::<Vec<_>>()
        .join(" ")
}

fn print_json(value: &Value) {
    println!(
        "{}",
        serde_json::to_string_pretty(value).expect("serializing JSON should not fail")
    );
}

fn print_doctor_human(value: &Value) {
    let ok = value["ok"].as_bool().unwrap_or(false);
    println!(
        "Age Mac doctor: {}",
        if ok { "ok" } else { "needs attention" }
    );
    if let Some(repo_path) = value["repo"]["path"].as_str() {
        println!("Repo: {}", repo_path);
    } else if let Some(error) = value["repo"]["error"].as_str() {
        println!("Repo: missing ({})", error);
    }
    if let Some(version) = value["bundle_version"].as_str() {
        println!("Bundle version: {}", version);
    }
    let auth = &value["github_auth"];
    println!(
        "GitHub auth: {} ({})",
        if auth["available"].as_bool().unwrap_or(false) {
            "available"
        } else {
            "missing"
        },
        auth["source"].as_str().unwrap_or("unknown")
    );
    if let Some(checks) = value["checks"].as_array() {
        for check in checks {
            let name = check["name"].as_str().unwrap_or("unknown");
            if let Some(path) = check["path"].as_str() {
                println!("{}: {}", name, path);
            } else {
                println!("{}: missing", name);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_versions() {
        assert_eq!(normalize_version_plain("v1.2.3"), "1.2.3");
        assert_eq!(normalize_version_plain("1.2.3"), "1.2.3");
        assert_eq!(normalize_tag("1.2.3"), "v1.2.3");
        assert_eq!(normalize_tag("v1.2.3"), "v1.2.3");
    }

    #[test]
    fn quotes_shell_words() {
        assert_eq!(shell_join(&["git".into(), "status".into()]), "git status");
        assert_eq!(
            shell_join(&["git".into(), "commit message".into()]),
            "git 'commit message'"
        );
    }

    #[test]
    fn builds_release_create_args_as_draft_by_default() {
        let args = release_create_args(
            &Config::default(),
            "1.3.2",
            None,
            None,
            None,
            false,
            false,
            &[],
        )
        .unwrap();
        assert!(args.contains(&"--draft".to_string()));
        assert_eq!(args[0], "release");
        assert_eq!(args[1], "create");
        assert_eq!(args[2], "v1.3.2");
    }

    #[test]
    fn parses_release_create_assets() {
        let cli = Cli::try_parse_from([
            "age-mac",
            "repo",
            "release",
            "create",
            "--version",
            "1.3.2",
            "--asset",
            "pages/releases/AgeMac-1.3.2-arm64.dmg",
            "--asset",
            "pages/releases/AgeMac-1.3.2-universal.dmg",
            "--live",
        ])
        .unwrap();

        let Commands::Repo {
            command:
                RepoCommands::Release {
                    command: ReleaseCommands::Create(args),
                },
        } = cli.command
        else {
            panic!("expected repo release create command");
        };

        assert_eq!(args.version, "1.3.2");
        assert_eq!(
            args.assets,
            vec![
                PathBuf::from("pages/releases/AgeMac-1.3.2-arm64.dmg"),
                PathBuf::from("pages/releases/AgeMac-1.3.2-universal.dmg"),
            ]
        );
        assert!(args.live);
    }

    #[test]
    fn builds_release_create_args_with_assets() {
        let args = release_create_args(
            &Config::default(),
            "1.3.2",
            Some("Age Mac 1.3.2"),
            Some("Release notes"),
            None,
            true,
            false,
            &[
                PathBuf::from("pages/releases/AgeMac-1.3.2-arm64.dmg"),
                PathBuf::from("pages/releases/AgeMac-1.3.2-universal.dmg"),
            ],
        )
        .unwrap();

        assert_eq!(
            &args[..5],
            [
                "release",
                "create",
                "v1.3.2",
                "pages/releases/AgeMac-1.3.2-arm64.dmg",
                "pages/releases/AgeMac-1.3.2-universal.dmg",
            ]
        );
        assert!(!args.contains(&"--draft".to_string()));
    }

    #[test]
    fn verifies_release_asset_metadata_by_name_state_and_size() {
        let temp = create_temp_dir("age-mac-cli-release-test").unwrap();
        let arm64 = temp.join("AgeMac-1.3.2-arm64.dmg");
        let universal = temp.join("AgeMac-1.3.2-universal.dmg");
        fs::write(&arm64, b"arm64").unwrap();
        fs::write(&universal, b"universal").unwrap();

        let release = json!({
            "assets": [
                {"name": "AgeMac-1.3.2-arm64.dmg", "state": "uploaded", "size": 5},
                {"name": "AgeMac-1.3.2-universal.dmg", "state": "uploaded", "size": 9}
            ]
        });

        let checks = verify_release_asset_metadata(&[arm64, universal], &release).unwrap();

        assert_eq!(checks.len(), 2);
        assert!(checks.iter().all(|check| check["ok"] == true));

        fs::remove_dir_all(temp).unwrap();
    }

    #[test]
    fn release_asset_metadata_rejects_size_mismatch() {
        let temp = create_temp_dir("age-mac-cli-release-test").unwrap();
        let arm64 = temp.join("AgeMac-1.3.2-arm64.dmg");
        fs::write(&arm64, b"arm64").unwrap();

        let release = json!({
            "assets": [
                {"name": "AgeMac-1.3.2-arm64.dmg", "state": "uploaded", "size": 999}
            ]
        });

        let error = verify_release_asset_metadata(&[arm64], &release).unwrap_err();
        assert!(
            format!("{:#}", error).contains("size mismatch"),
            "unexpected error: {error:#}"
        );

        fs::remove_dir_all(temp).unwrap();
    }

    #[test]
    fn parses_legacy_config_and_prefers_nested_repo_defaults() {
        let config: Config = toml::from_str(
            r#"
default_repo = "/legacy/repo"

[repo]
default_repo = "/nested/repo"
default_base = "develop"
default_remote = "upstream"
"#,
        )
        .unwrap();

        assert_eq!(config.default_repo_path(), Some("/nested/repo"));
        assert_eq!(config.default_base(), "develop");
        assert_eq!(config.default_remote(), "upstream");
    }

    #[test]
    fn fills_missing_config_defaults_for_init_template() {
        let mut config = Config::default();
        config.repo.default_repo = Some("/repo".to_string());
        config.fill_missing_defaults();

        assert_eq!(config.default_repo_path(), Some("/repo"));
        assert_eq!(
            config.paths.build_script.as_deref(),
            Some("script/build_and_run.sh")
        );
        assert_eq!(
            config.paths.release_script.as_deref(),
            Some("scripts/release/build_dmg_release.sh")
        );
        assert_eq!(config.paths.release_dir.as_deref(), Some("pages/releases"));
        assert_eq!(config.paths.app_bundle.as_deref(), Some("dist/AgeMac.app"));
        assert_eq!(config.tools.go(), "go");
        assert_eq!(config.release.asset_name(), "AgeMac");

        let text = toml::to_string_pretty(&config).unwrap();
        assert!(text.contains("[paths]"));
        assert!(text.contains("release_dir = \"pages/releases\""));
    }

    #[test]
    fn resolves_configured_relative_paths_against_repo_root() {
        let mut config = Config::default();
        config.paths.release_dir = Some("artifacts/releases".to_string());
        config.paths.app_bundle = Some("/tmp/AgeMac.app".to_string());
        let repo = RepoContext {
            root: PathBuf::from("/repo"),
            config,
        };

        assert_eq!(
            release_dir_path(&repo),
            PathBuf::from("/repo/artifacts/releases")
        );
        assert_eq!(app_bundle_path(&repo), PathBuf::from("/tmp/AgeMac.app"));
    }
}
