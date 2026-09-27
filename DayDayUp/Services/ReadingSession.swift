import Foundation
import Observation

enum InspectorTab: String, Hashable, CaseIterable {
    case card, sentence, list

    var title: String {
        switch self {
        case .card: return "单词"
        case .sentence: return "句子"
        case .list: return "词表"
        }
    }
}

struct TokInfo {
    let tok: Tok
    let sid: Int
    let pi: Int
}

/// How one word is marked in the text.
struct WordMark: Equatable {
    var band = 0          // IELTS level 5...8, 0 = basic word
    var known = false
    var star = false
    var trap = false      // familiar word with a rare sense (熟词僻义)
    var phrase = false
}

struct VocabRow: Identifiable, Hashable {
    let key: String
    let band: Int
    let tokIndex: Int
    let sid: Int
    var id: String { key }
}

/// The article that is open in the reader, its playback-driven highlight,
/// loop / step modes, and listening progress.
@MainActor
@Observable
final class ReadingSession {
    // Article
    private(set) var ref: ArticleRef?
    private(set) var article: Article?
    private(set) var loadError: String?

    // Highlight driven by the audio clock
    private(set) var curTok: Int?
    private(set) var curSent: Int?
    private(set) var titleOn = false

    // Modes and selection
    private(set) var loopSid: Int?
    private(set) var stepMode = false
    var blind = false
    var selectedTok: Int?
    var inspectorTab: InspectorTab = .card
    var showInspector = false
    var sentenceInPanel: Int?
    private(set) var marksVersion = 0
    var toast: String?
    private(set) var toastID = 0
    private(set) var scrollTarget: Int?        // paragraph index to reveal
    private(set) var scrollRequestID = 0

    // Indexes, rebuilt when an article opens (not observed)
    @ObservationIgnored private(set) var toks: [Int: TokInfo] = [:]
    @ObservationIgnored private(set) var sents: [Int: Sent] = [:]
    @ObservationIgnored private(set) var sentPara: [Int: Int] = [:]
    @ObservationIgnored private(set) var order: [Sent] = []      // timed sentences by start time
    @ObservationIgnored private var timed: [Tok] = []            // timed tokens by start time
    @ObservationIgnored private var trapToks: Set<Int> = []
    @ObservationIgnored private var phraseToks: Set<Int> = []
    @ObservationIgnored private var entities: [String: Ann] = [:]
    @ObservationIgnored private var bands: [Int: Int] = [:]
    @ObservationIgnored private var known: Set<String> = []
    @ObservationIgnored private var starred: Set<String> = []
    @ObservationIgnored private var stepTarget: Double?
    @ObservationIgnored private var isLoopSeeking = false

    // Listening progress, flushed to UserStore every 15 s
    @ObservationIgnored private var pendingSeconds: Double = 0
    @ObservationIgnored private var pendingBuckets: Set<Int> = []
    @ObservationIgnored private var pendingTextBuckets: Set<Int> = []
    @ObservationIgnored private var lastWall: Date?
    @ObservationIgnored private var lastFlush = Date()

    let engine: PlaybackEngine
    let packs: PackStore
    let user: UserStore

    init(engine: PlaybackEngine, packs: PackStore, user: UserStore) {
        self.engine = engine
        self.packs = packs
        self.user = user
        engine.setRate(user.settings.rate)
        engine.onTick = { [weak self] t in self?.tick(t) }
        engine.onNextSentence = { [weak self] in self?.moveSentence(1) }
        engine.onPreviousSentence = { [weak self] in self?.moveSentence(-1) }
    }

    // MARK: Opening an article

    func open(_ newRef: ArticleRef) {
        if ref == newRef && article != nil { return }
        flushProgress()
        do {
            let art = try packs.loadArticle(newRef)
            buildIndexes(art)
            ref = newRef
            article = art
            loadError = nil
            curTok = nil
            curSent = nil
            titleOn = false
            loopSid = nil
            stepTarget = nil
            selectedTok = nil
            sentenceInPanel = nil
            if let url = packs.audioURL(newRef) {
                engine.load(url: url, title: art.title, album: "The Economist · \(art.issue)",
                            duration: art.dur, startAt: user.state.positions[newRef.key] ?? 0)
            }
            user.update { $0.lastArticle = newRef.key }
            tick(engine.time)
        } catch {
            ref = newRef
            article = nil
            loadError = error.localizedDescription
        }
    }

