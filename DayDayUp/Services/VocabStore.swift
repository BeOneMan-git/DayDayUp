import Foundation
import Observation

/// What happened in one answer, besides the rating (DATA-08).
struct AnswerDetails {
    var correct: Bool? = nil
    var answer: String? = nil
    var expected: String? = nil
    var hint = 0
    var revealedEarly = false
    var userAccepted = false
    var durationMs = 0
    var evidence: String? = nil
    var source: String? = nil
}

/// Evidence for one ability of one item (MET-03 / VOC-F01). Never merged into one "mastered" number.
struct AbilityStatus: Equatable {
    var enabled = false          // a card for this ability exists and is not paused
    var reviews = 0              // answers, taken-back ones excluded
    var independent = 0          // first answers of the day without seeing the answer first
    var independentSuccess = 0   // …that were remembered (记得 / 轻松, or correct)
    var longInterval = false     // current interval ≥ 21 days ("较长复习间隔", not "掌握")
    var due: Date? = nil
    var lastAt: Date? = nil

    var label: String {
        if !enabled && reviews == 0 { return "未开始" }
        if reviews == 0 { return "新任务" }
        if longInterval { return "较长复习间隔" }
        return "\(independentSuccess)/\(independent) 次独立回忆成功"
    }
}

/// Owns vocab.json (items, cards, settings) and vocab-events.jsonl (append-only answers).
@MainActor
@Observable
final class VocabStore {
    private(set) var state: VocabState
    private(set) var events: [ReviewEvent]
    private(set) var saveError: String?
    private(set) var badEventLines = 0

    let fileURL: URL
    let eventsURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    static let longIntervalDays = 21

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        fileURL = support.appendingPathComponent("vocab.json")
        eventsURL = support.appendingPathComponent("vocab-events.jsonl")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? DataCoding.decoder.decode(VocabState.self, from: data) {
            state = loaded
        } else {
            state = VocabState()
            if fm.fileExists(atPath: fileURL.path) {
                let copy = support.appendingPathComponent("vocab-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.copyItem(at: fileURL, to: copy)
                DiagLog.shared.log("vocab", "vocab.json unreadable, copied to \(copy.lastPathComponent)")
            }
        }
        let read = JSONLines<ReviewEvent>(url: eventsURL).readAll()
        events = read.records
        badEventLines = read.badLines
        if read.badLines > 0 {
            DiagLog.shared.log("vocab", "skipped \(read.badLines) unreadable event lines")
        }
    }

    var settings: VocabSettings { state.settings }
    var scheduler: FSRSScheduler { FSRSScheduler(desiredRetention: state.settings.retention) }

    // MARK: Saving

    func update(_ change: (inout VocabState) -> Void) {
        var copy = state
        change(&copy)
        guard copy != state else { return }
        state = copy
        scheduleSave()
    }

    func updateSettings(_ change: (inout VocabSettings) -> Void) {
        update { change(&$0.settings) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            let data = try DataCoding.encoder.encode(state)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saveError = nil
        } catch {
            saveError = error.localizedDescription
            DiagLog.shared.log("vocab", "save failed: \(error.localizedDescription)")
        }
    }

    private func appendEvents(_ list: [ReviewEvent]) {
        do {
            try JSONLines<ReviewEvent>(url: eventsURL).append(list)
            events.append(contentsOf: list)
        } catch {
            // Keep the answer in memory so the session goes on; say so in the diagnostics.
            events.append(contentsOf: list)
            saveError = "复习记录没写进文件：\(error.localizedDescription)"
            DiagLog.shared.log("vocab", "event append failed: \(error.localizedDescription)")
        }
    }

    // MARK: Lookup

    var activeItems: [VocabItem] { state.items.filter { !$0.archived } }

    func item(_ id: String) -> VocabItem? {
        state.items.first { $0.id == id }
    }

    func card(_ id: String) -> VocabCard? {
        state.cards.first { $0.id == id }
    }

    func cards(for itemId: String) -> [VocabCard] {
        state.cards.filter { $0.itemId == itemId }
            .sorted { VocabTask.allCases.firstIndex(of: $0.task)! < VocabTask.allCases.firstIndex(of: $1.task)! }
    }

    func items(forKey key: String) -> [VocabItem] {
        state.items.filter { $0.kind == .sense && $0.key == key && !$0.archived }
    }

