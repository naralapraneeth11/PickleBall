// The live scoreboard: a read-only view of one match or tournament behind a
// share link (https://<site>/live/?t=<token>). It calls public_scoreboard(),
// which returns first names and scores only, and polls while things move.
(function () {
  "use strict";

  var token = new URLSearchParams(location.search).get("t") || "";
  var app;
  var timer;
  var last;
  var failures = 0;

  function t(key) { return window.PB ? window.PB.t(key) : key; }

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function message(key) {
    app.innerHTML = "";
    var p = el("p", "muted center", t(key));
    app.appendChild(p);
  }

  function fetchBoard() {
    var cfg = (window.PB && window.PB.config()) || {};
    if (!cfg.supabaseUrl || !cfg.supabaseAnonKey) return Promise.reject(new Error("not configured"));
    return fetch(cfg.supabaseUrl.replace(/\/$/, "") + "/rest/v1/rpc/public_scoreboard", {
      method: "POST",
      headers: {
        "apikey": cfg.supabaseAnonKey,
        "Authorization": "Bearer " + cfg.supabaseAnonKey,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ tok: token })
    }).then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    });
  }

  function schedule(board) {
    clearTimeout(timer);
    var delay = 60000;
    if (board && board.kind === "match" && board.live) delay = 4000;
    else if (board && board.kind === "tournament" && board.status === "active") delay = 20000;
    else if (!board) delay = Math.min(60000, 5000 * Math.pow(2, failures));
    if (document.hidden) delay = Math.max(delay, 30000);
    timer = setTimeout(load, delay);
  }

  function load() {
    fetchBoard().then(function (board) {
      failures = 0;
      last = board;
      render(board);
      schedule(board);
    }).catch(function () {
      failures += 1;
      if (!last) message("live.offline");
      schedule(null);
    });
  }

  function render(board) {
    if (!board) { message("live.missing"); return; }
    if (board.gone) { message("live.ended"); return; }
    app.innerHTML = "";
    if (board.kind === "match") renderMatch(board);
    else renderTournament(board);
  }

  function sportName(sport) { return t(sport === "padel" ? "live.padel" : "live.pickleball"); }

  function names(team) {
    return (team || []).map(function (p) { return typeof p === "string" ? p : p.name; }).join(" & ");
  }

  function unitLabel(unit) {
    if (!unit || !unit.score) return "";
    var label = unit.score.a + "–" + unit.score.b;
    if (unit.tiebreak) label += " (" + Math.min(unit.tiebreak.a, unit.tiebreak.b) + ")";
    return label;
  }

  function renderMatch(board) {
    var card = el("section", "board");
    var meta = el("div", "meta");
    var left = el("span");
    if (board.live) {
      left.appendChild(el("span", "live-dot"));
      left.appendChild(document.createTextNode(t("live.live")));
    } else {
      left.textContent = board.status === "pending" ? t("live.pending") : t("live.final");
    }
    meta.appendChild(left);
    meta.appendChild(el("span", null, sportName(board.sport)));
    card.appendChild(meta);

    var teams = board.teams || [[], []];
    if (board.live) {
      var score = board.score || {};
      var points = score.points || { a: "0", b: "0" };
      var games = score.games || { a: 0, b: 0 };
      var sets = score.sets || { a: 0, b: 0 };
      ["a", "b"].forEach(function (side, index) {
        var row = el("div", "side" + (score.winner === index ? " won" : ""));
        var who = el("div");
        var name = el("div", "name", names(teams[index]));
        if (score.servingTeam === index && score.winner === undefined) {
          var dot = el("span", "serve"); dot.setAttribute("aria-label", "serving");
          name.appendChild(dot);
        }
        who.appendChild(name);
        var detail = board.sport === "padel" ? sets[side] + " · " + games[side] : String(games[side]);
        who.appendChild(el("div", "sets", detail));
        row.appendChild(who);
        row.appendChild(el("div", "points", points[side]));
        card.appendChild(row);
      });
      card.appendChild(el("div", "call", score.pressure || score.call || score.history || ""));
      if (score.updatedAt) {
        var updated = new Date(score.updatedAt);
        if (!isNaN(updated)) {
          card.appendChild(el("div", "call small", t("live.updated") + " " + updated.toLocaleTimeString(window.PB.lang(), { hour: "numeric", minute: "2-digit" })));
        }
      }
    } else {
      var units = board.units || [];
      ["a", "b"].forEach(function (side, index) {
        var row = el("div", "side" + (board.winner === index ? " won" : ""));
        var who = el("div");
        who.appendChild(el("div", "name", names(teams[index])));
        who.appendChild(el("div", "sets", units.map(function (u) { return u.score ? u.score[side] : ""; }).join("  ")));
        row.appendChild(who);
        row.appendChild(el("div", "points", (board.match_score || [0, 0])[index]));
        card.appendChild(row);
      });
    }
    app.appendChild(card);
  }

  // Tournaments: champion, standings (league formats) and every match.
  function renderTournament(board) {
    var head = el("section", "card");
    head.appendChild(el("span", "pill", t("format." + board.format)));
    head.appendChild(el("h1", null, board.name));
    head.appendChild(el("p", "muted", sportName(board.sport)));
    if (board.champions && board.champions.length) {
      head.appendChild(el("div", "champ", "🏆 " + board.champions.join(" & ")));
    }
    app.appendChild(head);

    var fixtures = board.fixtures || [];
    var bracket = board.format === "single_elimination" || board.format === "double_elimination";
    if (!bracket && board.format !== "pools") {
      app.appendChild(standings(board, fixtures));
    }

    var groups = {};
    var order = [];
    fixtures.forEach(function (f) {
      var key = groupKey(f);
      if (!groups[key]) { groups[key] = []; order.push(key); }
      groups[key].push(f);
    });
    order.forEach(function (key) {
      var section = el("section", "card");
      section.appendChild(el("h2", null, key));
      groups[key].forEach(function (f) { section.appendChild(fixtureRow(f)); });
      app.appendChild(document.createElement("br"));
      app.appendChild(section);
    });
  }

  function groupKey(f) {
    switch (f.stage) {
      case "pool": return t("live.pool") + " " + String.fromCharCode(65 + (f.pool || 0));
      case "winners": return t("live.winners") + " · " + t("live.round") + " " + f.round;
      case "losers": return t("live.losers") + " · " + t("live.round") + " " + f.round;
      case "final": return t("live.final_stage");
      case "reset": return t("live.reset");
      default: return t("live.round") + " " + f.round;
    }
  }

  function points(f, side) {
    return (f.units || []).reduce(function (sum, u) {
      var s = u.isSuperTiebreak && u.tiebreak ? u.tiebreak : u.score;
      return sum + (s ? s[side] : 0);
    }, 0);
  }

  function fixtureRow(f) {
    var row = el("div", "fixture");
    var played = f.winner === 0 || f.winner === 1;
    row.appendChild(el("div", played ? (f.winner === 0 ? "w" : "l") : null, names(f.team_a)));
    row.appendChild(el("div", "n " + (played && f.winner === 0 ? "w" : "l"), played ? (f.units || []).map(function (u) { return u.score ? u.score.a : ""; }).join(" ") : ""));
    row.appendChild(el("div", played ? (f.winner === 1 ? "w" : "l") : null, names(f.team_b)));
    row.appendChild(el("div", "n " + (played && f.winner === 1 ? "w" : "l"), played ? (f.units || []).map(function (u) { return u.score ? u.score.b : ""; }).join(" ") : (f.scheduled_at ? new Date(f.scheduled_at).toLocaleString(window.PB.lang(), { weekday: "short", hour: "numeric", minute: "2-digit" }) : t("live.upcoming"))));
    return row;
  }

  // Wins (or points, for Americano and Mexicano) per player or pair.
  function standings(board, fixtures) {
    var byPoints = board.format === "americano" || board.format === "mexicano";
    var individual = byPoints || board.format === "king_of_court";
    var rows = {};
    function entry(team) {
      var list = individual ? team.map(function (p) { return [p]; }) : [team];
      return list.map(function (members) {
        var key = members.map(function (p) { return p.id; }).sort().join("+");
        if (!rows[key]) rows[key] = { name: names(members), p: 0, w: 0, l: 0, pf: 0, pa: 0 };
        return rows[key];
      });
    }
    fixtures.forEach(function (f) {
      var a = entry(f.team_a || []), b = entry(f.team_b || []);
      if (f.winner !== 0 && f.winner !== 1) return;
      var pa = points(f, "a"), pb = points(f, "b");
      a.forEach(function (r) { r.p++; r.pf += pa; r.pa += pb; if (f.winner === 0) r.w++; else r.l++; });
      b.forEach(function (r) { r.p++; r.pf += pb; r.pa += pa; if (f.winner === 1) r.w++; else r.l++; });
    });
    var list = Object.keys(rows).map(function (k) { return rows[k]; });
    list.sort(function (x, y) {
      if (byPoints && x.pf !== y.pf) return y.pf - x.pf;
      if (x.w !== y.w) return y.w - x.w;
      return (y.pf - y.pa) - (x.pf - x.pa);
    });

    var section = el("section", "card");
    section.appendChild(el("h2", null, t("live.standings")));
    var table = el("table", "table");
    var head = el("tr");
    ["#", "", t("live.played"), t("live.won"), t("live.lost"), byPoints ? t("live.points") : "±"].forEach(function (h) { head.appendChild(el("th", null, h)); });
    table.appendChild(head);
    list.forEach(function (r, i) {
      var tr = el("tr");
      [i + 1, r.name, r.p, r.w, r.l, byPoints ? r.pf : (r.pf - r.pa > 0 ? "+" : "") + (r.pf - r.pa)].forEach(function (v) { tr.appendChild(el("td", null, v)); });
      table.appendChild(tr);
    });
    section.appendChild(table);
    var wrap = document.createElement("div");
    wrap.appendChild(document.createElement("br"));
    wrap.appendChild(section);
    return wrap;
  }

  document.addEventListener("DOMContentLoaded", function () {
    app = document.getElementById("app");
    if (!/^[0-9a-f]{24}$/.test(token)) { message("live.missing"); return; }
    load();
    document.addEventListener("visibilitychange", function () { if (!document.hidden) load(); });
    document.addEventListener("languagechange", function () { if (last) render(last); });
  });
})();
