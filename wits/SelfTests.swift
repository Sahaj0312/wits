//
//  SelfTests.swift
//  wits
//
//  Self-report tests: validated public screeners and questionnaires (ASRS,
//  AQ-10, WHO-5, rMEQ, Mini-IPIP, …) presented as a data-driven catalog with
//  per-test scoring. Screeners always carry "signal, not a diagnosis" framing.
//  Attempts persist to Supabase (self_test_results); the profile page shows
//  the latest result per test.
//

import SwiftUI

// MARK: - Model

struct SelfTestOption: Equatable {
    let label: String
    let value: Int
}

struct SelfTestQuestion: Equatable {
    let text: String
    /// Scenario framing shown above the question (e.g. VVIQ imagery scenes).
    var context: String? = nil
    /// Per-question scale override; defaults to the test's shared scale.
    var options: [SelfTestOption]? = nil
}

struct SelfTestOutcome: Equatable {
    let score: Double
    let maxScore: Double
    let label: String
    let summary: String
    var subscales: [String: Double]? = nil
}

/// Latest stored attempt for one test (mirrors a self_test_results row).
struct SelfTestRecord: Codable, Equatable {
    var score: Double
    var maxScore: Double
    var label: String
    var takenAt: Date
}

struct SelfTest: Identifiable {
    let id: String
    let name: String
    let tagline: String
    let icon: String
    let tint: Color
    /// Instrument name + origin, shown on the intro and result screens.
    let source: String
    /// Clinical screeners get the "screening signal, not a diagnosis" frame.
    let isScreener: Bool
    let intro: String
    let scale: [SelfTestOption]
    let questions: [SelfTestQuestion]
    let score: ([Int]) -> SelfTestOutcome

    func options(for question: SelfTestQuestion) -> [SelfTestOption] {
        question.options ?? scale
    }
}

// MARK: - Catalog

enum SelfTestCatalog {

    static let screenerDisclaimer =
        "this is a screening signal, not a diagnosis. only a qualified professional can assess you — if the result resonates, consider talking to one."

    static let all: [SelfTest] = [
        asrs6, gad7, phq8, aq10,
        who5, stress10, burnout10, overthink10, impostor10, procrast9, rosenberg,
        miniIPIP, beis10, dirtyDozen, ncs6, vviq16, rmeq,
    ]

    static func test(withID id: String) -> SelfTest? {
        all.first { $0.id == id }
    }

    // MARK: Shared scales

    private static let frequency5: [SelfTestOption] = [
        .init(label: "never", value: 0),
        .init(label: "rarely", value: 1),
        .init(label: "sometimes", value: 2),
        .init(label: "often", value: 3),
        .init(label: "very often", value: 4),
    ]

    private static let bothered4: [SelfTestOption] = [
        .init(label: "not at all", value: 0),
        .init(label: "several days", value: 1),
        .init(label: "more than half the days", value: 2),
        .init(label: "nearly every day", value: 3),
    ]

    private static let agreement4: [SelfTestOption] = [
        .init(label: "definitely agree", value: 0),
        .init(label: "slightly agree", value: 1),
        .init(label: "slightly disagree", value: 2),
        .init(label: "definitely disagree", value: 3),
    ]

    private static let accuracy5: [SelfTestOption] = [
        .init(label: "very inaccurate", value: 1),
        .init(label: "moderately inaccurate", value: 2),
        .init(label: "neither", value: 3),
        .init(label: "moderately accurate", value: 4),
        .init(label: "very accurate", value: 5),
    ]

    private static let agreement5: [SelfTestOption] = [
        .init(label: "strongly disagree", value: 1),
        .init(label: "disagree", value: 2),
        .init(label: "neutral", value: 3),
        .init(label: "agree", value: 4),
        .init(label: "strongly agree", value: 5),
    ]

    private static let vividness5: [SelfTestOption] = [
        .init(label: "no image at all — i just \"know\" i'm thinking of it", value: 1),
        .init(label: "dim and vague", value: 2),
        .init(label: "moderately clear", value: 3),
        .init(label: "clear and lively", value: 4),
        .init(label: "perfectly clear, like really seeing it", value: 5),
    ]

    // MARK: ASRS v1.1 (6-item screener, part A)

    static let asrs6 = SelfTest(
        id: "asrs6",
        name: "adhd screener",
        tagline: "the 6-question WHO instrument clinicians use",
        icon: "bolt.fill",
        tint: .witsWarm,
        source: "ASRS v1.1 part A — WHO adult ADHD self-report scale",
        isScreener: true,
        intro: "six questions about the last 6 months. answer honestly — there are no good or bad answers.",
        scale: frequency5,
        questions: [
            .init(text: "how often do you have trouble wrapping up the final details of a project, once the challenging parts have been done?"),
            .init(text: "how often do you have difficulty getting things in order when you have to do a task that requires organization?"),
            .init(text: "how often do you have problems remembering appointments or obligations?"),
            .init(text: "when you have a task that requires a lot of thought, how often do you avoid or delay getting started?"),
            .init(text: "how often do you fidget or squirm with your hands or feet when you have to sit down for a long time?"),
            .init(text: "how often do you feel overly active and compelled to do things, like you were driven by a motor?"),
        ],
        score: scoreASRS
    )

    static func scoreASRS(_ values: [Int]) -> SelfTestOutcome {
        // Part A keying: items 1–3 count from "sometimes", items 4–6 from "often".
        let thresholds = [2, 2, 2, 3, 3, 3]
        let markers = zip(values, thresholds).filter { $0 >= $1 }.count
        let met = markers >= 4
        return SelfTestOutcome(
            score: Double(markers),
            maxScore: 6,
            label: met ? "signals present (\(markers)/6)" : "below threshold (\(markers)/6)",
            summary: met
                ? "your answers match the pattern the screener is designed to flag (4 or more markers). that's a reason to talk to a professional, not a diagnosis."
                : "your answers land below the screener's flag line (fewer than 4 markers). attention struggles can still be real and worth exploring."
        )
    }

    // MARK: AQ-10 (autism-spectrum traits)

    static let aq10 = SelfTest(
        id: "aq10",
        name: "autism traits",
        tagline: "the 10-item screener the NHS uses for referrals",
        icon: "puzzlepiece.fill",
        tint: .witsViolet,
        source: "AQ-10 — autism spectrum quotient, Baron-Cohen et al.",
        isScreener: true,
        intro: "ten quick statements. pick the answer closest to how you actually are, not how you'd like to be.",
        scale: agreement4,
        questions: [
            .init(text: "i often notice small sounds when others do not."),
            .init(text: "i usually concentrate more on the whole picture, rather than the small details."),
            .init(text: "i find it easy to do more than one thing at once."),
            .init(text: "if there is an interruption, i can switch back to what i was doing very quickly."),
            .init(text: "i find it easy to \"read between the lines\" when someone is talking to me."),
            .init(text: "i know how to tell if someone listening to me is getting bored."),
            .init(text: "when i'm reading a story i find it difficult to work out the characters' intentions."),
            .init(text: "i like to collect information about categories of things (types of car, bird, train, plant…)."),
            .init(text: "i find it easy to work out what someone is thinking or feeling just by looking at their face."),
            .init(text: "i find it difficult to work out people's intentions."),
        ],
        score: scoreAQ10
    )

