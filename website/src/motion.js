// 滚动特效：顶部进度条、首屏轻微视差、进入视口的淡入上移

const REVEAL_SELECTOR = [
  '.section-head',
  '.feature-card',
  '.android-callout',
  '.ui-points li',
  '.platform-card',
  '.download-notes li',
].join(', ');

const PARALLAX_RATIO = 0.06;
const PARALLAX_LIMIT = 28;
const STAGGER_STEP = 70;
const STAGGER_LIMIT = 3;

export function bindScrollEffects() {
  const progress = document.querySelector('[data-role="scroll-progress"]');
  const parallaxTarget = reducedMotion() ? null : document.querySelector('.hero-shot');
  let scheduled = false;

  const apply = () => {
    scheduled = false;

    const scrolled = window.scrollY;
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;

    if (progress) {
      const ratio = scrollable > 0 ? Math.min(scrolled / scrollable, 1) : 0;
      progress.style.setProperty('--scroll-progress', ratio.toFixed(4));
    }

    if (parallaxTarget) {
      const offset = Math.min(scrolled * PARALLAX_RATIO, PARALLAX_LIMIT);
      parallaxTarget.style.transform = `translate3d(0, ${offset.toFixed(2)}px, 0)`;
    }
  };

  const schedule = () => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(apply);
  };

  apply();
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
}

export function bindReveal() {
  if (reducedMotion() || !('IntersectionObserver' in window)) {
    return;
  }

  // 只接管还没被接管过、且加载时仍在视口下方的元素；已在视口里的不碰，免得闪一下
  const targets = [...document.querySelectorAll(REVEAL_SELECTOR)].filter(needsReveal);

  if (targets.length === 0) {
    return;
  }

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) {
        continue;
      }
      entry.target.classList.add('is-visible');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -8% 0px', threshold: 0.05 });

  for (const node of targets) {
    node.style.setProperty('--reveal-delay', `${staggerDelay(node)}ms`);
    node.classList.add('reveal-pending');
    observer.observe(node);
  }
}

function needsReveal(node) {
  return !node.classList.contains('reveal-pending') && node.getBoundingClientRect().top > window.innerHeight;
}

// 同一组里的兄弟依次晚一点进场，不至于齐刷刷地一起冒出来
function staggerDelay(node) {
  const siblings = [...node.parentElement.children].filter((child) => child.matches(REVEAL_SELECTOR));
  return Math.min(siblings.indexOf(node), STAGGER_LIMIT) * STAGGER_STEP;
}

function reducedMotion() {
  return window.matchMedia('(prefers-reduced-motion: reduce)').matches;
}
