import type { Command } from "commander";
import { registerDiscover } from "./discover.js";
import { registerDevices } from "./devices.js";
import { registerPing } from "./ping.js";
import { registerNavigate } from "./navigate.js";
import { registerScreenshot } from "./screenshot.js";
import { registerDOM } from "./dom.js";
import { registerInteraction } from "./interaction.js";
import { registerScroll } from "./scroll.js";
import { registerWait } from "./wait.js";
import { registerDeviceInfo } from "./device-info.js";
import { registerEval } from "./eval.js";
import { registerConsole } from "./console.js";
import { registerNetwork } from "./network.js";
import { registerMutations } from "./mutations.js";
import { registerIntercept } from "./intercept.js";
import { registerShadowDOM } from "./shadow-dom.js";
import { registerDialog } from "./dialog.js";
import { registerTabs } from "./tabs.js";
import { registerIframes } from "./iframes.js";
import { registerCookies } from "./cookies.js";
import { registerStorage } from "./storage.js";
import { registerClipboard } from "./clipboard.js";
import { registerGeo } from "./geo.js";
import { registerKeyboard } from "./keyboard.js";
import { registerA11y } from "./a11y.js";
import { registerAnnotate } from "./annotate.js";
import { registerVisible } from "./visible.js";
import { registerPageText } from "./page-text.js";
import { registerFormState } from "./form-state.js";
import { registerFind } from "./find.js";
import { registerGroup } from "./group.js";
import { registerMcp } from "./mcp.js";
import { registerExplain } from "./explain.js";
import { registerHome } from "./home.js";
import { registerBrowser } from "./browser.js";
import { registerAI } from "./ai.js";
import { registerScript } from "./script.js";

export function registerAllCommands(program: Command): void {
  // Discovery
  registerDiscover(program);
  registerDevices(program);
  registerPing(program);
  registerBrowser(program);

  // Core: Navigation
  registerNavigate(program);
  registerHome(program);
  registerScreenshot(program);
  registerDOM(program);

  // Interaction + Scroll + Wait
  registerInteraction(program);
  registerScript(program);
  registerScroll(program);
  registerWait(program);
  registerDeviceInfo(program);
  registerEval(program);

  // DevTools
  registerConsole(program);
  registerNetwork(program);
  registerMutations(program);
  registerIntercept(program);
  registerShadowDOM(program);

  // Browser Management
  registerDialog(program);
  registerTabs(program);
  registerIframes(program);
  registerCookies(program);
  registerStorage(program);
  registerClipboard(program);
  registerGeo(program);
  registerKeyboard(program);

  // LLM-Optimized
  registerA11y(program);
  registerAnnotate(program);
  registerVisible(program);
  registerPageText(program);
  registerFormState(program);
  registerFind(program);

  // Group Commands
  registerGroup(program);

  // MCP Server
  registerMcp(program);

  // AI
  registerAI(program);

  // Help
  registerExplain(program);
}
