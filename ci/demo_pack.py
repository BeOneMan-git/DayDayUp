"""Makes a small DayDayUp content pack (format 2) with ORIGINAL demo text, for the simulator smoke test in CI.

No magazine content: the two short articles, translations, word cards and questions below were written for
DayDayUp. Audio comes from the macOS `say` voice; word times are spread over each sentence by word length.
On a machine without `say`/`afconvert` (e.g. Linux) the audio is silence in a .wav, so the pack can still be
checked for structure.

Usage: python3 ci/demo_pack.py OUT.ecopack
"""
import hashlib, io, json, os, re, shutil, struct, subprocess, sys, tarfile, tempfile, wave
from datetime import datetime, timezone

ISSUE = '2026-01-03'
PACK_ID = 'demo-2026-01-03'

ARTICLES = [
    {
        'id': 'market', 'section': '生活', 'fly': 'Demo', 'title': 'A morning at the market', 'topics': ['社会'],
        'paras': [
            [("Every Saturday, the small market near the river opens at seven.", "每个星期六，河边的小市场七点开门。"),
             ("Farmers arrive early with fresh bread, apples and flowers.", "农民很早就带着新鲜的面包、苹果和鲜花来了。"),
             ("Many shoppers come on foot, carrying their own bags.", "很多顾客步行过来，自己带着购物袋。")],
            [("Prices are written on small boards, but people still like to chat before they pay.",
              "价格写在小木板上，但人们付钱前还是喜欢聊几句。"),
             ("For older residents, the market is a place to meet friends.", "对年长的居民来说，市场是和朋友见面的地方。"),
             ("For young families, it is a chance to show children where food comes from.",
              "对年轻的家庭来说，这是让孩子知道食物从哪里来的机会。")],
            [("By noon, most stalls are empty and the square is quiet again.", "到中午，大多数摊位都空了，广场又安静下来。")],
        ],
        'quiz': [
            ('main', 'What is the passage mainly about?', '这段话主要讲什么？',
             ['A weekly market and the people who use it', 'How farmers grow apples',
              'Why prices at markets are high', 'A new shopping centre by the river'], 0, '全文写每周六的市场和来这里的人，所以选 A。', [1, 4, 5]),
            ('detail', 'How do many shoppers get to the market?', '很多顾客怎么去市场？',
             ['By bus', 'On foot', 'By bicycle', 'By car'], 1, '第 3 句说很多顾客步行过来，所以选 B。', [2]),
            ('inference', 'What does the writer suggest about the market?', '作者暗示了市场的什么特点？',
             ['It is only for tourists', 'It matters for social life, not just shopping',
              'It is open every day', 'It is losing customers'], 1, '第 5–6 句说市场是见朋友、带孩子的地方，所以选 B。', [4, 5]),
        ],
    },
    {
        'id': 'trees', 'section': '环境', 'fly': 'Demo', 'title': 'Why cities plant trees', 'topics': ['环境'],
        'paras': [
            [("On a hot afternoon, a street with trees can feel several degrees cooler.",
              "在炎热的下午，有树的街道会让人感觉凉快好几度。"),
             ("Leaves block sunlight, and water evaporating from them cools the air.",
              "树叶挡住阳光，叶子里蒸发的水分让空气变凉。"),
             ("Trees also catch rain, which reduces the risk of floods.", "树还能接住雨水，减少发生洪水的风险。")],
            [("However, planting a tree is cheaper than keeping it alive.", "不过，种一棵树比让它活下去便宜。"),
             ("Young trees need water, space for their roots and protection from damage.",
              "小树需要水、根系生长的空间，还要防止受到损伤。")],
            [("Some cities now ask residents to adopt a tree and water it in summer.",
              "现在一些城市请居民认养一棵树，夏天给它浇水。"),
             ("The results are encouraging: more trees survive their first three years.",
              "结果令人鼓舞：更多的树活过了最初三年。")],
        ],
        'quiz': [
            ('main', 'What is the main point of the passage?', '这段话的主要观点是什么？',
             ['Trees help cities, but they need care to survive', 'Cities should stop planting trees',
              'Trees cause floods in cities', 'Only old trees are useful'], 0, '全文先讲树的好处，再讲要照顾小树，所以选 A。', [0, 3, 6]),
            ('detail', 'How do leaves make the air cooler?', '树叶怎样让空气变凉？',
             ['By making wind', 'By blocking sunlight and releasing water',
              'By absorbing noise', 'By growing very fast'], 1, '第 2 句说树叶挡住阳光、蒸发水分，所以选 B。', [1]),
            ('detail', 'What do some cities ask residents to do?', '一些城市请居民做什么？',
             ['Plant flowers in parks', 'Pay a tree tax', 'Adopt a tree and water it',
              'Cut down old trees'], 2, '第 6 句说请居民认养一棵树并浇水，所以选 C。', [5]),
            ('word', 'In the passage, "encouraging" is closest in meaning to', '文中 encouraging 的意思最接近哪一项？',
             ['worrying', 'surprising', 'hopeful', 'expensive'], 2, '第 7 句说结果令人鼓舞，即 hopeful，所以选 C。', [6]),
        ],
    },
]

