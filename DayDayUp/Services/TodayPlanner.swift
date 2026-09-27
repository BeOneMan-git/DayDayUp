import Foundation

/// Gathers today's facts from the stores and asks PlanEngine for a plan (PAGE-01).
/// The first plan of a day is stored (DATA-11); later calls return the stored one.
@MainActor
enum TodayPlanner {
    static func inputs(packs: PackStore, user: UserStore, practice: PracticeStore, vocab: VocabStore,
                       study: StudyStore, now: Date = Date()) -> PlanInputs {
        let day = DayKey.of(now)
        let q = vocab.queue(now: now)
        let items = packs.allItems
        // Answering an article's questions (基线短听读, a practice quiz) is contact with it too, even though the
        // reader never opened it: it is no longer new material for the weekly check.
        var quizzedAt: [String: Date] = [:]
        for r in study.state.quizResults {
            if let seen = quizzedAt[r.article], seen <= r.at { continue }
            quizzedAt[r.article] = r.at
        }
        var candidates: [ReadingCandidate] = []
        for item in items {
            let key = item.ref.key
            let listened = user.state.listenProgress(key, duration: item.meta.dur)
            candidates.append(ReadingCandidate(
                ref: item.ref, title: item.meta.title, minutes: item.meta.dur / 60, listened: listened,
                lastOpened: study.state.articleOpened[key] ?? quizzedAt[key], difficulty: study.difficulty(item.ref),
                firstUnpractisedSid: nil, hasQuiz: packs.resources(item.ref).quiz == .available,
                readDay: study.state.articleFinished[key].map(DayKey.of), checked: study.hasIndependentCheck(key)))
        }
        // Only the likely picks need the (slower) look into the article for an unpractised sentence.
        if let pick = PlanEngine.pickReading(candidates), let i = candidates.firstIndex(where: { $0.ref == pick.ref }) {
            candidates[i].firstUnpractisedSid = firstUnpractised(pick.ref, packs: packs, practice: practice)
        }
        return PlanInputs(
            day: day, now: now, settings: study.settings,
            vocabBudgetMinutes: vocab.settings.budgetMinutes, vocabDue: q.dueCount, vocabEstSeconds: q.estDueSeconds,
            vocabNewAllowed: q.newAllowed, vocabBacklog: q.backlogSuggestsZero && !q.backlogOverridden,
            vocabItems: vocab.activeItems.count, baseline: study.state.baseline, reading: candidates,
            dueRetests: study.dueRetests(on: day),
            nextSpeaking: nextSpeaking(stage: study.settings.stage, practice: practice),
            nextWriting: nextWriting(stage: study.settings.stage, practice: practice),
            outputDoneRecently: [], deferred: study.deferred(to: day), lastWeeklyCheck: study.lastWeeklyCheck)
    }

    /// Today's stored plan, made now if there is none yet.
    @discardableResult
    static func today(packs: PackStore, user: UserStore, practice: PracticeStore, vocab: VocabStore,
                      study: StudyStore) -> PlanSnapshot {
        study.ensurePlan {
            PlanEngine.build(inputs(packs: packs, user: user, practice: practice, vocab: vocab, study: study))
        }
    }

    /// Makes today's plan again (after the learner changed the budget or the stage).
    /// What the day already holds is kept (ACC-30): see `keepProgress`.
    @discardableResult
    static func rebuild(packs: PackStore, user: UserStore, practice: PracticeStore, vocab: VocabStore,
                        study: StudyStore) -> PlanSnapshot {
        let day = DayKey.today
        let fresh = PlanEngine.build(inputs(packs: packs, user: user, practice: practice, vocab: vocab, study: study))
        let merged = keepProgress(old: study.plan(for: day), fresh: fresh)
        study.resetPlan(day: day)
        return study.ensurePlan { merged }
    }

    /// Done and deferred tasks survive a rebuild. When the new plan has a task with the same id and the same
    /// target, that task takes over the state, time and deferral; when the id is the same but the target is not,
    /// the old task stays in its place (that slot was already dealt with today); a task the new plan does not
    /// have is appended unchanged, so the day's record keeps it.
    static func keepProgress(old: PlanSnapshot?, fresh: PlanSnapshot) -> PlanSnapshot {
        guard let old else { return fresh }
        var out = fresh
        for t in old.tasks where t.state != .todo {
            if let i = out.tasks.firstIndex(where: { $0.id == t.id }) {
                if out.tasks[i].target == t.target {
                    out.tasks[i].state = t.state
                    out.tasks[i].doneAt = t.doneAt
                    out.tasks[i].deferredTo = t.deferredTo
                } else {
                    out.tasks[i] = t
                }
            } else {
                out.tasks.append(t)
            }
        }
        out.tasks = PlanEngine.order(out.tasks)
        return out
    }

