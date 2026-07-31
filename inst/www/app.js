(function () {
  "use strict";

  const messagesEl = document.getElementById("messages");
  const inputEl = document.getElementById("input");
  const sendBtn = document.getElementById("send");
  const modelBadge = document.getElementById("model-badge");
  const debugBtn = document.getElementById("debug-btn");
  const logPanel = document.getElementById("log-panel");
  const logOutput = document.getElementById("log-output");
  const logClearBtn = document.getElementById("log-clear");
  const logCloseBtn = document.getElementById("log-close");
  let logVisible = false;

  let history = []; // [{role, content}]
  let ws = null;
  let currentMsg = null; // {div, bubble, think, thinkPre, resp, typing}

  function connect() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    clientLog("Connecting WebSocket to " + proto + "://" + location.host + "/");
    ws = new WebSocket(`${proto}://${location.host}/`);
    ws.onopen = function () { clientLog("WebSocket opened"); fetchConfig(); };
    ws.onmessage = function (ev) { handleMessage(ev.data); };
    ws.onerror = function (e) { clientLog("WebSocket error: " + (e.message || "unknown")); };
    ws.onclose = function () {
      clientLog("WebSocket closed");
      if (currentBubble) finalizeStream(null);
    };
  }

  function clientLog(msg) {
    if (!logOutput) return;
    const line = el("span", "log-line");
    const lvl = el("span", "lvl info");
    lvl.textContent = "[client]".padEnd(9);
    line.appendChild(lvl);
    line.appendChild(textNode(msg));
    logOutput.appendChild(line);
    if (logVisible) logOutput.scrollTop = logOutput.scrollHeight;
  }

  function fetchConfig() {
    fetch("/config").then(r => r.json()).then(cfg => {
      modelBadge.textContent = cfg.model || "";
    }).catch(() => {});
  }

  function handleMessage(raw) {
    let msg;
    try { msg = JSON.parse(raw); } catch (e) { clientLog("Bad JSON from server: " + raw); return; }
    clientLog("<- " + msg.type + " (" + (msg.text ? msg.text.length : 0) + " chars)");
    if (msg.type === "delta") {
      appendDelta(msg.text);
    } else if (msg.type === "thinking") {
      appendThinking(msg.text);
    } else if (msg.type === "done") {
      finalizeStream(msg.text);
    } else if (msg.type === "error") {
      if (currentMsg) {
        currentMsg.bubble.appendChild(errorEl(msg.message));
        finalizeStream(null);
      } else {
        const div = el("div", "msg assistant");
        div.appendChild(el("div", "bubble error").appendChild(textNode(msg.message)));
        messagesEl.appendChild(div);
      }
    } else if (msg.type === "tool_result") {
      renderToolResult(msg);
    }
  }

  function ensureMsg() {
    if (currentMsg) return currentMsg;
    const div = el("div", "msg assistant");
    const bubble = el("div", "bubble");
    const typing = el("span", "typing");
    typing.appendChild(textNode("Working..."));
    bubble.appendChild(typing);
    div.appendChild(bubble);
    messagesEl.appendChild(div);
    currentMsg = { div: div, bubble: bubble, think: null, thinkPre: null, resp: null, typing: typing };
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return currentMsg;
  }

  function removeTyping(m) {
    if (m.typing) { m.typing.remove(); m.typing = null; }
  }

  function appendThinking(text) {
    const m = ensureMsg();
    if (!m.think) {
      m.think = el("details", "thinking");
      m.think.appendChild(el("summary").appendChild(textNode("Thinking")));
      m.thinkPre = el("pre", "think");
      m.think.appendChild(m.thinkPre);
      m.bubble.insertBefore(m.think, m.bubble.firstChild);
    }
    m.thinkPre.textContent += text;
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  function appendDelta(text) {
    const m = ensureMsg();
    if (!m.resp) {
      removeTyping(m);
      m.resp = el("pre", "raw");
      m.bubble.appendChild(m.resp);
    }
    m.resp.textContent += text;
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  function finalizeStream(text) {
    if (currentMsg) {
      const m = currentMsg;
      let content;
      if (text != null) content = text;
      else if (m.resp) content = m.resp.textContent;
      else content = "";
      if (m.resp) m.resp.remove();
      const actionsAnchor = m.bubble.querySelector(".actions");
      if (content && content.trim()) {
        renderMarkdown(content).forEach(n => m.bubble.insertBefore(n, actionsAnchor));
        if (text != null && text.trim()) history.push({ role: "assistant", content: text.trim() });
      } else if (m.thinkPre && m.thinkPre.textContent.trim()) {
        history.push({ role: "assistant", content: m.thinkPre.textContent.trim() });
      }
      if (m.think) m.think.open = false; // collapse reasoning once finished
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }
    currentMsg = null;
  }

  function renderToolResult(msg) {
    const div = el("div", "msg assistant");
    const bubble = el("div", "bubble");
    bubble.appendChild(el("strong").appendChild(textNode("Tool " + msg.tool)));
    bubble.appendChild(el("pre").appendChild(textNode(JSON.stringify(msg.result, null, 2))));
    div.appendChild(bubble);
    messagesEl.appendChild(div);
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  function send() {
    const text = inputEl.value.trim();
    if (!text) return;
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      clientLog("Send failed: WebSocket not open (state " + (ws ? ws.readyState : "null") + ")");
      return;
    }
    history.push({ role: "user", content: text });
    inputEl.value = "";
    renderUserMessage(text);
    clientLog("-> chat sent (" + text.length + " chars)");
    ws.send(JSON.stringify({ type: "chat", messages: history }));
  }

  function renderUserMessage(text) {
    const div = el("div", "msg user");
    div.appendChild(el("div", "bubble").appendChild(textNode(text)));
    messagesEl.appendChild(div);
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  function insertCode(code) {
    ws.send(JSON.stringify({ type: "insert", code: code }));
  }
  function runCode(code) {
    ws.send(JSON.stringify({ type: "run", code: code }));
  }

  function renderMarkdown(text) {
    const nodes = [];
    const blocks = text.split(/(```[\s\S]*?```)/g);
    blocks.forEach(block => {
      if (/^```/.test(block.trim())) {
        const inner = block.replace(/^```(.*?)\n?/, "").replace(/```$/, "").replace(/\n$/, "");
        const lang = (block.match(/^```([\w+-]*)/) || [])[1] || "";
        const pre = el("pre");
        pre.appendChild(el("code").appendChild(textNode(inner)));
        if (lang) pre.setAttribute("data-lang", lang);
        nodes.push(pre);
        if (inner.trim()) {
          const actions = el("div", "actions");
          const ins = el("button").appendChild(textNode("Insert"));
          const run = el("button", "secondary").appendChild(textNode("Run"));
          ins.onclick = () => insertCode(inner);
          run.onclick = () => runCode(inner);
          actions.appendChild(ins);
          actions.appendChild(run);
          nodes.push(actions);
        }
      } else if (block.trim()) {
        nodes.push(paragraphify(block));
      }
    });
    return nodes;
  }

  function paragraphify(text) {
    const p = el("p");
    // minimal inline markdown
    text.split(/\n{2,}/).forEach((para, i) => {
      if (i > 0) p.appendChild(el("br"));
      p.appendChild(textNode(para));
    });
    return p;
  }

  function errorEl(msg) {
    return el("div", "error").appendChild(textNode(msg));
  }

  function el(tag, cls) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    return e;
  }
  function textNode(t) { return document.createTextNode(t); }

  function toggleLog() {
    logVisible = !logVisible;
    logPanel.hidden = !logVisible;
    if (logVisible) fetchLog();
  }

  function clearLog() {
    fetch("/log/clear").then(() => { logOutput.textContent = ""; }).catch(() => {});
  }

  function fetchLog() {
    fetch("/log").then(r => r.json()).then(entries => {
      logOutput.innerHTML = "";
      (entries || []).forEach(e => {
        const line = el("span", "log-line");
        const lvl = el("span", "lvl " + (e.level || "info"));
        lvl.textContent = ("[" + (e.level || "info") + "]").padEnd(7);
        line.appendChild(lvl);
        line.appendChild(textNode((e.time || "") + "  " + (e.msg || "")));
        logOutput.appendChild(line);
      });
      logOutput.scrollTop = logOutput.scrollHeight;
    }).catch(err => {
      logOutput.textContent = "Failed to load log: " + err;
    });
  }

  sendBtn.onclick = send;
  inputEl.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && e.shiftKey) { e.preventDefault(); send(); }
  });
  debugBtn.onclick = toggleLog;
  logCloseBtn.onclick = toggleLog;
  logClearBtn.onclick = clearLog;

  connect();
})();
