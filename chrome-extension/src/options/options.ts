/**
 * Ghost Extension Options Controller
 * Handles Gateway connection, default Provider & Model, API-Key Vault, and Session Management.
 */

import { GhostBrowserClient } from "../gateway/browserClient";

document.addEventListener("DOMContentLoaded", async () => {
  // Tabs
  const tabBtns = document.querySelectorAll(".tab-btn");
  const tabContents = document.querySelectorAll(".tab-content");

  // Status message
  const statusMsg = document.getElementById("statusMsg") as HTMLElement;

  // 1. Gateway Tab Elements
  const gatewayUrlInput = document.getElementById("gatewayUrl") as HTMLInputElement;
  const authTokenInput = document.getElementById("authToken") as HTMLInputElement;
  const autoConnectCheckbox = document.getElementById("autoConnect") as HTMLInputElement;
  const settingsForm = document.getElementById("settingsForm") as HTMLFormElement;
  const testBtn = document.getElementById("testBtn") as HTMLButtonElement;

  // 2. Model Tab Elements
  const defaultProviderSelect = document.getElementById("defaultProviderSelect") as HTMLSelectElement;
  const defaultModelSelect = document.getElementById("defaultModelSelect") as HTMLSelectElement;
  const saveModelBtn = document.getElementById("saveModelBtn") as HTMLButtonElement;

  // 3. API-Keys Tab Elements
  const apiKeyProviderSelect = document.getElementById("apiKeyProviderSelect") as HTMLSelectElement;
  const keyStatusBadge = document.getElementById("keyStatusBadge") as HTMLElement;
  const apiKeyLabel = document.getElementById("apiKeyLabel") as HTMLElement;
  const apiKeyValue = document.getElementById("apiKeyValue") as HTMLInputElement;
  const apiKeyHelpText = document.getElementById("apiKeyHelpText") as HTMLElement;
  const toggleKeyVisibilityBtn = document.getElementById("toggleKeyVisibilityBtn") as HTMLButtonElement;
  const saveKeyBtn = document.getElementById("saveKeyBtn") as HTMLButtonElement;
  const removeKeyBtn = document.getElementById("removeKeyBtn") as HTMLButtonElement;

  // 4. Sessions Tab Elements
  const deleteAllSessionsBtn = document.getElementById("deleteAllSessionsBtn") as HTMLButtonElement;
  const sessionsListContainer = document.getElementById("sessionsListContainer") as HTMLElement;

  let client: GhostBrowserClient | null = null;

  // --- Tab Navigation ---
  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      const tabId = btn.getAttribute("data-tab");
      if (!tabId) return;

      tabBtns.forEach((b) => b.classList.remove("active"));
      tabContents.forEach((c) => c.classList.remove("active"));

      btn.classList.add("active");
      const target = document.getElementById(tabId);
      if (target) target.classList.add("active");

      // Tab specific refresh
      if (tabId === "tab-model") {
        ensureConnected().then(() => loadModelTab());
      } else if (tabId === "tab-keys") {
        ensureConnected().then(() => loadKeyForSelectedProvider());
      } else if (tabId === "tab-sessions") {
        ensureConnected().then(() => loadSessionsTab());
      }
    });
  });

  // --- Initial Loading ---
  const stored = await chrome.storage.local.get({
    gatewayUrl: "ws://localhost:3000",
    authToken: "",
    autoConnect: true,
  });

  gatewayUrlInput.value = stored.gatewayUrl;
  authTokenInput.value = stored.authToken;
  autoConnectCheckbox.checked = stored.autoConnect;

  // Save Gateway settings
  settingsForm.addEventListener("submit", async (e) => {
    e.preventDefault();
    const url = gatewayUrlInput.value.trim() || "ws://localhost:3000";
    const token = authTokenInput.value.trim();
    const autoConnect = autoConnectCheckbox.checked;

    await chrome.storage.local.set({
      gatewayUrl: url,
      authToken: token,
      autoConnect,
    });

    showStatus("Gateway-Einstellungen gespeichert!", "success");
    if (client) {
      client.disconnect();
      client = null;
    }
  });

  // Test Gateway Connection
  testBtn.addEventListener("click", async () => {
    const url = gatewayUrlInput.value.trim() || "ws://localhost:3000";
    const token = authTokenInput.value.trim();

    testBtn.disabled = true;
    testBtn.textContent = "Teste...";
    showStatus("Verbindung wird getestet...", "success");

    const testClient = new GhostBrowserClient();
    try {
      const ok = await testClient.connect(url, token);
      if (ok) {
        showStatus(`Verbindung zu ${url} erfolgreich hergestellt! ✓`, "success");
      } else {
        showStatus(`Verbindung fehlgeschlagen. Läuft Ghost auf ${url}?`, "error");
      }
    } catch (err: any) {
      showStatus(`Fehler beim Verbinden: ${err.message}`, "error");
    } finally {
      testClient.disconnect();
      testBtn.disabled = false;
      testBtn.textContent = "Verbindung testen";
    }
  });

  // --- Helper: Ensure Client Connected ---
  async function ensureConnected(): Promise<GhostBrowserClient | null> {
    if (client && client.getState() === "connected") {
      return client;
    }

    const url = gatewayUrlInput.value.trim() || "ws://localhost:3000";
    const token = authTokenInput.value.trim();

    client = new GhostBrowserClient();
    try {
      const ok = await client.connect(url, token);
      if (ok) return client;
    } catch {
      showStatus("Nicht mit Gateway verbunden. Bitte Verbindung im ersten Tab prüfen.", "error");
    }
    return null;
  }

  // --- Tab 2: Provider & Model Management ---
  async function loadModelTab() {
    const c = await ensureConnected();
    if (!c) return;

    try {
      const config = await c.getConfig();
      if (config && config.agent) {
        if (config.agent.provider) {
          defaultProviderSelect.value = config.agent.provider;
        }
        await populateModelsForProvider(defaultProviderSelect.value, config.agent.model);
      }
    } catch (e: any) {
      showStatus(`Fehler beim Laden der Konfiguration: ${e.message}`, "error");
    }
  }

  defaultProviderSelect.addEventListener("change", async () => {
    await populateModelsForProvider(defaultProviderSelect.value);
  });

  async function populateModelsForProvider(provider: string, selectedModel?: string) {
    const c = await ensureConnected();
    if (!c) return;

    defaultModelSelect.innerHTML = `<option value="">(Lade Modelle...)</option>`;
    try {
      const models = await c.listModels(provider);
      defaultModelSelect.innerHTML = "";
      if (models && models.length > 0) {
        for (const m of models) {
          const opt = document.createElement("option");
          opt.value = m;
          opt.textContent = m;
          if (m === selectedModel) opt.selected = true;
          defaultModelSelect.appendChild(opt);
        }
        if (!defaultModelSelect.value && models.length > 0) {
          defaultModelSelect.value = models[0];
        }
      } else {
        const opt = document.createElement("option");
        opt.value = selectedModel || provider;
        opt.textContent = selectedModel || `Standard (${provider})`;
        opt.selected = true;
        defaultModelSelect.appendChild(opt);
      }
    } catch {
      defaultModelSelect.innerHTML = `<option value="${selectedModel || ''}">${selectedModel || 'Standard'}</option>`;
    }
  }

  saveModelBtn.addEventListener("click", async () => {
    const c = await ensureConnected();
    if (!c) return;

    const provider = defaultProviderSelect.value;
    const model = defaultModelSelect.value;
    if (!model) {
      showStatus("Bitte ein Modell auswählen.", "error");
      return;
    }

    try {
      saveModelBtn.disabled = true;
      await c.setModel(model, provider);
      showStatus(`Standard-Modell erfolgreich auf ${provider} / ${model} gesetzt! ✓`, "success");
    } catch (e: any) {
      showStatus(`Fehler beim Speichern des Modells: ${e.message}`, "error");
    } finally {
      saveModelBtn.disabled = false;
    }
  });

  // --- Tab 3: API-Key Management ---
  apiKeyProviderSelect.addEventListener("change", () => {
    loadKeyForSelectedProvider();
  });

  toggleKeyVisibilityBtn.addEventListener("click", () => {
    if (apiKeyValue.type === "password") {
      apiKeyValue.type = "text";
      toggleKeyVisibilityBtn.textContent = "🔒";
    } else {
      apiKeyValue.type = "password";
      toggleKeyVisibilityBtn.textContent = "👁️";
    }
  });

  async function loadKeyForSelectedProvider() {
    const c = await ensureConnected();
    if (!c) return;

    const provider = apiKeyProviderSelect.value;
    const isLocal = provider === "ollama" || provider === "lmstudio" || provider === "vllm";

    if (isLocal) {
      apiKeyLabel.textContent = "Base-URL";
      apiKeyValue.type = "text";
      apiKeyValue.placeholder = provider === "ollama"
        ? "http://localhost:11434/v1"
        : provider === "lmstudio"
        ? "http://localhost:1234/v1"
        : "http://localhost:8000/v1";
      apiKeyHelpText.textContent = "Gib die HTTP Base-URL deiner lokalen Model-Server-Instanz an.";
      toggleKeyVisibilityBtn.style.display = "none";
    } else {
      apiKeyLabel.textContent = "API-Key";
      apiKeyValue.type = "password";
      apiKeyValue.placeholder = "sk-... oder API-Token";
      apiKeyHelpText.textContent = "Key wird sicher im verschlüsselten Ghost Vault gespeichert.";
      toggleKeyVisibilityBtn.style.display = "block";
      toggleKeyVisibilityBtn.textContent = "👁️";
    }

    try {
      const key = await c.getKey(provider);
      apiKeyValue.value = key || "";
      if (key && key.trim().length > 0) {
        keyStatusBadge.className = "badge badge-success";
        keyStatusBadge.textContent = "Konfiguriert ✓";
      } else {
        keyStatusBadge.className = "badge badge-muted";
        keyStatusBadge.textContent = "Nicht hinterlegt";
      }
    } catch {
      keyStatusBadge.className = "badge badge-muted";
      keyStatusBadge.textContent = "Unbekannt";
    }
  }

  saveKeyBtn.addEventListener("click", async () => {
    const c = await ensureConnected();
    if (!c) return;

    const provider = apiKeyProviderSelect.value;
    const key = apiKeyValue.value.trim();

    try {
      saveKeyBtn.disabled = true;
      await c.setKey(provider, key);
      showStatus(`Schlüssel für ${provider} erfolgreich im Vault gespeichert! ✓`, "success");
      await loadKeyForSelectedProvider();
    } catch (e: any) {
      showStatus(`Fehler beim Speichern: ${e.message}`, "error");
    } finally {
      saveKeyBtn.disabled = false;
    }
  });

  removeKeyBtn.addEventListener("click", async () => {
    const c = await ensureConnected();
    if (!c) return;

    const provider = apiKeyProviderSelect.value;
    if (!confirm(`Möchtest du den API-Key für ${provider} wirklich aus dem Vault löschen?`)) {
      return;
    }

    try {
      removeKeyBtn.disabled = true;
      await c.setKey(provider, "");
      apiKeyValue.value = "";
      showStatus(`Schlüssel für ${provider} entfernt.`, "success");
      await loadKeyForSelectedProvider();
    } catch (e: any) {
      showStatus(`Fehler beim Löschen: ${e.message}`, "error");
    } finally {
      removeKeyBtn.disabled = false;
    }
  });

  // --- Tab 4: Session Management ---
  async function loadSessionsTab() {
    const c = await ensureConnected();
    if (!c) return;

    sessionsListContainer.innerHTML = `<p style="color:var(--text-secondary); font-size:12px;">Lade Sitzungen...</p>`;
    try {
      const sessions = await c.getSessions();
      if (!sessions || sessions.length === 0) {
        sessionsListContainer.innerHTML = `<p style="color:var(--text-secondary); font-size:12px;">Keine gespeicherten Sitzungen vorhanden.</p>`;
        return;
      }

      sessionsListContainer.innerHTML = "";
      for (const s of sessions) {
        const item = document.createElement("div");
        item.className = "session-item";

        const info = document.createElement("div");
        info.innerHTML = `<div class="session-title">${s.title || "Sitzung " + s.id.substring(0, 8)}</div>
                          <div class="session-meta">ID: ${s.id}</div>`;

        const delBtn = document.createElement("button");
        delBtn.className = "btn btn-danger-outline";
        delBtn.style.padding = "4px 8px";
        delBtn.style.fontSize = "11px";
        delBtn.textContent = "🗑️ Löschen";
        delBtn.addEventListener("click", async () => {
          if (confirm(`Sitzung "${s.title || s.id}" wirklich löschen?`)) {
            await c.deleteSession(s.id);
            await loadSessionsTab();
            showStatus(`Sitzung ${s.id} gelöscht.`, "success");
          }
        });

        item.appendChild(info);
        item.appendChild(delBtn);
        sessionsListContainer.appendChild(item);
      }
    } catch (e: any) {
      sessionsListContainer.innerHTML = `<p style="color:var(--danger); font-size:12px;">Fehler beim Laden der Sitzungen: ${e.message}</p>`;
    }
  }

  deleteAllSessionsBtn.addEventListener("click", async () => {
    const c = await ensureConnected();
    if (!c) return;

    if (!confirm("⚠️ ACHTUNG: Möchtest du wirklich ALLE gespeicherten Sitzungsverläufe unwiderruflich löschen?")) {
      return;
    }

    try {
      deleteAllSessionsBtn.disabled = true;
      await c.deleteAllSessions();
      showStatus("Alle Sitzungen wurden erfolgreich gelöscht! ✓", "success");
      await loadSessionsTab();
    } catch (e: any) {
      showStatus(`Fehler beim Löschen aller Sitzungen: ${e.message}`, "error");
    } finally {
      deleteAllSessionsBtn.disabled = false;
    }
  });

  function showStatus(text: string, type: "success" | "error"): void {
    statusMsg.textContent = text;
    statusMsg.className = `status-msg ${type}`;
    statusMsg.style.display = "block";
    setTimeout(() => {
      statusMsg.style.display = "none";
    }, 6000);
  }
});
