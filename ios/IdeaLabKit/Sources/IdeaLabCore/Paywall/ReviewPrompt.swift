import Foundation

/// When to ask for an App Store rating, as Apple advises: once people have
/// used the app for some days and finished what they came to do several
/// times, never in its first days, not twice for the same version, and two
/// weeks apart at least. Each request starts the count again: the next one
/// waits for more use. The app asks with StoreKit's own prompt only
/// (`requestsReview` in IdeaLabStore), which the system shows at most three
/// times a year, or not at all; App Review forbids prompts of the app's own
/// (Guideline 5.6.1).
public struct ReviewPrompt: Hashable, Sendable, Codable {
    /// How much use comes before a request.
    public struct Rules: Hashable, Sendable {
        /// Tasks done since the last request, or ever before the first: an
        /// entry saved, a cleanup finished. Apple's sample waits for four.
        public var tasks: Int
        /// The distinct days they were done on: a habit, not one busy hour.
        public var days: Int
        /// Days since the app was first used: never in its first days, when
        /// people do not know it yet.
        public var sinceFirstUse: Int
        /// Days between two requests: "at least a week or two" (HIG).
        public var spacing: Int

        public init(tasks: Int, days: Int, sinceFirstUse: Int, spacing: Int) {
            self.tasks = tasks
            self.days = days
            self.sinceFirstUse = sinceFirstUse
            self.spacing = spacing
        }

        public static let standard = Rules(tasks: 4, days: 2, sinceFirstUse: 3, spacing: 14)
    }

    /// When the app was first used: with `ReviewPromptStore`, when the
    /// first task was done.
    public private(set) var firstUse: Date
    /// Tasks done since the last request.
    public private(set) var tasks = 0
    /// The days they were done on, as each day starts on the app's calendar.
    public private(set) var days: Set<Date> = []
    /// When the app last asked, and for which version.
    public private(set) var lastAsked: Date?
    public private(set) var lastAskedVersion: String?

    public init(firstUse: Date) {
        self.firstUse = firstUse
    }

    /// A task done for good, whatever the app is for: a cleanup finished,
    /// an entry saved once "Hoàn tác" is gone. One taken back is no task.
    public mutating func completedTask(at date: Date, calendar: Calendar) {
        tasks += 1
        days.insert(calendar.startOfDay(for: date))
    }

    /// Whether to ask at `date`, on a screen where something just ended
    /// well, in app `version`.
    public func shouldAsk(at date: Date, version: String, calendar: Calendar, rules: Rules = .standard) -> Bool {
        guard version != lastAskedVersion, tasks >= rules.tasks, days.count >= rules.days,
              let settled = calendar.date(byAdding: .day, value: rules.sinceFirstUse, to: firstUse), date >= settled
        else { return false }
        guard let lastAsked else { return true }
        guard let next = calendar.date(byAdding: .day, value: rules.spacing, to: lastAsked) else { return false }
        return date >= next
    }

    /// Asked: not again for this version, nor before more use and time.
    public mutating func asked(at date: Date, version: String) {
        lastAsked = date
        lastAskedVersion = version
        tasks = 0
        days = []
    }
}

/// Where the app keeps its `ReviewPrompt`: its defaults. Each call reads,
/// changes and writes it in one step, whichever store and thread it comes
/// from: two tasks done at once both count, and two screens at rest at
/// once never both ask (`askIfDue`).
public struct ReviewPromptStore: Sendable {
    /// One read, change and write at a time, for every store: two done at
    /// once would read the same prompt, and the second write would drop
    /// what the first kept.
    private static let lock = NSLock()
    private let key: String
    private let suite: String?
    private let enabled: Bool

    /// - Parameters:
    ///   - suite: `UserDefaults(suiteName:)`'s name; `nil`, the app's own.
    ///   - enabled: `false` for a store that never asks and keeps nothing:
    ///     for screenshots and tests, as a build run from Xcode always shows
    ///     StoreKit's prompt.
    public init(suite: String? = nil, key: String = "IdeaLab.reviewPrompt", enabled: Bool = true) {
        self.suite = suite
        self.key = key
        self.enabled = enabled
    }

    private var defaults: UserDefaults? {
        guard enabled else { return nil }
        return suite.map { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// What was kept; until anything is, a first use at `date`.
    public func prompt(at date: Date) -> ReviewPrompt {
        guard let defaults else { return ReviewPrompt(firstUse: date) }
        return Self.lock.withLock { load(from: defaults, at: date) }
    }

    /// The version people see on the App Store (`CFBundleShortVersionString`),
    /// the one `requestsReview` asks for once: a build's number changes
    /// with every upload, and would ask again for the same version.
    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// A task done (`ReviewPrompt.completedTask`), kept.
    public func completedTask(at date: Date = .now, calendar: Calendar = .current) {
        update(at: date) { $0.completedTask(at: date, calendar: calendar) }
    }

    /// Whether to ask now (`ReviewPrompt.shouldAsk`); never when disabled.
    public func shouldAsk(at date: Date, version: String, calendar: Calendar, rules: ReviewPrompt.Rules = .standard) -> Bool {
        guard defaults != nil else { return false }
        return prompt(at: date).shouldAsk(at: date, version: version, calendar: calendar, rules: rules)
    }

    /// Asked (`ReviewPrompt.asked`), kept.
    public func asked(at date: Date, version: String) {
        update(at: date) { $0.asked(at: date, version: version) }
    }

    /// Whether to ask now, and if so, kept as asked, in one step
    /// (`shouldAsk`, then `asked`): of two screens at rest at once, only
    /// one asks. What `requestsReview` calls.
    public func askIfDue(at date: Date, version: String, calendar: Calendar, rules: ReviewPrompt.Rules = .standard) -> Bool {
        update(at: date) { prompt in
            guard prompt.shouldAsk(at: date, version: version, calendar: calendar, rules: rules) else { return false }
            prompt.asked(at: date, version: version)
            return true
        } ?? false
    }

    /// Reads the prompt, changes it and writes it back, with no other store
    /// in between; `nil`, and nothing kept, when disabled.
    @discardableResult
    private func update<Outcome>(at date: Date, _ change: (inout ReviewPrompt) -> Outcome) -> Outcome? {
        guard let defaults else { return nil }
        return Self.lock.withLock {
            var prompt = load(from: defaults, at: date)
            let outcome = change(&prompt)
            if let data = try? JSONEncoder().encode(prompt) {
                defaults.set(data, forKey: key)
            }
            return outcome
        }
    }

    /// What was kept, read with the lock held.
    private func load(from defaults: UserDefaults, at date: Date) -> ReviewPrompt {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(ReviewPrompt.self, from: $0) } ?? ReviewPrompt(firstUse: date)
    }
}

extension StoreLinks {
    /// The app's page on the App Store, open at "Viết đánh giá": for a
    /// Settings row that stays, as Apple suggests, since StoreKit's prompt
    /// may never show. `nil` unless `appID` is the digits of an App Store id.
    public static func writeReview(appID: String) -> URL? {
        guard !appID.isEmpty, appID.allSatisfy(\.isASCII), appID.allSatisfy(\.isNumber) else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review")
    }
}