    /// Lexicon keys with at least one saved sense (marks words in the reader).
    var savedKeys: Set<String> {
        Set(state.items.filter { $0.kind == .sense && !$0.archived }.compactMap { $0.key })
    }

    func hasItem(forKey key: String) -> Bool {
        state.items.contains { $0.kind == .sense && $0.key == key && !$0.archived }
    }

    func chunk(text: String) -> VocabItem? {
        item(VocabItem.chunkID(text))
    }

    func events(for itemId: String) -> [ReviewEvent] {
        events.filter { $0.itemId == itemId }
    }

    // MARK: Adding

    /// Saves one sense of a word (VOC-F02). The same sense again adds the new context instead of a copy.
    @discardableResult
    func saveSense(key: String, text: String, pos: String?, gloss: String, senseIndex: Int?,
                   occurrence: Occurrence?, origin: VocabItem.Origin, note: String? = nil,
                   created: Date = Date(), openTasks: [VocabTask] = [.recognize]) -> VocabItem {
        var id = VocabItem.senseID(key: key, senseIndex: senseIndex)
        if senseIndex == nil, let occurrence {
            id = "s:\(key)#c\(SentenceText.hash(occurrence.sentenceKey))"
        }
        if var existing = item(id) {
            if let occurrence, !existing.sources.contains(where: { $0.sentenceKey == occurrence.sentenceKey }) {
                existing.sources.append(occurrence)
            }
            existing.archived = false
            let updated = existing
            update { s in
                if let i = s.items.firstIndex(where: { $0.id == id }) { s.items[i] = updated }
            }
            ensureCards(itemId: id, tasks: openTasks, created: created)
            return updated
        }
        var item = VocabItem(id: id, kind: .sense, key: key, text: text, gloss: gloss, created: created, origin: origin)
        item.pos = pos
        item.senseIndex = senseIndex
        item.note = note
        if let occurrence { item.sources = [occurrence] }
        update { $0.items.append(item) }
        ensureCards(itemId: id, tasks: openTasks, created: created)
        DiagLog.shared.log("vocab", "saved sense \(id)")
        return item
    }

    /// Saves a lexical chunk (DATA-06). Thought groups (意群) never come here; they stay in 跟读 annotations.
    @discardableResult
    func saveChunk(text: String, gloss: String, note: String?, variants: [String]? = nil, function: String? = nil,
                   occurrence: Occurrence?, origin: VocabItem.Origin, created: Date = Date(),
                   openTasks: [VocabTask] = [.recognize]) -> VocabItem {
        let id = VocabItem.chunkID(text)
        if var existing = item(id) {
            if let occurrence, !existing.sources.contains(where: { $0.sentenceKey == occurrence.sentenceKey }) {
                existing.sources.append(occurrence)
            }
            existing.archived = false
            if existing.gloss.isEmpty { existing.gloss = gloss }
            if (existing.note ?? "").isEmpty, let note, !note.isEmpty { existing.note = note }
            if (existing.variants ?? []).isEmpty, let variants, !variants.isEmpty { existing.variants = variants }
            if (existing.function ?? "").isEmpty, let function, !function.isEmpty { existing.function = function }
            let updated = existing
            update { s in
                if let i = s.items.firstIndex(where: { $0.id == id }) { s.items[i] = updated }
            }
            ensureCards(itemId: id, tasks: openTasks, created: created)
            return updated
        }
        var item = VocabItem(id: id, kind: .chunk, key: nil, text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                             gloss: gloss, created: created, origin: origin)
        item.note = note
        item.variants = variants
        item.function = function
        if let occurrence { item.sources = [occurrence] }
        update { $0.items.append(item) }
        ensureCards(itemId: id, tasks: openTasks, created: created)
        DiagLog.shared.log("vocab", "saved chunk \(id)")
        return item
    }

    func editItem(_ id: String, _ change: (inout VocabItem) -> Void) {
        update { s in
            if let i = s.items.firstIndex(where: { $0.id == id }) { change(&s.items[i]) }
        }
    }

    func toggleStar(_ id: String) {
        editItem(id) { $0.starred.toggle() }
    }

    /// Takes an item out of review. Its cards keep their own on/off state and their schedule;
    /// the queue simply skips paused items. Its answers stay in the log; it can come back.
    func setArchived(_ id: String, _ archived: Bool) {
        editItem(id) { $0.archived = archived }
    }

    var archivedItemIDs: Set<String> {
        Set(state.items.filter { $0.archived }.map(\.id))
    }

