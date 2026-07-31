(function () {
  "use strict";

  const messagesEl = document.getElementById("messages");
  const inputEl = document.getElementById("input");
  const sendBtn = document.getElementById("send");
  const modelBadge = document.getElementById("model-badge");

  let history = []; // [{role, content}]
  let ws = null;
  let currentBubble = null;

  function connect() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    ws = new WebSocket(`${proto}://${location.host}/`);
    ws.onopen = function () { fetchConfig(); };
    ws.onmessage = function (ev) { handleMessage(ev.data); };
    ws.onclose = function () {
      if (currentBubble) finalizeStream(null);
    };
  }

  function fetchConfig() {
    fetch("/config").then(r => r.json()).then(cfg => {
      modelBadge.textContent = cfg.model || "";
    }).catch(() => {});
  }

  function handleMessage(raw) {
    const msg = JSON.parse(raw);
    if (msg.type === "delta") {
      appendDelta(msg.text);
    } else if (msg.type === "done") {
      finalizeStream(msg.text);
    } else if (msg.type === "error") {
      if (currentBubble) {
        currentBubble.appendChild(errorEl(msg.message));
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

  function appendDelta(text) {
    if (!currentBubble) {
      currentBubble = newBubble();
    }
    const pre = currentBubble.querySelector("pre.raw");
    if (!pre) {
      currentBubble.appendChild(el("pre", "raw").appendChild(textNode(text)));
    } else {
      pre.textContent += text;
      messagesEl.scrollTop = messagesEl.scrollHeight;
    }
  }

  function finalizeStream(text) {
    if (currentBubble) {
      // Render markdown, replacing raw pre
      const content = text != null ? text : (currentBubble.querySelector("pre.raw") || {}).textContent || "";
      const pre = currentBubble.querySelector("pre.raw");
      if (pre) pre.remove();
      const rendered = renderMarkdown(content);
      rendered.forEach(n => currentBubble.insertBefore(n, currentBubble.querySelector(".actions")));
      messagesEl.scrollTop = messagesEl.scrollHeight;
      if (text != null && text.trim()) history.push({ role: "assistant", content: text.trim() });
    }
    currentBubble = null;
  }

  function newBubble() {
    const div = el("div", "msg assistant");
    const bubble = el("div", "bubble");
    bubble.appendChild(el("span", "typing").appendChild(textNode("Thinking...")));
    div.appendChild(bubble);
    messagesEl.appendChild(div);
    messagesEl.scrollTop = messagesEl.scrollHeight;
    return bubble;
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
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    history.push({ role: "user", content: text });
    inputEl.value = "";
    renderUserMessage(text);
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

  sendBtn.onclick = send;
  inputEl.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); send(); }
  });

  connect();
})();
