# MultiConverter

HTMX will load external dynamic content from PHP, Hack or Laravel.


MultiConverter is a hybrid compilation and build pipeline that converts multiple web technologies (PHP, Laravel, Hack, TypeScript, SQL, Scss, Sass, Less) into unified outputs for HTMX, JavaScript, Tailwind CSS, and CSS — fully automated with Node.js and Vite.

## 🧠 Technologies Used

```markdown
PHP / Laravel / Hack / TypeScript / SQL
↓
converted into JavaScript via `phptojs`, `tsc` and `sql.js`.

Scss / Sass / Less
↓
compiled via Tailwind CSS.

HTMX + Hyperscript for reactive HTML interface.
Vite for bundling.
GitHub Actions + Pages
```

## 📁Project Structure

```markdown
MultiConverter
|-Before
|--PHP
|--Laravel
|--Hack
|--TypeScript
|--Scss
|--Sass
|--Less
|-After (Created after running `npm run build` on root directory. See `gh-pages` branch.
|--HTMX
|--JavaScript      
|--Tailwind      
|--CSS    
|-dist
|--index.html
|--assets
|-node_modules
|-package.json
|-package-lock.json
|-vite.config.js
|-build.js
|-tailwind.config.js
|-postcss.config.js
|-index.html
|-database.sql
|-App.css
|-App.js
|-README.md
```

## ⚙️ ️ Local Development (Included XAMPP on Your Local Environment)

1. Clone this repository: ```https://github.com/Uchida16104/MultiConverter.git```
2. Go to cloned directory: ```cd MultiConverter```
3. Install dependencies: ```npm install```
4. Start development server: ```npm run dev```
5. Open http://localhost:5173 in your browser. [Pseudo Preview1](https://multiconverter.onrender.com) [Pseudo Preview2](https://multi-converter-five.vercel.app)
6. Build for production: ```npm run build```
7. View build output: [After/HTMX/index.htmx.html](After/HTMX/index.htmx.html)

---
**Information on: *2025***  
**Developer: *[Hirotoshi Uchida](https://hirotoshiuchida.onrender.com)***
