import { defineConfig } from 'vite';

// 站点发布在 GitHub Pages 的项目路径下：https://mdtcopper.github.io/launcher/
// 绑自定义域名时把 base 改成 '/'，并去掉 workflow 里的 Pages 相关路径假设
export default defineConfig({
  base: '/launcher/',
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
});