# key -> (band, cefr, gloss, card or None)
LEXICON = {
    'resident': (6, 'B2', 'n. 居民', {
        'pos': 'n.', 'ipa': {'br': '/ˈrezɪdənt/', 'am': '/ˈrezɪdənt/', 'ai': False},
        'ctx': [{'sid': 'market:4', 'm': '居民：住在这一带的人。'}],
        'senses': [{'pos': 'n.', 'zh': '居民；住户', 'en': 'a person who lives in a particular place'}],
        'colloc': [{'en': 'local residents', 'zh': '当地居民'}],
        'ielts': {'en': 'Local residents should have a say in how parks are used.', 'zh': '当地居民应该对公园怎么用有发言权。', 'use': '写作 Task 2'}}),
    'stall': (6, 'B2', 'n. 货摊；摊位', {
        'pos': 'n.', 'ipa': {'br': '/stɔːl/', 'am': '/stɔːl/', 'ai': False},
        'ctx': [{'sid': 'market:6', 'm': '摊位：市场里卖东西的小台子。'}],
        'senses': [{'pos': 'n.', 'zh': '货摊；摊位', 'en': 'a table or small shop in a market'},
                   {'pos': 'v.', 'zh': '（车）熄火；拖延', 'en': 'to stop working suddenly; to delay'}]}),
    'evaporate': (7, 'C1', 'v. 蒸发', {
        'pos': 'v.', 'ipa': {'br': '/ɪˈvæpəreɪt/', 'am': '/ɪˈvæpəreɪt/', 'ai': False},
        'ctx': [{'sid': 'trees:1', 'm': '蒸发：水从叶子变成水汽散到空气里。'}],
        'senses': [{'pos': 'v.', 'zh': '蒸发', 'en': 'to change from liquid into gas'},
                   {'pos': 'v.', 'zh': '逐渐消失', 'en': 'to disappear gradually'}]}),
    'encouraging': (6, 'B2', 'adj. 令人鼓舞的', {
        'pos': 'adj.', 'ipa': {'br': '/ɪnˈkʌrɪdʒɪŋ/', 'am': '/ɪnˈkɜːrɪdʒɪŋ/', 'ai': False},
        'ctx': [{'sid': 'trees:6', 'm': '令人鼓舞的：结果比预想的好。'}],
        'senses': [{'pos': 'adj.', 'zh': '令人鼓舞的；给人希望的', 'en': 'giving hope or confidence'}]}),
    'adopt': (6, 'B2', 'v. 收养；采用', {
        'pos': 'v.', 'ipa': {'br': '/əˈdɒpt/', 'am': '/əˈdɑːpt/', 'ai': False},
        'ctx': [{'sid': 'trees:5', 'm': '认养：负责照顾一棵树。'}],
        'senses': [{'pos': 'v.', 'zh': '收养；认养', 'en': 'to take and look after as your own'},
                   {'pos': 'v.', 'zh': '采用', 'en': 'to start to use a plan or method'}]}),
    'survive': (6, 'B2', 'v. 存活', None),
    'protection': (6, 'B2', 'n. 保护', None),
    'reduce': (5, 'B1', 'v. 减少', None),
    'degree': (5, 'B1', 'n. 度；程度', None),
    'flood': (5, 'B1', 'n. 洪水', None),
    'sunlight': (5, 'B1', 'n. 阳光', None),
    'farmer': (5, 'A2', 'n. 农民', None),
}
LEMMA = {'residents': 'resident', 'stalls': 'stall', 'evaporating': 'evaporate', 'survive': 'survive',
         'reduces': 'reduce', 'degrees': 'degree', 'floods': 'flood', 'farmers': 'farmer'}


