//
//  Social+Tournaments.swift
//  PickleBall
//
//  Squad tournaments: create from a squad in one tap (plus guests), keep
//  the schedule, score any match, crown the champion. Standings and
//  brackets are computed on the phone from confirmed results.
//
//  Progressive formats (King of the Court, Mexicano, knockouts, pools)
//  grow as they're played. Knockouts and pools advance on their own: any
//  phone that sees a finished feeder match adds the next one, and the
//  database's (stage, round, slot) key makes a second phone's copy a no-op.
//  Mexicano and King of the Court rounds wait for someone to tap "Next
//  round", since players may want a break.
//

import Foundation
import CourtKit
import CourtNet

extension Social {
    func entrants(of tournament: TournamentRow) -> [UUID] {
        entrants.filter { $0.tournamentID == tournament.id }.map(\.playerID)
    }

    func fixtures(of tournament: TournamentRow) -> [FixtureRow] {
        fixtures.filter { $0.tournamentID == tournament.id }
            .sorted { ($0.stage?.order ?? 0, $0.round, $0.slot ?? $0.courtNumber) < ($1.stage?.order ?? 0, $1.round, $1.slot ?? $1.courtNumber) }
    }

    /// Scores of played fixtures, from matches both sides confirmed (or
    /// that needed no confirmation).
    func scores(of tournament: TournamentRow) -> [UUID: FixtureScore] {
        var scores: [UUID: FixtureScore] = [:]
        for fixture in fixtures(of: tournament) {
            guard let matchID = fixture.matchID ?? MatchStore.shared.matchID(forFixture: fixture.id),
                  let record = MatchStore.shared.record(id: matchID), record.confirmation != .disputed,
                  let lineup = record.lineup else { continue }
            // Orient the score to the fixture's team A.
            let aIDs = Set(fixture.teamA)
            let recordAIsFixtureA = Set(lineup.teams.a.map(\.id.rawValue)).intersection(aIDs).count > 0
                || Set(lineup.teams.a.compactMap { self.playerUser($0.id.rawValue) }).intersection(aIDs).count > 0
            // Points (pickleball) or games (padel) across every game or set,
            // so point difference means the same for scored and typed results.
            var points = record.units.reduce(into: TeamPair<Int>.zero) { total, unit in
                let score = unit.isSuperTiebreak ? (unit.tiebreak ?? .zero) : unit.score
                total.a += score.a
                total.b += score.b
            }
            var winner = record.winner
            if !recordAIsFixtureA {
                points = points.swapped
                winner = winner?.opponent
            }
            scores[fixture.id] = FixtureScore(score: points, winner: winner)
        }
        return scores
    }

    /// Entrants in seed order: players, or fixed pairs.
    func units(of tournament: TournamentRow) -> [[PlayerID]] {
        if let seeded = tournament.settings?.seededEntrants, !seeded.isEmpty { return seeded }
        if tournament.format == .roundRobin, tournament.rules.isDoubles {
            // Before settings existed: the teams as scheduled.
            var pairs: [[PlayerID]] = []
            for fixture in fixtures(of: tournament) {
                for team in [fixture.teamA, fixture.teamB] {
                    let pair = team.map(PlayerID.init(rawValue:))
                    if !pairs.contains(where: { Set($0) == Set(pair) }) { pairs.append(pair) }
                }
            }
            return pairs
        }
        return entrants(of: tournament).map { [PlayerID(rawValue: $0)] }
    }

    func standings(of tournament: TournamentRow) -> [StandingRow] {
        let units = tournament.format.ranksIndividuals ? units(of: tournament).flatMap { $0 }.map { [$0] } : units(of: tournament)
        let league = fixtures(of: tournament).map(\.fixture).filter { $0.stage == .main || $0.stage == .pool }
        return Standings.compute(format: tournament.format, entrants: units, fixtures: league, scores: scores(of: tournament))
    }

    /// Pools as drawn at the start.
    func pools(of tournament: TournamentRow) -> [[[PlayerID]]] {
        guard tournament.format == .pools else { return [] }
        return Pools.split(units(of: tournament), pools: tournament.settings?.pools ?? Pools.suggestedCount(entrants: units(of: tournament).count))
    }

    /// The knockout: the whole tournament for knockouts, the second stage
    /// once pool play is done.
    func bracket(of tournament: TournamentRow) -> Bracket.State? {
        let fixtureList = fixtures(of: tournament).map(\.fixture)
        let scores = scores(of: tournament)
        switch tournament.format {
        case .singleElimination, .doubleElimination:
            return Bracket.resolve(entrants: units(of: tournament), double: tournament.format == .doubleElimination,
                                   fixtures: fixtureList, scores: scores)
        case .pools:
            let pools = pools(of: tournament)
            let advancing = tournament.settings?.advancing
                ?? Pools.suggestedAdvancing(entrants: units(of: tournament).count, pools: pools.count)
            guard let seeds = Pools.qualifiers(pools: pools, advancing: advancing, fixtures: fixtureList, scores: scores) else { return nil }
            return Bracket.resolve(entrants: seeds, double: false, fixtures: fixtureList, scores: scores)
        default:
            return nil
        }
    }

