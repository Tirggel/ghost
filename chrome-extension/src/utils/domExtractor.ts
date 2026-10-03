/**
 * Utility to extract clean text and context from web pages for Ghost AI prompts.
 */

export interface PageContext {
  url: string;
  title: string;
  selectedText?: string;
  pageContentSnippet?: string;
}

/**
 * Extracts visible text content from the current document, stripping scripts, styles, etc.
 */
export function extractPageContext(): PageContext {
  const selection = window.getSelection()?.toString().trim();
  const title = document.title || "";
  const url = window.location.href || "";

  // Helper to extract main article text if available, else body
  let text = "";
  const article = document.querySelector("article, main, [role='main'], #content, .content");
  const targetElement = article || document.body;

  if (targetElement) {
    const clone = targetElement.cloneNode(true) as HTMLElement;
    // Remove noise elements
    const unwanted = clone.querySelectorAll("script, style, noscript, svg, nav, footer, header, iframe");
    unwanted.forEach((el) => el.remove());

    text = (clone.innerText || clone.textContent || "")
      .replace(/\s+/g, " ")
      .trim();

    // Cap the text snippet to a reasonable length (e.g. ~4000 characters)
    if (text.length > 4000) {
      text = text.substring(0, 4000) + "... [gekürzt]";
    }
  }

  return {
    url,
    title,
    selectedText: selection || undefined,
    pageContentSnippet: text || undefined,
  };
}
