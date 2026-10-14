import { loadChannels, detectPlatform } from './release.js';

const PLATFORM_NAMES = { windows: 'Windows', linux: 'Linux', android: 'Android' };

const channelNodes = new Map(
  [...document.querySelectorAll('[data-channel]')].map((node) => [node.dataset.channel, node]),
);

const header = document.querySelector('[data-role="site-header"]');
const statusNode = document.querySelector('[data-role="status"]');
const fallbackNode = document.querySelector('[data-role="fallback"]');
const heroHint = document.querySelector('[data-role="hero-hint"]');

const platform = detectPlatform();

start();

async function start() {
  bindHeaderShadow();

  try {
    const channels = await loadChannels();
    renderChannels(channels);
    markDetectedPlatform();
    statusNode.textContent = `以上版本信息读取于 ${clockNow()}`;
  } catch (error) {
    statusNode.hidden = true;
    fallbackNode.hidden = false;
    console.warn('[website] 读取版本信息失败', error);
  }
}

function renderChannels(channels) {
  for (const [key, node] of channelNodes) {
    const channel = channels[key];
    const grid = node.querySelector('[data-role="platforms"]');
    const empty = node.querySelector('[data-role="empty"]');
    const version = node.querySelector('[data-role="channel-version"]');

    grid.replaceChildren();
    if (!channel || countVariants(channel) === 0) {
      empty.hidden = false;
      continue;
    }

    empty.hidden = true;
    version.textContent = `${channel.label} · ${formatDate(channel.publishedAt)} 发布`;
    for (const platformInfo of channel.platforms) {
      grid.append(buildPlatformCard(platformInfo));
    }
  }
}

function buildPlatformCard(platformInfo) {
  const card = el('article', 'card platform-card');
  card.dataset.platform = platformInfo.id;

  const head = el('header', 'platform-head');
  head.append(el('h4', null, platformInfo.name), el('span', 'platform-hint', platformInfo.hint));
  card.append(head);

  if (platformInfo.variants.length === 0) {
    card.append(el('p', 'variant-empty', '该通道暂无这个平台的产物。'));
    return card;
  }

  const list = el('ul', 'variant-list');
  for (const variant of platformInfo.variants) {
    list.append(buildVariantRow(variant));
  }
  card.append(list);
  return card;
}

function buildVariantRow(variant) {
  const info = el('div', 'variant-info');

  const label = el('p', 'variant-label');
  label.append(el('span', null, variant.label), el('span', 'variant-size', formatSize(variant.size)));

  const fileName = el('p', 'variant-file', variant.fileName);
  fileName.title = variant.fileName;

  info.append(label, el('p', 'variant-note', variant.note), fileName);

  const download = el('a', 'button button-secondary button-small', '下载');
  download.href = variant.url;
  download.rel = 'noreferrer noopener';

  const row = el('li', 'variant');
  row.append(info, download);
  return row;
}

// 认出的平台在下载区打标；认不出来就保持原样
function markDetectedPlatform() {
  if (!platform) {
    return;
  }

  const markers = document.querySelectorAll(`[data-platform="${platform}"] .platform-head`);
  markers.forEach((head) => head.append(el('span', 'tag', '你的平台')));

  if (markers.length > 0) {
    heroHint.textContent = `已识别到 ${PLATFORM_NAMES[platform]}，下载区里标出来了；当前全部产物都是内测版，尚未发布正式版`;
  }
}

function bindHeaderShadow() {
  const sync = () => header.classList.toggle('is-scrolled', window.scrollY > 8);
  sync();
  window.addEventListener('scroll', sync, { passive: true });
}

function countVariants(channel) {
  return channel.platforms.reduce((total, platformInfo) => total + platformInfo.variants.length, 0);
}

function formatSize(bytes) {
  if (!bytes) {
    return '';
  }

  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }

  const digits = unit === 0 || value >= 100 ? 0 : 1;
  return `${value.toFixed(digits)} ${units[unit]}`;
}

function formatDate(iso) {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return '';
  }
  return new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit' }).format(date);
}

function clockNow() {
  const now = new Date();
  return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) {
    node.className = className;
  }
  if (text !== undefined) {
    node.textContent = text;
  }
  return node;
}