def tokens(sentence):
    out = []
    for raw in sentence.split(' '):
        m = re.match(r'^([“"(]*)(.*?)([.,:;!?”")]*)$', raw)
        a, w, z = m.group(1), m.group(2), m.group(3)
        key = w.lower()
        tok = {'w': w, 'k': LEMMA.get(key, key)}
        if a:
            tok['a'] = a
        if z:
            tok['z'] = z
        out.append(tok)
    return out


def silence(path, seconds):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(22050)
        w.writeframes(b'\0\0' * int(22050 * seconds))


def speak(text, path, rate=175):
    """WAV of `text` (16-bit mono 22.05 kHz). Uses the macOS voice when there is one; otherwise, or when the
    voice fails, silence of about the right length (the screenshots do not need sound)."""
    fallback = max(1.0, 0.36 * len(text.split()))
    if shutil.which('say') and shutil.which('afconvert'):
        aiff = path + '.aiff'
        try:
            subprocess.run(['say', '-r', str(rate), '-o', aiff, text], check=True, capture_output=True, timeout=60)
            subprocess.run(['afconvert', '-f', 'WAVE', '-d', 'LEI16@22050', '-c', '1', aiff, path],
                           check=True, capture_output=True, timeout=60)
            ch, sw, fr, _ = read_wav(path)
            if (ch, sw, fr) == (1, 2, 22050):
                return
            print(f'voice output has an unexpected format {(ch, sw, fr)}; using silence', file=sys.stderr)
        except Exception as e:  # any failure falls back to silence
            print(f'voice failed ({e}); using silence', file=sys.stderr)
    silence(path, fallback)


def read_wav(path):
    """(channels, bytes per sample, rate, PCM bytes). A small RIFF reader: it also accepts the
    WAVE_FORMAT_EXTENSIBLE header that Python's `wave` module rejects before 3.12."""
    data = open(path, 'rb').read()
    if data[:4] != b'RIFF' or data[8:12] != b'WAVE':
        raise ValueError('not a WAVE file')
    pos = 12
    fmt = pcm = None
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = int.from_bytes(data[pos + 4:pos + 8], 'little')
        body = data[pos + 8:pos + 8 + size]
        if cid == b'fmt ':
            fmt = body
        elif cid == b'data':
            pcm = body
        pos += 8 + size + (size & 1)
    if fmt is None or pcm is None:
        raise ValueError('WAVE file without fmt or data')
    _, channels, rate = struct.unpack('<HHI', fmt[:8])
    bits = struct.unpack('<H', fmt[14:16])[0]
    return channels, bits // 8, rate, pcm


