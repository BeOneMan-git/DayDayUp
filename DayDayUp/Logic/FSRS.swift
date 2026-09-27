import Foundation

// FSRS-6 spaced-repetition scheduler.
// A line-by-line port of py-fsrs 6.3.2 (Scheduler.review_card, MIT licence), with one change:
// intervals are not fuzzed, so every due date can be explained from the numbers on the card.
// LogicTests compares this port with py-fsrs on fixed review sequences.

enum FSRSRating: Int, Codable, CaseIterable, Sendable {
    case again = 1, hard = 2, good = 3, easy = 4

    var title: String {
        switch self {
        case .again: return "忘记"
        case .hard: return "困难"
        case .good: return "记得"
        case .easy: return "轻松"
        }
    }
}

struct FSRSCard: Codable, Equatable, Sendable {
    enum State: Int, Codable, Sendable {
        case learning = 1, review = 2, relearning = 3
    }

    var state: State = .learning
    var step: Int? = 0
    var stability: Double? = nil
    var difficulty: Double? = nil
    var due: Date
    var lastReview: Date? = nil
    /// Not used by the algorithm; kept for display.
    var reps: Int = 0
    var lapses: Int = 0

    init(due: Date) {
        self.due = due
    }

    /// Never reviewed yet.
    var isNew: Bool { lastReview == nil }

    enum CodingKeys: String, CodingKey {
        case state, step, stability, difficulty, due, lastReview, reps, lapses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = (try? c.decodeIfPresent(State.self, forKey: .state)) ?? .learning
        step = try? c.decodeIfPresent(Int.self, forKey: .step)
        stability = try? c.decodeIfPresent(Double.self, forKey: .stability)
        difficulty = try? c.decodeIfPresent(Double.self, forKey: .difficulty)
        due = (try? c.decodeIfPresent(Date.self, forKey: .due)) ?? Date(timeIntervalSince1970: 0)
        lastReview = try? c.decodeIfPresent(Date.self, forKey: .lastReview)
        reps = (try? c.decodeIfPresent(Int.self, forKey: .reps)) ?? 0
        lapses = (try? c.decodeIfPresent(Int.self, forKey: .lapses)) ?? 0
    }
}

