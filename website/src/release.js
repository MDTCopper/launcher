// GitHub Releases 的读取与资产归类；页面只消费这里导出的结构

const REPO = 'MDTCopper/launcher';

export const RELEASES_PAGE = `https://github.com/${REPO}/releases`;

const RELEASES_API = `https://api.github.com/repos/${REPO}/releases?per_page=20`;

// 平台段宽松匹配、产物尾巴精确匹配：构建脚本换平台后缀时不必改这里
const PLATFORMS = [
  {
    id: 'windows',
    name: 'Windows',
    hint: 'Windows 10 / 11 · x64',
    matches: (fileName) => fileName.includes('-windows'),
    variants: [
      {
        label: '安装包',
        note: '双击安装，之后走安装包更新',
        matches: (fileName) => fileName.endsWith('-setup.exe'),
      },
      {
        label: '免安装',
        note: '解压即用，退出后自动覆盖更新',
        matches: (fileName) => fileName.endsWith('.zip'),
      },
    ],
  },
  {
    id: 'linux',
    name: 'Linux',
    hint: 'x64',
    matches: (fileName) => fileName.includes('-linux'),
    variants: [
      {
        label: 'tar.gz',
        note: '解压后运行目录里的可执行文件',
        matches: (fileName) => fileName.endsWith('.tar.gz'),
      },
      {
        label: 'AppImage',
        note: '加执行权限后直接运行',
        matches: (fileName) => /\.appimage$/i.test(fileName),
      },
    ],
  },
  {
    id: 'android',
    name: 'Android',
    hint: 'APK 按 ABI 分开，选错装不上',
    matches: (fileName) => fileName.includes('-android'),
    variants: [
      {
        label: 'arm64-v8a',
        note: '绝大多数现代手机',
        matches: (fileName) => fileName.endsWith('-android-arm64-v8a.apk'),
      },
      {
        label: 'armeabi-v7a',
        note: '较老的 32 位设备',
        matches: (fileName) => fileName.endsWith('-android-armeabi-v7a.apk'),
      },
      {
        label: 'x86_64',
        note: '模拟器与 x86 平板',
        matches: (fileName) => fileName.endsWith('-android-x86_64.apk'),
      },
    ],
  },
];

export async function loadChannels() {
  const response = await fetch(RELEASES_API, {
    headers: { Accept: 'application/vnd.github+json' },
  });

  if (!response.ok) {
    throw new Error(`GitHub 接口返回 ${response.status}`);
  }

  return sortIntoChannels(await response.json());
}

// 通道划分只认 prerelease 标记；仓库把内测与公测都勾成预发布
function sortIntoChannels(releases) {
  const published = releases
    .filter((release) => !release.draft)
    .sort((left, right) => publishedTime(right) - publishedTime(left));

  return {
    release: toChannel(published.find((release) => !release.prerelease)),
    prerelease: toChannel(published.find((release) => release.prerelease)),
  };
}

function toChannel(release) {
  if (!release) {
    return null;
  }

  return {
    tag: release.tag_name,
    label: release.name || release.tag_name,
    publishedAt: release.published_at || release.created_at,
    url: release.html_url,
    platforms: PLATFORMS.map((platform) => ({
      id: platform.id,
      name: platform.name,
      hint: platform.hint,
      variants: pickVariants(release.assets, platform),
    })),
  };
}

function pickVariants(assets, platform) {
  const owned = assets.filter((asset) => platform.matches(asset.name));

  return platform.variants
    .map((variant) => {
      const asset = owned.find((candidate) => variant.matches(candidate.name));
      if (!asset) {
        return null;
      }
      return {
        label: variant.label,
        note: variant.note,
        fileName: asset.name,
        size: asset.size,
        url: asset.browser_download_url,
      };
    })
    .filter(Boolean);
}

function publishedTime(release) {
  return Date.parse(release.published_at || release.created_at || 0);
}

// 首屏按钮用；认不出来就交给下载区分平台卡片
export function detectPlatform() {
  const agent = navigator.userAgent;
  if (/Android/i.test(agent)) {
    return 'android';
  }
  if (/Windows/i.test(agent)) {
    return 'windows';
  }
  if (/Linux|X11/i.test(agent)) {
    return 'linux';
  }
  return null;
}
