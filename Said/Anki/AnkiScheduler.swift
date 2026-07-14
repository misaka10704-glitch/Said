import Foundation

/// Anki SM-2 scheduler (v2 semantics), aligned with classic Anki / AnkiDroid.
/// Source behaviour: ankitects/anki open-source scheduling (AGPL).
enum AnkiScheduler {
    struct Config {
        var learningStepsMin: [Double] // minutes
        var graduatingIvl: Int
        var easyIvl: Int
        var startingEase: Int // permille, 2500 = 250%
        var easyBonus: Double
        var intervalModifier: Double
        var maxInterval: Int
        var hardFactor: Double
    }

    static func answer(
        card: AnkiCollection.RawCard,
        ease: AnkiEase,
        conf: Config,
        today: Int,
        nowSec: Int
    ) -> AnkiCollection.RawCard {
        var c = card
        c.reps += 1

        switch AnkiCardType(rawValue: c.type) ?? .new {
        case .new, .learning, .relearning:
            return answerLearning(card: &c, ease: ease, conf: conf, today: today, nowSec: nowSec)
        case .review:
            return answerReview(card: &c, ease: ease, conf: conf, today: today)
        }
    }

    private static func answerLearning(
        card: inout AnkiCollection.RawCard,
        ease: AnkiEase,
        conf: Config,
        today: Int,
        nowSec: Int
    ) -> AnkiCollection.RawCard {
        let steps = conf.learningStepsMin.isEmpty ? [1.0, 10.0] : conf.learningStepsMin

        if card.type == AnkiCardType.new.rawValue {
            card.type = AnkiCardType.learning.rawValue
            card.left = steps.count * 1000 + steps.count // Anki packs remaining steps
        }

        switch ease {
        case .again:
            card.lapses += card.type == AnkiCardType.review.rawValue ? 1 : 0
            card.left = steps.count * 1000 + steps.count
            card.queue = AnkiCardQueue.learning.rawValue
            let delay = Int(max(1, steps[0] * 60))
            card.due = nowSec + delay
            card.ivl = 0
            return card

        case .hard:
            // stay on same step; delay = midpoint or 1.5x current
            let remaining = card.left % 1000
            let idx = max(0, steps.count - remaining)
            let cur = steps[min(idx, steps.count - 1)]
            let delayMin = max(steps[0], cur * 1.5)
            card.queue = AnkiCardQueue.learning.rawValue
            card.due = nowSec + Int(delayMin * 60)
            return card

        case .good:
            var remaining = card.left % 1000
            remaining -= 1
            if remaining <= 0 {
                // graduate
                card.type = AnkiCardType.review.rawValue
                card.queue = AnkiCardQueue.review.rawValue
                card.ivl = conf.graduatingIvl
                card.due = today + card.ivl
                card.factor = conf.startingEase
                card.left = 0
            } else {
                let idx = steps.count - remaining
                let delayMin = steps[min(max(idx, 0), steps.count - 1)]
                card.left = (card.left / 1000) * 1000 + remaining
                card.queue = AnkiCardQueue.learning.rawValue
                card.due = nowSec + Int(delayMin * 60)
            }
            return card

        case .easy:
            card.type = AnkiCardType.review.rawValue
            card.queue = AnkiCardQueue.review.rawValue
            card.ivl = conf.easyIvl
            card.due = today + card.ivl
            card.factor = conf.startingEase
            card.left = 0
            return card
        }
    }

    private static func answerReview(
        card: inout AnkiCollection.RawCard,
        ease: AnkiEase,
        conf: Config,
        today: Int
    ) -> AnkiCollection.RawCard {
        let oldIvl = max(1, card.ivl)
        let factor = Double(max(1300, card.factor)) / 1000.0

        switch ease {
        case .again:
            card.lapses += 1
            card.type = AnkiCardType.relearning.rawValue
            card.queue = AnkiCardQueue.learning.rawValue
            let steps = conf.learningStepsMin.isEmpty ? [10.0] : conf.learningStepsMin
            card.left = steps.count * 1000 + steps.count
            card.due = Int(Date().timeIntervalSince1970) + Int(steps[0] * 60)
            card.ivl = 1
            card.factor = max(1300, card.factor - 200)
            return card

        case .hard:
            let hardIvl = max(1, Int(Double(oldIvl) * conf.hardFactor * conf.intervalModifier))
            card.ivl = min(conf.maxInterval, hardIvl)
            card.factor = max(1300, card.factor - 150)
            card.due = today + card.ivl
            card.queue = AnkiCardQueue.review.rawValue
            return card

        case .good:
            let goodIvl = max(oldIvl + 1, Int(Double(oldIvl) * factor * conf.intervalModifier))
            card.ivl = min(conf.maxInterval, goodIvl)
            card.due = today + card.ivl
            card.queue = AnkiCardQueue.review.rawValue
            return card

        case .easy:
            let easyIvl = max(oldIvl + 1, Int(Double(oldIvl) * factor * conf.easyBonus * conf.intervalModifier))
            card.ivl = min(conf.maxInterval, easyIvl)
            card.factor = card.factor + 150
            card.due = today + card.ivl
            card.queue = AnkiCardQueue.review.rawValue
            return card
        }
    }
}
