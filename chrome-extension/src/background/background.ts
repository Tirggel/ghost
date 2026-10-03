/**
 * Ghost Background Service Worker (Manifest V3)
 * Manages side panel behavior, context menus, and dispatching actions.
 */

// Lifecycle: setup side panel and context menus on install
chrome.runtime.onInstalled.addListener(async () => {
  try {
    // Enable opening the side panel on extension action icon click
    await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true });
  } catch (err) {
    console.error("[Ghost SW] Failed to set side panel behavior:", err);
  }

  // Set up context menus
  try {
    await chrome.contextMenus.removeAll();

    chrome.contextMenus.create({
      id: "ghost-explain",
      title: "👻 Ghost: Text / Code erklären",
      contexts: ["selection"],
    });

    chrome.contextMenus.create({
      id: "ghost-summarize",
      title: "👻 Ghost: Auswahl zusammenfassen",
      contexts: ["selection"],
    });

    chrome.contextMenus.create({
      id: "ghost-create-task",
      title: "👻 Ghost: Als Kanban-Task anlegen (/plan)",
      contexts: ["selection"],
    });

    chrome.contextMenus.create({
      id: "ghost-page-qa",
      title: "👻 Ghost: Diese Seite analysieren",
      contexts: ["page"],
    });
  } catch (err) {
    console.error("[Ghost SW] Failed to create context menus:", err);
  }
});

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (!tab || tab.windowId === undefined) return;

  const actionPayload = {
    action: String(info.menuItemId),
    selectedText: info.selectionText || "",
    pageUrl: tab.url || "",
    pageTitle: tab.title || "",
    timestamp: Date.now(),
  };

  try {
    // 1. Open the Side Panel in the active window
    await chrome.sidePanel.open({ windowId: tab.windowId });

    // 2. Persist in session storage so the sidepanel reads it immediately upon mounting
    await chrome.storage.session.set({ pendingAction: actionPayload });

    // 3. Send message to sidepanel if it's already mounted and listening
    try {
      await chrome.runtime.sendMessage({
        type: "GHOST_PENDING_ACTION",
        payload: actionPayload,
      });
    } catch {
      // Sidepanel might not have finished opening yet; it will read from storage.session
    }

    // 4. Brief badge feedback for the user
    await chrome.action.setBadgeText({ text: "👻" });
    setTimeout(async () => {
      await chrome.action.setBadgeText({ text: "" });
    }, 2000);
  } catch (err) {
    console.error("[Ghost SW] Error handling context menu click:", err);
  }
});
