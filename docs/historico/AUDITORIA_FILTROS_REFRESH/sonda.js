/* Sonda da auditoria de filtros e recargas. SÓ LEITURA: não altera a página nem dados.
   Uso pelo javascript_tool (colar o arquivo inteiro e, no fim, a chamada desejada):
     antes da operação:  <arquivo> ; __sonda.instalar("A1-L07")
     depois:             <arquivo> ; __sonda.ler()
   Se a página recarregou, as funções somem; colar de novo e chamar ler(): o estado
   "antes" e os eventos ficam no sessionStorage desta aba. */
(function () {
  var K = "__sonda_auditoria";
  function guardar(o) { try { sessionStorage.setItem(K, JSON.stringify(o)); } catch (e) {} }
  function carregar() { try { return JSON.parse(sessionStorage.getItem(K) || "null"); } catch (e) { return null; } }
  function ehEscrita(f) {
    if (!f) return false;
    var m = (f.getAttribute("method") || "get").toLowerCase();
    return m === "post" || f.hasAttribute("hx-post") || f.hasAttribute("hx-put") || f.hasAttribute("hx-patch") || f.hasAttribute("hx-delete");
  }
  function chave(el) {
    var f = el.form, onde = f ? (f.id || f.getAttribute("hx-get") || f.getAttribute("action") || "form") : "solto";
    return onde.split("?")[0] + "|" + el.name;
  }
  function valor(el) {
    if (el.type === "checkbox" || el.type === "radio") return el.checked ? (el.value || "on") : null;
    if (el.multiple) return Array.prototype.filter.call(el.options, function (o) { return o.selected; }).map(function (o) { return o.value; }).join(",");
    return el.value;
  }
  function foto() {
    var filtros = {};
    document.querySelectorAll("input[name],select[name],textarea[name]").forEach(function (el) {
      if (/csrf/i.test(el.name) || el.type === "password" || el.type === "file" || el.disabled) return;
      if (!el.hasAttribute("data-table-filter") && ehEscrita(el.form)) return;
      var k = chave(el), v = valor(el);
      if (el.type === "checkbox" || el.type === "radio") { if (v === null) return; filtros[k] = (filtros[k] ? filtros[k] + "," : "") + v; }
      else filtros[k] = v;
    });
    var a = document.activeElement;
    return {
      url: location.pathname + location.search,
      filtros: filtros,
      scrollY: Math.round(window.scrollY),
      foco: a && a !== document.body ? (a.tagName + (a.id ? "#" + a.id : "") + (a.name ? "[" + a.name + "]" : "")) : "",
      abertos: document.querySelectorAll("details[open],[aria-expanded=true]").length,
      nav: (performance.getEntriesByType("navigation")[0] || {}).type || ""
    };
  }
  function registrar(tipo, ev) {
    var st = carregar(); if (!st) return;
    var d = ev.detail || {}, x = d.xhr, cfg = d.requestConfig || {}, alvo = d.target || ev.target;
    var r = { t: tipo, ms: Date.now() - st.inicio };
    if (cfg.verb || (d.verb)) r.verbo = (cfg.verb || d.verb).toUpperCase();
    if (cfg.path || d.path) r.path = String(cfg.path || d.path).slice(0, 160);
    if (alvo && alvo.id) r.alvo = alvo.id; else if (alvo && alvo.tagName) r.alvo = alvo.tagName;
    if (x && x.readyState === 4) {
      r.status = x.status;
      ["HX-Redirect", "HX-Refresh", "HX-Location", "HX-Trigger", "HX-Push-Url", "HX-Replace-Url", "HX-Retarget", "HX-Reswap"].forEach(function (h) {
        var v = x.getResponseHeader(h); if (v) r[h] = v.slice(0, 120);
      });
      if (x.responseURL && x.responseURL.indexOf(cfg.path || "\u0000") < 0) r.seguiu = x.responseURL.replace(location.origin, "").slice(0, 160);
    }
    if (d.elt && d.elt.getAttribute) { var sw = d.elt.getAttribute("hx-swap"); if (sw) r.swap = sw; }
    st.eventos.push(r); if (st.eventos.length > 60) st.eventos.shift();
    guardar(st);
  }
  function ouvir() {
    if (window.__sonda_ouvindo) return;
    window.__sonda_ouvindo = true;
    ["htmx:beforeRequest", "htmx:afterRequest", "htmx:afterSwap", "htmx:oobAfterSwap", "htmx:responseError",
     "htmx:sendError", "htmx:swapError", "htmx:pushedIntoHistory", "htmx:replacedInHistory", "htmx:historyRestore", "htmx:abort"]
      .forEach(function (n) { document.addEventListener(n, function (ev) { registrar(n.slice(5), ev); }, true); });
    window.addEventListener("beforeunload", function () { var st = carregar(); if (st) { st.eventos.push({ t: "UNLOAD", ms: Date.now() - st.inicio }); guardar(st); } });
  }
  window.__sonda = {
    instalar: function (rotulo) {
      var marca = "M" + Date.now();
      window.__sonda_marca = marca;
      guardar({ rotulo: rotulo || "", marca: marca, inicio: Date.now(), antes: foto(), eventos: [] });
      ouvir();
      return "instalada " + marca;
    },
    ler: function () {
      var st = carregar(); if (!st) return { erro: "sonda não instalada nesta aba" };
      ouvir();
      var a = st.antes, d = foto(), dif = [];
      Object.keys(a.filtros).forEach(function (k) { if (a.filtros[k] !== d.filtros[k]) dif.push([k, a.filtros[k], d.filtros[k] === undefined ? "(sumiu)" : d.filtros[k]]); });
      Object.keys(d.filtros).forEach(function (k) { if (!(k in a.filtros)) dif.push([k, "(não havia)", d.filtros[k]]); });
      var pa = new URLSearchParams(a.url.split("?")[1] || ""), pd = new URLSearchParams(d.url.split("?")[1] || ""), url_perdeu = [];
      pa.forEach(function (v, k) { if (pd.get(k) !== v) url_perdeu.push(k + "=" + v + " -> " + (pd.get(k) === null ? "(sumiu)" : pd.get(k))); });
      var trocas = st.eventos.filter(function (e) { return e.t === "afterSwap" || e.t === "oobAfterSwap"; }).map(function (e) { return e.alvo; });
      return {
        rotulo: st.rotulo,
        recarregou: window.__sonda_marca !== st.marca,
        nav_tipo: d.nav,
        url: a.url === d.url ? "igual" : [a.url, d.url],
        url_perdeu: url_perdeu,
        filtros_mudaram: dif,
        scroll: [a.scrollY, d.scrollY],
        foco: [a.foco, d.foco],
        abertos: [a.abertos, d.abertos],
        trocas: trocas,
        eventos: st.eventos.filter(function (e) { return e.t !== "beforeRequest" && e.t !== "afterSwap"; })
      };
    }
  };
})();
