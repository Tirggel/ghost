/**
 * Ambient type definitions for Chrome Extension APIs used by Ghost.
 */
declare namespace chrome {
  namespace sidePanel {
    interface PanelBehavior {
      openPanelOnActionClick?: boolean;
    }
    interface OpenOptions {
      tabId?: number;
      windowId?: number;
    }
    function setPanelBehavior(behavior: PanelBehavior): Promise<void>;
    function open(options: OpenOptions): Promise<void>;
    function setOptions(options: { tabId?: number; path?: string; enabled?: boolean }): Promise<void>;
  }

  namespace contextMenus {
    type ContextType = "all" | "page" | "frame" | "selection" | "link" | "editable" | "image" | "video" | "audio" | "launcher" | "browser_action" | "page_action" | "action";
    interface CreateProperties {
      id?: string;
      title?: string;
      contexts?: ContextType[];
      parentId?: string | number;
      type?: "normal" | "checkbox" | "radio" | "separator";
    }
    interface OnClickData {
      menuItemId: string | number;
      parentMenuItemId?: string | number;
      selectionText?: string;
      pageUrl?: string;
      linkUrl?: string;
    }
    function create(createProperties: CreateProperties, callback?: () => void): string | number;
    function removeAll(): Promise<void>;
    const onClicked: {
      addListener(callback: (info: OnClickData, tab?: tabs.Tab) => void | Promise<void>): void;
    };
  }

  namespace tabs {
    interface Tab {
      id?: number;
      windowId?: number;
      url?: string;
      title?: string;
      active?: boolean;
    }
    interface QueryInfo {
      active?: boolean;
      currentWindow?: boolean;
      lastFocusedWindow?: boolean;
    }
    function query(queryInfo: QueryInfo): Promise<Tab[]>;
    function get(tabId: number): Promise<Tab>;
    function sendMessage<M = any, R = any>(tabId: number, message: M): Promise<R>;
    const onActivated: {
      addListener(callback: (activeInfo: { tabId: number; windowId: number }) => void): void;
    };
    const onUpdated: {
      addListener(callback: (tabId: number, changeInfo: { status?: string; url?: string }, tab: Tab) => void): void;
    };
  }

  namespace scripting {
    interface InjectionTarget {
      tabId: number;
      allFrames?: boolean;
      frameIds?: number[];
    }
    interface ScriptInjection<Args extends any[], Result> {
      target: InjectionTarget;
      func?: (...args: Args) => Result;
      args?: Args;
      files?: string[];
    }
    interface InjectionResult<Result> {
      result: Result;
      frameId: number;
    }
    function executeScript<Args extends any[], Result>(
      injection: ScriptInjection<Args, Result>
    ): Promise<InjectionResult<Result>[]>;
  }

  namespace storage {
    interface StorageArea {
      get(keys?: string | string[] | Record<string, any> | null): Promise<Record<string, any>>;
      set(items: Record<string, any>): Promise<void>;
      remove(keys: string | string[]): Promise<void>;
      clear(): Promise<void>;
    }
    const local: StorageArea;
    const session: StorageArea;
    const sync: StorageArea;
  }

  namespace action {
    function setBadgeText(details: { text: string; tabId?: number }): Promise<void>;
    function setBadgeBackgroundColor(details: { color: string | [number, number, number, number]; tabId?: number }): Promise<void>;
    function setIcon(details: { path?: string | Record<string, string>; tabId?: number }): Promise<void>;
    const onClicked: {
      addListener(callback: (tab: tabs.Tab) => void | Promise<void>): void;
    };
  }

  namespace runtime {
    interface MessageSender {
      tab?: tabs.Tab;
      frameId?: number;
      id?: string;
      url?: string;
    }
    interface InstalledDetails {
      reason: "install" | "update" | "chrome_update" | "shared_module_update";
      previousVersion?: string;
    }
    function getURL(path: string): string;
    function openOptionsPage(): Promise<void>;
    function sendMessage<M = any, R = any>(message: M): Promise<R>;
    const onInstalled: {
      addListener(callback: (details: InstalledDetails) => void | Promise<void>): void;
    };
    const onMessage: {
      addListener(callback: (message: any, sender: MessageSender, sendResponse: (response?: any) => void) => boolean | void): void;
    };
  }
}