    /// Stronger players first, by level in this sport (unrated players at
    /// the starting level); ties keep the order given.
    func seeded(_ players: [PlayerRef], sport: Sport) -> [PlayerRef] {
        let levels = players.map { level(of: $0.id.rawValue, in: sport) ?? PlayerLevel().level }
        return players.indices.sorted { (-levels[$0], $0) < (-levels[$1], $1) }.map { players[$0] }
    }

    /// My own level comes from the phone; everyone else's from what they
    /// published.
    func level(of userID: UUID, in sport: Sport) -> Double? {
        if userID == self.userID, let mine = MatchStore.shared.levels.level(of: PlayerID(rawValue: userID), in: sport), !mine.isProvisional {
            return mine.level
        }
        return profiles[userID]?.level(in: sport)
    }

    struct TournamentOptions {
        var courts = 1
        var mexicanoRounds = 6
        var pools: Int?
        var advancing: Int?
        var startsAt: Date?
        var court: CourtTag?
    }

    func createTournament(squadID: UUID, name: String, format: TournamentFormat, rules: MatchRules,
                          entrants: [PlayerRef], pairs: [[PlayerRef]]?, options: TournamentOptions) async -> UUID? {
        guard let cleaned = ContentFilter.standard.cleaned(name.trimmingCharacters(in: .whitespacesAndNewlines)), !cleaned.isEmpty else {
            notice = "Pick a different name."
            return nil
        }
        let players = seeded(entrants, sport: rules.sport)
        let ids = players.map(\.id)
        // Pairs are seeded by their average level.
        let units: [[PlayerID]] = pairs.map { list in
            let average = { (pair: [PlayerRef]) in
                pair.map { self.level(of: $0.id.rawValue, in: rules.sport) ?? PlayerLevel().level }.reduce(0, +) / Double(max(pair.count, 1))
            }
            return list.indices.sorted { (-average(list[$0]), $0) < (-average(list[$1]), $1) }.map { list[$0].map(\.id) }
        } ?? ids.map { [$0] }

        var settings = TournamentSettings(entrants: units.map { $0.map(\.rawValue) }, courts: options.courts)
        var fixtureList: [Fixture]
        switch format {
        case .roundRobin:
            fixtureList = RoundRobin.schedule(units, courts: options.courts)
        case .kingOfTheCourt:
            fixtureList = KingOfTheCourt.firstRound(ids.shuffled(), doubles: rules.isDoubles).fixtures
        case .americano:
            fixtureList = Americano.schedule(ids.shuffled(), courts: options.courts)
        case .mexicano:
            settings.rounds = options.mexicanoRounds
            fixtureList = Mexicano.firstRound(ids, courts: options.courts)
        case .singleElimination, .doubleElimination:
            fixtureList = Bracket.resolve(entrants: units, double: format == .doubleElimination, fixtures: [], scores: [:]).fixturesToAdd
        case .pools:
            let count = options.pools ?? Pools.suggestedCount(entrants: units.count)
            settings.pools = count
            settings.advancing = options.advancing ?? Pools.suggestedAdvancing(entrants: units.count, pools: count)
            fixtureList = Pools.schedule(Pools.split(units, pools: count))
        }
        // Progressive rounds get a slot so they can't be added twice.
        if format == .kingOfTheCourt || format == .mexicano {
            for index in fixtureList.indices { fixtureList[index].slot = fixtureList[index].court - 1 }
        }
        // Spread the schedule: each round 20 minutes after the last.
        if let startsAt = options.startsAt {
            for index in fixtureList.indices {
                fixtureList[index].scheduledAt = startsAt.addingTimeInterval(Double(fixtureList[index].round - 1) * 20 * 60)
                fixtureList[index].place = options.court
            }
        }
        let draft = TournamentDraft(squadID: squadID, name: cleaned, format: format, rules: rules, entrants: entrants,
                                    fixtures: fixtureList, settings: settings)
        var id: UUID?
        await run { id = try await $0.createTournament(draft) }
        await refreshTournaments()
        return id
    }

    func schedule(_ fixture: FixtureRow, at date: Date?, court: CourtTag?) async {
        await run { try await $0.scheduleFixture(fixture.id, at: date, court: court) }
        await refreshTournaments()
    }

    /// Adds whatever knockout matches are ready, in every active
    /// tournament. Safe to run on every phone at once.
    func advanceTournaments() async {
        guard let backend else { return }
        var added = false
        for tournament in tournaments where tournament.status == .active {
            guard let state = bracket(of: tournament) else { continue }
            let rows = state.fixturesToAdd.map { FixtureRow($0, tournamentID: tournament.id) }
            guard !rows.isEmpty else { continue }
            do {
                try await backend.addFixtures(rows)
                added = true
            } catch {
                report(error)
            }
        }
        if added { await refreshTournaments() }
    }