    /// Creates the missing cards for these tasks (a paused card is switched back on).
    func ensureCards(itemId: String, tasks: [VocabTask], created: Date = Date()) {
        update { s in
            for task in tasks {
                let id = VocabCard.makeID(itemId: itemId, task: task)
                if let i = s.cards.firstIndex(where: { $0.id == id }) {
                    s.cards[i].suspended = false
                } else {
                    s.cards.append(VocabCard(itemId: itemId, task: task, created: created))
                }
            }
        }
    }

    /// Turns one task of an item on or off. Off only pauses: the history stays.
    func setTask(_ task: VocabTask, enabled: Bool, for itemId: String) {
        if enabled {
            ensureCards(itemId: itemId, tasks: [task])
        } else {
            let id = VocabCard.makeID(itemId: itemId, task: task)
            update { s in
                if let i = s.cards.firstIndex(where: { $0.id == id }) { s.cards[i].suspended = true }
            }
        }
    }

    func isTaskEnabled(_ task: VocabTask, for itemId: String) -> Bool {
        card(VocabCard.makeID(itemId: itemId, task: task)).map { !$0.suspended } ?? false
    }

    // MARK: Queue

    func todayEvents(_ day: String = DayKey.today) -> [ReviewEvent] {
        events.filter { $0.day == day }
    }

    /// Today's queue. Pure: safe to call while a view is drawn.
    /// If today's starting load was not recorded yet, it is computed as if it were.
    func queue(now: Date = Date()) -> VocabQueue {
        let today = DayKey.of(now)
        let estimates = VocabQueueBuilder.estimates(from: events)
        var days = state.days
        if days[today] == nil {
            let first = VocabQueueBuilder.build(cards: state.cards, settings: state.settings, now: now, today: today,
                                                todayEvents: todayEvents(today), estimates: estimates,
                                                days: days, keepNewOn: state.keepNewOn, archivedItems: archivedItemIDs)
            days[today] = VocabDay(dueAtStart: first.dueCount, estSeconds: first.estDueSeconds,
                                   budgetSeconds: first.budgetSeconds, studied: false)
        }
        return VocabQueueBuilder.build(cards: state.cards, settings: state.settings, now: now, today: today,
                                       todayEvents: todayEvents(today), estimates: estimates,
                                       days: days, keepNewOn: state.keepNewOn, archivedItems: archivedItemIDs)
    }

    /// Records the load at the start of today (for the backlog rule, VOC-P04). Call outside view updates:
    /// when the app becomes active and before the first answer of the day.
    func noteDayStart(now: Date = Date()) {
        let today = DayKey.of(now)
        guard state.days[today] == nil else { return }
        let q = queue(now: now)
        let day = VocabDay(dueAtStart: q.dueCount, estSeconds: q.estDueSeconds, budgetSeconds: q.budgetSeconds,
                           studied: false)
        update { $0.days[today] = day }
    }

    /// The learner keeps new tasks today despite the backlog suggestion.
    func keepNewTasksToday(_ keep: Bool) {
        update { $0.keepNewOn = keep ? DayKey.today : nil }
    }

    // MARK: Answering

    /// Records one answer and moves the card. Returns the event (it can be taken back with `undo`).
    @discardableResult
    func answer(cardId: String, rating: FSRSRating, details: AnswerDetails, at date: Date = Date()) -> ReviewEvent? {
        guard let card = card(cardId) else { return nil }
        noteDayStart(now: date)
        let sch = scheduler
        let after = sch.review(card.fsrs, rating: rating, at: date)
        var e = ReviewEvent(kind: .review, itemId: card.itemId, at: date)
        e.cardId = card.id
        e.task = card.task
        e.rating = rating.rawValue
        e.correct = details.correct
        e.answer = details.answer
        e.expected = details.expected
        e.hint = details.hint
        e.revealedEarly = details.revealedEarly
        e.userAccepted = details.userAccepted
        e.durationMs = details.durationMs
        e.evidence = details.evidence
        e.source = details.source
        e.scheduler = FSRSScheduler.name
        e.retention = sch.desiredRetention
        e.before = card.fsrs
        e.after = after
        let active = VocabQueueBuilder.activeReviews(todayEvents(e.day))
        e.firstOfDay = !active.contains { $0.cardId == card.id }
        update { s in
            if let i = s.cards.firstIndex(where: { $0.id == cardId }) { s.cards[i].fsrs = after }
            if var day = s.days[e.day] {
                day.studied = true
                s.days[e.day] = day
            } else {
                s.days[e.day] = VocabDay(dueAtStart: 0, estSeconds: 0, budgetSeconds: s.settings.budgetMinutes * 60,
                                         studied: true)
            }
        }
        appendEvents([e])
        saveNow()
        return e
    }

