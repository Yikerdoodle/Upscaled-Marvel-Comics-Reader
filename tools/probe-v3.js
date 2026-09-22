/* probe v3 - identifies WHERE the reader's pixels come from.
   v2 could not distinguish "Marvel only has small assets" from
   "Marvel gave us small assets because our viewport was small".   */
(async () => {
  const d = devicePixelRatio, X = '\u00d7';
  const R = performance.getEntriesByType('resource');
  const sch = s => (s || '').split(':')[0] || '-';

  if (innerHeight < 500)
    console.log('%c!! VIEWPORT IS ONLY ' + innerHeight + ' CSS px TALL. DevTools is docked and '
      + 'shrinking the page. Undock it to a separate window (Ctrl+Shift+Alt+I) and re-run, '
      + 'or these numbers are meaningless.', 'background:#900;color:#fff;font-size:14px;padding:3px');
  if (Math.abs(d - Math.round(d * 4) / 4) > 0.01)
    console.log('%c!! devicePixelRatio is ' + d + ' - that is not a clean Windows scaling value. '
      + 'Press Ctrl+0 to reset Firefox page zoom to 100%, then re-run.',
      'background:#960;color:#fff;font-size:14px;padding:3px');

  /* painted: include the src scheme + responsive-image hints */
  const painted = [...document.querySelectorAll('img,canvas')].map(e => {
    const r  = e.getBoundingClientRect();
    const iw = e.naturalWidth || e.width || 0, ih = e.naturalHeight || e.height || 0;
    return { tag: e.tagName,
             source_px: iw + X + ih,
             drawn_px : Math.round(r.width * d) + X + Math.round(r.height * d),
             upscale  : (iw && r.width) ? (r.width * d / iw).toFixed(2) + X : '-',
             scheme   : sch(e.currentSrc || e.src),
             srcset   : e.srcset ? 'YES(' + e.srcset.split(',').length + ')' : 'no',
             src      : (e.currentSrc || e.src || '').slice(0, 60),
             _s: r.width * r.height };
  }).filter(o => o._s > 5000).sort((a, b) => b._s - a._s).slice(0, 8);

  /* downloaded */
  const cand = [...new Set(R.filter(r => !/^(script|link|css|beacon)$/.test(r.initiatorType)).map(r => r.name))];
  const size = new Map(R.map(r => [r.name, r.transferSize || r.encodedBodySize || r.decodedBodySize || 0]));
  const dec  = await Promise.all(cand.map(u => new Promise(k => {
    const i = new Image();
    i.onload = () => k({ u, w: i.naturalWidth, h: i.naturalHeight });
    i.onerror = () => k({ u, w: 0, h: 0 });
    i.src = u;
  })));
  const imgs = dec.filter(o => o.w >= 300 && o.h >= 300).sort((a, b) => b.w * b.h - a.w * a.h);
  const rows = imgs.slice(0, 8).map(o => {
    const kib = size.get(o.u) / 1024;
    return { source_px: o.w + X + o.h, aspect: (o.h / o.w).toFixed(3),
             KiB: kib ? Math.round(kib) : 'cached',
             bits_px: kib ? ((kib * 8192) / (o.w * o.h)).toFixed(3) : '-',
             url: o.u.slice(0, 75) };
  });

  console.log('%cDPR ' + d + '   viewport ' + innerWidth + X + innerHeight + ' CSS  =  '
    + Math.round(innerWidth * d) + X + Math.round(innerHeight * d) + ' device px  |  screen '
    + screen.width + X + screen.height, 'font-weight:bold;font-size:13px');
  console.log(R.length + ' resources, ' + cand.length + ' candidates, ' + imgs.length + ' decoded >=300px');
  console.log('--- PAINTED (scheme "blob" means the reader fetches bytes and builds the image itself) ---');
  console.table(painted.map(({ _s, ...r }) => r));
  console.log('--- DOWNLOADED (aspect ~1.50 = comic page, ~1.43 = something else) ---');
  console.table(rows);
})();