    /// Whether "Next round" makes sense right now.
    func canStartNextRound(of tournament: TournamentRow) -> Bool {
        guard tournament.status == .active else { return false }
        let rows = fixtures(of: tournament)
        guard let last = rows.map(\.round).max() else { return false }
        let scores = scores(of: tournament)
        let done = rows.filter { $0.round == last }.allSatisfy { scores[$0.id] != nil }
        switch tournament.format {
        case .kingOfTheCourt: return done
        case .mexicano: return done && last < (tournament.settings?.rounds ?? 6)
        default: return false
        }
    }

    /// King of the Court and Mexicano: the next round once every court has
    /// a result.
    func startNextRound(of tournament: TournamentRow) async {
        let rows = fixtures(of: tournament)
        guard let last = rows.map(\.round).max() else { return }
        let scores = scores(of: tournament)
        var next: [Fixture]?
        switch tournament.format {
        case .kingOfTheCourt:
            let round = rows.filter { $0.round == last }.map(\.fixture)
            let playing = Set(round.flatMap(\.players))
            let bench = entrants(of: tournament).map(PlayerID.init(rawValue:)).filter { !playing.contains($0) }
            next = KingOfTheCourt.nextRound(after: round, scores: scores, bench: bench, doubles: tournament.rules.isDoubles)?.fixtures
        case .mexicano:
            next = Mexicano.nextRound(players: units(of: tournament).flatMap { $0 }, fixtures: rows.map(\.fixture),
                                      scores: scores, courts: tournament.settings?.courts)
        default:
            return
        }
        guard var next else {
            notice = "Every court needs a result first."
            return
        }
        for index in next.indices { next[index].slot = next[index].court - 1 }
        let newRows = next.map { FixtureRow($0, tournamentID: tournament.id) }
        await run { try await $0.addFixtures(newRows) }
        await refreshTournaments()
    }

    /// Who won, once it's decided.
    func champions(of tournament: TournamentRow) -> [PlayerID]? {
        switch tournament.format {
        case .singleElimination, .doubleElimination, .pools:
            return bracket(of: tournament)?.champion
        case .mexicano:
            let rounds = Set(fixtures(of: tournament).map(\.round)).count
            guard rounds >= (tournament.settings?.rounds ?? 6) else { return nil }
            fallthrough
        default:
            let league = fixtures(of: tournament).map(\.fixture)
            return Standings.champions(standings(of: tournament), fixtures: league, scores: scores(of: tournament))
        }
    }

    func complete(_ tournament: TournamentRow) async -> [PlayerID]? {
        guard let champions = champions(of: tournament) else {
            notice = "Finish every match first."
            return nil
        }
        guard await run({ try await $0.completeTournament(tournament.id, champions: champions.map(\.rawValue)) }) else { return nil }
        await refreshTournaments()
        await refreshTrophies()
        if let userID, champions.contains(PlayerID(rawValue: userID)) {
            offerTrophyCard(tournamentName: tournament.name)
        }
        return champions
    }

    /// A read-only web page for a match or tournament anyone can open.
    func shareLink(_ kind: ShareLinkKind, target: UUID) async -> URL? {
        guard let site = backend?.config.site else {
            notice = "Set SITE_URL in Secrets.plist to share live links."
            return nil
        }
        var token: String?
        await run { token = try await $0.createShareLink(kind, target: target) }
        return token.map { ShareLinks.url(token: $0, site: site) }
    }

    /// The next thing on the calendar for me: accepted call outs and
    /// scheduled tournament matches, soonest first.
    var upcoming: [UpcomingMatch] {
        guard let userID else { return [] }
        var list: [UpcomingMatch] = []
        for row in activeCallOuts where row.status == .accepted {
            list.append(UpcomingMatch(id: row.id, date: row.proposedAt, title: lineup(for: row).name(of: .a, separator: " & ") + " vs " + lineup(for: row).name(of: .b, separator: " & "),
                                      subtitle: "Call out · \(row.rules.summary)", court: row.court, kind: .callOut(row)))
        }
        for tournament in tournaments where tournament.status == .active {
            for fixture in fixtures(of: tournament) where fixture.matchID == nil && (fixture.teamA + fixture.teamB).contains(where: { playerUser($0) == userID }) {
                let names = { (ids: [UUID]) in ids.map { self.firstName(of: $0) }.joined(separator: " & ") }
                list.append(UpcomingMatch(id: fixture.id, date: fixture.scheduledAt, title: "\(names(fixture.teamA)) vs \(names(fixture.teamB))",
                                          subtitle: "\(tournament.name) · Round \(fixture.round)", court: fixture.court, kind: .fixture(tournament, fixture)))
            }
        }
        return list.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
    }
}

extension FixtureStage {
    /// Display order: pools, then the winners' side, losers' side, finals.
    var order: Int {
        switch self {
        case .main: return 0
        case .pool: return 0
        case .winners: return 1
        case .losers: return 2
        case .final: return 3
        case .reset: return 4
        }
    }
}

struct UpcomingMatch: Identifiable {
    enum Kind {
        case callOut(CallOutRow)
        case fixture(TournamentRow, FixtureRow)
    }

    let id: UUID
    let date: Date?
    let title: String
    let subtitle: String
    let court: CourtTag?
    let kind: Kind
}