    private func buildIndexes(_ art: Article) {
        var toks: [Int: TokInfo] = [:]
        var sents: [Int: Sent] = [:]
        var sentPara: [Int: Int] = [:]
        var order: [Sent] = []
        var timed: [Tok] = []
        var trap = Set<Int>()
        var phrase = Set<Int>()
        var ents: [String: Ann] = [:]
        for (pi, para) in art.paras.enumerated() {
            for s in para.sents {
                sents[s.id] = s
                sentPara[s.id] = pi
                if s.isTimed { order.append(s) }
                for t in s.toks {
                    toks[t.i] = TokInfo(tok: t, sid: s.id, pi: pi)
                    if t.s != nil { timed.append(t) }
                }
                for a in s.ann ?? [] {
                    if a.t == "e", let text = a.text { ents[text] = a }
                    if a.t == "s" || a.t == "p", a.r.count == 2, a.r[0] <= a.r[1] {
                        for i in a.r[0]...a.r[1] {
                            if a.t == "s" { trap.insert(i) } else { phrase.insert(i) }
                        }
                    }
                }
            }
        }
        timed.sort { ($0.s ?? 0) < ($1.s ?? 0) }
        order.sort { ($0.s ?? 0) < ($1.s ?? 0) }
        self.toks = toks
        self.sents = sents
        self.sentPara = sentPara
        self.order = order
        self.timed = timed
        self.trapToks = trap
        self.phraseToks = phrase
        self.entities = ents
        refreshMarks()
    }

    /// Recomputes levels (needs the merged lexicon) and the learner's known / starred words.
    func refreshMarks() {
        var levels: [Int: Int] = [:]
        for (i, info) in toks {
            if let e = packs.entry(info.tok.k), let b = e.b, b >= 5, e.pn != true, e.num != true {
                levels[i] = b
            }
        }
        bands = levels
        known = Set(user.state.known.keys)
        starred = Set(user.state.star.keys)
        marksVersion += 1
    }

    func mark(for t: Tok) -> WordMark {
        var m = WordMark()
        m.band = bands[t.i] ?? 0
        if let k = t.k {
            m.known = known.contains(k)
            m.star = starred.contains(k)
        }
        m.trap = trapToks.contains(t.i)
        m.phrase = phraseToks.contains(t.i)
        return m
    }

    func band(ofToken i: Int) -> Int { bands[i] ?? 0 }
    func isTrap(_ i: Int) -> Bool { trapToks.contains(i) }

    // MARK: Clock

    private func tick(_ t: Double) {
        guard let art = article else { return }

        // Current word: keep it lit 0.35 s after it ends, or until the next word starts.
        let ti = ReadingSession.lastIndex(timed, atOrBefore: t) { $0.s ?? 0 }
        var newTok: Int?
        if ti >= 0 {
            let tk = timed[ti]
            let end = tk.e ?? (tk.s ?? 0)
            if t <= end + 0.35 || (ti + 1 < timed.count && t < (timed[ti + 1].s ?? 0)) {
                newTok = tk.i
            }
        }

        // Current sentence; none while the headline is being read.
        let titleStart = art.titleStart ?? 0
        let titleEnd = art.titleEnd ?? 0
        let si = ReadingSession.lastIndex(order, atOrBefore: t) { $0.s ?? 0 }
        var newSent: Int? = si >= 0 ? order[si].id : nil
        if titleEnd > 0 && t < titleEnd + 0.2 { newSent = nil }
        let newTitle = titleEnd > 0 && t >= titleStart && t < titleEnd + 0.3

        if newTok != curTok { curTok = newTok }
        if newSent != curSent { curSent = newSent }
        if newTitle != titleOn { titleOn = newTitle }

        // Sentence loop and step-by-step pause.
        if let ls = loopSid, let s = sents[ls], let start = s.s, let end = s.e {
            // seek() calls tick() again at once; the flag stops a loop on very short sentences.
            if engine.isPlaying && !isLoopSeeking && (t >= end - 0.03 || t < start - 0.5) {
                isLoopSeeking = true
                engine.seek(to: start)
                isLoopSeeking = false
            }
        } else if stepMode && engine.isPlaying {
            if stepTarget == nil { stepTarget = nextSentenceEnd(after: t) }
            if let target = stepTarget, t >= target - 0.05 {
                stepTarget = nil
                engine.pause()
                engine.seek(to: target)
                showToast("逐句暂停：点 ▶ 继续下一句")
            }
        }

        track(t)
    }