    static func scoreAQ10(_ values: [Int]) -> SelfTestOutcome {
        // Agree-keyed items score on (definitely/slightly) agree; the rest on disagree.
        let agreeKeyed: Set<Int> = [0, 6, 7, 9]
        var points = 0
        for (index, value) in values.enumerated() {
            if agreeKeyed.contains(index) ? value <= 1 : value >= 2 { points += 1 }
        }
        let met = points >= 6
        return SelfTestOutcome(
            score: Double(points),
            maxScore: 10,
            label: met ? "elevated traits (\(points)/10)" : "below threshold (\(points)/10)",
            summary: met
                ? "a score of 6 or more is the line where the NHS recommends considering a specialist assessment. it measures traits, not identity."
                : "your score sits below the referral line of 6. autistic traits exist on a spectrum across everyone."
        )
    }

    // MARK: VVIQ (imagery vividness / aphantasia)

    static let vviq16 = SelfTest(
        id: "vviq16",
        name: "mind's eye",
        tagline: "can you actually picture an apple? (aphantasia test)",
        icon: "eye.fill",
        tint: .witsSky,
        source: "VVIQ — vividness of visual imagery questionnaire, Marks",
        isScreener: false,
        intro: "close your eyes for each scene and rate how vividly you can picture it. some people see photographs; some see nothing at all — both are normal brains.",
        scale: vividness5,
        questions: [
            .init(text: "the exact contour of their face, head, shoulders and body.",
                  context: "picture a relative or friend you see often"),
            .init(text: "characteristic poses of their head, attitudes of their body.",
                  context: "picture a relative or friend you see often"),
            .init(text: "their precise carriage and length of step as they walk.",
                  context: "picture a relative or friend you see often"),
            .init(text: "the different colours worn in some familiar clothes of theirs.",
                  context: "picture a relative or friend you see often"),
            .init(text: "the sun rising above the horizon into a hazy sky.",
                  context: "picture a sunrise"),
            .init(text: "the sky clears and surrounds the sun with blueness.",
                  context: "picture a sunrise"),
            .init(text: "clouds roll in and a storm blows up, with flashes of lightning.",
                  context: "picture a sunrise"),
            .init(text: "a rainbow appears.",
                  context: "picture a sunrise"),
            .init(text: "the overall appearance of the shop from the opposite side of the road.",
                  context: "picture the front of a shop you often go to"),
            .init(text: "a window display, including colours, shapes and details of individual items.",
                  context: "picture the front of a shop you often go to"),
            .init(text: "you are near the entrance. the colour, shape and details of the door.",
                  context: "picture the front of a shop you often go to"),
            .init(text: "you enter and go to the counter. the assistant serves you, money changes hands.",
                  context: "picture the front of a shop you often go to"),
            .init(text: "the contours of the landscape.",
                  context: "picture a country scene with trees, mountains and a lake"),
            .init(text: "the colour and shape of the trees.",
                  context: "picture a country scene with trees, mountains and a lake"),
            .init(text: "the colour and shape of the lake.",
                  context: "picture a country scene with trees, mountains and a lake"),
            .init(text: "a strong wind blows on the trees and the lake, making waves.",
                  context: "picture a country scene with trees, mountains and a lake"),
        ],
        score: scoreVVIQ
    )

