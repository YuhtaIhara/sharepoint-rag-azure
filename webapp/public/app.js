(function () {
  const messagesEl = document.getElementById("messages");
  const form = document.getElementById("chat-form");
  const input = document.getElementById("chat-input");
  const sendBtn = document.getElementById("send-btn");

  let sessionId = localStorage.getItem("sprag_session_id") || crypto.randomUUID();
  localStorage.setItem("sprag_session_id", sessionId);

  function scrollToBottom() {
    const container = document.getElementById("chat-container");
    container.scrollTop = container.scrollHeight;
  }

  function addMessage(role, text) {
    const div = document.createElement("div");
    div.className = "message " + role;
    div.textContent = text;
    messagesEl.appendChild(div);
    scrollToBottom();
    return div;
  }

  function addAssistantMessage(answer, citations) {
    const div = document.createElement("div");
    div.className = "message assistant";

    const answerText = document.createElement("div");
    answerText.textContent = answer;
    div.appendChild(answerText);

    if (citations && citations.length > 0) {
      const details = document.createElement("details");
      details.className = "citations";

      const summary = document.createElement("summary");
      summary.textContent = "\u53C2\u7167\u5143 (" + citations.length + "\u4EF6)";
      details.appendChild(summary);

      const ul = document.createElement("ul");
      citations.forEach(function (c) {
        const li = document.createElement("li");
        if (c.url) {
          const a = document.createElement("a");
          a.href = c.url;
          a.target = "_blank";
          a.rel = "noopener noreferrer";
          a.textContent = c.title || c.url;
          li.appendChild(a);
        } else {
          li.textContent = c.title || JSON.stringify(c);
        }
        ul.appendChild(li);
      });
      details.appendChild(ul);
      div.appendChild(details);
    }

    messagesEl.appendChild(div);
    scrollToBottom();
  }

  function showLoading() {
    const div = document.createElement("div");
    div.className = "loading";
    div.id = "loading-indicator";
    div.innerHTML = '<div class="spinner"></div>\u56DE\u7B54\u3092\u751F\u6210\u4E2D...';
    messagesEl.appendChild(div);
    scrollToBottom();
  }

  function hideLoading() {
    const el = document.getElementById("loading-indicator");
    if (el) el.remove();
  }

  function setDisabled(disabled) {
    sendBtn.disabled = disabled;
    input.disabled = disabled;
  }

  async function sendMessage(text) {
    addMessage("user", text);
    showLoading();
    setDisabled(true);

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        credentials: "include",
        headers: {
          "Content-Type": "application/json",
          "X-Requested-With": "XMLHttpRequest",
        },
        body: JSON.stringify({ message: text, session_id: sessionId }),
      });

      // 認証切れ → ログインページにリダイレクト
      if (res.status === 401 || res.status === 302) {
        window.location.href = "/.auth/login/aad?post_login_redirect_uri=" + encodeURIComponent(window.location.pathname);
        return;
      }

      hideLoading();

      if (!res.ok) {
        addMessage("assistant", "\u30A8\u30E9\u30FC\u304C\u767A\u751F\u3057\u307E\u3057\u305F\u3002\u3057\u3070\u3089\u304F\u3057\u3066\u304B\u3089\u518D\u5EA6\u304A\u8A66\u3057\u304F\u3060\u3055\u3044\u3002");
        setDisabled(false);
        return;
      }

      const data = await res.json();

      if (data.session_id) {
        sessionId = data.session_id;
        localStorage.setItem("sprag_session_id", sessionId);
      }

      const answer =
        data.answer || "\u8A72\u5F53\u3059\u308B\u60C5\u5831\u304C\u898B\u3064\u304B\u308A\u307E\u305B\u3093\u3067\u3057\u305F";
      addAssistantMessage(answer, data.citations);
    } catch (err) {
      hideLoading();
      console.error(err);
      addMessage(
        "assistant",
        "\u901A\u4FE1\u30A8\u30E9\u30FC\u304C\u767A\u751F\u3057\u307E\u3057\u305F\u3002\u30CD\u30C3\u30C8\u30EF\u30FC\u30AF\u63A5\u7D9A\u3092\u78BA\u8A8D\u3057\u3066\u304F\u3060\u3055\u3044\u3002"
      );
    }

    setDisabled(false);
    input.focus();
  }

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    sendMessage(text);
  });

  document.getElementById("new-chat-btn").addEventListener("click", function () {
    sessionId = crypto.randomUUID();
    localStorage.setItem("sprag_session_id", sessionId);
    messagesEl.innerHTML = "";
    input.focus();
  });
})();