    /// 换一篇: a plan made without the current article (and without `alsoSkip`), from which the "-read" task
    /// and the "-shadow" task for the new article are taken. Each new reason starts with "你换了一篇。".
    /// nil when there is no other material.
    static func swapReading(current: ArticleRef, alsoSkip: [ArticleRef] = [], packs: PackStore, user: UserStore,
                            practice: PracticeStore, vocab: VocabStore,
                            study: StudyStore) -> (read: PlanTask, shadow: PlanTask?)? {
        var i = inputs(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
        let skip = Set(alsoSkip + [current])
        i.reading.removeAll { skip.contains($0.ref) }
        i.deferred = []
        // The first unpractised sentence was looked up for the old pick only; look it up for the new one.
        if let pick = PlanEngine.pickReading(i.reading), let n = i.reading.firstIndex(where: { $0.ref == pick.ref }) {
            i.reading[n].firstUnpractisedSid = firstUnpractised(pick.ref, packs: packs, practice: practice)
        }
        let p = PlanEngine.build(i)
        guard var read = p.tasks.first(where: { $0.id.hasSuffix("-read") }) else { return nil }
        read.reason = "你换了一篇。" + read.reason
        var shadow = p.tasks.first { $0.id.hasSuffix("-shadow") }
        if var s = shadow {
            s.reason = "你换了一篇。" + s.reason
            shadow = s
        }
        return (read, shadow)
    }

    /// Applies 换一篇 to the plan of `day`: the reading task gets the new article (same id); the 跟读 task
    /// follows only while it is still open and points at the old article. False when nothing else is left.
    @discardableResult
    static func applySwap(readTaskId: String, day: String, current: ArticleRef, alsoSkip: [ArticleRef] = [],
                          packs: PackStore, user: UserStore, practice: PracticeStore, vocab: VocabStore,
                          study: StudyStore) -> Bool {
        guard let picked = swapReading(current: current, alsoSkip: alsoSkip, packs: packs, user: user,
                                       practice: practice, vocab: vocab, study: study) else { return false }
        var read = picked.read
        read.id = readTaskId
        study.replaceTask(day: day, read)
        guard var shadow = picked.shadow, let plan = study.plan(for: day),
              let old = plan.tasks.first(where: { $0.id.hasSuffix("-shadow") }), old.state == .todo,
              case .shadow(let issue, let id, _) = old.target, ArticleRef(issue: issue, id: id) == current else {
            return true
        }
        shadow.id = old.id
        study.replaceTask(day: day, shadow)
        return true
    }

    // MARK: Automatic completion (ACC-30)

    /// The time the records show this task was done on `day`; nil when they do not (yet).
    /// - 词汇: at least one review today and nothing due any more.
    /// - 听读: the article reached 听读完成 (90 % coverage) today.
    /// - 跟读: at least 3 takes with voice on that article today.
    /// - 口语: a take with voice for that prompt today. 写作: a work for that prompt whose first version was
    ///   finished today.
    /// - 复测: the retest is completed. 基线: finished, or one of its four parts was done today.
    /// - 回忆 / 每周复测: a quiz result today for that article with the same purpose.
    static func evidenceTime(for task: PlanTask, day: String, packs: PackStore, user: UserStore,
                             practice: PracticeStore, vocab: VocabStore, study: StudyStore) -> Date? {
        switch task.target {
        case .vocabReview:
            let reviews = VocabQueueBuilder.activeReviews(vocab.todayEvents(day))
            guard let last = reviews.map(\.at).max(), vocab.queue().dueCount == 0 else { return nil }
            return last
        case .article(let issue, let id):
            guard let at = study.state.articleFinished[ArticleRef(issue: issue, id: id).key],
                  DayKey.of(at) == day else { return nil }
            return at
        case .shadow(let issue, let id, _):
            let key = ArticleRef(issue: issue, id: id).key
            let takes = practice.state.shadow
                .filter { $0.article == key && !$0.silent && $0.dayKey == day }
                .map(\.created)
                .sorted()
            return takes.count >= 3 ? takes[2] : nil
        case .speaking(let promptId):
            return practice.state.speaking
                .filter { $0.promptId == promptId && !$0.silent && $0.dayKey == day }
                .map(\.created)
                .min()
        case .writing(let promptId):
            return practice.state.writing
                .filter { $0.promptId == promptId }
                .compactMap { $0.versions.first?.finished }
                .filter { DayKey.of($0) == day }
                .min()
        case .retest(let id):
            return study.retest(id)?.done
        case .baseline:
            let b = study.state.baseline
            if b.isDone { return b.finished ?? Date() }
            let parts: [BaselineResult?] = [b.listening, b.speaking, b.writing, b.vocab]
            return parts.compactMap { $0?.done }.filter { DayKey.of($0) == day }.max()
        case .articleCheck(let issue, let id, let purpose):
            let key = ArticleRef(issue: issue, id: id).key
            return study.state.quizResults
                .filter { $0.article == key && $0.purpose == purpose && $0.day == day }
                .map { $0.at.addingTimeInterval($0.seconds) }
                .min()
        }
    }

    static func evidence(for task: PlanTask, day: String, packs: PackStore, user: UserStore, practice: PracticeStore,
                         vocab: VocabStore, study: StudyStore) -> Bool {
        evidenceTime(for: task, day: day, packs: packs, user: user, practice: practice, vocab: vocab,
                     study: study) != nil
    }

    /// Marks today's open tasks done when the records show them done. `markDone` ignores a task that is
    /// already done, so running this again never counts twice. `skipping`: tasks the learner reopened.
    @discardableResult
    static func applyEvidence(skipping: Set<String> = [], packs: PackStore, user: UserStore, practice: PracticeStore,
                              vocab: VocabStore, study: StudyStore) -> Int {
        let day = DayKey.today
        guard let plan = study.plan(for: day) else { return 0 }
        var marked = 0
        for task in plan.tasks where task.state == .todo && !skipping.contains(task.id) {
            guard let at = evidenceTime(for: task, day: day, packs: packs, user: user, practice: practice,
                                        vocab: vocab, study: study) else { continue }
            study.markDone(day: day, taskId: task.id, at: min(at, Date()))
            marked += 1
        }
        return marked
    }

    static func firstUnpractised(_ ref: ArticleRef, packs: PackStore, practice: PracticeStore) -> Int? {
        guard let art = packs.cachedArticle(ref) else { return nil }
        let done = Set(practice.state.shadow.filter { $0.article == ref.key }.map(\.sid))
        return art.paras.flatMap(\.sents).first { $0.isTimed && $0.unread != true && !done.contains($0.id) }?.id
    }

    /// The next speaking prompt the learner has not answered, matching the stage.
    static func nextSpeaking(stage: StudyStage, practice: PracticeStore) -> (id: String, text: String)? {
        let done = Set(practice.state.speaking.map(\.promptId))
        if stage == .exam, let c = IELTSExamBank.cueCards.first(where: { !done.contains($0.id) }) {
            return (c.id, c.title)
        }
        if let p = IELTSBank.speaking.first(where: { !done.contains($0.id) }) { return (p.id, p.question) }
        return IELTSBank.speaking.first.map { ($0.id, $0.question) }
    }

    static func nextWriting(stage: StudyStage, practice: PracticeStore) -> (id: String, text: String)? {
        let done = Set(practice.state.writing.map(\.promptId))
        if stage == .exam, let t = IELTSExamBank.task2Prompts.first(where: { !done.contains($0.id) }) {
            return (t.id, t.zh)
        }
        if let p = IELTSBank.writing.first(where: { !done.contains($0.id) }) { return (p.id, p.task) }
        return IELTSBank.writing.first.map { ($0.id, $0.task) }
    }

    /// A new prompt of the same kind as an earlier work, never the same one (IEL-F04).
    static func retestPrompt(for r: Retest, practice: PracticeStore) -> String? {
        let used = Set((r.kind == "speaking" ? practice.state.speaking.map(\.promptId) : practice.state.writing.map(\.promptId)))
        if r.kind == "speaking" {
            let source = practice.speaking(r.sourceId)
            let exam = source?.part == "p2"
            if exam { return IELTSExamBank.cueCards.first { !used.contains($0.id) }?.id }
            let topic = IELTSBank.speaking.first { $0.id == source?.promptId }?.topic
            return IELTSBank.speaking.first { !used.contains($0.id) && $0.topic != topic }?.id
                ?? IELTSBank.speaking.first { !used.contains($0.id) }?.id
        } else {
            let source = practice.writing(r.sourceId)
            switch source?.kind {
            case "task2": return IELTSExamBank.task2Prompts.first { !used.contains($0.id) }?.id
            case "task1": return IELTSExamBank.task1Prompts.first { !used.contains($0.id) }?.id
            default:
                let topic = IELTSBank.writing.first { $0.id == source?.promptId }?.topic
                return IELTSBank.writing.first { !used.contains($0.id) && $0.topic != topic }?.id
                    ?? IELTSBank.writing.first { !used.contains($0.id) }?.id
            }
        }
    }
}
