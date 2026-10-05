// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Tareq Jami (Jami IT)
// Additional terms under GPLv3 section 7 apply; see NOTICE.
// The store listing's halftone (branding/store-listing/index.html): a dot grid
// whose dots grow from nothing at a wavy line to nearly touching at the
// bottom edge. `p` (0..1) raises the line, so the field fills in on scroll.
export function drawHalftone(canvas, p, color = '#fee036') {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  const W = canvas.clientWidth;
  const H = canvas.clientHeight;
  if (!W || !H) return;
  if (canvas.width !== Math.round(W * dpr) || canvas.height !== Math.round(H * dpr)) {
    canvas.width = Math.round(W * dpr);
    canvas.height = Math.round(H * dpr);
  }
  const ctx = canvas.getContext('2d');
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, W, H);
  ctx.fillStyle = color;

  const spacing = W < 700 ? 15 : 22;
  const maxR = spacing * 0.5;
  // How far up the dots climb at p = 1: the band under the content (the
  // section's bottom padding), so they never sit behind text.
  const reach = Math.min(200, H * 0.3);
  const e = 1 - (1 - p) ** 3; // ease out
  const startY = H + 30 - (reach + 30) * e;
  for (let y = spacing / 2; y < H + spacing; y += spacing) {
    for (let x = spacing / 2; x < W + spacing; x += spacing) {
      const wave = (reach * 0.14) * Math.sin((x / W) * Math.PI * 1.3 + 0.4) - (reach * 0.16) * (x / W);
      const yT = startY + wave;
      let q = (y - yT) / (H - yT);
      if (q <= 0) continue;
      if (q > 1) q = 1;
      const r = maxR * q ** 0.85;
      if (r < 0.4) continue;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
    }
  }
}
