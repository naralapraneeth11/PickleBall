//
//  Social+Tournaments.swift
//  PickleBall
//
//  Squad tournaments: create from a squad in one tap (plus guests), keep
//  the schedule, score any match, add King of the Court rounds, crown the
//  champion. Standings are computed on the phone from confirmed results.
//

import Foundation
import CourtKit
import CourtNet

extension Social {
    func entrants(of tournament: TournamentRow) -> [UUID] {
        entrants.filter { $0.tournamentID == tournament.id }.map(\.playerID)
    }

    func fixtures(of tournament: TournamentRow) -> [FixtureRow] {
        fixtures.filter { $0.tournamentID == tournament.id }.sorted { ($0.round, $0.courtNumber) < ($1.round, $1.courtNumber) }
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
            var points = TeamPair(a: record.pointsA, b: record.pointsB)
            var winner = record.winner
            if tournament.format != .americano {
                points = TeamPair(a: record.matchScoreA, b: record.matchScoreB)
                if points.a == 0 && points.b == 0 { points = TeamPair(a: record.pointsA, b: record.pointsB) }
            }
            if !recordAIsFixtureA {
                points = points.swapped
                winner = winner?.opponent
            }
            scores[fixture.id] = FixtureScore(score: points, winner: winner)
        }
        return scores
    }

    func standings(of tournament: TournamentRow) -> [StandingRow] {
        let fixtureRows = fixtures(of: tournament)
        let entrantIDs = entrants(of: tournament)
        let units: [[PlayerID]]
        if tournament.format == .roundRobin, tournament.rules.isDoubles {
            // Fixed pairs: the teams as scheduled.
            var pairs: [[PlayerID]] = []
            for fixture in fixtureRows {
                for team in [fixture.teamA, fixture.teamB] {
                    let pair = team.map(PlayerID.init(rawValue:))
                    if !pairs.contains(where: { Set($0) == Set(pair) }) { pairs.append(pair) }
                }
            }
            units = pairs
        } else {
            units = entrantIDs.map { [PlayerID(rawValue: $0)] }
        }
        return Standings.compute(format: tournament.format, entrants: units, fixtures: fixtureRows.map(\.fixture), scores: scores(of: tournament))
    }

    func createTournament(squadID: UUID, name: String, format: TournamentFormat, rules: MatchRules,
                          entrants: [PlayerRef], pairs: [[PlayerRef]]?, courts: Int, startsAt: Date?, court: CourtTag?) async -> UUID? {
        guard let cleaned = ContentFilter.standard.cleaned(name.trimmingCharacters(in: .whitespacesAndNewlines)), !cleaned.isEmpty else {
            notice = "Pick a different name."
            return nil
        }
        var fixtureList: [Fixture]
        let ids = entrants.map(\.id)
        switch format {
        case .roundRobin:
            let units = pairs?.map { $0.map(\.id) } ?? ids.map { [$0] }
            fixtureList = RoundRobin.schedule(units, courts: courts)
        case .kingOfTheCourt:
            fixtureList = KingOfTheCourt.firstRound(ids.shuffled(), doubles: rules.isDoubles).fixtures
        case .americano:
            fixtureList = Americano.schedule(ids.shuffled(), courts: courts)
        }
        // Spread the schedule: each round 20 minutes after the last.
        if let startsAt {
            for index in fixtureList.indices {
                fixtureList[index].scheduledAt = startsAt.addingTimeInterval(Double(fixtureList[index].round - 1) * 20 * 60)
                fixtureList[index].place = court
            }
        }
        let draft = TournamentDraft(squadID: squadID, name: cleaned, format: format, rules: rules, entrants: entrants, fixtures: fixtureList)
        var id: UUID?
        await run { id = try await $0.createTournament(draft) }
        await refreshTournaments()
        return id
    }

    func schedule(_ fixture: FixtureRow, at date: Date?, court: CourtTag?) async {
        await run { try await $0.scheduleFixture(fixture.id, at: date, court: court) }
        await refreshTournaments()
    }

    /// King of the Court: the next round once every court has a result.
    func startNextRound(of tournament: TournamentRow) async {
        let rows = fixtures(of: tournament)
        guard let last = rows.map(\.round).max() else { return }
        let round = rows.filter { $0.round == last }.map(\.fixture)
        let playing = Set(round.flatMap(\.players))
        let bench = entrants(of: tournament).map(PlayerID.init(rawValue:)).filter { !playing.contains($0) }
        guard let next = KingOfTheCourt.nextRound(after: round, scores: scores(of: tournament), bench: bench, doubles: tournament.rules.isDoubles) else {
            notice = "Every court needs a result first."
            return
        }
        let newRows = next.fixtures.map { FixtureRow($0, tournamentID: tournament.id) }
        await run { try await $0.addFixtures(newRows) }
        await refreshTournaments()
    }

    func complete(_ tournament: TournamentRow) async -> [PlayerID]? {
        let rows = standings(of: tournament)
        let fixtureRows = fixtures(of: tournament).map(\.fixture)
        guard let champions = Standings.champions(rows, fixtures: fixtureRows, scores: scores(of: tournament)) else {
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
