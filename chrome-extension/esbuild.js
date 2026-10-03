const esbuild = require("esbuild");
const fs = require("fs");
const path = require("path");

const production = process.argv.includes("--production");
const watch = process.argv.includes("--watch");

function copyHtml() {
  fs.mkdirSync(path.join(__dirname, "sidepanel"), { recursive: true });
  fs.mkdirSync(path.join(__dirname, "options"), { recursive: true });

  fs.copyFileSync(
    path.join(__dirname, "src/sidepanel/sidepanel.html"),
    path.join(__dirname, "sidepanel/sidepanel.html")
  );
  fs.copyFileSync(
    path.join(__dirname, "src/options/options.html"),
    path.join(__dirname, "options/options.html")
  );
}

async function main() {
  copyHtml();

  const configs = [
    {
      entryPoints: ["src/background/background.ts"],
      bundle: true,
      format: "esm",
      platform: "browser",
      target: "es2022",
      outfile: "background.js",
      minify: production,
      sourcemap: !production,
    },
    {
      entryPoints: ["src/content/content.ts"],
      bundle: true,
      format: "iife",
      platform: "browser",
      target: "es2022",
      outfile: "content.js",
      minify: production,
      sourcemap: !production,
    },
    {
      entryPoints: ["src/sidepanel/sidepanel.ts"],
      bundle: true,
      format: "iife",
      platform: "browser",
      target: "es2022",
      outfile: "sidepanel/sidepanel.js",
      minify: production,
      sourcemap: !production,
    },
    {
      entryPoints: ["src/options/options.ts"],
      bundle: true,
      format: "iife",
      platform: "browser",
      target: "es2022",
      outfile: "options/options.js",
      minify: production,
      sourcemap: !production,
    },
  ];

  if (watch) {
    const contexts = await Promise.all(configs.map((c) => esbuild.context(c)));
    await Promise.all(contexts.map((ctx) => ctx.watch()));
    console.log("[Ghost Chrome Extension] Watching for changes...");
  } else {
    await Promise.all(configs.map((c) => esbuild.build(c)));
    console.log("[Ghost Chrome Extension] Build completed successfully.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