    private func nextSentenceEnd(after t: Double) -> Double? {
        order.first { ($0.e ?? 0) > t + 0.1 }?.e
    }

    /// Index of the last element whose start <= t, or -1.
    static func lastIndex<T>(_ items: [T], atOrBefore t: Double, start: (T) -> Double) -> Int {
        var lo = 0
        var hi = items.count - 1
        var found = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if start(items[mid]) <= t {
                found = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return found
    }

    // MARK: Transport

    func togglePlay() {
        if engine.isPlaying {
            engine.pause()
            flushProgress()
        } else {
            stepTarget = nil
            sentenceInPanel = nil
            engine.play()
        }
    }

    func playSentence(_ sid: Int, autoplay: Bool = true) {
        guard let s = sents[sid], let start = s.s else { return }
        if loopSid != nil { loopSid = sid }
        stepTarget = nil
        engine.seek(to: max(0, start - 0.05))
        if autoplay { engine.play() }
    }

    /// Previous (-1) or next (+1) sentence. "Previous" first restarts the current
    /// sentence if more than 1.2 s of it has played.
    func moveSentence(_ direction: Int) {
        guard !order.isEmpty else { return }
        let t = engine.time
        var i = ReadingSession.lastIndex(order, atOrBefore: t + 0.01) { $0.s ?? 0 }
        if i < 0 { i = 0 }
        let target: Sent
        if direction < 0 {
            let s = order[i]
            target = t - (s.s ?? 0) > 1.2 ? s : order[max(0, i - 1)]
        } else {
            target = order[min(order.count - 1, i + 1)]
        }
        playSentence(target.id, autoplay: engine.isPlaying)
    }

    func toggleLoop() {
        if loopSid != nil {
            loopSid = nil
            showToast("单句循环：关")
            return
        }
        let fromSelection = selectedTok.flatMap { toks[$0]?.sid }
        guard let sid = curSent ?? fromSelection ?? order.first?.id else { return }
        loopSid = sid
        showToast("单句循环：第 \(position(of: sid)) 句")
        if !engine.isPlaying { playSentence(sid) }
    }

    func loopSentence(_ sid: Int) {
        loopSid = sid
        playSentence(sid)
        showToast("循环本句：再点“单句循环”关闭")
    }

    func toggleStepMode() {
        stepMode.toggle()
        stepTarget = nil
        showToast(stepMode ? "逐句暂停：开" : "逐句暂停：关")
    }

    func setRate(_ rate: Double) {
        engine.setRate(rate)
        user.updateSettings { $0.rate = rate }
    }

    func position(of sid: Int) -> Int {
        (order.firstIndex { $0.id == sid } ?? 0) + 1
    }

    var sentenceCount: Int { order.count }

    // MARK: Selection

    func tapToken(_ i: Int) {
        guard let info = toks[i] else { return }
        if user.settings.pauseOnTap && engine.isPlaying {
            engine.pause()
            flushProgress()
        }
        selectedTok = i
        sentenceInPanel = info.sid
        inspectorTab = .card
        showInspector = true
        if let k = info.tok.k {
            user.update { $0.lookups[k, default: 0] += 1 }
        }
    }

    /// Selects a word from a list and scrolls the text to it.
    func reveal(_ i: Int) {
        guard let info = toks[i] else { return }
        selectedTok = i
        sentenceInPanel = info.sid
        inspectorTab = .card
        showInspector = true
        scrollTarget = info.pi
        scrollRequestID += 1
    }

    func showSentence(_ sid: Int) {
        sentenceInPanel = sid
        inspectorTab = .sentence
        showInspector = true
    }

    func info(_ i: Int) -> TokInfo? { toks[i] }
    func sentence(_ sid: Int) -> Sent? { sents[sid] }
    func paragraphIndex(ofSentence sid: Int) -> Int? { sentPara[sid] }
    func paragraphIndex(ofToken i: Int) -> Int? { toks[i]?.pi }

    /// Meaning of a card in this sentence of the open article.
    func context(_ card: Card?, sid: Int) -> Ctx? {
        guard let card, let ref else { return nil }
        let key = "\(ref.id):\(sid)"
        return card.ctx?.first { $0.sid == key }
    }

    /// Background for a proper noun: annotated entities first, then the global list.
    func entity(for word: String) -> (text: String, zh: String?, bg: String?)? {
        if let x = packs.xent[word] { return (word, x.zh, x.bg) }
        if let a = entities[word] { return (a.text ?? word, a.zh, a.bg) }
        for (name, a) in entities {
            let parts = name.split(whereSeparator: { $0 == " " || $0 == "’" }).map(String.init)
            if parts.contains(word) { return (a.text ?? name, a.zh, a.bg) }
        }
        return nil
    }

    func toggleStar(_ key: String) {
        user.toggleStar(key)
        refreshUserMarks()
        showToast(user.isStarred(key) ? "已加入生词本" : "已移出生词本")
    }

    func toggleKnown(_ key: String) {
        user.toggleKnown(key)
        refreshUserMarks()
        showToast(user.isKnown(key) ? "已标为认识：正文不再标注" : "已取消认识")
    }

    private func refreshUserMarks() {
        known = Set(user.state.known.keys)
        starred = Set(user.state.star.keys)
        marksVersion += 1
    }

    /// IELTS 5+ words of the open article, in reading order, one row per word.
    func vocabRows() -> [VocabRow] {
        guard let art = article else { return [] }
        var seen = Set<String>()
        var rows: [VocabRow] = []
        for para in art.paras {
            for s in para.sents {
                for t in s.toks {
                    let b = bands[t.i] ?? 0
                    guard b > 0, let k = t.k, !seen.contains(k) else { continue }
                    seen.insert(k)
                    rows.append(VocabRow(key: k, band: b, tokIndex: t.i, sid: s.id))
                }
            }
        }
        return rows
    }

    static func plainText(_ s: Sent) -> String {
        var out = ""
        for (n, t) in s.toks.enumerated() {
            out += (t.a ?? "") + t.w + (t.z ?? "")
            if n < s.toks.count - 1 {
                switch t.j {
                case "-": out += "-"
                case "_": break
                default: out += " "
                }
            }
        }
        return out
    }

    // MARK: Toast

    func showToast(_ text: String) {
        toast = text
        toastID += 1
    }

    // MARK: Listening progress

    private func track(_ t: Double) {
        guard ref != nil, engine.isPlaying else {
            lastWall = nil
            return
        }
        let now = Date()
        if let last = lastWall {
            let dt = now.timeIntervalSince(last)
            if dt > 0 && dt < 1 { pendingSeconds += dt }
        }
        lastWall = now
        let bucket = Int(t / UserState.bucketSeconds)
        pendingBuckets.insert(bucket)
        if !blind { pendingTextBuckets.insert(bucket) }
        if now.timeIntervalSince(lastFlush) > 15 { flushProgress() }
    }

    func flushProgress() {
        lastFlush = Date()
        guard let ref, article != nil else { return }
        let key = ref.key
        let seconds = pendingSeconds
        let buckets = pendingBuckets
        let textBuckets = pendingTextBuckets
        let position = engine.time
        pendingSeconds = 0
        pendingBuckets = []
        pendingTextBuckets = []
        user.update { s in
            if seconds > 0 { s.daily[DayKey.today, default: 0] += seconds }
            if !buckets.isEmpty {
                s.heard[key] = Array(Set(s.heard[key] ?? []).union(buckets)).sorted()
            }
            if !textBuckets.isEmpty {
                s.heardText[key] = Array(Set(s.heardText[key] ?? []).union(textBuckets)).sorted()
            }
            s.positions[key] = position
        }
    }
}