    static func scoreVVIQ(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)
        let label: String
        let summary: String
        switch total {
        case ...23:
            label = "aphantasia range (\(total)/80)"
            summary = "you likely have little or no voluntary visual imagery — a difference, not a deficit, shared by a few percent of people."
        case 24...32:
            label = "dim imagery (\(total)/80)"
            summary = "your mind's eye works, but faintly. many people in this range think in concepts and words more than pictures."
        case 33...59:
            label = "typical imagery (\(total)/80)"
            summary = "a solidly typical mind's eye — images form, though not photo-realistic ones."
        case 60...74:
            label = "vivid imagery (\(total)/80)"
            summary = "your visual imagination runs richer than most people's."
        default:
            label = "hyperphantasia range (\(total)/80)"
            summary = "near photo-realistic imagery — the top few percent of visual imagination."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 80, label: label, summary: summary)
    }

    // MARK: rMEQ (chronotype)

    static let rmeq = SelfTest(
        id: "rmeq",
        name: "chronotype",
        tagline: "lark, night owl, or something in between",
        icon: "moon.stars.fill",
        tint: .witsGold,
        source: "rMEQ — reduced morningness-eveningness questionnaire, Adan & Almirall",
        isScreener: false,
        intro: "five questions about when your body actually wants to be awake — answer for your natural rhythm, not your alarm clock.",
        scale: [],
        questions: [
            .init(text: "what time would you get up if you were entirely free to plan your day?",
                  options: [
                    .init(label: "5:00–6:30 am", value: 5),
                    .init(label: "6:30–7:45 am", value: 4),
                    .init(label: "7:45–9:45 am", value: 3),
                    .init(label: "9:45–11:00 am", value: 2),
                    .init(label: "11:00 am or later", value: 1),
                  ]),
            .init(text: "during the first half hour after you wake up, how tired do you feel?",
                  options: [
                    .init(label: "very tired", value: 1),
                    .init(label: "fairly tired", value: 2),
                    .init(label: "fairly refreshed", value: 3),
                    .init(label: "very refreshed", value: 4),
                  ]),
            .init(text: "at what time in the evening do you feel tired and in need of sleep?",
                  options: [
                    .init(label: "8:00–9:00 pm", value: 5),
                    .init(label: "9:00–10:15 pm", value: 4),
                    .init(label: "10:15 pm–12:45 am", value: 3),
                    .init(label: "12:45–2:00 am", value: 2),
                    .init(label: "2:00 am or later", value: 1),
                  ]),
            .init(text: "at what time of day do you feel your best?",
                  options: [
                    .init(label: "5–8 am", value: 5),
                    .init(label: "8–10 am", value: 4),
                    .init(label: "10 am–5 pm", value: 3),
                    .init(label: "5–10 pm", value: 2),
                    .init(label: "10 pm–5 am", value: 1),
                  ]),
            .init(text: "do you consider yourself a morning type or an evening type?",
                  options: [
                    .init(label: "definitely a morning type", value: 6),
                    .init(label: "more morning than evening", value: 4),
                    .init(label: "more evening than morning", value: 2),
                    .init(label: "definitely an evening type", value: 0),
                  ]),
        ],
        score: scoreRMEQ
    )

    static func scoreRMEQ(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)   // 4...25
        let label: String
        let summary: String
        switch total {
        case ...7:
            label = "definite night owl (\(total)/25)"
            summary = "your rhythm runs late — evenings are your prime time. schedule the hard thinking after dark."
        case 8...11:
            label = "night owl (\(total)/25)"
            summary = "you lean evening. mornings are survivable, but your brain warms up late."
        case 12...17:
            label = "hummingbird (\(total)/25)"
            summary = "an intermediate chronotype — flexible in both directions, sharpest mid-day."
        case 18...21:
            label = "lark (\(total)/25)"
            summary = "you lean morning. do the deep work early; evenings fade fast."
        default:
            label = "definite lark (\(total)/25)"
            summary = "a strong morning type — dawn is your superpower, late nights are not."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 25, label: label, summary: summary)
    }

    // MARK: Mini-IPIP (Big Five)

    static let miniIPIP = SelfTest(
        id: "mini_ipip",
        name: "personality (big five)",
        tagline: "the 20-item science-grade personality test",
        icon: "person.crop.circle.badge.questionmark.fill",
        tint: .witsAccent,
        source: "Mini-IPIP — Donnellan et al., public-domain IPIP items",
        isScreener: false,
        intro: "twenty statements. rate how accurately each one describes you as you generally are now, not as you wish to be.",
        scale: accuracy5,
        questions: [
            .init(text: "i am the life of the party."),
            .init(text: "i sympathize with others' feelings."),
            .init(text: "i get chores done right away."),
            .init(text: "i have frequent mood swings."),
            .init(text: "i have a vivid imagination."),
            .init(text: "i don't talk a lot."),
            .init(text: "i am not interested in other people's problems."),
            .init(text: "i often forget to put things back in their proper place."),
            .init(text: "i am relaxed most of the time."),
            .init(text: "i am not interested in abstract ideas."),
            .init(text: "i talk to a lot of different people at parties."),
            .init(text: "i feel others' emotions."),
            .init(text: "i like order."),
            .init(text: "i get upset easily."),
            .init(text: "i have difficulty understanding abstract ideas."),
            .init(text: "i keep in the background."),
            .init(text: "i am not really interested in others."),
            .init(text: "i make a mess of things."),
            .init(text: "i seldom feel blue."),
            .init(text: "i do not have a good imagination."),
        ],
        score: scoreMiniIPIP
    )

    static func scoreMiniIPIP(_ values: [Int]) -> SelfTestOutcome {
        let reversed: Set<Int> = [5, 6, 7, 8, 9, 14, 15, 16, 17, 18, 19]
        let scored = values.enumerated().map { reversed.contains($0.offset) ? 6 - $0.element : $0.element }
        func sum(_ indices: [Int]) -> Double { Double(indices.reduce(0) { $0 + scored[$1] }) }
        let subscales: [String: Double] = [
            "extraversion": sum([0, 5, 10, 15]),
            "agreeableness": sum([1, 6, 11, 16]),
            "conscientiousness": sum([2, 7, 12, 17]),
            "negative emotionality": sum([3, 8, 13, 18]),
            "openness": sum([4, 9, 14, 19]),
        ]
        let top = subscales.max { a, b in (a.value, b.key) < (b.value, a.key) }!
        return SelfTestOutcome(
            score: top.value,
            maxScore: 20,
            label: "\(top.key)-led",
            summary: "your strongest trait is \(top.key) (\(Int(top.value))/20). the full profile below is the real result — the big five are five sliders, not one box.",
            subscales: subscales
        )
    }

    // MARK: Dirty Dozen (dark triad)

    static let dirtyDozen = SelfTest(
        id: "dirty_dozen",
        name: "dark triad",
        tagline: "machiavelli, narcissus, or neither — 12 blunt questions",
        icon: "theatermasks.fill",
        tint: .witsPink,
        source: "Dirty Dozen — Jonason & Webster",
        isScreener: false,
        intro: "twelve uncomfortable statements. the test only works if you answer like nobody's watching — because nobody is.",
        scale: agreement5,
        questions: [
            .init(text: "i tend to manipulate others to get my way."),
            .init(text: "i have used deceit or lied to get my way."),
            .init(text: "i have used flattery to get my way."),
            .init(text: "i tend to exploit others toward my own end."),
            .init(text: "i tend to lack remorse."),
            .init(text: "i tend to be unconcerned with the morality of my actions."),
            .init(text: "i tend to be callous or insensitive."),
            .init(text: "i tend to be cynical."),
            .init(text: "i tend to want others to admire me."),
            .init(text: "i tend to want others to pay attention to me."),
            .init(text: "i tend to seek prestige or status."),
            .init(text: "i tend to expect special favors from others."),
        ],
        score: scoreDirtyDozen
    )

    static func scoreDirtyDozen(_ values: [Int]) -> SelfTestOutcome {
        func sum(_ range: Range<Int>) -> Double { Double(values[range].reduce(0, +)) }
        let subscales: [String: Double] = [
            "machiavellianism": sum(0..<4),
            "psychopathy": sum(4..<8),
            "narcissism": sum(8..<12),
        ]
        let total = values.reduce(0, +)   // 12...60
        let label: String
        let summary: String
        switch total {
        case ...24:
            label = "low dark traits (\(total)/60)"
            summary = "your shadow side stays mostly in the shade. the subscales below show where the little there is lives."
        case 25...35:
            label = "average shadows (\(total)/60)"
            summary = "a normal amount of strategic self-interest — everyone carries some of each trait."
        case 36...47:
            label = "elevated dark traits (\(total)/60)"
            summary = "you lean into the dark triad more than most. worth knowing which subscale drives it."
        default:
            label = "high dark traits (\(total)/60)"
            summary = "a notably high score — remember it measures self-reported tendencies, not destiny."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 60, label: label, summary: summary, subscales: subscales)
    }

    // MARK: NCS-6 (need for cognition)

    static let ncs6 = SelfTest(
        id: "ncs6",
        name: "need for cognition",
        tagline: "do you actually enjoy thinking hard?",
        icon: "brain.head.profile",
        tint: .witsViolet,
        source: "NCS-6 — need for cognition scale, short form",
        isScreener: false,
        intro: "six statements about how you relate to hard thinking. characteristic means \"that's so me.\"",
        scale: [
            .init(label: "extremely uncharacteristic of me", value: 1),
            .init(label: "somewhat uncharacteristic", value: 2),
            .init(label: "uncertain", value: 3),
            .init(label: "somewhat characteristic", value: 4),
            .init(label: "extremely characteristic of me", value: 5),
        ],
        questions: [
            .init(text: "i would prefer complex to simple problems."),
            .init(text: "i like to have the responsibility of handling a situation that requires a lot of thinking."),
            .init(text: "thinking is not my idea of fun."),
            .init(text: "i would rather do something that requires little thought than something that is sure to challenge my thinking abilities."),
            .init(text: "i really enjoy a task that involves coming up with new solutions to problems."),
            .init(text: "i would prefer a task that is intellectual, difficult, and important to one that is somewhat important but does not require much thought."),
        ],
        score: scoreNCS6
    )

    static func scoreNCS6(_ values: [Int]) -> SelfTestOutcome {
        let reversed: Set<Int> = [2, 3]
        let total = values.enumerated().reduce(0) { $0 + (reversed.contains($1.offset) ? 6 - $1.element : $1.element) }
        let label: String
        let summary: String
        switch total {
        case ...13:
            label = "practical mind (\(total)/30)"
            summary = "you think when it pays and skip it when it doesn't — efficient, not lazy."
        case 14...21:
            label = "balanced thinker (\(total)/30)"
            summary = "you enjoy a good problem without needing every problem to be one."
        case 22...26:
            label = "deep thinker (\(total)/30)"
            summary = "hard problems energize you more than they drain you. wits should feel like home."
        default:
            label = "insatiable mind (\(total)/30)"
            summary = "thinking is your recreation. the top of this scale is where puzzle-a-day people live."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 30, label: label, summary: summary)
    }

    // MARK: WHO-5 (wellbeing)

    static let who5 = SelfTest(
        id: "who5",
        name: "wellbeing",
        tagline: "the WHO's 5-question wellbeing check",
        icon: "sun.max.fill",
        tint: .witsGold,
        source: "WHO-5 well-being index — World Health Organization",
        isScreener: false,
        intro: "five statements about the last two weeks. pick what's been true, not what should be.",
        scale: [
            .init(label: "at no time", value: 0),
            .init(label: "some of the time", value: 1),
            .init(label: "less than half of the time", value: 2),
            .init(label: "more than half of the time", value: 3),
            .init(label: "most of the time", value: 4),
            .init(label: "all of the time", value: 5),
        ],
        questions: [
            .init(text: "i have felt cheerful and in good spirits."),
            .init(text: "i have felt calm and relaxed."),
            .init(text: "i have felt active and vigorous."),
            .init(text: "i woke up feeling fresh and rested."),
            .init(text: "my daily life has been filled with things that interest me."),
        ],
        score: scoreWHO5
    )

    static func scoreWHO5(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +) * 4   // 0...100
        let label: String
        let summary: String
        switch total {
        case ...28:
            label = "running on empty (\(total)/100)"
            summary = "the last two weeks have been heavy. a score this low is the WHO's cue to check in with someone you trust — or a professional."
        case 29...50:
            label = "below par (\(total)/100)"
            summary = "wellbeing has been below the typical range lately. small daily anchors (sleep, movement, light) move this score more than anything."
        case 51...75:
            label = "steady (\(total)/100)"
            summary = "a solid, typical range — most days are working for you."
        default:
            label = "thriving (\(total)/100)"
            summary = "the last two weeks have genuinely been good ones. bottle whatever this routine is."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 100, label: label, summary: summary)
    }

    // MARK: Rosenberg (self-esteem)

    static let rosenberg = SelfTest(
        id: "rosenberg",
        name: "self-esteem",
        tagline: "the classic 10-item Rosenberg scale",
        icon: "heart.fill",
        tint: .witsPink,
        source: "Rosenberg self-esteem scale",
        isScreener: false,
        intro: "ten statements about how you see yourself. go with your gut — first answers are usually the honest ones.",
        scale: [
            .init(label: "strongly agree", value: 3),
            .init(label: "agree", value: 2),
            .init(label: "disagree", value: 1),
            .init(label: "strongly disagree", value: 0),
        ],
        questions: [
            .init(text: "on the whole, i am satisfied with myself."),
            .init(text: "at times i think i am no good at all."),
            .init(text: "i feel that i have a number of good qualities."),
            .init(text: "i am able to do things as well as most other people."),
            .init(text: "i feel i do not have much to be proud of."),
            .init(text: "i certainly feel useless at times."),
            .init(text: "i feel that i'm a person of worth, at least on an equal plane with others."),
            .init(text: "i wish i could have more respect for myself."),
            .init(text: "all in all, i am inclined to feel that i am a failure."),
            .init(text: "i take a positive attitude toward myself."),
        ],
        score: scoreRosenberg
    )

    static func scoreRosenberg(_ values: [Int]) -> SelfTestOutcome {
        let reversed: Set<Int> = [1, 4, 5, 7, 8]
        let total = values.enumerated().reduce(0) { $0 + (reversed.contains($1.offset) ? 3 - $1.element : $1.element) }
        let label: String
        let summary: String
        switch total {
        case ...14:
            label = "running low (\(total)/30)"
            summary = "you're harder on yourself than the evidence warrants. low scores here respond well to small tracked wins — which is half of what training streaks are."
        case 15...25:
            label = "healthy range (\(total)/30)"
            summary = "a secure, realistic view of yourself — the range most people land in."
        default:
            label = "rock solid (\(total)/30)"
            summary = "high, stable self-regard. the top of this scale is quiet confidence, and you're there."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 30, label: label, summary: summary)
    }

    // MARK: GAD-7 (anxiety)

    static let gad7 = SelfTest(
        id: "gad7",
        name: "anxiety check",
        tagline: "the 7-question screener clinics use worldwide",
        icon: "wind",
        tint: .witsSky,
        source: "GAD-7 — generalized anxiety scale, Spitzer et al. (public domain)",
        isScreener: true,
        intro: "seven questions about the last two weeks. over the last 2 weeks, how often have you been bothered by each of these?",
        scale: bothered4,
        questions: [
            .init(text: "feeling nervous, anxious, or on edge."),
            .init(text: "not being able to stop or control worrying."),
            .init(text: "worrying too much about different things."),
            .init(text: "trouble relaxing."),
            .init(text: "being so restless that it's hard to sit still."),
            .init(text: "becoming easily annoyed or irritable."),
            .init(text: "feeling afraid, as if something awful might happen."),
        ],
        score: scoreGAD7
    )

    static func scoreGAD7(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)   // 0...21
        let label: String
        let summary: String
        switch total {
        case ...4:
            label = "minimal (\(total)/21)"
            summary = "anxiety hasn't been running the show these two weeks. everyone visits this scale sometimes — nice to be at the quiet end."
        case 5...9:
            label = "mild (\(total)/21)"
            summary = "some anxiety in the mix, at a level most people move through. worth watching, not worth alarm."
        case 10...14:
            label = "moderate (\(total)/21)"
            summary = "a score of 10+ is the line where this screener suggests talking to a professional. it's a signal worth taking seriously, not a diagnosis."
        default:
            label = "severe range (\(total)/21)"
            summary = "the last two weeks have been genuinely hard. this is exactly the score range where talking to a professional helps most — please consider it."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 21, label: label, summary: summary)
    }

    // MARK: PHQ-8 (low mood)

    static let phq8 = SelfTest(
        id: "phq8",
        name: "low mood",
        tagline: "the 8-question PHQ mood screener",
        icon: "cloud.rain.fill",
        tint: .witsViolet,
        source: "PHQ-8 — patient health questionnaire, Kroenke et al. (public domain)",
        isScreener: true,
        intro: "eight questions about the last two weeks. over the last 2 weeks, how often have you been bothered by each of these?",
        scale: bothered4,
        questions: [
            .init(text: "little interest or pleasure in doing things."),
            .init(text: "feeling down, depressed, or hopeless."),
            .init(text: "trouble falling or staying asleep, or sleeping too much."),
            .init(text: "feeling tired or having little energy."),
            .init(text: "poor appetite or overeating."),
            .init(text: "feeling bad about yourself — or that you are a failure or have let yourself or your family down."),
            .init(text: "trouble concentrating on things, such as reading or watching tv."),
            .init(text: "moving or speaking so slowly that other people noticed — or the opposite, being fidgety or restless."),
        ],
        score: scorePHQ8
    )

    static func scorePHQ8(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)   // 0...24
        let label: String
        let summary: String
        switch total {
        case ...4:
            label = "minimal (\(total)/24)"
            summary = "mood has held steady these two weeks. this scale moves — retaking it monthly makes it a useful weather report."
        case 5...9:
            label = "mild (\(total)/24)"
            summary = "a dip, at a level lots of people pass through. sleep, movement and daylight move this score more than willpower does."
        case 10...14:
            label = "moderate (\(total)/24)"
            summary = "10+ is where this screener recommends checking in with a professional. that's a signal worth acting on, not a diagnosis."
        default:
            label = "significant (\(total)/24)"
            summary = "these two weeks have been heavy. a score here is the strongest cue this screener gives to talk to someone — a professional, or someone you trust as a first step."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 24, label: label, summary: summary)
    }

    // MARK: Stress load (wits original)

    static let stress10 = SelfTest(
        id: "stress10",
        name: "stress load",
        tagline: "how much are you actually carrying right now?",
        icon: "flame.fill",
        tint: .witsWarm,
        source: "wits reflection — 10 items written for wits, not a clinical scale",
        isScreener: false,
        intro: "ten questions about the last month. in the last month, how often have you…",
        scale: frequency5,
        questions: [
            .init(text: "felt there was more to do than you could realistically handle?"),
            .init(text: "felt tension in your body — jaw, shoulders, stomach — with no obvious cause?"),
            .init(text: "kept thinking about work or obligations during your downtime?"),
            .init(text: "snapped at someone over something small?"),
            .init(text: "felt like events were happening to you, out of your control?"),
            .init(text: "had trouble winding down enough to fall asleep?"),
            .init(text: "skipped meals, movement or breaks because there was \"no time\"?"),
            .init(text: "felt a background hum of urgency even when nothing was due?"),
            .init(text: "found small setbacks hitting harder than they should?"),
            .init(text: "ended the day feeling wrung out rather than tired-but-satisfied?"),
        ],
        score: scoreStress10
    )

    static func scoreStress10(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)   // 0...40
        let label: String
        let summary: String
        switch total {
        case ...10:
            label = "light load (\(total)/40)"
            summary = "you're carrying a normal amount. whatever your recovery routine is, it's working — keep it."
        case 11...20:
            label = "carrying some (\(total)/40)"
            summary = "a real load, still within range. the items you marked \"often\" are the ones worth designing around."
        case 21...30:
            label = "heavy load (\(total)/40)"
            summary = "stress is leaking into your body and sleep. subtracting one commitment usually beats adding one coping trick."
        default:
            label = "red zone (\(total)/40)"
            summary = "this level of sustained load is the kind that compounds. treat recovery as a task with a deadline, not a reward."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 40, label: label, summary: summary)
    }

    // MARK: Burnout (wits original)

    static let burnout10 = SelfTest(
        id: "burnout10",
        name: "burnout",
        tagline: "tired-tired, or something deeper?",
        icon: "battery.25",
        tint: .witsGold,
        source: "wits reflection — 10 items written for wits, not a clinical scale",
        isScreener: false,
        intro: "ten statements about how work — paid, study, or care — has felt lately. how often is each one true?",
        scale: frequency5,
        questions: [
            .init(text: "you wake up tired even after a full night's sleep."),
            .init(text: "by mid-afternoon you're running on fumes."),
            .init(text: "small tasks feel like they need a run-up."),
            .init(text: "rest days don't seem to recharge you anymore."),
            .init(text: "your body feels heavier than your schedule looks."),
            .init(text: "things you used to care about feel like chores."),
            .init(text: "you catch yourself doing the minimum and feeling nothing about it."),
            .init(text: "you feel detached from the point of what you do."),
            .init(text: "your cynical jokes about it feel less like jokes lately."),
            .init(text: "you can't remember the last time you felt proud of the work."),
        ],
        score: scoreBurnout10
    )

    static func scoreBurnout10(_ values: [Int]) -> SelfTestOutcome {
        func sum(_ range: Range<Int>) -> Double { Double(values[range].reduce(0, +)) }
        let subscales: [String: Double] = [
            "drain (energy)": sum(0..<5),
            "distance (caring)": sum(5..<10),
        ]
        let total = values.reduce(0, +)   // 0...40
        let label: String
        let summary: String
        switch total {
        case ...10:
            label = "charged (\(total)/40)"
            summary = "energy and caring are both intact. this is the baseline worth protecting."
        case 11...20:
            label = "running warm (\(total)/40)"
            summary = "early signs, still recoverable with ordinary rest. check which subscale is higher — losing energy and losing caring need different fixes."
        case 21...30:
            label = "smoldering (\(total)/40)"
            summary = "this is the range where \"push through\" stops working. if distance outweighs drain, it's about meaning, not sleep."
        default:
            label = "burnout range (\(total)/40)"
            summary = "sustained scores here usually don't resolve on their own. something structural about the load needs to change — and that's worth help to figure out."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 40, label: label, summary: summary, subscales: subscales)
    }

    // MARK: Overthinking (wits original)

    static let overthink10 = SelfTest(
        id: "overthink10",
        name: "overthinking",
        tagline: "is your mind solving, or just spinning?",
        icon: "arrow.triangle.2.circlepath",
        tint: .witsAccent,
        source: "wits reflection — 10 items written for wits, not a clinical scale",
        isScreener: false,
        intro: "ten habits of a looping mind. how often do you catch yourself doing each one?",
        scale: frequency5,
        questions: [
            .init(text: "replaying conversations, editing what you should have said?"),
            .init(text: "rehearsing future conversations that may never happen?"),
            .init(text: "reopening decisions you already made, hunting for the mistake?"),
            .init(text: "losing sleep to a thought loop you can't put down?"),
            .init(text: "reading a neutral message several times for hidden meaning?"),
            .init(text: "comparing options long after they became roughly equal?"),
            .init(text: "building worst-case scenarios in vivid detail?"),
            .init(text: "asking for reassurance on something you already know?"),
            .init(text: "mistaking more thinking for more progress?"),
            .init(text: "feeling exhausted by decisions that never left your head?"),
        ],
        score: scoreOverthink10
    )

    static func scoreOverthink10(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)   // 0...40
        let label: String
        let summary: String
        switch total {
        case ...10:
            label = "settled mind (\(total)/40)"
            summary = "your thoughts mostly finish and file themselves. rarer than it sounds."
        case 11...20:
            label = "occasional loops (\(total)/40)"
            summary = "normal amounts of replay and rehearsal. loops that resolve into decisions are just called thinking."
        case 21...30:
            label = "busy loops (\(total)/40)"
            summary = "a lot of cycles are going to thoughts that don't cash out. writing the loop down is the cheapest known exit."
        default:
            label = "spin cycle (\(total)/40)"
            summary = "the machine is running hot on idle. deadlines for decisions — even tiny ones — break loops better than \"just stop thinking about it\" ever has."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 40, label: label, summary: summary)
    }

    // MARK: Impostor feelings (wits original)

    static let impostor10 = SelfTest(
        id: "impostor10",
        name: "impostor feelings",
        tagline: "do you believe your own track record?",
        icon: "person.fill.questionmark",
        tint: .witsPink,
        source: "wits reflection — 10 items written for wits, not a clinical scale",
        isScreener: false,
        intro: "ten statements about how you explain your own successes. rate how much each one sounds like you.",
        scale: agreement5,
        questions: [
            .init(text: "when something goes well, my first explanation is luck or timing."),
            .init(text: "i worry people will eventually find out i'm less capable than they think."),
            .init(text: "compliments about my ability are hard to actually believe."),
            .init(text: "i remember my failures far more vividly than my wins."),
            .init(text: "i feel like i've fooled people into rating me too highly."),
            .init(text: "when i succeed, i quietly discount it — anyone could have done it."),
            .init(text: "i over-prepare because \"good enough\" never feels safe."),
            .init(text: "i compare my behind-the-scenes to everyone else's highlight reel."),
            .init(text: "new challenges feel like the moment i finally get exposed."),
            .init(text: "i credit others' success to skill, but mine to effort or luck."),
        ],
        score: scoreImpostor10
    )

    static func scoreImpostor10(_ values: [Int]) -> SelfTestOutcome {
        let total = values.reduce(0, +)   // 10...50
        let label: String
        let summary: String
        switch total {
        case ...20:
            label = "credits earned (\(total)/50)"
            summary = "you mostly believe your own track record. that's the healthy calibration everyone else is aiming for."
        case 21...30:
            label = "occasional visitor (\(total)/50)"
            summary = "impostor feelings drop by, especially around new challenges — which is where they visit almost everyone."
        case 31...40:
            label = "frequent guest (\(total)/50)"
            summary = "the discounting habit is doing real work against you. evidence beats affirmations: keep a plain list of things you objectively did."
        default:
            label = "moved in (\(total)/50)"
            summary = "the feeling of being found out is running the narration. worth remembering: actual impostors don't worry about being impostors."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 50, label: label, summary: summary)
    }

    // MARK: Procrastination (wits original)

    static let procrast9 = SelfTest(
        id: "procrast9",
        name: "procrastination",
        tagline: "starter, delayer, or deadline gambler?",
        icon: "hourglass",
        tint: .witsMustard,
        source: "wits reflection — 9 items written for wits, not a clinical scale",
        isScreener: false,
        intro: "nine statements about how you and deadlines get along. answer for how you actually behave, not this week's intentions.",
        scale: agreement5,
        questions: [
            .init(text: "i delay starting tasks even when i know the delay will cost me."),
            .init(text: "\"i work better under pressure\" is my cover story for starting late."),
            .init(text: "i do easy, unimportant tasks to avoid the important one."),
            .init(text: "deadlines sneak up on me even when i saw them coming for weeks."),
            .init(text: "i start tasks soon after i get them."),
            .init(text: "\"five more minutes\" of scrolling regularly becomes an hour."),
            .init(text: "i wait for the right mood to start hard things."),
            .init(text: "i finish what i plan for the day."),
            .init(text: "the guilt of not starting often feels worse than the task itself."),
        ],
        score: scoreProcrast9
    )

    static func scoreProcrast9(_ values: [Int]) -> SelfTestOutcome {
        let reversed: Set<Int> = [4, 7]
        let total = values.enumerated().reduce(0) { $0 + (reversed.contains($1.offset) ? 6 - $1.element : $1.element) }
        // 9...45
        let label: String
        let summary: String
        switch total {
        case ...18:
            label = "starter (\(total)/45)"
            summary = "you mostly begin when you decide to. the rarest skill on this page."
        case 19...27:
            label = "mild delayer (\(total)/45)"
            summary = "ordinary friction between intention and action. shrinking the first step usually clears it."
        case 28...36:
            label = "practiced procrastinator (\(total)/45)"
            summary = "delay is a habit with a system behind it. the fix isn't discipline — it's making starting cheaper than avoiding."
        default:
            label = "deadline gambler (\(total)/45)"
            summary = "you're running a casino where the house is future-you. the pressure rush works until the one time it doesn't."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 45, label: label, summary: summary)
    }

    // MARK: BEIS-10 (emotional intelligence)

    static let beis10 = SelfTest(
        id: "beis10",
        name: "emotional intelligence",
        tagline: "reading feelings — yours and everyone else's",
        icon: "face.smiling.inverse",
        tint: .witsSky,
        source: "BEIS-10 — brief emotional intelligence scale, Davies et al.",
        isScreener: false,
        intro: "ten statements about noticing and steering emotions. rate how much you agree with each.",
        scale: agreement5,
        questions: [
            .init(text: "i know why my emotions change."),
            .init(text: "i easily recognize my emotions as i experience them."),
            .init(text: "i can tell how people are feeling by listening to the tone of their voice."),
            .init(text: "by looking at their facial expressions, i recognize the emotions people are experiencing."),
            .init(text: "i seek out activities that make me happy."),
            .init(text: "i have control over my emotions."),
            .init(text: "i arrange events others enjoy."),
            .init(text: "i help other people feel better when they are down."),
            .init(text: "when i am in a positive mood, i am able to come up with new ideas."),
            .init(text: "i use good moods to help myself keep trying in the face of obstacles."),
        ],
        score: scoreBEIS10
    )

    static func scoreBEIS10(_ values: [Int]) -> SelfTestOutcome {
        func sum(_ indices: [Int]) -> Double { Double(indices.reduce(0) { $0 + values[$1] }) }
        let subscales: [String: Double] = [
            "reading yourself": sum([0, 1]) * 2,
            "reading others": sum([2, 3]) * 2,
            "steering yourself": sum([4, 5]) * 2,
            "lifting others": sum([6, 7]) * 2,
            "using moods": sum([8, 9]) * 2,
        ]
        let total = values.reduce(0, +)   // 10...50
        let label: String
        let summary: String
        switch total {
        case ...25:
            label = "still tuning (\(total)/50)"
            summary = "emotional signal comes through patchy. the subscales below show which channel to practice — noticing usually comes before steering."
        case 26...37:
            label = "tuned in (\(total)/50)"
            summary = "a solid, typical read on yourself and others, with room in whichever subscale runs lowest."
        default:
            label = "finely tuned (\(total)/50)"
            summary = "you read the room and yourself with high fidelity. the balance across subscales below matters more than the total."
        }
        return SelfTestOutcome(score: Double(total), maxScore: 50, label: label, summary: summary, subscales: subscales)
    }
}

