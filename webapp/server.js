const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 8080;

const FUNCTIONS_BASE =
  process.env.BACKEND_API_URL ||
  "https://func-sprag-poc-jpe-xxxxxxxxxx.japaneast-01.azurewebsites.net";
const FUNCTIONS_KEY = process.env.FUNCTIONS_KEY || "";
const FUNCTIONS_ENDPOINT = `${FUNCTIONS_BASE}/api/chat${FUNCTIONS_KEY ? "?code=" + FUNCTIONS_KEY : ""}`;

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

async function callFunctions(payload, retries = 2) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 60000); // 60秒タイムアウト

      const response = await fetch(FUNCTIONS_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
      clearTimeout(timeout);

      if (response.status === 500 && attempt < retries) {
        console.log(`Attempt ${attempt + 1} got 500, retrying...`);
        await new Promise((r) => setTimeout(r, 2000));
        continue;
      }

      return response;
    } catch (err) {
      if (attempt < retries && (err.name === "AbortError" || err.cause?.code === "ECONNRESET")) {
        console.log(`Attempt ${attempt + 1} failed (${err.message}), retrying...`);
        await new Promise((r) => setTimeout(r, 3000));
        continue;
      }
      throw err;
    }
  }
}

app.post("/api/chat", async (req, res) => {
  const userEmail =
    (req.headers["x-ms-client-principal-name"] || "anonymous@local").toLowerCase();
  const userId = req.headers["x-ms-client-principal-id"] || "anonymous";

  const { message, session_id } = req.body;

  if (!message) {
    return res.status(400).json({ error: "message is required" });
  }

  const payload = {
    message,
    session_id: session_id || "",
    user_id: userEmail,
    user_groups: [userEmail],
  };

  try {
    const response = await callFunctions(payload);

    if (!response.ok) {
      const text = await response.text();
      console.error(`Functions backend error: ${response.status} ${text}`);
      return res
        .status(response.status)
        .json({ error: "Backend error", detail: text });
    }

    const data = await response.json();
    res.json(data);
  } catch (err) {
    console.error("Proxy error:", err, err.cause);
    res.status(502).json({
      error: "Failed to reach backend",
      detail: err.message,
      cause: err.cause ? err.cause.message : "unknown",
    });
  }
});

app.listen(PORT, () => {
  console.log(`Server listening on port ${PORT}`);
  console.log(`Backend: ${FUNCTIONS_ENDPOINT.replace(/code=.*/, "code=***")}`);
});