struct FSRSScheduler: Sendable {
    static let defaultParameters: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666,
        0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658,
        0.1542,
    ]
    /// Written into every review event, so later changes stay traceable.
    static let name = "FSRS-6 · py-fsrs 6.3.2 移植 · 无随机抖动"

    static let stabilityMin = 0.001
    static let minDifficulty = 1.0
    static let maxDifficulty = 10.0

    var parameters: [Double] = FSRSScheduler.defaultParameters
    var desiredRetention: Double = 0.9
    var learningSteps: [TimeInterval] = [60, 600]
    var relearningSteps: [TimeInterval] = [600]
    var maximumInterval: Int = 36_500

    init(desiredRetention: Double = 0.9) {
        self.desiredRetention = desiredRetention
    }

    var decay: Double { -parameters[20] }
    var factor: Double { pow(0.9, 1 / decay) - 1 }

    // MARK: Public

    /// Predicted probability of recall at `date`. 0 for a card that was never reviewed.
    func retrievability(_ card: FSRSCard, at date: Date) -> Double {
        guard let last = card.lastReview, let stability = card.stability else { return 0 }
        let elapsed = max(0, FSRSScheduler.wholeDays(from: last, to: date))
        return pow(1 + factor * Double(elapsed) / stability, decay)
    }

    /// Days until recall is expected to drop to the desired retention, for a given stability.
    func interval(forStability stability: Double) -> Int {
        nextInterval(stability: stability)
    }

    func review(_ input: FSRSCard, rating: FSRSRating, at date: Date) -> FSRSCard {
        var card = input
        let daysSinceLastReview: Int? = card.lastReview.map { FSRSScheduler.wholeDays(from: $0, to: date) }
        let g = Double(rating.rawValue)
        var next: TimeInterval = 0

        switch card.state {
        case .learning:
            let step = card.step ?? 0
            if card.stability == nil || card.difficulty == nil {
                card.stability = initialStability(rating)
                card.difficulty = initialDifficulty(rating, clamp: true)
            } else if let d = daysSinceLastReview, d < 1 {
                card.stability = shortTermStability(card.stability!, g)
                card.difficulty = nextDifficulty(card.difficulty!, g)
            } else {
                card.stability = nextStability(difficulty: card.difficulty!, stability: card.stability!,
                                               retrievability: retrievability(card, at: date), rating: rating)
                card.difficulty = nextDifficulty(card.difficulty!, g)
            }
            if learningSteps.isEmpty || (step >= learningSteps.count && rating != .again) {
                card.state = .review
                card.step = nil
                next = days(nextInterval(stability: card.stability!))
            } else {
                switch rating {
                case .again:
                    card.step = 0
                    next = learningSteps[0]
                case .hard:
                    if step == 0 && learningSteps.count == 1 {
                        next = learningSteps[0] * 1.5
                    } else if step == 0 && learningSteps.count >= 2 {
                        next = (learningSteps[0] + learningSteps[1]) / 2
                    } else {
                        next = learningSteps[step]
                    }
                    card.step = step
                case .good:
                    if step + 1 == learningSteps.count {
                        card.state = .review
                        card.step = nil
                        next = days(nextInterval(stability: card.stability!))
                    } else {
                        card.step = step + 1
                        next = learningSteps[step + 1]
                    }
                case .easy:
                    card.state = .review
                    card.step = nil
                    next = days(nextInterval(stability: card.stability!))
                }
            }

        case .review:
            let stability = card.stability ?? FSRSScheduler.stabilityMin
            let difficulty = card.difficulty ?? initialDifficulty(.good, clamp: true)
            if let d = daysSinceLastReview, d < 1 {
                card.stability = shortTermStability(stability, g)
            } else {
                card.stability = nextStability(difficulty: difficulty, stability: stability,
                                               retrievability: retrievability(card, at: date), rating: rating)
            }
            card.difficulty = nextDifficulty(difficulty, g)
            switch rating {
            case .again:
                card.lapses += 1
                if relearningSteps.isEmpty {
                    next = days(nextInterval(stability: card.stability!))
                } else {
                    card.state = .relearning
                    card.step = 0
                    next = relearningSteps[0]
                }
            case .hard, .good, .easy:
                next = days(nextInterval(stability: card.stability!))
            }

        case .relearning:
            let step = card.step ?? 0
            let stability = card.stability ?? FSRSScheduler.stabilityMin
            let difficulty = card.difficulty ?? initialDifficulty(.good, clamp: true)
            if let d = daysSinceLastReview, d < 1 {
                card.stability = shortTermStability(stability, g)
                card.difficulty = nextDifficulty(difficulty, g)
            } else {
                card.stability = nextStability(difficulty: difficulty, stability: stability,
                                               retrievability: retrievability(card, at: date), rating: rating)
                card.difficulty = nextDifficulty(difficulty, g)
            }
            if relearningSteps.isEmpty || (step >= relearningSteps.count && rating != .again) {
                card.state = .review
                card.step = nil
                next = days(nextInterval(stability: card.stability!))
            } else {
                switch rating {
                case .again:
                    card.step = 0
                    next = relearningSteps[0]
                case .hard:
                    if step == 0 && relearningSteps.count == 1 {
                        next = relearningSteps[0] * 1.5
                    } else if step == 0 && relearningSteps.count >= 2 {
                        next = (relearningSteps[0] + relearningSteps[1]) / 2
                    } else {
                        next = relearningSteps[step]
                    }
                    card.step = step
                case .good:
                    if step + 1 == relearningSteps.count {
                        card.state = .review
                        card.step = nil
                        next = days(nextInterval(stability: card.stability!))
                    } else {
                        card.step = step + 1
                        next = relearningSteps[step + 1]
                    }
                case .easy:
                    card.state = .review
                    card.step = nil
                    next = days(nextInterval(stability: card.stability!))
                }
            }
        }

        card.due = date.addingTimeInterval(next)
        card.lastReview = date
        card.reps += 1
        return card
    }

    // MARK: Formulas (py-fsrs names)

    /// Python `(b - a).days`: whole days, rounded down (also for negative spans).
    static func wholeDays(from a: Date, to b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 86_400).rounded(.down))
    }

    private func days(_ n: Int) -> TimeInterval { TimeInterval(n) * 86_400 }

    private func clampDifficulty(_ d: Double) -> Double {
        min(max(d, FSRSScheduler.minDifficulty), FSRSScheduler.maxDifficulty)
    }

    private func clampStability(_ s: Double) -> Double {
        max(s, FSRSScheduler.stabilityMin)
    }

    func initialStability(_ rating: FSRSRating) -> Double {
        clampStability(parameters[rating.rawValue - 1])
    }

    func initialDifficulty(_ rating: FSRSRating, clamp: Bool) -> Double {
        let d = parameters[4] - exp(parameters[5] * Double(rating.rawValue - 1)) + 1
        return clamp ? clampDifficulty(d) : d
    }

    /// Python round() rounds halves to even; keep that so intervals match py-fsrs exactly.
    func nextInterval(stability: Double) -> Int {
        let raw = (stability / factor) * (pow(desiredRetention, 1 / decay) - 1)
        var n = Int(raw.rounded(.toNearestOrEven))
        n = max(n, 1)
        n = min(n, maximumInterval)
        return n
    }

    private func shortTermStability(_ stability: Double, _ g: Double) -> Double {
        var increase = exp(parameters[17] * (g - 3 + parameters[18])) * pow(stability, -parameters[19])
        if g >= 2 {
            increase = max(increase, 1.0)
        }
        return clampStability(stability * increase)
    }

    private func nextDifficulty(_ difficulty: Double, _ g: Double) -> Double {
        let arg1 = initialDifficulty(.easy, clamp: false)
        let delta = -(parameters[6] * (g - 3))
        let arg2 = difficulty + (10.0 - difficulty) * delta / 9.0
        let reverted = parameters[7] * arg1 + (1 - parameters[7]) * arg2
        return clampDifficulty(reverted)
    }

    private func nextStability(difficulty: Double, stability: Double, retrievability: Double,
                               rating: FSRSRating) -> Double {
        let s: Double
        if rating == .again {
            s = nextForgetStability(difficulty: difficulty, stability: stability, retrievability: retrievability)
        } else {
            s = nextRecallStability(difficulty: difficulty, stability: stability,
                                    retrievability: retrievability, rating: rating)
        }
        return clampStability(s)
    }

    private func nextForgetStability(difficulty: Double, stability: Double, retrievability: Double) -> Double {
        let a = parameters[11] * pow(difficulty, -parameters[12])
        let b = pow(stability + 1, parameters[13]) - 1
        let c = exp((1 - retrievability) * parameters[14])
        let longTerm = a * b * c
        let shortTerm = stability / exp(parameters[17] * parameters[18])
        return min(longTerm, shortTerm)
    }

    private func nextRecallStability(difficulty: Double, stability: Double, retrievability: Double,
                                     rating: FSRSRating) -> Double {
        let hardPenalty = rating == .hard ? parameters[15] : 1
        let easyBonus = rating == .easy ? parameters[16] : 1
        let growth = exp(parameters[8]) * (11 - difficulty) * pow(stability, -parameters[9]) *
            (exp((1 - retrievability) * parameters[10]) - 1) * hardPenalty * easyBonus
        return stability * (1 + growth)
    }
}
