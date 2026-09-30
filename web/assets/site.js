// PickleBall web: translations, the "Get the app" banner and the language
// picker. Pages mark text with data-i18n="key"; this fills it in.
(function () {
  "use strict";

  var STRINGS = {
    en: {
      "nav.language": "Language",
      "footer.privacy": "Privacy",
      "footer.terms": "Terms",
      "footer.support": "Support",
      "banner.title": "PickleBall",
      "banner.ios": "Score, confirm, take the belt.",
      "banner.android": "On iPhone now. Android is on the way.",
      "banner.get": "Get the app",
      "banner.open": "Open",
      "banner.close": "Close",
      "home.title": "Your games. Your crew. The belt.",
      "home.lead": "Score pickleball and padel on your wrist or phone. Friends confirm every result, and the belt goes to whoever beats the holder.",
      "home.point1": "Belts, a squad ladder and a level for each sport, worked out from real results.",
      "home.point2": "Brackets, pools, Americano and Mexicano nights, run from your phone.",
      "home.point3": "Friends only. Nothing is ever public unless you share a live page.",
      "home.cta": "Get PickleBall",
      "invite.title": "You’ve been called up",
      "invite.lead": "Scores, belts and your squad. Beat them and take the belt.",
      "invite.open": "Open in PickleBall",
      "invite.get": "Get PickleBall",
      "invite.code": "Or enter this code in the app",
      "live.loading": "Loading the score…",
      "live.missing": "This link has expired or doesn’t exist.",
      "live.offline": "Can’t reach the scoreboard. Retrying…",
      "live.live": "Live",
      "live.final": "Final",
      "live.pending": "Waiting for confirmation",
      "live.ended": "This match has ended.",
      "live.updated": "Updated",
      "live.standings": "Standings",
      "live.schedule": "Matches",
      "live.champion": "Champion",
      "live.round": "Round",
      "live.pool": "Pool",
      "live.winners": "Winners’ bracket",
      "live.losers": "Losers’ bracket",
      "live.final_stage": "Final",
      "live.reset": "Reset final",
      "live.played": "P",
      "live.won": "W",
      "live.lost": "L",
      "live.points": "Pts",
      "live.upcoming": "Up next",
      "live.pickleball": "Pickleball",
      "live.padel": "Padel",
      "format.round_robin": "Round robin",
      "format.king_of_court": "King of the Court",
      "format.americano": "Americano",
      "format.mexicano": "Mexicano",
      "format.single_elimination": "Knockout",
      "format.double_elimination": "Double elimination",
      "format.pools": "Pools + knockout",
      "support.title": "Support",
      "support.lead": "Questions, bugs or ideas: we read everything.",
      "support.email": "Email us",
      "support.faq": "Common questions",
      "support.q1": "Why does a result need confirming?",
      "support.a1": "So every result counts. The other side taps confirm (or dispute) in the app. Belts, ladders and levels only use confirmed results.",
      "support.q2": "How is my level worked out?",
      "support.a2": "From your confirmed results in each sport: who you played, whether you won, and how close it was. Everyone starts at 3.00. It’s provisional for your first five matches.",
      "support.q3": "Who can see my matches?",
      "support.a3": "Your friends and squadmates. Nothing is public, except a live page you choose to share, which shows first names and the score only.",
      "support.q4": "How do I delete my account?",
      "support.a4": "In the app: Me → Settings → Delete account. Your profile, friends, chats, posts, photos and trophies are deleted immediately. Matches stay in your opponents’ history as “Former player”.",
      "support.q5": "How do I stop notifications?",
      "support.a5": "Me → Settings → Nudges. Turn them off, or mute just the kinds you don’t want.",
      "support.q6": "Someone is being abusive.",
      "support.a6": "Press and hold their message or post, or open their profile, and choose Report or Block. Reports are reviewed by a person."
    },
    es: {
      "nav.language": "Idioma",
      "footer.privacy": "Privacidad",
      "footer.terms": "Condiciones",
      "footer.support": "Ayuda",
      "banner.title": "PickleBall",
      "banner.ios": "Anota, confirma, llévate el cinturón.",
      "banner.android": "Ya en iPhone. Android, muy pronto.",
      "banner.get": "Descargar",
      "banner.open": "Abrir",
      "banner.close": "Cerrar",
      "home.title": "Tus partidos. Tu grupo. El cinturón.",
      "home.lead": "Anota pickleball y pádel desde el reloj o el móvil. Tus amigos confirman cada resultado y el cinturón es para quien gane al que lo lleva.",
      "home.point1": "Cinturones, una escalera de grupo y un nivel por deporte, calculados con resultados reales.",
      "home.point2": "Cuadros, grupos, noches de Americano y Mexicano, todo desde el móvil.",
      "home.point3": "Solo amigos. Nada es público salvo que compartas una página en directo.",
      "home.cta": "Descargar PickleBall",
      "invite.title": "Te han convocado",
      "invite.lead": "Resultados, cinturones y tu grupo. Gánales y llévate el cinturón.",
      "invite.open": "Abrir en PickleBall",
      "invite.get": "Descargar PickleBall",
      "invite.code": "O introduce este código en la app",
      "live.loading": "Cargando el marcador…",
      "live.missing": "Este enlace ha caducado o no existe.",
      "live.offline": "No se puede conectar con el marcador. Reintentando…",
      "live.live": "En directo",
      "live.final": "Final",
      "live.pending": "Pendiente de confirmar",
      "live.ended": "Este partido ha terminado.",
      "live.updated": "Actualizado",
      "live.standings": "Clasificación",
      "live.schedule": "Partidos",
      "live.champion": "Campeón",
      "live.round": "Ronda",
      "live.pool": "Grupo",
      "live.winners": "Cuadro de ganadores",
      "live.losers": "Cuadro de perdedores",
      "live.final_stage": "Final",
      "live.reset": "Final de desempate",
      "live.played": "PJ",
      "live.won": "G",
      "live.lost": "P",
      "live.points": "Pts",
      "live.upcoming": "Próximo",
      "live.pickleball": "Pickleball",
      "live.padel": "Pádel",
      "format.round_robin": "Liguilla",
      "format.king_of_court": "Rey de la pista",
      "format.americano": "Americano",
      "format.mexicano": "Mexicano",
      "format.single_elimination": "Eliminatoria",
      "format.double_elimination": "Doble eliminación",
      "format.pools": "Grupos + eliminatoria",
      "support.title": "Ayuda",
      "support.lead": "Dudas, errores o ideas: lo leemos todo.",
      "support.email": "Escríbenos",
      "support.faq": "Preguntas frecuentes",
      "support.q1": "¿Por qué hay que confirmar un resultado?",
      "support.a1": "Para que cada resultado cuente. El otro lado confirma (o discute) en la app. Los cinturones, la escalera y el nivel solo usan resultados confirmados.",
      "support.q2": "¿Cómo se calcula mi nivel?",
      "support.a2": "Con tus resultados confirmados en cada deporte: contra quién jugaste, si ganaste y lo ajustado que fue. Todos empiezan en 3,00. Es provisional durante tus cinco primeros partidos.",
      "support.q3": "¿Quién ve mis partidos?",
      "support.a3": "Tus amigos y compañeros de grupo. Nada es público, salvo una página en directo que decidas compartir, que solo muestra nombres de pila y el marcador.",
      "support.q4": "¿Cómo borro mi cuenta?",
      "support.a4": "En la app: Yo → Ajustes → Eliminar cuenta. Tu perfil, amigos, chats, publicaciones, fotos y trofeos se borran al momento. Los partidos siguen en el historial de tus rivales como «Exjugador».",
      "support.q5": "¿Cómo dejo de recibir notificaciones?",
      "support.a5": "Yo → Ajustes → Avisos. Desactívalos o silencia solo los tipos que no quieras.",
      "support.q6": "Alguien está siendo abusivo.",
      "support.a6": "Mantén pulsado su mensaje o publicación, o abre su perfil, y elige Denunciar o Bloquear. Una persona revisa cada denuncia."
    },
    pt: {
      "nav.language": "Idioma",
      "footer.privacy": "Privacidade",
      "footer.terms": "Termos",
      "footer.support": "Suporte",
      "banner.title": "PickleBall",
      "banner.ios": "Marque, confirme, leve o cinturão.",
      "banner.android": "Já no iPhone. Android em breve.",
      "banner.get": "Baixar o app",
      "banner.open": "Abrir",
      "banner.close": "Fechar",
      "home.title": "Seus jogos. Sua galera. O cinturão.",
      "home.lead": "Marque pickleball e padel no relógio ou no celular. Os amigos confirmam cada resultado, e o cinturão fica com quem vencer quem o tem.",
      "home.point1": "Cinturões, um ranking do grupo e um nível por esporte, calculados com resultados reais.",
      "home.point2": "Chaves, grupos, noites de Americano e Mexicano, tudo pelo celular.",
      "home.point3": "Só amigos. Nada é público, a não ser que você compartilhe uma página ao vivo.",
      "home.cta": "Baixar o PickleBall",
      "invite.title": "Você foi convocado",
      "invite.lead": "Placares, cinturões e seu grupo. Vença e leve o cinturão.",
      "invite.open": "Abrir no PickleBall",
      "invite.get": "Baixar o PickleBall",
      "invite.code": "Ou digite este código no app",
      "live.loading": "Carregando o placar…",
      "live.missing": "Este link expirou ou não existe.",
      "live.offline": "Sem conexão com o placar. Tentando de novo…",
      "live.live": "Ao vivo",
      "live.final": "Final",
      "live.pending": "Aguardando confirmação",
      "live.ended": "Esta partida terminou.",
      "live.updated": "Atualizado",
      "live.standings": "Classificação",
      "live.schedule": "Partidas",
      "live.champion": "Campeão",
      "live.round": "Rodada",
      "live.pool": "Grupo",
      "live.winners": "Chave dos vencedores",
      "live.losers": "Chave dos perdedores",
      "live.final_stage": "Final",
      "live.reset": "Final de desempate",
      "live.played": "J",
      "live.won": "V",
      "live.lost": "D",
      "live.points": "Pts",
      "live.upcoming": "A seguir",
      "live.pickleball": "Pickleball",
      "live.padel": "Padel",
      "format.round_robin": "Todos contra todos",
      "format.king_of_court": "Rei da quadra",
      "format.americano": "Americano",
      "format.mexicano": "Mexicano",
      "format.single_elimination": "Mata-mata",
      "format.double_elimination": "Dupla eliminação",
      "format.pools": "Grupos + mata-mata",
      "support.title": "Suporte",
      "support.lead": "Dúvidas, bugs ou ideias: lemos tudo.",
      "support.email": "Fale com a gente",
      "support.faq": "Perguntas frequentes",
      "support.q1": "Por que um resultado precisa ser confirmado?",
      "support.a1": "Para que todo resultado valha. O outro lado confirma (ou contesta) no app. Cinturões, ranking e nível só usam resultados confirmados.",
      "support.q2": "Como meu nível é calculado?",
      "support.a2": "Pelos seus resultados confirmados em cada esporte: contra quem jogou, se venceu e o quão apertado foi. Todo mundo começa em 3,00. É provisório nas suas cinco primeiras partidas.",
      "support.q3": "Quem vê minhas partidas?",
      "support.a3": "Seus amigos e colegas de grupo. Nada é público, exceto uma página ao vivo que você decidir compartilhar, que mostra só os primeiros nomes e o placar.",
      "support.q4": "Como excluo minha conta?",
      "support.a4": "No app: Eu → Ajustes → Excluir conta. Seu perfil, amigos, conversas, posts, fotos e troféus são apagados na hora. As partidas continuam no histórico dos adversários como “Ex-jogador”.",
      "support.q5": "Como paro as notificações?",
      "support.a5": "Eu → Ajustes → Cutucadas. Desligue ou silencie só os tipos que não quiser.",
      "support.q6": "Alguém está sendo abusivo.",
      "support.a6": "Toque e segure a mensagem ou o post, ou abra o perfil, e escolha Denunciar ou Bloquear. Uma pessoa revisa cada denúncia."
    },
    it: {
      "nav.language": "Lingua",
      "footer.privacy": "Privacy",
      "footer.terms": "Termini",
      "footer.support": "Assistenza",
      "banner.title": "PickleBall",
      "banner.ios": "Segna, conferma, prenditi la cintura.",
      "banner.android": "Già su iPhone. Android in arrivo.",
      "banner.get": "Scarica l’app",
      "banner.open": "Apri",
      "banner.close": "Chiudi",
      "home.title": "Le tue partite. Il tuo gruppo. La cintura.",
      "home.lead": "Segna pickleball e padel dal polso o dal telefono. Gli amici confermano ogni risultato e la cintura va a chi batte chi la detiene.",
      "home.point1": "Cinture, una classifica di gruppo e un livello per sport, calcolati dai risultati veri.",
      "home.point2": "Tabelloni, gironi, serate Americano e Mexicano, tutto dal telefono.",
      "home.point3": "Solo amici. Niente è pubblico, a meno che tu non condivida una pagina live.",
      "home.cta": "Scarica PickleBall",
      "invite.title": "Sei stato convocato",
      "invite.lead": "Punteggi, cinture e il tuo gruppo. Battili e prenditi la cintura.",
      "invite.open": "Apri in PickleBall",
      "invite.get": "Scarica PickleBall",
      "invite.code": "Oppure inserisci questo codice nell’app",
      "live.loading": "Caricamento del punteggio…",
      "live.missing": "Questo link è scaduto o non esiste.",
      "live.offline": "Impossibile raggiungere il tabellone. Nuovo tentativo…",
      "live.live": "In diretta",
      "live.final": "Finale",
      "live.pending": "In attesa di conferma",
      "live.ended": "Questa partita è finita.",
      "live.updated": "Aggiornato",
      "live.standings": "Classifica",
      "live.schedule": "Partite",
      "live.champion": "Campione",
      "live.round": "Turno",
      "live.pool": "Girone",
      "live.winners": "Tabellone vincenti",
      "live.losers": "Tabellone perdenti",
      "live.final_stage": "Finale",
      "live.reset": "Finale di spareggio",
      "live.played": "G",
      "live.won": "V",
      "live.lost": "P",
      "live.points": "Pti",
      "live.upcoming": "Prossima",
      "live.pickleball": "Pickleball",
      "live.padel": "Padel",
      "format.round_robin": "Girone all’italiana",
      "format.king_of_court": "Re del campo",
      "format.americano": "Americano",
      "format.mexicano": "Mexicano",
      "format.single_elimination": "Eliminazione diretta",
      "format.double_elimination": "Doppia eliminazione",
      "format.pools": "Gironi + eliminazione",
      "support.title": "Assistenza",
      "support.lead": "Domande, bug o idee: leggiamo tutto.",
      "support.email": "Scrivici",
      "support.faq": "Domande frequenti",
      "support.q1": "Perché un risultato va confermato?",
      "support.a1": "Perché ogni risultato conti. L’altra parte conferma (o contesta) nell’app. Cinture, classifica e livello usano solo risultati confermati.",
      "support.q2": "Come viene calcolato il mio livello?",
      "support.a2": "Dai tuoi risultati confermati in ogni sport: contro chi hai giocato, se hai vinto e quanto è stata combattuta. Tutti partono da 3,00. È provvisorio per le prime cinque partite.",
      "support.q3": "Chi vede le mie partite?",
      "support.a3": "I tuoi amici e compagni di gruppo. Niente è pubblico, tranne una pagina live che scegli di condividere, che mostra solo i nomi e il punteggio.",
      "support.q4": "Come elimino il mio account?",
      "support.a4": "Nell’app: Io → Impostazioni → Elimina account. Profilo, amici, chat, post, foto e trofei vengono eliminati subito. Le partite restano nello storico degli avversari come “Ex giocatore”.",
      "support.q5": "Come disattivo le notifiche?",
      "support.a5": "Io → Impostazioni → Stimoli. Disattivali o silenzia solo i tipi che non vuoi.",
      "support.q6": "Qualcuno si comporta in modo offensivo.",
      "support.a6": "Tieni premuto il messaggio o il post, oppure apri il profilo, e scegli Segnala o Blocca. Ogni segnalazione viene esaminata da una persona."
    }
  };

  var LANGS = { en: "English", es: "Español", pt: "Português", it: "Italiano" };

  function pickLanguage() {
    var fromQuery = new URLSearchParams(location.search).get("lang");
    if (fromQuery && STRINGS[fromQuery]) return fromQuery;
    try {
      var saved = localStorage.getItem("lang");
      if (saved && STRINGS[saved]) return saved;
    } catch (e) { /* storage off */ }
    var wanted = navigator.languages || [navigator.language || "en"];
    for (var i = 0; i < wanted.length; i++) {
      var code = String(wanted[i]).slice(0, 2).toLowerCase();
      if (STRINGS[code]) return code;
    }
    return "en";
  }

  var lang = pickLanguage();

  function t(key) {
    return (STRINGS[lang] && STRINGS[lang][key]) || STRINGS.en[key] || key;
  }

  function apply(root) {
    document.documentElement.lang = lang;
    (root || document).querySelectorAll("[data-i18n]").forEach(function (el) {
      el.textContent = t(el.getAttribute("data-i18n"));
    });
    (root || document).querySelectorAll("[data-i18n-label]").forEach(function (el) {
      el.setAttribute("aria-label", t(el.getAttribute("data-i18n-label")));
    });
    // Pages with one block per language (privacy, terms) show the reader's,
    // or English when there isn't one.
    var blocks = document.querySelectorAll("[data-lang-only]");
    if (blocks.length) {
      var has = Array.prototype.some.call(blocks, function (el) { return el.getAttribute("data-lang-only") === lang; });
      var show = has ? lang : "en";
      blocks.forEach(function (el) { el.hidden = el.getAttribute("data-lang-only") !== show; });
    }
  }

  function platform() {
    var ua = navigator.userAgent || "";
    if (/android/i.test(ua)) return "android";
    if (/iphone|ipad|ipod/i.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1)) return "ios";
    return "other";
  }

  function config() { return window.PICKLEBALL || {}; }

  function banner() {
    var host = document.getElementById("getapp");
    if (!host) return;
    try { if (sessionStorage.getItem("getapp.closed")) return; } catch (e) { /* ignore */ }
    var p = platform();
    var cfg = config();
    var link = p === "android" ? (cfg.androidUrl || "") : (cfg.appStoreUrl || "https://apps.apple.com/");
    host.innerHTML = "";
    var ball = document.createElement("span"); ball.className = "ball"; ball.setAttribute("aria-hidden", "true");
    var text = document.createElement("div");
    var b = document.createElement("b"); b.textContent = t("banner.title");
    var s = document.createElement("span"); s.textContent = t(p === "android" && !cfg.androidUrl ? "banner.android" : "banner.ios");
    text.appendChild(b); text.appendChild(s);
    host.appendChild(ball); host.appendChild(text);
    if (link) {
      var a = document.createElement("a"); a.href = link; a.textContent = t("banner.get"); a.rel = "noopener";
      host.appendChild(a);
    }
    var close = document.createElement("button"); close.type = "button"; close.textContent = "×";
    close.setAttribute("aria-label", t("banner.close"));
    close.addEventListener("click", function () {
      host.hidden = true;
      try { sessionStorage.setItem("getapp.closed", "1"); } catch (e) { /* ignore */ }
    });
    host.appendChild(close);
    host.hidden = false;
  }

  function languagePicker() {
    document.querySelectorAll("select.lang").forEach(function (select) {
      select.innerHTML = "";
      Object.keys(LANGS).forEach(function (code) {
        var option = document.createElement("option");
        option.value = code; option.textContent = LANGS[code];
        if (code === lang) option.selected = true;
        select.appendChild(option);
      });
      select.setAttribute("aria-label", t("nav.language"));
      select.addEventListener("change", function () {
        lang = select.value;
        try { localStorage.setItem("lang", lang); } catch (e) { /* ignore */ }
        apply();
        banner();
        document.dispatchEvent(new CustomEvent("languagechange"));
      });
    });
  }

  window.PB = { t: t, apply: apply, lang: function () { return lang; }, platform: platform, config: config };

  document.addEventListener("DOMContentLoaded", function () {
    languagePicker();
    apply();
    banner();
    document.querySelectorAll("[data-app-store]").forEach(function (a) {
      a.href = config().appStoreUrl || a.href;
    });
    document.querySelectorAll("[data-support-email]").forEach(function (a) {
      var email = config().supportEmail || "";
      a.href = "mailto:" + email;
      if (!a.textContent.trim()) a.textContent = email;
    });
  });
})();