// MARK: - Flow UI

struct SelfTestFlowView: View {
    let test: SelfTest
    let lastRecord: SelfTestRecord?
    let onComplete: (SelfTestOutcome) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Stage: Equatable {
        case intro
        case question(Int)
        case result(SelfTestOutcome)
    }

    @State private var stage: Stage = .intro
    @State private var answers: [Int] = []
    @State private var picked: Int?

    private var sourceParts: (instrument: String, origin: String) {
        let parts = test.source.components(separatedBy: " — ")
        let instrument = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? test.source
        let origin = parts.dropFirst().joined(separator: " — ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (instrument, origin.isEmpty ? "self-report" : origin)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            switch stage {
            case .intro: intro
            case .question(let index): questionView(index)
            case .result(let outcome): resultView(outcome)
            }
        }
        .background(Color.witsBg.ignoresSafeArea())
    }

    private var header: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.witsFaint.opacity(0.34))
                .frame(width: 44, height: 5)
                .padding(.top, 8)

            HStack {
                if case .question(let index) = stage {
                    Button {
                        withQuestionAnimation {
                            if index == 0 {
                                stage = .intro
                            } else {
                                if !answers.isEmpty { answers.removeLast() }
                                stage = .question(index - 1)
                            }
                            picked = nil
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color.witsMuted)
                            .frame(width: 42, height: 42)
                            .background(Color.witsTint, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("previous question")
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.witsMuted)
                        .frame(width: 42, height: 42)
                        .background(Color.witsTint, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("close")
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
        }
        .frame(height: 60)
        .padding(.top, 4)
    }

    private func withQuestionAnimation(_ changes: () -> Void) {
        withAnimation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.32)) {
            changes()
        }
    }

    // MARK: Intro

    private var intro: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introHero
                introMetadata

                if let lastRecord {
                    lastResultCard(lastRecord)
                } else {
                    firstRunCard
                }

                if test.isScreener {
                    screenerDisclaimerCard
                }
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 112)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                answers = []
                picked = nil
                withQuestionAnimation {
                    stage = .question(0)
                }
            } label: {
                Text(lastRecord == nil ? "start" : "take it again")
                    .font(.witsBody(17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(test.tint, in: Capsule())
                    .shadow(color: test.tint.opacity(0.28), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(
                LinearGradient(colors: [
                    Color.witsBg.opacity(0),
                    Color.witsBg,
                    Color.witsBg,
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
        }
    }

    private var introHero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: test.icon)
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(test.tint)
                .frame(width: 88, height: 88)
                .background(
                    LinearGradient(colors: [test.tint.opacity(0.22), Color.witsCard.opacity(0.96)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)
                        .strokeBorder(test.tint.opacity(0.42), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 9) {
                Text(test.name)
                    .font(.witsDisplay(31))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Text(test.intro)
                    .font(.witsBody(15.5))
                    .foregroundStyle(Color.witsMuted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
        }
        .padding(.vertical, 4)
    }

    private var introMetadata: some View {
        HStack(spacing: 0) {
            metadataItem(icon: "doc.text.fill", title: "\(test.questions.count) questions")
            metadataDivider
            metadataItem(icon: "checkmark.shield.fill", title: sourceParts.instrument)
            metadataDivider
            metadataItem(icon: "person.text.rectangle.fill", title: compactOriginLabel(sourceParts.origin))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.witsCard.opacity(0.78), in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(Color.witsLine, lineWidth: 1)
        )
    }

    private func metadataItem(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(test.tint)
            Text(title)
                .font(.witsBody(12.5, weight: .semibold))
                .foregroundStyle(Color.witsMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var metadataDivider: some View {
        Rectangle()
            .fill(Color.witsLine)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 10)
    }

    private func lastResultCard(_ record: SelfTestRecord) -> some View {
        let shape = RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)

        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("last result")
                        .font(.witsLabel(13))
                        .foregroundStyle(test.tint)
                        .textCase(.uppercase)
                        .kerning(0.7)

                    Text(record.label)
                        .font(.witsHeading(26))
                        .foregroundStyle(Color.witsInk)
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)
                        .fixedSize(horizontal: false, vertical: true)

                    Label("last taken \(Self.shortDate(record.takenAt))", systemImage: "calendar")
                        .font(.witsBody(14, weight: .semibold))
                        .foregroundStyle(Color.witsMuted)
                }
                .layoutPriority(1)

                scoreRing(record)
            }

            segmentedScore(record)

            Text("your latest saved result for this test. retakes replace what appears on your profile.")
                .font(.witsBody(14))
                .foregroundStyle(Color.witsMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Color.witsCard, test.tint.opacity(0.08)],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing),
            in: shape
        )
        .overlay(shape.strokeBorder(Color.witsLine, lineWidth: 1))
        .shadow(color: Color.witsShadow, radius: 10, y: 5)
        .accessibilityElement(children: .combine)
    }

    private var firstRunCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(test.tint)
                .frame(width: 38, height: 38)
                .background(test.tint.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("quick check-in")
                    .font(.witsHeading(16))
                    .foregroundStyle(Color.witsInk)
                Text("answer honestly. this takes about a minute and only your latest result is shown on your profile.")
                    .font(.witsBody(14))
                    .foregroundStyle(Color.witsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color.witsCard, in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(Color.witsLine, lineWidth: 1)
        )
    }

    private var screenerDisclaimerCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(test.tint)
                .frame(width: 42, height: 42)
                .background(test.tint.opacity(0.13), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("screening signal, not a diagnosis")
                    .font(.witsHeading(15.5))
                    .foregroundStyle(Color.witsInk)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SelfTestCatalog.screenerDisclaimer)
                    .font(.witsBody(13.5))
                    .foregroundStyle(Color.witsMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
        }
        .padding(16)
        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: WitsMetrics.radius, style: .continuous)
                .strokeBorder(Color.witsLine, lineWidth: 1)
        )
    }

    private func scoreRing(_ record: SelfTestRecord) -> some View {
        let fraction = scoreFraction(record)

        return ZStack {
            Circle()
                .stroke(Color.witsLine, lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(test.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(scoreLabel(record))
                .font(.witsValue(17))
                .foregroundStyle(test.tint)
                .monospacedDigit()
                .minimumScaleFactor(0.72)
        }
        .frame(width: 74, height: 74)
        .accessibilityLabel("score \(scoreLabel(record))")
    }

    private func segmentedScore(_ record: SelfTestRecord) -> some View {
        let filled = max(0, min(Int(round(scoreFraction(record) * 6)), 6))

        return HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(index < filled ? test.tint : Color.witsLine)
                    .frame(height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private func scoreFraction(_ record: SelfTestRecord) -> Double {
        guard record.maxScore > 0 else { return 0 }
        return min(max(record.score / record.maxScore, 0), 1)
    }

    private func scoreLabel(_ record: SelfTestRecord) -> String {
        "\(formatScore(record.score))/\(formatScore(record.maxScore))"
    }

    private func formatScore(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func compactOriginLabel(_ origin: String) -> String {
        let lowered = origin.lowercased()
        if lowered.contains("self-report") { return "self-report" }
        if lowered.contains("questionnaire") { return "questionnaire" }
        return origin
    }

    // MARK: Questions

    private func questionView(_ index: Int) -> some View {
        let question = test.questions[index]
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                questionProgressHeader(index)
                questionPrompt(question)
                answerGroup(question, index: index)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 10)
            .padding(.bottom, 28)
        }
        .safeAreaInset(edge: .bottom) {
            questionNextButton(index, question: question)
        }
        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
        .animation(.timingCurve(0.2, 0.8, 0.25, 1, duration: 0.28), value: index)
        .id(index)   // reset scroll per question
    }

    private func questionProgressHeader(_ index: Int) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: test.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(test.tint)
                    .frame(width: 38, height: 38)
                    .background(test.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text(test.name)
                    .font(.witsHeading(18))
                    .foregroundStyle(Color.witsInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer(minLength: 10)

                Text("\(index + 1) of \(test.questions.count)")
                    .font(.witsValue(15))
                    .foregroundStyle(test.tint)
                    .monospacedDigit()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.witsTint, in: Capsule())
            }

            ProgressTrack(fraction: Double(index + 1) / Double(test.questions.count), tint: test.tint)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func questionPrompt(_ question: SelfTestQuestion) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let context = question.context {
                Label(context, systemImage: "eye.fill")
                    .font(.witsBody(14, weight: .bold))
                    .foregroundStyle(test.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(question.text)
                .font(.witsHeading(24))
                .foregroundStyle(Color.witsInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("choose the closest answer")
                .font(.witsLabel(12))
                .foregroundStyle(Color.witsFaint)
                .textCase(.uppercase)
                .kerning(0.7)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func answerGroup(_ question: SelfTestQuestion, index: Int) -> some View {
        let options = Array(test.options(for: question).enumerated())
        let shape = RoundedRectangle(cornerRadius: WitsMetrics.panelRadius, style: .continuous)

        return VStack(spacing: 0) {
            ForEach(options, id: \.offset) { optionIndex, option in
                if optionIndex > 0 {
                    Rectangle()
                        .fill(Color.witsLine)
                        .frame(height: 1)
                        .padding(.leading, 64)
                }

                selfTestAnswerRow(option.label,
                                  number: optionIndex + 1,
                                  picked: picked == optionIndex) {
                    selectAnswer(optionIndex)
                }
            }
        }
        .background(Color.witsCard.opacity(0.78), in: shape)
        .overlay(shape.strokeBorder(Color.witsLine, lineWidth: 1))
        .clipShape(shape)
    }

    private func selfTestAnswerRow(_ label: String,
                                   number: Int,
                                   picked: Bool,
                                   action: @escaping () -> Void) -> some View {
        let parts = answerLabelParts(label)

        return Button(action: action) {
            HStack(alignment: .center, spacing: 13) {
                Text("\(number)")
                    .font(.witsValue(13))
                    .foregroundStyle(picked ? .white : test.tint)
                    .monospacedDigit()
                    .frame(width: 30, height: 30)
                    .background(picked ? test.tint : test.tint.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(parts.title)
                        .font(.witsBody(17, weight: .bold))
                        .foregroundStyle(Color.witsInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = parts.detail {
                        Text(detail)
                            .font(.witsBody(13.5))
                            .foregroundStyle(Color.witsMuted)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                ZStack {
                    Circle()
                        .strokeBorder(picked ? test.tint : Color.witsFaint.opacity(0.32), lineWidth: 2)
                        .frame(width: 26, height: 26)
                    if picked {
                        Circle()
                            .fill(test.tint)
                            .frame(width: 13, height: 13)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(minHeight: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .animation(.easeOut(duration: 0.12), value: picked)
        .accessibilityLabel("\(number). \(label)")
    }

    private func answerLabelParts(_ label: String) -> (title: String, detail: String?) {
        let separators = [" — ", " - "]
        for separator in separators {
            let pieces = label.components(separatedBy: separator)
            if pieces.count > 1, let first = pieces.first {
                let detail = pieces.dropFirst().joined(separator: separator)
                return (first, detail)
            }
        }

        if let comma = label.firstIndex(of: ","), label.distance(from: label.startIndex, to: comma) <= 22 {
            let title = String(label[..<comma])
            let detailStart = label.index(after: comma)
            let detail = label[detailStart...].trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, detail.isEmpty ? nil : detail)
        }

        return (label, nil)
    }

    @ViewBuilder
    private func questionNextButton(_ index: Int, question: SelfTestQuestion) -> some View {
        if picked != nil {
            Button {
                confirmAnswer(from: index, question: question)
            } label: {
                Text(index + 1 == test.questions.count ? "finish" : "next")
                    .font(.witsBody(17, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(test.tint, in: Capsule())
                    .shadow(color: test.tint.opacity(0.24), radius: 14, y: 7)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(
                LinearGradient(colors: [
                    Color.witsBg.opacity(0),
                    Color.witsBg,
                    Color.witsBg,
                ], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func selectAnswer(_ index: Int) {
        GameFeel.shared.uiTick(0.55)
        withAnimation(.easeOut(duration: 0.16)) {
            picked = index
        }
    }

    private func confirmAnswer(from index: Int, question: SelfTestQuestion) {
        let options = test.options(for: question)
        guard let picked, options.indices.contains(picked) else { return }
        let value = options[picked].value
        withQuestionAnimation {
            advance(with: value, from: index)
        }
    }

    private func advance(with value: Int, from index: Int) {
        answers.append(value)
        picked = nil
        if index + 1 < test.questions.count {
            stage = .question(index + 1)
        } else {
            let outcome = test.score(answers)
            stage = .result(outcome)
            onComplete(outcome)
        }
    }

    // MARK: Result

    private func resultView(_ outcome: SelfTestOutcome) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(test.name)
                    .font(.witsLabel(12.5))
                    .foregroundStyle(Color.witsFaint)
                    .textCase(.uppercase)
                    .kerning(0.8)
                    .padding(.top, 12)
                Text(outcome.label)
                    .font(.witsDisplay(28))
                    .foregroundStyle(test.tint)
                Text(outcome.summary)
                    .font(.witsBody(16))
                    .foregroundStyle(Color.witsMuted)
                if let subscales = outcome.subscales {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(subscales.sorted { $0.value > $1.value }, id: \.key) { name, value in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(name)
                                        .font(.witsBody(14, weight: .semibold))
                                        .foregroundStyle(Color.witsInk)
                                    Spacer()
                                    Text("\(Int(value))/20")
                                        .font(.witsBody(13, weight: .semibold))
                                        .foregroundStyle(Color.witsMuted)
                                        .monospacedDigit()
                                }
                                ProgressTrack(fraction: value / 20.0, tint: test.tint)
                            }
                        }
                    }
                    .padding(16)
                    .cardSurface(radius: 14)
                }
                if test.isScreener {
                    Text(SelfTestCatalog.screenerDisclaimer)
                        .font(.witsBody(13))
                        .foregroundStyle(Color.witsMuted)
                        .padding(14)
                        .background(Color.witsTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Text("you can retake this any time — only your latest result is shown on your profile.")
                    .font(.witsBody(13))
                    .foregroundStyle(Color.witsFaint)
                Spacer(minLength: 16)
                Button {
                    dismiss()
                } label: {
                    Text("done")
                        .font(.witsBody(17, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(test.tint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, WitsMetrics.screenPadding)
            .padding(.bottom, 24)
        }
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day()).lowercased()
    }
}
