// 用真实 Releases 数据核对资产匹配规则；新产物上线后跑一次，看每个平台是否都配上了
import { loadChannels } from '../src/release.js';

const channels = await loadChannels();

for (const key of ['release', 'prerelease']) {
  const channel = channels[key];
  console.log(`\n[${key}] ${channel ? `${channel.label} · ${channel.publishedAt}` : '（无）'}`);

  if (!channel) {
    continue;
  }

  for (const platform of channel.platforms) {
    const matched = platform.variants.map((variant) => `${variant.label} → ${variant.fileName}`);
    console.log(`  ${platform.name}：${matched.length > 0 ? matched.join('　|　') : '无产物'}`);
  }
}