    /// The most recent answer of today that can still be taken back (VOC-F03 "误点可撤销").
    var lastUndoable: ReviewEvent? {
        let active = VocabQueueBuilder.activeReviews(todayEvents())
        guard let last = active.last, let cardId = last.cardId, let current = card(cardId) else { return nil }
        // Only while nothing else has moved this card since.
        guard let after = last.after, sameSchedule(current.fsrs, after) else { return nil }
        return last
    }

    /// Takes back one answer: the card goes back to where it was; an undo line is appended.
    @discardableResult
    func undo(_ eventId: String) -> Bool {
        guard let e = events.first(where: { $0.id == eventId && $0.kind == .review }),
              let cardId = e.cardId, let before = e.before else { return false }
        guard !events.contains(where: { $0.kind == .undo && $0.undoes == eventId }) else { return false }
        var u = ReviewEvent(kind: .undo, itemId: e.itemId, at: Date())
        u.cardId = cardId
        u.task = e.task
        u.undoes = eventId
        update { s in
            if let i = s.cards.firstIndex(where: { $0.id == cardId }) { s.cards[i].fsrs = before }
        }
        appendEvents([u])
        saveNow()
        return true
    }

    /// Dates lose sub-seconds in JSON, so compare to the second.
    private func sameSchedule(_ a: FSRSCard, _ b: FSRSCard) -> Bool {
        a.state == b.state && a.step == b.step && a.reps == b.reps
            && abs(a.due.timeIntervalSince(b.due)) < 1.5
    }

    /// 听词: a record of listening only (VOC-F04). It does not count as a review.
    func recordListen(itemId: String, source: String) {
        var e = ReviewEvent(kind: .listen, itemId: itemId, at: Date())
        e.source = source
        appendEvents([e])
    }

    // MARK: Evidence

    func abilities(for itemId: String) -> [VocabAbility: AbilityStatus] {
        var out: [VocabAbility: AbilityStatus] = [:]
        let reviews = VocabQueueBuilder.activeReviews(events.filter { $0.itemId == itemId })
        for card in state.cards where card.itemId == itemId {
            var st = out[card.task.ability] ?? AbilityStatus()
            st.enabled = st.enabled || !card.suspended
            if card.fsrs.state == .review, let last = card.fsrs.lastReview,
               card.fsrs.due.timeIntervalSince(last) >= Double(VocabStore.longIntervalDays) * 86_400 {
                st.longInterval = true
            }
            if !card.suspended, !card.isNew {
                st.due = min(st.due ?? card.fsrs.due, card.fsrs.due)
            }
            out[card.task.ability] = st
        }
        for e in reviews {
            guard let task = e.task else { continue }
            var st = out[task.ability] ?? AbilityStatus()
            st.reviews += 1
            st.lastAt = max(st.lastAt ?? e.at, e.at)
            if e.firstOfDay == true && e.revealedEarly != true {
                st.independent += 1
                let remembered = (e.rating ?? 1) >= 3 || (task.isObjective && e.correct == true && (e.rating ?? 1) >= 2)
                if remembered { st.independentSuccess += 1 }
            }
            out[task.ability] = st
        }
        return out
    }

    // MARK: Migration from V0.2

    /// 生词本 → one sense item each, with a 认义 card. "认识" stays a history mark only.
    /// Runs once (vocab.json remembers it). Needs the lexicon to be loaded.
    func migrateFromV02IfNeeded(user: UserStore, packs: PackStore) {
        guard state.migratedV02 == nil, packs.lexiconReady else { return }
        var cache: [String: Article] = [:]
        let keys = user.state.star.keys.sorted { (user.state.star[$0] ?? .distantPast) < (user.state.star[$1] ?? .distantPast) }
        var added = 0
        for key in keys where !hasItem(forKey: key) {
            let entry = packs.entry(key)
            let senses = entry?.card?.senses ?? []
            var occurrence: Occurrence?
            if let ctx = entry?.card?.ctx?.first {
                occurrence = packs.occurrence(forContext: ctx.sid, key: key, cache: &cache)
            }
            let gloss = senses.first?.zh ?? entry?.zh?.components(separatedBy: "\n").first ?? ""
            saveSense(key: key, text: key, pos: entry?.card?.pos ?? senses.first?.pos, gloss: gloss,
                      senseIndex: senses.isEmpty ? nil : 0, occurrence: occurrence, origin: .legacyStar,
                      note: nil, created: user.state.star[key] ?? Date())
            added += 1
        }
        update { $0.migratedV02 = Date() }
        saveNow()
        DiagLog.shared.log("vocab", "migrated V0.2 word list: \(added) items")
    }

