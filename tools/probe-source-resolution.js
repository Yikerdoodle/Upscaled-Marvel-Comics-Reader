/* probe-source-resolution.js  (v2)
   Paste the WHOLE of this file into the browser console while a comic PAGE
   is displayed inside the Marvel reader (not the issue detail page).

   v2 fix: v1 matched image URLs by file extension, which misses CDN URLs that
   have no extension or carry a query string. Now keyed off resource
   initiatorType and verified by actually decoding the bytes.                */
(async () => {
  const d = devicePixelRatio, X = '\u00d7';
  const R = performance.getEntriesByType('resource');

  /* 1. what is painted on screen right now */
  const painted = [...document.querySelectorAll('img,canvas')].map(e => {
    const r  = e.getBoundingClientRect();
    const iw = e.naturalWidth  || e.width  || 0;
    const ih = e.naturalHeight || e.height || 0;
    return { tag: e.tagName,
             source_px: iw + X + ih,
             drawn_px : Math.round(r.width * d) + X + Math.round(r.height * d),
             upscale  : (iw && r.width) ? (r.width * d / iw).toFixed(2) + X : '-',
             _shown   : r.width * r.height };
  }).filter(o => o._shown > 10000).sort((a, b) => b._shown - a._shown).slice(0, 6);

  /* 2. what was actually downloaded - decode to confirm, format-agnostic */
  const cand = [...new Set(
    R.filter(r => !/^(script|link|css|beacon)$/.test(r.initiatorType)).map(r => r.name))];
  const size = new Map(R.map(r => [r.name, r.transferSize || r.encodedBodySize || 0]));
  const dec  = await Promise.all(cand.map(u => new Promise(k => {
    const i = new Image();
    i.onload  = () => k({ u, w: i.naturalWidth, h: i.naturalHeight });
    i.onerror = () => k({ u, w: 0, h: 0 });
    i.src = u;
  })));
  const imgs = dec.filter(o => o.w >= 300 && o.h >= 300).sort((a, b) => b.w * b.h - a.w * a.h);
  const rows = imgs.slice(0, 6).map(o => {
    const kib = size.get(o.u) / 1024;
    return { source_px: o.w + X + o.h,
             KiB      : kib ? Math.round(kib) : 'cached',
             bits_px  : kib ? ((kib * 8192) / (o.w * o.h)).toFixed(3) : '-',
             url      : o.u.slice(0, 70) };
  });

  console.log('%cDPR ' + d + '    viewport ' + innerWidth + X + innerHeight + ' CSS  =  '
    + Math.round(innerWidth * d) + X + Math.round(innerHeight * d) + ' device px',
    'font-weight:bold;font-size:13px');
  console.log('diagnostic: ' + R.length + ' resources, ' + cand.length + ' candidates, '
    + imgs.length + ' decoded >=300px, ' + painted.length + ' painted');

  console.log('--- PAINTED ON SCREEN ---');
  console.table(painted.map(({ _shown, ...r }) => r));
  console.log('--- DOWNLOADED ASSETS ---');
  console.table(rows);

  if (rows[0]) {
    console.log('%cBIGGEST ASSET: ' + rows[0].source_px + '  @  ' + rows[0].bits_px + ' bits/px',
      'font-weight:bold;color:#c00;font-size:15px');
    console.log('Below ~0.3 bits/px, compression damage - not resolution - is the main enemy.');
  } else {
    console.log('%cNothing page-sized found. Are you inside the READER with a page showing?'
      + ' Turn 2-3 pages with the console open, then re-run.', 'color:#c60');
  }
})();
