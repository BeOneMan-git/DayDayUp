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
        var candidates: [ReadingCandidate] = []
        for item in items {
            let key = item.ref.key
            let listened = user.state.listenProgress(key, duration: item.meta.dur)
            candidates.append(ReadingCandidate(
                ref: item.ref, title: item.meta.title, minutes: item.meta.dur / 60, listened: listened,
                lastOpened: study.state.articleOpened[key], difficulty: study.difficulty(item.ref),
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
    @discardableResult
    static func rebuild(packs: PackStore, user: UserStore, practice: PracticeStore, vocab: VocabStore,
                        study: StudyStore) -> PlanSnapshot {
        study.resetPlan(day: DayKey.today)
        return today(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
    }

    /// 换一篇: the next reading candidate that is not the current one.
    static func swapReading(current: ArticleRef, packs: PackStore, user: UserStore, practice: PracticeStore,
                            vocab: VocabStore, study: StudyStore) -> PlanTask? {
        var i = inputs(packs: packs, user: user, practice: practice, vocab: vocab, study: study)
        i.reading.removeAll { $0.ref == current }
        i.deferred = []
        let p = PlanEngine.build(i)
        return p.tasks.first { $0.cat == .read && $0.id.hasSuffix("-read") }
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