def build_article(spec, tmp):
    rate = 22050
    chunks = []
    t = 1.0
    chunks.append(b'\0\0' * int(rate * 1.0))

    def add(text):
        nonlocal t
        p = os.path.join(tmp, 'part.wav')
        speak(text, p)
        ch, sw, fr, data = read_wav(p)
        assert (ch, sw, fr) == (1, 2, rate), (ch, sw, fr)
        start = t
        dur = len(data) / (2 * rate)
        chunks.append(data)
        gap = b'\0\0' * int(rate * 0.45)
        chunks.append(gap)
        t = start + dur + 0.45
        return start, start + dur

    title_start, title_end = add(spec['title'])
    paras = []
    sid = 0
    tok_index = 0
    for pn, para in enumerate(spec['paras']):
        sents = []
        for text, zh in para:
            s, e = add(text)
            toks = tokens(text)
            weights = [len(tk['w']) + 2 for tk in toks]
            total = sum(weights)
            cur = s + 0.05
            span = (e - s) - 0.1
            for tk, wgt in zip(toks, weights):
                d = span * wgt / total
                tk['i'] = tok_index
                tok_index += 1
                tk['s'] = round(cur, 2)
                tk['e'] = round(cur + d, 2)
                cur += d
            sents.append({'id': sid, 's': round(s, 2), 'e': round(e, 2), 'zh': zh, 'toks': toks, 'al': 'machine'})
            sid += 1
        paras.append({'kind': 'p', 'pid': f"{spec['id']}-p{pn + 1}", 'sents': sents})
    wav_path = os.path.join(tmp, spec['id'] + '.wav')
    with wave.open(wav_path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b''.join(chunks))
    dur = round(t + 0.5, 2)
    out = os.path.join(tmp, spec['id'] + '.m4a')
    converted = False
    if shutil.which('afconvert'):
        r = subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', '-b', '64000', wav_path, out], capture_output=True)
        converted = r.returncode == 0 and os.path.exists(out)
        if not converted:
            print(f'afconvert to m4a failed: {r.stderr.decode(errors="replace")[:300]}', file=sys.stderr)
    if converted:
        audio_name = f"audio/{spec['id']}.m4a"
        audio = open(out, 'rb').read()
        media = 'audio/mp4'
    else:
        audio_name = f"audio/{spec['id']}.wav"
        audio = open(wav_path, 'rb').read()
        media = 'audio/wav'
    article = {'id': spec['id'], 'issue': ISSUE, 'section': spec['section'], 'fly': spec['fly'], 'title': spec['title'],
               'dur': dur, 'titleStart': round(title_start, 2), 'titleEnd': round(title_end, 2), 'paras': paras}
    quiz = {'articleId': spec['id'], 'segment': [paras[0]['sents'][0]['s'], paras[-1]['sents'][-1]['e']],
            'questions': [{'id': f'q{n + 1}', 'kind': k, 'q': q, 'zh': zh, 'options': opts, 'answer': ans,
                           'explain': ex, 'inSegment': True, 'sids': sids}
                          for n, (k, q, zh, opts, ans, ex, sids) in enumerate(spec['quiz'])]}
    nwords = sum(len(s['toks']) for p in paras for s in p['sents'])
    meta = {'id': spec['id'], 'section': spec['section'], 'fly': spec['fly'], 'title': spec['title'], 'dur': dur,
            'nw': nwords, 'ns': sid, 'n5': 5, 'topics': spec['topics'], 'audio': audio_name, 'contentRevision': 1,
            'deps': {'text': 'available', 'audio': 'available', 'timing': 'available', 'wordAudio': 'available',
                     'senses': 'available', 'annotations': 'missing', 'quiz': 'available', 'pdf': 'not-required'}}
    return meta, article, quiz, audio_name, audio, media


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else 'demo.ecopack'
    tmp = tempfile.mkdtemp()
    body = {}
    metas = []
    media_types = {}
    lex = {'entries': {}, 'xent': {}}
    for key, (band, cefr, zh, card) in LEXICON.items():
        entry = {'b': band, 'cefr': cefr, 'zh': zh}
        if card:
            entry['card'] = card
        lex['entries'][key] = entry
    body['lexicon.json'] = json.dumps(lex, ensure_ascii=False).encode()
    media_types['lexicon.json'] = 'application/json'
    for spec in ARTICLES:
        meta, article, quiz, audio_name, audio, media = build_article(spec, tmp)
        metas.append(meta)
        body[f"articles/{spec['id']}.json"] = json.dumps(article, ensure_ascii=False).encode()
        body[f"quiz/{spec['id']}.json"] = json.dumps(quiz, ensure_ascii=False).encode()
        body[audio_name] = audio
        media_types[audio_name] = media
    assets = []
    for name, blob in body.items():
        assets.append({'path': name, 'byteLength': len(blob), 'sha256': hashlib.sha256(blob).hexdigest(),
                       'mediaType': media_types.get(name, 'application/json')})
    created = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    manifest = {
        'format': 2, 'schemaVersion': 2, 'packId': PACK_ID, 'packageId': PACK_ID, 'packageRevision': 1,
        'issue': ISSUE, 'part': 1, 'parts': 1, 'title': 'DayDayUp 演示内容包', 'version': f'{PACK_ID}.r1',
        'created': created[:10], 'createdAt': created, 'producer': 'DayDayUp ci/demo_pack.py 1.0',
        'sourceInfo': {'publication': 'DayDayUp 原创演示', 'issue': ISSUE, 'note': '原创文字和系统合成语音，只用于测试截图。'},
        'provenance': {'cards': 'checked', 'translation': 'checked', 'quiz': 'checked'},
        'articles': metas, 'assets': assets,
        'files': {a['path']: {'size': a['byteLength'], 'sha256': a['sha256']} for a in assets},
    }
    files = {'manifest.json': json.dumps(manifest, ensure_ascii=False, indent=1).encode()}
    files.update(body)
    with tarfile.open(out_path, 'w', format=tarfile.USTAR_FORMAT) as t:
        for name, blob in files.items():
            ti = tarfile.TarInfo(name)
            ti.size = len(blob)
            ti.mtime = 1790500000
            ti.mode = 0o644
            t.addfile(ti, io.BytesIO(blob))
    print(f'{out_path}: {os.path.getsize(out_path)} bytes, {len(metas)} articles')


if __name__ == '__main__':
    main()
