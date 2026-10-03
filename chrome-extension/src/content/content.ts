/**
 * Ghost Content Script
 * Runs in the context of web pages to extract selection, content, and page context.
 */

import { extractPageContext } from "../utils/domExtractor";

// Listen for messages from Side Panel or Service Worker
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message.type === "GHOST_GET_PAGE_CONTEXT") {
    const context = extractPageContext();
    sendResponse({ success: true, context });
    return false; // synchronous response
  }
  return false;
});