    // MARK: Pack updates (PKG-P03, ACC-07)

    /// After a pack update: follow trusted mappings; mark the rest "unmapped" and keep their snapshots.
    func applyDiffs(_ diffs: [ArticleDiff]) {
        guard !diffs.isEmpty else { return }
        var moved = 0
        var lost = 0
        update { s in
            for i in s.items.indices {
                for j in s.items[i].sources.indices {
                    let occ = s.items[i].sources[j]
                    guard let d = diffs.first(where: { $0.article == occ.ref }) else { continue }
                    if let newSid = d.newSid(for: occ.sid) {
                        if newSid != occ.sid {
                            s.items[i].sources[j].sid = newSid
                            s.items[i].sources[j].clip = nil     // times belong to the old sentence
                            moved += 1
                        }
                    } else if occ.unmapped != true {
                        s.items[i].sources[j].unmapped = true
                        s.items[i].sources[j].clip = nil
                        lost += 1
                    }
                }
            }
        }
        saveNow()
        DiagLog.shared.log("vocab", "pack update: \(moved) contexts moved, \(lost) marked unmapped")
    }

    // MARK: CSV import (IMP-F08)

    /// Imports checked rows. "认识" rows are kept as history only; no review card.
    func importCSV(_ rows: [CSVCandidate], createCards: Bool) -> Int {
        var n = 0
        let now = Date()
        for row in rows where row.importable {
            let text = row.word.trimmingCharacters(in: .whitespacesAndNewlines)
            let isChunk = text.contains(" ")
            let tasks: [VocabTask] = (createCards && !row.known) ? [.recognize] : []
            let item: VocabItem
            if isChunk {
                item = saveChunk(text: text, gloss: row.meaning, note: nil, occurrence: nil, origin: .csv,
                                 created: now, openTasks: tasks)
            } else {
                item = saveSense(key: SentenceText.normalize(text), text: text, pos: nil, gloss: row.meaning,
                                 senseIndex: nil, occurrence: nil, origin: .csv, created: now, openTasks: tasks)
            }
            if !row.sentence.isEmpty || row.known {
                editItem(item.id) { it in
                    if !row.sentence.isEmpty, it.note == nil { it.note = "CSV 例句：" + row.sentence }
                    if row.known { it.legacyKnown = now }
                }
            }
            n += 1
        }
        saveNow()
        DiagLog.shared.log("vocab", "CSV import: \(n) rows")
        return n
    }

    /// Normalised words and chunks already saved (for the CSV duplicate check).
    var existingTexts: Set<String> {
        Set(state.items.map { SentenceText.normalize($0.kind == .sense ? ($0.key ?? $0.text) : $0.text) })
    }

    // MARK: Backup

    func backupFiles() throws -> [(name: String, data: Data)] {
        [(name: "vocab.json", data: try DataCoding.encoder.encode(state)),
         (name: "vocab-events.jsonl", data: try JSONLines<ReviewEvent>.encode(events))]
    }

    /// Replaces the vocabulary data with a backup's. Writes to temporary files first.
    func restore(_ restored: VocabState, events restoredEvents: [ReviewEvent]) throws {
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        let tmpState = dir.appendingPathComponent("vocab-restore.json")
        let tmpEvents = dir.appendingPathComponent("vocab-events-restore.jsonl")
        try DataCoding.encoder.encode(restored).write(to: tmpState, options: .atomic)
        try JSONLines<ReviewEvent>.encode(restoredEvents).write(to: tmpEvents, options: .atomic)
        for (target, source) in [(fileURL, tmpState), (eventsURL, tmpEvents)] {
            if fm.fileExists(atPath: target.path) {
                _ = try fm.replaceItemAt(target, withItemAt: source)
            } else {
                try fm.moveItem(at: source, to: target)
            }
        }
        state = restored
        events = restoredEvents
    }
}
