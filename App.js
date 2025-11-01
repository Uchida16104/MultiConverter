// @vite-ignore
// eslint-disable-next-line

import "./App.css";
import "./tailwind.config.js";
import "./postcss.config.js";
import "./Before/TypeScript/main.ts";
import "./Before/Scss/style.scss";
import "./Before/Sass/theme.sass";
import "./Before/Less/layout.less";

async function runSQL() {
  const SQL = await initSqlJs({
    locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.9.0/${file}`
  });

  const response = await fetch("./database.sql");
  const sqlText = await response.text();

  const db = new SQL.Database();
  db.run(sqlText);

  const tables = db.exec("SELECT name FROM sqlite_master WHERE type='table';");
  const desc = db.exec("PRAGMA table_info(users);");
  const select = db.exec("SELECT * FROM users;");
  db.run("UPDATE users SET email='alice@multiconverter.com' WHERE name='Alice';");
  const selectAfterUpdate = db.exec("SELECT * FROM users;");

  function formatResult(result) {
    if (!result[0]) return "";
    const columns = result[0].columns;
    const values = result[0].values;
    return [columns.join(" | "), ...values.map(row => row.join(" | "))].join("\n");
  }

  const outputText =
    "=== Tables ===\n" + formatResult(tables) + "\n\n" +
    "=== Table Structure ===\n" + formatResult(desc) + "\n\n" +
    "=== Initial Data ===\n" + formatResult(select) + "\n\n" +
    "=== After UPDATE ===\n" + formatResult(selectAfterUpdate);

  console.log(outputText);
}

window.addEventListener("DOMContentLoaded", runSQL);


document.body.innerHTML = `
  <div class="text-center p-10">
    <h1 class="text-3xl font-bold text-green-600">MultiConverter</h1>
    <br>
    <p>HTMX will load external dynamic content from PHP, Hack or Laravel.</p>
    <br>
    <div id="root"
         hx-get="./Before/Hack/example.hack"
         hx-trigger="load"
         hx-swap="innerHTML">
      Loading...
    </div>
    <br>
    <div id="root"
         hx-get="./Before/PHP/sample.php"
         hx-trigger="load"
         hx-swap="innerHTML">
      Loading...
    </div>
    <br>
    <div id="root"
         hx-get="./Before/Laravel/welcome.blade.php"
         hx-trigger="load"
         hx-swap="innerHTML">
      Loading...
    </div>
  </div>
`;