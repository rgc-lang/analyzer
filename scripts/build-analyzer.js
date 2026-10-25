#!/usr/bin/env node
/*
 * Build the RGC analyzer (language server).
 *
 * The analyzer reuses the rgc compiler frontend, so this script resolves the
 * import closure of src/*.rg against a checkout of the rgc repository, stages
 * the needed modules into a flat build directory, and invokes the rgc compiler.
 *
 * Frontend checkout resolution: --frontend, else vendor/rgc/src/src (CI checkout),
 * else ../rgc/src/src (local sibling checkout).
 *
 * Usage:
 *   node scripts/build-analyzer.js [--check] [--rgc <path>] [--frontend <dir>]
 *                                  [--lib <dir>] [--work <dir>] [--out <dir>]
 *
 *   --check   resolve and print the module closure without compiling
 *   --out     directory that receives rgc-analyzer(.exe) and lib/ (default build/server)
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const isWindows = process.platform === "win32";
const exeName = isWindows ? "rgc-analyzer.exe" : "rgc-analyzer";

function fail(message) {
  console.error(`error: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const opts = {
    check: false,
    rgc: process.env.RGC || "",
    frontend: "",
    lib: "",
    work: path.join(repoRoot, "build"),
    out: path.join(repoRoot, "build", "server"),
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--check":
        opts.check = true;
        break;
      case "--rgc":
      case "--frontend":
      case "--lib":
      case "--work":
      case "--out": {
        const value = argv[++i];
        if (!value) fail(`${arg} requires a value`);
        opts[arg.slice(2)] = path.resolve(value);
        break;
      }
      case "-h":
      case "--help":
        console.log("Usage: node scripts/build-analyzer.js [--check] [--rgc <path>] [--frontend <dir>] [--lib <dir>] [--work <dir>] [--out <dir>]");
        process.exit(0);
        break;
      default:
        fail(`unknown argument: ${arg}`);
    }
  }
  return opts;
}

function firstExisting(candidates) {
  for (const candidate of candidates) {
    if (candidate && fs.existsSync(candidate)) return candidate;
  }
  return undefined;
}

function resolveFrontend(explicit) {
  const dir = explicit
    ? explicit
    : firstExisting([
        path.join(repoRoot, "vendor", "rgc", "src", "src"),
        path.join(repoRoot, "..", "rgc", "src", "src"),
      ]);
  if (!dir) {
    fail("rgc frontend not found; pass --frontend <dir> or check out rgc into vendor/rgc");
  }
  if (!fs.existsSync(dir)) fail(`frontend directory not found: ${dir}`);
  return dir;
}

function resolveLib(explicit, frontendDir) {
  const dir = explicit ? explicit : path.join(frontendDir, "..", "..", "lib");
  if (!fs.existsSync(dir)) fail(`rgc standard library directory not found: ${dir}`);
  return path.resolve(dir);
}

function resolveCompiler(explicit) {
  if (explicit) return explicit;
  const local = path.join(repoRoot, "..", "rgc", "build", "rgc");
  if (fs.existsSync(local)) return local;
  return "rgc";
}

function moduleFile(dir, name) {
  const file = path.join(dir, name.split(".").join(path.sep) + ".rg");
  return fs.existsSync(file) ? file : undefined;
}

function importsOf(source) {
  const names = [];
  const re = /^\s*import\s+([A-Za-z_][A-Za-z0-9_.]*)/gm;
  let match;
  while ((match = re.exec(source)) !== null) names.push(match[1]);
  return names;
}

function resolveClosure(analyzerDir, frontendDir) {
  const analyzerModules = fs
    .readdirSync(analyzerDir)
    .filter((file) => file.endsWith(".rg") && !file.endsWith(".d.ts"))
    .sort();
  const local = new Map();
  for (const file of analyzerModules) {
    local.set(path.basename(file, ".rg"), path.join(analyzerDir, file));
  }

  const staged = new Map(local);
  const frontend = new Map();
  const queue = [...staged.keys()];
  while (queue.length > 0) {
    const name = queue.shift();
    const source = fs.readFileSync(staged.get(name) ?? frontend.get(name), "utf8");
    for (const imported of importsOf(source)) {
      const key = imported.split(".").join("/");
      if (staged.has(key) || frontend.has(key)) continue;
      const file = moduleFile(frontendDir, imported);
      if (!file) {
        fail(`module \`${imported}\` (imported by ${name}.rg) was not found in ${frontendDir}`);
      }
      frontend.set(key, file);
      queue.push(key);
    }
  }
  return { local, frontend };
}

function copyFile(from, to) {
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
}

function main() {
  const opts = parseArgs(process.argv.slice(2));
  const frontendDir = resolveFrontend(opts.frontend);
  const libDir = resolveLib(opts.lib, frontendDir);
  const { local, frontend } = resolveClosure(path.join(repoRoot, "src"), frontendDir);

  console.log(`frontend: ${frontendDir}`);
  console.log(`analyzer: ${[...local.keys()].sort().join(", ")}`);
  console.log(`frontend: ${[...frontend.keys()].sort().join(", ")}`);
  if (opts.check) {
    console.log("module closure OK");
    return;
  }

  const compiler = resolveCompiler(opts.rgc);
  const workDir = opts.work;
  const srcDir = path.join(workDir, "src");
  fs.rmSync(srcDir, { recursive: true, force: true });
  fs.mkdirSync(srcDir, { recursive: true });
  for (const [, file] of local) copyFile(file, path.join(srcDir, path.basename(file)));
  for (const [key, file] of frontend) copyFile(file, path.join(srcDir, key + ".rg"));

  fs.mkdirSync(opts.out, { recursive: true });
  const outBin = path.join(opts.out, exeName);
  const entry = path.join(srcDir, "main.rg");
  console.log(`compiler: ${compiler}`);
  const result = spawnSync(compiler, [entry, "-o", outBin], {
    cwd: repoRoot,
    stdio: "inherit",
  });
  if (result.error) fail(`failed to run ${compiler}: ${result.error.message}`);
  if (result.status !== 0) fail(`${compiler} exited with status ${result.status}`);
  if (!fs.existsSync(outBin)) fail(`compiler did not produce ${outBin}`);

  const outLib = path.join(opts.out, "lib");
  fs.rmSync(outLib, { recursive: true, force: true });
  fs.cpSync(libDir, outLib, { recursive: true });

  const size = (fs.statSync(outBin).size / (1024 * 1024)).toFixed(1);
  console.log(`built ${outBin} (${size} MiB)`);
  console.log(`staged ${outLib}`);
}

main();
