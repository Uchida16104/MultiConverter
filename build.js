import fs from "fs";
import { execSync } from "child_process";

console.log("🚀 Starting MultiConverter build...");

const dirs = [
  "./Before/PHP",
  "./Before/Laravel",
  "./Before/Svelte",
  "./Before/Hack",
  "./Before/TypeScript",
  "./Before/Scss",
  "./Before/Sass",
  "./Before/Less",
];

// Ensure “After” directories exist
["HTMX", "JavaScript", "Tailwind", "CSS"].forEach((d) => {
  if (!fs.existsSync(`./After/${d}`)) fs.mkdirSync(`./After/${d}`, { recursive: true });
});

// Simulated conversions:
console.log("🔄 Converting PHP / Laravel / Svelte / Hack → JS...");
execSync('echo "// Converted JS output" > ./After/JavaScript/bundle.js');

console.log("🔄 Compiling TypeScript → JS...");
execSync("tsc ./Before/TypeScript/main.ts --outFile ./After/JavaScript/bundle.js", { stdio: "inherit" });

console.log("🔄 Converting Scss / Sass / Less → Tailwind / CSS...");
execSync("npx tailwindcss -i ./App.css -o ./After/Tailwind/output.css", { stdio: "inherit" });

console.log("✅ Generating HTMX file...");
fs.writeFileSync(
  "./After/HTMX/index.htmx.html",
  `<!DOCTYPE html>
<html hx-push-url="true">
<head>
  <meta charset="UTF-8">
  <title>MultiConverter</title>
  <link rel="stylesheet" href="../Tailwind/output.css">
  <script src="https://unpkg.com/htmx.org"></script>
  <script src="https://unpkg.com/hyperscript.org"></script>
</head>
<body class="bg-gray-100 text-center p-10">
  <h1 class="text-3xl font-bold text-blue-700">🚀 MultiConverter App</h1>
  <div id="app"></div>
  <script src="../JavaScript/bundle.js"></script>
</body>
</html>`
);

console.log("✅ All files successfully generated in ./After directory!");
