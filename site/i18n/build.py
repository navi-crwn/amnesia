#!/usr/bin/env python3
"""Builds the website in every language from the two source pages.

  python3 site/i18n/build.py          (run from the repo folder)

Source: site/i18n/src/mac.html and win.html. Every piece of text is written twice there,
<span data-en>English</span><span data-id>Indonesian</span> (the way the site always worked).
Other languages come from site/i18n/strings/<code>.json: {"English text": "translation"}.
Output: docs/index.html + docs/win/index.html (English) and docs/<slug>/index.html +
docs/<slug>/win/index.html for each other language. Missing translations fall back to English
and are counted at the end. Edit the source pages and the .json files, never the output.
"""
import json
import os
import posixpath
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.join(ROOT, 'site', 'i18n')
DOCS = os.path.join(ROOT, 'docs')
SITE = 'https://navi-crwn.github.io/amnesia/'

# English first, the rest sorted by their English name
LANGS = [
    # code,   slug,    menu name,             short, locale,  terms file
    ('en',    '',      'English',             'EN',  'en-GB', 'TERMS.md'),
    ('zh-CN', 'zh-cn', '简体中文',             '中文', 'zh-CN', 'TERMS.md'),
    ('de',    'de',    'Deutsch',             'DE',  'de-DE', 'TERMS.md'),
    ('id',    'id',    'Bahasa Indonesia',    'ID',  'id-ID', 'TERMS.id.md'),
    ('ja',    'ja',    '日本語',               '日本語', 'ja-JP', 'TERMS.md'),
    ('pt-BR', 'pt-br', 'Português (Brasil)',  'PT',  'pt-BR', 'TERMS.md'),
    ('es',    'es',    'Español',             'ES',  'es-ES', 'TERMS.md'),
]
PAGES = [('mac.html', ''), ('win.html', 'win/')]


def norm(x):
    return re.sub(r'\s+', ' ', x).strip()


def load(code):
    p = os.path.join(HERE, 'strings', code + '.json')
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else {}


EXTRA = load('_extra')   # small strings outside the source pairs, per language


def rel(from_dir, target):
    r = posixpath.relpath(target or '.', from_dir or '.')
    if (target.endswith('/') or not target or r in ('.', '..') or r.endswith('/..')) and not r.endswith('/'):
        r += '/'
    return r


def inner(s, i):
    """s[i:] starts right after an opening <span ...>: returns (content, index after its </span>), nested spans counted."""
    depth, j = 1, i
    for m in re.compile(r'<span\b|</span>').finditer(s, i):
        depth += 1 if m.group(0) != '</span>' else -1
        if depth == 0:
            return s[i:m.start()], m.end()
    sys.exit('unclosed <span> at %d' % i)


def pairs(s, T):
    out, pos = [], 0
    while True:
        a = s.find('<span data-en>', pos)
        if a < 0:
            return ''.join(out) + s[pos:]
        en, e = inner(s, a + len('<span data-en>'))
        m = re.compile(r'\s*<span data-id>').match(s, e)
        if not m:
            sys.exit('a data-en span at %d has no data-id span right after it' % a)
        idt, e2 = inner(s, m.end())
        out.append(s[pos:a] + '<span>' + T(en, idt) + '</span>')
        pos = e2


