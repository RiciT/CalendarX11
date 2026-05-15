//bridge to the ultralight api set up in zig - TODO

declare global {
  interface Window {
    __saveEvent?: (json: string) => void;
    __exitApp?: () => void;
  }
}

export function callSave(json: string): boolean {
  if (typeof window.__saveEvent === "function") {
    window.__saveEvent(json);
    return true;
  }
  //fallback - trigger a download
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  const date = (JSON.parse(json) as { date: string }).date ?? "event";
  a.download = `event-${date}.json`;
  a.click();
  URL.revokeObjectURL(url);
  return false; //native not available
}

export function callExit(): boolean {
  if (typeof window.__exitApp === "function") {
    window.__exitApp();
    return true;
  }
  return false;
}
