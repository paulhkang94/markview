#!/usr/bin/env node
/**
 * postinstall.js
 *
 * Downloads the MarkView MCP server binary from GitHub Releases and places it
 * at ./bin/markview-mcp-server-binary so the shell wrapper can find it.
 *
 * Uses only Node.js built-ins — zero runtime dependencies.
 */

"use strict";

const https = require("https");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { execFileSync } = require("child_process");

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const GITHUB_OWNER = "paulhkang94";
const GITHUB_REPO = "markview";
const VERSION = "1.1.3";
const ARCHIVE_NAME = `MarkView-${VERSION}.tar.gz`;
const DOWNLOAD_URL = `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases/download/v${VERSION}/${ARCHIVE_NAME}`;

// Path inside the tar.gz where the MCP server binary lives
const BINARY_IN_ARCHIVE = `MarkView.app/Contents/MacOS/markview-mcp-server`;

// Destination: placed next to the shell wrapper in bin/
const PKG_ROOT = path.resolve(__dirname, "..");
const DEST_BINARY = path.join(PKG_ROOT, "bin", "markview-mcp-server-binary");

// ---------------------------------------------------------------------------
// Platform guard
// ---------------------------------------------------------------------------

if (process.platform !== "darwin") {
  console.error(
    "[mcp-server-markview] MarkView is a macOS-only application. " +
      "This package is not supported on " +
      process.platform +
      ".",
  );
  // Exit 0 so npm install does not fail on non-macOS CI environments.
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Follow HTTP redirects and return a Promise that resolves with the final
 * IncomingMessage once we land on a non-redirect response.
 */
function followRedirects(url, maxRedirects) {
  maxRedirects = maxRedirects === undefined ? 10 : maxRedirects;

  return new Promise((resolve, reject) => {
    if (maxRedirects === 0) {
      return reject(new Error("Too many redirects"));
    }

    https
      .get(
        url,
        { headers: { "User-Agent": "mcp-server-markview-postinstall" } },
        (res) => {
          if (
            res.statusCode >= 300 &&
            res.statusCode < 400 &&
            res.headers.location
          ) {
            res.resume(); // drain the response body so the socket is freed
            resolve(followRedirects(res.headers.location, maxRedirects - 1));
          } else {
            resolve(res);
          }
        },
      )
      .on("error", reject);
  });
}

/**
 * Download a URL to a local file. Returns a Promise.
 */
function downloadFile(url, destPath) {
  return new Promise((resolve, reject) => {
    followRedirects(url)
      .then((res) => {
        if (res.statusCode !== 200) {
          res.resume();
          return reject(new Error(`HTTP ${res.statusCode} downloading ${url}`));
        }

        const total = parseInt(res.headers["content-length"] || "0", 10);
        let received = 0;
        let lastPct = -1;

        const out = fs.createWriteStream(destPath);

        res.on("data", (chunk) => {
          received += chunk.length;
          if (total > 0) {
            const pct = Math.floor((received / total) * 100);
            if (pct !== lastPct && pct % 10 === 0) {
              process.stdout.write(`\r  ${pct}%`);
              lastPct = pct;
            }
          }
        });

        res.pipe(out);

        out.on("finish", () => {
          process.stdout.write("\r       \r"); // clear progress line
          resolve();
        });

        out.on("error", reject);
        res.on("error", reject);
      })
      .catch(reject);
  });
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  // Skip if the binary is already present (e.g. re-running postinstall).
  if (fs.existsSync(DEST_BINARY)) {
    console.log(
      "[mcp-server-markview] Binary already present, skipping download.",
    );
    return;
  }

  // Ensure the bin/ directory exists (it should, since it ships with the package).
  fs.mkdirSync(path.dirname(DEST_BINARY), { recursive: true });

  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-server-markview-"));
  const archivePath = path.join(tmpDir, ARCHIVE_NAME);

  try {
    console.log(`[mcp-server-markview] Downloading MarkView v${VERSION}...`);
    console.log(`  ${DOWNLOAD_URL}`);

    await downloadFile(DOWNLOAD_URL, archivePath);

    console.log("[mcp-server-markview] Extracting MCP server binary...");

    // Extract only the MCP server binary from the archive.
    // Path is MarkView.app/Contents/MacOS/markview-mcp-server (3 dirs deep).
    execFileSync(
      "tar",
      [
        "-xzf",
        archivePath,
        "--strip-components=3",
        "-C",
        path.dirname(DEST_BINARY),
        BINARY_IN_ARCHIVE,
      ],
      { stdio: "pipe" },
    );

    // The extracted file will be named "markview-mcp-server"; rename if needed.
    const extractedName = path.join(
      path.dirname(DEST_BINARY),
      "markview-mcp-server",
    );
    if (fs.existsSync(extractedName) && extractedName !== DEST_BINARY) {
      fs.renameSync(extractedName, DEST_BINARY);
    }

    // Make executable.
    fs.chmodSync(DEST_BINARY, 0o755);

    console.log("[mcp-server-markview] Binary installed successfully.");
    console.log(`  Location: ${DEST_BINARY}`);
  } catch (err) {
    console.error("[mcp-server-markview] Installation failed:", err.message);
    console.error(
      "\nYou can still use MarkView's MCP server if MarkView.app is installed at /Applications.\n" +
        "Run `npx mcp-server-markview` and the wrapper will fall back to the app bundle automatically.",
    );
    // Exit 0 — a postinstall failure should not block npm install entirely.
    process.exit(0);
  } finally {
    // Clean up temp directory.
    try {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    } catch (_) {
      // Ignore cleanup errors.
    }
  }
}

main();
