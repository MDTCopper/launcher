# Copper Launcher 官网

单页落地页，Vite + 原生 HTML / CSS / JS，没有框架依赖。改完推到 `main` 由
`.github/workflows/website.yml` 构建并发布到 GitHub Pages。

## 本地跑

```bash
cd website
npm install
npm run dev      # 打开 http://localhost:5173/launcher/
npm run build    # 产物在 website/dist
```

`npm run dev` 的地址带 `/launcher/` 前缀，因为线上站点在
`https://mdtcopper.github.io/launcher/` 这个项目路径下；这个前缀写在
`vite.config.js` 的 `base`，绑自定义域名时改成 `'/'`。

## 目录

| 路径 | 作用 |
|---|---|
| `index.html` | 页面结构与全部中文文案 |
| `src/main.js` | 渲染下载区、标记访问者平台、顶栏滚动阴影 |
| `src/release.js` | 读 GitHub Releases 并按通道与平台归类产物 |
| `src/styles/tokens.css` | 设计令牌，颜色对着启动器的暗色主题 |
| `src/styles/base.css` | 重置、排版与通用件（容器 / 卡片 / 按钮 / 标签） |
| `src/styles/sections.css` | 各分节样式 |
| `public/` | `logo.png`、`ui-demo.png`、`favicon.ico` |
| `scripts/check-release.mjs` | 用真实接口核对产物匹配规则 |

## 下载区怎么来的

`src/release.js` 取最近的 release，按 `prerelease` 标记分成正式版与内测版两个通道，
再按产物文件名的尾巴配对：

- 平台段宽松匹配（`-windows` / `-linux` / `-android`），尾部精确匹配（`-setup.exe` / `.zip` / `.tar.gz` / `.AppImage` / `-<abi>.apk`）
- 某一通道某个平台没有对应文件就写「暂无这个平台的产物」，不会留死链
- 接口读不到（断网、限流）时页面退化成「前往 Releases 页面」

发了新版本、加了新平台产物之后跑一次核对：

```bash
node scripts/check-release.mjs
```

它会打印两个通道各自配到的文件，缺哪个平台一眼能看出来。