def build_page(src_name, page_dir, lang):
    code, slug, _, _, locale, terms = lang
    s = open(os.path.join(HERE, 'src', src_name), encoding='utf-8').read()
    tr = load(code) if code not in ('en', 'id') else {}
    extra = EXTRA.get(code, {})
    miss = set()

    def T(en, idtext=None):
        k = norm(en)
        if code == 'en':
            return en
        if code == 'id':
            return idtext if idtext is not None else extra.get(k, en)
        v = tr.get(k) or extra.get(k)
        if not v:
            miss.add(k)
            return en
        return v

    # text pairs
    s = pairs(s, T)
    # link pairs (terms)
    s = re.sub(r'<a href="([^"]*)" data-en>(.*?)</a><a href="([^"]*)" data-id>(.*?)</a>',
               lambda m: '<a href="%s">%s</a>' % (m.group(3) if code == 'id' else m.group(1), T(m.group(2), m.group(4))),
               s, flags=re.S)
    # plain alt texts and labels (the Indonesian alt texts come from the data-alt pairs)
    altmap = dict(re.findall(r'data-alt-en="([^"]*)" data-alt-id="([^"]*)"', s))
    s = re.sub(r'\balt="([^"]+)"', lambda m: 'alt="%s"' % T(m.group(1), altmap.get(m.group(1))).replace('"', '&quot;'), s)
    s = re.sub(r'\baria-label="([^"]+)"', lambda m: 'aria-label="%s"' % T(m.group(1)).replace('"', '&quot;'), s)
    # screenshot alt texts: the page script reads data-alt-id on the Indonesian page, data-alt-en elsewhere
    s = re.sub(r'data-alt-en="([^"]*)" data-alt-id="([^"]*)"',
               lambda m: 'data-alt-en="%s" data-alt-id="%s"' % (T(m.group(1), m.group(2)).replace('"', '&quot;'), m.group(2)), s)
    # title and meta
    s = re.sub(r'<title>([^<]*)</title>', lambda m: '<title>%s</title>' % T(m.group(1)), s)
    s = re.sub(r'(<meta (?:name|property)="(?:description|og:title|og:description)" content=")([^"]*)(")',
               lambda m: m.group(1) + T(m.group(2)).replace('"', '&quot;') + m.group(3), s)
    if '<span data-en>' in s or '<span data-id>' in s:
        sys.exit('%s: a data-en/data-id pair is not side by side, fix the source' % src_name)

    out_dir = (slug + '/' if slug else '') + page_dir           # e.g. "de/win/"
    # relative links: pages stay in this language, files point back to the shared ones
    pages = {'': '', 'index.html': '', 'win/': 'win/', 'win': 'win/', 'win/index.html': 'win/', 'mac/': ''}

    def fix(m):
        attr, url = m.group(1), m.group(2)
        if re.match(r'^(?:[a-z]+:|#|/|data:|\{)', url) or not slug:
            return m.group(0)
        path, _, frag = url.partition('#')
        target = posixpath.normpath(posixpath.join(page_dir or '.', path)) if path else (page_dir or '')
        target = '' if target == '.' else target
        if target in pages or target + '/' in pages:
            new = rel(out_dir, slug + '/' + pages.get(target, pages.get(target + '/')))
        else:
            new = posixpath.relpath(target, out_dir.rstrip('/'))
        return '%s="%s%s"' % (attr, new, ('#' + frag) if frag else '')
    s = re.sub(r'\b(href|src|poster|data-src)="([^"]*)"', fix, s)
    if slug:
        s = re.sub(r'\bsrcset="([^"]*)"',
                   lambda m: 'srcset="%s"' % ', '.join(
                       (posixpath.relpath(posixpath.normpath(posixpath.join(page_dir or '.', p.split()[0])), out_dir.rstrip('/'))
                        + (' ' + ' '.join(p.split()[1:]) if len(p.split()) > 1 else ''))
                       if not re.match(r'^(?:[a-z]+:|/|data:)', p.strip()) else p.strip()
                       for p in m.group(1).split(',')), s)
        # the Windows page script builds screenshot paths at run time
        s = s.replace("var f = 'shots/' +", "var f = '%s' +" % (posixpath.relpath('win/shots', out_dir.rstrip('/')) + '/'))

    # <html lang>, the language set before paint, and a nudge to the visitor's language on English pages
    s = s.replace('<html lang="en">', '<html lang="%s">' % code, 1)
    boot = re.search(r'<script>\n// Runs before paint.*?</script>', s, re.S)
    if not boot:
        sys.exit('%s: the before-paint script changed, update build.py' % src_name)
    slugs = {c.split('-')[0].lower(): sl for c, sl, *_ in LANGS if sl}
    js = {'locale': locale}
    js.update(EXTRA.get('_js', {}).get(code, {}))
    to_root = posixpath.relpath('.', out_dir.rstrip('/')) + '/' if out_dir else ''
    nudge = ''
    if not slug:
        nudge = ("var p=null;try{p=localStorage.getItem('lang')}catch(e){}"
                 "var m=%s;if(!p){var n=(navigator.language||'').toLowerCase();p=n.indexOf('zh')===0?'zh-cn':n.split('-')[0]}"
                 "p=m[p]||m[(p||'').split('-')[0]];"
                 "if(p&&!/[?&]lang=en/.test(location.search))location.replace('%s'+p+'/%s'+location.hash);"
                 % (json.dumps(dict(slugs, **{'zh-cn': 'zh-cn', 'pt-br': 'pt-br'})), to_root, page_dir))
    new_boot = ("<script>\n// Runs before paint: theme, and on the English page a first-visit nudge to the visitor's language.\n"
                "window.AMNESIA_I18N=%s;\n(function(){var d=document.documentElement,t=null;d.classList.add('js');\n"
                "try{t=localStorage.getItem('theme')}catch(e){}\nif(t==='light'||t==='dark')d.setAttribute('data-theme',t);%s})();\n</script>"
                % (json.dumps(js, ensure_ascii=False), nudge))
    s = s[:boot.start()] + new_boot + s[boot.end():]

    # hreflang alternates + og:url
    alts = ''.join('<link rel="alternate" hreflang="%s" href="%s%s%s">\n' % (c, SITE, (sl + '/') if sl else '', page_dir)
                   for c, sl, *_ in LANGS)
    alts += '<link rel="alternate" hreflang="x-default" href="%s%s">\n' % (SITE, page_dir)
    s = s.replace('<link rel="icon"', alts + '<link rel="icon"', 1)
    s = re.sub(r'(<meta property="og:url" content=")[^"]*(")', r'\g<1>%s%s%s\2' % (SITE, (slug + '/') if slug else '', page_dir), s)

    # language menu in place of the old EN/ID switch
    items = []
    for c, sl, name, short, *_ in LANGS:
        href = rel(out_dir, (sl + '/' if sl else '') + page_dir)
        if c == 'en':
            href += '?lang=en'
        cur = ' aria-current="page"' if c == code else ''
        items.append('<li><a href="%s" hreflang="%s" lang="%s"%s>%s<small>%s</small></a></li>' % (href, c, c, cur, name, short))
    me = [x for x in LANGS if x[0] == code][0]
    menu = ('<details class="langmenu"><summary aria-label="%s"><svg viewBox="0 0 24 24" aria-hidden="true">'
            '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.7 3.8 5.7 3.8 9s-1.3 6.3-3.8 9c-2.5-2.7-3.8-5.7-3.8-9S9.5 5.7 12 3z"/>'
            '</svg>%s</summary><ul>%s</ul></details>' % (T('Language').replace('"', '&quot;'), me[3], ''.join(items)))
    s, n = re.subn(r'<div class="lang" role="group" aria-label="[^"]*">.*?</div>', menu, s, flags=re.S)
    if n != 1:
        sys.exit('%s: language switch not found' % src_name)

    s = re.sub(r'\n?[ \t]*<!--(?!\[).*?-->', '', s, flags=re.S)   # notes for us, not for visitors
    dest = os.path.join(DOCS, out_dir, 'index.html')
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    open(dest, 'w', encoding='utf-8').write(s)
    return dest, miss


def main():
    total = 0
    for lang in LANGS:
        for src, page_dir in PAGES:
            dest, miss = build_page(src, page_dir, lang)
            total += len(miss)
            print('%-6s %-24s %s' % (lang[0], os.path.relpath(dest, ROOT), ('%d missing' % len(miss)) if miss else 'ok'))
            for m in sorted(miss)[:3]:
                print('         missing:', m[:90])
    print('done, %d missing translations (shown in English)' % total)


if __name__ == '__main__':
    main()
